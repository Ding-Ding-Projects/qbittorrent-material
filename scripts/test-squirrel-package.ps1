[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $InstallerPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string] $PackageVersion,

    [Parameter(Mandatory = $true)]
    [string] $ReleaseDirectory,

    [switch] $ExpectDelta,

    [switch] $SkipNormalSetupLaunchAssertion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ("System.IO.Compression.ZipFile" -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

function Resolve-RequiredFile([string] $Path, [string] $Label) {
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    return $resolved.Path
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
    $PackagePath = Resolve-RequiredFile $PackagePath $Label
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

function Assert-PackagedExecutableVersion(
    [string] $PackagePath,
    [string] $ExpectedPackageVersion,
    [string] $ScratchRoot
) {
    $extractRoot = Join-Path $ScratchRoot "qbt-material-version-resource-$([guid]::NewGuid().ToString('N'))"
    $executablePath = Join-Path $extractRoot "qbittorrent.exe"
    $expectedWindowsVersion = "$ExpectedPackageVersion.0"
    try {
        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
        try {
            $entries = @($archive.Entries | Where-Object {
                $_.FullName -eq "lib/net45/qbittorrent.exe"
            })
            if ($entries.Count -ne 1) {
                throw "Squirrel full package must contain exactly one lib/net45/qbittorrent.exe; found $($entries.Count)."
            }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $executablePath, $false)
        }
        finally {
            $archive.Dispose()
        }

        $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($executablePath)
        if ($versionInfo.FileVersion -ne $expectedWindowsVersion `
            -or $versionInfo.ProductVersion -ne $expectedWindowsVersion) {
            throw "Packaged qbittorrent.exe version resource is FileVersion '$($versionInfo.FileVersion)' / ProductVersion '$($versionInfo.ProductVersion)', expected '$expectedWindowsVersion' from Squirrel package $ExpectedPackageVersion."
        }
        Write-Host "Verified packaged qbittorrent.exe FileVersion/ProductVersion $expectedWindowsVersion from Squirrel package $ExpectedPackageVersion."
    }
    finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -Recurse -Force -LiteralPath $extractRoot
        }
    }
}

function Invoke-CheckedProcess(
    [string] $FilePath,
    [string[]] $ArgumentList,
    [string] $Label
) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "$Label returned exit code $($process.ExitCode)."
    }
}

function Invoke-CheckedRootProcess(
    [string] $FilePath,
    [string[]] $ArgumentList,
    [string] $Label,
    [int] $TimeoutSeconds = 120
) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Label did not exit within $TimeoutSeconds seconds."
    }
    if ($process.ExitCode -ne 0) {
        throw "$Label returned exit code $($process.ExitCode)."
    }
}

function Read-AssociationValue([string] $SubKey, [string] $ValueName = "") {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "Software\Classes\$SubKey")
    if ($null -eq $key) {
        return [pscustomobject]@{
            KeyPresent = $false
            Present = $false
            Value = $null
            Kind = $null
        }
    }
    try {
        $present = @($key.GetValueNames()) -contains $ValueName
        $value = if ($present) {
            $key.GetValue(
                $ValueName,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        else { $null }
        $kind = if ($present) { $key.GetValueKind($ValueName).ToString() } else { $null }
        return [pscustomobject]@{
            KeyPresent = $true
            Present = $present
            Value = $value
            Kind = $kind
        }
    }
    finally {
        $key.Dispose()
    }
}

function Write-AssociationValue(
    [string] $SubKey,
    [string] $ValueName,
    [string] $Value,
    [Microsoft.Win32.RegistryValueKind] $Kind = `
        [Microsoft.Win32.RegistryValueKind]::String
) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
        "Software\Classes\$SubKey")
    if ($null -eq $key) { throw "Could not create the per-user association key: $SubKey" }
    try {
        $key.SetValue($ValueName, $Value, $Kind)
    }
    finally {
        $key.Dispose()
    }
}

function Read-AssociationKeyState([string] $SubKey) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "Software\Classes\$SubKey")
    if ($null -eq $key) {
        return [pscustomobject]@{
            Present = $false
            ValueCount = 0
            SubKeyCount = 0
        }
    }
    try {
        return [pscustomobject]@{
            Present = $true
            ValueCount = @($key.GetValueNames()).Count
            SubKeyCount = @($key.GetSubKeyNames()).Count
        }
    }
    finally {
        $key.Dispose()
    }
}

function Assert-AssociationKeyEmpty([string] $SubKey, [string] $Label) {
    $state = Read-AssociationKeyState $SubKey
    if (-not $state.Present -or $state.ValueCount -ne 0 -or $state.SubKeyCount -ne 0) {
        throw "$Label expected Software\Classes\$SubKey to exist with no values or subkeys."
    }
}

function Assert-AssociationKeyAbsent([string] $SubKey, [string] $Label) {
    $state = Read-AssociationKeyState $SubKey
    if ($state.Present) {
        throw "$Label expected Software\Classes\$SubKey to be absent."
    }
}

function New-EmptyAssociationKey([string] $SubKey) {
    Assert-AssociationKeyAbsent $SubKey "Empty-key smoke precondition"
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
        "Software\Classes\$SubKey")
    if ($null -eq $key) {
        throw "Could not create the empty per-user association key: $SubKey"
    }
    $key.Dispose()
    Assert-AssociationKeyEmpty $SubKey "Empty-key smoke setup"
}

function Remove-EmptyAssociationKey([string] $SubKey) {
    Assert-AssociationKeyEmpty $SubKey "Absent-key smoke setup"
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey(
        "Software\Classes\$SubKey", $false)
    Assert-AssociationKeyAbsent $SubKey "Absent-key smoke setup"
}

function Get-AssociationSnapshot {
    return @($script:AssociationSpecs | ForEach-Object {
        $current = Read-AssociationValue $_.SubKey $_.ValueName
        [pscustomobject]@{
            SubKey = $_.SubKey
            ValueName = $_.ValueName
            KeyPresent = $current.KeyPresent
            Present = $current.Present
            Value = $current.Value
            Kind = $current.Kind
        }
    })
}

function Assert-AssociationSnapshot($ExpectedSnapshot, [string] $Label) {
    foreach ($expected in $ExpectedSnapshot) {
        $current = Read-AssociationValue $expected.SubKey $expected.ValueName
        if ($current.KeyPresent -ne $expected.KeyPresent `
            -or $current.Present -ne $expected.Present `
            -or ($current.Present -and ($current.Value -ne $expected.Value `
                -or $current.Kind -ne $expected.Kind))) {
            throw "$Label did not restore $($expected.SubKey) [$($expected.ValueName)] exactly."
        }
    }
}

function Assert-AssociationBaseline {
    Assert-AssociationSnapshot $script:AssociationBaseline "Squirrel uninstall"
}

function Restore-AssociationSnapshot($Snapshot) {
    foreach ($expected in $Snapshot) {
        $path = "Software\Classes\$($expected.SubKey)"
        if ($expected.Present) {
            Write-AssociationValue $expected.SubKey $expected.ValueName `
                $expected.Value $expected.Kind
            continue
        }
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $true)
        if ($null -ne $key) {
            try { $key.DeleteValue($expected.ValueName, $false) }
            finally { $key.Dispose() }
        }
    }

    $expectedKeyPresence = @{}
    foreach ($expected in $Snapshot) {
        if (-not $expectedKeyPresence.ContainsKey($expected.SubKey)) {
            $expectedKeyPresence[$expected.SubKey] = $expected.KeyPresent
        }
    }

    $candidateKeys = @(
        $script:AssociationSpecs.SubKey
        "qBittorrentMaterial.torrent\shell\open"
        "qBittorrentMaterial.torrent\shell"
        "magnet\shell\open"
        "magnet\shell"
    ) | Sort-Object -Unique | Sort-Object Length -Descending
    foreach ($subKey in $candidateKeys) {
        $path = "Software\Classes\$subKey"
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
        if ($null -eq $key) {
            if ($expectedKeyPresence.ContainsKey($subKey) `
                -and $expectedKeyPresence[$subKey]) {
                $restoredKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
                if ($null -eq $restoredKey) {
                    throw "Could not restore the originally empty association key: $subKey"
                }
                $restoredKey.Dispose()
            }
            continue
        }
        try {
            $empty = ($key.GetSubKeyNames().Count -eq 0 `
                -and $key.GetValueNames().Count -eq 0)
        }
        finally { $key.Dispose() }
        $shouldRemain = $expectedKeyPresence.ContainsKey($subKey) `
            -and $expectedKeyPresence[$subKey]
        if ($empty -and -not $shouldRemain) {
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($path, $false)
        }
    }
}

function Get-SquirrelShortcuts {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    $programs = Join-Path `
        ([Environment]::GetFolderPath([Environment+SpecialFolder]::StartMenu) `
        ) "Programs"
    $candidates = @(
        Get-ChildItem -LiteralPath $desktop -Filter "*qBittorrent*.lnk" `
            -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $programs -Filter "*qBittorrent*.lnk" `
            -File -Recurse -ErrorAction SilentlyContinue
    )
    $shell = New-Object -ComObject WScript.Shell
    $stubPath = Join-Path $script:InstallRoot "qbittorrent.exe"
    return @($candidates | ForEach-Object {
        $shortcut = $shell.CreateShortcut($_.FullName)
        if ($shortcut.TargetPath -eq $stubPath) {
            [pscustomobject]@{
                Path = $_.FullName
                TargetPath = $shortcut.TargetPath
                Arguments = $shortcut.Arguments
                WorkingDirectory = $shortcut.WorkingDirectory
                IsDesktop = $_.DirectoryName -eq $desktop
                IsStartMenu = $_.FullName.StartsWith(
                    $programs, [StringComparison]::OrdinalIgnoreCase)
            }
        }
    })
}

function Wait-ForInstalledApplication([string] $ExecutablePath, [int] $TimeoutSeconds = 45) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $match = @(Get-Process qbittorrent -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -eq $ExecutablePath } catch { $false }
        } | Select-Object -First 1)
        if ($match.Count -eq 1) { return $match[0] }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "The installed application did not start within $TimeoutSeconds seconds: $ExecutablePath"
}

function Assert-Installed([string] $Version) {
    $appDirectory = Join-Path $script:InstallRoot "app-$Version"
    $executable = Join-Path $appDirectory "qbittorrent.exe"
    $requiredFiles = @(
        (Join-Path $script:InstallRoot "Update.exe"),
        (Join-Path $script:InstallRoot "qbittorrent.exe"),
        $executable,
        (Join-Path $appDirectory "qt.conf"),
        (Join-Path $appDirectory "plugins/platforms/qwindows.dll"),
        (Join-Path $appDirectory "plugins/platforms/qoffscreen.dll")
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "The Squirrel install is incomplete: $requiredFile"
        }
    }
    foreach ($debugPlugin in @(
        (Join-Path $appDirectory "plugins/platforms/qwindowsd.dll"),
        (Join-Path $appDirectory "plugins/platforms/qoffscreend.dll")
    )) {
        if (Test-Path -LiteralPath $debugPlugin) {
            throw "A debug Qt plugin leaked into the release: $debugPlugin"
        }
    }

    $qtConfiguration = @(Get-Content -LiteralPath (Join-Path $appDirectory "qt.conf"))
    if ($qtConfiguration.Count -ne 2 -or $qtConfiguration[0] -ne "[Paths]" `
        -or $qtConfiguration[1] -ne "Prefix = .") {
        throw "The flattened Squirrel runtime has an invalid qt.conf."
    }

    $shortcuts = @(Get-SquirrelShortcuts)
    if (@($shortcuts | Where-Object IsDesktop).Count -ne 1 `
        -or @($shortcuts | Where-Object IsStartMenu).Count -ne 1) {
        throw "Expected one Squirrel Desktop shortcut and one Start Menu shortcut."
    }
    foreach ($shortcut in $shortcuts) {
        if ($shortcut.TargetPath -ne (Join-Path $script:InstallRoot "qbittorrent.exe") `
            -or $shortcut.WorkingDirectory -ne $appDirectory) {
            throw "Shortcut does not target the Squirrel execution stub for app-$Version`: $($shortcut.Path)"
        }
    }

    $expectedCommand = '"' + (Join-Path $script:InstallRoot "qbittorrent.exe") + '" "%1"'
    $torrentDefault = Read-AssociationValue ".torrent"
    $torrentContentType = Read-AssociationValue ".torrent" "Content Type"
    $torrentCommand = Read-AssociationValue `
        "qBittorrentMaterial.torrent\shell\open\command"
    $magnetProtocol = Read-AssociationValue "magnet" "URL Protocol"
    $magnetCommand = Read-AssociationValue "magnet\shell\open\command"
    if (-not $torrentDefault.Present `
        -or $torrentDefault.Value -ne "qBittorrentMaterial.torrent" `
        -or -not $torrentContentType.Present `
        -or $torrentContentType.Value -ne "application/x-bittorrent" `
        -or -not $torrentCommand.Present `
        -or $torrentCommand.Value -ne $expectedCommand `
        -or -not $magnetProtocol.Present `
        -or $magnetProtocol.Value -ne "" `
        -or -not $magnetCommand.Present `
        -or $magnetCommand.Value -ne $expectedCommand) {
        throw "The Squirrel lifecycle hook did not register .torrent and magnet: to the stable execution stub."
    }

    return [pscustomobject]@{
        AppDirectory = $appDirectory
        Executable = $executable
        Stub = Join-Path $script:InstallRoot "qbittorrent.exe"
        Updater = Join-Path $script:InstallRoot "Update.exe"
        Shortcuts = $shortcuts
    }
}

function Assert-Uninstalled {
    $remainingAppDirectories = @(
        Get-ChildItem -LiteralPath $script:InstallRoot -Directory `
            -Filter "app-*" -ErrorAction SilentlyContinue
    )
    $remainingShortcuts = @(Get-SquirrelShortcuts)
    $forbiddenPaths = @(
        (Join-Path $script:InstallRoot "packages"),
        (Join-Path $script:InstallRoot "qbittorrent.exe")
    )
    if ($remainingAppDirectories.Count -ne 0 -or $remainingShortcuts.Count -ne 0 `
        -or @($forbiddenPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0) {
        throw "Squirrel uninstall left an app version, package cache, execution stub, or shortcut behind."
    }

    # Squirrel 2.0.1 deliberately retains its updater and a .dead tombstone so
    # an accidentally elevated launch cannot resurrect an uninstalled app.
    $allowedRemainders = @(".dead", "Update.exe")
    $unexpectedRemainders = @(
        Get-ChildItem -LiteralPath $script:InstallRoot -Force `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $allowedRemainders }
    )
    if ($unexpectedRemainders.Count -ne 0) {
        throw "Squirrel uninstall left unexpected files: $($unexpectedRemainders.Name -join ', ')."
    }
    Assert-AssociationBaseline
}

function Invoke-SquirrelUninstall {
    $updater = Join-Path $script:InstallRoot "Update.exe"
    Invoke-CheckedProcess $updater @("--uninstall", "--silent") "Squirrel uninstall"
    Start-Sleep -Seconds 2
    Assert-Uninstalled
}

function Invoke-AssociationKeyPresenceSmoke(
    [string] $SetupPath,
    [string] $Version
) {
    $topLevelKeys = @(".torrent", "magnet")

    foreach ($subKey in $topLevelKeys) {
        New-EmptyAssociationKey $subKey
    }
    $script:AssociationBaseline = Get-AssociationSnapshot
    Invoke-CheckedProcess $SetupPath @("--silent") "Empty association-key silent Setup"
    [void](Assert-Installed $Version)
    Invoke-SquirrelUninstall
    foreach ($subKey in $topLevelKeys) {
        Assert-AssociationKeyEmpty $subKey "Empty-key Squirrel uninstall"
    }
    Write-Host "Verified originally empty per-user .torrent and magnet association keys remain present and empty after uninstall."

    foreach ($subKey in $topLevelKeys) {
        Remove-EmptyAssociationKey $subKey
    }
    $script:AssociationBaseline = Get-AssociationSnapshot
    Invoke-CheckedProcess $SetupPath @("--silent") "Absent association-key silent Setup"
    [void](Assert-Installed $Version)
    Invoke-SquirrelUninstall
    foreach ($subKey in $topLevelKeys) {
        Assert-AssociationKeyAbsent $subKey "Absent-key Squirrel uninstall"
    }
    Write-Host "Verified originally absent per-user .torrent and magnet association keys remain absent after uninstall."
}

function Invoke-IsolatedLaunch(
    [string] $LaunchPath,
    [string] $ExpectedExecutable,
    [string] $Label
) {
    $identifier = [guid]::NewGuid().ToString("N")
    $profileRoot = Join-Path $script:ScratchRoot "qbt-material-profile-$identifier"
    $workspaceRoot = Join-Path $script:ScratchRoot "qbt-material-workspace-$identifier"
    $originalPlatform = $env:QT_QPA_PLATFORM
    $originalWorkspace = $env:QBT_WORKSPACE_ROOT
    $originalDisableUpdates = $env:QBT_DISABLE_PROGRAM_UPDATES
    try {
        $env:QT_QPA_PLATFORM = "offscreen"
        $env:QBT_WORKSPACE_ROOT = $workspaceRoot
        $env:QBT_DISABLE_PROGRAM_UPDATES = "1"
        Start-Process -FilePath $LaunchPath `
            -ArgumentList @("--profile-root=$profileRoot") | Out-Null
        $application = Wait-ForInstalledApplication $ExpectedExecutable
        $workspacePath = Join-Path $workspaceRoot "workspace.json"
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf) `
            -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 250
        }
        if (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf)) {
            throw "$Label launched, but it did not initialize its isolated workspace."
        }
        Stop-Process -Id $application.Id -Force
        $application.WaitForExit()
        Write-Host "$Label launched $ExpectedExecutable and initialized workspace state."
    }
    finally {
        $env:QT_QPA_PLATFORM = $originalPlatform
        $env:QBT_WORKSPACE_ROOT = $originalWorkspace
        $env:QBT_DISABLE_PROGRAM_UPDATES = $originalDisableUpdates
    }
}

function Invoke-WorkspaceRecoverySmoke([string] $InstalledExecutable) {
    $identifier = [guid]::NewGuid().ToString("N")
    $profileRoot = Join-Path $script:ScratchRoot "qbt-material-recovery-profile-$identifier"
    $workspaceRoot = Join-Path $script:ScratchRoot "qbt-material-recovery-$identifier"
    $smokeLogRoot = Join-Path $script:ScratchRoot "qbt-material-smoke-logs-$identifier"
    New-Item -ItemType Directory -Force -Path $smokeLogRoot | Out-Null

    $gitExecutable = (Get-Command git.exe -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source
    $originalPath = $env:PATH
    $originalPlatform = $env:QT_QPA_PLATFORM
    $originalWorkspace = $env:QBT_WORKSPACE_ROOT
    $originalDisableUpdates = $env:QBT_DISABLE_PROGRAM_UPDATES

    function Write-SmokeOutput($Launch) {
        foreach ($stream in @(
            @{ Name = "stdout"; Path = $Launch.Stdout },
            @{ Name = "stderr"; Path = $Launch.Stderr }
        )) {
            Write-Host "::group::$($Launch.Label) $($stream.Name)"
            if (Test-Path -LiteralPath $stream.Path) {
                $content = Get-Content -Raw -LiteralPath $stream.Path
                if ([string]::IsNullOrEmpty($content)) { Write-Host "<empty>" }
                else { Write-Host $content }
            }
            else { Write-Host "<missing>" }
            Write-Host "::endgroup::"
        }
    }

    function Start-SmokeApplication([string] $Label) {
        $safeLabel = $Label -replace '[^A-Za-z0-9_-]', '-'
        $stdout = Join-Path $smokeLogRoot "$safeLabel.stdout.log"
        $stderr = Join-Path $smokeLogRoot "$safeLabel.stderr.log"
        $process = Start-Process -FilePath $InstalledExecutable -PassThru `
            -ArgumentList @("--profile-root=$profileRoot") `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Start-Sleep -Seconds 10
        $launch = [pscustomobject]@{
            Label = $Label
            Process = $process
            Stdout = $stdout
            Stderr = $stderr
        }
        if ($process.HasExited) {
            Write-SmokeOutput $launch
            throw "$Label exited during smoke test with code $($process.ExitCode)."
        }
        return $launch
    }

    function Stop-SmokeApplication($Launch) {
        Stop-Process -Id $Launch.Process.Id -Force
        $Launch.Process.WaitForExit()
        Write-SmokeOutput $Launch
    }

    try {
        $env:PATH = (@($originalPath -split ";" | Where-Object {
            $segment = $_.Trim()
            if ([string]::IsNullOrWhiteSpace($segment)) { return $false }
            -not (Test-Path -LiteralPath (Join-Path $segment "git.exe")) `
                -and -not (Test-Path -LiteralPath (Join-Path $segment "git.cmd"))
        }) -join ";")
        $gitOnPath = @($env:PATH -split ";" | Where-Object {
            $segment = $_.Trim()
            $segment -and ((Test-Path -LiteralPath (Join-Path $segment "git.exe")) `
                -or (Test-Path -LiteralPath (Join-Path $segment "git.cmd")))
        })
        if ($gitOnPath.Count -ne 0) {
            throw "Git must be absent from PATH during the installed-app smoke test."
        }
        $env:QBT_WORKSPACE_ROOT = $workspaceRoot
        $env:QT_QPA_PLATFORM = "offscreen"
        $env:QBT_DISABLE_PROGRAM_UPDATES = "1"

        $initialLaunch = Start-SmokeApplication "Installed application"
        Stop-SmokeApplication $initialLaunch

        $workspaceJson = Join-Path $workspaceRoot "workspace.json"
        $workspaceGit = Join-Path $workspaceRoot ".git"
        $workspaceTabs = @(Get-ChildItem -LiteralPath (Join-Path $workspaceRoot "tabs") `
            -Filter "*.md" -File -ErrorAction SilentlyContinue)
        if (-not (Test-Path -LiteralPath $workspaceJson) `
            -or -not (Test-Path -LiteralPath $workspaceGit) `
            -or $workspaceTabs.Count -ne 1) {
            throw "Installed application did not initialize the expected workspace and Git history."
        }
        $workspaceState = Get-Content -Raw -LiteralPath $workspaceJson | ConvertFrom-Json
        if ($workspaceState.type -ne "qbt-material-workspace" `
            -or $workspaceState.schemaVersion -ne 2 `
            -or @($workspaceState.tabs).Count -ne 1) {
            throw "Persisted workspace metadata failed schema validation."
        }

        $orphanId = [guid]::NewGuid().ToString()
        $orphanContent = "Recovered after interrupted metadata save"
        $orphanPath = Join-Path $workspaceRoot "tabs/$orphanId.md"
        [IO.File]::WriteAllText($orphanPath, $orphanContent, [Text.UTF8Encoding]::new($false))

        $recoveryLaunch = Start-SmokeApplication "Crash-recovery application"
        Stop-SmokeApplication $recoveryLaunch

        $recoveredState = Get-Content -Raw -LiteralPath $workspaceJson | ConvertFrom-Json
        $recoveredTabs = @($recoveredState.tabs)
        $recoveredRecord = @($recoveredTabs | Where-Object { $_.id -eq $orphanId })
        if ($recoveredTabs.Count -ne 2 -or $recoveredRecord.Count -ne 1 `
            -or $recoveredRecord[0].name -notlike "Recovered tab *" `
            -or (Get-Content -Raw -LiteralPath $orphanPath) -ne $orphanContent) {
            throw "Interrupted tab body was not recovered without data loss."
        }
        $recoveryHeadFiles = @(& $gitExecutable -C $workspaceRoot ls-tree -r --name-only HEAD)
        if ($recoveryHeadFiles -notcontains "tabs/$orphanId.md") {
            throw "Recovered tab was not committed by embedded libgit2."
        }

        $remainingTabs = @($recoveredTabs | Where-Object { $_.id -ne $orphanId })
        $recoveredState.tabs = $remainingTabs
        $recoveredState.activeTabId = $remainingTabs[0].id
        [IO.File]::WriteAllText(
            $workspaceJson,
            ($recoveredState | ConvertTo-Json -Depth 20),
            [Text.UTF8Encoding]::new($false))

        $closeRecoveryLaunch = Start-SmokeApplication "Interrupted-close application"
        Stop-SmokeApplication $closeRecoveryLaunch
        $closedState = Get-Content -Raw -LiteralPath $workspaceJson | ConvertFrom-Json
        if (@($closedState.tabs).Count -ne 1 `
            -or @($closedState.tabs | Where-Object { $_.id -eq $orphanId }).Count -ne 0 `
            -or (Test-Path -LiteralPath $orphanPath)) {
            throw "Interrupted close was resurrected instead of completed."
        }

        & $gitExecutable -C $workspaceRoot rev-parse --verify HEAD | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Embedded libgit2 did not create the initial workspace commit."
        }
        & $gitExecutable -C $workspaceRoot fsck --strict
        if ($LASTEXITCODE -ne 0) { throw "Workspace repository failed git fsck." }
        $headFiles = @(& $gitExecutable -C $workspaceRoot ls-tree -r --name-only HEAD)
        if ($headFiles -contains "tabs/$orphanId.md") {
            throw "Closed tab remains in the final embedded Git commit."
        }
        $workspaceStatus = @(& $gitExecutable -C $workspaceRoot status --porcelain)
        if ($workspaceStatus.Count -ne 0) {
            throw "Recovered workspace repository is not clean."
        }
    }
    finally {
        $env:PATH = $originalPath
        $env:QT_QPA_PLATFORM = $originalPlatform
        $env:QBT_WORKSPACE_ROOT = $originalWorkspace
        $env:QBT_DISABLE_PROGRAM_UPDATES = $originalDisableUpdates
    }
}

$hasPriorFeed = $ExpectDelta.IsPresent

$InstallerPath = Resolve-RequiredFile $InstallerPath "Current Squirrel Setup"
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory -ErrorAction Stop).Path
$releaseManifest = Resolve-RequiredFile (Join-Path $ReleaseDirectory "RELEASES") "Squirrel feed manifest"
$currentFullPackage = Resolve-RequiredFile `
    (Join-Path $ReleaseDirectory "qBittorrentMaterial-$PackageVersion-full.nupkg") `
    "Current Squirrel full package"
$fullEntry = Assert-ReleaseManifestPackage `
    $releaseManifest $currentFullPackage "Current Squirrel full package"

$currentDeltaName = "qBittorrentMaterial-$PackageVersion-delta.nupkg"
$currentDeltaPath = Join-Path $ReleaseDirectory $currentDeltaName
$currentDeltaFiles = @(
    Get-ChildItem -LiteralPath $ReleaseDirectory -Filter $currentDeltaName -File
)
$escapedDeltaName = [regex]::Escape($currentDeltaName)
$deltaEntryPattern = "^[0-9A-Fa-f]{40}\s+$escapedDeltaName\s+[0-9]+(?:\s+#.*)?$"
$currentDeltaManifestLines = @(
    Get-Content -LiteralPath $releaseManifest |
        Where-Object { $_ -match $deltaEntryPattern }
)
$expectedDeltaCount = if ($hasPriorFeed) { 1 } else { 0 }
if ($currentDeltaFiles.Count -ne $expectedDeltaCount `
    -or $currentDeltaManifestLines.Count -ne $expectedDeltaCount) {
    $feedDescription = if ($hasPriorFeed) {
        "a release with a prior Squirrel feed"
    }
    else {
        "the first Squirrel release"
    }
    throw "The update feed for $feedDescription must contain exactly $expectedDeltaCount current delta package and RELEASES entry; found $($currentDeltaFiles.Count) package(s) and $($currentDeltaManifestLines.Count) entry/entries."
}
$currentDeltaPackage = $null
$deltaEntry = $null
if ($hasPriorFeed) {
    $currentDeltaPackage = Resolve-RequiredFile $currentDeltaPath "Current Squirrel delta package"
    $deltaEntry = Assert-ReleaseManifestPackage `
        $releaseManifest $currentDeltaPackage "Current Squirrel delta package"
    if ((Get-Item -LiteralPath $currentDeltaPackage).Length `
        -ge (Get-Item -LiteralPath $currentFullPackage).Length) {
        throw "The current delta package is not smaller than the full package, so Squirrel would select the full-package path."
    }
}
$script:InstallRoot = Join-Path $env:LOCALAPPDATA "qBittorrentMaterial"
$script:AssociationSpecs = @(
    [pscustomobject]@{ SubKey = ".torrent"; ValueName = "" },
    [pscustomobject]@{ SubKey = ".torrent"; ValueName = "Content Type" },
    [pscustomobject]@{ SubKey = "qBittorrentMaterial.torrent"; ValueName = "" },
    [pscustomobject]@{ SubKey = "qBittorrentMaterial.torrent\DefaultIcon"; ValueName = "" },
    [pscustomobject]@{ SubKey = "qBittorrentMaterial.torrent\shell\open\command"; ValueName = "" },
    [pscustomobject]@{ SubKey = "magnet"; ValueName = "" },
    [pscustomobject]@{ SubKey = "magnet"; ValueName = "URL Protocol" },
    [pscustomobject]@{ SubKey = "magnet\DefaultIcon"; ValueName = "" },
    [pscustomobject]@{ SubKey = "magnet\shell\open\command"; ValueName = "" }
)
$script:OriginalAssociationBaseline = Get-AssociationSnapshot
$script:AssociationBaseline = $script:OriginalAssociationBaseline
$script:SeededAssociationBaseline = $false
$script:AssociationStateChanged = $false
$script:ScratchRoot = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
}
else {
    [IO.Path]::GetTempPath()
}
Assert-PackagedExecutableVersion $currentFullPackage $PackageVersion $script:ScratchRoot

if (Test-Path -LiteralPath $script:InstallRoot) {
    $existingNames = @(Get-ChildItem -LiteralPath $script:InstallRoot -Force | Select-Object -ExpandProperty Name)
    if (@($existingNames | Where-Object { $_ -notin @(".dead", "Update.exe") }).Count -ne 0) {
        throw "Refusing to overwrite an existing Squirrel installation at $script:InstallRoot."
    }
}

try {
if ($env:GITHUB_ACTIONS -eq "true") {
    # These key-shape scenarios must never erase an unknown user's handlers.
    # The hosted runner starts clean; any existing per-user root fails closed.
    foreach ($subKey in @(".torrent", "magnet")) {
        Assert-AssociationKeyAbsent $subKey "Association key-presence smoke precondition"
    }
    $script:AssociationStateChanged = $true

    $script:SeededAssociationBaseline = $true
    Write-AssociationValue ".torrent" "" "Squirrel.Association.Sentinel"
    Write-AssociationValue ".torrent" "Content Type" "application/x-squirrel-sentinel"
    Write-AssociationValue "qBittorrentMaterial.torrent" "" "Squirrel torrent sentinel"
    Write-AssociationValue "qBittorrentMaterial.torrent\DefaultIcon" "" `
        '%SystemRoot%\SquirrelAssociationSentinel\torrent.ico,0' `
        ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    Write-AssociationValue "qBittorrentMaterial.torrent\shell\open\command" "" `
        '"C:\SquirrelAssociationSentinel\torrent-handler.exe" "%1"'
    Write-AssociationValue "magnet" "" "URL:Squirrel Magnet Sentinel"
    Write-AssociationValue "magnet" "URL Protocol" "squirrel-protocol-sentinel"
    Write-AssociationValue "magnet\DefaultIcon" "" `
        '%SystemRoot%\SquirrelAssociationSentinel\magnet.ico,0' `
        ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    Write-AssociationValue "magnet\shell\open\command" "" `
        '"C:\SquirrelAssociationSentinel\magnet-handler.exe" "%1"'
    $script:AssociationBaseline = Get-AssociationSnapshot
}

if ($hasPriorFeed) {
    # The prior public feed is input to Squirrel's delta generator, but a
    # token-bearing CI job must not execute an old Setup.exe merely to exercise
    # an upgrade path. The delta and RELEASES assertions above prove the exact
    # current feed shape without trusting that historical executable.
    Write-Host "Verified the current delta package and RELEASES entry from a prior feed without executing a prior Setup."
}
else {
    Write-Host "Verified the first Squirrel release has no delta; prior-feed delta validation is not applicable."
}

Invoke-CheckedProcess $InstallerPath @("--silent") "Current silent Setup"
$silentInstall = Assert-Installed $PackageVersion
Invoke-WorkspaceRecoverySmoke $silentInstall.Executable
Invoke-SquirrelUninstall
Write-Host "Verified silent Setup, installed runtime, workspace recovery, and uninstall."

$normalWorkspace = Join-Path $script:ScratchRoot `
    "qbt-material-normal-install-$([guid]::NewGuid().ToString('N'))"
$originalPlatform = $env:QT_QPA_PLATFORM
$originalWorkspace = $env:QBT_WORKSPACE_ROOT
$originalDisableUpdates = $env:QBT_DISABLE_PROGRAM_UPDATES
try {
    $env:QT_QPA_PLATFORM = "offscreen"
    $env:QBT_WORKSPACE_ROOT = $normalWorkspace
    $env:QBT_DISABLE_PROGRAM_UPDATES = "1"
    # Start-Process -Wait follows the whole process tree on Windows and would
    # therefore wait forever for the deliberately auto-launched first-run app.
    # Wait only for the Setup process; the next assertion finds its child app.
    Invoke-CheckedRootProcess $InstallerPath @() "Current normal Setup"
    $normalInstall = Assert-Installed $PackageVersion
    if ($SkipNormalSetupLaunchAssertion) {
        Write-Warning "Normal Setup auto-launch assertion was explicitly skipped."
    }
    else {
        $normalApplication = Wait-ForInstalledApplication $normalInstall.Executable
        Stop-Process -Id $normalApplication.Id -Force
        $normalApplication.WaitForExit()
    }
}
finally {
    $env:QT_QPA_PLATFORM = $originalPlatform
    $env:QBT_WORKSPACE_ROOT = $originalWorkspace
    $env:QBT_DISABLE_PROGRAM_UPDATES = $originalDisableUpdates
}

foreach ($shortcut in $normalInstall.Shortcuts) {
    Invoke-IsolatedLaunch $shortcut.Path $normalInstall.Executable `
        "Shortcut $($shortcut.Path)"
}
Invoke-SquirrelUninstall

if ($script:SeededAssociationBaseline) {
    Write-Host "Verified exact restoration of pre-existing per-user .torrent and magnet association values."
    # Run the current-installer key-shape cycles after the primary setup checks
    # so every executed installer is the exact artifact built in this job.
    Restore-AssociationSnapshot $script:OriginalAssociationBaseline
    Assert-AssociationSnapshot $script:OriginalAssociationBaseline `
        "Association key-presence smoke setup"
    $script:AssociationBaseline = $script:OriginalAssociationBaseline
    Invoke-AssociationKeyPresenceSmoke $InstallerPath $PackageVersion
}
Write-Host "Verified normal Setup launch, Desktop/Start Menu shortcuts, and clean Update.exe uninstall."
Write-Host "RELEASES: $releaseManifest"
Write-Host "Full package: $currentFullPackage"
if ($hasPriorFeed) {
    Write-Host "Delta package: $currentDeltaPackage"
}
}
finally {
    if ($script:AssociationStateChanged) {
        Restore-AssociationSnapshot $script:OriginalAssociationBaseline
        Assert-AssociationSnapshot $script:OriginalAssociationBaseline `
            "Association smoke cleanup"
        Write-Host "Restored the original per-user association values after the smoke test."
    }
}
