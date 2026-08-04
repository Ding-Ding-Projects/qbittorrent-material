[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $ReleaseBodiesPath,
    [string] $OutputPath,
    [string] $CatalogFixturePath,
    [string] $PublicReleasesFixturePath,
    [string] $ConsumerReleasesFixturePath,
    [string] $ConsumerRepository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publicRepository = "Ding-Ding-Projects/dim-sum-photos"
$catalogSourceUrl = "https://raw.githubusercontent.com/$publicRepository/main/catalog/index.json"
$ghTimeoutMilliseconds = 60000

function Assert-InputFile {
    param(
        [string] $Path,
        [string] $ParameterName
    )

    if (-not [string]::IsNullOrWhiteSpace($Path) -and
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [ArgumentException]::new("$ParameterName does not identify a readable file: $Path")
    }
}

function Get-ObjectValue {
    param(
        [AllowNull()]
        [object] $InputObject,
        [string[]] $Names
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    return $null
}

function ConvertTo-Boolean {
    param([AllowNull()][object] $Value)

    if ($Value -is [bool]) {
        return $Value
    }
    if ($null -eq $Value) {
        return $false
    }
    return [string]$Value -match '^(?i:true|1)$'
}

function ConvertTo-NormalizedDigest {
    param([AllowNull()][object] $Value)

    $digest = ([string]$Value).Trim()
    if ($digest -match '^(?i:sha256:)?([0-9a-f]{64})$') {
        return "sha256:$($Matches[1].ToLowerInvariant())"
    }
    return ""
}

function ConvertTo-SafeOutputValue {
    param([AllowNull()][object] $Value)

    $safe = [string]$Value
    $safe = $safe -replace '[\x00\r\n]+', ' '
    return $safe.Trim()
}

function ConvertTo-BoundedReason {
    param([string] $Prefix, [AllowNull()][object] $Detail)

    $reason = ConvertTo-SafeOutputValue "$Prefix$Detail"
    if ($reason.Length -gt 320) {
        return $reason.Substring(0, 317) + "..."
    }
    return $reason
}

function Read-JsonFixture {
    param([string] $Path, [string] $ParameterName)

    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw [ArgumentException]::new("$ParameterName is not valid JSON: $($_.Exception.Message)")
    }
}

function Invoke-GhText {
    param([string[]] $Arguments)

    $gh = Get-Command gh -CommandType Application -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'gh could not be started.'
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($ghTimeoutMilliseconds)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            [void]$process.WaitForExit(5000)
            throw "gh timed out after $([int]($ghTimeoutMilliseconds / 1000)) seconds while resolving release metadata."
        }
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "gh failed with exit code $($process.ExitCode) while resolving release metadata."
        }
        return $text
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-GhJson {
    param([string[]] $Arguments)

    $text = Invoke-GhText -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "gh returned an empty JSON response."
    }
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        throw "gh returned invalid JSON: $($_.Exception.Message)"
    }
}

function ConvertTo-ReleaseList {
    param([AllowNull()][object] $Data)

    $items = [System.Collections.Generic.List[object]]::new()
    function Add-ReleaseValue {
        param([AllowNull()][object] $Value)

        if ($null -eq $Value) {
            return
        }

        $tagName = Get-ObjectValue -InputObject $Value -Names @('tagName', 'tag_name')
        if (-not [string]::IsNullOrWhiteSpace([string]$tagName)) {
            $items.Add($Value)
            return
        }

        $wrapped = Get-ObjectValue -InputObject $Value -Names @('releases')
        if ($null -ne $wrapped) {
            Add-ReleaseValue -Value $wrapped
            return
        }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($entry in $Value) {
                Add-ReleaseValue -Value $entry
            }
        }
    }

    Add-ReleaseValue -Value $Data
    return $items.ToArray()
}

function Resolve-CatalogData {
    param([AllowNull()][object] $Fixture)

    if ($null -ne $Fixture) {
        $catalog = Get-ObjectValue -InputObject $Fixture -Names @('catalog')
        if ($null -eq $catalog) {
            $catalog = $Fixture
        }
        $revision = ([string](Get-ObjectValue -InputObject $Fixture -Names @('catalogRevision', 'revision'))).Trim()
        $blobSha = ([string](Get-ObjectValue -InputObject $Fixture -Names @('catalogBlobSha', 'blobSha'))).Trim()
        if ($revision -notmatch '^[0-9a-fA-F]{40}$' -or
            $blobSha -notmatch '^[0-9a-fA-F]{40}$') {
            throw 'The catalog fixture revision and blob SHA must each be exactly 40 hexadecimal characters.'
        }
        return [pscustomobject]@{
            Catalog = $catalog
            Revision = $revision.ToLowerInvariant()
            BlobSha = $blobSha.ToLowerInvariant()
        }
    }

    $repository = Invoke-GhJson -Arguments @('api', "repos/$publicRepository")
    $defaultBranch = [string](Get-ObjectValue -InputObject $repository -Names @('default_branch'))
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        throw 'The public photo repository did not report a default branch.'
    }

    $encodedBranch = [Uri]::EscapeDataString($defaultBranch)
    $commit = Invoke-GhJson -Arguments @('api', "repos/$publicRepository/commits/$encodedBranch")
    $revision = [string](Get-ObjectValue -InputObject $commit -Names @('sha'))
    if ($revision -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'The public catalog revision was missing or malformed.'
    }

    $encodedRevision = [Uri]::EscapeDataString($revision)
    $contentEndpoint = "repos/$publicRepository/contents/catalog/index.json?ref=$encodedRevision"
    $contentMetadata = Invoke-GhJson -Arguments @('api', $contentEndpoint)
    $blobSha = [string](Get-ObjectValue -InputObject $contentMetadata -Names @('sha'))
    if ($blobSha -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'The public catalog blob SHA was missing or malformed.'
    }

    $catalogText = Invoke-GhText -Arguments @(
        'api',
        '-H', 'Accept: application/vnd.github.raw+json',
        $contentEndpoint
    )
    try {
        $catalog = $catalogText | ConvertFrom-Json
    }
    catch {
        throw "The public catalog was not valid JSON: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Catalog = $catalog
        Revision = $revision.ToLowerInvariant()
        BlobSha = $blobSha.ToLowerInvariant()
    }
}

function ConvertTo-CatalogDishes {
    param([object] $Catalog)

    $schemaVersion = ([string](Get-ObjectValue -InputObject $Catalog -Names @('schemaVersion'))).Trim()
    if ($schemaVersion -ne '1.0.0') {
        throw "The public catalog schema '$schemaVersion' is not supported."
    }

    $rawDishes = Get-ObjectValue -InputObject $Catalog -Names @('dishes')
    if ($null -eq $rawDishes -or @($rawDishes).Count -eq 0) {
        throw 'The public catalog has no dishes.'
    }
    $declaredTotal = 0
    $rawTotal = [string](Get-ObjectValue -InputObject $Catalog -Names @('total'))
    if (-not [int]::TryParse($rawTotal, [ref]$declaredTotal) -or
        $declaredTotal -ne @($rawDishes).Count) {
        throw 'The public catalog total does not match its dish records.'
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $images = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $dishes = [System.Collections.Generic.List[object]]::new()
    foreach ($dish in @($rawDishes)) {
        $id = ([string](Get-ObjectValue -InputObject $dish -Names @('id'))).Trim()
        $name = Get-ObjectValue -InputObject $dish -Names @('name')
        $english = ([string](Get-ObjectValue -InputObject $name -Names @('en'))).Trim()
        $zhHant = ([string](Get-ObjectValue -InputObject $name -Names @('zhHant'))).Trim()
        $image = Get-ObjectValue -InputObject $dish -Names @('image')
        $imagePath = ([string](Get-ObjectValue -InputObject $image -Names @('path'))).Trim()
        $imageName = [IO.Path]::GetFileName($imagePath)

        $expectedImagePattern = '^images/' + [regex]::Escape($id) + '-[a-z0-9]+(?:-[a-z0-9]+)*\.png$'
        if ($id -notmatch '^hk-dish-[0-9]{4}$' -or
            [string]::IsNullOrWhiteSpace($english) -or
            [string]::IsNullOrWhiteSpace($zhHant) -or
            $english -match '[\x00\r\n]' -or
            $zhHant -match '[\x00\r\n]' -or
            [string]::IsNullOrWhiteSpace($imageName) -or
            $imagePath -cnotmatch $expectedImagePattern) {
            throw "The public catalog contains an incomplete dish record."
        }
        if (-not $ids.Add($id)) {
            throw "The public catalog contains duplicate dish id '$id'."
        }
        if (-not $images.Add($imageName)) {
            throw "The public catalog contains duplicate image basename '$imageName'."
        }

        $dishes.Add([pscustomobject]@{
            Id = $id
            English = $english
            ZhHant = $zhHant
            ImageName = $imageName
        })
    }
    return $dishes.ToArray()
}

function Test-PublicAssetUrl {
    param(
        [string] $Url,
        [string] $Tag,
        [string] $AssetName
    )

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) {
        return $false
    }
    $expectedPath = "/$publicRepository/releases/download/$Tag/$AssetName"
    $decodedPath = [Uri]::UnescapeDataString($uri.AbsolutePath)
    return $uri.Scheme -eq 'https' -and
        $uri.Host -eq 'github.com' -and
        [string]::IsNullOrEmpty($uri.Query) -and
        $decodedPath.Equals($expectedPath, [StringComparison]::Ordinal)
}

function ConvertTo-PublicAssetMap {
    param([object[]] $Releases)

    $published = foreach ($release in $Releases) {
        $tag = ([string](Get-ObjectValue -InputObject $release -Names @('tagName', 'tag_name'))).Trim()
        $isDraft = ConvertTo-Boolean (Get-ObjectValue -InputObject $release -Names @('isDraft', 'draft'))
        $isPrerelease = ConvertTo-Boolean (Get-ObjectValue -InputObject $release -Names @('isPrerelease', 'prerelease'))
        $publishedAt = [string](Get-ObjectValue -InputObject $release -Names @('publishedAt', 'published_at'))
        $parsedPublishedAt = [DateTimeOffset]::MinValue
        if ($tag -notmatch '^catalog-v1(?:-part-[0-9]{3})?$' -or $isDraft -or $isPrerelease -or
            -not [DateTimeOffset]::TryParse($publishedAt, [ref]$parsedPublishedAt)) {
            continue
        }
        [pscustomobject]@{
            Release = $release
            Tag = $tag
            PublishedAt = $parsedPublishedAt
        }
    }

    $assetMap = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $digestOwners = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ambiguous = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($published | Sort-Object PublishedAt, Tag)) {
        $assets = Get-ObjectValue -InputObject $entry.Release -Names @('assets')
        foreach ($asset in @($assets)) {
            $name = ([string](Get-ObjectValue -InputObject $asset -Names @('name'))).Trim()
            $contentType = ([string](Get-ObjectValue -InputObject $asset -Names @('contentType', 'content_type'))).Trim()
            $state = ([string](Get-ObjectValue -InputObject $asset -Names @('state'))).Trim()
            # REST release objects expose both an API `url` and the public
            # `browser_download_url`; gh release view exposes only `url` for
            # the public download. Prefer the browser URL when both exist.
            $url = ([string](Get-ObjectValue -InputObject $asset -Names @('browser_download_url', 'url'))).Trim()
            $digest = ConvertTo-NormalizedDigest (Get-ObjectValue -InputObject $asset -Names @('digest'))
            if ($name -notmatch '(?i)\.png$' -or
                $contentType -ne 'image/png' -or
                $state -ne 'uploaded' -or
                [string]::IsNullOrWhiteSpace($digest) -or
                -not (Test-PublicAssetUrl -Url $url -Tag $entry.Tag -AssetName $name)) {
                continue
            }

            $candidateAsset = [pscustomobject]@{
                Name = $name
                Url = $url
                Digest = $digest
                Tag = $entry.Tag
            }
            if ($digestOwners.ContainsKey($digest)) {
                $digestOwner = $digestOwners[$digest]
                if (-not $digestOwner.Equals($name, [StringComparison]::OrdinalIgnoreCase)) {
                    [void]$ambiguous.Add($digestOwner)
                    [void]$ambiguous.Add($name)
                }
            }
            else {
                $digestOwners.Add($digest, $name)
            }
            if (-not $assetMap.ContainsKey($name)) {
                $assetMap.Add($name, $candidateAsset)
                continue
            }

            $existing = $assetMap[$name]
            # Re-publishing the same immutable bytes under a later catalog-v1*
            # tag is harmless; retain the earliest stable public URL. Conflicting
            # bytes for one basename are ambiguous and therefore ineligible.
            if ($existing.Digest -ne $candidateAsset.Digest) {
                [void]$ambiguous.Add($name)
            }
        }
    }

    foreach ($name in $ambiguous) {
        [void]$assetMap.Remove($name)
    }
    return $assetMap
}

function Get-ConsumerHistory {
    param([object[]] $Releases)

    $bodies = [System.Collections.Generic.List[string]]::new()
    $digests = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $assetNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($release in $Releases) {
        $isDraft = ConvertTo-Boolean (Get-ObjectValue -InputObject $release -Names @('isDraft', 'draft'))
        if ($isDraft) {
            continue
        }
        $body = [string](Get-ObjectValue -InputObject $release -Names @('body'))
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            $bodies.Add($body)
        }
        $assets = Get-ObjectValue -InputObject $release -Names @('assets')
        foreach ($asset in @($assets)) {
            $assetName = ([string](Get-ObjectValue -InputObject $asset -Names @('name'))).Trim()
            if (-not [string]::IsNullOrWhiteSpace($assetName)) {
                [void]$assetNames.Add($assetName)
            }
            $digest = ConvertTo-NormalizedDigest (Get-ObjectValue -InputObject $asset -Names @('digest'))
            if (-not [string]::IsNullOrWhiteSpace($digest)) {
                [void]$digests.Add($digest)
            }
        }
    }
    return [pscustomobject]@{
        Bodies = $bodies.ToArray()
        Digests = $digests
        AssetNames = $assetNames
    }
}

function Test-CandidateUsed {
    param(
        [object] $Dish,
        [object] $Asset,
        [object] $History
    )

    if ($History.Digests.Contains($Asset.Digest) -or
        $History.AssetNames.Contains($Asset.Name)) {
        return $true
    }

    $codeName = "$($Dish.English) · $($Dish.ZhHant)"
    $idPattern = '(?im)<!--\s*dim-sum-id:\s*' + [regex]::Escape($Dish.Id) + '\s*-->'
    $codeNamePattern = '(?im)^\s*(?:[-*]\s*)?Dim-sum code name:\s*`?' +
        [regex]::Escape($codeName) + '`?\s*$'
    foreach ($body in $History.Bodies) {
        $hasId = [regex]::IsMatch($body, $idPattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        $hasCodeName = [regex]::IsMatch(
            $body,
            $codeNamePattern,
            [Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        $hasAsset = $body.IndexOf($Asset.Name, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $body.IndexOf($Asset.Url, [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($hasId -or $hasCodeName -or $hasAsset) {
            return $true
        }
    }
    return $false
}

function New-Result {
    param(
        [bool] $Available,
        [AllowNull()][object] $Dish,
        [AllowNull()][object] $Asset,
        [string] $Revision,
        [string] $BlobSha,
        [string] $Reason
    )

    return [ordered]@{
        available = $Available.ToString().ToLowerInvariant()
        id = if ($Available) { $Dish.Id } else { '' }
        codeName = if ($Available) { "$($Dish.English) · $($Dish.ZhHant)" } else { '' }
        english = if ($Available) { $Dish.English } else { '' }
        zhHant = if ($Available) { $Dish.ZhHant } else { '' }
        photoUrl = if ($Available) { $Asset.Url } else { '' }
        photoAssetName = if ($Available) { $Asset.Name } else { '' }
        photoDigest = if ($Available) { $Asset.Digest } else { '' }
        photoTag = if ($Available) { $Asset.Tag } else { '' }
        catalogSourceUrl = $catalogSourceUrl
        catalogRevision = $Revision
        catalogBlobSha = $BlobSha
        reason = $Reason
    }
}

function Write-Result {
    param([System.Collections.IDictionary] $Result)

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Write-Output ($Result | ConvertTo-Json -Compress)
        return
    }

    $lines = foreach ($key in $Result.Keys) {
        "$key=$(ConvertTo-SafeOutputValue $Result[$key])"
    }
    $payload = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    try {
        [IO.File]::AppendAllText($OutputPath, $payload, [Text.UTF8Encoding]::new($false))
    }
    catch {
        throw [IOException]::new("Could not append dim-sum outputs to '$OutputPath': $($_.Exception.Message)")
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepositoryRoot = Split-Path -Parent $scriptDirectory
}
if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
    throw [ArgumentException]::new("RepositoryRoot does not identify a directory: $RepositoryRoot")
}

Assert-InputFile -Path $ReleaseBodiesPath -ParameterName 'ReleaseBodiesPath'
Assert-InputFile -Path $CatalogFixturePath -ParameterName 'CatalogFixturePath'
Assert-InputFile -Path $PublicReleasesFixturePath -ParameterName 'PublicReleasesFixturePath'
Assert-InputFile -Path $ConsumerReleasesFixturePath -ParameterName 'ConsumerReleasesFixturePath'
$fixtureCount = @(
    $CatalogFixturePath,
    $PublicReleasesFixturePath,
    $ConsumerReleasesFixturePath
).Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count
if ($fixtureCount -ne 0 -and $fixtureCount -ne 3) {
    throw [ArgumentException]::new(
        'CatalogFixturePath, PublicReleasesFixturePath, and ConsumerReleasesFixturePath must be supplied together.'
    )
}
$usingFixtures = $fixtureCount -eq 3
if (-not [string]::IsNullOrWhiteSpace($ReleaseBodiesPath) -and
    -not [string]::IsNullOrWhiteSpace($ConsumerReleasesFixturePath)) {
    throw [ArgumentException]::new('ReleaseBodiesPath and ConsumerReleasesFixturePath cannot be used together.')
}

$catalogFixture = $null
$publicReleasesFixture = $null
$consumerReleasesFixture = $null
if (-not [string]::IsNullOrWhiteSpace($CatalogFixturePath)) {
    $catalogFixture = Read-JsonFixture -Path $CatalogFixturePath -ParameterName 'CatalogFixturePath'
}
if (-not [string]::IsNullOrWhiteSpace($PublicReleasesFixturePath)) {
    $publicReleasesFixture = Read-JsonFixture -Path $PublicReleasesFixturePath -ParameterName 'PublicReleasesFixturePath'
}
if (-not [string]::IsNullOrWhiteSpace($ConsumerReleasesFixturePath)) {
    $consumerReleasesFixture = Read-JsonFixture -Path $ConsumerReleasesFixturePath -ParameterName 'ConsumerReleasesFixturePath'
}
if ([string]::IsNullOrWhiteSpace($ReleaseBodiesPath) -and
    -not $usingFixtures -and
    -not [string]::IsNullOrWhiteSpace($ConsumerRepository) -and
    $ConsumerRepository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw [ArgumentException]::new("ConsumerRepository is malformed: $ConsumerRepository")
}

$catalogData = $null
$dishes = @()
$publicReleases = @()
$assetMap = $null
try {
    $catalogData = Resolve-CatalogData -Fixture $catalogFixture
    $dishes = @(ConvertTo-CatalogDishes -Catalog $catalogData.Catalog)
    if ($usingFixtures) {
        $publicReleases = @(ConvertTo-ReleaseList -Data $publicReleasesFixture)
    }
    else {
        $releasePages = Invoke-GhJson -Arguments @(
            'api', '--paginate', '--slurp',
            "repos/$publicRepository/releases?per_page=100"
        )
        $publicReleases = @(ConvertTo-ReleaseList -Data $releasePages)
    }
    $assetMap = ConvertTo-PublicAssetMap -Releases $publicReleases
}
catch {
    if ($usingFixtures) {
        throw [ArgumentException]::new("Invalid public fixture data: $($_.Exception.Message)")
    }
    $failure = New-Result -Available $false -Dish $null -Asset $null `
        -Revision '' -BlobSha '' `
        -Reason (ConvertTo-BoundedReason 'Public dim-sum catalog or releases could not be resolved: ' $_.Exception.Message)
    Write-Result -Result $failure
    exit 0
}

if ($assetMap.Count -eq 0) {
    $failure = New-Result -Available $false -Dish $null -Asset $null `
        -Revision $catalogData.Revision -BlobSha $catalogData.BlobSha `
        -Reason 'No published catalog-v1* PNG asset with a public URL and SHA-256 digest matched the catalog.'
    Write-Result -Result $failure
    exit 0
}

$consumerReleases = @()
$history = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($ReleaseBodiesPath)) {
        $consumerReleases = @([pscustomobject]@{
            tagName = 'injected-release-bodies'
            body = Get-Content -Raw -LiteralPath $ReleaseBodiesPath
            assets = @()
        })
    }
    elseif ($usingFixtures) {
        $consumerReleases = @(ConvertTo-ReleaseList -Data $consumerReleasesFixture)
    }
    else {
        if ([string]::IsNullOrWhiteSpace($ConsumerRepository)) {
            throw 'GITHUB_REPOSITORY was not set and no consumer-release fixture was supplied.'
        }
        $consumerPages = Invoke-GhJson -Arguments @(
            'api', '--paginate', '--slurp',
            "repos/$ConsumerRepository/releases?per_page=100"
        )
        $consumerReleases = @(ConvertTo-ReleaseList -Data $consumerPages)
    }
    $history = Get-ConsumerHistory -Releases $consumerReleases
}
catch {
    if ($usingFixtures) {
        throw [ArgumentException]::new("Invalid consumer release fixture data: $($_.Exception.Message)")
    }
    $failure = New-Result -Available $false -Dish $null -Asset $null `
        -Revision $catalogData.Revision -BlobSha $catalogData.BlobSha `
        -Reason (ConvertTo-BoundedReason 'Consumer release history could not be resolved: ' $_.Exception.Message)
    Write-Result -Result $failure
    exit 0
}

$selectedDish = $null
$selectedAsset = $null
foreach ($dish in $dishes) {
    if (-not $assetMap.ContainsKey($dish.ImageName)) {
        continue
    }
    $asset = $assetMap[$dish.ImageName]
    if (-not (Test-CandidateUsed -Dish $dish -Asset $asset -History $history)) {
        $selectedDish = $dish
        $selectedAsset = $asset
        break
    }
}

if ($null -eq $selectedDish) {
    $failure = New-Result -Available $false -Dish $null -Asset $null `
        -Revision $catalogData.Revision -BlobSha $catalogData.BlobSha `
        -Reason 'Every published public dim-sum candidate has already been used by a consumer release.'
    Write-Result -Result $failure
    exit 0
}

$success = New-Result -Available $true -Dish $selectedDish -Asset $selectedAsset `
    -Revision $catalogData.Revision -BlobSha $catalogData.BlobSha -Reason ''
Write-Result -Result $success
exit 0
