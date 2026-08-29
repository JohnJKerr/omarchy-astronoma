#!/usr/bin/env bash
# Install Astronoma into the Omarchy shell.
#
# Copies this checkout to ~/.config/omarchy/plugins/astronoma.updates and
# asks the shell to pick it up. Safe to re-run: it replaces the installed
# copy in place and leaves captured update history alone.
#
#   ./install.sh              install or update, then enable
#   ./install.sh --no-enable   install without touching the bar layout
#   ./install.sh --menu        also add a row to the Omarchy menu

set -euo pipefail

PLUGIN_ID="astronoma.updates"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
ENABLE=1
MENU=0

for arg in "$@"; do
  case "$arg" in
    --no-enable) ENABLE=0 ;;
    --menu) MENU=1 ;;
  esac
done

command -v python3 >/dev/null || {
  echo "Astronoma needs python3, which is not on PATH." >&2
  exit 1
}

echo "Installing Astronoma to $TARGET_DIR"
# A symlinked plugin does not hot-reload, so always install a real copy.
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
for entry in manifest.json README.md LICENSE Model.js bin helper assets ./*.qml; do
  [[ -e $SOURCE_DIR/$entry ]] && cp -r "$SOURCE_DIR/$entry" "$TARGET_DIR/"
done
chmod +x "$TARGET_DIR/bin/astronoma" "$TARGET_DIR/bin/astronoma-menu-entry"

# Opt-in: the bar rocket hides once an update is read, so a permanent menu
# row is how the flight log stays reachable the rest of the time.
(( MENU )) && "$TARGET_DIR/bin/astronoma-menu-entry" add

# Capture whatever this machine can still evidence, so the plugin has
# something to show the first time it is opened.
"$TARGET_DIR/bin/astronoma" capture >/dev/null || true

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null || true
  if (( ENABLE )); then
    omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  echo "Installed. If the bar does not show it, run: omarchy-restart-shell"
else
  echo "Installed. Start or restart the shell to load it."
fi
