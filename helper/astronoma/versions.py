"""Omarchy version detection and comparison.

Two vocabularies meet here. Pacman speaks `4.0.1-1` (with an epoch and a
pkgrel); GitHub speaks `v4.0.1`. `release_key` reduces both to the tuple
the rest of Astronoma sorts and compares on, so a pacman version can be
lined up against a release tag without either side caring.
"""

import re
import subprocess

from . import paths

_PKG_CANDIDATES = ("omarchy-dev", "omarchy")


def installed() -> str | None:
    """The Omarchy version this machine is running, or None if unknown.

    Mirrors `omarchy-version`: a source checkout reports as a dev build and
    has no release to line up against, so it deliberately yields None
    rather than a version that would sort wrongly against real releases.
    """
    path = paths.omarchy_path()
    if str(path).rstrip("/") != "/usr/share/omarchy":
        return None
    for package in _PKG_CANDIDATES:
        version = _pacman_version(package)
        if version:
            return version
    return _version_file()


def _pacman_version(package: str) -> str | None:
    try:
        out = subprocess.run(
            ["pacman", "-Q", package],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    parts = out.stdout.split()
    return parts[1] if len(parts) >= 2 else None


def _version_file() -> str | None:
    try:
        text = (paths.omarchy_path() / "version").read_text().strip()
    except OSError:
        return None
    return text or None


def strip_pkgrel(version: str) -> str:
    """`1:4.0.1-1` -> `4.0.1`. Epoch and pkgrel are packaging detail.

    Only a numeric trailing field is a pkgrel. `4.0.1-rc1` is a prerelease
    and keeps its suffix, or it would compare equal to the real 4.0.1.
    """
    value = str(version or "").strip()
    value = value.split(":", 1)[-1] if ":" in value else value
    return re.sub(r"-\d+(?:\.\d+)*$", "", value)


def normalize_tag(tag: str) -> str:
    """`v4.0.1` -> `4.0.1`."""
    value = str(tag or "").strip()
    return value[1:] if value[:1] in ("v", "V") else value


def release_key(version: str) -> tuple:
    """A sortable key that orders 3.8.4 < 4.0.0 < 4.0.1.

    Numeric runs compare as integers so 3.10 sorts above 3.9; any trailing
    non-numeric suffix (a `-rc1`) sorts below the bare release, matching
    how people read a prerelease.
    """
    base = strip_pkgrel(normalize_tag(version))
    match = re.match(r"^(\d+(?:\.\d+)*)(.*)$", base)
    if not match:
        return ((), 1, base)
    numbers = tuple(int(part) for part in match.group(1).split("."))
    suffix = match.group(2).strip(".-_")
    # No suffix ranks above a suffixed build of the same numbers.
    return (numbers, 0 if suffix else 1, suffix)


def compare(left: str, right: str) -> int:
    a, b = release_key(left), release_key(right)
    return (a > b) - (a < b)


def is_between(candidate: str, previous: str | None, current: str) -> bool:
    """True when `candidate` is a release crossed going previous -> current.

    Exclusive of `previous` (already had it) and inclusive of `current`.
    """
    key = release_key(candidate)
    if key > release_key(current):
        return False
    return previous is None or key > release_key(previous)
