# qBittorrent Material brand assets

The product mark is a rounded cyan and deep-blue lowercase **q** whose tail
becomes a download arrow. It was created specifically for this project and is
distributed under `GPL-3.0-or-later` with the rest of the source tree.

## Files

| Asset | Best use |
| --- | --- |
| `logo-mark.png` | Canonical 1024 px transparent app mark, window icon, normal tray icon, PWA icon, and compact navigation |
| `logo-monochrome.png` | Ink-color silhouette for the monochrome tray preference |
| `logo-horizontal.png` | Repository and release-page header lockup |
| `qbittorrent-material.ico` | Multi-resolution Windows executable, shortcut, association, and installer icon |
| `qbittorrent-material.rc` | Windows resource declaration consumed by CMake |

The documentation site keeps a copy of the canonical mark at
`docs/assets/logo-mark.png`, allowing GitHub Pages and the PWA manifest to serve
the same identity as the desktop application.

## Usage rules

- Preserve the transparent clear space around the mark; do not crop to the
  painted bounds.
- Use the full-color mark at 24 CSS pixels or larger. Prefer the monochrome
  asset for constrained one-color system surfaces.
- Do not rotate, stretch, or recolor individual parts of the mark.
- When the mark is decorative, use an empty HTML `alt` attribute to avoid a
  duplicate accessible name next to the visible product wordmark.

## Runtime resource paths

The application bundles the normal mark at `:/branding/logo-mark.png` and the
monochrome treatment at `:/branding/logo-monochrome.png`. Qt uses them for the
global window icon and system tray. On Windows, the resource compiler also
embeds `qbittorrent-material.ico` into the executable, which makes the same mark
available to Explorer, Start-menu shortcuts, file associations, and NSIS.

## Source and reproducibility

The canonical raster was produced from the project-owned generated artwork by
removing its solid chroma background, fitting the visible mark inside a 1024 px
transparent canvas, and preserving a clear-space margin. The horizontal,
monochrome, documentation, and ICO variants are deterministic mechanical
derivatives of that canonical raster.
