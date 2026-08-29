"""Astronoma helper tests.

Weighted towards the failure modes the ticket calls out: absent logs, no
history, no network, no agent, and lines nothing knows how to parse.
"""

import json
import os
import sys
import tempfile
import unittest
import urllib.error
import subprocess
import re
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "helper"))

FIXTURES = Path(__file__).resolve().parent / "fixtures"

PACMAN_SAMPLE = """\
[2026-08-17T09:00:00+0100] [PACMAN] Running 'pacman -Syu'
[2026-08-17T09:00:01+0100] [ALPM] transaction started
[2026-08-17T09:00:02+0100] [ALPM] upgraded omarchy (3.8.4-1 -> 4.0.0-1)
[2026-08-17T09:00:03+0100] [ALPM] installed newthing (1.0-1)
[2026-08-17T09:00:04+0100] [ALPM] removed oldthing (0.9-1)
[2026-08-17T09:00:05+0100] [ALPM] transaction completed
[2026-08-28T23:00:00+0100] [PACMAN] Running 'pacman -Syu --noconfirm'
[2026-08-28T23:00:33+0100] [ALPM] upgraded omarchy (4.0.0-1 -> 4.0.1-1)
[2026-08-28T23:01:00+0100] [ALPM] upgraded quickshell (0.3.0-1 -> 0.3.1-1)
[2026-08-29T10:00:00+0100] [PACMAN] Running 'pacman -S ripgrep'
[2026-08-29T10:00:01+0100] [ALPM] installed ripgrep (14.0-1)
"""


class TempEnv(unittest.TestCase):
    """Redirects every Astronoma path into a throwaway tree."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.state = base / "state"
        self.cache = base / "cache"
        self.migrations = base / "migrations"
        self.migrations.mkdir(parents=True)
        self.pacman = base / "pacman.log"
        self.pacman.write_text(PACMAN_SAMPLE)
        self._saved = dict(os.environ)
        os.environ.update({
            "ASTRONOMA_STATE_DIR": str(self.state),
            "ASTRONOMA_CACHE_DIR": str(self.cache),
            "ASTRONOMA_MIGRATIONS_DIR": str(self.migrations),
            "ASTRONOMA_PACMAN_LOG": str(self.pacman),
            "ASTRONOMA_UPDATE_LOG": str(base / "absent.log"),
        })

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._saved)
        self.tmp.cleanup()


class VersionTests(unittest.TestCase):
    def test_pkgrel_stripped_but_prerelease_kept(self):
        from astronoma import versions
        self.assertEqual(versions.strip_pkgrel("1:1.94.117-1"), "1.94.117")
        self.assertEqual(versions.strip_pkgrel("4.0.1-1"), "4.0.1")
        self.assertEqual(versions.strip_pkgrel("4.0.1-rc1"), "4.0.1-rc1")

    def test_ordering_is_numeric_not_lexical(self):
        from astronoma import versions
        ordered = sorted(["3.8.4", "3.10.0", "3.9.0", "4.0.0"],
                         key=versions.release_key)
        self.assertEqual(ordered, ["3.8.4", "3.9.0", "3.10.0", "4.0.0"])

    def test_prerelease_sorts_below_release(self):
        from astronoma import versions
        self.assertEqual(versions.compare("4.0.1-rc1", "4.0.1"), -1)

    def test_crossing_window_excludes_previous_includes_current(self):
        from astronoma import versions
        self.assertTrue(versions.is_between("4.0.0", "3.8.4", "4.0.1"))
        self.assertTrue(versions.is_between("4.0.1", "3.8.4", "4.0.1"))
        self.assertFalse(versions.is_between("3.8.4", "3.8.4", "4.0.1"))
        self.assertFalse(versions.is_between("4.1.0", "3.8.4", "4.0.1"))

    def test_no_previous_version_still_yields_a_window(self):
        from astronoma import versions
        self.assertTrue(versions.is_between("3.8.4", None, "4.0.1"))


class PacmanLogTests(TempEnv):
    def test_mixed_legacy_and_modern_timestamps_are_grouped(self):
        from astronoma import pacmanlog
        self.pacman.write_text(
            "[2026-08-17 09:00] [PACMAN] Running 'pacman -Syu'\n"
            "[2026-08-17 09:01] [ALPM] upgraded omarchy (3.8.4-1 -> 4.0.0-1)\n"
            "[2026-08-17T09:02:00+0100] [ALPM] upgraded quickshell (1-1 -> 2-1)\n"
        )
        self.assertEqual(len(pacmanlog.sessions()), 1)
    def test_sessions_split_on_time_gap(self):
        from astronoma import pacmanlog
        sessions = pacmanlog.sessions()
        self.assertEqual(len(sessions), 3)

    def test_session_records_version_delta(self):
        from astronoma import pacmanlog
        august = pacmanlog.sessions()[1]
        self.assertEqual(august.omarchy_delta(), ("4.0.0-1", "4.0.1-1"))
        self.assertTrue(august.is_system_upgrade())

    def test_one_off_install_is_not_a_system_upgrade(self):
        from astronoma import pacmanlog
        self.assertFalse(pacmanlog.sessions()[2].is_system_upgrade())

    def test_missing_log_is_not_an_error(self):
        from astronoma import pacmanlog
        os.environ["ASTRONOMA_PACMAN_LOG"] = "/nonexistent/pacman.log"
        self.assertEqual(pacmanlog.sessions(), [])

    def test_unparseable_lines_are_skipped(self):
        from astronoma import pacmanlog
        self.pacman.write_text(
            PACMAN_SAMPLE
            + "this is not a pacman log line at all\n"
            + "[not-a-timestamp] [ALPM] upgraded ghost (1-1 -> 2-1)\n"
        )
        names = {c.name for s in pacmanlog.sessions() for c in s.changes}
        self.assertNotIn("ghost", names)
        self.assertIn("omarchy", names)


class UpdateLogTests(unittest.TestCase):
    def test_ansi_and_carriage_returns_are_flattened(self):
        from astronoma import updatelog
        raw = "\x1b[32mhello\x1b[0m\r\nprogress 1\rprogress 2\rdone\r\n"
        self.assertEqual(updatelog.strip_ansi(raw), "hello\ndone\n")

    def test_parses_migrations_errors_and_packages(self):
        from astronoma import updatelog
        parsed = updatelog.load(FIXTURES / "omarchy-update.log")
        self.assertTrue(parsed.present)
        self.assertEqual(parsed.migrations, ["1787618700", "1787580187"])
        self.assertIn("omarchy", parsed.upgraded)
        self.assertIn("qt6-wayland", parsed.installed)
        self.assertIn("quickshell-git", parsed.removed)
        self.assertTrue(parsed.aur_skipped)
        self.assertTrue(any("Initramfs" in e for e in parsed.errors))

    def test_benign_noise_is_not_reported_as_an_error(self):
        from astronoma import updatelog
        parsed = updatelog.load(FIXTURES / "omarchy-update.log")
        self.assertFalse(any("target not found" in e for e in parsed.errors))

    def test_absent_log_reports_absence(self):
        from astronoma import updatelog
        parsed = updatelog.load(Path("/nonexistent/omarchy-update.log"))
        self.assertFalse(parsed.present)
        self.assertEqual(parsed.errors, [])

    def test_binary_garbage_does_not_raise(self):
        from astronoma import updatelog
        with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as handle:
            handle.write(b"\xff\xfe\x00\x01 upgrading foo...\n")
            name = handle.name
        try:
            parsed = updatelog.load(Path(name))
            self.assertTrue(parsed.present)
        finally:
            os.unlink(name)


class CaptureTests(TempEnv):
    def test_capture_repairs_permissions_on_existing_state(self):
        from astronoma import capture
        self.state.mkdir(parents=True)
        old = self.state / "old.json"
        old.write_text("{}")
        old.chmod(0o644)
        capture.run()
        self.assertEqual(old.stat().st_mode & 0o777, 0o600)

    def test_force_preserves_transcript_evidence_for_older_records(self):
        from astronoma import capture, history
        self._stage_transcript(finished="2026-08-17T09:00:30+01:00")
        capture.run()
        before = history.load("2026-08-17-0900")
        os.environ["ASTRONOMA_UPDATE_LOG"] = str(Path(self.tmp.name) / "absent.log")
        capture.run(force=True)
        after = history.load("2026-08-17-0900")
        self.assertEqual(after["errors"], before["errors"])
        self.assertFalse(after["partial"])

    def test_captures_only_updates_not_one_off_installs(self):
        from astronoma import capture, history
        capture.run()
        ids = [r["id"] for r in history.all_records()]
        self.assertEqual(ids, ["2026-08-28-2300", "2026-08-17-0900"])

    def test_records_survive_as_files(self):
        from astronoma import capture
        capture.run()
        written = sorted(p.name for p in self.state.glob("*.json"))
        self.assertEqual(written, ["2026-08-17-0900.json", "2026-08-28-2300.json"])

    def test_capture_is_idempotent(self):
        from astronoma import capture
        first = capture.run()
        second = capture.run()
        self.assertEqual(len(first["captured"]), 2)
        self.assertEqual(second["captured"], [])

    def _stage_transcript(self, finished="2026-08-28T23:05:00+01:00"):
        """Place the transcript with the mtime a real update would leave."""
        import shutil
        staged = Path(self.tmp.name) / "omarchy-update.log"
        shutil.copy(FIXTURES / "omarchy-update.log", staged)
        when = datetime.fromisoformat(finished).timestamp()
        os.utime(staged, (when, when))
        os.environ["ASTRONOMA_UPDATE_LOG"] = str(staged)
        return staged

    def test_transcript_attaches_to_newest_session_only(self):
        from astronoma import capture, history
        self._stage_transcript()
        capture.run()
        newest = history.load("2026-08-28-2300")
        older = history.load("2026-08-17-0900")
        self.assertFalse(newest["partial"])
        self.assertTrue(newest["errors"])
        self.assertTrue(older["partial"])
        self.assertEqual(older["errors"], [])

    def test_migrations_attributed_by_marker_mtime(self):
        from astronoma import capture, history
        marker = self.migrations / "1787580187.sh"
        marker.touch()
        when = datetime.fromisoformat("2026-08-28T23:02:00+01:00").timestamp()
        os.utime(marker, (when, when))
        capture.run()
        self.assertIn("1787580187", history.load("2026-08-28-2300")["migrations"])

    def test_transcript_attaches_to_the_update_it_dates_to(self):
        from astronoma import capture, history
        # Written during the August 17th update, not the newest one.
        self._stage_transcript(finished="2026-08-17T09:00:30+01:00")
        capture.run()
        self.assertTrue(history.load("2026-08-28-2300")["partial"])
        self.assertFalse(history.load("2026-08-17-0900")["partial"])
        self.assertTrue(history.load("2026-08-17-0900")["errors"])

    def test_history_without_pacman_log_is_empty_not_broken(self):
        from astronoma import capture
        os.environ["ASTRONOMA_PACMAN_LOG"] = "/nonexistent/pacman.log"
        result = capture.run()
        self.assertEqual(result["captured"], [])
        self.assertEqual(result["sessions"], 0)


class HistoryTests(TempEnv):
    def test_rejects_unsafe_record_id(self):
        from astronoma import history
        with self.assertRaises(ValueError):
            history.save({"id": "../../escape"})

    def test_corrupt_record_is_skipped_not_fatal(self):
        from astronoma import capture, history
        capture.run()
        (self.state / "2026-08-28-2300.json").write_text("{ not json")
        remaining = [r["id"] for r in history.all_records()]
        self.assertEqual(remaining, ["2026-08-17-0900"])

    def test_no_history_yields_no_latest(self):
        from astronoma import history
        self.assertIsNone(history.latest())


class ReleaseTests(TempEnv):
    def test_malformed_cache_entries_are_ignored(self):
        from astronoma import releases
        self.cache.mkdir(parents=True, exist_ok=True)
        (self.cache / "releases.json").write_text(json.dumps({
            "schema": releases.CACHE_SCHEMA,
            "fetchedAt": 9999999999,
            "releases": [None, "bad", {"tag": "v4.0.1", "name": "v4.0.1"}],
        }))
        items, _ = releases.load()
        self.assertEqual([item.tag for item in items], ["v4.0.1"])

    def _seed_cache(self, fetched_at=None):
        import time
        from astronoma import releases
        self.cache.mkdir(parents=True, exist_ok=True)
        (self.cache / "releases.json").write_text(json.dumps({
            "schema": releases.CACHE_SCHEMA,
            "fetchedAt": fetched_at or int(time.time()),
            "releases": [
                {"tag": "v4.0.1", "name": "v4.0.1", "publishedAt": "", "body": "b", "url": ""},
                {"tag": "v4.0.0", "name": "v4.0.0", "publishedAt": "", "body": "b", "url": ""},
                {"tag": "v3.8.4", "name": "v3.8.4", "publishedAt": "", "body": "b", "url": ""},
            ],
        }))

    def test_offline_refresh_serves_cache_and_reports_staleness(self):
        from astronoma import releases
        self._seed_cache(fetched_at=1)
        def explode(*_args, **_kwargs):
            raise urllib.error.URLError("offline")
        releases._fetch, original = explode, releases._fetch
        try:
            items, status = releases.load(refresh=True)
        finally:
            releases._fetch = original
        self.assertEqual([r.tag for r in items], ["v4.0.1", "v4.0.0", "v3.8.4"])
        self.assertTrue(status["stale"])
        self.assertEqual(status["error"], "No network connection")

    def test_no_cache_and_no_network_is_empty_not_fatal(self):
        from astronoma import releases
        def explode(*_args, **_kwargs):
            raise urllib.error.URLError("offline")
        releases._fetch, original = explode, releases._fetch
        try:
            items, status = releases.load(refresh=True)
        finally:
            releases._fetch = original
        self.assertEqual(items, [])
        self.assertTrue(status["stale"])

    def test_crossed_matches_ticket_example(self):
        from astronoma import releases
        self._seed_cache()
        items, _ = releases.load()
        self.assertEqual(
            [r.tag for r in releases.crossed(items, "3.8.4", "4.0.1")],
            ["v4.0.1", "v4.0.0"],
        )

    def test_recent_never_reaches_past_installed(self):
        from astronoma import releases
        self._seed_cache()
        items, _ = releases.load()
        self.assertEqual(
            [r.tag for r in releases.recent(items, "4.0.0", limit=5)],
            ["v4.0.0", "v3.8.4"],
        )

    def test_corrupt_cache_is_ignored(self):
        from astronoma import releases
        self.cache.mkdir(parents=True, exist_ok=True)
        (self.cache / "releases.json").write_text("{{{ broken")
        def explode(*_args, **_kwargs):
            raise urllib.error.URLError("offline")
        releases._fetch, original = explode, releases._fetch
        try:
            items, _ = releases.load()
        finally:
            releases._fetch = original
        self.assertEqual(items, [])


class AgentTests(TempEnv):
    def test_cached_summary_rejects_unsafe_id(self):
        from astronoma import agent
        self.assertIsNone(agent.cached_summary("../../escape"))

    def test_supported_agents_do_not_allow_unattended_tools(self):
        from astronoma import agent
        commands = {item.command: item.argv for item in agent.AGENTS}
        self.assertNotIn("codex", commands)
        self.assertNotIn("opencode", commands)
        self.assertIn("--disallowedTools", commands["claude"])

    def test_state_and_summary_files_are_private(self):
        from astronoma import agent, capture, history
        capture.run()
        record_path = self.state / "2026-08-28-2300.json"
        agent.save_summary("2026-08-28-2300", {"ok": True, "text": "private"})
        self.assertEqual(record_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.state / "summaries" / "2026-08-28-2300.json").stat().st_mode & 0o777, 0o600)
    def test_summarise_without_agent_reports_cleanly(self):
        from astronoma import agent, capture
        capture.run()
        agent.AGENTS, original = (), agent.AGENTS
        try:
            result = agent.summarise("2026-08-28-2300", [])
        finally:
            agent.AGENTS = original
        self.assertFalse(result["ok"])
        self.assertIn("No supported agent", result["error"])

    def test_summarise_unknown_update_reports_cleanly(self):
        from astronoma import agent
        result = agent.summarise("2026-01-01-0000", [])
        self.assertFalse(result["ok"])

    def test_prompt_grounds_in_the_record(self):
        from astronoma import agent, capture, history
        capture.run()
        record = history.load("2026-08-28-2300")
        prompt = agent.build_prompt(record, [
            {"tag": "v4.0.1", "name": "v4.0.1", "body": "Release body here"}
        ])
        self.assertIn("Omarchy 4.0.0 -> 4.0.1", prompt)
        self.assertIn("Release body here", prompt)
        self.assertIn("quickshell", prompt)

    def test_prompt_never_truncates_removals(self):
        from astronoma import agent
        record = {
            "omarchy": {"from": "4.0.0", "to": "4.0.1"},
            "packages": {"removed": [{"name": f"gone{i}"} for i in range(80)],
                         "installed": [], "upgraded": []},
        }
        prompt = agent.build_prompt(record, [])
        self.assertIn("gone79", prompt)


class ReportTests(TempEnv):
    def test_report_without_history_still_offers_recent_releases(self):
        from astronoma import report, releases
        self.cache.mkdir(parents=True, exist_ok=True)
        (self.cache / "releases.json").write_text(json.dumps({
            "schema": releases.CACHE_SCHEMA,
            "fetchedAt": 9999999999,
            "releases": [{"tag": "v4.0.1", "name": "v4.0.1",
                          "publishedAt": "", "body": "notes", "url": ""}],
        }))
        payload = report.build()
        self.assertIsNone(payload["latest"])
        self.assertEqual(payload["history"], [])
        self.assertEqual([r["tag"] for r in payload["releases"]["recent"]], ["v4.0.1"])

    def test_report_is_json_serialisable(self):
        from astronoma import capture, report
        capture.run()
        json.dumps(report.build())

    def test_detail_of_unknown_update_is_reported_not_raised(self):
        from astronoma import report
        self.assertFalse(report.detail("2026-01-01-0000")["ok"])


class CliTests(TempEnv):
    def _run(self, argv):
        import io
        import contextlib
        from astronoma import cli
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = cli.main(argv)
        return code, json.loads(buffer.getvalue())

    def test_capture_then_history(self):
        code, _ = self._run(["capture"])
        self.assertEqual(code, 0)
        code, payload = self._run(["history"])
        self.assertEqual(code, 0)
        self.assertEqual(len(payload["history"]), 2)

    def test_show_unknown_update_exits_nonzero(self):
        code, payload = self._run(["show", "2026-01-01-0000"])
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])

    def test_pretty_accepted_after_subcommand(self):
        code, _ = self._run(["capture", "--pretty"])
        self.assertEqual(code, 0)


class MenuEntryTests(unittest.TestCase):
    def test_add_preserves_valid_object_without_trailing_comma_and_remove_reverses_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "omarchy" / "extensions" / "omarchy-menu.jsonc"
            config.parent.mkdir(parents=True)
            config.write_text('{\n  "existing": {"label":"Existing"}\n}\n')
            env = {**os.environ, "XDG_CONFIG_HOME": temporary}
            script = str(Path(__file__).resolve().parents[1] / "bin" / "astronoma-menu-entry")
            subprocess.run([script, "add"], env=env, check=True, capture_output=True)
            added = config.read_text()
            self.assertIn('"existing": {"label":"Existing"},', added)
            json.loads(re.sub(r",\s*}", "\n}", added))
            subprocess.run([script, "remove"], env=env, check=True, capture_output=True)
            self.assertEqual(json.loads(config.read_text()), {"existing": {"label": "Existing"}})


if __name__ == "__main__":
    unittest.main(verbosity=2)
