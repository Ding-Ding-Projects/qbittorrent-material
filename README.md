<p align="center">
  <img src="resources/branding/logo-horizontal.png" width="620" alt="qBittorrent Material">
</p>

<p align="center">
  <a href="https://ding-ding-projects.github.io/qbittorrent-material/">Material documentation site</a>
  ·
  <a href="https://github.com/Ding-Ding-Projects/qbittorrent-material/wiki">GitHub Wiki</a>
  ·
  <a href="https://github.com/Ding-Ding-Projects/qbittorrent-material/releases">Windows installers</a>
</p>

# qBittorrent Material

A ground-up rewrite of [qBittorrent](https://www.qbittorrent.org/) with a **Qt 6 / QML** front end styled entirely with **Material Design** (Qt Quick Controls 2 Material style). Every window and every dialog is Material.

- **Language:** C++20 (engine + model layer) and QML (all UI)
- **Engine:** wraps `libtorrent-rasterbar` 2.x
- **UI:** Qt Quick Controls 2, Material style, System + Light + Dark themes
- **Goal:** feature-for-feature clone of qBittorrent's desktop client, rebuilt as Material Design

## Status

The native desktop interface is fully rewritten in Qt Quick/Material: the shell,
all five workspaces, settings, shared controls, and dialogs use the same design
system in System, Light, and Dark modes. Backend parity and edge-case coverage
remain tracked in [`docs/FEATURE_SPEC.md`](docs/FEATURE_SPEC.md).

Cross-app experience, Workspace, appearance, and delivery behavior is indexed
in [`docs/features/README.md`](docs/features/README.md), with one factual article
per feature and explicit verification limits.

## Native Material workspace

The rewritten desktop shell follows one compact, data-first system: a 64px
command bar, persistent 248px workspace navigation, 24px content gutters,
flat bordered panels with 24px corners, 40px controls, and a 32px status
footer. Transfers, Search, RSS, Execution Log, and the personal Workspace stay
one click away; Options opens as the shared settings surface.

System theme follows the operating system, with explicit Light and Dark modes
available. The light palette uses the supplied cool-neutral Material tokens;
the dark palette uses their Google Material counterparts. Both retain visible
focus, semantic transfer states, and compact monospace operational data. Quick
Settings persists density, seed color, installed UI font, font scale and weight,
and reduced motion, and applies those values to the running interface.

The shell's menu bar, header commands, and Material tray menu invoke shared
actions. Header icon controls, the Add/navigation rail, and status-filter chips
are keyboard reachable, expose descriptive accessible names, and show a clear
focus ring. The Behavior-page tray-icon choice is staged with the Options
transaction: **Apply** commits and refreshes the native tray icon, while
**Cancel** preserves the active icon.

The About dialog renders its bundled GPL notice directly from the QRC resource
bundle. Peer-country flags resolve through
the registered `image://flags` provider; flag SVGs are optional, and an absent
asset intentionally becomes a transparent placeholder rather than a broken
image.

Navigation and details tabs use focusable controls with a single destination
handoff, so optional Search/RSS/Log workspaces are enabled before selection and
the application-menu plugin action opens the same Search plugins dialog as the
visible Search workspace button.

## Desktop experience

English, playful Hong Kong-style Cantonese, and compact bilingual modes switch
live. English and Cantonese each have an independently persisted funny-level
slider from 1 to 5; the disclosure states that voice styling reaches errors and
warnings while facts stay unchanged.

Non-decision messages use a bottom-right notification stack backed by a
persistent, searchable 200-entry notification center. Information, success, and
progress cards auto-dismiss; warnings and errors wait for dismissal. The header
also opens Git-backed action and settings history, and settings history remains
always on.

An eligible launch has one fresh 1% chance to show a non-blocking, eight-second
dim-sum card from three bundled local photos. It is skipped on first run,
capture, and blocking flows and can be disabled permanently. The About surface
contains the complete bundled changelog with typed locale/ISO dates, calendar
range selection, composed plain-text or Qt-regex search, copy, and Markdown
export.

Quick Settings detects common Windows editors, accepts a custom executable, and
can open the managed Workspace without using a command shell. See the
[Experience feature index](docs/features/experience/README.md) and
[External editor integration](docs/features/workspace/external-editor.md).

## Persistent custom workspace

The built-in **Workspace** adds browser-style tabs for personal plain-text pages.
Tab names, content, physical and pinned order, groups, collapse state, active
page, and sparse global/group/tab appearance are restored on launch. An overflow
surface prevents clipping. Tabs can be pinned and groups can be created,
renamed, colored, reordered, collapsed, and searched.

Current-strip, per-group, group-name, and master tab searches each have their
own adjacent Qt/PCRE2 regex builder. Bulk close can match or invert visible tab
labels, previews the affected set, rejects empty or invalid input, and excludes
pinned tabs unless they are explicitly included.

Right-click or `Ctrl+Shift+A` opens the anchored appearance editor; Shift+
right-click is the direct pointer path. It searches installed fonts, exposes
deep typography and geometry controls, translates continuous colors across the
documented color spaces, and imports/exports named presets. Qt rendering limits
for some text effects remain visible and preserved as metadata rather than
being silently dropped.

The application display name can be changed without changing the executable or
profile identity. Workspace edits save atomically and commit automatically to a
managed local Git repository through bundled libgit2—no separate Git install or
remote service is required. Export a compact JSON snapshot or the complete Git
repository with its history, and import either format from the Workspace menu.

See [Custom Workspace Tabs](docs/WORKSPACE_TABS.md),
[Tab management and discovery](docs/features/workspace/tab-management.md), and
[Runtime appearance](docs/features/appearance/runtime-appearance.md).

## Documentation website

The [GitHub Pages site](https://ding-ding-projects.github.io/qbittorrent-material/)
puts the landing page, every Markdown and JSON specification, the complete visual
tour, and a curated wiki into one installable Material interface. It includes
plain-text and regex search, a rule-based filter builder, regex test dialog,
local Markdown/JSON imports, portable wiki/search exports, and the categorized
desktop feature corpus.

The same curated guides and full technical references are mirrored to the
[GitHub Wiki](https://github.com/Ding-Ding-Projects/qbittorrent-material/wiki).
See [`docs/PAGES.md`](docs/PAGES.md) for local preview, content generation,
publishing, and Wiki synchronization.

![qBittorrent Material documentation landing page](docs/images/site/01-landing-desktop.png)

| Embedded wiki search | Regex builder |
| --- | --- |
| ![Embedded documentation search](docs/images/site/02-wiki-search.png) | ![Regex search builder](docs/images/site/03-regex-builder.png) |

![Responsive mobile documentation](docs/images/site/04-mobile-landing.png)

## Screenshots

Captured from the native Windows build with an isolated, empty test profile.
The complete 17-capture visual tour and capture matrix live in
[`docs/SCREENSHOTS.md`](docs/SCREENSHOTS.md). Captures `14`–`17` exercise
the compact 960×640 Split Dock and Card Flow layouts in Light and Dark themes.
The deterministic capture path saves each PNG at its documented logical target.

![Light Transfers workspace in the complete qBittorrent Material shell](docs/images/app/01-main-window.png)

| Dark Transfers workspace | Compact desktop shell |
| --- | --- |
| ![Dark theme Transfers workspace](docs/images/app/02-toolbar-and-filter.png) | ![Compact 960px Transfers layout](docs/images/app/03-filter-sidebar.png) |

| Transfer table | Dark torrent properties |
| --- | --- |
| ![Transfers table and filters](docs/images/app/04-transfer-list.png) | ![Dark Transfers properties panel](docs/images/app/05-properties-tabs.png) |

| Execution Log | Search |
| --- | --- |
| ![Execution Log workspace](docs/images/app/06-statusbar.png) | ![Dark Search workspace](docs/images/app/07-navigation-and-toolbar.png) |

| RSS | Personal Workspace |
| --- | --- |
| ![RSS reader workspace](docs/images/app/08-main-workspace.png) | ![Persistent personal Workspace](docs/images/app/09-custom-workspace-tabs.png) |

| Options · Light | Options · Dark |
| --- | --- |
| ![Options dialog in Light mode](docs/images/app/10-tab-context-menu.png) | ![Options dialog in Dark mode](docs/images/app/11-tab-typography-color.png) |

| Download from URLs | About |
| --- | --- |
| ![Download from URLs dialog](docs/images/app/12-workspace-portability.png) | ![About qBittorrent dialog in Dark mode](docs/images/app/13-restored-workspace.png) |

| Split Dock · Light | Split Dock · Dark |
| --- | --- |
| ![Compact Split Dock layout in Light mode](docs/images/app/14-split-dock-compact.png) | ![Compact Split Dock layout in Dark mode](docs/images/app/15-split-dock-dark-compact.png) |

| Card Flow · Light | Card Flow · Dark |
| --- | --- |
| ![Compact Card Flow layout in Light mode](docs/images/app/16-card-flow-compact.png) | ![Compact Card Flow layout in Dark mode](docs/images/app/17-card-flow-dark-compact.png) |

## Building

On Windows, the helper provisions Git, CMake, Ninja, Python, Qt 6.8.3, vcpkg,
and the remaining repository-local dependencies, then builds with MSVC 2022:

```powershell
# Build and run
powershell -ExecutionPolicy Bypass -File .\run.ps1

# Build only
powershell -ExecutionPolicy Bypass -File .\run.ps1 -NoRun

# Build a self-contained Windows installer
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Package

# Validate desktop catalogs, resources, surfaces, and release policy
powershell -ExecutionPolicy Bypass -File .\scripts\test-desktop-policy.ps1
```

CPack writes local installers and SHA-256 checksums to `build\packages`.
See [`docs/BUILDING.md`](docs/BUILDING.md) for prerequisites, manual CMake
commands, and Linux/macOS instructions.

## Continuous releases

Every branch push and manual dispatch runs desktop policy checks and a Windows
installer build on GitHub Actions using `windows-2022` and Qt 6.8.3. A successful
run publishes one immutable, uniquely tagged, full release for that exact
commit. It contains the real NSIS installer and the bundled Shrimp dumpling ·
蝦餃 PNG identified in the release notes. A failed test publishes no release,
and the workflow never clobbers an earlier tag or asset.

See [Immutable Windows Releases](docs/features/delivery/windows-releases.md) for
the test, token, asset, and verification contract.

## License

GPLv3+, matching upstream qBittorrent.
