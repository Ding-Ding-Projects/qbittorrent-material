# Getting Started

## Install a continuous release

Every successful push or manual dispatch publishes a Windows x64 installer on
the repository's Releases page. Choose the newest release for the branch and
commit you want to test, verify the SHA-256 value in its release notes, then run
the NSIS installer. Each release also carries the bundled Shrimp dumpling · 蝦餃
PNG identified in those notes.

The CI smoke gate silently installs the package into an isolated directory, checks the Qt platform plugin, launches the installed executable for ten seconds, and silently uninstalls it before publishing.

## Build and run on Windows

Visual Studio 2022 Build Tools with the C++ workload is the only large prerequisite that must exist first. The helper provisions CMake, Ninja, Python, NSIS, Qt 6.8.3, and repository dependencies as needed.

```powershell
# Configure, build, and launch
powershell -ExecutionPolicy Bypass -File .\run.ps1

# Build only
powershell -ExecutionPolicy Bypass -File .\run.ps1 -NoRun

# Produce the self-contained installer
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Package

# Validate desktop resources, catalogs, surfaces, and delivery policy
powershell -ExecutionPolicy Bypass -File .\scripts\test-desktop-policy.ps1
```

Installers and their SHA-256 files are written to `build\packages`.

## Try the persistent workspace

Press `Alt+5` after launch to open **Workspace**, then press `Ctrl+T` to create a
browser-style page. Changes save and commit to a managed local Git repository.
Git support is included in the application, so a separate Git installation is
not required. Continue with the [Workspace Tabs](Workspace-Tabs.md) guide for
appearance controls, application renaming, and portable exports.

Use the tab strip's discovery action to open current-strip, per-group,
group-name, or master search. Each field is plain-text-first and has its own
adjacent Qt/PCRE2 builder.

## Linux and macOS

```sh
./run.sh
./run.sh --no-run
./run.sh --clean
```

For the complete dependency matrix and manual CMake commands, open [Building qBittorrent Material](../BUILDING.md).
