# Documentation Site and Wiki

The project website is a dependency-free Material 3 application published directly from the repository's `master/docs` directory at:

<https://ding-ding-projects.github.io/qbittorrent-material/>

It combines the landing page, screenshot gallery, complete technical corpus, and curated wiki in one installable static site. No server, analytics service, runtime package manager, or search API is required.

## Content model

Canonical content comes from:

- `README.md`
- every Markdown and JSON file under `docs`
- curated guides under `docs/wiki`
- categorized feature articles under `docs/features`

This includes the complete [Custom Workspace Tabs](WORKSPACE_TABS.md) reference
and its shorter task-oriented Wiki guide. The
[Windows Desktop Features](features/README.md) index links one article per
cross-app experience, Workspace, appearance, and delivery feature.

Run the deterministic generator after changing any source document:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generate-pages-content.ps1
```

The command writes `docs/content.generated.js`. The generated bundle is committed intentionally: GitHub Pages can publish the directory as-is without a build workflow or Actions artifact.

## Local preview

Serve the `docs` directory over HTTP so service-worker and file-import behavior match production:

```powershell
py -3 -m http.server 4173 --directory docs
```

Then open <http://127.0.0.1:4173/>.

Opening `index.html` directly still renders the site, but browsers disable some PWA features for `file:` URLs.

## Search modes

The search engine indexes title, path, category, format, headings, and full body text for every embedded document.

- Plain-text search escapes regex syntax by default.
- Regex mode validates patterns and supports case, multiline, dot-all, and Unicode flags.
- Whole-word mode wraps the search expression in word boundaries.
- Filter rules target title, path, category, format, body, or every field.
- Rules combine with all/any logic and support negation.

The regex builder offers token insertion, sample-text testing, match highlighting, and capture-group inspection before applying a pattern.

Regular expressions run in disposable Web Workers so a pathological expression cannot freeze the page. Searches have a 1.2-second deadline, previews have a 600-millisecond deadline, patterns are limited to 320 characters, and preview text is capped at 200,000 characters. A timed-out worker is terminated and the next search starts in a fresh worker.

## Imports and exports

Markdown and text files can be imported as local wiki pages. A versioned wiki JSON bundle can contain multiple pages, while a search-profile JSON file stores the current query, options, and filter rules. Each source file is limited to 2 MB, stored document bodies are capped at 1 MB, and bundles accept at most 500 pages.

Imported documents are stored only in browser local storage. Rendering escapes raw HTML, rejects unsafe URL schemes, and blocks remote images from imported Markdown. GitHub project sites share the owner’s `github.io` browser origin, so other Pages applications under the same owner can technically access that origin storage; do not import secrets. Export before clearing browser storage or moving the workspace to another browser.

## GitHub Wiki synchronization

The separate GitHub Wiki repository is generated from the same canonical content:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\export-github-wiki.ps1 `
  -WikiWorkingTree ..\qbittorrent-material.wiki
```

The exporter writes curated pages, complete references, JSON blueprints rendered as code, navigation, branding, and screenshots. Commit and push those changes from the Wiki repository after review.

## Publishing

GitHub Pages uses `master` and `/docs` as its source. This branch-based
configuration keeps the published site auditable without a
repository-maintained Pages upload workflow. GitHub may create a short-lived
internal `github-pages` artifact during deployment. The installer workflow does
not create, download, or delete Actions artifacts; release assets go directly
to the immutable GitHub Release.

The site includes `.nojekyll`, a web manifest, an offline service worker, project-root-aware `404.html`, and linked sitemap metadata. Pages refreshes automatically after `master` changes.

## Site screenshots

![Material landing page](images/site/01-landing-desktop.png)

| Searchable wiki | Regex builder | Mobile landing |
| --- | --- | --- |
| ![Wiki search results](images/site/02-wiki-search.png) | ![Regex builder](images/site/03-regex-builder.png) | ![Mobile landing page](images/site/04-mobile-landing.png) |

## Native application screenshots

The Pages gallery and root README share all 17 stable captured
`docs/images/app/01`–`17` filenames. Captures `14`–`17` cover compact
960×640 logical Split Dock and Card Flow views in each Light and Dark theme.
Together, the tour covers the shared 64px command bar, navigation,
status footer, Transfers, Search, RSS, Execution Log, Workspace, Options, and
representative dialogs.

The current logical and PNG dimensions are 960×900 for `01`, `02`, and
`06`–`11`; 960×640 for `03` and `14`–`17`; and 960×768 for `04`, `05`,
`12`, and `13`. Keep the intrinsic `width`/`height` attributes in
`index.html` and the `sizes` entries in `manifest.webmanifest` synchronized
with the actual files whenever the gallery is refreshed.

## Visual QA checklist

1. Desktop width at 1440×1000 or larger.
2. Tablet width near 900 pixels.
3. Mobile width at 390 pixels.
4. Light, dark, reduced-motion, and high-contrast preferences.
5. Keyboard-only navigation and visible focus states, including header icon
   buttons, the Add/navigation rail, and status-filter chips.
6. Plain, regex, invalid-regex, filtered, and empty-result searches.
7. Markdown/JSON import, wiki export, and search-profile round trip.
8. Internal document links, table of contents, copy-code buttons, and gallery lightbox.
9. Workspace guide search, internal links, and all 17 captured native
   application views, including compact Split Dock and Card Flow in both themes.
