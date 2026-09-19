"""Astronoma — the flight log for Omarchy updates.

The QML plugin is presentation only; everything that reads the machine,
persists history, talks to GitHub, or drives an agent lives here and is
reached through the `astronoma` CLI as JSON on stdout.
"""

from .metadata import version as _manifest_version


# The manifest is the release source of truth for both the CLI and the UI.
__version__ = _manifest_version()
