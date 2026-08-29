"""Read /var/log/pacman.log into update sessions.

pacman's log is the one package record that is exact and survives a
reboot, so Astronoma treats it as the source of truth for what packages
changed. It has no notion of "an Omarchy update", though — only a flat
stream of transactions. `sessions()` supplies that missing grouping by
clustering transactions that run back to back, which is what an update
looks like from the log's point of view.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from . import paths

# [2026-08-28T23:06:01+0100] [ALPM] upgraded brave-origin-bin (1:1.93.138-1 -> 1:1.94.117-1)
_ALPM = re.compile(
    r"^\[(?P<ts>[^\]]+)\]\s+\[ALPM\]\s+"
    r"(?P<action>upgraded|installed|removed)\s+"
    r"(?P<name>\S+)\s+\((?P<versions>[^)]*)\)\s*$"
)
# [2026-08-28T23:05:04+0100] [PACMAN] Running 'pacman -Syu ...'
_PACMAN_CMD = re.compile(
    r"^\[(?P<ts>[^\]]+)\]\s+\[PACMAN\]\s+Running\s+'(?P<cmd>.*)'\s*$"
)

# An Omarchy update is one long run of package activity. Anything separated
# by more than this from the previous change is a different update.
SESSION_GAP = timedelta(minutes=45)


@dataclass
class PackageChange:
    name: str
    action: str          # upgraded | installed | removed
    at: datetime
    from_version: str | None = None
    to_version: str | None = None
    aur: bool = False

    def as_dict(self) -> dict:
        data = {"name": self.name, "action": self.action}
        if self.from_version:
            data["from"] = self.from_version
        if self.to_version:
            data["to"] = self.to_version
        if self.aur:
            data["aur"] = True
        return data


@dataclass
class Session:
    """One cluster of package activity — Astronoma's idea of an update."""

    started: datetime
    finished: datetime
    changes: list[PackageChange] = field(default_factory=list)
    commands: list[str] = field(default_factory=list)

    @property
    def upgraded(self) -> list[PackageChange]:
        return [c for c in self.changes if c.action == "upgraded"]

    @property
    def installed(self) -> list[PackageChange]:
        return [c for c in self.changes if c.action == "installed"]

    @property
    def removed(self) -> list[PackageChange]:
        return [c for c in self.changes if c.action == "removed"]

    def omarchy_delta(self) -> tuple[str | None, str | None]:
        """The Omarchy version change this session performed, if any."""
        for change in self.changes:
            if change.name in ("omarchy", "omarchy-dev"):
                return change.from_version, change.to_version
        return None, None

    def is_system_upgrade(self) -> bool:
        """True when a full `-Syu` ran, as opposed to a one-off install."""
        return any(_looks_like_sysupgrade(cmd) for cmd in self.commands)


def _looks_like_sysupgrade(command: str) -> bool:
    tokens = command.split()
    sync = upgrade = False
    for token in tokens:
        if token in ("--sync",):
            sync = True
        elif token in ("--sysupgrade",):
            upgrade = True
        elif token.startswith("-") and not token.startswith("--"):
            sync = sync or "S" in token
            upgrade = upgrade or "u" in token
    return sync and upgrade


def _parse_timestamp(raw: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(raw)
        return parsed.astimezone() if parsed.tzinfo else parsed.astimezone()
    except ValueError:
        pass
    # Pre-5.x pacman wrote [2019-01-01 12:00] with no timezone.
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(raw, fmt).astimezone()
        except ValueError:
            continue
    return None


def _split_versions(action: str, raw: str) -> tuple[str | None, str | None]:
    if action == "upgraded" and "->" in raw:
        before, after = raw.split("->", 1)
        return before.strip(), after.strip()
    value = raw.strip() or None
    return (None, value) if action == "installed" else (value, None)


def read(path=None) -> tuple[list[PackageChange], list[tuple[datetime, str]]]:
    """All package changes and pacman invocations, oldest first.

    A missing or unreadable log is not an error — plenty of machines will
    not hand us one — so it yields empty results and lets the caller carry
    on with whatever other sources it has.
    """
    log_path = path or paths.pacman_log()
    changes: list[PackageChange] = []
    commands: list[tuple[datetime, str]] = []
    try:
        handle = open(log_path, "r", errors="replace")
    except OSError:
        return changes, commands
    with handle:
        for line in handle:
            match = _ALPM.match(line.rstrip("\n"))
            if match:
                at = _parse_timestamp(match.group("ts"))
                if at is None:
                    continue
                action = match.group("action")
                before, after = _split_versions(action, match.group("versions"))
                changes.append(
                    PackageChange(
                        name=match.group("name"),
                        action=action,
                        at=at,
                        from_version=before,
                        to_version=after,
                    )
                )
                continue
            command = _PACMAN_CMD.match(line.rstrip("\n"))
            if command:
                at = _parse_timestamp(command.group("ts"))
                if at is not None:
                    commands.append((at, command.group("cmd")))
    return changes, commands


def _mark_aur(changes: list[PackageChange], commands: list[tuple[datetime, str]]) -> None:
    """Flag changes that came from a helper installing a locally built package.

    yay hands pacman a built `-U /home/<user>/.cache/yay/...` package, which
    is the only trace in the log that a change came from the AUR.
    """
    windows = [
        at for at, cmd in commands
        if " -U " in f" {cmd} " and "/.cache/" in cmd
    ]
    if not windows:
        return
    for change in changes:
        for start in windows:
            if start <= change.at <= start + timedelta(minutes=30):
                change.aur = True
                break


def sessions(path=None, gap: timedelta = SESSION_GAP) -> list[Session]:
    """Group package activity into updates, newest session last.

    Transactions that run within `gap` of each other belong to the same
    update: an Omarchy update runs pacman, then migrations, then yay, all
    inside a few minutes, while the next update is hours or days away.
    """
    changes, commands = read(path)
    _mark_aur(changes, commands)
    if not changes:
        return []

    changes.sort(key=lambda c: c.at)
    grouped: list[Session] = []
    current = Session(started=changes[0].at, finished=changes[0].at)
    for change in changes:
        if change.at - current.finished > gap:
            grouped.append(current)
            current = Session(started=change.at, finished=change.at)
        current.changes.append(change)
        current.finished = change.at
    grouped.append(current)

    for session in grouped:
        session.commands = [
            cmd for at, cmd in commands
            if session.started - gap <= at <= session.finished + gap
        ]
    return grouped
