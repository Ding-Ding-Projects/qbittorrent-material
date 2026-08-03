[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $ReleaseBodiesPath,
    [string] $OutputPath
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepositoryRoot = Split-Path -Parent $scriptDirectory
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$catalogPath = Join-Path $RepositoryRoot "resources/dim-sum/index.json"
$catalog = @(Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json)
if ($catalog.Count -eq 0) {
    throw "The dim-sum release catalog is empty: $catalogPath"
}

function Test-Png([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 8) { return $false }
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    for ($i = 0; $i -lt $signature.Length; ++$i) {
        if ($bytes[$i] -ne $signature[$i]) { return $false }
    }
    return $true
}

$valid = @(
    foreach ($dish in $catalog) {
        $imageName = [string]$dish.image
        $imagePath = Join-Path $RepositoryRoot (Join-Path "resources/dim-sum" $imageName)
        if (-not (Test-Png $imagePath)) {
            throw "The catalog image is missing or is not a PNG: $imagePath"
        }
        [pscustomobject]@{
            Id = [string]$dish.id
            English = [string]$dish.english
            Cantonese = [string]$dish.cantonese
            Image = "resources/dim-sum/$imageName"
            ImageName = $imageName
        }
    }
)

$releaseBodies = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($ReleaseBodiesPath)) {
    foreach ($body in @(Get-Content -Raw -LiteralPath $ReleaseBodiesPath)) {
        $releaseBodies.Add([string]$body)
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    $releaseJson = gh release list --repo $env:GITHUB_REPOSITORY --limit 1000 --json tagName
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list existing releases while allocating the dim-sum code name."
    }
    foreach ($release in @($releaseJson | ConvertFrom-Json)) {
        $view = gh release view $release.tagName --repo $env:GITHUB_REPOSITORY --json body
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read release notes for $($release.tagName) while allocating the dim-sum code name."
        }
        $releaseBody = $view | ConvertFrom-Json
        $releaseBodies.Add([string]$releaseBody.body)
    }
}

$used = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($body in $releaseBodies) {
    foreach ($dish in $valid) {
        $idPattern = [regex]::Escape($dish.Id)
        $imagePattern = [regex]::Escape($dish.ImageName)
        $englishPattern = [regex]::Escape($dish.English)
        $cantonesePattern = [regex]::Escape($dish.Cantonese)
        $alreadyUsed = ($body -match "dim-sum-id:\s*$idPattern") `
            -or ($body -match $imagePattern) `
            -or (($body -match $englishPattern) -and ($body -match $cantonesePattern))
        if ($alreadyUsed) {
            [void]$used.Add($dish.Id)
        }
    }
}

$selected = $valid | Where-Object { -not $used.Contains($_.Id) } | Select-Object -First 1
$photo = if ($null -ne $selected) { $selected } else { $valid | Select-Object -First 1 }
$codeName = if ($null -ne $selected) {
    "$($selected.English) · $($selected.Cantonese)"
}
else {
    ""
}

$result = [ordered]@{
    id = if ($null -ne $selected) { $selected.Id } else { "" }
    codeName = $codeName
    path = $photo.Image
    english = if ($null -ne $selected) { $selected.English } else { "" }
    cantonese = if ($null -ne $selected) { $selected.Cantonese } else { "" }
    imageName = $photo.ImageName
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $result | ConvertTo-Json -Compress
    exit 0
}

foreach ($key in $result.Keys) {
    "$key=$($result[$key])" | Out-File -LiteralPath $OutputPath -Append -Encoding utf8NoBOM
}
Write-Output "Dim-sum photo: $($result.path)"
if ($result.codeName) {
    Write-Output "Dim-sum code name: $($result.codeName)"
}
else {
    Write-Output "No unused dim-sum code name remains; the verified catalog photo is still attached."
}
