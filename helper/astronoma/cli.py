"""The `astronoma` command. Every subcommand prints JSON on stdout.

The plugin runs this and renders the result; a person can run the same
commands to see exactly what the plugin sees.
"""

import argparse
import json
import sys

from . import __version__, agent, capture, history, releases as releases_mod, report

MAX_OUTPUT_BYTES = 16 * 1024 * 1024


def _emit(payload, pretty: bool) -> int:
    encoded = (json.dumps(payload, indent=2 if pretty else None) + "\n").encode("utf-8")
    if len(encoded) > MAX_OUTPUT_BYTES:
        payload = {"ok": False, "error": "Report exceeds the output limit"}
        encoded = (json.dumps(payload) + "\n").encode("utf-8")
    stream = getattr(sys.stdout, "buffer", sys.stdout)
    stream.write(encoded if stream is not sys.stdout else encoded.decode("utf-8"))
    ok = payload.get("ok", True) if isinstance(payload, dict) else True
    return 0 if ok else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="astronoma",
        description="Flight log for Omarchy updates.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--pretty", action="store_true", default=False,
                        dest="global_pretty", help="indent JSON output")

    # Also accepted after the subcommand, so `astronoma report --pretty`
    # works as naturally as `astronoma --pretty report`.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--pretty", action="store_true", default=None,
                        help="indent JSON output")

    sub = parser.add_subparsers(dest="command", required=True)

    capture_cmd = sub.add_parser("capture", parents=[common], help="parse logs into update history")
    capture_cmd.add_argument("--force", action="store_true",
                             help="rewrite records that already exist")

    report_cmd = sub.add_parser("report", parents=[common], help="everything the plugin renders")
    report_cmd.add_argument("--refresh", action="store_true",
                            help="refresh GitHub releases before reporting")
    report_cmd.add_argument("--no-capture", action="store_true",
                            help="report without capturing new updates first")
    report_cmd.add_argument("--notes-limit", type=int, default=None,
                            help="truncate release bodies to N characters")

    show_cmd = sub.add_parser("show", parents=[common], help="one captured update in full")
    show_cmd.add_argument("id")
    show_cmd.add_argument("--refresh", action="store_true")

    sub.add_parser("history", parents=[common], help="captured updates, newest first")

    seen_cmd = sub.add_parser("seen", parents=[common],
                              help="mark an update as read")
    seen_cmd.add_argument("id", nargs="?", help="defaults to the latest update")

    releases_cmd = sub.add_parser("releases", parents=[common], help="Omarchy releases")
    releases_cmd.add_argument("--refresh", action="store_true")

    sub.add_parser("agents", parents=[common], help="installed agent CLIs")

    consent_cmd = sub.add_parser("agent-summaries", parents=[common],
                                 help="inspect or revoke agent-summary consent")
    consent_cmd.add_argument("state", choices=("status", "enable", "disable"),
                             nargs="?", default="status")

    summarise_cmd = sub.add_parser("summarise", parents=[common], help="agent impact summary")
    summarise_cmd.add_argument("id", nargs="?", help="defaults to the latest update")
    summarise_cmd.add_argument("--agent", dest="agent_key", default=None)
    summarise_cmd.add_argument("--refresh", action="store_true",
                               help="regenerate even if one is cached")
    summarise_cmd.add_argument("--enable", action="store_true",
                               help="record consent and enable agent summaries")

    args = parser.parse_args(argv)
    # The subcommand flag wins when given; otherwise fall back to the global.
    pretty = bool(args.global_pretty or args.pretty)

    if args.command == "capture":
        return _emit(capture.run(force=args.force), pretty)

    if args.command == "report":
        if not args.no_capture:
            # Capturing first is what makes a freshly finished update show up
            # the moment the panel is opened.
            capture.run_if_changed()
        return _emit(
            report.build(refresh=args.refresh, notes_limit=args.notes_limit), pretty
        )

    if args.command == "show":
        return _emit(report.detail(args.id, refresh=args.refresh), pretty)

    if args.command == "history":
        return _emit(
            {"history": [history.summary_row(r) for r in history.all_records()]},
            pretty,
        )

    if args.command == "seen":
        identifier = args.id
        if not identifier:
            latest = history.latest()
            identifier = str(latest.get("id")) if latest else ""
        return _emit(
            {"ok": bool(identifier), "seen": history.mark_seen(identifier)}, pretty
        )

    if args.command == "releases":
        # Typed by a person who wants a fetch, not the panel reopening: this
        # is the one caller that should get through the refresh floor.
        catalogue, status = releases_mod.load(refresh=args.refresh, min_interval=0)
        return _emit(
            {"status": status, "releases": [r.as_dict() for r in catalogue]}, pretty
        )

    if args.command == "agents":
        return _emit({"agents": agent.available()}, pretty)

    if args.command == "agent-summaries":
        if args.state != "status":
            agent.set_enabled(args.state == "enable")
        return _emit({"ok": True, "enabled": agent.enabled()}, pretty)

    if args.command == "summarise":
        if args.enable:
            agent.set_enabled(True)
        if not agent.enabled():
            return _emit({
                "ok": False,
                "error": "Agent summaries are disabled; explicitly enable them first",
            }, pretty)
        identifier = args.id
        if not identifier:
            latest = history.latest()
            if not latest:
                return _emit(
                    {"ok": False, "error": "No captured updates yet"}, pretty
                )
            identifier = str(latest.get("id"))
        catalogue, _ = releases_mod.load()
        record = history.load(identifier) or {}
        omarchy = record.get("omarchy") or {}
        crossed = releases_mod.crossed(
            catalogue, omarchy.get("from"), omarchy.get("to") or ""
        )
        return _emit(
            agent.summarise(
                identifier,
                [r.as_dict() for r in crossed],
                key=args.agent_key,
                refresh=args.refresh,
            ),
            pretty,
        )

    parser.error(f"unknown command {args.command}")
    return 2
