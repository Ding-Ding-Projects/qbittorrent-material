# Releases and Automation

## One immutable release per successful run

Every branch push and manual dispatch runs the `Build and release every push`
workflow on Windows Server 2022. It measures the hosted runner, runs the desktop
policy test, configures MSVC and Qt, restores vcpkg caches, builds the
application, packages NSIS, performs the installed-app smoke, and creates one
uniquely tagged full GitHub release marked “latest.”

The dependency restore includes libgit2, which powers the app's private
workspace repository without requiring `git.exe`. The installed-app launch gate
therefore also verifies that the packaged workspace runtime dependencies can be
loaded before an installer is published.

Tags follow this form:

```text
build-<workflow-run-number>-<8-character-commit>
```

The tested installer and the bundled Shrimp dumpling · 蝦餃 `har-gow.png` are
uploaded directly as release assets. The workflow creates no ordinary Actions
artifact and never fetches the release image from a third party.

Before publishing, the workflow proves the tag is unused twice. It never
uploads to an existing release, uses `--clobber`, or recycles a tag. A rerun
after publication fails safely instead of mutating the release.

## Pages publishing

GitHub Pages publishes directly from `master/docs`. That keeps the documentation deployment static and artifact-free. The generated `content.generated.js` file is committed so the browser needs no build tool or API at runtime.

## Release confidence gates

1. Measure CPU, memory, and disk on the hosted runner.
2. Validate desktop catalogs, decoded images, required surfaces, and release
   policy.
3. Configure with the pinned Qt, libgit2, and vcpkg toolchain.
4. Compile the Release target and build exactly one NSIS installer.
5. Hash and silently install the package in an isolated directory.
6. Verify the executable, Qt platform plugin, schema 2 persistence, both
   Workspace crash windows, and strict local Git integrity.
7. Uninstall silently.
8. Publish one full release containing the exact installer and bundled PNG.

Any failure before step 8 publishes no release. See
[Immutable Windows Releases](https://ding-ding-projects.github.io/qbittorrent-material/wiki.html#wiki/features-delivery-windows-releases)
for the token fallback and complete verification contract.
