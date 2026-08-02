# Handoff

## 2026-08-02 — broad bug-audit checkpoint 1: relocatable builds

The active repository is the clean default checkout at
`C:\Users\antho\Documents\Codex\2026-08-01\replace-qbittorrnt-on-my-machine-with`,
on `master` with `origin/master` at `9f651d1` when this audit began. There is one
worktree, one local branch, and no stash.

The first baseline native build reproduced a deterministic helper failure: the
ignored `build/CMakeCache.txt` had been created through `Q:\`, so CMake rejected
the checkout's current source and binary paths before compiling. Both one-click
helpers now read `CMAKE_HOME_DIRECTORY` and `CMAKE_CACHEFILE_DIR`, detect a moved
checkout, and recreate only the repository-owned generated `build/` tree. The
POSIX cleanup path additionally refuses any target other than the exact
`$REPO/build` directory. Desktop policy coverage protects both helpers.

Checkpoint verification:

- PowerShell parsed `run.ps1` and `scripts/test-desktop-policy.ps1` with no errors.
- Git Bash parsed `run.sh -n` with no errors.
- `git diff --check` passed.
- All 257 desktop policy and content-integrity checks passed.
- `run.ps1 -NoRun -Jobs 4` detected the stale `Q:\` cache, regenerated the
  build tree, compiled all 433 native/QML-cache steps, linked, deployed the Qt
  runtime, and exited 0.

High-confidence findings queued for the next checkpoints include strict and
single-shot download-size enforcement, hostile Wiki export manifests, transitive
CI action pinning, transfer selection after proxy sorting, and global shortcuts
while a text editor owns focus. Each remains uncommitted until its own fix and
targeted proof are complete.

## 2026-08-01 — Windows Default Apps parity

The Behavior page now exposes upstream qBittorrent's Windows file-association
handoff. Its platform-gated controller launches the fixed
`ms-settings:defaultapps` URI through the system Explorer path, reports launch
failure through the notification center, and leaves Options transaction state
unchanged. The QML surface includes explanatory copy and accessible action text;
non-Windows builds do not show it. Desktop policy coverage and the Experience
feature article record the URI, guard, wiring, failure behavior, and security
boundary.

## 2026-08-01 — verifiable changelog history

The offline changelog now carries the full source commit for every historical
entry and the compact-filter fix. Each entry exposes an accessible short commit
button that opens the exact repository revision; copy and Markdown export keep
the full SHA and link so traceability survives outside the app. Desktop policy
checks require a 40-character identifier, prove every referenced object is a
real local Git commit, and cover the viewer and export wiring. No commit was
guessed: the current entry points to the existing compact-filter completion
commit `6bc2b3f54e88622d48f724d616d93a72d94d0c64`.

## 2026-07-30 — desktop experience, Workspace, appearance, and delivery

The current tree adds the cross-app language/funny-level controls, persistent
notifications, startup dim-sum surprise, changelog viewer, appearance settings,
external-editor integration, and always-on settings history. Workspace schema 2
adds pinning, grouping, overflow, four scoped tab searches, bounded Qt/PCRE2
construction, reviewed bulk close, and sparse global/group/tab appearance with
portable named presets.

Delivery and documentation changes:

- `.github/workflows/release-every-push.yml` now measures the hosted runner,
  reserves an immutable monotonic tag, runs the desktop policy test before
  packaging, uses the required release-token fallback, refuses tag/asset
  mutation, and attaches the built installer plus `har-gow.png` to one full
  release.
- `scripts/test-desktop-policy.ps1` validates required controllers and QML,
  three decoded bundled PNGs, the 34-entry changelog, the case-sensitive
  Cantonese catalog, resource globs, notification migration, and release-policy
  invariants.
- `docs/features` provides categorized indexes and one article per desktop
  feature. README, roadmap, Pages landing source, and curated Wiki source point
  to the same factual corpus.
- Pages, Wiki, release, and source links use the repository's current
  `Ding-Ding-Projects` owner and `ding-ding-projects.github.io` Pages host rather
  than the pre-transfer owner.

Verification at documentation handoff:

- Targeted MSVC object and Qt QML-cache checks passed for language, Workspace,
  tab strip, search, and appearance changes.
- Direct Qt 6.8.3 `qmlcachegen` passed for the complete appearance editor.
- The integrated Windows build completed all 429 steps successfully, and final
  incremental rebuilds passed after the last runtime fixes. Real capture runs
  rendered the changelog, quick Settings at 960×600, forced dim-sum startup,
  Regex Builder, and notification center. The final five-surface pass exited 0
  with no fresh QML warnings; the appearance confirmation width loop and narrow
  notification-search truncation found by that pass were fixed and recaptured.
- The desktop policy test passes 108 checks. Actionlint 1.7.12, PyYAML, and the
  PowerShell parser accept the workflow and all five embedded script blocks.
  The generated Pages corpus contains 42 uniquely sluggified documents; local
  link validation covers all 42 Markdown sources, 3 HTML pages, and 14 landing
  deep links. A disposable Wiki export produced 47 tracked output files,
  including the new Desktop Features page and sidebar entry.
- Case-sensitive Cantonese parity covers 1,178 unique source literals with zero
  missing keys. The final 1,989-key catalog has zero duplicate, placeholder,
  newline, mnemonic, glob, HTML, unit-token, or changelog fact mismatches; all
  37 unique changelog title/change strings are covered.
- Repository release immutability is enabled and the workflow now gates on that
  setting before building, then verifies `isImmutable`, the target commit, the
  installer, and `har-gow.png` after publication.
- Final integration-review findings were resolved in the tree: persisted undo
  action dispatch and Snackbar queuing/cleanup, notification-history journal
  exclusion, bounded changelog regex and localized content/export, filtered
  notification counts, corrected dim-sum eligibility, and keyboard-operable
  Settings controls.
- Installed-package smoke for this new commit, remote Actions, release assets,
  and full live interaction automation remain final integration gates; no
  unexecuted check is treated as success here.
- Start and checkpoint issue scans found no open issues in the origin project or
  the canonical agent-global-memory repository.

Known evidence and platform limits:

- Master tab search covers the app's single WorkspaceManager/strip; there is no
  multi-window Workspace model to aggregate.
- Qt Quick approximates double strike and shadow. Custom underline, outline,
  and glow metadata is preserved but not fully rendered; arbitrary variable
  axes remain backend-dependent.
- Recursive live application of every working target override to all appearance
  editor controls is not proven. Context/keyboard paths and file dialogs are
  cache-compiled but await live UI automation and fresh captures.

## 2026-07-21 — navigation and tab smoke fix

Changed the optional workspace destination handoff in `Main.qml` and
`CentralTabs.qml`, routed Manage Plugins into Search's plugin dialog, and
converted Split Dock details tabs to focusable `AbstractButton` controls.
Added the missing `QtQuick.Controls` import and used the supported Button
accessibility role after the cold-start log exposed the unsupported `TabItem`
role on Qt 6.8.

Verification:

- Build: `run.ps1 -NoRun -Jobs 4` passed after the final source change.
- Visual smoke: all 17 captures from `scripts/capture-ui.ps1` passed after the
  final source change; current inspected captures include 01, 07, 09, 14, and
  17.
- Cold launch: isolated `--capture-ui` process exited 0, wrote its PNG, and
  emitted no startup QML warnings/errors.
- Desktop input: accessibility discovery exposed all five navigation buttons,
  but the host helper blocked injected input with `GetCursorPos failed: Access
  is denied`; this is recorded as a capture/input environment limitation, not
  as a false interaction pass.

The build and smoke output remain under ignored `build\smoke-20260721`.

## 2026-08-01 — compact filter interaction and clipping fix

Split Dock filter delegates now reserve the vertical scrollbar viewport and
constrain translated labels to one elided line. This keeps maximum-playfulness
bilingual status, category, tag, tracker, and tracker-status rows inside the
sidebar while preserving the complete accessible label and full-row click
target. Pointer cursors and keyboard focus make their interactive state clear.

The Split Dock Start, Stop, and Remove toolbar actions now disable when no
torrent is selected instead of appearing actionable and silently doing nothing.
The Add torrent action remains available. Desktop policy assertions cover the
scrollbar reservation, bounded labels, and selection-dependent action state.

## 2026-08-01 — unified application logo

The generated cyan/deep-blue q-and-download mark is now the canonical desktop
and documentation identity. Its magenta key was removed into a transparent
1024 px PNG with preserved clear space. Deterministic derivatives provide the
monochrome tray treatment, README lockup, documentation/PWA mark, and a
seven-size Windows ICO embedded directly in the executable for Explorer,
shortcuts, file associations, and NSIS.

Verification:

- Alpha inspection confirmed transparent and opaque pixels in both canonical
  mark copies, with visible bounds safely inside the 1024 px canvas.
- Pillow decoded all PNG assets and confirmed ICO frames at 16, 24, 32, 48,
  64, 128, and 256 px.
- `scripts/test-desktop-policy.ps1` passed all 136 checks, including canonical
  runtime paths and Windows resource embedding.

## 2026-08-01 — transfer filter-by parity

The transfer toolbar now mirrors upstream desktop field selection for Name,
Save path, Info hash v1, and Info hash v2. Existing case-insensitive wildcard
and Qt regular-expression behavior is preserved and reapplied immediately when
the selected field changes. Partial hash prefixes work independently for v1,
v2, and hybrid torrents without weakening the active status/sidebar filters.

Desktop policy coverage requires the four choices and both hash-generation
branches. The feature article records local-only behavior, empty-hash behavior,
and the remaining runtime acceptance matrix.

## 2026-08-01 — honest asynchronous update checking

The application menu's update action now queries the project's latest stable
GitHub Release asynchronously through the shared download manager. It validates
the immutable build-run-sha identity and compares the monotonic run number with
the build.run.sha identity embedded by release builds. Development builds offer
a valid published release instead of pretending semantic version 5.3.0 proves
equivalence.

Failed downloads, oversized or malformed responses, and unsupported release
objects produce a retryable notification without emitting the misleading
"up to date" result. Concurrent checks are coalesced, response size is bounded,
and parser/comparison logic is isolated from the network path for direct tests.

## 2026-08-01 — verified filters and next global-memory slices

The Split Dock filter failure was traced beyond pointer delivery: QML called
ordinary C++ property setters as methods even though they were not invokable.
Status, category, tag, and tracker rows now assign the writable proxy
properties, while an explicit invokable tracker reset represents All trackers.
A real-input Lowlevel headless-desktop check selected Completed (0) and changed
the transfer table to its no-match result. The installed and locally built
executables matched byte-for-byte, and all 36 resume records remained present.

The first bounded command-palette slice adds Ctrl+Shift+P, accessible keyboard
navigation, shared regex-builder search, core actions, all five destinations,
and direct navigation to all nine Options pages. Pause Session moved to
Ctrl+Alt+P. The palette persists card versus full-window presentation. It does
not yet enumerate every individual setting as a live inline control or
teleport/highlight a precise setting control.

Transfer and log context menus now include keyboard-focused local action search.
Transfer Start, Stop, and Remove display shortcuts from their shared actions;
Log Copy displays Ctrl+C. Remaining global-memory priorities include complete
per-setting command-palette controls/teleport, search and true shortcut labels
across every context menu, systematic bilingual release code names and photos,
full search-builder coverage for settings/properties, universal rendered-element
appearance editing, and broader bulk/export-everything coverage.
