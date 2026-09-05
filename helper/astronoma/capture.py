"""Turn the machine's logs into persisted update records.

Two sources are combined. pacman.log says exactly which packages changed
and when, and it survives reboots, so it decides where one update starts
and the next begins. The /tmp transcript is the only place migrations,
warnings and errors are recorded, so it is layered onto the most recent
session — the run that produced it.

Sessions older than the transcript are still captured, from pacman.log
alone, and marked `partial`. That backfill is what lets a machine show a
useful history the first time Astronoma ever runs.
"""

import os
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path

from . import history, pacmanlog, paths, updatelog, versions

MAX_MIGRATION_MARKERS = 4096


def _migration_markers() -> list[tuple[str, datetime]]:
    directory = paths.migrations_state_dir()
    try:
        entries = paths.owned_regular_metadata(directory, MAX_MIGRATION_MARKERS)
    except FileNotFoundError:
        return []
    return [
        (Path(name).stem, datetime.fromtimestamp(info.st_mtime).astimezone())
        for name, info in entries
    ]


def _migrations_between(markers: list[tuple[str, datetime]],
                        start: datetime, end: datetime) -> list[str]:
    """Migration markers Omarchy touched inside this update's window.

    The marker's mtime is the only record that a migration ran at a
    particular time, and it is what makes migrations recoverable for
    updates whose transcript is long gone.
    """
    window_start = start - timedelta(minutes=5)
    window_end = end + timedelta(minutes=30)
    found = [name for name, touched in markers if window_start <= touched <= window_end]
    return sorted(found)


def _is_update(session: pacmanlog.Session) -> bool:
    """Whether a cluster of package activity counts as an Omarchy update.

    A one-off `pacman -S somepackage` is not an update and would only
    clutter the history; a full system upgrade is, and so is anything that
    moved the Omarchy package itself.
    """
    if session.is_system_upgrade():
        return True
    return session.omarchy_delta() != (None, None)


def _record_from(session: pacmanlog.Session, log: updatelog.UpdateLog | None,
                 migration_markers: list[tuple[str, datetime]]) -> dict:
    from_version, to_version = session.omarchy_delta()
    migrations = _migrations_between(migration_markers, session.started, session.finished)
    if log and log.migrations:
        # The transcript names exactly what ran; prefer it over mtimes.
        migrations = sorted(set(migrations) | set(log.migrations))

    aur = [c.as_dict() for c in session.changes if c.aur]
    record = {
        "schema": history.SCHEMA,
        "id": history.record_id(session.started),
        "startedAt": session.started.isoformat(),
        "finishedAt": session.finished.isoformat(),
        "omarchy": {
            "from": versions.strip_pkgrel(from_version) if from_version else None,
            "to": versions.strip_pkgrel(to_version) if to_version else None,
            "changed": bool(to_version and from_version != to_version),
        },
        "packages": {
            "upgraded": [c.as_dict() for c in session.upgraded],
            "installed": [c.as_dict() for c in session.installed],
            "removed": [c.as_dict() for c in session.removed],
        },
        "aur": aur,
        "migrations": migrations,
        "warnings": list(log.warnings) if log else [],
        "errors": list(log.errors) if log else [],
        "failed": bool(log.failed) if log else False,
        "aurSkipped": bool(log.aur_skipped) if log else False,
        # `partial` means package data only: no transcript was available for
        # this update, so migrations are inferred and errors are unknown.
        "partial": log is None,
        "sources": {
            "pacmanLog": True,
            "updateLog": log is not None,
            "logDigest": log.digest if log else None,
        },
    }
    return record


def _log_matches(session: pacmanlog.Session, log: updatelog.UpdateLog) -> bool:
    """Whether the transcript describes this session.

    The transcript carries no timestamps of its own, but the file's mtime
    is effectively when the update finished, which dates it precisely
    against pacman.log. Name overlap is only consulted when the mtime is
    unavailable, since a transcript that names none of the packages a
    session moved is describing some other run.
    """
    if log.modified is not None:
        window_start = session.started - timedelta(minutes=5)
        window_end = session.finished + timedelta(hours=2)
        return window_start <= log.modified <= window_end

    named = set(log.upgraded) | set(log.installed) | set(log.removed)
    if not named:
        return True
    return bool(named & {c.name for c in session.changes})


@contextmanager
def _capture_lock():
    paths.harden_private_tree(paths.state_dir(), history.MAX_RECORDS + 8)
    with paths.private_lock(paths.state_dir() / ".capture.lock"):
        yield


def _source_signature() -> dict:
    signature = {}
    sources = (
        ("pacman", paths.pacman_log(), (0, os.geteuid())),
        ("update", paths.update_log(), (os.geteuid(),)),
    )
    for name, source, owners in sources:
        try:
            signature[name] = paths.trusted_leaf_identity(source, owners)
        except OSError:
            # Distinct from a missing leaf, so an unsafe replacement cannot
            # hit the unchanged fast path and hide its rejection.
            signature[name] = "unsafe"
    return signature


def run_if_changed() -> dict:
    """Skip the expensive full-log pass when neither input changed."""
    stamp = paths.state_dir() / ".capture-sources.json"
    signature = _source_signature()
    try:
        previous = paths.read_json(stamp, 4096)
    except (OSError, ValueError):
        previous = None
    if previous == signature and history.any_records():
        return {"captured": [], "skipped": [], "unchanged": True}
    result = run(include_source_signatures=True)
    consumed_signature = result.pop("sourceSignatures", None)
    if not result.get("error") and not result.get("warning"):
        paths.atomic_json_write(stamp, consumed_signature, private=True)
    return result


def run(force: bool = False, include_source_signatures: bool = False) -> dict:
    """Capture every update the machine can still evidence.

    Returns a report of what was written, so the caller can tell the
    difference between "nothing to do" and "nothing readable".
    """
    with _capture_lock():
        result = _run_locked(force)
    if not include_source_signatures:
        result.pop("sourceSignatures", None)
    return result


def _run_locked(force: bool = False) -> dict:
    try:
        all_sessions, pacman_signature = pacmanlog.sessions_with_identity()
        sessions = [s for s in all_sessions if _is_update(s)]
    except pacmanlog.PacmanLogError as error:
        return {
            "captured": [], "skipped": [], "sessions": 0,
            "updateLogPresent": False, "updateLogAttached": False,
            "error": str(error),
        }
    log = updatelog.load()
    migration_warning = str(log.error or "")
    try:
        migration_markers = _migration_markers()
    except (OSError, ValueError) as error:
        migration_markers = []
        migration_warning = f"Migration history was not read safely: {error}"
    records = history.all_records()
    known = set() if force else {
        str(digest) for record in records
        if (digest := (record.get("sources") or {}).get("logDigest"))
    }
    existing_records = {r.get("id"): r for r in records}
    existing = set(existing_records)

    # Attach the transcript to the update it actually dates to. Searching
    # newest first means an ambiguous match lands on the most recent run,
    # which is the one a /tmp file is overwhelmingly likely to describe.
    owner = None
    if log.present:
        for session in reversed(sessions):
            if _log_matches(session, log):
                owner = session
                break

    captured, skipped, pending = [], [], []
    for session in sessions:
        attached = log if session is owner else None
        identifier = history.record_id(session.started)

        if identifier in existing and not force:
            # An update may still be running at first capture. Re-record
            # when package activity grows or new transcript evidence arrives.
            previous = existing_records[identifier]
            packages = {
                "upgraded": [c.as_dict() for c in session.upgraded],
                "installed": [c.as_dict() for c in session.installed],
                "removed": [c.as_dict() for c in session.removed],
            }
            packages_unchanged = (previous.get("packages") == packages
                                  and previous.get("finishedAt") == session.finished.isoformat())
            if packages_unchanged and (not attached or (attached.digest and attached.digest in known)):
                skipped.append(identifier)
                continue

        rebuilt = _record_from(session, attached, migration_markers)
        previous = existing_records.get(identifier)
        if previous and not attached and not previous.get("partial", True):
            # Package history is reproducible, but a vanished transcript is
            # not. Never erase evidence retained by an earlier capture.
            for key in ("migrations", "warnings", "errors", "failed", "aurSkipped", "partial"):
                rebuilt[key] = previous.get(key)
            rebuilt["sources"] = previous.get("sources", rebuilt["sources"])
        pending.append(rebuilt)
        captured.append(identifier)

    result = {
        "captured": captured,
        "skipped": skipped,
        "sessions": len(sessions),
        "updateLogPresent": log.present,
        "updateLogAttached": owner is not None,
        "sourceSignatures": {
            "pacman": pacman_signature,
            "update": log.source_signature,
        },
    }
    if migration_warning:
        result["warning"] = migration_warning[:200]
    try:
        history.save_all(pending)
    except ValueError as error:
        result["captured"] = []
        result["error"] = f"Captured update exceeded storage limits: {error}"[:200]
    return result
