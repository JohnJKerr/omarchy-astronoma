"""Persisted update records.

One JSON file per captured update under ~/.local/state/omarchy-updates/,
holding enough structure to render that update later without the original
log — which matters because the log it came from lives in /tmp and is gone
after a reboot.
"""

import json
import re
from datetime import datetime

from . import paths

SCHEMA = 1
_ID = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{4}$")


def valid_id(identifier: str) -> bool:
    return _ID.fullmatch(str(identifier or "")) is not None


def record_id(when: datetime) -> str:
    """Sorts chronologically as a plain string, and stays readable."""
    return when.strftime("%Y-%m-%d-%H%M")


def _path_for(identifier: str):
    return paths.state_dir() / f"{identifier}.json"


def save(record: dict) -> None:
    identifier = str(record.get("id") or "")
    if not valid_id(identifier):
        raise ValueError(f"refusing to write record with invalid id: {identifier!r}")
    target = _path_for(identifier)
    paths.atomic_json_write(target, record, private=True)


def load(identifier: str) -> dict | None:
    if not valid_id(identifier):
        return None
    try:
        data = json.loads(_path_for(identifier).read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def all_records() -> list[dict]:
    """Every captured update, newest first. Unreadable files are skipped."""
    directory = paths.state_dir()
    try:
        files = sorted(directory.glob("*.json"), reverse=True)
    except OSError:
        return []
    records = []
    for file in files:
        if not _ID.match(file.stem):
            continue
        try:
            data = json.loads(file.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            records.append(data)
    records.sort(key=lambda r: str(r.get("id") or ""), reverse=True)
    return records


def latest() -> dict | None:
    records = all_records()
    return records[0] if records else None


def digests() -> set[str]:
    """Transcript digests already captured, so no run is recorded twice."""
    found = set()
    for record in all_records():
        digest = (record.get("sources") or {}).get("logDigest")
        if digest:
            found.add(str(digest))
    return found


def _seen_path():
    return paths.state_dir() / "seen.json"


def seen_id() -> str | None:
    """The most recent update the user has actually opened."""
    try:
        data = json.loads(_seen_path().read_text())
    except (OSError, ValueError):
        return None
    value = data.get("id") if isinstance(data, dict) else None
    return str(value) if value else None


def mark_seen(identifier: str) -> str | None:
    """Record an update as read, so the bar stops asking for attention.

    Only ever moves forward: opening an old update from the history list
    must not re-flag the newest one as unread.
    """
    if not _ID.match(str(identifier or "")):
        return seen_id()
    current = seen_id()
    if current and current >= identifier:
        return current
    target = _seen_path()
    paths.atomic_json_write(target, {"id": identifier}, private=True)
    return identifier


def unread_id() -> str | None:
    """The newest captured update the user has not opened yet, if any."""
    records = all_records()
    if not records:
        return None
    newest = str(records[0].get("id") or "")
    seen = seen_id()
    return newest if (not seen or newest > seen) else None


def summary_row(record: dict) -> dict:
    """The compact shape the history list renders, without the payload."""
    packages = record.get("packages") or {}
    omarchy = record.get("omarchy") or {}
    counts = {
        key: len(packages.get(key) or [])
        for key in ("upgraded", "installed", "removed")
    }
    return {
        "id": record.get("id"),
        "at": record.get("startedAt"),
        "omarchy": omarchy,
        "counts": counts,
        "packageTotal": sum(counts.values()),
        "migrations": len(record.get("migrations") or []),
        "errors": len(record.get("errors") or []),
        "warnings": len(record.get("warnings") or []),
        "partial": bool(record.get("partial")),
    }
