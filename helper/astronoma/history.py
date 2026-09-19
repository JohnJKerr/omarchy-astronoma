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
MAX_RECORD_BYTES = 2 * 1024 * 1024
MAX_RECORDS = 4096
MAX_HISTORY_BYTES = 32 * 1024 * 1024


def valid_id(identifier: str) -> bool:
    return _ID.fullmatch(str(identifier or "")) is not None


def record_id(when: datetime) -> str:
    """Sorts chronologically as a plain string, and stays readable."""
    return when.strftime("%Y-%m-%d-%H%M")


def _path_for(identifier: str):
    return paths.state_dir() / f"{identifier}.json"


def save(record: dict) -> None:
    save_all([record])


def save_all(records: list[dict]) -> None:
    """Validate a whole capture batch before replacing any stored record."""
    prepared = []
    for record in records:
        identifier = str(record.get("id") or "")
        if not valid_id(identifier):
            raise ValueError(f"refusing to write record with invalid id: {identifier!r}")
        if not _valid_record(record, identifier):
            raise ValueError(f"refusing to write invalid record: {identifier}")
        encoded = (json.dumps(record, indent=2) + "\n").encode("utf-8")
        if len(encoded) > MAX_RECORD_BYTES:
            raise ValueError(f"record {identifier} exceeds the byte limit")
        prepared.append((_path_for(identifier), encoded))
    for target, encoded in prepared:
        paths.atomic_bytes_write(target, encoded, private=True)

def load(identifier: str) -> dict | None:
    if not valid_id(identifier):
        return None
    try:
        data = paths.read_json(_path_for(identifier), MAX_RECORD_BYTES)
    except (OSError, ValueError):
        return None
    return data if _valid_record(data, identifier) else None


def all_records() -> list[dict]:
    records, _truncated = all_records_with_status()
    return records


def all_records_with_status() -> tuple[list[dict], bool]:
    """Every captured update, newest first. Unreadable files are skipped."""
    directory = paths.state_dir()
    try:
        files = sorted(paths.list_regular(directory, MAX_RECORDS), reverse=True)
    except ValueError:
        return [], True
    except OSError:
        return [], False
    records, remaining, truncated = [], MAX_HISTORY_BYTES, False
    for name in files:
        file = directory / name
        if not name.endswith(".json") or not valid_id(name[:-5]):
            continue
        if remaining <= 0:
            truncated = True
            break
        try:
            limit = min(MAX_RECORD_BYTES, remaining)
            data, size = paths.read_json_with_size(file, limit)
        except (OSError, ValueError):
            if remaining < MAX_RECORD_BYTES:
                truncated = True
                break
            continue
        remaining -= size
        if _valid_record(data, name[:-5]):
            records.append(data)
    records.sort(key=lambda r: str(r.get("id") or ""), reverse=True)
    return records, truncated


def latest() -> dict | None:
    records = all_records()
    return records[0] if records else None


def any_records() -> bool:
    """Whether anything has ever been captured, without parsing it.

    The capture short-circuit only needs to know that history is not empty,
    and reading every record to answer that is the expensive way to ask.
    """
    try:
        return any(name.endswith(".json") and valid_id(name[:-5])
                   for name in paths.list_regular(paths.state_dir(), MAX_RECORDS))
    except (OSError, ValueError):
        return False


def reset_captured() -> int:
    """Remove captured records and read/capture markers, ready for reconstruction."""
    try:
        # Early versions did not make every state leaf private. Repair
        # user-owned regular files before the trusted listing so upgrades can
        # reset them too; symlinks and foreign-owned entries remain excluded.
        paths.harden_private_tree(paths.state_dir(), MAX_RECORDS + 8)
        names = paths.list_regular(paths.state_dir(), MAX_RECORDS + 8)
    except FileNotFoundError:
        return 0
    record_names = [name for name in names
                    if name.endswith(".json") and valid_id(name[:-5])]
    for name in record_names:
        paths.unlink_private(paths.state_dir() / name)
    paths.unlink_private(_seen_path())
    paths.unlink_private(paths.state_dir() / ".capture-sources.json")
    return len(record_names)


def _seen_path():
    return paths.state_dir() / "seen.json"


def seen_id() -> str | None:
    """The most recent update the user has actually opened."""
    try:
        data = paths.read_json(_seen_path(), 1024)
    except (OSError, ValueError):
        return None
    value = data.get("id") if isinstance(data, dict) and set(data) == {"id"} else None
    return str(value) if valid_id(value) else None


def _valid_record(data, identifier: str) -> bool:
    if not (isinstance(data, dict) and data.get("schema") == SCHEMA
            and data.get("id") == identifier and set(data) == {
                "schema", "id", "startedAt", "finishedAt", "omarchy", "packages",
                "aur", "migrations", "warnings", "errors", "failed", "aurSkipped",
                "partial", "sources",
            }):
        return False

    def text(value, limit=1024, optional=False):
        return (optional and value is None) or isinstance(value, str) and len(value) <= limit

    def change(value, expected_action=None):
        return (isinstance(value, dict) and set(value) <= {"name", "action", "from", "to", "aur"}
                and text(value.get("name")) and text(value.get("action"), 32)
                and value.get("action") in ("upgraded", "installed", "removed")
                and (expected_action is None or value.get("action") == expected_action)
                and text(value.get("from"), optional=True) and text(value.get("to"), optional=True)
                and ("aur" not in value or isinstance(value["aur"], bool)))

    def changes(value, expected_action=None):
        return (isinstance(value, list) and len(value) <= 5000
                and all(change(item, expected_action) for item in value))

    omarchy, packages, sources = data["omarchy"], data["packages"], data["sources"]
    strings = (data["migrations"], data["warnings"], data["errors"])
    return (text(data["startedAt"]) and text(data["finishedAt"])
            and isinstance(omarchy, dict) and set(omarchy) == {"from", "to", "changed"}
            and text(omarchy["from"], optional=True) and text(omarchy["to"], optional=True)
            and isinstance(omarchy["changed"], bool)
            and isinstance(packages, dict) and set(packages) == {"upgraded", "installed", "removed"}
            and all(changes(packages[key], key) for key in packages)
            and changes(data["aur"])
            and all(isinstance(items, list) and len(items) <= 1000
                    and all(text(item, 65536) for item in items) for items in strings)
            and all(isinstance(data[key], bool) for key in ("failed", "aurSkipped", "partial"))
            and isinstance(sources, dict) and set(sources) == {"pacmanLog", "updateLog", "logDigest"}
            and isinstance(sources["pacmanLog"], bool) and isinstance(sources["updateLog"], bool)
            and text(sources["logDigest"], 64, optional=True)
            and (sources["logDigest"] is None
                 or re.fullmatch(r"[0-9a-f]{64}", sources["logDigest"]) is not None))


def mark_seen(identifier: str) -> str | None:
    """Record an update as read, so the bar stops asking for attention.

    Only ever moves forward: opening an old update from the history list
    must not re-flag the newest one as unread.
    """
    if not valid_id(identifier):
        return seen_id()
    current = seen_id()
    if current and current >= identifier:
        return current
    target = _seen_path()
    paths.atomic_json_write(target, {"id": identifier}, private=True)
    return identifier


def unread_in(records: list[dict]) -> str | None:
    """The newest of `records` the user has not opened yet, if any.

    Takes the list so a caller that already has it does not pay to read and
    parse every record file a second time.
    """
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
