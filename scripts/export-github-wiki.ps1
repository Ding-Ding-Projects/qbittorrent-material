param(
    [Parameter(Mandatory = $true)]
    [string] $WikiWorkingTree,
    [string] $RepositoryRoot
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$wikiRoot = [System.IO.Path]::GetFullPath($WikiWorkingTree)
$docsRoot = Join-Path $RepositoryRoot "docs"
$canonicalWikiRoot = Join-Path $docsRoot "wiki"
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$manifestPath = Join-Path $wikiRoot ".qbt-material-generated.json"
$previousGeneratedPaths = @()
$generatedPaths = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath (Join-Path $wikiRoot ".git"))) {
    throw "WikiWorkingTree must be a cloned Git repository: $wikiRoot"
}

if (Test-Path -LiteralPath $manifestPath) {
    try {
        $previousManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        if ($previousManifest.files) {
            $previousGeneratedPaths = @($previousManifest.files)
        }
    }
    catch {
        throw "Could not parse the existing Wiki export manifest: $manifestPath"
    }
}

function Write-Utf8([string] $path, [string] $content) {
    [System.IO.File]::WriteAllText($path, $content.TrimEnd() + "`n", $utf8WithoutBom)
    $relative = $path.Substring($wikiRoot.Length).TrimStart('\', '/').Replace('\', '/')
    $generatedPaths.Add($relative)
}

function Convert-WikiLinks([string] $content) {
    $replacements = [ordered]@{
        '../ARCHITECTURE.md' = 'Reference-Architecture'
        '../BUILDING.md' = 'Reference-Building'
        '../CONTRACTS.md' = 'Reference-Contracts'
        '../DESIGN_SYSTEM.md' = 'Reference-Design-System'
        '../ENGINE_API.md' = 'Reference-Engine-API'
        '../FEATURE_SPEC.md' = 'Reference-Feature-Spec'
        '../PAGES.md' = 'Reference-Documentation-Site'
        'PAGES.md' = 'Reference-Documentation-Site'
        '../REQUIREMENTS.md' = 'Reference-Requirements'
        '../SCREENSHOTS.md' = 'Reference-Visual-Tour'
        'SCREENSHOTS.md' = 'Reference-Visual-Tour'
        '../WORKSPACE_TABS.md' = 'Reference-Workspace-Tabs'
        'WORKSPACE_TABS.md' = 'Reference-Workspace-Tabs'
        'wiki/Workspace-Tabs.md' = 'Workspace-Tabs'
        'wiki/Troubleshooting.md' = 'Troubleshooting'
        'Getting-Started.md' = 'Getting-Started'
        'Interface-Tour.md' = 'Interface-Tour'
        'Desktop-Features.md' = 'Desktop-Features'
        'Workspace-Tabs.md' = 'Workspace-Tabs'
        'Search-Import-Export.md' = 'Search-Import-Export'
        'Releases.md' = 'Releases'
        'Architecture.md' = 'Architecture'
        'Troubleshooting.md' = 'Troubleshooting'
        'Contributing.md' = 'Contributing'
    }

    foreach ($entry in $replacements.GetEnumerator()) {
        $content = $content.Replace($entry.Key, $entry.Value)
    }
    return (($content -split "`r?`n") | ForEach-Object { $_.TrimEnd() }) -join "`n"
}

$canonicalPages = Get-ChildItem -LiteralPath $canonicalWikiRoot -Filter "*.md" -File
foreach ($page in $canonicalPages) {
    $content = [System.IO.File]::ReadAllText($page.FullName, [System.Text.Encoding]::UTF8)
    $content = Convert-WikiLinks $content
    if ($page.Name -eq "Home.md") {
        $content += @"

## Searchable documentation site

Open the [full Material documentation experience](https://ding-ding-projects.github.io/qbittorrent-material/) for regex search, filter building, local imports, portable exports, dark mode, and the complete embedded corpus.
"@
    }
    Write-Utf8 (Join-Path $wikiRoot $page.Name) $content
}

$referencePages = [ordered]@{
    'ARCHITECTURE.md' = 'Reference-Architecture.md'
    'BUILDING.md' = 'Reference-Building.md'
    'CONTRACTS.md' = 'Reference-Contracts.md'
    'DESIGN_SYSTEM.md' = 'Reference-Design-System.md'
    'ENGINE_API.md' = 'Reference-Engine-API.md'
    'FEATURE_SPEC.md' = 'Reference-Feature-Spec.md'
    'PAGES.md' = 'Reference-Documentation-Site.md'
    'REQUIREMENTS.md' = 'Reference-Requirements.md'
    'SCREENSHOTS.md' = 'Reference-Visual-Tour.md'
    'WORKSPACE_TABS.md' = 'Reference-Workspace-Tabs.md'
}

foreach ($entry in $referencePages.GetEnumerator()) {
    $content = [System.IO.File]::ReadAllText(
        (Join-Path $docsRoot $entry.Key), [System.Text.Encoding]::UTF8)
    $content = Convert-WikiLinks $content
    Write-Utf8 (Join-Path $wikiRoot $entry.Value) $content
}

$jsonPages = [ordered]@{
    'FILE_PLAN.json' = @('Reference-File-Plan.md', 'Repository File Plan')
    'SCREENS.json' = @('Reference-Screen-Blueprints.md', 'Screen Blueprints')
}

foreach ($entry in $jsonPages.GetEnumerator()) {
    $json = [System.IO.File]::ReadAllText(
        (Join-Path $docsRoot $entry.Key), [System.Text.Encoding]::UTF8)
    $body = "# $($entry.Value[1])`n`n``````json`n$json`n``````"
    Write-Utf8 (Join-Path $wikiRoot $entry.Value[0]) $body
}

$sidebar = @'
# qBittorrent Material

**Start**

- [Home](Home)
- [Getting started](Getting-Started)
- [Interface tour](Interface-Tour)
- [Windows desktop features](Desktop-Features)
- [Workspace tabs](Workspace-Tabs)
- [Search and portability](Search-Import-Export)
- [FAQ](FAQ)

**Project**

- [Releases and automation](Releases)
- [Architecture guide](Architecture)
- [Troubleshooting](Troubleshooting)
- [Contributing](Contributing)

**Complete reference**

- [Architecture](Reference-Architecture)
- [Building](Reference-Building)
- [Contracts](Reference-Contracts)
- [Design system](Reference-Design-System)
- [Engine API](Reference-Engine-API)
- [Feature specification](Reference-Feature-Spec)
- [Documentation site](Reference-Documentation-Site)
- [Requirements](Reference-Requirements)
- [Visual tour](Reference-Visual-Tour)
- [Workspace tabs](Reference-Workspace-Tabs)
- [File plan](Reference-File-Plan)
- [Screen blueprints](Reference-Screen-Blueprints)

[Searchable Pages site](https://ding-ding-projects.github.io/qbittorrent-material/)
'@
Write-Utf8 (Join-Path $wikiRoot "_Sidebar.md") $sidebar

$footer = @'
qBittorrent Material · [Documentation site](https://ding-ding-projects.github.io/qbittorrent-material/) · [Source](https://github.com/Ding-Ding-Projects/qbittorrent-material) · GPL-3.0-or-later
'@
Write-Utf8 (Join-Path $wikiRoot "_Footer.md") $footer

$wikiImages = Join-Path $wikiRoot "images"
$wikiAppImages = Join-Path $wikiImages "app"
$wikiSiteImages = Join-Path $wikiImages "site"
New-Item -ItemType Directory -Force -Path $wikiAppImages | Out-Null
New-Item -ItemType Directory -Force -Path $wikiSiteImages | Out-Null
Copy-Item -LiteralPath (Join-Path $docsRoot "assets\logo-mark.png") `
    -Destination (Join-Path $wikiImages "logo-mark.png") -Force
$generatedPaths.Add("images/logo-mark.png")
Get-ChildItem -LiteralPath (Join-Path $docsRoot "images\app") -File |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $wikiAppImages $_.Name) -Force
        $generatedPaths.Add("images/app/$($_.Name)")
    }
Get-ChildItem -LiteralPath (Join-Path $docsRoot "images\site") -File |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $wikiSiteImages $_.Name) -Force
        $generatedPaths.Add("images/site/$($_.Name)")
    }

$currentGeneratedPaths = @($generatedPaths | Sort-Object -Unique)
$wikiPrefix = $wikiRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

function Assert-NoReparsePointAncestor([string] $candidate, [string] $relativePath) {
    $normalizedRelative = $candidate.Substring($wikiPrefix.Length)
    $cursor = $wikiRoot
    foreach ($segment in ($normalizedRelative -split '[\\/]')) {
        if (-not $segment) {
            continue
        }
        $cursor = Join-Path $cursor $segment
        if (-not (Test-Path -LiteralPath $cursor)) {
            continue
        }
        $item = Get-Item -Force -LiteralPath $cursor
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove a generated path through a reparse point: $relativePath"
        }
    }
}

foreach ($relativePath in $previousGeneratedPaths) {
    if ($currentGeneratedPaths -contains $relativePath) {
        continue
    }
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $wikiRoot $relativePath))
    if (-not $candidate.StartsWith($wikiPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a generated path outside the Wiki tree: $relativePath"
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Assert-NoReparsePointAncestor -candidate $candidate -relativePath $relativePath
        Remove-Item -Force -LiteralPath $candidate
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    files = $currentGeneratedPaths
} | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($manifestPath, $manifest.TrimEnd() + "`n", $utf8WithoutBom)

Write-Host "Exported $($canonicalPages.Count) curated pages, $($referencePages.Count) references, JSON blueprints, and images to $wikiRoot."
