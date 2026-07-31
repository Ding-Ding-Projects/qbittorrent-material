# Handoff

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
