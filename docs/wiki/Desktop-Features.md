# Windows Desktop Features

The current native desktop tree adds cross-app experience controls and a deeper
personal Workspace without introducing a remote service.

## Experience

- English, playful Hong Kong-style Cantonese, and compact bilingual modes
  retranslate live. English and Cantonese have independent persisted funny
  levels from 1 to 5.
- The bottom-right Snackbar stack is non-blocking and feeds a searchable,
  persisted notification center.
- An eligible launch has one fresh 1% chance to show an eight-second card from
  three bundled dim-sum photos. First-run, capture, and blocking flows are
  excluded, and the feature can be disabled.
- About includes the complete bundled changelog with composed date and text or
  Qt-regex filtering, copy, and Markdown export.

## Workspace and appearance

- Schema 2 persists pinned order, groups, group order and collapse, and sparse
  global/group/tab appearance while remaining able to read schema 1.
- Current-strip, per-group, group-name, and master tab search each retain an
  independent adjacent Qt/PCRE2 builder.
- Containing and inverse bulk close share one visible-label predicate, preview
  the affected set, reject empty or invalid input, and exclude pinned tabs by
  default.
- The anchored appearance editor exposes installed-font typography, continuous
  color translation, geometry and state controls, reset scopes, and portable
  named presets. Qt rendering limitations are shown explicitly and preserved as
  metadata.
- App-managed Git history covers Workspace pages, supported actions, and
  settings. Restores append a revision. Nothing is pushed automatically.
- Settings can detect common Windows editors or use a custom executable to open
  the managed Workspace without a command shell.

## Delivery

Every branch push and manual dispatch runs desktop policy checks before building
and testing the real NSIS installer. A successful run creates one immutable full
release with a unique monotonic tag, the installer, and the bundled Shrimp
dumpling · 蝦餃 image. A failed test creates no release.

## Detailed articles

The [searchable documentation site](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-readme)
contains one article per feature, including behavior, configuration, failure
modes, security/privacy considerations, and verification evidence.

- [Language modes and funny levels](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-experience-language-and-funny-levels)
- [Notification center](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-experience-notifications)
- [Startup dim-sum surprise](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-experience-startup-dim-sum)
- [In-app changelog](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-experience-changelog-viewer)
- [Tab management and discovery](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-tab-management)
- [Search and regex builder](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-search-and-regex)
- [Local version history](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-local-version-history)
- [External editor integration](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-workspace-external-editor)
- [Runtime appearance](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-appearance-runtime-appearance)
- [Immutable Windows releases](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-delivery-windows-releases)

## Verification state

Targeted MSVC and QML-cache checks passed for the language, Workspace, search,
and appearance changes. The integrated Windows build completed all 429 steps,
and real capture runs rendered changelog, quick Settings at 960×600, and forced
dim sum. Installed-package smoke for the new commit, remaining live interaction
paths, and the remote release remain evidence gates and are not predicted here.
