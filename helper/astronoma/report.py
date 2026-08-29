"""Assemble the single payload the plugin renders.

The QML side does no joining and no fallback logic: it draws whatever
this returns. That keeps the shell-side code thin and means the whole
view can be inspected from a terminal with `astronoma report`.
"""

from . import agent, history, releases as releases_mod, versions

RECENT_RELEASE_COUNT = 5


def _release_dicts(items) -> list[dict]:
    return [item.as_dict() for item in items]


def _crossed_for(catalogue, omarchy: dict):
    """Releases a captured update crossed, or none when it crossed none.

    An update that moved packages without touching Omarchy has no landing
    version, and falling back to the installed one would present releases
    the machine already had as though this update had delivered them.
    """
    landed = omarchy.get("to")
    if not landed:
        return []
    return releases_mod.crossed(catalogue, omarchy.get("from"), landed)


def build(refresh: bool = False, notes_limit: int | None = None) -> dict:
    """The full view: latest update, history, and the releases behind them.

    Every section degrades on its own. No network yields cached notes; no
    captured history yields the recent-releases view; no Omarchy version
    yields package data with the release side left empty.
    """
    installed_raw = versions.installed()
    installed = versions.strip_pkgrel(installed_raw) if installed_raw else None

    catalogue, status = releases_mod.load(refresh=refresh)
    records = history.all_records()
    latest = records[0] if records else None

    def trim(entries: list[dict]) -> list[dict]:
        if notes_limit is None:
            return entries
        return [{**entry, "body": _clip(str(entry.get("body") or ""))} for entry in entries]

    def _clip(body: str) -> str:
        if len(body) <= notes_limit:
            return body
        # Cut back to the last line break so the caller never has to reason
        # about a bullet that stops mid-word.
        cut = body[:notes_limit]
        boundary = cut.rfind("\n")
        return cut[:boundary] if boundary > 0 else cut

    payload = {
        "schema": 1,
        "omarchy": {
            "installed": installed,
            "installedRaw": installed_raw,
            # A dev checkout has no release to line up against; an unreadable
            # pacman is a version we failed to read. Both leave `installed`
            # empty, and only the first is the machine being unusual.
            "isDev": versions.is_dev_checkout(),
            "versionUnknown": installed_raw is None,
        },
        "releases": {
            "status": status,
            "recent": trim(_release_dicts(
                releases_mod.recent(catalogue, installed, RECENT_RELEASE_COUNT)
            )),
        },
        "history": [history.summary_row(record) for record in records],
        # Drives whether the bar asks for attention at all.
        "unread": history.unread_in(records),
        "agents": agent.available(),
        "agentSummariesEnabled": agent.enabled(),
        "latest": None,
    }

    if latest:
        omarchy = latest.get("omarchy") or {}
        crossed = _crossed_for(catalogue, omarchy)
        payload["latest"] = {
            **latest,
            "crossed": trim(_release_dicts(crossed)),
            "summary": agent.cached_summary(str(latest.get("id") or "")),
        }

    return payload


def detail(identifier: str, refresh: bool = False) -> dict:
    """One captured update, with the release notes it crossed."""
    record = history.load(identifier)
    if not record:
        return {"ok": False, "error": f"No captured update {identifier}"}

    catalogue, status = releases_mod.load(refresh=refresh)
    crossed = _crossed_for(catalogue, record.get("omarchy") or {})
    return {
        "ok": True,
        **record,
        "crossed": _release_dicts(crossed),
        "releaseStatus": status,
        "summary": agent.cached_summary(identifier),
        "agents": agent.available(),
        "agentSummariesEnabled": agent.enabled(),
    }
