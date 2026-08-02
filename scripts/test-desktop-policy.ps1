[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepositoryRoot = Split-Path -Parent $scriptDirectory
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Test-Policy {
    param(
        [bool] $Condition,
        [string] $Description
    )

    $script:checks++
    if ($Condition) {
        Write-Host "[PASS] $Description"
        return
    }

    $script:failures.Add($Description)
    Write-Host "[FAIL] $Description"
}

function Get-RepositoryPath {
    param([string] $RelativePath)
    return Join-Path $RepositoryRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile {
    param(
        [string] $RelativePath,
        [switch] $AsHashtable
    )

    $path = Get-RepositoryPath $RelativePath
    Test-Policy (Test-Path -LiteralPath $path -PathType Leaf) "$RelativePath exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    try {
        $json = Get-Content -Raw -LiteralPath $path
        $value = if ($AsHashtable) {
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("AsHashtable")) {
                $json | ConvertFrom-Json -AsHashtable
            }
            else {
                # Windows PowerShell 5.1 treats case-only JSON keys as
                # duplicates. JavaScriptSerializer preserves this flat
                # translation catalog with ordinal dictionary keys instead.
                Add-Type -AssemblyName System.Web.Extensions
                $serializer = [Web.Script.Serialization.JavaScriptSerializer]::new()
                $serializer.MaxJsonLength = [int]::MaxValue
                $serializer.DeserializeObject($json)
            }
        }
        else {
            $json | ConvertFrom-Json
        }
        Test-Policy $true "$RelativePath contains valid JSON"
        return $value
    }
    catch {
        Test-Policy $false "$RelativePath contains valid JSON ($($_.Exception.Message))"
        return $null
    }
}

function Test-DecodablePng {
    param([string] $RelativePath)

    $path = Get-RepositoryPath $RelativePath
    Test-Policy (Test-Path -LiteralPath $path -PathType Leaf) "$RelativePath exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    $signature = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    $signatureValid = $bytes.Length -ge $signature.Count
    for ($index = 0; $signatureValid -and $index -lt $signature.Count; $index++) {
        $signatureValid = $bytes[$index] -eq $signature[$index]
    }
    Test-Policy $signatureValid "$RelativePath has a PNG signature"

    try {
        $image = [Drawing.Image]::FromFile($path)
        try {
            Test-Policy (($image.Width -gt 0) -and ($image.Height -gt 0)) `
                "$RelativePath decodes as a non-empty image"
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
        Test-Policy $false "$RelativePath decodes as a non-empty image ($($_.Exception.Message))"
    }
}

$requiredDesktopFiles = @(
    "src/quick/controllers/experiencecontroller.cpp",
    "src/quick/controllers/experiencecontroller.h",
    "src/quick/controllers/notificationcontroller.cpp",
    "src/quick/controllers/notificationcontroller.h",
    "src/quick/qml/components/Snackbar.qml",
    "src/quick/qml/dialogs/ChangelogPage.qml",
    "src/quick/qml/shell/DimSumSurprise.qml",
    "src/quick/qml/shell/NotificationsSheet.qml",
    "src/quick/qml/shell/RegexBuilderSheet.qml",
    "src/quick/qml/shell/SettingsSheet.qml",
    "src/quick/qml/workspace/WorkspaceSearchPanel.qml",
    "src/quick/qml/workspace/WorkspaceTabStrip.qml",
    "resources/branding/logo-mark.png",
    "resources/branding/logo-monochrome.png",
    "resources/branding/logo-horizontal.png",
    "resources/branding/qbittorrent-material.ico",
    "resources/branding/qbittorrent-material.rc",
    "docs/assets/logo-mark.png",
    "resources/experience/changelog.json",
    "resources/experience/dim-sum.json"
)
foreach ($relativePath in $requiredDesktopFiles) {
    Test-Policy (Test-Path -LiteralPath (Get-RepositoryPath $relativePath) -PathType Leaf) `
        "$relativePath is present"
}

try {
    Add-Type -AssemblyName System.Drawing
    Test-Policy $true "the Windows image decoder is available"
}
catch {
    Test-Policy $false "the Windows image decoder is available ($($_.Exception.Message))"
}

$dishes = Read-JsonFile "resources/experience/dim-sum.json"
if ($null -ne $dishes) {
    $dishList = @($dishes)
    $requiredDishIds = @("har-gow", "siu-mai", "egg-tart")
    Test-Policy ($dishList.Count -ge $requiredDishIds.Count) `
        "the startup catalog preserves every shipped dish and can grow"
    Test-Policy ((@($dishList.id | Sort-Object -Unique)).Count -eq $dishList.Count) `
        "dim-sum identifiers are unique"
    foreach ($requiredDishId in $requiredDishIds) {
        Test-Policy (@($dishList.id) -contains $requiredDishId) `
            "the startup catalog preserves '$requiredDishId'"
    }

    foreach ($dish in $dishList) {
        $complete = -not [string]::IsNullOrWhiteSpace([string] $dish.id) `
            -and -not [string]::IsNullOrWhiteSpace([string] $dish.english) `
            -and -not [string]::IsNullOrWhiteSpace([string] $dish.cantonese) `
            -and -not [string]::IsNullOrWhiteSpace([string] $dish.altEnglish) `
            -and -not [string]::IsNullOrWhiteSpace([string] $dish.altCantonese)
        Test-Policy $complete "dim-sum entry '$($dish.id)' has bilingual names and alt text"

        $resourcePath = [string] $dish.image
        Test-Policy ($resourcePath -match '^qrc:/dim-sum/[^/]+\.png$') `
            "dim-sum entry '$($dish.id)' uses a bundled qrc PNG"
        if ($resourcePath -match '^qrc:/(.+)$') {
            Test-DecodablePng "resources/$($Matches[1])"
        }
    }
}

$changelog = Read-JsonFile "resources/experience/changelog.json"
if ($null -ne $changelog) {
    $releaseList = @($changelog)
    $historicalVersions = @(
        "build-48-8b68ae74", "build-47-b44229e4", "build-46-399e4350",
        "build-45-430a6177", "build-44-af4cbf25", "build-43-0881ad0e",
        "build-42-58164502", "build-41-a2ae836d", "build-40-c6d0e333",
        "build-39-50c67897", "build-38-576c85c8", "build-37-21b0b2b6",
        "build-26-3dc2ec00", "build-25-2eb40141", "build-24-e8e41838",
        "build-23-83a81bc3", "build-22-41c2cea7", "build-21-69740550",
        "build-20-74c4aa3c", "build-19-0c21fac4", "build-17-a07e3af8",
        "build-16-47b984a4", "build-14-423929a0", "build-13-f64178cc",
        "build-12-2e33d38c", "build-11-61616f2a", "build-10-33e5a062",
        "build-9-ae9843a4", "build-8-3b9cd888", "build-7-60822258",
        "build-6-98325da1", "build-5-476b6e7c", "build-4-9ce72b8b",
        "build-3-510c365e"
    )
    $releaseVersions = @($releaseList.version)
    $missingHistoricalVersions = @($historicalVersions | Where-Object {
        $releaseVersions -notcontains $_
    })
    Test-Policy ($missingHistoricalVersions.Count -eq 0) `
        "the changelog preserves the canonical 34-release history$($missingHistoricalVersions -join ', ')"
    Test-Policy ((@($releaseList.version | Sort-Object -Unique)).Count -eq $releaseList.Count) `
        "changelog release versions are unique"
    Test-Policy ($releaseVersions -contains "build-50-59a259c6") `
        "the changelog is current through the branding and transfer-filter completion commit"

    foreach ($release in $releaseList) {
        $releaseDate = [DateTime]::MinValue
        $dateValid = [DateTime]::TryParseExact(
            [string] $release.date,
            "yyyy-MM-dd",
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref] $releaseDate)
        $complete = -not [string]::IsNullOrWhiteSpace([string] $release.version) `
            -and -not [string]::IsNullOrWhiteSpace([string] $release.title) `
            -and @($release.changes).Count -gt 0 `
            -and $dateValid
        Test-Policy $complete "changelog entry '$($release.version)' has a date, title, and change list"

        $commit = [string] $release.commit
        $commitFormatValid = $commit -match '^[0-9a-f]{40}$'
        Test-Policy $commitFormatValid `
            "changelog entry '$($release.version)' carries a full lowercase commit SHA"
        if ($commitFormatValid) {
            $commitType = & git -C $RepositoryRoot cat-file -t $commit 2>$null
            Test-Policy (($LASTEXITCODE -eq 0) -and ($commitType -eq "commit")) `
                "changelog entry '$($release.version)' references an existing Git commit"
        }
    }
}

$cantonese = Read-JsonFile "resources/i18n/cantonese.json" -AsHashtable
if ($null -ne $cantonese) {
    $translationKeys = @($cantonese.Keys)
    foreach ($requiredKey in @(
        "1 is fully professional and 5 is maximum playfulness",
        "Cantonese funny level",
        "English funny level",
        "Language"
    )) {
        Test-Policy ($translationKeys -contains $requiredKey) `
            "the Cantonese catalog translates '$requiredKey'"
    }
}

$sourceCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/CMakeLists.txt")
Test-Policy ($sourceCMake -match 'quick/qml/\*\.qml') "CMake discovers every desktop QML surface"
Test-Policy ($sourceCMake -match 'experience/\*\.json') "CMake bundles the offline experience catalogs"
Test-Policy ($sourceCMake -match 'dim-sum/\*\.png') "CMake bundles the local dim-sum images"

$mainQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/Main.qml")
foreach ($surface in @("DimSumSurprise", "NotificationsSheet", "RegexBuilderSheet", "SettingsSheet")) {
    Test-Policy ($mainQml -match [regex]::Escape($surface)) "Main.qml wires $surface"
}

$legacySnackbarCalls = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath (Get-RepositoryPath "src/quick/qml") -Filter "*.qml" -File -Recurse |
    ForEach-Object {
        $matches = Select-String -LiteralPath $_.FullName `
            -Pattern '(?<![A-Za-z0-9_])Snackbar\s*\.\s*show\s*\(' -AllMatches -CaseSensitive
        foreach ($match in $matches) {
            $legacySnackbarCalls.Add("$($_.FullName):$($match.LineNumber)")
        }
    }
Test-Policy ($legacySnackbarCalls.Count -eq 0) `
    "desktop QML contains no legacy static Snackbar.show calls$($legacySnackbarCalls -join ', ')"

$filterSidebar = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/transferlist/FilterSidebar.qml")
Test-Policy ($filterSidebar -match 'width:\s*Math\.max\(0,\s*filterScroll\.availableWidth\)') `
    "the filter sidebar reserves the vertical scrollbar viewport"

foreach ($filterPanel in @(
    "StatusFilterPanel.qml",
    "CategoryFilterTree.qml",
    "TagFilterList.qml",
    "TrackersFilterList.qml",
    "TrackerStatusFilterPanel.qml"
)) {
    $filterPanelSource = Get-Content -Raw -LiteralPath `
        (Get-RepositoryPath "src/quick/qml/transferlist/$filterPanel")
    Test-Policy ($filterPanelSource -match 'Layout\.fillWidth:\s*true' `
            -and $filterPanelSource -match 'Layout\.minimumWidth:\s*0' `
            -and $filterPanelSource -match 'elide:\s*Text\.ElideRight' `
            -and $filterPanelSource -match 'wrapMode:\s*Text\.NoWrap') `
        "$filterPanel bounds and elides long translated labels"
}

$changelogQml = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/dialogs/ChangelogPage.qml")
$experienceSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/experiencecontroller.cpp")
Test-Policy ($changelogQml -match 'entry\.commit' `
        -and $changelogQml -match 'Qt\.openUrlExternally\(root\.commitBaseUrl \+ commitId\)' `
        -and $changelogQml -match 'Accessible\.name:\s*qsTr\("Open commit %1"\)') `
    "the changelog exposes each source commit as an accessible link"
Test-Policy ($experienceSource -match 'Commit:\s*\[%1\]\(%2%1\)' `
        -and $experienceSource -match 'kCommitBaseUrl') `
    "copied and exported changelog Markdown preserves full commit links"

Test-DecodablePng "resources/branding/logo-mark.png"
Test-DecodablePng "resources/branding/logo-monochrome.png"
Test-DecodablePng "resources/branding/logo-horizontal.png"
Test-DecodablePng "docs/assets/logo-mark.png"

$applicationSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/application.cpp")
$desktopIntegrationSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/desktopintegration.cpp")
$appCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/CMakeLists.txt")
Test-Policy ($applicationSource -match ':/branding/logo-mark\.png') `
    "the global window icon uses the canonical raster mark"
Test-Policy ($desktopIntegrationSource -match ':/branding/logo-mark\.png' `
        -and $desktopIntegrationSource -match ':/branding/logo-monochrome\.png') `
    "normal and monochrome tray modes use the current product mark"
Test-Policy ($appCMake -match 'qbittorrent-material\.rc') `
    "the Windows executable embeds the multi-resolution product icon"

$transfersPage = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/TransfersPage.qml")
Test-Policy ($transfersPage -match 'enabled:\s*TransferController\.selectionCount\s*>\s*0') `
    "selection-only Split Dock actions expose their disabled state"

$transferFilterProxyHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/torrentfilterproxymodel.h")
$transferFilterProxySource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/torrentfilterproxymodel.cpp")
$transferListView = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TransferListView.qml")
Test-Policy ($transferFilterProxyHeader -match 'Q_PROPERTY\(int textFilterColumn') `
    "the transfer proxy exposes its selected text-filter column"
Test-Policy ($transferFilterProxySource -match 'TR_NAME' `
        -and $transferFilterProxySource -match 'TR_SAVE_PATH' `
        -and $transferFilterProxySource -match 'infoHash\(\)\.v1\(\)\.toString\(\)' `
        -and $transferFilterProxySource -match 'infoHash\(\)\.v2\(\)\.toString\(\)') `
    "transfer filtering covers name, save path, and both info-hash generations"
Test-Policy ($transferListView -match 'text:\s*qsTr\("Filter by:"\)' `
        -and $transferListView -match 'TransferListModel\.TR_NAME' `
        -and $transferListView -match 'TransferListModel\.TR_SAVE_PATH' `
        -and $transferListView -match 'TransferListModel\.TR_INFOHASH_V1' `
        -and $transferListView -match 'TransferListModel\.TR_INFOHASH_V2') `
    "the transfer toolbar offers all upstream desktop filter-by choices"

$peerListModel = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/models/peerlistmodel.h")
$peersTab = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/properties/PeersTab.qml")
Test-Policy ($peerListModel -match 'ContributionRole' `
        -and $peerListModel -match 'ContributionValueRole' `
        -and $peerListModel -match 'row\.contribution\s*=\s*static_cast<qreal>\(row\.totalUpload\)' `
        -and $peerListModel -match 'm_sortRole\s*==\s*u"contribution"') `
    "the peer model calculates and numerically sorts upstream contribution"
Test-Policy ($peersTab -match 'role:\s*"contribution"' `
        -and $peersTab -match 'title:\s*qsTr\("Contribution"\)') `
    "the Peers table displays the upstream Contribution column"

$optionsControllerHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/optionscontroller.h")
$optionsControllerSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/optionscontroller.cpp")
$behaviorPage = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/BehaviorPage.qml")
Test-Policy ($optionsControllerHeader -match 'Q_PROPERTY\(bool windowsDefaultAppsAvailable' `
        -and $optionsControllerHeader -match 'Q_INVOKABLE void openWindowsDefaultApps\(\)') `
    "the options controller exposes the Windows Default Apps capability and action"
Test-Policy ($optionsControllerSource -match 'Utils::OS::windowsSystemPath\(\)\.parentPath\(\)' `
        -and $optionsControllerSource -match 'QProcess::startDetached' `
        -and $optionsControllerSource -match 'ms-settings:defaultapps') `
    "the Default Apps action uses the fixed URI through system Explorer on Windows"
Test-Policy ($behaviorPage -match 'visible:\s*OptionsController\.windowsDefaultAppsAvailable' `
        -and $behaviorPage -match 'OptionsController\.openWindowsDefaultApps\(\)' `
        -and $behaviorPage -match 'Accessible\.description:\s*qsTr\(' `
        -and $behaviorPage -match 'action === "windowsDefaultApps"') `
    "the Behavior page platform-gates, describes, invokes, and reports the Default Apps action"

$updateController = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/appcontroller.cpp")
$updateParser = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/updatecheck.cpp")
$appCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/CMakeLists.txt")
Test-Policy ($updateController.Contains('releases/latest') -and $updateController.Contains('.limit(maxReleaseResponseSize)') -and $updateController.Contains('m_updateCheckInProgress') -and $updateController.Contains('result.status != Net::DownloadStatus::Success')) "the program update check is asynchronous, bounded, and failure-safe"
Test-Policy ($updateParser.Contains('draft') -and $updateParser.Contains('prerelease') -and $updateParser.Contains('^build(?:-|\\.)') -and $updateParser.Contains('latest.buildNumber > current.number')) "the update parser accepts only stable immutable builds and compares run numbers"
Test-Policy ($appCMake.Contains('QBT_BUILD_ID=\"${QBT_BUILD_ID}\"')) "the packaged release identity is compiled into the update checker"
Test-Policy (Test-Path -LiteralPath (Get-RepositoryPath "docs/features/delivery/update-check.md") -PathType Leaf) "the in-app update-check behavior and failure modes are documented"

$workflowPath = Get-RepositoryPath ".github/workflows/release-every-push.yml"
Test-Policy (Test-Path -LiteralPath $workflowPath -PathType Leaf) "the push release workflow exists"
if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
    $workflow = Get-Content -Raw -LiteralPath $workflowPath
    $workflowLines = @(Get-Content -LiteralPath $workflowPath)
    $onLine = [Array]::IndexOf($workflowLines, "on:")
    $nextRootLine = $workflowLines.Count
    if ($onLine -ge 0) {
        for ($index = $onLine + 1; $index -lt $workflowLines.Count; $index++) {
            if ($workflowLines[$index] -match '^\S') {
                $nextRootLine = $index
                break
            }
        }
    }
    $onBlock = if ($onLine -ge 0) {
        @($workflowLines[($onLine + 1)..($nextRootLine - 1)])
    }
    else { @() }
    Test-Policy ($onLine -ge 0 -and $onBlock -match '^  push:\s*$') `
        "the root workflow trigger includes push"
    Test-Policy ($onLine -ge 0 -and $onBlock -match '^  workflow_dispatch:\s*$') `
        "the root workflow trigger includes manual dispatch"

    $stepLines = [ordered]@{}
    for ($index = 0; $index -lt $workflowLines.Count; $index++) {
        if ($workflowLines[$index] -match '^      - name: (.+?)\s*$') {
            $stepLines[$Matches[1]] = $index
        }
    }
    $policyStep = $stepLines["Run desktop policy and content-integrity tests"]
    $buildStep = $stepLines["Build"]
    $packageStep = $stepLines["Build and verify the NSIS installer"]
    $publishStep = $stepLines["Publish one immutable non-draft release"]
    Test-Policy ($null -ne $policyStep -and $null -ne $buildStep `
            -and $null -ne $packageStep -and $null -ne $publishStep `
            -and $policyStep -lt $buildStep -and $buildStep -lt $packageStep `
            -and $packageStep -lt $publishStep) `
        "policy, build, installed-package tests, and publication are strictly ordered"

    $tokenPattern = 'secrets\.RELEASE_TOKEN\s*\|\|\s*secrets\.ORG_TOKEN\s*\|\|\s*secrets\.GITHUB_TOKEN'
    Test-Policy (([regex]::Matches($workflow, $tokenPattern)).Count -eq 2) `
        "both GitHub operations use RELEASE_TOKEN, ORG_TOKEN, GITHUB_TOKEN fallback order"
    Test-Policy ($workflow -match 'Measure hosted runner resources') `
        "the workflow measures the hosted runner before relying on it"
    Test-Policy ($workflow -match 'GITHUB_WORKSPACE' -and $workflow -match 'RUNNER_TEMP') `
        "the workflow measures the actual workspace and temporary build volumes"
    Test-Policy ($workflow -match 'test-desktop-policy\.ps1') `
        "the workflow runs this desktop policy test before release"
    Test-Policy ($workflow -match 'resources/dim-sum/har-gow\.png') `
        "the release attaches the bundled Shrimp dumpling image"
    Test-Policy (([regex]::Matches($workflow, '(?m)^\s*gh release create\s')).Count -eq 1) `
        "the workflow has exactly one GitHub Release creation command"
    Test-Policy ($workflow -match 'build-\$env:GITHUB_RUN_NUMBER-\$shortSha') `
        "the immutable tag includes a monotonic run number and commit identity"
    Test-Policy ($workflow -match 'immutable-releases' -and $workflow -match 'isImmutable') `
        "the workflow gates on repository immutability and verifies the published release"
    Test-Policy ($workflow -match 'targetCommitish -ne \$env:GITHUB_SHA') `
        "the published release target is verified against the triggering commit"
    Test-Policy ($workflow -notmatch 'ls-remote\s+--exit-code') `
        "an absent release tag does not leak an expected native failure code"
    Test-Policy ($workflow -notmatch '(?m)^\s*uses:\s*[^@\s]+@(?![0-9a-f]{40}(?:\s|#|$))') `
        "every external GitHub Action is pinned to a full commit"
    Test-Policy ($workflow -match '(?ms)name:\s*Check out the pushed commit.*?fetch-depth:\s*0') `
        "the release checkout includes full history for changelog commit validation"
    Test-Policy ($workflow -notmatch '--draft|--prerelease') `
        "the release command cannot request a draft or prerelease"
    Test-Policy ($workflow -notmatch '--clobber') "the workflow never clobbers a release asset"
    Test-Policy ($workflow -notmatch 'gh release upload') "the workflow never mutates an existing release"
    Test-Policy ($workflow -notmatch '(?i)\btui\b') "the workflow remains Windows-desktop-only"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) of $checks desktop policy checks failed:"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    throw "Desktop policy and content-integrity verification failed."
}

Write-Host ""
Write-Host "All $checks desktop policy and content-integrity checks passed."
