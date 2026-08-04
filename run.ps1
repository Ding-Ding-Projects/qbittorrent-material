<#
  qBittorrent Material - one-click build & run (Windows)

  Fully automatic after MSVC is present: provisions missing command-line tools,
  keeps Qt and vcpkg inside the repo, configures, builds, and launches the app.
  Safe to re-run; completed dependency work is reused.

  Usage:
      powershell -ExecutionPolicy Bypass -File run.ps1        # build + run
      ...-File run.ps1 -NoRun                                  # build only
      ...-File run.ps1 -Package                                # build Squirrel installer/feed
      ...-File run.ps1 -Clean                                  # wipe build/ first
      ...-File run.ps1 -Jobs 8                                 # parallel build jobs

  Requirements it will use if present, else install locally:
    - Visual Studio 2022 Build Tools (MSVC, C++). MUST be installed by you
      (Microsoft does not allow silent redistribution). If missing, the script
      prints the one-line winget command to get it.
    - Git, CMake >= 3.21, Ninja -> installed via winget if missing
    - Python 3              -> used to fetch Qt (aqtinstall)
    - Qt 6.8.3 (msvc2022_64) -> fetched into .\.qt via aqtinstall
    - vcpkg + libtorrent/libgit2/zlib -> cloned into .\.vcpkg and built
    - Squirrel.Windows + NuGet CLI -> pinned and checksum-verified from NuGet
#>
[CmdletBinding()]
param(
    [switch]$NoRun,
    [switch]$Package,
    [switch]$Clean,
    [int]$Jobs = 0
)

$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$QtVersion = '6.8.3'
$QtArch = 'win64_msvc2022_64'
$QtDirName = 'msvc2022_64'
$Triplet = 'x64-windows-static-md'
$VcpkgBaseline = '40a9bd4ccdf5dc14ff76d4ed47d46a226ce84a83'
$QtRoot = Join-Path $Repo '.qt'
$QtPrefix = Join-Path $QtRoot "$QtVersion\$QtDirName"
$VcpkgRoot = Join-Path $Repo '.vcpkg'
$BuildDir = Join-Path $Repo 'build'
$PackageDir = Join-Path $BuildDir 'squirrel-release'

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Get-NormalizedPath($path) {
    try {
        return [IO.Path]::GetFullPath($path).TrimEnd([char[]] @('\', '/'))
    }
    catch {
        return ([string] $path).TrimEnd([char[]] @('\', '/'))
    }
}

function Get-CMakeCacheValue($name) {
    $cachePath = Join-Path $BuildDir 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { return $null }

    $pattern = '^' + [regex]::Escape($name) + '(?::[^=]*)?=(.*)$'
    foreach ($line in Get-Content -LiteralPath $cachePath) {
        if ($line -match $pattern) { return $Matches[1] }
    }
    return $null
}

function Reset-MovedCMakeBuild {
    $cachedSource = Get-CMakeCacheValue 'CMAKE_HOME_DIRECTORY'
    $cachedBuild = Get-CMakeCacheValue 'CMAKE_CACHEFILE_DIR'
    $sourceMoved = $cachedSource -and -not [StringComparer]::OrdinalIgnoreCase.Equals(
        (Get-NormalizedPath $cachedSource), (Get-NormalizedPath $Repo))
    $buildMoved = $cachedBuild -and -not [StringComparer]::OrdinalIgnoreCase.Equals(
        (Get-NormalizedPath $cachedBuild), (Get-NormalizedPath $BuildDir))

    if ($sourceMoved -or $buildMoved) {
        Warn "The build cache belongs to another checkout ($cachedSource); regenerating build/."
        Remove-Item -LiteralPath $BuildDir -Recurse -Force
    }
}

function Find-Python {
    $candidates = @(
        'python',
        'py',
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe')
    )
    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate) -and -not (Have $candidate)) { continue }
        & $candidate -c 'import sys; print(sys.executable)' *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    return $null
}

# --- 0. winget helper for Git/CMake/Ninja -------------------------------------
function Ensure-Tool($cmd, $wingetId, $friendly) {
    if (Have $cmd) { return }
    # Reuse tools bundled with an existing Visual Studio installation before
    # downloading another copy. VS does not add these CMake paths globally.
    $knownDirs = switch ($cmd) {
        'cmake' {
            @(
                (Join-Path $env:ProgramFiles 'CMake\bin'),
                (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\18\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'),
                (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin')
            )
        }
        'ninja' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
                (Join-Path $env:ProgramFiles 'Ninja'),
                (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\18\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'),
                (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja')
            )
        }
        'git' {
            @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd'),
                (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
                (Join-Path $env:ProgramFiles 'Git\cmd'),
                (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd')
            )
        }
        default { @() }
    }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        foreach ($install in @(& $vswhere -all -products * -property installationPath 2>$null)) {
            if ($cmd -eq 'cmake') {
                $knownDirs += (Join-Path $install 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin')
            }
            elseif ($cmd -eq 'ninja') {
                $knownDirs += (Join-Path $install 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja')
            }
        }
    }
    foreach ($dir in $knownDirs) {
        if ($dir -and (Test-Path (Join-Path $dir "$cmd.exe"))) {
            $env:PATH = "$dir;$env:PATH"
            break
        }
    }
    if (Have $cmd) { return }
    if (Have 'winget') {
        Info "Installing $friendly via winget..."
        winget install --id $wingetId --accept-source-agreements --accept-package-agreements -e --silent | Out-Host
    }
    # Most installers update the persistent PATH, not this PowerShell process.
    # Re-check the known install directories after the installer returns.
    foreach ($dir in $knownDirs) {
        if ($dir -and (Test-Path (Join-Path $dir "$cmd.exe"))) {
            $env:PATH = "$dir;$env:PATH"
            break
        }
    }
    if (-not (Have $cmd)) {
        Die "$friendly ($cmd) not found and could not be auto-installed. Install it and re-run."
    }
}

# --- 1. Locate MSVC (vcvars64) -------------------------------------------------
function Find-VcVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null | Select-Object -First 1
        if ($path) {
            $vc = Join-Path $path 'VC\Auxiliary\Build\vcvars64.bat'
            if (Test-Path $vc) { return $vc }
        }
    }
    return $null
}

function Import-VcVars($vcvars, $vcToolsVersion) {
    $toolsetArgument = if ($vcToolsVersion) { " -vcvars_ver=$vcToolsVersion" } else { '' }
    Info "Importing MSVC environment ($vcvars$toolsetArgument)"
    cmd /c "`"$vcvars`"$toolsetArgument && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] }
    }
}

# --- 2. Qt via aqtinstall ------------------------------------------------------
function Ensure-Qt {
    if (Test-Path (Join-Path $QtPrefix 'bin\qmake.exe')) {
        Info "Qt $QtVersion already present at $QtPrefix"
        return
    }
    # A Windows Store app-execution alias can make Get-Command report Python
    # even though no interpreter is installed, so validate by executing it.
    $py = Find-Python
    if (-not $py -and (Have 'winget')) {
        Info 'Installing Python 3 via winget...'
        winget install --id Python.Python.3.12 --accept-source-agreements `
            --accept-package-agreements -e --silent | Out-Host
        $py = Find-Python
    }
    if (-not $py) { Die 'Python 3 was not found and could not be auto-installed.' }
    Info "Installing aqtinstall (Qt downloader)..."
    & $py -m pip install --quiet --upgrade aqtinstall
    if ($LASTEXITCODE -ne 0) { Die 'Could not install aqtinstall.' }
    Info "Downloading Qt $QtVersion $QtArch into $QtRoot (a few minutes)..."
    & $py -m aqt install-qt windows desktop $QtVersion $QtArch `
        -m qt5compat qtimageformats qtshadertools qtmultimedia --outputdir $QtRoot
    if ($LASTEXITCODE -ne 0) { Die 'Qt download failed.' }
    if (-not (Test-Path (Join-Path $QtPrefix 'bin\qmake.exe'))) { Die "Qt install failed." }
}

# --- 3. vcpkg + native libraries ----------------------------------------------
function Ensure-Vcpkg {
    if (-not (Test-Path $VcpkgRoot)) {
        Info "Cloning vcpkg into $VcpkgRoot ..."
        git clone --filter=blob:none https://github.com/microsoft/vcpkg.git $VcpkgRoot | Out-Host
        if ($LASTEXITCODE -ne 0) { Die 'Could not clone vcpkg.' }
    }
    if (-not (Test-Path (Join-Path $VcpkgRoot '.git'))) {
        Die "$VcpkgRoot exists but is not a vcpkg Git checkout. Move it aside and re-run."
    }

    git -C $VcpkgRoot cat-file -e "$VcpkgBaseline^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Info "Fetching pinned vcpkg baseline $VcpkgBaseline ..."
        git -C $VcpkgRoot fetch --depth 1 origin $VcpkgBaseline | Out-Host
        if ($LASTEXITCODE -ne 0) { Die 'Could not fetch the pinned vcpkg baseline.' }
    }
    git -C $VcpkgRoot checkout --detach $VcpkgBaseline | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'Could not check out the pinned vcpkg baseline.' }

    # Re-run the inexpensive bootstrap check after selecting the baseline so an
    # existing vcpkg.exe can never drift from the pinned source revision.
    Info "Ensuring the pinned vcpkg tool is bootstrapped..."
    & (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'Could not bootstrap vcpkg.' }
    $vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
    $installedRoot = Join-Path $VcpkgRoot 'installed'
    Warn "Restoring the vcpkg manifest for $Triplet."
    Warn "FIRST run only; this can take 30-90 minutes. Subsequent runs are incremental."
    & $vcpkg install --triplet $Triplet `
        --x-manifest-root="$Repo" `
        --x-install-root="$installedRoot" `
        --clean-after-build | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'vcpkg dependency restore failed.' }

    $libtorrent = Join-Path $installedRoot "$Triplet\lib\torrent-rasterbar.lib"
    $libgit2 = Join-Path $installedRoot "$Triplet\lib\git2.lib"
    if (-not (Test-Path $libtorrent)) { Die 'vcpkg completed but libtorrent was not installed.' }
    if (-not (Test-Path $libgit2)) { Die 'vcpkg completed but libgit2 was not installed.' }
}

# --- MAIN ----------------------------------------------------------------------
Info "qBittorrent Material - automatic build & run"
Info "Repo: $Repo"

if ($Clean -and (Test-Path $BuildDir)) {
    Info "Cleaning build/"
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}
elseif (Test-Path $BuildDir) {
    Reset-MovedCMakeBuild
}

$vcvars = Find-VcVars
if (-not $vcvars) {
    Die @"
Visual Studio 2022 Build Tools (MSVC C++) not found.
Install it (one-time) with:
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
then re-run this script.
"@
}
$VcVarsFile = Get-Item -LiteralPath $vcvars -ErrorAction Stop
$VcVarsBuildDir = $VcVarsFile.Directory
if ($null -eq $VcVarsBuildDir -or $VcVarsBuildDir.Name -ine 'Build') {
    Die "Cannot derive the Visual Studio installation from $($VcVarsFile.FullName)."
}
$VcVarsAuxiliaryDir = $VcVarsBuildDir.Parent
if ($null -eq $VcVarsAuxiliaryDir -or $VcVarsAuxiliaryDir.Name -ine 'Auxiliary') {
    Die "Unexpected Visual Studio vcvars path: $($VcVarsFile.FullName)."
}
$VcDir = Get-Item -LiteralPath $VcVarsAuxiliaryDir.Parent.FullName -ErrorAction Stop
if ($null -eq $VcDir -or $VcDir.Name -ine 'VC' -or $null -eq $VcDir.Parent) {
    Die "Unexpected Visual Studio vcvars path: $($VcVarsFile.FullName)."
}
$VcToolsRoot = Join-Path $VcDir 'Tools\MSVC'
$VcToolsDirectory = Get-ChildItem -LiteralPath $VcToolsRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $VcToolsDirectory) {
    Die "No installed MSVC toolset was found under $VcToolsRoot."
}
$VcToolsVersion = ($VcToolsDirectory.Name -split '\.')[0..1] -join '.'
$env:VCPKG_VISUAL_STUDIO_TOOLSET = $VcToolsDirectory.Name
$env:VCPKG_VISUAL_STUDIO_PATH = $VcDir.Parent.FullName
Info "Pinning vcpkg to the selected Visual Studio: $env:VCPKG_VISUAL_STUDIO_PATH ($($VcToolsDirectory.Name))"
Import-VcVars $vcvars $VcToolsVersion
$env:VCPKG_ROOT = $VcpkgRoot

Ensure-Tool 'git' 'Git.Git' 'Git'
Ensure-Tool 'cmake' 'Kitware.CMake' 'CMake'
Ensure-Tool 'ninja' 'Ninja-build.Ninja' 'Ninja'
Ensure-Qt
Ensure-Vcpkg

if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }

Info "Configuring (CMake + Ninja)..."
$CMakeExe = (Get-Command 'cmake.exe' -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$NinjaExe = (Get-Command 'ninja.exe' -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$VcpkgToolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
$VcpkgInstalled = Join-Path $VcpkgRoot 'installed'
$CMakeConfigureArgs = @(
    '-B'
    $BuildDir
    '-S'
    $Repo
    '-G'
    'Ninja'
    '-DCMAKE_BUILD_TYPE=Release'
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=$NinjaExe"
    "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=$VcpkgToolchain"
    "-DVCPKG_TARGET_TRIPLET:STRING=$Triplet"
    "-DVCPKG_INSTALLED_DIR:PATH=$VcpkgInstalled"
    '-DVCPKG_MANIFEST_MODE=ON'
    "-DCMAKE_PREFIX_PATH:PATH=$QtPrefix"
)
& $CMakeExe @CMakeConfigureArgs
if ($LASTEXITCODE -ne 0) { Die "CMake configure failed." }

Info "Building (-j $Jobs)..."
cmake --build $BuildDir --parallel $Jobs
if ($LASTEXITCODE -ne 0) { Die "Build failed." }

$exe = Get-ChildItem -Path $BuildDir -Recurse -Filter 'qbittorrent.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Die "Build succeeded but qbittorrent.exe not found." }
Info "Build OK: $($exe.FullName)"

if ($Package) {
    $cacheVersion = Select-String -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt') `
        -Pattern '^QBT_PACKAGE_VERSION:STRING=([0-9]+\.[0-9]+\.[0-9]+)$' |
        Select-Object -First 1
    if (-not $cacheVersion) {
        Die 'Configured Squirrel package version is missing from CMakeCache.txt.'
    }
    $packageVersion = $cacheVersion.Matches[0].Groups[1].Value
    Info "Building the Squirrel installer and update feed ($packageVersion)..."
    & (Join-Path $Repo 'scripts\build-squirrel-package.ps1') `
        -PackageVersion $packageVersion `
        -RepositoryRoot $Repo `
        -BuildDirectory $BuildDir `
        -OutputDirectory $PackageDir `
        -CMakeExecutable $CMakeExe
    $installer = Get-ChildItem -Path $PackageDir `
        -Filter "qBittorrent-Material-$packageVersion-windows-x64-Setup.exe" `
        -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $installer) { Die "Packaging succeeded but no installer was found in $PackageDir." }

    Info "Installer OK: $($installer.FullName)"
    Info "SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName).Hash.ToLowerInvariant())"
    Info "Update feed: $(Join-Path $PackageDir 'RELEASES')"
    exit 0
}

# Ensure Qt runtime DLLs are next to the exe for a portable run.
$windeployqt = Join-Path $QtPrefix 'bin\windeployqt.exe'
if (-not (Test-Path -LiteralPath $windeployqt -PathType Leaf)) {
    Die "Qt deployment tool not found: $windeployqt"
}
Info "Deploying Qt runtime (windeployqt)..."
& $windeployqt --qmldir "$Repo\src\quick\qml" --release "$($exe.FullName)" | Out-Null
if ($LASTEXITCODE -ne 0) { Die "Qt runtime deployment failed." }

if ($NoRun) {
    Info "Done (build only). Run it with: `"$($exe.FullName)`""
} else {
    Info "Launching qBittorrent Material..."
    & $exe.FullName
}
