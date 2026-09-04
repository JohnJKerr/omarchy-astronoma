"""Fetch and cache Omarchy's GitHub releases.

Opening the panel must never depend on the network, so every fetch is
written to a cache that reads are served from. A failed refresh leaves
the previous cache in place and reports the failure alongside it, which
is what lets the UI show real release notes with a quiet "couldn't
refresh" note rather than an empty panel.
"""

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass

from . import paths, versions

REPO = "omacom/omarchy"
API = f"https://api.github.com/repos/{REPO}/releases"
CACHE_SCHEMA = 1
DEFAULT_TTL = 6 * 60 * 60  # Releases land a few times a week at most.
USER_AGENT = "omarchy-astronoma"
# Thirty releases of notes is a few hundred KB. Anything past this is not a
# releases payload, and read() without a bound would take all of it.
MAX_PAYLOAD_BYTES = 8 * 1024 * 1024
MAX_CACHE_BYTES = 8 * 1024 * 1024
MAX_RELEASES = 30
MAX_RELEASE_STRING = 256 * 1024
MAX_METADATA_STRING = 2048
# Opening the panel asks for a refresh every time, and unauthenticated GitHub
# allows 60 requests an hour. Releases do not land often enough for a second
# fetch inside this window to return anything new.
MIN_REFRESH_INTERVAL = 5 * 60


@dataclass
class Release:
    tag: str
    name: str
    published_at: str
    body: str
    url: str

    @property
    def version(self) -> str:
        return versions.normalize_tag(self.tag)

    def as_dict(self) -> dict:
        return {
            "tag": self.tag,
            "version": self.version,
            "name": self.name,
            "publishedAt": self.published_at,
            "body": self.body,
            "url": self.url,
        }

    @classmethod
    def from_api(cls, payload: dict) -> "Release":
        return cls(
            tag=str(payload.get("tag_name") or ""),
            name=str(payload.get("name") or payload.get("tag_name") or ""),
            published_at=str(payload.get("published_at") or ""),
            body=str(payload.get("body") or ""),
            url=str(payload.get("html_url") or ""),
        )

    @classmethod
    def from_cache(cls, payload: dict) -> "Release":
        return cls(
            tag=str(payload.get("tag") or ""),
            name=str(payload.get("name") or ""),
            published_at=str(payload.get("publishedAt") or ""),
            body=str(payload.get("body") or ""),
            url=str(payload.get("url") or ""),
        )


def _valid_release_fields(payload: dict, api: bool = False) -> bool:
    """Validate the fields we consume before constructing display data.

    GitHub may add unrelated API fields, so those are explicitly ignored;
    every field crossing into Astronoma has an exact type and length budget.
    """
    names = {
        "tag": "tag_name" if api else "tag",
        "name": "name",
        "publishedAt": "published_at" if api else "publishedAt",
        "body": "body",
        "url": "html_url" if api else "url",
    }
    for local_name, source_name in names.items():
        value = payload.get(source_name)
        # The API documents nullable name/body fields. The constructors turn
        # those into empty strings, but no other scalar/container is accepted.
        if value is None and local_name in ("name", "body"):
            continue
        limit = MAX_RELEASE_STRING if local_name == "body" else MAX_METADATA_STRING
        if not isinstance(value, str) or len(value) > limit:
            return False
    return True


def _read_cache() -> dict:
    try:
        data = paths.read_json(paths.releases_cache(), MAX_CACHE_BYTES)
    except (OSError, ValueError):
        return {}
    if not (isinstance(data, dict) and set(data) == {"schema", "fetchedAt", "releases"}
            and data.get("schema") == CACHE_SCHEMA and isinstance(data.get("fetchedAt"), int)):
        return {}
    items = data.get("releases")
    required = {"tag", "name", "publishedAt", "body", "url"}
    allowed = required | {"version"}
    if not isinstance(items, list) or len(items) > MAX_RELEASES:
        return {}
    valid_items = [
        item for item in items
        if (isinstance(item, dict) and required <= set(item) <= allowed
            and all(isinstance(item[key], str) for key in item)
            and _valid_release_fields(item))
    ]
    return {**data, "releases": valid_items}


def _write_cache(releases: list[Release]) -> None:
    payload = {
        "schema": CACHE_SCHEMA,
        "fetchedAt": int(time.time()),
        "releases": [release.as_dict() for release in releases],
    }
    paths.atomic_json_write(paths.releases_cache(), payload)


def _fetch(limit: int = 30, timeout: int = 15) -> list[Release]:
    request = urllib.request.Request(
        f"{API}?per_page={int(limit)}",
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read(MAX_PAYLOAD_BYTES + 1)
    if len(raw) > MAX_PAYLOAD_BYTES:
        raise ValueError("releases payload too large")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, list):
        raise ValueError("unexpected releases payload")
    if len(payload) > min(MAX_RELEASES, max(0, int(limit))):
        raise ValueError("too many releases in payload")
    parsed = [
        Release.from_api(item) for item in payload
        if isinstance(item, dict) and _valid_release_fields(item, api=True)
    ]
    return [release for release in parsed if release.tag]


def load(refresh: bool = False, ttl: int = DEFAULT_TTL,
         min_interval: int = MIN_REFRESH_INTERVAL) -> tuple[list[Release], dict]:
    """Return (releases, status). Never raises on a network problem.

    `status` carries `stale`, `fetchedAt` and any `error`, so the caller can
    render cached notes and still say the refresh did not get through.

    `refresh` overrides the TTL but not `min_interval`, which keeps a panel
    opened repeatedly from spending the hourly GitHub allowance on answers
    that cannot have changed. Pass `min_interval=0` to force a real fetch.
    """
    cache = _read_cache()
    raw_cached = cache.get("releases", [])
    cached = [
        Release.from_cache(item) for item in raw_cached
        if isinstance(raw_cached, list) and isinstance(item, dict)
    ]
    fetched_at = int(cache.get("fetchedAt") or 0)
    age = int(time.time()) - fetched_at if fetched_at else None
    expired = age is None or age > ttl
    too_soon = age is not None and age < min_interval

    if (not refresh and not expired) or (refresh and too_soon and cached):
        return cached, {"stale": False, "fetchedAt": fetched_at, "source": "cache"}

    try:
        live = _fetch()
    except (urllib.error.URLError, OSError, ValueError, TimeoutError) as error:
        return cached, {
            "stale": True,
            "fetchedAt": fetched_at,
            "source": "cache",
            "error": _describe(error),
        }

    if live:
        _write_cache(live)
        return live, {"stale": False, "fetchedAt": int(time.time()), "source": "network"}
    return cached, {"stale": True, "fetchedAt": fetched_at, "source": "cache"}


def _describe(error: Exception) -> str:
    if isinstance(error, urllib.error.HTTPError):
        if error.code == 403:
            return "GitHub rate limit reached"
        return f"GitHub returned {error.code}"
    if isinstance(error, urllib.error.URLError):
        return "No network connection"
    return "Could not reach GitHub"


def crossed(releases: list[Release], previous: str | None, current: str) -> list[Release]:
    """Releases an update moved the machine through, newest first.

    Exclusive of `previous` and inclusive of `current`: the user already
    had the release they were on, and did land on the one they are now.

    With no `previous` there is no lower bound to work from, and every
    release up to `current` would qualify — which would claim an update
    crossed the entire history of Omarchy. A packages-only update hits
    this on every machine, so the honest answer is the release the machine
    is on and nothing else: those are the notes we can stand behind.
    """
    if not current:
        return []
    if previous is None:
        current_key = versions.release_key(current)
        return [r for r in releases if versions.release_key(r.version) == current_key]
    selected = [
        release for release in releases
        if versions.is_between(release.version, previous, current)
    ]
    return sorted(selected, key=lambda r: versions.release_key(r.version), reverse=True)


def recent(releases: list[Release], current: str | None, limit: int = 5) -> list[Release]:
    """The newest releases up to the installed version.

    This is the default view when there is no captured update to show, so
    it never reaches past what the machine is actually running.
    """
    pool = releases
    if current:
        current_key = versions.release_key(current)
        pool = [r for r in releases if versions.release_key(r.version) <= current_key]
    ordered = sorted(pool, key=lambda r: versions.release_key(r.version), reverse=True)
    return ordered[: max(0, int(limit))]


def upcoming(releases: list[Release], current: str | None) -> list[Release]:
    """Published releases newer than the version installed on this machine."""
    if not current:
        return []
    current_key = versions.release_key(current)
    return sorted(
        (release for release in releases
         if versions.release_key(release.version) > current_key),
        key=lambda release: versions.release_key(release.version),
        reverse=True,
    )


def earlier(releases: list[Release], earliest: str | None) -> list[Release]:
    """Published releases older than the first version in recorded history."""
    if not earliest:
        return []
    earliest_key = versions.release_key(earliest)
    return sorted(
        (release for release in releases
         if versions.release_key(release.version) < earliest_key),
        key=lambda release: versions.release_key(release.version),
        reverse=True,
    )
