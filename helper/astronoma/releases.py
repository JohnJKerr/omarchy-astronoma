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

REPO = "basecamp/omarchy"
API = f"https://api.github.com/repos/{REPO}/releases"
CACHE_SCHEMA = 1
DEFAULT_TTL = 6 * 60 * 60  # Releases land a few times a week at most.
USER_AGENT = "omarchy-astronoma"


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


def _read_cache() -> dict:
    try:
        data = json.loads(paths.releases_cache().read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) and data.get("schema") == CACHE_SCHEMA else {}


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
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, list):
        raise ValueError("unexpected releases payload")
    parsed = [Release.from_api(item) for item in payload if isinstance(item, dict)]
    return [release for release in parsed if release.tag]


def load(refresh: bool = False, ttl: int = DEFAULT_TTL) -> tuple[list[Release], dict]:
    """Return (releases, status). Never raises on a network problem.

    `status` carries `stale`, `fetchedAt` and any `error`, so the caller can
    render cached notes and still say the refresh did not get through.
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

    if not refresh and not expired:
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
