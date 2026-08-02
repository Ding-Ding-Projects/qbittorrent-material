# Search Runtime

## Behavior

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
