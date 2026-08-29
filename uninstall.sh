#!/usr/bin/env bash
# Remove Astronoma from the Omarchy shell.
#
# The optional menu row lives in the user's own config and points at this
# plugin, so it has to come out before the plugin directory does — once the
# directory is gone there is nothing left to run the removal. Doing both in
# one place is the only way that ordering is not the user's problem.
#
#   ./uninstall.sh              remove the plugin and the menu row
#   ./uninstall.sh --purge      also delete captured history and the cache

set -euo pipefail

PLUGIN_ID="io.github.johnjkerr.astronoma"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
STATE_DIR="${ASTRONOMA_STATE_DIR:-$HOME/.local/state/omarchy-updates}"
CACHE_DIR="${ASTRONOMA_CACHE_DIR:-$HOME/.cache/astronoma}"
PURGE=0

# `omarchy plugin add` installs by cloning, so this script usually lives
# inside the very directory it is about to delete. Everything runs from a
# function: bash parses a function whole before executing any of it, so the
# script is entirely in memory before the rm that removes it from disk.
main() {
  for arg in "$@"; do
    case "$arg" in
      --purge) PURGE=1 ;;
      *)
        echo "Unknown option: $arg" >&2
        exit 2
        ;;
    esac
  done

  # Prefer the installed copy: it is the one whose row is actually in the
  # menu. Fall back to this checkout so an already-removed plugin can still
  # be tidied up after the fact.
  local menu_entry="$TARGET_DIR/bin/astronoma-menu-entry"
  [[ -x $menu_entry ]] || menu_entry="$SOURCE_DIR/bin/astronoma-menu-entry"
  if [[ -x $menu_entry ]]; then
    "$menu_entry" remove
  fi

  if command -v omarchy >/dev/null; then
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TARGET_DIR"
  echo "Removed $TARGET_DIR"

  if (( PURGE )); then
    rm -rf "$STATE_DIR" "$CACHE_DIR"
    echo "Removed captured history ($STATE_DIR) and the release cache ($CACHE_DIR)"
  else
    echo "Kept captured history in $STATE_DIR — re-run with --purge to delete it."
  fi

  if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null || true
  fi
}

main "$@"
