<#
.SYNOPSIS
    Launches the built application offscreen and fails if the QML root object
    does not load cleanly.

.DESCRIPTION
    A QML fault — a duplicate id, an unresolved type, a bad binding — compiles
    perfectly. qmlcachegen accepts it, the linker accepts it, the policy suite
    accepts it, and the application then aborts at startup with "Failed to
    create Main.qml root object". Nothing else in this repository catches that,
    which is how a build that cannot start reached the default branch.

    This runs the real binary against a throwaway profile and greps its own log
    for the faults that only appear at runtime.

    Skips (exit 0) when no built binary exists, so it can be called from the
    policy suite on a source-only checkout.
#>
[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [int] $TimeoutSeconds = 40
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepositoryRoot = Split-Path -Parent $scriptDirectory
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$exe = Join-Path $RepositoryRoot "build/qbittorrent.exe"
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Host "[SKIP] No built binary at build/qbittorrent.exe; nothing to start."
    exit 0
}

$platformPlugin = Join-Path $RepositoryRoot "build/platforms/qoffscreen.dll"
if (-not (Test-Path -LiteralPath $platformPlugin -PathType Leaf)) {
    Write-Host "[SKIP] The offscreen platform plugin is not deployed; cannot start headlessly."
    exit 0
}

# A short profile path: libgit2 refuses the resume-data repository under a deep
# directory, and the session then never reports restored.
$profileRoot = Join-Path ([IO.Path]::GetTempPath()) "qbt-qml-startup"
$logPath = Join-Path ([IO.Path]::GetTempPath()) "qbt-qml-startup.log"
foreach ($stale in @($profileRoot, $logPath)) {
    if (Test-Path -LiteralPath $stale) {
        Remove-Item -Recurse -Force -LiteralPath $stale
    }
}
New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null

$env:QT_QPA_PLATFORM = "offscreen"
$process = Start-Process -FilePath $exe `
    -ArgumentList @("--profile-root=$profileRoot") `
    -PassThru -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err"

try {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $exitedEarly = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { $exitedEarly = $true; break }
        if ((Test-Path -LiteralPath $logPath) -and
            ((Get-Content -Raw -LiteralPath $logPath) -match 'SearchController constructed|TransferListModel')) {
            break
        }
    }

    $log = ""
    foreach ($candidate in @($logPath, "$logPath.err")) {
        if (Test-Path -LiteralPath $candidate) {
            $log += (Get-Content -Raw -LiteralPath $candidate)
        }
    }

    # These only ever appear at runtime; each one aborts or degrades the UI.
    $faults = @(
        'Failed to create Main.qml root object',
        'is not unique',
        'unavailable',
        'Unable to assign',
        'ReferenceError',
        'TypeError'
    )
    $found = @($faults | Where-Object { $log -match [regex]::Escape($_) })

    if ($exitedEarly -and ($process.ExitCode -ne 0)) {
        Write-Host $log
        throw "The application exited during startup with code $($process.ExitCode)."
    }
    if ($found.Count -gt 0) {
        Write-Host $log
        throw "QML startup faults detected: $($found -join ', ')"
    }

    Write-Host "[PASS] The QML root object loaded with no runtime faults."
}
finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }
    foreach ($stale in @($profileRoot, $logPath, "$logPath.err")) {
        if (Test-Path -LiteralPath $stale) {
            Remove-Item -Recurse -Force -LiteralPath $stale -ErrorAction SilentlyContinue
        }
    }
}
