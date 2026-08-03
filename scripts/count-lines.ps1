<#
.SYNOPSIS
    Counts the repository's tracked text lines with a reproducible breakdown.

.DESCRIPTION
    The release workflow runs this script at the exact commit it releases. It
    uses Git's tracked-file list and Git blame for surviving-line attribution;
    it does not count dependency directories, build output, lockfiles, or
    binary assets as project code.
#>
[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepositoryRoot = Split-Path -Parent $scriptDirectory
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

function Get-Category {
    param([string] $Path)

    $normalized = $Path.Replace('\', '/')
    if ($normalized -match '^(vendor|\.git|build|\.qt|\.vcpkg)/') {
        return [pscustomobject]@{ Name = "Excluded"; Reason = "vendor/dependency tree" }
    }
    if ($normalized -match '(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|Podfile\.lock|Gemfile\.lock|composer\.lock)$') {
        return [pscustomobject]@{ Name = "Excluded"; Reason = "lockfile" }
    }
    if ($normalized -match '(^|/)(docs/content\.generated\.js|docs/manifest\.json)$') {
        return [pscustomobject]@{ Name = "Generated"; Reason = "generated project asset" }
    }
    if ($normalized -match '^scripts/test-[^/]+\.ps1$' -or $normalized -match '^tests?/') {
        return [pscustomobject]@{ Name = "Tests"; Reason = "verification" }
    }
    if ($normalized -match '^src/quick/qml/' -or
        $normalized -match '\.(qml|qmltypes|css|html|scss|js)$') {
        return [pscustomobject]@{ Name = "Styles/markup"; Reason = "user-facing markup or style" }
    }
    if ($normalized -match '^src/') {
        return [pscustomobject]@{ Name = "Source"; Reason = "project source" }
    }
    return [pscustomobject]@{ Name = "Other tracked"; Reason = "tracked project file" }
}

function Get-TextStats {
    param([string] $Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if (($bytes -contains [byte] 0) -or ($bytes.Length -eq 0)) {
        return [pscustomobject]@{ IsText = ($bytes.Length -eq 0); Lines = 0; NonBlank = 0 }
    }

    $encoding = [Text.UTF8Encoding]::new($false, $false)
    $text = $encoding.GetString($bytes).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($text.EndsWith("`n")) {
        $text = $text.Substring(0, $text.Length - 1)
    }
    if ($text.Length -eq 0) {
        return [pscustomobject]@{ IsText = $true; Lines = 0; NonBlank = 0 }
    }

    $lines = @($text -split "`n")
    $nonBlank = @($lines | Where-Object { $_.Trim().Length -gt 0 }).Count
    return [pscustomobject]@{ IsText = $true; Lines = $lines.Count; NonBlank = $nonBlank }
}

$agentCommitCache = @{}
function Test-AgentCommit {
    param([string] $Commit)

    # Uncommitted lines are reported by Git blame with the all-zero object id;
    # they have no commit metadata yet, so leave them outside attribution until
    # the release commit exists.
    if ($Commit -match '^0{40}$') {
        return $false
    }
    if ($agentCommitCache.ContainsKey($Commit)) {
        return $agentCommitCache[$Commit]
    }
    $message = @(& git -C $RepositoryRoot show -s --format="%an%n%B" $Commit)
    $isAgent = ($message -join "`n") -match '(?im)(^|\n)(?:codex|claude|openai|automation|agent|bot)(?:$|\n)' `
        -or ($message -join "`n") -match '(?im)^\s*Co-Authored-By:.*(?:codex|claude|openai|automation|agent|bot)'
    $agentCommitCache[$Commit] = $isAgent
    return $isAgent
}

function Get-BlameStats {
    param([string] $RelativePath)

    $physical = 0
    $agent = 0
    $blame = @(& git -C $RepositoryRoot blame --line-porcelain -- $RelativePath)
    foreach ($line in $blame) {
        if ($line -match '^([0-9a-f]{40})\s+\S+\s+\S+') {
            # --line-porcelain emits one commit header for every surviving
            # source line; the optional fourth header field is a group size,
            # not another number of lines to add.
            $physical++
            if (Test-AgentCommit $Matches[1]) {
                $agent++
            }
        }
    }
    return [pscustomobject]@{ Lines = $physical; AgentLines = $agent }
}

$tracked = @(& git -C $RepositoryRoot ls-files)
$records = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in $tracked) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $fullPath = Join-Path $RepositoryRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    $category = Get-Category $relativePath
    # A Git submodule is represented by a tracked gitlink, not a readable file
    # in the superproject. Keep it visible in Excluded without descending into
    # or counting the nested repository.
    $stats = if (Test-Path -LiteralPath $fullPath -PathType Container) {
        [pscustomobject]@{ IsText = $false; Lines = 0; NonBlank = 0 }
    }
    else {
        Get-TextStats $fullPath
    }
    if (-not $stats.IsText) {
        $reason = if (Test-Path -LiteralPath $fullPath -PathType Container) {
            "submodule gitlink"
        } else { "binary asset" }
        $category = [pscustomobject]@{ Name = "Excluded"; Reason = $reason }
        $stats = [pscustomobject]@{ IsText = $false; Lines = 0; NonBlank = 0 }
    }

    $blame = if ($stats.IsText -and $stats.Lines -gt 0) {
        Get-BlameStats $relativePath
    }
    else {
        [pscustomobject]@{ Lines = 0; AgentLines = 0 }
    }
    if ($blame.Lines -ne $stats.Lines) {
        throw "Git blame line count differs for ${relativePath}: file=$($stats.Lines), blame=$($blame.Lines)."
    }

    $records.Add([pscustomobject]@{
        Path = $relativePath
        Category = $category.Name
        Reason = $category.Reason
        Lines = $stats.Lines
        NonBlank = $stats.NonBlank
        AgentLines = $blame.AgentLines
    })
}

$orderedCategories = @("Source", "Tests", "Styles/markup", "Generated", "Other tracked", "Excluded")
$rows = foreach ($categoryName in $orderedCategories) {
    $items = @($records | Where-Object { $_.Category -eq $categoryName })
    [pscustomobject]@{
        Scope = $categoryName
        Files = $items.Count
        Lines = [int64](($items | Measure-Object -Property Lines -Sum).Sum)
        NonBlank = [int64](($items | Measure-Object -Property NonBlank -Sum).Sum)
        AgentLines = [int64](($items | Measure-Object -Property AgentLines -Sum).Sum)
    }
}

$projectRows = @($rows | Where-Object { $_.Scope -ne "Excluded" })
$project = [pscustomobject]@{
    Scope = "Project total"
    Files = [int](($projectRows | Measure-Object -Property Files -Sum).Sum)
    Lines = [int64](($projectRows | Measure-Object -Property Lines -Sum).Sum)
    NonBlank = [int64](($projectRows | Measure-Object -Property NonBlank -Sum).Sum)
    AgentLines = [int64](($projectRows | Measure-Object -Property AgentLines -Sum).Sum)
}
$excluded = $rows | Where-Object { $_.Scope -eq "Excluded" }
$grand = [pscustomobject]@{
    Scope = "Grand total (tracked text)"
    Files = [int](($rows | Measure-Object -Property Files -Sum).Sum)
    Lines = [int64](($rows | Measure-Object -Property Lines -Sum).Sum)
    NonBlank = [int64](($rows | Measure-Object -Property NonBlank -Sum).Sum)
    AgentLines = [int64](($rows | Measure-Object -Property AgentLines -Sum).Sum)
}
$blameTotal = [int64](($records | Measure-Object -Property Lines -Sum).Sum)
if ($blameTotal -ne $grand.Lines -or $grand.AgentLines -gt $grand.Lines) {
    throw "Line-count arithmetic is inconsistent: records=$blameTotal, total=$($grand.Lines), agent=$($grand.AgentLines)."
}

$commit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
$result = [pscustomobject]@{
    Commit = $commit
    Rows = @($rows)
    ProjectTotal = $project
    GrandTotal = $grand
    Attribution = [pscustomobject]@{
        Rule = "Surviving physical lines attributed by git blame; automation identities or agent Co-Authored-By trailers count as agent-written."
        BlameLines = $blameTotal
        AgentLines = $grand.AgentLines
        ArithmeticAgrees = ($blameTotal -eq $grand.Lines)
    }
    Exclusions = "Vendored and third-party trees, dependency directories, lockfiles, build output, and binary assets are excluded from project code; the Excluded row remains visible."
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Output "# Project line count"
Write-Output ""
Write-Output "Commit: $commit"
Write-Output ""
Write-Output "| Scope | Files | Lines | Non-blank lines | Agent-written physical lines |"
Write-Output "| --- | ---: | ---: | ---: | ---: |"
foreach ($row in $rows) {
    Write-Output "| $($row.Scope) | $($row.Files) | $($row.Lines) | $($row.NonBlank) | $($row.AgentLines) |"
}
Write-Output "| **Project total** | **$($project.Files)** | **$($project.Lines)** | **$($project.NonBlank)** | **$($project.AgentLines)** |"
Write-Output "| **Grand total (tracked text)** | **$($grand.Files)** | **$($grand.Lines)** | **$($grand.NonBlank)** | **$($grand.AgentLines)** |"
Write-Output ""
Write-Output "Attribution rule: $($result.Attribution.Rule)"
Write-Output "Arithmetic check: blame lines $blameTotal = grand-total lines $($grand.Lines)"
Write-Output "Exclusions: $($result.Exclusions)"
