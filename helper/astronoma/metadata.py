"""Read bounded, display-safe metadata from the plugin manifest."""

import json
import os
import stat
from pathlib import Path

from . import paths


MAX_MANIFEST_BYTES = 16 * 1024
MAX_VERSION_CHARS = 32


def _read_version(manifest: Path) -> str:
    """Return a validated version from one bounded, non-symlink manifest."""
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        descriptor = os.open(manifest, flags)
        try:
            info = os.fstat(descriptor)
            if (not stat.S_ISREG(info.st_mode)
                    or info.st_uid not in (0, os.geteuid())
                    or info.st_size > MAX_MANIFEST_BYTES):
                return ""
            raw = paths.read_descriptor(descriptor, MAX_MANIFEST_BYTES)
        finally:
            os.close(descriptor)
        payload = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeError, ValueError):
        return ""

    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1:
        return ""
    value = payload.get("version")
    if not isinstance(value, str) or not value or len(value) > MAX_VERSION_CHARS:
        return ""
    return value


def version() -> str:
    """Return the adjacent plugin manifest version, or empty on failure."""
    return _read_version(Path(__file__).parents[2] / "manifest.json")
