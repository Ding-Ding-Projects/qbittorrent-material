# Building qBittorrent Material

The project uses CMake and Ninja. The supported Windows helper builds with
MSVC 2022 and downloads Qt 6.8.3 plus the remaining dependencies into the
repository on first use.

## Windows: build and run

Install Visual Studio 2022 Build Tools with the C++ workload first. If it is
not already installed, run:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Then run the helper from the repository root:

```powershell
# Build and launch the application
powershell -ExecutionPolicy Bypass -File .\run.ps1

# Build without launching
powershell -ExecutionPolicy Bypass -File .\run.ps1 -NoRun

# Remove the previous build first
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Clean -NoRun

# Override the default parallel job count
powershell -ExecutionPolicy Bypass -File .\run.ps1 -NoRun -Jobs 8
```

The first build can take a while because the helper installs Git, CMake, Ninja,
Python, and NSIS when necessary, downloads Qt 6.8.3 to `.qt`, and builds the
vcpkg dependencies in `.vcpkg`. Visual Studio Build Tools must be installed by
the user; the remaining command-line dependencies are provisioned automatically.

## Windows: build an installer

Use the same helper with `-Package` to build the application and create a
self-contained NSIS installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Package
```

Packaging mode reports the generated installer path and exits without launching
the application. It can be combined with `-Clean` or `-Jobs <count>`.

CPack writes the installer and its SHA-256 checksum to:

```text
build\packages\
```

Installer names follow this pattern:

```text
qBittorrent-Material-<version>-<build-id>-windows-x64.exe
```

The package includes the Qt runtime, plugins, QML imports, and libgit2 support
required to run the installed application and its persistent local Workspace
repository. End users do not need to install the Git command-line client.

## Visual smoke-test gallery

The checked-in visual gallery is captured from the native Windows build using a
fresh test profile and the deterministic capture path. It provides a quick UI
handoff alongside the package-only CPack smoke; the pushed GitHub Actions gate
performs the installed-package validation:

![qBittorrent Material dashboard](images/app/01-main-window.png)

See the complete [visual tour](SCREENSHOTS.md) for the toolbar, filters,
transfer workspace, properties tabs, and status bar.

If the build is already configured, the equivalent packaging command is:

```powershell
cpack --config build\CPackConfig.cmake -G NSIS -C Release
```

## Manual CMake build

For an existing Qt and libtorrent installation, configure and build directly:

```powershell
cmake -S . -B build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_TOOLCHAIN_FILE="<vcpkg>\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static-md `
  -DCMAKE_PREFIX_PATH="<Qt>\6.8.3\msvc2022_64"
cmake --build build --parallel
```

CMake requires Qt 6.6 or newer, libtorrent-rasterbar 2.0.7 or newer, Boost
1.76 or newer, OpenSSL 3.0 or newer, Zlib 1.2.11 or newer, and libgit2. The
supported Windows helper supplies libgit2 through the repository's vcpkg
manifest.

## Linux and macOS

The Unix helper installs dependencies using a supported system package manager,
then configures and builds with CMake and Ninja:

```sh
./run.sh          # build and run
./run.sh --no-run # build only
./run.sh --clean  # clean, build, and run
```

## Continuous Windows releases

Every branch push and manual dispatch triggers the `Build and release every
push` GitHub Actions workflow. It measures the hosted `windows-2022` runner,
runs the desktop policy test, builds with MSVC 2022 and Qt 6.8.3, creates and
smoke-tests the NSIS installer, and publishes one immutable full release:

- the Windows x64 installer built by that run; and
- the existing bundled Shrimp dumpling · 蝦餃 `har-gow.png` image.

The installed-app gate removes every Git executable directory from `PATH`, then
verifies that bundled libgit2 initializes and commits a clean repository. It
also simulates an interrupted metadata save and confirms that the orphaned page
body is restored as a committed recovered tab without data loss. A second crash
window confirms that a tracked body left behind after an intentional close is
removed and not resurrected.

The workflow intentionally does not create a separate Actions artifact. It
attaches both files directly to the release.

Each push receives a unique tag in the form
`build-<run-number>-<short-sha>`. The release targets the exact pushed
commit, is marked “latest” on creation, and records the branch, build ID,
installer SHA-256, and dim-sum dish/filename in its release notes. The workflow
refuses an existing tag or release and never uses `--clobber`. Its release token
uses `RELEASE_TOKEN`, then `ORG_TOKEN`, then `GITHUB_TOKEN`.

Run the same offline policy gate locally before packaging:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-desktop-policy.ps1
```

## Preview the documentation site

The complete Material documentation site is committed under `docs` and publishes
directly through GitHub Pages. Regenerate its embedded corpus, then serve it over
HTTP for local testing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generate-pages-content.ps1
py -3 -m http.server 4173 --directory docs
```

Open `http://127.0.0.1:4173/`. See [Documentation Site and Wiki](PAGES.md)
for regex/filter testing, import/export round trips, responsive QA, and GitHub
Wiki synchronization.
