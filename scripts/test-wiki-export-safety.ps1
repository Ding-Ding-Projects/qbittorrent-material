[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$exportScript = Join-Path $RepositoryRoot "scripts/export-github-wiki.ps1"
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("qbt-wiki-export-safety-" + [guid]::NewGuid().ToString("N"))
$wikiRoot = Join-Path $testRoot "Wiki"
$outsideCanary = Join-Path $testRoot "outside-canary.txt"
$homeCanary = Join-Path $wikiRoot "Home.md"
$gitCanary = Join-Path $wikiRoot ".git/config"
$manifestPath = Join-Path $wikiRoot ".qbt-material-generated.json"

function Write-Utf8([string] $path, [string] $content) {
    $parent = Split-Path -Parent $path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($path, $content, $utf8WithoutBom)
}

function Assert-Content([string] $path, [string] $expected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Safety canary is missing: $path"
    }
    $actual = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($actual -cne $expected) {
        throw "Safety canary changed unexpectedly: $path"
    }
}

function Write-Manifest([object[]] $files, [int] $schemaVersion = 1) {
    $manifest = [ordered]@{
        schemaVersion = $schemaVersion
        files = @($files)
    } | ConvertTo-Json -Depth 4
    Write-Utf8 $manifestPath ($manifest + "`n")
}

function Assert-UnsafeManifestRejected([string] $name, [object[]] $files) {
    Write-Manifest $files
    $rejected = $false
    try {
        & $exportScript -WikiWorkingTree $wikiRoot -RepositoryRoot $RepositoryRoot
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Unsafe manifest case '$name' was accepted."
    }

    # Validation must finish before the exporter overwrites its first page.
    Assert-Content $homeCanary "home canary"
    Assert-Content $gitCanary "git canary"
    Assert-Content $outsideCanary "outside canary"
    Write-Host "[PASS] rejected $name before touching export or safety canaries"
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $wikiRoot ".git") | Out-Null
    Write-Utf8 $outsideCanary "outside canary"
    Write-Utf8 $homeCanary "home canary"
    Write-Utf8 $gitCanary "git canary"

    Assert-UnsafeManifestRejected "parent traversal" @("../outside-canary.txt")
    Assert-UnsafeManifestRejected "backslash traversal" @("..\outside-canary.txt")
    Assert-UnsafeManifestRejected "rooted path" @($outsideCanary)
    Assert-UnsafeManifestRejected "Git metadata" @(".git/config")
    Assert-UnsafeManifestRejected "dot directory" @("images/.private/canary.png")
    Assert-UnsafeManifestRejected "non-generated namespace" @("notes/private.txt")
    Assert-UnsafeManifestRejected "non-string entry" @(42)

    $stalePage = Join-Path $wikiRoot "Stale.md"
    $staleImage = Join-Path $wikiRoot "images/app/stale.png"
    Write-Utf8 $stalePage "stale page"
    Write-Utf8 $staleImage "stale image"
    Write-Manifest @("Stale.md", "images/app/stale.png")

    & $exportScript -WikiWorkingTree $wikiRoot -RepositoryRoot $RepositoryRoot
    if ((Test-Path -LiteralPath $stalePage) -or (Test-Path -LiteralPath $staleImage)) {
        throw "Validated stale generated paths were not removed."
    }
    Assert-Content $gitCanary "git canary"
    Assert-Content $outsideCanary "outside canary"
    Write-Host "[PASS] valid generated paths export and stale cleanup preserve safety canaries"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
