```
   /\
  /  \
  |==|      Astronoma
  |  |      The flight log for Omarchy
 /|  |\
/_|__|_\
   ..
```

Omarchy is a rocket ship. **Astronoma is the flight log.**

It answers one question, every time you open it:

> I just updated Omarchy. What changed, and does any of it matter to me?

Astronoma records what each update did to *this machine* — the Omarchy
version it moved you to, the releases you crossed, the packages it added,
upgraded and removed, the migrations that ran, and anything that went
wrong — and keeps that history after the update log itself is gone.

## What you get

**A bar widget** that shows a rocket when an update has landed that you
have not read yet. Click it for a card with the version change, what the
update did, and the headline changes from the releases you crossed.

**A full flight log** with every captured update, the complete release
notes for each, the package lists, migrations, and warnings. Open it from
the card, or bind a key to:

```bash
omarchy-shell shell toggle astronoma.updates '{}'
```

**An optional impact summary.** If you have an agent CLI installed —
Claude Code, Codex, Gemini CLI or opencode — Astronoma can hand it the
release notes and your machine's package changes and ask what actually
affects you. It is opt-in, cached once produced, and entirely optional:
everything above works with no agent and no API key.

## Install

```bash
git clone https://github.com/kerrjohn/omarchy-astronoma.git
cd omarchy-astronoma
./install.sh
```

That copies the plugin to `~/.config/omarchy/plugins/astronoma.updates`,
captures whatever update history the machine can still evidence, and
enables it. If the bar does not pick it up, run `omarchy-restart-shell`.

To remove it:

```bash
omarchy plugin remove astronoma.updates
```

## Settings

Set on the widget's entry in `~/.config/omarchy/shell.json`:

| Key                  | Default    | What it does                                                        |
|----------------------|------------|---------------------------------------------------------------------|
| `visibility`         | `"unread"` | `unread` shows the rocket only while an unread update is waiting; `always` keeps it in the bar |
| `refreshIntervalSec` | `900`      | How often the widget re-reads local update state                     |

## Where the data comes from

| Source                     | What it provides                                          |
|----------------------------|-----------------------------------------------------------|
| `/var/log/pacman.log`      | Exactly which packages changed, and when. Survives reboots, so it is what Astronoma groups into updates. |
| `/tmp/omarchy-update.log`  | Migrations, warnings and errors — the things only the update transcript records. Cleared on reboot. |
| `~/.local/state/omarchy/migrations/` | Which migrations ran, recoverable from marker mtimes when the transcript is gone. |
| GitHub releases            | Omarchy's user-facing release notes, cached locally.       |

Updates captured before Astronoma was installed are reconstructed from
package history alone. Those are labelled **partial** in the UI, because
their migrations are inferred and their warnings were never recorded.

Nothing is written outside `~/.local/state/omarchy-updates/` and
`~/.cache/astronoma/`, and Astronoma never changes packages — it is an
update *explainer*, not a package manager.

## The CLI

The plugin is a thin presentation layer over a helper you can run
yourself. Every command prints JSON.

```bash
bin/astronoma report          # everything the plugin renders
bin/astronoma capture         # parse logs into update history
bin/astronoma history         # captured updates, newest first
bin/astronoma show <id>       # one update in full
bin/astronoma releases        # Omarchy releases (--refresh to fetch)
bin/astronoma agents          # which agent CLIs are installed
bin/astronoma summarise [id]  # impact summary via an installed agent
```

## Development

```bash
python3 -m unittest discover -s tests -t .
```

Install a working copy with `./install.sh` and reload with
`omarchy-shell shell rescanPlugins`. Note that a **symlinked** plugin
directory does not hot-reload — `install.sh` deliberately copies.

## Licence

MIT. See [LICENSE](LICENSE).
