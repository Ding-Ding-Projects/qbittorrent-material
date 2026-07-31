param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$docsRoot = Join-Path $RepositoryRoot "docs"
$outputPath = Join-Path $docsRoot "content.generated.js"

if (-not (Test-Path -LiteralPath $docsRoot)) {
    throw "Documentation directory not found: $docsRoot"
}

$sourceFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$sourceFiles.Add((Get-Item -LiteralPath (Join-Path $RepositoryRoot "README.md")))

Get-ChildItem -LiteralPath $docsRoot -File -Recurse |
    Where-Object {
        $_.Extension -in @(".md", ".json") -and
        $_.FullName -notmatch "[\\/]site-audit[\\/]"
    } |
    Sort-Object FullName |
    ForEach-Object { $sourceFiles.Add($_) }

function Get-DocumentCategory([string] $repositoryPath) {
    switch -Regex ($repositoryPath) {
        '^README\.md$' { return "Overview" }
        '^docs/features/experience/' { return "Desktop · Experience" }
        '^docs/features/workspace/' { return "Desktop · Workspace" }
        '^docs/features/appearance/' { return "Desktop · Appearance" }
        '^docs/features/delivery/' { return "Desktop · Delivery" }
        '^docs/features/' { return "Desktop features" }
        '^docs/wiki/' { return "Wiki" }
        'BUILDING|REQUIREMENTS|PAGES' { return "Get started" }
        'SCREENSHOTS|SCREENS|WORKSPACE_TABS' { return "Interface" }
        'DESIGN_SYSTEM' { return "Design" }
        'ARCHITECTURE|CONTRACTS|ENGINE_API|FILE_PLAN' { return "Engineering" }
        'FEATURE_SPEC' { return "Product" }
        default { return "Reference" }
    }
}

function Get-DocumentTitle([string] $content, [string] $fallback) {
    foreach ($line in ($content -split "`r?`n")) {
        if ($line -match '^#\s+(.+?)\s*$') {
            return $Matches[1] -replace '`', ''
        }
    }
    return $fallback
}

function Get-Slug([string] $repositoryPath) {
    if ($repositoryPath -eq "README.md") {
        return "overview"
    }

    $slugSource = [System.IO.Path]::GetFileNameWithoutExtension($repositoryPath)
    if ($repositoryPath -match '^docs/(features(?:/.+)?)/[^/]+$') {
        $slugSource = [System.IO.Path]::ChangeExtension($Matches[1] + "/" `
            + [System.IO.Path]::GetFileName($repositoryPath), $null)
    }

    $slug = $slugSource.ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ($repositoryPath -match '^docs/wiki/') {
        return "wiki-$slug"
    }
    return $slug
}

$documents = foreach ($file in $sourceFiles) {
    $rootPrefix = $RepositoryRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $file.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Documentation source is outside the repository: $($file.FullName)"
    }
    $relativePath = $file.FullName.Substring($rootPrefix.Length).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    # Keep the generated search corpus byte-stable across Windows and Unix
    # checkouts. Source line endings are presentation-neutral inside JSON.
    $content = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($relativePath -eq "README.md") {
        # GitHub renders the centered brand/link blocks as HTML. The embedded
        # wiki intentionally escapes raw HTML, so omit those two decorative
        # blocks and start the local article at its Markdown heading instead.
        $content = [System.Text.RegularExpressions.Regex]::Replace(
            $content,
            '\A\s*<p align="center">.*?</p>\s*<p align="center">.*?</p>\s*',
            '',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    $fallbackTitle = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '[-_]+', ' '

    [ordered]@{
        slug = Get-Slug $relativePath
        title = Get-DocumentTitle $content $fallbackTitle
        path = $relativePath
        category = Get-DocumentCategory $relativePath
        format = if ($file.Extension -eq ".json") { "json" } else { "markdown" }
        content = $content
    }
}

$payload = [ordered]@{
    schemaVersion = 1
    repository = "Ding-Ding-Projects/qbittorrent-material"
    documents = @($documents)
}

$json = $payload | ConvertTo-Json -Depth 8 -Compress
$script = "window.QBT_DOCS = $json;`n"

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPath, $script, $utf8WithoutBom)

Write-Host "Generated $outputPath with $($documents.Count) documents."
