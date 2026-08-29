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

import fcntl
import json
import os
from contextlib import contextmanager
from datetime import datetime, timedelta

from . import history, pacmanlog, paths, updatelog, versions


def _migrations_between(start: datetime, end: datetime) -> list[str]:
    """Migration markers Omarchy touched inside this update's window.

    The marker's mtime is the only record that a migration ran at a
    particular time, and it is what makes migrations recoverable for
    updates whose transcript is long gone.
    """
    directory = paths.migrations_state_dir()
    try:
        entries = list(directory.iterdir())
    except OSError:
        return []
    window_start = start - timedelta(minutes=5)
    window_end = end + timedelta(minutes=30)
    found = []
    for entry in entries:
        try:
            touched = datetime.fromtimestamp(entry.stat().st_mtime).astimezone()
        except OSError:
            continue
        if window_start <= touched <= window_end:
            found.append(entry.stem)
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


def _record_from(session: pacmanlog.Session, log: updatelog.UpdateLog | None) -> dict:
    from_version, to_version = session.omarchy_delta()
    migrations = _migrations_between(session.started, session.finished)
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
    directory = paths.state_dir()
    paths.private_directory(directory)
    with (directory / ".capture.lock").open("a+") as handle:
        os.fchmod(handle.fileno(), 0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def _source_signature() -> dict:
    signature = {}
    for name, source in (("pacman", paths.pacman_log()), ("update", paths.update_log())):
        try:
            stat = source.stat()
            signature[name] = [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns]
        except OSError:
            signature[name] = None
    return signature


def run_if_changed() -> dict:
    """Skip the expensive full-log pass when neither input changed."""
    stamp = paths.state_dir() / ".capture-sources.json"
    signature = _source_signature()
    try:
        previous = json.loads(stamp.read_text())
    except (OSError, ValueError):
        previous = None
    if previous == signature and history.latest() is not None:
        return {"captured": [], "skipped": [], "unchanged": True}
    result = run()
    paths.atomic_json_write(stamp, signature, private=True)
    return result


def run(force: bool = False) -> dict:
    """Capture every update the machine can still evidence.

    Returns a report of what was written, so the caller can tell the
    difference between "nothing to do" and "nothing readable".
    """
    with _capture_lock():
        return _run_locked(force)


def _run_locked(force: bool = False) -> dict:
    sessions = [s for s in pacmanlog.sessions() if _is_update(s)]
    log = updatelog.load()
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

    captured, skipped = [], []
    for session in sessions:
        attached = log if session is owner else None
        identifier = history.record_id(session.started)

        if identifier in existing and not force:
            # Re-record only when this run brings a transcript we have not
            # already folded into the stored record.
            if not attached or (attached.digest and attached.digest in known):
                skipped.append(identifier)
                continue

        rebuilt = _record_from(session, attached)
        previous = existing_records.get(identifier)
        if previous and not attached and not previous.get("partial", True):
            # Package history is reproducible, but a vanished transcript is
            # not. Never erase evidence retained by an earlier capture.
            for key in ("migrations", "warnings", "errors", "failed", "aurSkipped", "partial"):
                rebuilt[key] = previous.get(key)
            rebuilt["sources"] = previous.get("sources", rebuilt["sources"])
        history.save(rebuilt)
        captured.append(identifier)

    return {
        "captured": captured,
        "skipped": skipped,
        "sessions": len(sessions),
        "updateLogPresent": log.present,
        "updateLogAttached": owner is not None,
    }
