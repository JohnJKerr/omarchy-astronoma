"""Parse Omarchy's /tmp/omarchy-update.log.

`omarchy-update` re-execs itself under `script -qefc`, so this file is a
terminal transcript, not a clean log: SGR colour codes, carriage-return
progress redraws, and occasional OSC sequences all land in it verbatim.
Everything here works on de-escaped text.

pacman.log already records packages exactly, so this parser deliberately
concentrates on what only the transcript knows — which migrations ran,
what Omarchy printed in red, and how the run ended. Package lines are
read too, but only as a fallback for machines whose pacman.log is
unreadable.
"""

import os
import re
import stat
from dataclasses import dataclass, field

from . import paths

# CSI / OSC escape sequences emitted by colourised output and progress bars.
_ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][B0]")
_MIGRATION = re.compile(r"^Running migration \((?P<name>[^)]+)\)\s*$")
_UPGRADING = re.compile(r"^upgrading (?P<name>\S+)\.\.\.\s*$")
_INSTALLING = re.compile(r"^installing (?P<name>\S+)\.\.\.\s*$")
_REMOVING = re.compile(r"^removing (?P<name>\S+)\.\.\.\s*$")
_SECTION = re.compile(
    r"^(Update system packages|Update AUR packages|Update firmware"
    r"|Update mise|Remove orphan packages|Update keyring)\s*$"
)
MAX_LOG_BYTES = 32 * 1024 * 1024
MAX_LINE_CHARS = 65536
MAX_MIGRATIONS = 1000
MAX_MESSAGES = 1000
MAX_PACKAGES_PER_ACTION = 5000
MAX_NAME_CHARS = 1024

_ERROR_HINTS = (
    "error:", "error!", "failed to", "failure", "cannot ", "unable to",
    "something went wrong", "no space left",
)
_WARNING_HINTS = ("warning:", "warn:", "skipping", "is unavailable")

# Noise that matches the hint lists but says nothing a reader would act on.
_IGNORE = (
    "error: target not found: ",          # probed optional package
    "warning: config file /etc/pacman.conf",
)


def strip_ansi(text: str) -> str:
    """Flatten a terminal transcript to the text a human would have seen.

    Progress bars redraw with carriage returns; only the final paint of
    each line survives, which is what the reader actually ended up with.
    """
    without_escapes = _ANSI.sub("", text)
    lines = []
    for raw in without_escapes.replace("\r\n", "\n").split("\n"):
        lines.append(raw.split("\r")[-1] if "\r" in raw else raw)
    return "\n".join(lines)


@dataclass
class UpdateLog:
    present: bool = False
    migrations: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    upgraded: list[str] = field(default_factory=list)
    installed: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    aur_skipped: bool = False
    failed: bool = False
    digest: str | None = None
    # When the transcript was last written — effectively when the update
    # finished. This is what dates a run that carries no timestamps.
    modified: object | None = None
    source_signature: list[int] | None = None
    error: str | None = None


def _classify(line: str) -> str | None:
    lowered = line.lower()
    if any(lowered.startswith(skip) or skip in lowered for skip in _IGNORE):
        return None
    if any(hint in lowered for hint in _ERROR_HINTS):
        return "error"
    if any(hint in lowered for hint in _WARNING_HINTS):
        return "warning"
    return None


def parse(text: str) -> UpdateLog:
    result = UpdateLog(present=True)
    seen_migrations: set[str] = set()
    seen_errors: set[str] = set()
    seen_warnings: set[str] = set()
    seen_packages = {
        "upgraded": set(), "installed": set(), "removed": set(),
    }

    def append_unique(bucket, seen, value, max_items, max_chars, label):
        if len(value) > max_chars:
            raise ValueError(f"update transcript {label} exceeds the string limit")
        if value in seen:
            return
        if len(bucket) >= max_items:
            raise ValueError(f"update transcript contains too many {label}")
        seen.add(value)
        bucket.append(value)

    for raw in strip_ansi(text).split("\n"):
        line = raw.strip()
        if not line:
            continue
        if len(line) > MAX_LINE_CHARS:
            raise ValueError("update transcript contains an overlong line")

        migration = _MIGRATION.match(line)
        if migration:
            name = migration.group("name")
            append_unique(result.migrations, seen_migrations, name,
                          MAX_MIGRATIONS, MAX_NAME_CHARS, "migrations")
            continue

        # A step heading is structure, not content. Skipped explicitly so it
        # can never fall through to the error/warning classifier.
        if _SECTION.match(line):
            continue

        for pattern, bucket, seen in (
            (_UPGRADING, result.upgraded, seen_packages["upgraded"]),
            (_INSTALLING, result.installed, seen_packages["installed"]),
            (_REMOVING, result.removed, seen_packages["removed"]),
        ):
            match = pattern.match(line)
            if match:
                name = match.group("name")
                append_unique(bucket, seen, name,
                              MAX_PACKAGES_PER_ACTION, MAX_NAME_CHARS, "packages")
                break
        else:
            if "AUR is unavailable" in line:
                result.aur_skipped = True
            if "Something went wrong during the update" in line:
                result.failed = True
            kind = _classify(line)
            if kind == "error":
                append_unique(result.errors, seen_errors, line,
                              MAX_MESSAGES, MAX_LINE_CHARS, "errors")
            elif kind == "warning":
                append_unique(result.warnings, seen_warnings, line,
                              MAX_MESSAGES, MAX_LINE_CHARS, "warnings")

    return result


def load(path=None) -> UpdateLog:
    """Parse the update transcript, or report absence.

    A missing transcript is the normal state on a machine that has
    rebooted since its last update, so it is reported as `present=False`
    rather than raised.
    """
    import hashlib
    from datetime import datetime

    log_path = path or paths.update_log()
    descriptor = -1
    try:
        descriptor = os.open(log_path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise PermissionError("update log is not a user-owned regular file")
        if info.st_size > MAX_LOG_BYTES:
            raise ValueError("update log is too large")
        chunks, total = [], 0
        while True:
            chunk = os.read(descriptor, min(65536, MAX_LOG_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_LOG_BYTES:
                raise ValueError("update log is too large")
        raw = b"".join(chunks)
        modified = datetime.fromtimestamp(info.st_mtime).astimezone()
    except FileNotFoundError:
        return UpdateLog(present=False)
    except (OSError, ValueError) as error:
        return UpdateLog(present=False, error=f"Update transcript was not read safely: {error}")
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    try:
        result = parse(raw.decode("utf-8", errors="replace"))
    except ValueError as error:
        return UpdateLog(present=False, error=str(error))
    result.modified = modified
    result.source_signature = [info.st_dev, info.st_ino, len(raw), info.st_mtime_ns]
    # Identifies this exact transcript so the same run is never captured
    # twice, however often the plugin looks at it.
    result.digest = hashlib.sha256(raw).hexdigest()
    return result
