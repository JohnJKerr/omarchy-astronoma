#!/usr/bin/env bash
# Install Astronoma into the Omarchy shell.
#
# Copies this checkout to ~/.config/omarchy/plugins/<plugin id> and asks the
# shell to pick it up. Safe to re-run: it replaces the installed copy in
# place and leaves captured update history alone.
#
#   ./install.sh              install or update, then enable
#   ./install.sh --no-enable   install without touching the bar layout
#   ./install.sh --menu        also add a row to the Omarchy menu
#   ./install.sh --enable-agent-summaries  pre-accept the optional AI feature

set -euo pipefail

PLUGIN_ID="io.github.johnjkerr.astronoma"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
ENABLE=1
MENU=0
AGENT_SUMMARIES=0

for arg in "$@"; do
  case "$arg" in
    --no-enable) ENABLE=0 ;;
    --menu) MENU=1 ;;
    --enable-agent-summaries) AGENT_SUMMARIES=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

command -v python3 >/dev/null || {
  echo "Astronoma needs python3, which is not on PATH." >&2
  exit 1
}

# Running the installed copy of this script would otherwise remove its own
# source tree before the copy begins, leaving a broken or empty plugin behind.
if [[ $(realpath -m -- "$SOURCE_DIR") == $(realpath -m -- "$TARGET_DIR") ]]; then
  echo "Refusing to install over the directory this script is running from: $SOURCE_DIR" >&2
  echo "Run install.sh from a separate checkout instead." >&2
  exit 1
fi

echo "Installing Astronoma to $TARGET_DIR"
# A symlinked plugin does not hot-reload, so always install a real copy.
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
# Every entry is spelled absolutely. A bare `./*.qml` here would glob against
# whatever directory the user ran the script from, so installing from anywhere
# but the checkout silently copied no QML at all and produced a plugin the
# shell could not load.
for entry in "$SOURCE_DIR"/manifest.json "$SOURCE_DIR"/README.md \
             "$SOURCE_DIR"/LICENSE "$SOURCE_DIR"/Model.js \
             "$SOURCE_DIR"/uninstall.sh \
             "$SOURCE_DIR"/assets "$SOURCE_DIR"/bin "$SOURCE_DIR"/helper \
             "$SOURCE_DIR"/*.qml; do
  if [[ -e $entry ]]; then
    cp -r "$entry" "$TARGET_DIR/"
  fi
done
# Bytecode from the developer's interpreter has no business in a plugin
# directory the shell trusts, and a stale .pyc outlives the .py it came from.
find "$TARGET_DIR" -name __pycache__ -type d -prune -exec rm -rf {} +

# A plugin missing its entry points installs and enables perfectly happily,
# then fails to load with nothing but a line on the shell's console. Refuse
# here instead, while there is still someone to tell.
for required in manifest.json BarWidget.qml Flightlog.qml Model.js bin/astronoma; do
  if [[ ! -f $TARGET_DIR/$required ]]; then
    echo "Install is incomplete: $required did not make it to $TARGET_DIR" >&2
    exit 1
  fi
done
chmod +x "$TARGET_DIR/bin/astronoma" "$TARGET_DIR/bin/astronoma-supervisor" \
         "$TARGET_DIR/bin/astronoma-menu-entry"
if [[ -f $TARGET_DIR/uninstall.sh ]]; then
  chmod +x "$TARGET_DIR/uninstall.sh"
fi

if (( AGENT_SUMMARIES )); then
  "$TARGET_DIR/bin/astronoma" agent-summaries enable >/dev/null
  echo "Agent summaries enabled: update evidence and GitHub release notes may be sent to an installed agent when requested."
fi

# Opt-in: the bar rocket hides once an update is read, so a permanent menu
# row is how the flight log stays reachable the rest of the time.
(( MENU )) && "$TARGET_DIR/bin/astronoma-menu-entry" add

# Capture whatever this machine can still evidence, so the plugin has
# something to show the first time it is opened.
"$TARGET_DIR/bin/astronoma" capture >/dev/null || true

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null || true
  if (( ENABLE )); then
    # The rescan is asynchronous, so enabling a plugin id the shell has not
    # caught up with yet fails. Retry briefly rather than swallowing it: a
    # silent failure here leaves the plugin installed, listed, and inert,
    # with only "plugin not enabled, not summoning" on the shell's console
    # to explain why nothing happens.
    for attempt in 1 2 3 4 5; do
      if omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1; then
        ENABLE=0
        break
      fi
      sleep 1
    done
    if (( ENABLE )); then
      echo "Installed, but could not enable it automatically." >&2
      echo "Run: omarchy plugin enable $PLUGIN_ID" >&2
      exit 1
    fi
  fi
  echo "Installed. If the bar does not show it, run: omarchy-restart-shell"
else
  echo "Installed. Start or restart the shell to load it."
fi
