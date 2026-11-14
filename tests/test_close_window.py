"""Close routing at the executable boundary, without a compositor."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CloseWindowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.events = self.base / "events"
        self.events.touch()
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ["PATH"],
                        EVENTS=str(self.events), RESPONSES=json.dumps(["inactive", "inactive"]))
        shell = self.base / "omarchy-shell"
        shell.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
responses = json.loads(os.environ["RESPONSES"])
index = 0 if sys.argv[1] == "astronoma" else 1
with open(os.environ["EVENTS"], "a") as f: f.write(sys.argv[1] + "\\n")
if responses[index] == "error": sys.exit(1)
print(responses[index])
''')
        shell.chmod(0o755)
        hypr = self.base / "hyprctl"
        hypr.write_text('#!' + sys.executable + '\n' + '''import os, sys
with open(os.environ["EVENTS"], "a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")
''')
        hypr.chmod(0o755)

    def run_close(self):
        return subprocess.run([sys.executable, ROOT / "bin/astronoma-close-window"],
                              env=self.env, capture_output=True, text=True)

    def test_open_flightlog_closes_without_dispatching_window_close(self):
        # Arrange
        self.env["RESPONSES"] = json.dumps(["closed", "inactive"])
        # Act
        self.run_close()
        # Assert
        self.assertEqual(self.events.read_text().splitlines(), ["astronoma"])

    def test_inactive_astronoma_preserves_normal_window_close(self):
        # Act
        self.run_close()
        # Assert
        self.assertEqual(self.events.read_text().splitlines(), [
            "astronoma", "astronoma.bar", "dispatch hl.dsp.window.close()",
        ])

    def test_open_bar_card_closes_without_dispatching_window_close(self):
        # Arrange
        self.env["RESPONSES"] = json.dumps(["inactive", "closed"])
        # Act
        self.run_close()
        # Assert
        self.assertEqual(self.events.read_text().splitlines(), ["astronoma", "astronoma.bar"])

    def test_ipc_failure_does_not_close_the_background_window(self):
        # Arrange
        self.env["RESPONSES"] = json.dumps(["error", "inactive"])
        # Act
        self.run_close()
        # Assert
        self.assertEqual(self.events.read_text().splitlines(), ["astronoma"])

    def test_unexpected_response_does_not_close_the_background_window(self):
        # Arrange
        self.env["RESPONSES"] = json.dumps(["unexpected", "inactive"])
        # Act
        self.run_close()
        # Assert
        self.assertEqual(self.events.read_text().splitlines(), ["astronoma"])
