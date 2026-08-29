# Astronoma

```
   /\
  /  \
  |==|      Omarchy is a rocket ship.
  |  |      Astronoma is the flight log.
 /|  |\
/_|__|_\
   ..
```

Omarchy moves fast. Astronoma keeps track of what each update actually did
to *this* machine — the version it moved you to, the releases you crossed,
the packages it added, upgraded and removed, the migrations that ran, and
anything that went wrong — and keeps that record long after
`/tmp/omarchy-update.log` is gone.

It optimises for one question:

> I just updated Omarchy. What changed, and does any of it matter to me?

The QML is deliberately thin. A bundled `astronoma` helper does all the
reading, parsing, persistence and fetching, and prints JSON;
`BarWidget.qml` draws the bar rocket and its summary card, `Flightlog.qml`
draws the full view, and both simply render what the helper returns.

## Features

- **A bar rocket** that appears when an update has landed that you have not
  read yet, and stands down once you have. Click for a card with the
  version change, what the update did, and the headline changes from the
  releases you crossed.
- **A full flight log** — every captured update, the releases crossed with
  their notes rendered natively, migrations, warnings, errors, and a
  package breakdown.
- **Update history that survives reboots.** The `/tmp` transcript is gone
  after a restart, so parsed records are kept in
  `~/.local/state/omarchy-updates/`.
- **Retroactive history.** On first run Astronoma reconstructs the updates
  it can still evidence from package history, so it is useful immediately
  rather than after your next update.
- **A package drill-down** — Upgraded / Installed / Removed, each showing
  `name  old → new`, with a filter for updates that moved a thousand
  packages.
- **Errors and warnings surfaced**, never silently dropped.
- **An optional agent summary.** If Claude Code or Gemini CLI is installed,
  Astronoma can hand it the release notes plus your
  machine's package changes and ask what actually affects you.
- **Offline-safe.** Release notes are cached; a failed refresh shows the
  cached copy and says so.

Everything except the summary works with no agent, no API key, and no
network.

## Install

```bash
omarchy plugin add https://github.com/JohnJKerr/omarchy-astronoma.git
omarchy plugin enable astronoma.updates
```

Plugins land disabled so you can read the code before running it — it runs
unsandboxed inside `omarchy-shell`. Add `--enable --yes` to skip both
prompts.

Astronoma needs `python3`, which Omarchy already installs. Nothing else.

Optionally add a permanent row to the Omarchy menu under **Update →
Changelog**:

```bash
~/.config/omarchy/plugins/astronoma.updates/bin/astronoma-menu-entry add
```

Updating and removing are ordinary plugin commands:

```bash
omarchy plugin update astronoma.updates
# If you added the optional menu row, remove it while the helper still exists:
~/.config/omarchy/plugins/astronoma.updates/bin/astronoma-menu-entry remove
omarchy plugin remove astronoma.updates
```

### From a checkout

To hack on it, clone anywhere and install a copy:

```bash
git clone https://github.com/JohnJKerr/omarchy-astronoma.git
cd omarchy-astronoma
./install.sh --menu
```

`install.sh` copies rather than symlinks on purpose: a symlinked plugin
directory does not hot-reload, and the shell will keep running stale QML.

## Opening it

On the default `unread` visibility the rocket leaves the bar once you have
read an update. The flight log is still loaded and reachable:

- **Omarchy menu** — Update → Changelog, if you added the row above.
- **A keybinding** in `~/.config/hypr/bindings.lua`:

  ```lua
  o.bind("SUPER + SHIFT + U", "Changelog", "omarchy-shell shell toggle astronoma.updates '{}'")
  ```

- **A terminal** — `omarchy-shell shell toggle astronoma.updates '{}'`.
- Or keep the rocket in the bar permanently with `visibility: "always"`.

## Interactions

- **Bar icon**: left = summary card, right = full flight log, middle =
  refresh.
- **Card**: `f` opens the flight log, `r` refreshes, Esc closes.
- **Flight log**: `↑`/`↓` or `j`/`k` move through history, `p` jumps to the
  package breakdown, `r` refreshes, Esc closes.
- **IPC**: `omarchy-shell astronoma <open|close|toggle|refresh>` for the
  flight log, `omarchy-shell astronoma.bar <open|close|toggle|refresh|status>`
  for the card.

Summarising has no keyboard shortcut on purpose. The flight log takes
exclusive keyboard focus, and a summary costs a real agent run, so the
button is the only way to start one.

## Settings

Settings live on the widget's entry in `~/.config/omarchy/shell.json` and
can be set with `omarchy bar set astronoma.updates <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `visibility` | `"unread"` | `"unread"` shows the rocket only while an update you have not opened is waiting; `"always"` keeps it in the bar |
| `refreshIntervalSec` | `900` | How often the widget re-reads local update state. The network refresh happens when you open the card, not on this timer |

```bash
omarchy bar set astronoma.updates visibility always
omarchy bar set astronoma.updates refreshIntervalSec 300 --json
```

Numbers need `--json`, or they land in `shell.json` as strings.

Astronoma writes only to `~/.local/state/omarchy-updates/` (update records,
agent summaries, and which update you have read) and `~/.cache/astronoma/`
(the release cache). Removing the plugin leaves both; delete them by hand if
you want them gone. Machine-specific state and summaries are stored with
user-only permissions.

Agent summaries are opt-in and run only when you press the summary button.
They are disabled by default. The first press shows what data will be sent;
a second, explicit **Enable and summarise** press records consent and starts
the agent. No configuration-file editing is required. Revoke consent with
`bin/astronoma agent-summaries disable`.
Release notes and local update evidence are treated as untrusted input:
Claude Code is launched with tools disabled, while Gemini's non-interactive
mode cannot approve tool calls. Both run from an empty temporary directory.
Astronoma deliberately does not invoke general-purpose agents that cannot
guarantee a non-tooling run.

## Data

| Source | What it provides |
|---|---|
| `/var/log/pacman.log` | Exactly which packages changed, and when. World-readable and survives reboots, so it is what Astronoma groups into updates. |
| `/tmp/omarchy-update.log` | Migrations, warnings and errors — what only the update transcript records. Cleared on reboot. |
| `~/.local/state/omarchy/migrations/` | Which migrations ran, recovered from marker mtimes when the transcript is gone. |
| GitHub releases | Omarchy's user-facing release notes, cached locally. |

pacman's log has no notion of "an update", so Astronoma groups transactions
that run back to back into one — which is what an Omarchy update looks like
from the log's point of view. The transcript is matched to the update it
dates to by its mtime.

Updates captured before Astronoma was installed are reconstructed from
package history alone. They are labelled **partial** in the UI, because
their migrations are inferred and their warnings were never recorded.

Astronoma never changes packages. It is an update *explainer*, not a
package manager.

## The CLI

The plugin is a presentation layer over a helper you can run yourself.
Every command prints JSON.

```bash
bin/astronoma report          # everything the plugin renders
bin/astronoma capture         # parse logs into update history
bin/astronoma history         # captured updates, newest first
bin/astronoma show <id>       # one update in full
bin/astronoma releases        # Omarchy releases (--refresh to fetch)
bin/astronoma agents          # which agent CLIs are installed
bin/astronoma agent-summaries # consent status; add enable or disable
bin/astronoma summarise [id]  # impact summary via an installed agent
bin/astronoma seen [id]       # mark an update as read
```

Add `--pretty` to any of them.

## Development

```bash
python3 -m unittest discover -s tests -t .   # 51 tests, no dependencies
omarchy plugin validate .                    # manifest against the schema
./install.sh && omarchy-restart-shell        # install and reload
```

Adding support for another agent CLI is one entry in `AGENTS` in
`helper/astronoma/agent.py`.

## Licence

MIT. See [LICENSE](LICENSE).
