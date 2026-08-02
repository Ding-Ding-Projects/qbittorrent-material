# Search Runtime

## Behavior

The Search tab is **on by default**. Upstream qBittorrent hides it until the
user opts in, because upstream cannot assume the search runtime is present; this
fork ships that runtime in its own resources, so search is usable out of the box.
The tab can still be toggled from **View -> Search Engine**, and that choice is
remembered.

Because the tab is on by default, the startup capabilities query is deferred to
the first event-loop iteration rather than run during construction — it spawns
Python and waits for it (~175 ms measured), which would otherwise stall every
launch on the GUI thread. Plugins and failures are reported through signals as
they arrive, so nothing waits on that probe.

The Search tab does not query torrent sites directly. It drives the `nova3`
Python runtime that qBittorrent search plugins are written against. On first use
the application extracts five bundled files — `helpers.py`, `nova2.py`,
`nova2dl.py`, `novaprinter.py`, and `socks.py` — from its own resources into the
profile's `nova3` directory, then runs `nova2.py --capabilities` to learn which
plugins are installed and which categories they support. Searching runs
`nova2.py`, and downloading a result runs `nova2dl.py`.

Extraction is version-aware: each bundled file carries a `# VERSION:` header,
and a file is only rewritten on disk when the bundled copy is newer. A file
without that header would never be extracted, so every bundled runtime file must
keep its header.

## Bundled plugins

Search sources are also shipped, not downloaded on demand. The engines from the
upstream `qbittorrent/search-plugins` project are vendored under
`resources/searchengine/nova3/engines/` at a pinned commit and seeded into the
profile's `nova3/engines` directory on startup, so the Search tab has sources the
first time it is opened with no user action. Upstream qBittorrent does not do
this — it downloads plugins on demand — so the bundled set is a point-in-time
snapshot and **Search plugins… -> Check for updates** remains the way to pick up
newer versions.

Seeding is deliberately conservative, because the alternative is a plugin list
the user cannot control:

- A plugin whose bundled copy is **not newer** than the installed one is left
  alone, so updates fetched from the upstream feed are never downgraded.
- A plugin that is **absent but already recorded as seeded** is left alone, so
  uninstalling a bundled plugin sticks across restarts instead of the plugin
  reappearing on the next launch.

The record of what has been seeded lives in the `SearchEngines/seededPlugins`
preference. Deleting that key makes the next launch restore the full bundled set.

## Prerequisites

Search needs a Python interpreter. The application resolves one by executing the
candidate with `--version` rather than trusting a name found on `PATH`. This
matters on Windows: `%LOCALAPPDATA%\Microsoft\WindowsApps` contains zero-byte
`python.exe` and `python3.exe` App Execution Alias stubs that are on `PATH` even
when Python is not installed, so a path lookup alone reports an interpreter that
cannot run anything. An interpreter chosen in Options is validated the same way
instead of being trusted because it is set.

## Failure modes

Three prerequisites can fail independently, and each is reported as itself:

- **No usable Python interpreter.** The Search tab explains that Python is
  required and offers **Check again**, which re-probes without a restart.
- **The nova runtime is missing from the profile.** Reported with the path that
  was expected.
- **The runtime starts but returns nothing usable.** The interpreter's own error
  output is included when it produced any.

None of these are the same as "no plugins installed yet", and the empty state
distinguishes them: when search cannot run, the **Install search plugins**
shortcut is withheld, because installing a plugin re-runs the capabilities query
and would fail with a misleading "Plugin is not supported."

## Packaging

The runtime is not optional and is not downloaded. It is committed under
`resources/searchengine/nova3/` and compiled into the binary by both resource
paths — the tolerant asset glob and the hand-authored `resources.qrc` manifest.
A missing runtime file fails the CMake configure step rather than producing a
build whose Search tab is silently dead. `Qt6::Xml` is a required component for
the same reason: the capabilities parser uses `QDomDocument` unconditionally.

## Verification

Repository policy checks require the five runtime files to be present with
intact `# VERSION:` headers, both resource paths to bundle them, the configure
guard to exist, `Qt6::Xml` to be required, the engine to report each failure
distinctly, Python detection to execute the interpreter, and the empty state to
separate a blocked runtime from an empty plugin list.

## Related articles

- [Result filtering](filtering.md)
- [Windows Desktop Features](../README.md)
