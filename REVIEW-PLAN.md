# Astronoma review and hardening handoff

## Execution contract

The user requested a full review covering dead code, module interfaces, security,
and performance, then asked for a plan instead of further implementation.
Work on branch `1.1.1`. Implement **one issue at a time**, validate it, and commit
that issue before starting the next. Split the steps below where indicated.
Preserve unrelated changes. Publishing, pushing, installing into the user's
desktop, and restarting their shell are separate from making local commits.

Apply the supplied `runtime-boundary-hardening` skill throughout implementation.
For each ingress, record producer → transport → parser → sink → cleanup/approval,
including identity, limits, deadline, schema, failure behavior, and proving tests.
The limits proposed below are starting points to validate against legitimate
large histories; existing limits are identified separately.

Reviewed implementation HEAD: `0c52d0d5db1c4df64c2d583effaff836c56940bd`.
Original review baseline: `98781e680c3a51a4253891a43758e5f10133eca4`.
The worktree was clean before this plan was added. The README is the behavior
specification; no separate originating issue or repository AGENTS.md was found.

## Already committed — retain and re-review

| Commit | Issue addressed | Validation performed |
| --- | --- | --- |
| `035a054` | Process cleanup now kills surviving group members even when the leader exits first; shared supervision moved from `agent.py` into `process.py`. | Security tests, including a TERM-ignoring descendant; full suite subsequently passed. |
| `93271b9` | Capture incorporates packages appended to an already recorded update. | Growing-log regression and capture tests. |
| `f79e068` | Report failures are visible; default bar remains accessible before its first successful load. | QML parsing and whitespace checks. |
| `0c52d0d` | History selection follows record identity across refreshes and clears removed records. | Five extracted-JavaScript scenarios, QML parsing, whitespace checks. |

The full Python suite passed 103 tests after the first three fixes were present;
the fourth was subsequently checked with targeted JavaScript/QML validation.
`omarchy plugin validate .` passed. QML lint with the shell import root reported
existing runtime-type warnings but no syntax errors or unused imports.
No live installation, restart, agent invocation, or remote security approval
was performed. Temporary checks under `/tmp` are supporting evidence, not
durable tests: reproduce relevant cases in the maintained suite.

## Boundary inventory and required contracts

| Flow | Current evidence and required work | Failure behavior and proving tests |
| --- | --- | --- |
| pacman log → file descriptor → package/session parser → persisted history | `pacmanlog.read()` uses ordinary unbounded text reads. Require a regular file owned by root or the current user, no-follow/nonblocking descriptor reads, and byte/line/item limits before accumulation. Proposal: 64 MiB source, 64 KiB line, 250,000 parsed events, with an explicit retained-history policy if exceeded. | Reject special files/symlinks without hanging; surface over-limit evidence instead of silently claiming complete history. Test FIFO, growing file, long line, and exact/over limits. |
| update transcript → descriptor → ANSI/parser → history and agent prompt | Existing source limit is 32 MiB, with leaf no-follow, ownership/type checks, and descriptor-derived mtime/hash. Parser lists and individual strings are not constrained to the persisted record schema before saving. | Preserve valid prior history on rejected input and show that transcript evidence was unavailable. Test unique-entry floods, long warnings/migrations, ANSI-heavy input, and output-schema compatibility. |
| migration directory → enumeration/stat → inferred migrations → history | `_migrations_between()` uses `list(iterdir())` and pathname `stat()` per session; follows leaf symlinks and rescans for every update. Require descriptor-relative enumeration, owner/type policy, and bounded entries. Proposal: 4,096 markers, sampled once per capture. | Reject unsafe markers and disclose incomplete inference; test symlink swap, nonregular entries, oversized directory, and timestamp-window edges. |
| private state/cache → verified directory/leaf → JSON/schema → reports, consent, summaries | Existing no-follow traversal, private modes, byte limits, atomic rename/fsync, and several exact schemas are useful. Directory ceilings occur after `listdir()` allocation; tree hardening has no entry budget. History can accumulate up to 4,096 × 2 MiB before a report is bounded. | Enforce limits while consuming; consent fails closed, display data retains last-good/empty behavior. Test directory flood, aggregate history size, deep JSON, malformed scalars, and permission/descriptor cleanup. |
| GitHub → HTTP response → release parser/cache → plain-text notes | Existing limits: 8 MiB response/cache, 30 releases, 256 Ki characters/body, 2,048 characters/metadata; request socket timeout 15 seconds. Verify total deadline, response decoding/schema failure, cache-write failure, and fetch policy. | Failed refresh retains cached notes with a visible status. Test slow trickle, malformed/deep JSON, empty/failing fetch, and cache write denial. |
| helper/agent → process group/pipes → JSON/text → QML collectors | Shared supervision has output ceilings and a monotonic deadline. Agent: 180 seconds, 256 KiB stdout, 64 KiB stderr. Helper: 30 seconds (190 for summarise), 16 MiB stdout, 64 KiB stderr. Nested process groups and QML cancellation still need end-to-end verification. | TERM/grace/KILL/reap on timeout, overflow, cancellation, and successful parent exit with descendants. Test both streams, closed pipes, nested supervisors, cancellation, and process-start/setup failures. |
| pacman version command/version file → subprocess/file → version parser → report | `versions.py` still uses `subprocess.run(capture_output=True)` and unbounded `read_text()`. Bring these under bounded interfaces with root/current-user ownership for packaged files. Proposal: 16 KiB per stream/file, short total detection deadline shared across candidates. | Report unknown version on failure while retaining package history. Test stdout/stderr flood, timeout, invalid encoding, FIFO/symlink, oversized version file. |
| releases/logs/agent text → JSON → dynamic QML text → desktop renderer | Most sinks explicitly use `Text.PlainText`; verify inherited/custom sinks and all failure paths too. `Service.applyReport()` currently accepts arrays or any object. Detail failures still lack a clear error state. | Schema-invalid reports retain the last good model; untrusted markup remains inert; requested-detail failures cannot masquerade as another update. Test HTML/images/entities/Markdown/URLs and malformed report/detail payloads. |
| menu/install/uninstall → mutable config/plugin paths → text edits/copy/delete → desktop configuration | Menu editing has confirmed parsing defects and ordinary pathname writes. Install/uninstall use pathname recursive operations; verify symlink ancestors, source/target overlap, and purge scope rather than assuming trusted paths. | Refuse unsafe/ambiguous input without partially damaging existing files. Test outside sentinels, symlink components, interrupted writes, malformed JSONC, and purge/non-purge behavior in disposable roots. |
| CI actions → pinned source → runner → tests/release | Existing third-party actions use full SHAs with release comments. SHA-to-upstream provenance and any remote approval chain were not verified during this review. | Verify immutable references against upstream; retain any security-review-required marker until review passes on the exact commit. |

## Ordered fixes

### 1. Preserve menu JSONC structure — confirmed correctness defect

Files: `bin/astronoma-menu-entry`, menu tests.

`content.partition("//")` mistakes URL content for comments. The row replacement
and removal regexes also assume the existing Astronoma entry occupies one line.

Implement a small string/comment-aware structural edit that finds the top-level
property and its full value, preserves surrounding comments, and places commas
outside strings. Validate the document before writing; malformed input must be
left untouched with a failure result. Avoid a broad text rewrite of user config.

Completion: add/re-add/remove round trips pass for URL actions, escaped quotes,
line/block comments, multiline entries, nested objects, first/middle/last/only
property positions, trailing commas, and malformed input. Commit this parsing
fix separately from file-access hardening in step 7.

### 2. Verify complete subprocess lifecycle — open hardening work

Files: `helper/astronoma/process.py`, `bin/astronoma-supervisor`,
`BoundedProcess.qml`, `Service.qml`, process tests.

Re-review `035a054` with whole-tree tests. The outer supervisor and inner agent
each create a session; killing the outer group does not directly kill the agent
group. Prove cancellation reaches inner cleanup before outer escalation. QML
currently uses the same 30/190-second deadlines as the helper; allow sufficient
outer grace for helper cleanup rather than racing equal deadlines.

Cover failures during signal-handler/selector setup after `Popen`, repeated
cancellation during cleanup, and descendants surviving a successful leader.
Keep handlers, pipes, selectors, and direct children cleaned up on every path.
Move version-command execution to the shared interface in a separate follow-up
commit with the version-specific limits from the inventory.

Completion: process-tree tests prove no live descendant remains for every
termination mode, including nested supervision. Test stderr overflow as well as
stdout overflow, and launch errors without uncaught desktop-facing tracebacks.

### 3. Bound filesystem consumption before allocation — observed gaps

Files: `paths.py`, `pacmanlog.py`, `capture.py`, `versions.py`.

Split into separate commits: private-directory enumeration/cleanup; package-log
reads; migration reads; version-file reads. Reuse descriptor-based primitives
where their ownership policies match. Packaged root-owned logs are different
from user-private state and must not be forced through a current-user-only rule.

Replace eager directory materialization with bounded iteration. Close the child
descriptor in `harden_private_tree()` even if `fstat` or `fchmod` raises. Handle
concurrent directory creation safely. Audit lock identity and blocking policy,
including special files and contention through the direct CLI.

For capture source signatures, replace pathname `stat()` assumptions with
descriptor-derived identity and ensure a race cannot stamp unconsumed input as
captured. A signature check is a cache optimization, not validation of the input.

Completion: exact/over-limit and adversarial file tests pass, outside sentinels
remain unchanged, descriptor counts remain stable under injected failures, and
budget failures have explicit report semantics rather than silently erased data.

### 4. Make structured-data and aggregate budgets consistent — observed gaps

Files: `history.py`, `paths.py`, `updatelog.py`, `releases.py`, `agent.py`, `cli.py`.

Separate commits for history/parser consistency, JSON rejection, and aggregate
report/prompt budgets. Existing `history.save()` validates only the ID, whereas
loading enforces the full record schema and 2 MiB ceiling: capture can write data
that it will subsequently ignore. Align producer limits with readers and retain
an explicit partial/error indication when evidence exceeds policy.

Handle deeply nested JSON failures predictably on all supported Python versions;
reject inappropriate numeric/schema values and bound work before model creation.
Decide whether the currently unused `json_within_limits()` earns a real call site
or should be removed; adding a post-parse check alone is not a producer limit.

Choose and document a total history budget (proposal: 32 MiB decoded source
bytes per operation), plus incremental report encoding or another bounded
strategy. `_emit()` checks only after `json.dumps()` has allocated the output.
Build agent prompts to a measured UTF-8 budget, and avoid exceeding the operating
system's single-argument limit for large release/package sets. If moving prompts
to stdin, preserve immediate EOF behavior and bounded nonblocking input delivery.
Align accepted live summary size with the serialized cache's read limit.

Completion: every accepted saved record/summary can be loaded; oversized history,
prompts, JSON nesting, non-ASCII text, and string/cardinality limits fail cleanly
without unbounded accumulation or silent loss of previously valid records.

### 5. Keep background refresh local — confirmed specification mismatch

Files: `releases.py`, `report.py`, `cli.py`, related tests and README.

`releases.load(refresh=False)` fetches when its cache expires or is absent, so
the bar's supposedly local timer can contact GitHub. Make cache-only reporting
explicit while preserving deliberate fetches on opening/refreshing the UI and
the documented CLI behavior. Avoid silently changing unrelated callers.

Follow up separately on total HTTP deadlines and refresh-failure throttling.
The current minimum interval relies on successful cached fetch time, so repeated
failed/empty requests are not necessarily throttled. Preserve cached data when
writing new cache data fails and expose the failure status.

Completion: no network call on timer reports with missing or expired cache;
opening fetches; repeated opens respect policy; explicit CLI bypass works;
slow/failing responses and cache-write failures preserve usable cached output.

### 6. Remove avoidable parsing and rendering work — measured checks required

Make each optimization its own commit and preserve the current grouping rules.

- `pacmanlog._mark_aur()` scans all AUR windows per change; `sessions()` scans all
  commands per session. Use sorted timestamps and bisect/sweeps, retaining the
  inclusive time windows. Verify unsorted input and interval endpoints against
  the old algorithm on representative data; report benchmark results.
- `updatelog.parse()` deduplicates packages and migrations with list membership.
  Use companion sets while keeping first-seen output order. Test repeated and
  all-unique transcripts; avoid a test that merely asserts the implementation.
- `Flightlog.qml` passes full release models to both hidden `FutureReleases`
  pages, whose Repeaters lay out release bodies eagerly. Gate the models or use
  active Loaders while preserving navigation, focus, and scrolling. Verify no
  body delegates are created for unopened catalogues and measure first-open work.

### 7. Harden menu and lifecycle file mutations — verification plus fixes

Files: `bin/astronoma-menu-entry`, `install.sh`, `uninstall.sh`, lifecycle tests.

First harden menu read/write: bounded input, descriptor-verified parent/leaf,
explicit ownership/mode policy, private sibling temporary file, atomic replace,
and durability where appropriate. Then review install and uninstall separately.
Test symlinked ancestors, aliased/overlapping source and target, failed copies,
and environment-controlled purge paths. Constrain deletion to the intended
plugin/data trees. Decide safe behavior for symlinked user config explicitly.

Completion: disposable-root tests prove user comments/settings/history survive
normal lifecycle operations, unsafe paths cannot alter an outside sentinel, and
copy/edit failures leave a recoverable installation. Include installation from
outside the checkout and uninstall with and without purge.

### 8. Finish UI data/error contracts and clarify detail ownership

Files: `Service.qml`, `Flightlog.qml`, optionally a dedicated detail component.

First validate report top-level type/schema and required shapes before replacing
the last good report. Add explicit selected-detail failure state: currently a
failed `show` clears the detail and can leave misleading empty/fallback content.
Ensure errors from stale requests cannot overwrite the newly selected record.
Test the `0c52d0d` selection cases in a maintained harness, including an in-flight
request when history becomes empty and a record changes under the same ID.

Only then consider extracting selected-detail orchestration from a general
`Service` instance. The useful interface is load/select, record, loading, error,
and summary result; avoid duplicating request lifecycle or creating pass-through
abstractions. Keep extraction separate from behavior fixes.

Audit every dynamic text sink, including inherited widgets, for inert formatting.
Completion: malformed objects/arrays, command failures, and malicious markup
retain coherent content and visible errors; last-good report behavior survives.

### 9. Prune confirmed dead code and stale comments

One focused cleanup commit after behavioral changes settle. Re-run reference
searches before removal, accounting for CLI/public callers and dynamic QML use.

Confirmed unreferenced at reviewed HEAD: `Flightlog.omarchyPath`,
`Flightlog.selectedRow`, `Service.hasAnything`,
`assets/release-astrolabe.png`, `assets/release-telescope.png` (layered replacements
are used). Candidates requiring final interface judgement: `history.unread_id`,
`paths.json_within_limits`, and unused imports in Python modules.

Correct `PackageSection.qml`'s opening ListView/recycling comment to describe its
capped Repeater; update the README's stale test count or remove the count.
Review comments claiming default `unread` visibility or transcript-only fallback
behavior that no longer matches callers. Keep this cleanup behavior-neutral.

Completion: reference search, imports/compilation, tests, manifest validation,
and QML parsing pass; assets still referenced by sprites and overlays remain.

### 10. Verify agent capability restrictions and CI provenance

This is verification work, not a claim of a demonstrated exploit. Inspect the
installed CLI versions and authoritative documentation for the exact Claude and
Codex controls. Prove no tools, hooks, plugins, project/user instructions, or
unintended network tools can be enabled by prompt data or configuration. An empty
working directory alone is not a sandbox. Fail closed for unsupported controls;
retain explicit revocable consent and disclose the actual data sent.

Use stub/fake-agent tests for local regression coverage. Any real provider run
must use appropriate consent and a harmless fixture. Test delimiter injection,
provider selection, revoked consent, and cached-summary behavior independently.
Check that changed update evidence cannot indefinitely reuse a stale summary;
if confirmed, key/invalidate cached summaries by the evidence used to build them.

Verify existing action SHAs against upstream releases. If a commit-bound security
approval workflow exists, its completion requires remote current HEAD = validation
SHA = decoded security-baseline SHA. No such approval was established here.

## Final validation and handoff

For each issue, record its commit, regression evidence, and any remaining unknown.
After the final implementation commit, run focused adversarial tests, the whole
suite, supported-version CI, Python compilation, shell syntax checks, QML
lint/parsing, manifest validation, and `git diff --check`. Re-review the complete
range from the original baseline for both README behavior and coding standards.

Useful local commands:

```bash
python3 -m unittest discover -s tests -t .
python3 -m compileall -q helper
bash -n install.sh uninstall.sh
omarchy plugin validate .
git diff --check
git status --short
```

QML lint needs an import root containing `qs` pointing at the Omarchy shell; the
README documents the setup. Distinguish runtime-type resolution warnings from
real syntax/property errors. Keep tests hermetic: temporary config/state roots,
blocked network, stubbed Omarchy commands, and a pinned timezone.

For live UI validation, coordinate the install/restart with the user, then check
bar loading/failure/unread states, historical selection, both release catalogues,
summary consent/error states, and all documented IPC targets. Bar changes require
a shell restart. Report unperformed live or remote checks explicitly. A passing
unit suite alone does not establish that every runtime boundary is secure.
