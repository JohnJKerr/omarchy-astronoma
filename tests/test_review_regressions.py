"""Regression coverage for incremental capture."""

import unittest

from tests.test_astronoma import TempEnv
from astronoma import capture, history


class GrowingCapture(TempEnv):
    def test_existing_session_collects_later_packages(self):
        self.pacman.write_text(
            "[2026-08-28T23:00:00+0100] [PACMAN] Running 'pacman -Syu'\n"
            "[2026-08-28T23:01:00+0100] [ALPM] upgraded first (1 -> 2)\n"
        )
        capture.run_if_changed()
        with self.pacman.open("a") as stream:
            stream.write(
                "[2026-08-28T23:02:00+0100] [ALPM] upgraded second (1 -> 2)\n"
            )
        capture.run_if_changed()
        record = history.latest()
        self.assertEqual([p["name"] for p in record["packages"]["upgraded"]],
                         ["first", "second"])
        self.assertEqual(record["finishedAt"], "2026-08-28T23:02:00+01:00")
        self.assertEqual(capture.run()["captured"], [])


if __name__ == "__main__":
    unittest.main()
