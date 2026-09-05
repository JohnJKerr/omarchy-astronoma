"""Paths plus descriptor-bound storage for Astronoma's mutable data."""

import errno
import json
import os
import secrets
import stat
from contextlib import contextmanager
from pathlib import Path


def _env_path(name: str, default: Path) -> Path:
    value = os.environ.get(name)
    return Path(value).expanduser() if value else default


def home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home())))


def state_dir() -> Path:
    return _env_path("ASTRONOMA_STATE_DIR", home() / ".local" / "state" / "omarchy-updates")


def cache_dir() -> Path:
    return _env_path("ASTRONOMA_CACHE_DIR", home() / ".cache" / "astronoma")


def update_log() -> Path:
    return _env_path("ASTRONOMA_UPDATE_LOG", Path("/tmp/omarchy-update.log"))


def pacman_log() -> Path:
    return _env_path("ASTRONOMA_PACMAN_LOG", Path("/var/log/pacman.log"))


def migrations_state_dir() -> Path:
    return _env_path("ASTRONOMA_MIGRATIONS_DIR", home() / ".local" / "state" / "omarchy" / "migrations")


def omarchy_path() -> Path:
    return Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))


def releases_cache() -> Path:
    return cache_dir() / "releases.json"


def summaries_dir() -> Path:
    return state_dir() / "summaries"


_DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
_FILE_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK


def _parts(path: Path) -> tuple[str, ...]:
    absolute = path.expanduser().absolute()
    if any(part in ("", ".", "..") for part in absolute.parts[1:]):
        raise OSError(errno.EINVAL, "unsafe path", str(path))
    return absolute.parts[1:]


def _open_directory(directory: Path, create: bool = False, private: bool = False) -> int:
    """Open a directory by walking from `/`, never following a symlink."""
    descriptor = os.open("/", _DIR_FLAGS)
    try:
        system_owner = os.fstat(descriptor).st_uid
        parts = _parts(directory)
        for index, name in enumerate(parts):
            final = index == len(parts) - 1
            try:
                child = os.open(name, _DIR_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(name, 0o700 if private else 0o755, dir_fd=descriptor)
                child = os.open(name, _DIR_FLAGS, dir_fd=descriptor)
            info = os.fstat(child)
            unsafe_writable = info.st_mode & 0o022 and not (info.st_mode & stat.S_ISVTX)
            if (not stat.S_ISDIR(info.st_mode)
                    or info.st_uid not in (system_owner, os.geteuid()) or unsafe_writable):
                os.close(child)
                raise PermissionError(f"untrusted directory component: {name}")
            if final and private:
                if info.st_uid != os.geteuid():
                    os.close(child)
                    raise PermissionError(f"private directory has wrong owner: {directory}")
                os.fchmod(child, 0o700)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def private_directory(directory: Path) -> None:
    descriptor = _open_directory(directory, create=True, private=True)
    os.close(descriptor)


def _open_regular(parent_fd: int, name: str, max_bytes: int, private: bool) -> int:
    descriptor = os.open(name, _FILE_FLAGS, dir_fd=parent_fd)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(errno.EINVAL, "not a regular file", name)
        if info.st_uid != os.geteuid():
            raise PermissionError(f"file has wrong owner: {name}")
        if private and info.st_mode & 0o077:
            os.fchmod(descriptor, 0o600)
        if info.st_size > max_bytes:
            raise ValueError(f"file exceeds {max_bytes} byte limit")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def read_bytes(target: Path, max_bytes: int, private: bool = True) -> bytes:
    parent = _open_directory(target.parent, private=private)
    try:
        descriptor = _open_regular(parent, target.name, max_bytes, private)
        try:
            chunks, total = [], 0
            while True:
                chunk = os.read(descriptor, min(65536, max_bytes + 1 - total))
                if not chunk:
                    return b"".join(chunks)
                chunks.append(chunk)
                total += len(chunk)
                if total > max_bytes:
                    raise ValueError(f"file exceeds {max_bytes} byte limit")
        finally:
            os.close(descriptor)
    finally:
        os.close(parent)


def read_json(target: Path, max_bytes: int, private: bool = True):
    return json.loads(read_bytes(target, max_bytes, private).decode("utf-8"))


def json_within_limits(value, max_items: int, max_string: int, max_depth: int = 8) -> bool:
    """Reject JSON shapes capable of inflating work after a bounded read."""
    remaining = max_items

    def visit(item, depth):
        nonlocal remaining
        remaining -= 1
        if remaining < 0 or depth > max_depth:
            return False
        if isinstance(item, str):
            return len(item) <= max_string
        if isinstance(item, list):
            return all(visit(child, depth + 1) for child in item)
        if isinstance(item, dict):
            return all(isinstance(key, str) and len(key) <= 80
                       and visit(child, depth + 1) for key, child in item.items())
        return item is None or isinstance(item, (bool, int, float))

    return visit(value, 0)


def list_regular(directory: Path, max_entries: int) -> list[str]:
    descriptor = _open_directory(directory, private=True)
    try:
        names = os.listdir(descriptor)
        if len(names) > max_entries:
            raise ValueError(f"directory exceeds {max_entries} entry limit")
        result = []
        for name in names:
            try:
                leaf = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISREG(leaf.st_mode) and leaf.st_uid == os.geteuid() and not leaf.st_mode & 0o077:
                result.append(name)
        return result
    finally:
        os.close(descriptor)


def harden_private_tree(directory: Path) -> None:
    descriptor = _open_directory(directory, create=True, private=True)
    try:
        for name in os.listdir(descriptor):
            try:
                child = os.open(name, _FILE_FLAGS, dir_fd=descriptor)
                info = os.fstat(child)
                if stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid():
                    os.fchmod(child, 0o600)
                os.close(child)
            except OSError:
                continue
    finally:
        os.close(descriptor)


@contextmanager
def private_lock(target: Path):
    """Lock a regular, user-owned file below a verified private parent."""
    import fcntl

    parent = _open_directory(target.parent, create=True, private=True)
    descriptor = -1
    try:
        descriptor = os.open(target.name, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW,
                             0o600, dir_fd=parent)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise PermissionError(f"untrusted lock file: {target}")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent)


def atomic_json_write(target: Path, payload, private: bool = True) -> None:
    parent = _open_directory(target.parent, create=True, private=private)
    temporary = f".{target.name}.{secrets.token_hex(8)}.tmp"
    descriptor = -1
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                             0o600 if private else 0o644, dir_fd=parent)
        with os.fdopen(descriptor, "w") as handle:
            descriptor = -1
            json.dump(payload, handle, indent=2 if private else None)
            handle.write("\n" if private else "")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target.name, src_dir_fd=parent, dst_dir_fd=parent)
        os.fsync(parent)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary, dir_fd=parent)
        except FileNotFoundError:
            pass
        os.close(parent)


def unlink_private(target: Path) -> None:
    """Remove one user-owned regular file without following a mutable path."""
    try:
        parent = _open_directory(target.parent, private=True)
    except FileNotFoundError:
        return
    try:
        try:
            info = os.stat(target.name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise PermissionError(f"refusing to remove untrusted file: {target}")
        os.unlink(target.name, dir_fd=parent)
        os.fsync(parent)
    finally:
        os.close(parent)


def clear_private_directory(directory: Path, max_entries: int) -> int:
    """Remove a bounded set of user-owned regular files from a private directory."""
    try:
        descriptor = _open_directory(directory, private=True)
    except FileNotFoundError:
        return 0
    try:
        names = os.listdir(descriptor)
        if len(names) > max_entries:
            raise ValueError(f"directory exceeds {max_entries} entry limit")
        for name in names:
            info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
                raise PermissionError(f"refusing to remove untrusted entry: {directory / name}")
        for name in names:
            os.unlink(name, dir_fd=descriptor)
        if names:
            os.fsync(descriptor)
        return len(names)
    finally:
        os.close(descriptor)
