# Windows Desktop Features

This index documents the current Windows desktop application. Each feature has
its own article covering behavior, configuration, failure modes, security or
privacy considerations, and verification. The documentation describes the
native Qt 6/QML Windows app.

## Categories

- [Experience](experience/README.md): language and voice, notifications, the
  startup dim-sum surprise, and the in-app changelog.
- [Workspace](workspace/README.md): browser-style tabs, tab discovery, the
  regex builder, local version history, and external-editor integration.
- [Appearance](appearance/README.md): persisted global appearance and the
  per-tab, per-group, and global workspace appearance editor.
- [Delivery](delivery/README.md): tested immutable Windows installer releases.
- [Transfers](transfers/README.md): transfer-list filtering, bulk selection,
  and scoped multi-format export.

The embedded documentation site indexes these articles through
`docs/content.generated.js`. Run `scripts/generate-pages-content.ps1` after an
article changes.

## HTTP API applicability

These desktop features do not add an HTTP API. A Postman collection would not
exercise them and is therefore not applicable.

## Verification state

The repository policy test validates required desktop files, JSON catalogs,
bundled PNG decoding, resource-discovery rules, localization keys, and release
workflow invariants. Targeted MSVC and QML-cache compilation has passed for the
language and workspace changes. The integrated Windows build passed all 429
steps, and real captures rendered the changelog, quick Settings at 960×600, and
the forced dim-sum surface. Installed-package smoke and unexercised interaction
paths remain release-gate evidence rather than assumptions in these articles.

## Related articles

- [Building qBittorrent Material](../BUILDING.md)
- [Material Design System](../DESIGN_SYSTEM.md)
- [Custom Workspace Tabs](../WORKSPACE_TABS.md)
