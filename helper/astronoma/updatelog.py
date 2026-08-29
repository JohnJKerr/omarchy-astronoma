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

import re
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
    sections: list[str] = field(default_factory=list)
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

    def as_dict(self) -> dict:
        return {
            "present": self.present,
            "migrations": self.migrations,
            "sections": self.sections,
            "errors": self.errors,
            "warnings": self.warnings,
            "aurSkipped": self.aur_skipped,
            "failed": self.failed,
        }


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
    seen_errors: set[str] = set()
    seen_warnings: set[str] = set()

    for raw in strip_ansi(text).split("\n"):
        line = raw.strip()
        if not line:
            continue

        migration = _MIGRATION.match(line)
        if migration:
            name = migration.group("name")
            if name not in result.migrations:
                result.migrations.append(name)
            continue

        section = _SECTION.match(line)
        if section:
            if line not in result.sections:
                result.sections.append(line)
            continue

        for pattern, bucket in (
            (_UPGRADING, result.upgraded),
            (_INSTALLING, result.installed),
            (_REMOVING, result.removed),
        ):
            match = pattern.match(line)
            if match:
                name = match.group("name")
                if name not in bucket:
                    bucket.append(name)
                break
        else:
            if "AUR is unavailable" in line:
                result.aur_skipped = True
            if "Something went wrong during the update" in line:
                result.failed = True
            kind = _classify(line)
            if kind == "error" and line not in seen_errors:
                seen_errors.add(line)
                result.errors.append(line)
            elif kind == "warning" and line not in seen_warnings:
                seen_warnings.add(line)
                result.warnings.append(line)

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
    try:
        raw = log_path.read_bytes()
        modified = datetime.fromtimestamp(log_path.stat().st_mtime).astimezone()
    except OSError:
        return UpdateLog(present=False)
    result = parse(raw.decode("utf-8", errors="replace"))
    result.modified = modified
    # Identifies this exact transcript so the same run is never captured
    # twice, however often the plugin looks at it.
    result.digest = hashlib.sha256(raw).hexdigest()
    return result
