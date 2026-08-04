[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string] $PackageVersion,

    [string] $RepositoryRoot = "",
    [string] $BuildDirectory = "build",
    [string] $OutputDirectory = "build/squirrel-release",
    [string] $PreviousReleaseDirectory = "",
    [string] $GitHubOutputPath = "",
    [string] $ToolCacheDirectory = "",
    [string] $CMakeExecutable = "cmake",
    [string] $SignWithParams = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 does not load the ZipFile assembly on first type use.
# run.ps1 supports that shell, while PowerShell 7 already has the type loaded.
if (-not ("System.IO.Compression.ZipFile" -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

$SquirrelVersion = "2.0.1"
$SquirrelSha256 = "923e18abb4fd50b5a4878a39dbcd042ed3f7eb68fc0f82c0955cd5380c921ac7"
$NuGetVersion = "7.6.0"
$NuGetSha256 = "12a7a2e0d11bd872c2a1e03c85b24a0288501f8b22084b47c90d4f2458c978d4"

function Resolve-TaskPath([string] $BasePath, [string] $Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Assert-DescendantPath([string] $ParentPath, [string] $ChildPath, [string] $Label) {
    $parent = [IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $child = [IO.Path]::GetFullPath($ChildPath)
    if (-not $child.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay below $parent (received $child)."
    }
}

function Reset-OwnedDirectory([string] $Path, [string] $OwnedRoot) {
    Assert-DescendantPath $OwnedRoot $Path "Owned build directory"
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -Recurse -Force -LiteralPath $Path
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-VerifiedPackageTool(
    [string] $PackageId,
    [string] $Version,
    [string] $ExpectedSha256,
    [string] $ExecutableRelativePath
) {
    $normalizedId = $PackageId.ToLowerInvariant()
    $fileName = "$normalizedId.$Version.nupkg"
    $downloadRoot = Join-Path $ToolCacheDirectory "downloads"
    $extractRoot = Join-Path $ToolCacheDirectory "$normalizedId-$Version-$ExpectedSha256"
    $packagePath = Join-Path $downloadRoot $fileName
    $executablePath = Join-Path $extractRoot $ExecutableRelativePath
    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null

    $packageValid = $false
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash.ToLowerInvariant()
        $packageValid = $actual -eq $ExpectedSha256
        if (-not $packageValid) {
            Remove-Item -Force -LiteralPath $packagePath
        }
    }

    if (-not $packageValid) {
        $url = "https://api.nuget.org/v3-flatcontainer/$normalizedId/$Version/$fileName"
        $temporaryPackage = "$packagePath.partial-$PID"
        try {
            Invoke-WebRequest -Uri $url -OutFile $temporaryPackage -UseBasicParsing
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryPackage).Hash.ToLowerInvariant()
            if ($actual -ne $ExpectedSha256) {
                throw "SHA256 mismatch for $PackageId ${Version}: expected $ExpectedSha256, received $actual."
            }
            Move-Item -Force -LiteralPath $temporaryPackage -Destination $packagePath
        }
        finally {
            Remove-Item -Force -LiteralPath $temporaryPackage -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        if (Test-Path -LiteralPath $extractRoot) {
            Assert-DescendantPath $ToolCacheDirectory $extractRoot "Tool extraction directory"
            Remove-Item -Recurse -Force -LiteralPath $extractRoot
        }
        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractRoot)
    }

    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "$PackageId $Version did not contain $ExecutableRelativePath."
    }
    return $executablePath
}

function Write-GitHubOutput([string] $Name, [string] $Value) {
    if ([string]::IsNullOrWhiteSpace($GitHubOutputPath)) { return }
    [IO.File]::AppendAllText(
        $GitHubOutputPath,
        "$Name=$Value$([Environment]::NewLine)",
        [Text.UTF8Encoding]::new($false))
}

function Get-ReleaseManifestEntry(
    [string] $ManifestPath,
    [string] $PackageName,
    [string] $Label
) {
    $escapedPackageName = [regex]::Escape($PackageName)
    $entryPattern = "^(?<sha1>[0-9A-Fa-f]{40})\s+(?<filename>$escapedPackageName)\s+(?<size>[0-9]+)(?:\s+#.*)?$"
    $matchingLines = @(
        Get-Content -LiteralPath $ManifestPath |
            Where-Object { $_ -match $entryPattern }
    )
    if ($matchingLines.Count -ne 1) {
        throw "$Label must have exactly one RELEASES entry for $PackageName; found $($matchingLines.Count)."
    }

    $entryMatch = [regex]::Match($matchingLines[0], $entryPattern)
    return [pscustomobject]@{
        Line = $matchingLines[0]
        SHA1 = $entryMatch.Groups["sha1"].Value.ToLowerInvariant()
        Filename = $entryMatch.Groups["filename"].Value
        Filesize = [long]::Parse($entryMatch.Groups["size"].Value)
    }
}

function Assert-ReleaseManifestPackage(
    [string] $ManifestPath,
    [string] $PackagePath,
    [string] $Label
) {
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "$Label is missing: $PackagePath"
    }

    $package = Get-Item -LiteralPath $PackagePath
    $entry = Get-ReleaseManifestEntry $ManifestPath $package.Name $Label
    $actualSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $package.FullName).Hash.ToLowerInvariant()
    if ($entry.SHA1 -ne $actualSha1) {
        throw "$Label SHA1 does not match its RELEASES entry."
    }
    if ($entry.Filesize -ne $package.Length) {
        throw "$Label byte length does not match its RELEASES entry."
    }
    return $entry
}

function Assert-ValidAuthenticodeSignature(
    [string] $Path,
    [string] $Label,
    [string] $ExpectedThumbprint
) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing from the signed Squirrel output: $Path"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid `
        -or $null -eq $signature.SignerCertificate) {
        throw "$Label does not have a valid trusted Authenticode signature (status: $($signature.Status))."
    }
    $actualThumbprint = $signature.SignerCertificate.Thumbprint.Replace(" ", "")
    if (-not $actualThumbprint.Equals(
        $ExpectedThumbprint,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label was signed by a different certificate than the requested certificate-store identity."
    }
}

function Export-EmbeddedSetupUpdater([string] $SetupPath, [string] $OutputPath) {
    if (-not ("QbtMaterial.Packaging.PeResourceReader" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace QbtMaterial.Packaging
{
    public static class PeResourceReader
    {
        private const uint LoadLibraryAsDataFile = 0x00000002;
        private const uint LoadLibraryAsImageResource = 0x00000020;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryExW(
            string fileName,
            IntPtr fileHandle,
            uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindResourceW(
            IntPtr module,
            IntPtr name,
            string type);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr loadedResource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeLibrary(IntPtr module);

        public static byte[] Read(string path, int identifier, string type)
        {
            IntPtr module = LoadLibraryExW(
                path,
                IntPtr.Zero,
                LoadLibraryAsDataFile | LoadLibraryAsImageResource);
            if (module == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());

            try
            {
                IntPtr resource = FindResourceW(module, new IntPtr(identifier), type);
                if (resource == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                uint size = SizeofResource(module, resource);
                if (size == 0 || size > Int32.MaxValue)
                    throw new InvalidOperationException("The embedded Setup resource has an invalid size.");

                IntPtr loadedResource = LoadResource(module, resource);
                if (loadedResource == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                IntPtr data = LockResource(loadedResource);
                if (data == IntPtr.Zero)
                    throw new InvalidOperationException("The embedded Setup resource could not be locked.");

                byte[] bytes = new byte[(int)size];
                Marshal.Copy(data, bytes, 0, bytes.Length);
                return bytes;
            }
            finally
            {
                FreeLibrary(module);
            }
        }
    }
}
"@
    }

    $embeddedZipPath = "$OutputPath.zip"
    $payload = [QbtMaterial.Packaging.PeResourceReader]::Read(
        $SetupPath,
        131,
        "DATA")
    [IO.File]::WriteAllBytes($embeddedZipPath, $payload)
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($embeddedZipPath)
        try {
            $updaterEntries = @(
                $archive.Entries |
                    Where-Object { $_.FullName.Equals(
                        "Update.exe",
                        [StringComparison]::OrdinalIgnoreCase) }
            )
            if ($updaterEntries.Count -ne 1) {
                throw "The embedded Squirrel Setup payload must contain exactly one top-level Update.exe."
            }

            $inputStream = $updaterEntries[0].Open()
            try {
                $outputStream = [IO.File]::Create($OutputPath)
                try {
                    $inputStream.CopyTo($outputStream)
                }
                finally {
                    $outputStream.Dispose()
                }
            }
            finally {
                $inputStream.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        Remove-Item -Force -LiteralPath $embeddedZipPath -ErrorAction SilentlyContinue
    }
}

$signingRequested = -not [string]::IsNullOrWhiteSpace($SignWithParams)
$expectedSigningThumbprint = ""
if ($signingRequested) {
    if ($SignWithParams -match "[`r`n`0]") {
        throw "SignWithParams must be a single command-line fragment without control characters."
    }
    # Squirrel 2.0.1 records its raw releasify command line in a local log. Keep
    # the interface deliberately narrow so only public certificate identity and
    # timestamp metadata can enter that log; passwords, PINs, PFX paths, token
    # values, authenticated URLs, and arbitrary signtool switches are rejected.
    $publicSigningPattern = '^\s*/sha1\s+(?<thumbprint>[0-9A-Fa-f]{40})\s+(?:/sm\s+)?/fd\s+sha256\s+/tr\s+https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~:/%-]*)?\s+/td\s+sha256\s*$'
    $publicSigningMatch = [regex]::Match(
        $SignWithParams,
        $publicSigningPattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $publicSigningMatch.Success) {
        throw "SignWithParams accepts only the non-secret form '/sha1 <40-hex thumbprint> [/sm] /fd SHA256 /tr https://host/path /td SHA256'. Squirrel logs this public command-line metadata, so use a pre-provisioned certificate-store or hardware-backed identity."
    }
    $expectedSigningThumbprint = $publicSigningMatch.Groups["thumbprint"].Value
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$BuildDirectory = Resolve-TaskPath $RepositoryRoot $BuildDirectory
$OutputDirectory = Resolve-TaskPath $RepositoryRoot $OutputDirectory
$ownedBuildRoot = Resolve-TaskPath $RepositoryRoot "build"
Assert-DescendantPath $RepositoryRoot $ownedBuildRoot "Build root"
Assert-DescendantPath $ownedBuildRoot $OutputDirectory "Squirrel output directory"

if ([string]::IsNullOrWhiteSpace($ToolCacheDirectory)) {
    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TOOL_CACHE)) {
        $ToolCacheDirectory = Join-Path $env:RUNNER_TOOL_CACHE "qbt-material-squirrel"
    }
    else {
        $ToolCacheDirectory = Join-Path ([IO.Path]::GetTempPath()) "qbt-material-squirrel-tools"
    }
}
$ToolCacheDirectory = [IO.Path]::GetFullPath($ToolCacheDirectory)
New-Item -ItemType Directory -Force -Path $ToolCacheDirectory | Out-Null

$nuspecPath = Join-Path $RepositoryRoot "installer/qbittorrent-material.nuspec"
$iconPath = Join-Path $RepositoryRoot "resources/branding/qbittorrent-material.ico"
foreach ($requiredPath in @($nuspecPath, $iconPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required packaging input is missing: $requiredPath"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $BuildDirectory "cmake_install.cmake") -PathType Leaf)) {
    throw "Configured CMake build directory is missing: $BuildDirectory"
}

$workingRoot = Join-Path $ownedBuildRoot "squirrel-work"
$stageRoot = Join-Path $workingRoot "stage"
$packageRoot = Join-Path $workingRoot "package"
Reset-OwnedDirectory $workingRoot $ownedBuildRoot
Reset-OwnedDirectory $OutputDirectory $ownedBuildRoot
New-Item -ItemType Directory -Force -Path $stageRoot, $packageRoot | Out-Null

& $CMakeExecutable --install $BuildDirectory --prefix $stageRoot --config Release
if ($LASTEXITCODE -ne 0) {
    throw "CMake could not create the Squirrel staging tree."
}

$installedBinRoot = Join-Path $stageRoot "bin"
$installedExe = Join-Path $installedBinRoot "qbittorrent.exe"
$stagedWindowsPlugin = Join-Path $stageRoot "plugins/platforms/qwindows.dll"
foreach ($requiredRuntime in @($installedExe, $stagedWindowsPlugin)) {
    if (-not (Test-Path -LiteralPath $requiredRuntime -PathType Leaf)) {
        throw "The deployed runtime is incomplete: $requiredRuntime"
    }
}

# Squirrel only discovers native executables placed at the application package
# root when it generates execution stubs and Start Menu/Desktop shortcuts. CMake
# keeps the executable and its dependent DLLs in bin/ so qt.conf can point at the
# sibling plugin/QML trees. Flatten that one directory for Squirrel and adjust
# the prefix; plugins/, qml/, and translations/ remain siblings of the exe.
Get-ChildItem -LiteralPath $installedBinRoot -Force | ForEach-Object {
    $destination = Join-Path $stageRoot $_.Name
    if (Test-Path -LiteralPath $destination) {
        throw "Cannot flatten the runtime because the Squirrel stage already contains $destination."
    }
    Move-Item -LiteralPath $_.FullName -Destination $destination
}
Remove-Item -LiteralPath $installedBinRoot
$stagedExe = Join-Path $stageRoot "qbittorrent.exe"
$stagedQtConfiguration = Join-Path $stageRoot "qt.conf"
@("[Paths]", "Prefix = .") |
    Set-Content -LiteralPath $stagedQtConfiguration -Encoding ascii
foreach ($requiredRuntime in @($stagedExe, $stagedQtConfiguration, $stagedWindowsPlugin)) {
    if (-not (Test-Path -LiteralPath $requiredRuntime -PathType Leaf)) {
        throw "The flattened Squirrel runtime is incomplete: $requiredRuntime"
    }
}

$nugetExe = Get-VerifiedPackageTool `
    "nuget.commandline" $NuGetVersion $NuGetSha256 "tools/NuGet.exe"
$squirrelCommand = Get-VerifiedPackageTool `
    "squirrel.windows" $SquirrelVersion $SquirrelSha256 "tools/Squirrel.com"

& $nugetExe pack $nuspecPath `
    -Version $PackageVersion `
    -BasePath $stageRoot `
    -OutputDirectory $packageRoot `
    -NoPackageAnalysis `
    -NonInteractive
if ($LASTEXITCODE -ne 0) {
    throw "NuGet could not create the Squirrel application package."
}

$inputPackages = @(Get-ChildItem -LiteralPath $packageRoot -Filter "qBittorrentMaterial.$PackageVersion.nupkg" -File)
if ($inputPackages.Count -ne 1) {
    throw "Expected one input NuGet package for $PackageVersion, found $($inputPackages.Count)."
}

$hasPreviousFeed = $false
if (-not [string]::IsNullOrWhiteSpace($PreviousReleaseDirectory)) {
    $PreviousReleaseDirectory = Resolve-TaskPath $RepositoryRoot $PreviousReleaseDirectory
    if (-not (Test-Path -LiteralPath $PreviousReleaseDirectory -PathType Container)) {
        throw "The supplied previous Squirrel release directory is missing: $PreviousReleaseDirectory"
    }
    $previousManifest = Join-Path $PreviousReleaseDirectory "RELEASES"
    $previousFullPackages = @(
        Get-ChildItem -LiteralPath $PreviousReleaseDirectory `
            -Filter "qBittorrentMaterial-*-full.nupkg" -File -ErrorAction SilentlyContinue
    )
    if (-not (Test-Path -LiteralPath $previousManifest -PathType Leaf)) {
        throw "The supplied previous Squirrel feed has no RELEASES manifest."
    }
    if ($previousFullPackages.Count -ne 1) {
        throw "The supplied previous Squirrel feed must contain exactly one full package; found $($previousFullPackages.Count)."
    }

    $previousVersionMatch = [regex]::Match(
        $previousFullPackages[0].Name,
        '^qBittorrentMaterial-(?<version>[0-9]+\.[0-9]+\.[0-9]+)-full\.nupkg$')
    if (-not $previousVersionMatch.Success) {
        throw "The supplied previous Squirrel full package has an invalid name."
    }
    $previousVersion = [version]$previousVersionMatch.Groups["version"].Value
    if ($previousVersion -ge [version]$PackageVersion) {
        throw "The supplied Squirrel feed version $previousVersion is not older than $PackageVersion."
    }

    $previousFullEntry = Assert-ReleaseManifestPackage `
        $previousManifest $previousFullPackages[0].FullName "Previous Squirrel full package"
    $previousFullEntry.Line |
        Set-Content -LiteralPath (Join-Path $OutputDirectory "RELEASES") -Encoding ascii
    Copy-Item -LiteralPath $previousFullPackages[0].FullName -Destination $OutputDirectory
    $hasPreviousFeed = $true
}

$squirrelArguments = @(
    "--releasify=$($inputPackages[0].FullName)",
    "--releaseDir=$OutputDirectory",
    "--setupIcon=$iconPath",
    "--framework-version=net461",
    "--no-msi"
)
if (-not $hasPreviousFeed) {
    $squirrelArguments += "--no-delta"
}
if ($signingRequested) {
    # Squirrel signs the packaged PE assets, generated execution stub, embedded
    # updater, and final Setup. The validated fragment contains public metadata
    # only; it is never emitted as workflow output.
    $squirrelArguments += "--signWithParams=$SignWithParams"
}
& $squirrelCommand @squirrelArguments
if ($LASTEXITCODE -ne 0) {
    throw "Squirrel.Windows could not releasify qBittorrent Material $PackageVersion."
}

$releaseManifest = Join-Path $OutputDirectory "RELEASES"
if (-not (Test-Path -LiteralPath $releaseManifest -PathType Leaf)) {
    throw "Squirrel.Windows did not create a RELEASES manifest."
}

$currentFullPackages = @(
    Get-ChildItem -LiteralPath $OutputDirectory `
        -Filter "qBittorrentMaterial-$PackageVersion-full.nupkg" -File
)
$currentDeltaPackages = @(
    Get-ChildItem -LiteralPath $OutputDirectory `
        -Filter "qBittorrentMaterial-$PackageVersion-delta.nupkg" -File
)
if ($currentFullPackages.Count -ne 1) {
    throw "Squirrel output must contain exactly one current full package; found $($currentFullPackages.Count)."
}
$expectedDeltaCount = if ($hasPreviousFeed) { 1 } else { 0 }
$currentDeltaName = "qBittorrentMaterial-$PackageVersion-delta.nupkg"
$escapedDeltaName = [regex]::Escape($currentDeltaName)
$currentDeltaEntryPattern = "^[0-9A-Fa-f]{40}\s+$escapedDeltaName\s+[0-9]+(?:\s+#.*)?$"
$currentDeltaManifestLines = @(
    Get-Content -LiteralPath $releaseManifest |
        Where-Object { $_ -match $currentDeltaEntryPattern }
)
if ($currentDeltaPackages.Count -ne $expectedDeltaCount `
    -or $currentDeltaManifestLines.Count -ne $expectedDeltaCount) {
    $feedDescription = if ($hasPreviousFeed) { "a validated previous feed" } else { "the first Squirrel feed" }
    throw "Squirrel output for $feedDescription must contain exactly $expectedDeltaCount current delta package(s) and RELEASES entry/entries; found $($currentDeltaPackages.Count) package(s) and $($currentDeltaManifestLines.Count) entry/entries."
}

$fullEntry = Assert-ReleaseManifestPackage `
    $releaseManifest $currentFullPackages[0].FullName "Current Squirrel full package"
$currentEntries = @($fullEntry.Line)
if ($hasPreviousFeed) {
    $deltaEntry = Assert-ReleaseManifestPackage `
        $releaseManifest $currentDeltaPackages[0].FullName "Current Squirrel delta package"
    $currentEntries += $deltaEntry.Line
}
$currentEntries | Set-Content -LiteralPath $releaseManifest -Encoding ascii

Get-ChildItem -LiteralPath $OutputDirectory -Filter "qBittorrentMaterial-*-full.nupkg" -File |
    Where-Object { $_.FullName -ne $currentFullPackages[0].FullName } |
    Remove-Item -Force

$generatedSetup = Join-Path $OutputDirectory "Setup.exe"
if (-not (Test-Path -LiteralPath $generatedSetup -PathType Leaf)) {
    throw "Squirrel did not create Setup.exe."
}
$installerName = "qBittorrent-Material-$PackageVersion-windows-x64-Setup.exe"
$installerPath = Join-Path $OutputDirectory $installerName
Move-Item -LiteralPath $generatedSetup -Destination $installerPath

$unexpectedInstallers = @(
    Get-ChildItem -LiteralPath $OutputDirectory -Filter "*.exe" -File |
        Where-Object { $_.FullName -ne $installerPath }
)
if ($unexpectedInstallers.Count -ne 0) {
    throw "Squirrel output contains unexpected installer executables: $($unexpectedInstallers.Name -join ', ')."
}

if ($signingRequested) {
    $signatureVerificationRoot = Join-Path $workingRoot "signature-verification"
    Reset-OwnedDirectory $signatureVerificationRoot $workingRoot
    $packageSignatureRoot = Join-Path $signatureVerificationRoot "package"
    New-Item -ItemType Directory -Force -Path $packageSignatureRoot | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory(
        $currentFullPackages[0].FullName,
        $packageSignatureRoot)
    $embeddedUpdaterPath = Join-Path `
        $signatureVerificationRoot "setup-embedded-Update.exe"
    Export-EmbeddedSetupUpdater $installerPath $embeddedUpdaterPath
    Assert-ValidAuthenticodeSignature `
        $installerPath "Squirrel Setup" $expectedSigningThumbprint
    Assert-ValidAuthenticodeSignature `
        $embeddedUpdaterPath "Setup-embedded Squirrel updater" `
        $expectedSigningThumbprint
    Assert-ValidAuthenticodeSignature `
        (Join-Path $packageSignatureRoot "lib/net45/qbittorrent.exe") `
        "Packaged qBittorrent Material application" `
        $expectedSigningThumbprint
    Assert-ValidAuthenticodeSignature `
        (Join-Path $packageSignatureRoot "lib/net45/qbittorrent_ExecutionStub.exe") `
        "Packaged Squirrel execution stub" `
        $expectedSigningThumbprint
}

$installerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash.ToLowerInvariant()
$fullSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $currentFullPackages[0].FullName).Hash.ToLowerInvariant()
$deltaPath = if ($currentDeltaPackages.Count -eq 1) { $currentDeltaPackages[0].FullName } else { "" }
$deltaSha256 = if ($currentDeltaPackages.Count -eq 1) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $currentDeltaPackages[0].FullName).Hash.ToLowerInvariant()
}
else { "" }

Write-GitHubOutput "installer" $installerPath
Write-GitHubOutput "installerSha256" $installerSha256
Write-GitHubOutput "releases" $releaseManifest
Write-GitHubOutput "fullPackage" $currentFullPackages[0].FullName
Write-GitHubOutput "fullPackageSha256" $fullSha256
Write-GitHubOutput "deltaPackage" $deltaPath
Write-GitHubOutput "deltaPackageSha256" $deltaSha256
Write-GitHubOutput "packageVersion" $PackageVersion
Write-GitHubOutput "signed" $signingRequested.ToString().ToLowerInvariant()

[pscustomobject]@{
    PackageVersion = $PackageVersion
    Installer = $installerPath
    InstallerSha256 = $installerSha256
    Releases = $releaseManifest
    FullPackage = $currentFullPackages[0].FullName
    FullPackageSha256 = $fullSha256
    DeltaPackage = $deltaPath
    DeltaPackageSha256 = $deltaSha256
    Signed = $signingRequested
    SquirrelVersion = $SquirrelVersion
    NuGetVersion = $NuGetVersion
} | Format-List
