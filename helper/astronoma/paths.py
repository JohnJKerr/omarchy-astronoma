"""Every path Astronoma reads or writes, resolved in one place.

Kept as functions rather than module constants so tests (and the
ASTRONOMA_* env overrides they use) can redirect the whole tree without
reimporting anything.
"""

import os
import json
import tempfile
from pathlib import Path


def _env_path(name: str, default: Path) -> Path:
    value = os.environ.get(name)
    return Path(value).expanduser() if value else default


def home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home())))


def state_dir() -> Path:
    """Persisted update records. Survives the reboot that clears /tmp."""
    return _env_path(
        "ASTRONOMA_STATE_DIR",
        home() / ".local" / "state" / "omarchy-updates",
    )


def cache_dir() -> Path:
    """GitHub release cache, so opening the panel never requires network."""
    return _env_path("ASTRONOMA_CACHE_DIR", home() / ".cache" / "astronoma")


def update_log() -> Path:
    """Omarchy's `script(1)` transcript of the most recent update run."""
    return _env_path("ASTRONOMA_UPDATE_LOG", Path("/tmp/omarchy-update.log"))


def pacman_log() -> Path:
    return _env_path("ASTRONOMA_PACMAN_LOG", Path("/var/log/pacman.log"))


def migrations_state_dir() -> Path:
    """Omarchy touches a marker file here per migration it has run."""
    return _env_path(
        "ASTRONOMA_MIGRATIONS_DIR",
        home() / ".local" / "state" / "omarchy" / "migrations",
    )


def omarchy_path() -> Path:
    return Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))


def releases_cache() -> Path:
    return cache_dir() / "releases.json"


def summaries_dir() -> Path:
    return state_dir() / "summaries"


def private_directory(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)


def atomic_json_write(target: Path, payload, private: bool = False) -> None:
    """Atomically replace JSON using a unique sibling temporary file."""
    if private:
        private_directory(target.parent)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target.name}.", suffix=".tmp", dir=target.parent
    )
    temporary = Path(temporary_name)
    try:
        if private:
            os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            json.dump(payload, handle, indent=2 if private else None)
            handle.write("\n" if private else "")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(target)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
