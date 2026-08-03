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
    Test-Policy ($releaseVersions -contains "build-55-a38c40e9") `
        "the changelog is current through the command-palette and context-search handoff"

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
Test-Policy ($sourceCMake -match 'DEPLOY_TOOL_OPTIONS\s+\$\{_qbt_qt_deploy_tool_options\}' `
        -and $sourceCMake -match '--include-plugins qoffscreen') `
    "Windows packages include the offscreen platform plugin used by release smoke tests"

$windowsBuildHelper = Get-Content -Raw -LiteralPath (Get-RepositoryPath "run.ps1")
$windowsLauncher = Get-Content -Raw -LiteralPath (Get-RepositoryPath "run.cmd")
$posixBuildHelper = Get-Content -Raw -LiteralPath (Get-RepositoryPath "run.sh")
Test-Policy ($windowsBuildHelper -match 'CMAKE_HOME_DIRECTORY' `
        -and $windowsBuildHelper -match 'CMAKE_CACHEFILE_DIR' `
        -and $windowsBuildHelper -match 'Reset-MovedCMakeBuild') `
    "the Windows build helper regenerates a relocated CMake build tree"
Test-Policy ($posixBuildHelper -match 'CMAKE_HOME_DIRECTORY' `
        -and $posixBuildHelper -match 'CMAKE_CACHEFILE_DIR' `
        -and $posixBuildHelper -match 'clean_build') `
    "the POSIX build helper regenerates a relocated CMake build tree"
Test-Policy ($windowsBuildHelper -match '\$env:VCPKG_ROOT\s*=\s*\$VcpkgRoot' `
        -and $windowsBuildHelper -match 'Qt deployment tool not found' `
        -and $windowsBuildHelper -match '\$LASTEXITCODE -ne 0\) \{ Die "Qt runtime deployment failed') `
    "the Windows helper pins vcpkg state and fails closed when Qt deployment fails"
Test-Policy ($windowsLauncher -match 'qbt_exit_code=%ERRORLEVEL%' `
        -and $windowsLauncher -match 'QBT_NO_PAUSE' `
        -and $windowsLauncher -match 'exit /b %qbt_exit_code%') `
    "the Windows launcher preserves failures and supports noninteractive invocation"

$sessionImpl = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/sessionimpl.cpp")
$proxyManager = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/net/proxyconfigurationmanager.cpp")
$connectionPage = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/ConnectionPage.qml")
Test-Policy ($sessionImpl -match 'out_enc_policy, encryptionPolicy' `
        -and $sessionImpl -match 'in_enc_policy, encryptionPolicy' `
        -and $sessionImpl -match 'proxy_tracker_connections, useProxy' `
        -and $sessionImpl -match 'useProxy && isProxyPeerConnectionsEnabled\(\)') `
    "BitTorrent encryption and proxy controls are applied to libtorrent"
Test-Policy ($connectionPage -match 'return \[0, 5, 2, 1\]\[index\]' `
        -and $connectionPage -match 'proxyIsSocks4:\s*proxyType === 5' `
        -and $proxyManager -match 'case ProxyType::HTTP:' `
        -and $proxyManager -match 'default:\s*validated\.type = ProxyType::None') `
    "the proxy UI preserves persisted enum values and rejects invalid types"

$wikiSafetyTest = Get-RepositoryPath "scripts/test-wiki-export-safety.ps1"
Test-Policy (Test-Path -LiteralPath $wikiSafetyTest -PathType Leaf) `
    "the Wiki exporter has hostile-manifest regression coverage"
if (Test-Path -LiteralPath $wikiSafetyTest -PathType Leaf) {
    try {
        & $wikiSafetyTest -RepositoryRoot $RepositoryRoot |
            ForEach-Object { Write-Host $_ }
        Test-Policy $true `
            "the Wiki exporter rejects hostile manifests before touching any canary"
    }
    catch {
        Test-Policy $false `
            "the Wiki exporter rejects hostile manifests before touching any canary ($($_.Exception.Message))"
    }
}

$mainQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/Main.qml")
foreach ($surface in @("DimSumSurprise", "NotificationsSheet", "RegexBuilderSheet", "SettingsSheet")) {
    Test-Policy ($mainQml -match [regex]::Escape($surface)) "Main.qml wires $surface"
}
Test-Policy ($mainQml.Contains('function isTextEditor(item)') `
        -and $mainQml.Contains('readonly property bool textEditorHasFocus: root.isTextEditor(root.activeFocusItem)')) `
    "global editing shortcuts share a focused text-editor detector"
Test-Policy ($mainQml.Contains('shortcut: root.textEditorHasFocus ? "" : StandardKey.Delete') `
        -and $mainQml.Contains('JournalController.busy') `
        -and $mainQml.Contains('&& !root.textEditorHasFocus') `
        -and $mainQml -match 'sequences:\s*\[StandardKey\.Paste\][\s\S]*?enabled:\s*root\.currentTabIndex === 0 && !root\.textEditorHasFocus') `
    "Undo, Delete, and Paste yield to focused text editors"

$guiAddManager = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/guiaddtorrentmanager.h")
$addTorrentDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/addtorrent/AddNewTorrentDialog.qml")

# The spoken narrator is optional, off until the user turns it on, serialized so
# utterances never overlap, and honest about sending text to a speech service.
$narratorHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/narratorcontroller.h")
$narratorSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/narratorcontroller.cpp")
$settingsSheetSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/SettingsSheet.qml")
Test-Policy ($narratorSource.Contains('pref->value(kEnabledKey, false).toBool()') `
        -and $narratorSource.Contains('bool m_enabled = false') -eq $false) `
    "the narrator is disabled until the user enables it"
Test-Policy ($narratorHeader.Contains('English = 0') `
        -and $narratorHeader.Contains('Cantonese = 1') `
        -and $narratorHeader.Contains('Both = 2') `
        -and $narratorSource.Contains('zh-HK-HiuMaanNeural')) `
    "the narrator speaks English, Cantonese or both, with a Hong Kong voice"
# One player, one utterance: a burst of events must not stack into a backlog.
Test-Policy ($narratorSource.Contains('if (m_speaking || m_queue.isEmpty())') `
        -and $narratorSource.Contains('m_queue[i] = utterance;') `
        -and $narratorSource.Contains('CategoryCooldownMs') `
        -and $narratorSource.Contains('GlobalDebounceMs')) `
    "narration is serialized, superseded rather than stacked, and rate limited"
# Rate limits shape routine chatter; they never silence a failure.
Test-Policy ($narratorSource.Contains('if (!isError && cooldownBlocks(category))') `
        -and $narratorSource.Contains('m_queue.prepend(utterance)')) `
    "an error is never dropped by the narrator's rate limits"
Test-Policy ($narratorSource.Contains('SPI_GETSCREENREADER')) `
    "the narrator yields to a running screen reader"
Test-Policy ($settingsSheetSource.Contains('NarratorController.enabled') `
        -and $settingsSheetSource -match 'sent to that service') `
    "the narrator setting discloses that speech is synthesized by an online service"

# A settings tab that configures nothing is a fake placeholder. All five Search
# settings were already staged and committed by OptionsController; the page just
# never rendered them.
$searchOptionsPage = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/SearchPage.qml")
$optionsDialogSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/OptionsDialog.qml")
$unboundSearchSettings = @(
    "searchEnabled", "storeOpenedSearchTabs", "storeOpenedSearchTabResults",
    "searchHistoryLength", "pythonExecutablePath"
) | Where-Object { -not $searchOptionsPage.Contains($_) }
Test-Policy (($unboundSearchSettings.Count -eq 0) `
        -and $optionsDialogSource.Contains('SearchPage {}') `
        -and ($optionsDialogSource -notmatch 'informational placeholder')) `
    "the Search options page renders real settings instead of a placeholder$($unboundSearchSettings -join ', ')"
Test-Policy ($searchOptionsPage.Contains('SearchController.unavailableReason') `
        -and $searchOptionsPage.Contains('SearchController.refreshPythonDetection()')) `
    "the Search options page reports whether the chosen interpreter actually works"

# Selecting one row and repeating an action forty times is the app failing to do
# its job. "Select all" must also state its scope: with a filter narrowing the
# view, a user who selects all and deletes needs to know whether that meant the
# rows on screen or every torrent in the session.
$transfersPageSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/TransfersPage.qml")
$centralTabsSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/mainwindow/CentralTabs.qml")
Test-Policy ($transfersPageSource.Contains('function selectAllVisible()') `
        -and $transfersPageSource.Contains('function invertSelection()') `
        -and $centralTabsSource.Contains('function selectAllTransfers()') `
        -and $centralTabsSource.Contains('function invertTransferSelection()')) `
    "the transfer list supports select-all and inverse selection"
Test-Policy (($mainQml -match 'sequences: \[StandardKey\.SelectAll\]') `
        -and ($mainQml -match 'StandardKey\.SelectAll\][\s\S]{0,160}?!root\.textEditorHasFocus')) `
    "select-all is keyboard reachable without stealing Ctrl+A from a text field"
Test-Policy ($transfersPageSource.Contains('readonly property bool filterNarrowsView') `
        -and $transfersPageSource.Contains('qsTr("%1 selected, of %2 shown by the current filter (%3 in total)")')) `
    "the selection summary states whether a filter is narrowing what all means"

# A PATH lookup misses every VS Code installed without "add to PATH" — the
# default for the user-scope installer — and misses Insiders entirely.
$desktopIntegration = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/app/desktopintegration.cpp")
Test-Policy ($desktopIntegration.Contains('QString DesktopIntegration::findWellKnownEditor') `
        -and $desktopIntegration.Contains('Programs\Microsoft VS Code\Code.exe') `
        -and $desktopIntegration.Contains('Code - Insiders.exe')) `
    "editor detection looks where VS Code actually installs, not only on PATH"
# An export the user cannot open is an export they have to hunt for on disk.
$workspaceViewSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/workspace/WorkspaceView.qml")
Test-Policy ($mainQml.Contains('actionId.startsWith("open-export:")') `
        -and $mainQml.Contains('DesktopIntegration.openInExternalEditor(target)') `
        -and $workspaceViewSource.Contains('"open-export:" + target')) `
    "an export offers to open itself in the configured editor"

# Local search surfaces reach the anchored regex builder rather than owning a
# hand-rolled ".*" toggle that cannot build a pattern.
$historySheet = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/HistorySheet.qml")
Test-Policy ($historySheet.Contains('FilterTextField {') `
        -and $historySheet.Contains('readonly property bool histRegex: searchField.regexEnabled') `
        -and -not ($historySheet -match 'text:\s*"\.\*"')) `
    "the history panel searches through the shared field and its anchored builder"
# The Search tab's site query genuinely cannot take a local pattern; the rule
# requires that exemption to be written down rather than left as a silent gap.
Test-Policy ((Get-Content -Raw -LiteralPath `
        (Get-RepositoryPath "docs/features/transfers/search-runtime.md")) `
        -match 'Documented exemption: the site-query field has no regex builder') `
    "the one search field without a builder documents why the rule cannot apply"

# Irreversible actions sit behind a deliberate gate: two independently operated
# keys, then a full-range slider, with an always-available emergency exit. A
# partial slide is not a decision and must spring back.
$superConfirm = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/SuperConfirmDialog.qml")
Test-Policy ($superConfirm.Contains('id: keyOne') `
        -and $superConfirm.Contains('id: keyTwo') `
        -and $superConfirm.Contains('readonly property bool bothKeysTurned: keyOne.checked && keyTwo.checked') `
        -and $superConfirm.Contains('enabled: root.bothKeysTurned')) `
    "the destructive gate needs two independent keys before its slider arms"
Test-Policy (($superConfirm -match 'if \(value < to\)\s*\r?\n\s*value = 0') `
        -and $superConfirm.Contains('root._authorize()')) `
    "a partial slide springs back and never authorizes a destructive action"
Test-Policy ($superConfirm.Contains('qsTr("Emergency exit")') `
        -and $superConfirm.Contains('closePolicy: Popup.CloseOnEscape') `
        -and $superConfirm.Contains('function _restoreFocus()') `
        -and $superConfirm.Contains('root._restoreFocus()')) `
    "the destructive gate always offers an escape and returns focus to its origin"
Test-Policy ($superConfirm.Contains('ThemeManager.reducedMotion === true') `
        -and $superConfirm.Contains('enabled: !root.reducedMotion')) `
    "the destructive gate honors reduced motion instead of playing its animations"
Test-Policy ($superConfirm.Contains('qsTr("This cannot be undone.")') `
        -and $superConfirm.Contains('root.actionText') `
        -and $superConfirm.Contains('qsTr("This affects: %1").arg(root.affectedText)')) `
    "the destructive gate states the exact action and what it affects"
$deletionDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/dialogs/DeletionConfirmationDialog.qml")
Test-Policy ($deletionDialog.Contains('SuperConfirmDialog {') `
        -and $deletionDialog.Contains('superConfirm.originatingControl = confirmButton') `
        -and $deletionDialog.Contains('onAuthorized:')) `
    "erasing downloaded files goes through the destructive gate"

# Controls presented as usable must perform their labelled action. The Trackers
# tab shipped five commands and a download button that routed through shims and
# only wrote a log line, so the whole surface looked live and did nothing.
$propertiesControllerHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/propertiescontroller.h")
$transferControllerHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/transfercontroller.h")
$trackersTab = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/properties/TrackersTab.qml")
$addTrackersDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/properties/dialogs/AddTrackersDialog.qml")
$trackersFilterList = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TrackersFilterList.qml")
$missingTrackerVerbs = @(
    "void addTrackers(const QString &multilineUrls)",
    "void editTracker(const QString &oldUrl, const QString &newUrl)",
    "void removeTrackers(const QStringList &urls)",
    "void reannounceToTrackers(const QStringList &urls)",
    "void reannounceToAllTrackers()",
    "void fetchTrackerList(const QString &url)"
) | Where-Object { -not $propertiesControllerHeader.Contains($_) }
Test-Policy ($missingTrackerVerbs.Count -eq 0) `
    "every Trackers-tab command is backed by a real controller verb$($missingTrackerVerbs -join '; ')"
Test-Policy ($transferControllerHeader.Contains('int removeTrackerFromAll(const QString &host)')) `
    "removing a tracker from every torrent is backed by a real controller verb"
# The shims silently swallowed a missing verb; nothing may reintroduce them.
Test-Policy (($trackersTab -notmatch 'is not available') `
        -and ($addTrackersDialog -notmatch 'is not available') `
        -and ($trackersFilterList -notmatch 'is not available') `
        -and ($addTrackersDialog -notmatch 'typeof PropertiesController') `
        -and ($trackersFilterList -notmatch 'typeof TransferController')) `
    "tracker commands call their controller directly instead of degrading to a log line"
Test-Policy ($trackersTab.Contains('function onTrackerActionFinished(ok, message)') `
        -and $addTrackersDialog.Contains('function onTrackerListFetchFinished()')) `
    "tracker actions report their real outcome and never leave a spinner running"

# Every context menu carries its own keyboard-accessible search field, and that
# field reaches the regex builder like every other search surface. Menus derive
# from SearchableMenu so none of that can be forgotten one menu at a time.
$searchableMenu = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/SearchableMenu.qml")
Test-Policy ($searchableMenu.Contains('FilterTextField {') `
        -and $searchableMenu.Contains('function matches(label)') `
        -and $searchableMenu.Contains('WorkspaceManager.evaluateRegularExpression(')) `
    "menu search filters through the app's own regex engine and reaches the builder"
# The evaluator returns its tally as "count". Reading any other key yields
# undefined, and `undefined > 0` hides every item as soon as regex is enabled.
$workspaceManagerSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/workspacemanager.cpp")
Test-Policy ($workspaceManagerSource.Contains('{QStringLiteral("count"), matches.size()}') `
        -and $searchableMenu.Contains('(evaluation.count > 0)') `
        -and -not $searchableMenu.Contains('matchCount')) `
    "menu regex matching reads the evaluator's real result key"
# A menu item's shortcut Label is right-anchored, so it adds nothing to
# implicitWidth; without a floor the menu collapses and paints over the label.
Test-Policy ($searchableMenu.Contains('property int minimumMenuWidth') `
        -and ($searchableMenu -match 'implicitWidth: Math\.max\(root\.minimumMenuWidth') `
        -and $searchableMenu.Contains('height: Math.min(implicitHeight, root.maxMenuHeight)')) `
    "context menus are wide enough for their shortcuts and scroll instead of clipping"
# Base handlers live in Connections: a derived `onOpened:` would replace them.
Test-Policy (($searchableMenu -match 'Connections \{[\s\S]{0,400}?function onAboutToShow\(\)') `
        -and ($searchableMenu -match 'function onOpened\(\)')) `
    "menu search reset and focus survive a deriving menu declaring its own handlers"

$contextMenuFiles = @(Get-ChildItem -LiteralPath (Get-RepositoryPath "src/quick/qml") `
    -Filter "*ContextMenu.qml" -File -Recurse)
$unsearchableMenus = @($contextMenuFiles | Where-Object {
    (Get-Content -Raw -LiteralPath $_.FullName) -notmatch '(?m)^SearchableMenu \{'
})
Test-Policy (($contextMenuFiles.Count -ge 10) -and ($unsearchableMenus.Count -eq 0)) `
    "every context menu derives from SearchableMenu$(($unsearchableMenus.Name) -join ', ')"

# Dropping a .torrent or magnet on the window must add it. Without a drop
# target the gesture is a complete no-op — no dialog, no error, no log line —
# which is indistinguishable from "adding a torrent does nothing".
Test-Policy ($mainQml.Contains('DropArea {') `
        -and $mainQml.Contains('id: torrentDropArea') `
        -and $mainQml -match 'onDropped:\s*\(drop\)\s*=>' `
        -and $mainQml.Contains('AppController.addTorrentFromSource(sources[i])')) `
    "dropping a torrent file or magnet link on the window adds it"
Test-Policy ($mainQml -match 'torrentDropArea[\s\S]{0,600}?containsDrag') `
    "an active drag over the window shows a drop affordance"

# A "file://" URL matches QNetworkAccessManager's supported schemes, so leaving
# it unnormalized routes local files through the HTTP download stack, skipping
# the TorrentFileGuard and reporting local errors as network failures.
Test-Policy ($guiAddManager.Contains('static QString normalizeSource(const QString &source)') `
        -and $guiAddManager.Contains('const QString source = normalizeSource(rawSource);') `
        -and $guiAddManager.Contains('QDir::toNativeSeparators(localFile)')) `
    "local file sources are normalized before the download-scheme test"
Test-Policy ($guiAddManager -match 'if \(m_pendingMerges\.isEmpty\(\)\)\s*\r?\n\s*scheduleNextDialogRequest\(\);') `
    "an unmatched tracker-merge response cannot strand the serialized dialog pipeline"
Test-Policy ($guiAddManager.Contains('QQueue<PendingDialogRequest> m_pendingDialogRequests') `
        -and $guiAddManager.Contains('m_dialogPipelineBusy') `
        -and $guiAddManager.Contains('QTimer::singleShot(0, this') `
        -and $guiAddManager.Contains('scheduleNextDialogRequest()')) `
    "add-torrent dialogs use one deferred FIFO that advances on every terminal path"
Test-Policy ($guiAddManager.Contains('request = PendingDownload {params, true}') `
        -and $guiAddManager.Contains('request = PendingDownload {params, false}') `
        -and -not $guiAddManager.Contains('m_downloadedTorrents')) `
    "remote torrent completions retain per-request parameters even for identical URLs"
Test-Policy ($guiAddManager.Contains('const bool mergingEnabled = m_session->isMergeTrackersEnabled()') `
        -and $guiAddManager.Contains('!m_session || !m_session->isMergeTrackersEnabled()') `
        -and $guiAddManager.Contains('!isPrivate && confirmationAvailable') `
        -and $guiAddManager.Contains('has no responder; declining merge')) `
    "tracker merging honors global, privacy, response-time, and missing-responder safeguards"
Test-Policy ($addTorrentDialog.Contains('function onMergeTrackersRequested(source, name, isPrivate)') `
        -and ([regex]::Matches($addTorrentDialog, 'closePolicy:\s*Popup\.NoAutoClose')).Count -eq 2 `
        -and ([regex]::Matches($addTorrentDialog, 'onActivated:\s*[^\r\n]*\.reject\(\)')).Count -eq 2 `
        -and $addTorrentDialog.Contains('GuiAddTorrentManager.respondMergeTrackers(source, true)') `
        -and $addTorrentDialog.Contains('GuiAddTorrentManager.respondMergeTrackers(source, false)')) `
    "add and merge dialogs reject explicitly and the merge prompt always responds"

$sessionHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/sessionimpl.h")
$addTorrentController = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/addtorrentcontroller.cpp")
$addTorrentControllerHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/addtorrentcontroller.h")
$torrentImpl = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/torrentimpl.cpp")
$torrentInfo = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/torrentinfo.cpp")
$torrentDescriptor = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/torrentdescriptor.cpp")
Test-Policy ($sessionImpl.Contains('m_nativeSession->add_torrent(p, error)') `
        -and $sessionImpl.Contains('cancelDownloadMetadata(TorrentID::fromInfoHash(infoHash))') `
        -and $sessionImpl.Contains('emit metadataDownloaded(TorrentInfo {*nativeInfo})') `
        -and $sessionImpl.Contains('m_nativeSession->remove_torrent(alert->handle)') `
        -and $addTorrentController.Contains('if (m_session)') `
        -and -not $addTorrentController.Contains('if (m_session && !hasMetadata())')) `
    "magnet metadata previews are concrete, delivered, and removed on accept or reject"
Test-Policy ($sessionImpl.Contains('p.userdata = &metadataPreviewAddTag') `
        -and $sessionImpl.Contains('userdata.get<MetadataPreviewAddTag>()') `
        -and $sessionImpl.Contains('p.flags |= lt::torrent_flags::duplicate_is_error') `
        -and $sessionImpl.Contains('it.value() == alert->handle')) `
    "metadata preview alerts and aliases cannot consume or remove a real same-hash add"
Test-Policy ($torrentInfo.Contains('ownV1.isValid() && otherV1.isValid()') `
        -and $torrentInfo.Contains('ownV2.isValid() && otherV2.isValid()') `
        -and $torrentDescriptor.Contains('m_ltAddTorrentParams.info_hashes =') `
        -and $torrentImpl.Contains('m_nativeHandle.set_metadata(') `
        -and $sessionImpl.Contains('m_hybridTorrentsByAltID.insert(v2ID, torrent)') `
        -and $sessionImpl.Contains('loadTorrentParams.id = id')) `
    "partial v1 or v2 magnets safely adopt and persist hybrid metadata"
Test-Policy ($addTorrentControllerHeader -match `
            'private:\s*explicit AddTorrentController\(QObject \*parent = nullptr\)' `
        -and $addTorrentController.Contains('QJSEngine::setObjectOwnership(controller') `
        -and $guiAddManager.Contains('QJSEngine::setObjectOwnership(manager')) `
    "add-torrent QML singletons cannot bypass their shared C++ factories"
Test-Policy ($sessionHeader.Contains('QHash<TorrentID, AddTorrentAlertHandler> m_addTorrentAlertHandlers') `
        -and $sessionHeader.Contains('QSet<TorrentID> m_addingTorrents') `
        -and $sessionImpl.Contains('m_addTorrentAlertHandlers.insert(id') `
        -and $sessionImpl.Contains('emit addTorrentFailed(infoHash')) `
    "normal torrent adds are known while queued and correlate alerts by info hash"
Test-Policy ($guiAddManager.Contains('&BitTorrent::Session::torrentAdded') `
        -and $guiAddManager.Contains('&BitTorrent::Session::addTorrentFailed') `
        -and $guiAddManager.Contains('QHash<BitTorrent::TorrentID, PendingSessionAdd>') `
        -and $guiAddManager.Contains('pending.guard->markAsAddedToSession()') `
        -and $guiAddManager.Contains('queued torrent add from') `
        -and $guiAddManager.Contains('session confirmed torrent from')) `
    "the GUI reports and cleans up adds only after the session confirms their outcome"
Test-Policy ($guiAddManager.Contains('std::optional<BitTorrent::TorrentID> m_activeSessionAddID') `
        -and $guiAddManager.Contains('const QScopedValueRollback activeAddScope') `
        -and $guiAddManager.Contains('*m_activeSessionAddID != infoHash.toTorrentID()')) `
    "same-hash failures from other session callers cannot consume a pending GUI add"
Test-Policy ($sessionImpl.Contains('while (!m_addTorrentAlertHandlers.isEmpty()') `
        -and $sessionImpl.Contains('saveResumeData();') `
        -and $sessionImpl.Contains('while ((m_numResumeData > 0)')) `
    "shutdown drains accepted torrent adds before the final resume checkpoint"
Test-Policy ($addTorrentDialog.Contains('function onTorrentAdded(source)') `
        -and $addTorrentDialog.Contains('function onAddTorrentFailed(source, reason)') `
        -and $addTorrentDialog.Contains('function onDuplicateTorrent(source, name)')) `
    "add success, failure, and duplicate outcomes reach persistent notifications"

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
    Test-Policy ($filterPanelSource -match 'acceptedButtons:\s*Qt\.LeftButton\s*\|\s*Qt\.RightButton' `
            -and $filterPanelSource -notmatch 'TapHandler\s*\{') `
        "$filterPanel routes left and right clicks through one pointer target"
}

$experienceController = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/controllers/experiencecontroller.cpp")
$experienceHeader = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/controllers/experiencecontroller.h")
$dimSumSurface = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/DimSumSurprise.qml")
$settingsSheet = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/SettingsSheet.qml")
Test-Policy ($experienceController -match 'bounded\(10\)\s*!=\s*0') `
    "startup dim-sum surprise uses one fresh 10 percent draw"
Test-Policy (($experienceController -notmatch 'DimSumSurpriseEnabled') -and
    ($experienceHeader -notmatch 'dimSumEnabled') -and
    ($dimSumSurface -notmatch 'Turn off surprises') -and
    ($settingsSheet -notmatch 'Enable startup dim sum surprise')) `
    "startup dim-sum surprise has no opt-out and ignores legacy disabled preferences"
Test-Policy (-not (Select-String -Path (Get-RepositoryPath "src/quick/qml/transferlist/*.qml") `
        -Pattern 'root\.proxy\.set(?:Status|Category|Tag|Tracker)Filter\(' -Quiet)) `
    "QML filter rows assign writable proxy properties instead of calling non-invokable setters"
$filterProxyHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/torrentfilterproxymodel.h")
Test-Policy ($filterProxyHeader -match 'Q_INVOKABLE\s+void\s+clearTrackerFilter\(\)') `
    "the All-trackers row has an invokable criterion reset"

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
$commandPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/CommandPalette.qml")
$mainQmlForPalette = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/Main.qml")
$optionsDialogForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/OptionsDialog.qml")
Test-Policy ($mainQmlForPalette -match 'Shortcut\s*\{\s*sequences:\s*\["Ctrl\+Shift\+P"\]' `
        -and $mainQmlForPalette -match 'CommandPalette\s*\{' `
        -and $mainQmlForPalette -match 'invokePaletteCommand\(commandId\)') `
    "Ctrl+Shift+P opens the wired desktop command palette"
Test-Policy ($commandPalette -match 'WorkspaceManager\.evaluateRegularExpression' `
        -and $commandPalette -match 'Keys\.onDownPressed' `
        -and $commandPalette -match 'Keys\.onUpPressed' `
        -and $commandPalette -match 'Keys\.onReturnPressed' `
        -and $commandPalette -match 'Accessible\.name:\s*qsTr\("Search command palette"\)') `
    "the command palette supports shared regex search, keyboard navigation, and accessible naming"
Test-Policy ($commandPalette -match 'GUI/CommandPalette/FullWindow' `
        -and $commandPalette -match 'color:\s*Theme\.color\("surface"\)' `
        -and $commandPalette -match 'clip:\s*true') `
    "the command palette persists card/full-window choice and paints a bounded scrollable surface"
Test-Policy ($mainQmlForPalette -match 'id:\s*"options\.0"' `
        -and $mainQmlForPalette -match 'id:\s*"options\.8"' `
        -and $optionsDialogForPalette -match 'function showPage\(index\)') `
    "the first palette slice reaches every Options page directly"
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
$downloadHandler = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/base/net/downloadhandlerimpl.cpp")
$downloadManager = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/base/net/downloadmanager.cpp")
$appCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/CMakeLists.txt")
Test-Policy ($updateController.Contains('releases/latest') -and $updateController.Contains('.limit(maxReleaseResponseSize)') -and $updateController.Contains('m_updateCheckInProgress') -and $updateController.Contains('result.status != Net::DownloadStatus::Success')) "the program update check is asynchronous, bounded, and failure-safe"
Test-Policy ($updateParser.Contains('draft') -and $updateParser.Contains('prerelease') -and $updateParser.Contains('^build(?:-|\\.)') -and $updateParser.Contains('latest.buildNumber > current.number')) "the update parser accepts only stable immutable builds and compares run numbers"
Test-Policy ($downloadHandler.Contains('if (m_isFinished)') `
        -and $downloadHandler.Contains('m_result.data.size() > m_downloadRequest.limit()') `
        -and $downloadHandler.Contains('std::max(bytesReceived, bytesTotal)') `
        -and $downloadHandler -notmatch 'bytesTotal\s*>\s*0\)\s*&&\s*\(bytesTotal\s*<=\s*m_downloadRequest\.limit\(\)') `
    "bounded downloads enforce the limit through completion and finish only once"
Test-Policy ($downloadManager.Contains('scheme.compare(u"https"') `
        -and $downloadManager.Contains('? 443') `
        -and $downloadManager.Contains('url.host().toLower()')) `
    "sequential download services normalize hosts and use the HTTPS default port"
Test-Policy ($appCMake.Contains('QBT_BUILD_ID=\"${QBT_BUILD_ID}\"')) "the packaged release identity is compiled into the update checker"
Test-Policy (Test-Path -LiteralPath (Get-RepositoryPath "docs/features/delivery/update-check.md") -PathType Leaf) "the in-app update-check behavior and failure modes are documented"

# --- Search: the nova3 runtime must actually ship -----------------------------
# SearchPluginManager hard-codes ":/searchengine/nova3/<file>" and shells out to
# `python nova2.py --capabilities`. When those resources are absent the whole
# Search tab is dead and every plugin install rolls back reporting the
# misleading "Plugin is not supported." Assert the runtime is present, bundled
# by both resource paths, and guarded at configure time.
$novaRuntimeFiles = @("helpers.py", "nova2.py", "nova2dl.py", "novaprinter.py", "socks.py")
$missingNovaFiles = [System.Collections.Generic.List[string]]::new()
$unversionedNovaFiles = [System.Collections.Generic.List[string]]::new()
foreach ($novaFile in $novaRuntimeFiles) {
    $novaPath = Get-RepositoryPath "resources/searchengine/nova3/$novaFile"
    if (-not (Test-Path -LiteralPath $novaPath -PathType Leaf)) {
        $missingNovaFiles.Add($novaFile)
        continue
    }
    # updateNova() only extracts a bundled file when its "# VERSION:" header
    # beats the on-disk copy, so a header-less file would never be installed.
    $novaHead = Get-Content -LiteralPath $novaPath -TotalCount 40
    if (-not ($novaHead -match '^#\s*VERSION:\s*[0-9]')) {
        $unversionedNovaFiles.Add($novaFile)
    }
}
Test-Policy ($missingNovaFiles.Count -eq 0) `
    "the nova3 search runtime is bundled in the repository$($missingNovaFiles -join ', ')"
Test-Policy ($unversionedNovaFiles.Count -eq 0) `
    "every bundled nova3 runtime file carries the VERSION header updateNova compares$($unversionedNovaFiles -join ', ')"

$searchResourcesQrc = Get-Content -Raw -LiteralPath (Get-RepositoryPath "resources/resources.qrc")
Test-Policy ($appCMake.Contains('searchengine/nova3/*.py') `
        -and $appCMake.Contains('QBT_NOVA_RUNTIME_FILES') `
        -and ($appCMake -match 'message\(FATAL_ERROR[\s\S]{0,200}Missing bundled search runtime') `
        -and $searchResourcesQrc.Contains('searchengine/nova3/nova2.py')) `
    "both resource paths bundle the nova3 runtime and a missing one fails the configure step"

Test-Policy ($appCMake -match 'find_package\(Qt6 REQUIRED COMPONENTS Xml\)' `
        -and $appCMake -notmatch 'find_package\(Qt6 QUIET COMPONENTS Xml\)') `
    "Qt6::Xml is required because the capabilities parser uses QDomDocument unconditionally"

$searchPluginManager = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/search/searchpluginmanager.cpp")
$searchControllerSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/searchcontroller.cpp")
$searchEmptyPage = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/search/SearchNoPluginsPage.qml")
Test-Policy ($searchPluginManager.Contains('setRuntimeError(') `
        -and $searchPluginManager.Contains('if (!pyInfo.isValid())') `
        -and $searchPluginManager.Contains('if (!novaScript.exists())') `
        -and $searchPluginManager.Contains('Bundled search runtime file is missing from the application resources')) `
    "the search runtime reports missing Python, a missing nova script, and unbundled resources"
Test-Policy ($searchControllerSource.Contains('Utils::ForeignApps::pythonInfo()') `
        -and $searchControllerSource -notmatch 'QStandardPaths::findExecutable\(') `
    "Python detection executes the interpreter instead of trusting a PATH entry"
Test-Policy ($searchEmptyPage.Contains('SearchController.unavailableReason') `
        -and $searchEmptyPage.Contains('visible: !root.blocked') `
        -and $searchEmptyPage.Contains('SearchController.refreshPythonDetection()')) `
    "the search empty state separates a blocked runtime from having no plugins yet"
Test-Policy (Test-Path -LiteralPath (Get-RepositoryPath "docs/features/transfers/search-runtime.md") -PathType Leaf) `
    "the bundled search runtime and its failure modes are documented"

# This fork ships the runtime, so the Search tab is on by default (upstream
# hides it). Keep the C++ preference and its QML mirror agreeing, and keep the
# startup probe off the GUI thread's critical path.
$preferencesSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/base/preferences.cpp")
$preferencesBridge = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/preferencescontroller.cpp")
Test-Policy ($preferencesSource -match 'readSetting\(u"Preferences/Search/SearchEnabled"_s, true\)' `
        -and $preferencesBridge -match 'm_preferences->isSearchEnabled\(\) : true') `
    "the Search tab is enabled by default and the QML bridge mirrors that default"
# The Search tab is useless without sources, so plugins ship too. Seeding must
# never downgrade a user-updated plugin and must never resurrect one the user
# uninstalled, or the uninstall button would silently do nothing across restarts.
$bundledEngineDir = Get-RepositoryPath "resources/searchengine/nova3/engines"
$bundledEngines = @()
if (Test-Path -LiteralPath $bundledEngineDir -PathType Container) {
    $bundledEngines = @(Get-ChildItem -LiteralPath $bundledEngineDir -Filter "*.py" -File)
}
Test-Policy ($bundledEngines.Count -ge 5) `
    "the application bundles a usable set of search plugins ($($bundledEngines.Count) found)"
$unversionedEngines = @($bundledEngines | Where-Object {
    -not ((Get-Content -LiteralPath $_.FullName -TotalCount 40) -match '^#\s*VERSION:\s*[0-9]')
})
Test-Policy ($unversionedEngines.Count -eq 0) `
    "every bundled search plugin carries a VERSION header$(($unversionedEngines.Name) -join ', ')"
$enginesInQrc = @($bundledEngines | Where-Object {
    -not $searchResourcesQrc.Contains("searchengine/nova3/engines/$($_.Name)")
})
Test-Policy (($enginesInQrc.Count -eq 0) -and $appCMake.Contains('searchengine/nova3/engines/*.py')) `
    "both resource paths bundle every search plugin$(($enginesInQrc.Name) -join ', ')"
Test-Policy ($appCMake -match 'message\(FATAL_ERROR[\s\S]{0,160}No bundled search plugins found') `
    "a build that bundles no search plugins fails at configure time"
Test-Policy ($searchPluginManager.Contains('void SearchPluginManager::seedBundledPlugins()') `
        -and $searchPluginManager.Contains('if (alreadySeeded.contains(name))') `
        -and $searchPluginManager.Contains('getPluginVersion(bundledPath) <= getPluginVersion(diskPath)')) `
    "seeding skips uninstalled plugins and never downgrades a newer installed one"
Test-Policy ($preferencesSource.Contains('u"SearchEngines/seededPlugins"_s') `
        -and $preferencesSource.Contains('QStringList Preferences::getSeededSearchPlugins() const')) `
    "the set of already-seeded bundled plugins is persisted so uninstalls stick"

# Scope this to the constructor: reload() legitimately runs both calls inline
# because the user asked for it and expects a fresh answer.
$searchManagerCtor = [regex]::Match($searchPluginManager,
    'SearchPluginManager::SearchPluginManager\(\)[\s\S]*?\n\}').Value
Test-Policy ($searchManagerCtor -match 'QTimer::singleShot\(0, this, \[this\] \{ update\(\); \}\)' `
        -and $searchManagerCtor -notmatch '\n\s*update\(\);') `
    "the startup capabilities probe is deferred instead of blocking construction"

# --- Workspace: the browser-style tab strip must actually be visible ----------
# "surfaceWarm" is aliased to primaryContainer in ThemeManager's named-id map,
# which is exactly the selected tab's fill. Painting the strip with it made the
# active tab invisible against its own background, and unselected tabs had no
# fill at all, so no tab shapes were drawn.
$workspaceStrip = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/workspace/WorkspaceTabStrip.qml")
$workspaceView = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/workspace/WorkspaceView.qml")
$themeManager = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/theme/thememanager.cpp")
Test-Policy ($themeManager.Contains('m_namedIdMap.insert(u"surfaceWarm"_s, u"primaryContainer"_s)')) `
    "surfaceWarm is still an alias of primaryContainer, so the strip must not use it"
Test-Policy ($workspaceStrip -match 'implicitHeight: Spacing\.controlHeight \+ Spacing\.sm[\s\S]{0,400}?color: Theme\.color\("surfaceVariant"\)' `
        -and $workspaceStrip -notmatch 'color: Theme\.color\("surfaceWarm"\)') `
    "the workspace tab strip paints a recessed tray that differs from the selected tab"
Test-Policy ($workspaceStrip.Contains('tabData.appearance.backgroundColor || Theme.color("surface")') `
        -and $workspaceStrip.Contains('tabData.appearance.hoverColor || Theme.color("surfaceContainerHigh")') `
        -and $workspaceStrip.Contains('tabData.appearance.checkedColor || Theme.color("primaryContainer")')) `
    "selected, unselected, and hovered workspace tabs each paint a distinct fill"
Test-Policy ($workspaceStrip.Contains('function positionTabInView(index)') `
        -and $workspaceView.Contains('modernTabStrip.positionTabInView(WorkspaceManager.activeIndex)') `
        -and $workspaceView -notmatch 'tabList\.positionViewAtIndex') `
    "activating a workspace tab scrolls the visible strip rather than a hidden list"
Test-Policy ($workspaceView -notmatch 'objectName: "workspaceTabBar"' `
        -and ([regex]::Matches(($workspaceStrip + $workspaceView), 'objectName: "workspaceAddTabButton"')).Count -eq 1) `
    "the workspace has exactly one tab bar, so automation cannot bind an invisible copy"

$torrentJournal = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/torrentjournal/torrentjournal.cpp")
Test-Policy ($torrentJournal -match 'if \(!writeTorrentFiles\(torrent, &changed\)\)\s*writeSucceeded = false' `
        -and $torrentJournal -match 'if \(sessionDirty && !writeSessionFile\(\)\)\s*writeSucceeded = false' `
        -and $torrentJournal -match 'requeueActionBatch\(std::move\(retryOps\), std::move\(dirty\), sessionDirty, true\)') `
    "torrent journal write and commit failures retain the complete action batch for retry"
Test-Policy ($torrentJournal -match 'Torrent blob write failed[\s\S]*?return false;' `
        -and $torrentJournal -match 'Async undo expectations are consumed only after Git accepted the batch') `
    "torrent blob failures retry and undo annotations survive failed commits"
Test-Policy ($torrentJournal -match 'Settings journal write failed:[\s\S]*?requeueChanges\(\);' `
        -and $torrentJournal -match 'Settings journal commit failed:[\s\S]*?requeueChanges\(\);') `
    "settings journal changes survive write and commit failures"

$transferContextMenu = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TransferRowContextMenu.qml")
$logContextMenu = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/log/LogContextMenu.qml")
$transfersPage = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/TransfersPage.qml")
$transferListView = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TransferListView.qml")
Test-Policy ($transfersPage -match 'property var selectedTorrentIds:\s*\[\]' `
        -and $transfersPage -match 'function remapSelection\(\)' `
        -and $transfersPage -match 'visibleIds\.indexOf\(id\)' `
        -and $transfersPage -match 'function onLayoutChanged\(\) \{ root\.remapSelection\(\) \}') `
    "redesigned transfer selection remaps stable torrent IDs after model layout changes"
Test-Policy ($transferListView -match 'property var _selectedTorrentIds:\s*\[\]' `
        -and $transferListView -match 'function _remapSelection\(\)' `
        -and $transferListView -match 'visibleIds\.indexOf\(id\)' `
        -and $transferListView -match 'function onLayoutChanged\(\) \{ view\._remapSelection\(\); \}') `
    "legacy transfer selection remaps stable torrent IDs after model layout changes"
# The search field, its focus and its regex builder now come from SearchableMenu
# rather than being re-hand-rolled per menu, so assert the derivation and the
# per-item gating that the base cannot supply on the menu's behalf.
Test-Policy (($transferContextMenu -match '(?m)^SearchableMenu \{') `
        -and ($transferContextMenu -match 'searchAccessibleName:\s*qsTr\("Search transfer actions"\)') `
        -and ($transferContextMenu -match 'visible:\s*root\.matches\(text\)')) `
    "the transfer context menu provides keyboard-focused local action search"
Test-Policy ($transferContextMenu -match 'root\.startAction\.shortcut\.toString\(\)' `
        -and $transferContextMenu -match 'root\.stopAction\.shortcut\.toString\(\)' `
        -and $transferContextMenu -match 'root\.removeAction\.shortcut\.toString\(\)' `
        -and ([regex]::Matches($transferContextMenu, 'Accessible\.description:\s*[^\r\n]*Shortcut|Accessible\.description:\s*[^\r\n]*\r?\n\s*\? qsTr\("Keyboard shortcut')).Count -ge 3 `
        -and $transfersPage -match 'startAction:\s*root\.shell\.actionStart' `
        -and $transfersPage -match 'stopAction:\s*root\.shell\.actionStop' `
        -and $transfersPage -match 'removeAction:\s*root\.shell\.actionDelete') `
    "transfer context shortcuts derive from shared actions and use Qt 6.8 accessibility properties"
Test-Policy (($logContextMenu -match '(?m)^SearchableMenu \{') `
        -and ($logContextMenu -match 'searchAccessibleName:\s*qsTr\("Search log actions"\)') `
        -and ($logContextMenu -match 'visible:\s*root\.matches\(text\)') `
        -and ($logContextMenu -match 'Accessible\.description:\s*qsTr\("Keyboard shortcut Ctrl\+C"\)')) `
    "the log context menu filters locally and truthfully exposes its Copy shortcut"
Test-Policy (Test-Path -LiteralPath `
        (Get-RepositoryPath "docs/features/experience/context-menu-search.md") -PathType Leaf) `
    "searchable context actions and shortcut truthfulness are documented"

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
    Test-Policy ($workflow -match 'actions/setup-python@[0-9a-f]{40}' `
            -and $workflow -match 'jurplel/install-qt-action/action@[0-9a-f]{40}') `
        "the Qt installer bypasses its mutable wrapper dependencies"
    Test-Policy ($workflow -match 'qoffscreen\.dll' `
            -and $workflow -match 'qoffscreend\.dll' `
            -and $workflow -match 'RedirectStandardOutput' `
            -and $workflow -match 'Write-SmokeOutput') `
        "installed-package smoke tests assert release plugins and retain launch diagnostics"
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
