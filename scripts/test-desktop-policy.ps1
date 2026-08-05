[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [switch] $SkipRuntimeStartup
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
    "src/quick/qml/components/AdvancedColorPicker.qml",
    "src/quick/qml/components/Snackbar.qml",
    "src/quick/qml/components/UpdateOperationBanner.qml",
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
    "resources/branding/qbittorrent-material.rc.in",
    "docs/assets/logo-mark.png",
    "resources/experience/changelog.json",
    "resources/experience/release-identity.json",
    "resources/updates/squirrel-feed-public-key.json",
    "scripts/count-lines.ps1",
    "scripts/select-release-dim-sum.ps1",
    "src/quick/qml/shell/MaterialTitleBar.qml"
)
foreach ($relativePath in $requiredDesktopFiles) {
    Test-Policy (Test-Path -LiteralPath (Get-RepositoryPath $relativePath) -PathType Leaf) `
        "$relativePath is present"
}

$lineCounterSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "scripts/count-lines.ps1")
Test-Policy ($lineCounterSource.Contains('HumanLines') `
        -and $lineCounterSource.Contains('Human-written physical lines') `
        -and $lineCounterSource.Contains('$grand.AgentLines + $grand.HumanLines') `
        -and $lineCounterSource.Contains('Co-Authored-By:') `
        -and $lineCounterSource.Contains('.+\[bot\]')) `
    "the committed line counter reports explicit human/agent surviving-line attribution with conservative automation identities"

$feedPublicKey = Read-JsonFile "resources/updates/squirrel-feed-public-key.json"
if ($null -ne $feedPublicKey) {
    $feedPublicDer = $null
    $feedPublicRsa = $null
    try {
        $feedPublicDer = [Convert]::FromBase64String(
            [string]$feedPublicKey.spkiDerBase64)
        $feedPublicFingerprint = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($feedPublicDer)).ToLowerInvariant()
        $feedPublicRsa = [Security.Cryptography.RSA]::Create()
        $feedPublicBytesRead = 0
        $feedPublicRsa.ImportSubjectPublicKeyInfo(
            $feedPublicDer, [ref]$feedPublicBytesRead)
        Test-Policy ($feedPublicKey.schemaVersion -eq 1 `
                -and $feedPublicKey.algorithm -eq 'RSASSA-PKCS1-v1_5-SHA256' `
                -and $feedPublicRsa.KeySize -eq 3072 `
                -and $feedPublicBytesRead -eq $feedPublicDer.Length `
                -and $feedPublicFingerprint -eq [string]$feedPublicKey.spkiSha256 `
                -and $feedPublicFingerprint -eq '4479439dfb5bce538ab92e492dd677628060c8558d4c49ac7b253f3eeb4f36e8') `
            "the committed Squirrel feed public key is the expected RSA-3072 SPKI and exact fingerprint"
    }
    catch {
        Test-Policy $false `
            "the committed Squirrel feed public key is the expected RSA-3072 SPKI and exact fingerprint ($($_.Exception.Message))"
    }
    finally {
        if ($null -ne $feedPublicRsa) { $feedPublicRsa.Dispose() }
    }
}

try {
    Add-Type -AssemblyName System.Drawing
    Test-Policy $true "the Windows image decoder is available"
}
catch {
    Test-Policy $false "the Windows image decoder is available ($($_.Exception.Message))"
}

$releaseIdentity = Read-JsonFile "resources/experience/release-identity.json"
if ($null -ne $releaseIdentity) {
    $identityAvailable = $releaseIdentity.available -eq $true
    $identityCodeName = "{0} · {1}" -f `
        ([string]$releaseIdentity.english), ([string]$releaseIdentity.zhHant)
    $identityAsset = [regex]::Escape([string]$releaseIdentity.photoAssetName)
    $identityTag = [regex]::Escape([string]$releaseIdentity.photoTag)
    $validIdentity = ([string]$releaseIdentity.id -match '^hk-dish-[0-9]{4}$') `
        -and ([string]$releaseIdentity.photoAssetName `
            -match '^hk-dish-[0-9]{4}-[a-z0-9-]+\.png$') `
        -and ([string]$releaseIdentity.photoTag `
            -match '^catalog-v1(?:-part-[0-9]{3})?$') `
        -and ([string]$releaseIdentity.photoDigest -match '^sha256:[0-9a-f]{64}$') `
        -and ([string]$releaseIdentity.catalogRevision -match '^[0-9a-f]{40}$') `
        -and ([string]$releaseIdentity.catalogBlobSha -match '^[0-9a-f]{40}$') `
        -and ([string]$releaseIdentity.catalogSourceUrl -eq `
            'https://raw.githubusercontent.com/Ding-Ding-Projects/dim-sum-photos/main/catalog/index.json') `
        -and ([string]$releaseIdentity.codeName -ceq $identityCodeName) `
        -and ([string]$releaseIdentity.photoUrl `
            -match "^https://github\.com/Ding-Ding-Projects/dim-sum-photos/releases/download/$identityTag/$identityAsset$")
    Test-Policy ($releaseIdentity.schemaVersion -eq 1 `
            -and (($identityAvailable -and $validIdentity) `
                -or (-not $identityAvailable `
                    -and -not [string]::IsNullOrWhiteSpace([string]$releaseIdentity.reason)))) `
        "release identity is either a complete public catalog-v1 record or a truthful version-only fallback"
}

foreach ($legacyDimSumPath in @(
    "resources/experience/dim-sum.json",
    "resources/dim-sum/index.json",
    "resources/dim-sum/har-gow.png",
    "resources/dim-sum/siu-mai.png",
    "resources/dim-sum/egg-tart.png"
)) {
    Test-Policy (-not (Test-Path -LiteralPath (Get-RepositoryPath $legacyDimSumPath))) `
        "$legacyDimSumPath is removed in favor of the authoritative public catalog"
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
    Test-Policy ($releaseVersions -contains "build-56-76dae193") `
        "the changelog is current through the transfer-export handoff"

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
$desktopResourcesQrc = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "resources/resources.qrc")
Test-Policy ($sourceCMake -match 'quick/qml/\*\.qml') "CMake discovers every desktop QML surface"
Test-Policy ($sourceCMake -match 'experience/\*\.json') `
    "CMake bundles changelog and release-identity metadata"
Test-Policy ($sourceCMake -notmatch 'dim-sum/\*\.png') `
    "CMake does not bundle private dim-sum photo copies"
Test-Policy ($desktopResourcesQrc.Contains('experience/release-identity.json') `
        -and $desktopResourcesQrc -notmatch 'experience/dim-sum\.json|dim-sum/[^<]+\.png') `
    "the desktop resource manifest ships release identity metadata without a copied catalog or photo"
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
$titleBarQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/MaterialTitleBar.qml")
$themeFacadeQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/theme/Theme.qml")
$themeManagerHeader = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/theme/thememanager.h")
$themeManagerSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/theme/thememanager.cpp")
$quickSettingsQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/SettingsSheet.qml")
$advancedColorPickerQml = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/AdvancedColorPicker.qml")
$filterTextFieldQml = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/FilterTextField.qml")
$sheetQml = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/Sheet.qml")
$regexBuilderSheetQml = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/RegexBuilderSheet.qml")
$componentsQmldir = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/qmldir")
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
Test-Policy ($mainQml.Contains('Qt.FramelessWindowHint') `
        -and $mainQml.Contains('MaterialTitleBar') `
        -and $titleBarQml.Contains('showMinimized()') `
        -and $titleBarQml.Contains('showMaximized()') `
        -and $titleBarQml.Contains('startSystemMove()') `
        -and $themeManagerSource.Contains('put(u"surfaceContainer"_s')) `
    "the Windows app paints a functional Material title bar and window controls"
Test-Policy ($themeManagerHeader.Contains('Q_PROPERTY(int paletteRevision READ paletteRevision NOTIFY themeChanged)') `
        -and $themeManagerSource.Contains('void ThemeManager::notifyThemeChanged()') `
        -and $themeFacadeQml.Contains('readonly property int paletteRevision: ThemeManager.paletteRevision') `
        -and $themeFacadeQml.Contains('const revision = paletteRevision') `
        -and $themeFacadeQml.Contains('return color(_stateName(state))')) `
    "seed, style, override, and scheme changes invalidate every QML palette-role binding"
Test-Policy (-not $quickSettingsQml.Contains('Dialogs.ColorDialog') `
        -and $quickSettingsQml.Contains('AdvancedColorPicker {') `
        -and $quickSettingsQml.Contains('id: seedColorPickerButton') `
        -and $quickSettingsQml.Contains('Accessible.name: qsTr("Open Material seed color picker")') `
        -and $quickSettingsQml.Contains('forceOpaque: true') `
        -and $quickSettingsQml.Contains('seedColorPicker.openFor(') `
        -and $componentsQmldir.Contains('AdvancedColorPicker')) `
    "Quick Settings uses the reusable app-painted advanced seed-color picker"
Test-Policy (-not $quickSettingsQml.Contains('placeholderText: "#6750A4"') `
        -and $quickSettingsQml.Contains('readonly property bool validColor: ThemeManager.isValidColor(text)') `
        -and $quickSettingsQml.Contains('interval: 160') `
        -and $quickSettingsQml.Contains('onTriggered: root.previewSeedColor(root.pendingSeedColor)') `
        -and $quickSettingsQml.Contains('if (validColor)') `
        -and $quickSettingsQml.Contains('root.queueSeedColorPreview(text)')) `
    "valid typed seed colors preview after a short debounce while invalid text remains editable"
Test-Policy ($quickSettingsQml.Contains('columns: width >= 360 ? 2 : 1') `
        -and $quickSettingsQml.Contains('text: qsTr("Open color picker")') `
        -and $quickSettingsQml.Contains('Layout.minimumWidth: seedColorLayout.columns === 1 ? 0 : 148') `
        -and $quickSettingsQml.Contains('wrapMode: Text.WordWrap') `
        -and $quickSettingsQml.Contains('Material seed colors are applied as opaque.')) `
    "the seed-color controls reflow at narrow and bilingual widths and explain output alpha"

$requiredColorSpaces = @(
    "HEX / HEX8", "RGB / RGBA", "HSL / HSLA", "HSV / HSB", "HWB",
    "CIELAB", "LCH", "OKLab", "OKLCH", "CMYK", "Named color"
)
foreach ($colorSpace in $requiredColorSpaces) {
    Test-Policy ($advancedColorPickerQml.Contains('qsTr("' + $colorSpace + '")')) `
        "the advanced picker translates $colorSpace values"
}
Test-Policy ($advancedColorPickerQml.Contains('id: saturationValueField') `
        -and $advancedColorPickerQml.Contains('id: hueSlider') `
        -and $advancedColorPickerQml.Contains('id: alphaSlider') `
        -and $advancedColorPickerQml.Contains('Keys.onPressed: function(event)') `
        -and $advancedColorPickerQml.Contains('Accessible.role: Accessible.Slider')) `
    "the advanced picker offers continuous keyboard-accessible saturation, value, hue, and alpha controls"
Test-Policy ($advancedColorPickerQml.Contains('function formattedColor(index, color)') `
        -and $advancedColorPickerQml.Contains('function parsedFormattedColor(index, value)') `
        -and $advancedColorPickerQml.Contains('ThemeManager.nameForColor(color)') `
        -and $advancedColorPickerQml.Contains('pendingClip = true') `
        -and $advancedColorPickerQml.Contains('function contrastRatio()')) `
    "color translation is bidirectional and reports gamut clipping and applied contrast"
Test-Policy ($advancedColorPickerQml.Contains('readonly property string strictNumberPattern:') `
        -and $advancedColorPickerQml.Contains('function strictNumbers(value, expression, count)') `
        -and $advancedColorPickerQml.Contains('new RegExp(expression, "i")') `
        -and $advancedColorPickerQml.Contains('match.length !== count + 1') `
        -and $advancedColorPickerQml.Contains('!Number.isFinite(number)') `
        -and $advancedColorPickerQml.Contains('"^rgb\\(') `
        -and $advancedColorPickerQml.Contains('"^cmyka\\(') `
        -and -not $advancedColorPickerQml.Contains('function numbersIn(')) `
    "color-space editors reject malformed and extra-token input with anchored exact-arity grammars"
Test-Policy ($advancedColorPickerQml.Contains('return name.length ? name : colorHex8(color)') `
        -and $advancedColorPickerQml.Contains('var fallbackHex = parseHex(namedValue)') `
        -and $advancedColorPickerQml.Contains('if (fallbackHex !== null)') `
        -and -not $advancedColorPickerQml.Contains('qsTr("custom (%1)")')) `
    "named-color formatting falls back to parseable ARGB so unnamed colors round-trip"
Test-Policy ($advancedColorPickerQml.Contains('var white = boundedUnit(values[1] / 100)') `
        -and $advancedColorPickerQml.Contains('var black = boundedUnit(values[2] / 100)') `
        -and $advancedColorPickerQml.Contains('if (sum > 1)') `
        -and $advancedColorPickerQml.Contains('var c = boundedUnit(values[0] / 100)') `
        -and $advancedColorPickerQml.Contains('var k = boundedUnit(values[3] / 100)') `
        -and $advancedColorPickerQml.Contains('if (lchChroma < 0)') `
        -and $advancedColorPickerQml.Contains('if (oklchChroma < 0)') `
        -and $advancedColorPickerQml.Contains('function boundedGamutUnit(value)') `
        -and $advancedColorPickerQml.Contains('if (!pendingClip)')) `
    "negative, out-of-range, stale, and out-of-gamut input requires an explicit current clipping review"
Test-Policy ($advancedColorPickerQml.Contains('clipboardHelper.copy()') `
        -and $advancedColorPickerQml.Contains('GUI/Appearance/RecentSeedColors') `
        -and $advancedColorPickerQml.Contains('customPalette') `
        -and $advancedColorPickerQml.Contains('function outputColor()')) `
    "the advanced picker copies translations, persists recent/custom colors, and enforces its alpha policy"
Test-Policy ($advancedColorPickerQml.Contains('id: pickerPropertySearch') `
        -and $advancedColorPickerQml.Contains('objectName: "advancedColorPickerPropertySearch"') `
        -and $advancedColorPickerQml.Contains('function propertyMatches(corpus)') `
        -and $advancedColorPickerQml.Contains('pickerPropertySearch.regexEnabled') `
        -and $advancedColorPickerQml.Contains('pickerPropertySearch.regexFlags') `
        -and $advancedColorPickerQml.Contains('visible: root.showTranslator') `
        -and $advancedColorPickerQml.Contains('visible: root.showCustomPalette') `
        -and $advancedColorPickerQml.Contains('visible: root.showRecentColors')) `
    "the picker has its own regex-builder-backed property search and filters its controls locally"
Test-Policy ($advancedColorPickerQml.Contains('Accessible.focused: activeFocus') `
        -and $advancedColorPickerQml.Contains('"Saturation %1 percent, value %2 percent.') `
        -and $advancedColorPickerQml.Contains('"Saturation %1% · value %2%"') `
        -and $advancedColorPickerQml.Contains('Qt.Key_Left') `
        -and $advancedColorPickerQml.Contains('Qt.Key_Right') `
        -and $advancedColorPickerQml.Contains('Qt.Key_Up') `
        -and $advancedColorPickerQml.Contains('Qt.Key_Down') `
        -and $advancedColorPickerQml.Contains('event.modifiers & Qt.ShiftModifier')) `
    "the two-dimensional color field exposes numeric saturation/value and keyboard-equivalent focus behavior"
Test-Policy ($filterTextFieldQml.Contains('property string snapshotPattern:') `
        -and $filterTextFieldQml.Contains('property string snapshotFlags:') `
        -and $filterTextFieldQml.Contains('property string draftFlags:') `
        -and $filterTextFieldQml.Contains('builderPopup.snapshotPattern = root.text') `
        -and $filterTextFieldQml.Contains('builderPopup.snapshotFlags = root.regexFlags') `
        -and $filterTextFieldQml.Contains('checked: builderPopup.draftFlags.indexOf(') `
        -and $filterTextFieldQml.Contains('onToggled: builderPopup.setDraftFlag(')) `
    "anchored regex builders stage a snapshot of both pattern and flags"
Test-Policy ($filterTextFieldQml.Contains('closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside') `
        -and $filterTextFieldQml.Contains('onClosed: {') `
        -and $filterTextFieldQml.Contains('if (!appliedThisOpen)') `
        -and $filterTextFieldQml.Contains('restoreSnapshot()') `
        -and $filterTextFieldQml.Contains('root.text = snapshotPattern') `
        -and $filterTextFieldQml.Contains('root.regexFlags = snapshotFlags') `
        -and $filterTextFieldQml.Contains('onClicked: builderPopup.close()')) `
    "Escape, outside press, and Close restore both regex pattern and flags"
Test-Policy ($filterTextFieldQml.Contains('var appliedPattern = builderPattern.text') `
        -and $filterTextFieldQml.Contains('var appliedFlags = root.canonicalFlags(builderPopup.draftFlags)') `
        -and $filterTextFieldQml.Contains('builderPopup.appliedThisOpen = true') `
        -and $filterTextFieldQml.Contains('root.text = appliedPattern') `
        -and $filterTextFieldQml.Contains('root.regexFlags = appliedFlags') `
        -and $filterTextFieldQml.Contains('root.regexApplied(appliedPattern, appliedFlags)')) `
    "Apply atomically commits the staged regex pattern and flags"
Test-Policy ($advancedColorPickerQml.Contains('parent: Overlay.overlay') `
        -and $advancedColorPickerQml.Contains('horizontalViewportMargin') `
        -and $advancedColorPickerQml.Contains('verticalViewportMargin') `
        -and $advancedColorPickerQml.Contains('ScrollBar.horizontal.policy: ScrollBar.AlwaysOff') `
        -and $advancedColorPickerQml.Contains('DragHandler {') `
        -and $advancedColorPickerQml.Contains('focusTarget.forceActiveFocus')) `
    "the picker paints a bounded scrollable draggable overlay and restores focus"
Test-Policy ($sheetQml.Contains('Math.max(0, parent.width - anchors.rightMargin * 2)') `
        -and $sheetQml.Contains('ThemeManager.reducedMotion ? 0 : 240') `
        -and $sheetQml.Contains('ThemeManager.reducedMotion ? 0 : 200') `
        -and $regexBuilderSheetQml.Contains('id: builderScroll') `
        -and $regexBuilderSheetQml.Contains('width: Math.max(0, builderScroll.availableWidth)') `
        -and $regexBuilderSheetQml.Contains('ScrollBar.horizontal.policy: ScrollBar.AlwaysOff')) `
    "sheets stay within narrow viewports, scroll internally, and respect reduced motion"
foreach ($namedSheet in @("SettingsSheet.qml", "HistorySheet.qml", "RegexBuilderSheet.qml")) {
    $namedSheetSource = Get-Content -Raw -LiteralPath `
        (Get-RepositoryPath "src/quick/qml/shell/$namedSheet")
    Test-Policy ($namedSheetSource.Contains('accessibleName: qsTr(')) `
        "$namedSheet exposes a named accessible pane"
}
Test-Policy ($themeManagerHeader.Contains('Q_INVOKABLE bool isValidColor(const QString &value) const') `
        -and $themeManagerHeader.Contains('Q_INVOKABLE QColor parseColorValue(const QString &value) const') `
        -and $themeManagerHeader.Contains('Q_INVOKABLE QString nameForColor(const QColor &value) const') `
        -and $themeManagerSource.Contains('normalized.setAlpha(255)')) `
    "the theme boundary validates/translates names and normalizes Material seeds to opaque"

$guiAddManager = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/guiaddtorrentmanager.h")
$addTorrentDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/addtorrent/AddNewTorrentDialog.qml")

# A QML fault compiles perfectly and then aborts the application at startup, so
# nothing static can catch it. Duplicate ids across a single QML file are the
# cheap half of that check; the behavioural half runs the real binary below.
$duplicateQmlIds = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath (Get-RepositoryPath "src/quick/qml") -Filter "*.qml" -File -Recurse |
    ForEach-Object {
        $inDocComment = $false
        $ids = [System.Collections.Generic.List[string]]::new()
        foreach ($line in (Get-Content -LiteralPath $_.FullName)) {
            # Ignore the \qml examples inside documentation comments.
            if ($line -match '^\s*/\*!') { $inDocComment = $true }
            if ($inDocComment) {
                if ($line -match '\*/') { $inDocComment = $false }
                continue
            }
            if ($line -match '^\s*id:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$') {
                $ids.Add($Matches[1])
            }
        }
        foreach ($duplicate in ($ids | Group-Object | Where-Object { $_.Count -gt 1 })) {
            $duplicateQmlIds.Add("$($_.Name):$($duplicate.Name)")
        }
    }
Test-Policy ($duplicateQmlIds.Count -eq 0) `
    "no QML file declares the same id twice$($duplicateQmlIds -join ', ')"

$qmlStartupTest = Get-RepositoryPath "scripts/test-qml-startup.ps1"
Test-Policy (Test-Path -LiteralPath $qmlStartupTest -PathType Leaf) `
    "the built application has a QML startup regression test"
$qmlStartupSource = if (Test-Path -LiteralPath $qmlStartupTest -PathType Leaf) {
    Get-Content -Raw -LiteralPath $qmlStartupTest
}
else { "" }
Test-Policy ($qmlStartupSource.Contains('$ready') `
        -and $qmlStartupSource.Contains('startup readiness marker')) `
    "the QML startup smoke test requires a real readiness marker"
if ($SkipRuntimeStartup) {
    Write-Host "[SKIP] Runtime QML startup is deferred until after the build."
}
elseif (Test-Path -LiteralPath $qmlStartupTest -PathType Leaf) {
    try {
        & $qmlStartupTest -RepositoryRoot $RepositoryRoot | ForEach-Object { Write-Host $_ }
        Test-Policy $true "the QML root object loads without a runtime fault"
    }
    catch {
        Test-Policy $false `
            "the QML root object loads without a runtime fault ($($_.Exception.Message))"
    }
}

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
Test-Policy ($narratorSource.Contains('QProcess::errorOccurred') `
        -and $narratorSource.Contains('QMediaPlayer::errorOccurred') `
        -and $narratorSource.Contains('setSpeaking(false)') `
        -and $narratorSource.Contains('qBound<qreal>')) `
    "narrator playback errors release the queue and clamp restored volume"
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
$appHeaderSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/AppHeader.qml")
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
Test-Policy ($transfersPageSource.Contains('readonly property int tableContentWidth') `
        -and $transfersPageSource.Contains('flickableDirection: Flickable.HorizontalFlick') `
        -and $transfersPageSource.Contains('ScrollBar.horizontal: ScrollBar') `
        -and $transfersPageSource.Contains('anchors.centerIn: parent') `
        -and $transfersPageSource.Contains('No torrents match the current filter')) `
    "the transfer table exposes every fixed column through an explicit horizontal surface and keeps its empty state centred"
Test-Policy ($appHeaderSource.Contains('readonly property bool compactSplitDock') `
        -and $appHeaderSource.Contains('visible: Theme.isSplitDock && !root.compactSplitDock') `
        -and $appHeaderSource.Contains('SearchableMenu {') `
        -and $appHeaderSource.Contains('searchPlaceholder: qsTr("Search destinations")')) `
    "Split Dock collapses its destination strip before compact header controls can clip"

# A PATH lookup misses every VS Code installed without "add to PATH" — the
# default for the user-scope installer — and misses Insiders entirely.
$desktopIntegration = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/app/desktopintegration.cpp")
Test-Policy ($desktopIntegration.Contains('QString DesktopIntegration::findWellKnownEditor') `
        -and $desktopIntegration.Contains('Programs\Microsoft VS Code\Code.exe') `
        -and $desktopIntegration.Contains('Microsoft VS Code\Code.exe') `
        -and $desktopIntegration.Contains('Code - Insiders.exe') `
        -and $desktopIntegration.Contains('qEnvironmentVariable("ProgramFiles")') `
        -and $desktopIntegration.Contains('qEnvironmentVariable("ProgramFiles(x86)")') `
        -and $desktopIntegration.Contains('qEnvironmentVariable("ProgramW6432")') `
        -and -not $desktopIntegration.Contains('writableLocation(QStandardPaths::AppLocalDataLocation),')) `
    "editor detection looks where VS Code actually installs, not only on PATH"
$squirrelLifecycle = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/app/squirrellifecycle.cpp")
$squirrelVersionResource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "resources/branding/qbittorrent-material.rc.in")
$rootCMakeForVersionResource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "CMakeLists.txt")
$appCMakeForVersionResource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/CMakeLists.txt")
$desktopMain = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/main.cpp")
Test-Policy ($squirrelVersionResource.Contains('BLOCK "040904b0"') `
        -and $squirrelVersionResource.Contains('@QBT_PACKAGE_VERSION_RC_NUMERIC@') `
        -and $squirrelVersionResource.Contains('@QBT_PACKAGE_VERSION_RC_STRING@') `
        -and $rootCMakeForVersionResource.Contains('QBT_PACKAGE_VERSION_RC_NUMERIC') `
        -and $rootCMakeForVersionResource.Contains('QBT_PACKAGE_VERSION_RC_STRING') `
        -and $rootCMakeForVersionResource.Contains('configure_file(') `
        -and $rootCMakeForVersionResource.Contains('qbittorrent-material.rc.in') `
        -and $rootCMakeForVersionResource.Contains('QBT_WINDOWS_VERSION_RESOURCE') `
        -and $appCMakeForVersionResource.Contains('"${QBT_WINDOWS_VERSION_RESOURCE}"') `
        -and $appCMakeForVersionResource.Contains('QBT_PACKAGE_VERSION=') `
        -and $squirrelVersionResource.Contains('VALUE "SquirrelAwareVersion", "1\0"') `
        -and $desktopMain.Contains('SquirrelLifecycle::handle(QCoreApplication::arguments())') `
        -and $squirrelLifecycle.Contains('event == u"--squirrel-install"_s') `
        -and $squirrelLifecycle.Contains('event == u"--squirrel-updated"_s') `
        -and $squirrelLifecycle.Contains('event == u"--squirrel-uninstall"_s') `
        -and $squirrelLifecycle.Contains('u"--createShortcut=qbittorrent.exe"_s') `
        -and $squirrelLifecycle.Contains('u"--removeShortcut=qbittorrent.exe"_s')) `
    "the generated package-version resource enables native Squirrel lifecycle hooks and keeps Explorer metadata aligned with the update feed"
Test-Policy ($squirrelLifecycle.Contains('Software\\qBittorrentMaterial\\AssociationBackup') `
        -and $squirrelLifecycle.Contains('captureAssociations()') `
        -and $squirrelLifecycle.Contains('commandBelongsTo(torrentCommand, expectedCommand)') `
        -and $squirrelLifecycle.Contains('commandBelongsTo(magnetCommand, expectedCommand)') `
        -and $squirrelLifecycle.Contains('restoreValue(torrentBackup') `
        -and $squirrelLifecycle.Contains('restoreValue(magnetBackup') `
        -and $squirrelLifecycle.Contains('backupName + u"Type"_s') `
        -and $squirrelLifecycle.Contains('RegQueryInfoKeyW') `
        -and $squirrelLifecycle.Contains('writeDword(torrentBackup, u"ExtensionKeyPresent"_s') `
        -and $squirrelLifecycle.Contains('writeDword(magnetBackup, u"RootKeyPresent"_s') `
        -and $squirrelLifecycle.Contains('restoreKeyPresence(torrentBackup') `
        -and $squirrelLifecycle.Contains('restoreKeyPresence(magnetBackup') `
        -and $squirrelLifecycle.Contains('value_or(1) == 1') `
        -and -not $squirrelLifecycle.Contains('deleteKeyIfEmpty(HKEY_CURRENT_USER, classes + u".torrent"_s)') `
        -and -not $squirrelLifecycle.Contains('deleteKeyIfEmpty(HKEY_CURRENT_USER, classes + u"magnet"_s)') `
        -and $squirrelLifecycle.Contains('SHChangeNotify(SHCNE_ASSOCCHANGED') `
        -and $squirrelLifecycle -notmatch 'HKEY_CLASSES_ROOT' `
        -and $squirrelLifecycle.Contains('installRoot.absoluteFilePath(u"qbittorrent.exe"_s)')) `
    "Squirrel snapshots exact per-user .torrent/magnet handlers and top-level key presence, restoring them only while the stable stub is still owned"
$torrentImplSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/torrentimpl.cpp")
Test-Policy ($torrentImplSource.Contains('Path logicalPath = m_filePaths.at(index)') `
        -and $torrentImplSource.Contains('doRenameFile(index, logicalPath)') `
        -and $torrentImplSource.Contains('applies the') `
        -and $torrentImplSource -notmatch 'doRenameFile\(index, desiredPath\)') `
    "incomplete-file maintenance applies the on-disk path transform exactly once"
$sessionSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/sessionimpl.cpp")
$resumeStorageSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/bittorrent/resumedatastorage.cpp")
Test-Policy ($sessionSource.Contains('m_startupQueueOrder = m_resumeDataStorage') `
        -and $sessionSource.Contains('applyStartupQueue()') `
        -and $sessionSource.Contains('nativeHandle().queue_position()') `
        -and $sessionSource -match '\+\+m_pendingStartupRestores;\s*\r?\n\s*m_nativeSession->async_add_torrent\(p\);' `
        -and $resumeStorageSource.Contains('bool ResumeDataStorage::storeQueue') `
        -and $resumeStorageSource.Contains('QList<TorrentID> ResumeDataStorage::loadQueue')) `
    "torrent queue order is stored explicitly and reapplied after asynchronous restore"
Test-Policy ($torrentImplSource.Contains('m_commentIsCustom {params.commentIsCustom}') `
        -and $torrentImplSource.Contains('data.commentIsCustom = m_commentIsCustom') `
        -and $resumeStorageSource.Contains('commentIsCustom')) `
    "a user-cleared torrent comment remains distinct from immutable metadata"
Test-Policy ($torrentImplSource.Contains('m_renamingFiles[nativeIndex]') `
        -and $torrentImplSource.Contains('m_renamingFiles.find(nativeFileIndex)') `
        -and $torrentImplSource.Contains('folder.pendingFileIndexes')) `
    "rename acknowledgements correlate by native file index and complete folder jobs atomically"
$rssParserSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/rss/rss_parser.cpp")
Test-Policy ($rssParserSource.Contains('bool isTorrentMimeType') `
        -and $rssParserSource.Contains('resolveFeedUrl(m_baseUrl') `
        -and $rssParserSource.Contains('article[Article::KeyTorrentURL] = resolveFeedUrl') `
        -and $rssParserSource -notmatch 'KeyTorrentURL\].*= article\.value\(Article::KeyLink\)' `
        -and $rssParserSource.Contains('m_baseUrl = m_feedUrl')) `
    "RSS parsing distinguishes article links from torrent enclosures and resolves relative URLs"
$foreignAppsSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/utils/foreignapps.cpp")
Test-Policy ($foreignAppsSource.Contains('cache.automaticProbeComplete') `
        -and $foreignAppsSource.Contains('cachedAutomaticPath.isAbsolute()') `
        -and $foreignAppsSource.Contains('cachedAutomaticPath.exists()') `
        -and $foreignAppsSource.Contains('cache.automaticInfo = {};') `
        -and $foreignAppsSource.Contains('cache.automaticProbeComplete = false;')) `
    "Python auto-detection avoids repeated PATH probes yet invalidates a removed concrete interpreter"
# An export the user cannot open is an export they have to hunt for on disk.
$workspaceViewSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/workspace/WorkspaceView.qml")
Test-Policy ($mainQml.Contains('actionId.startsWith("open-export:")') `
        -and $mainQml.Contains('DesktopIntegration.openInExternalEditor(target)') `
        -and $workspaceViewSource.Contains('"open-export:" + target')) `
    "an export offers to open itself in the configured editor"
Test-Policy ($workspaceViewSource.Contains('"open-workspace-location:" + target') `
        -and $mainQml.Contains('actionId.startsWith("open-workspace-location:")') `
        -and $mainQml.Contains('target.startsWith("file:")')) `
    "workspace notification actions are durable and handled by the single main snackbar host"

# Local search surfaces reach the anchored regex builder rather than owning a
# hand-rolled ".*" toggle that cannot build a pattern.
$historyModelSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/journalhistorymodel.cpp")
$historySheet = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/HistorySheet.qml")
Test-Policy ($historySheet.Contains('FilterTextField {') `
        -and $historySheet.Contains('readonly property bool histRegex: searchField.regexEnabled') `
        -and $historyModelSource.Contains('m_filterValid = false;') `
        -and $historyModelSource.Contains('Invalid regular expression at offset') `
        -and -not ($historySheet -match 'text:\s*"\.\*"')) `
    "the history panel searches through the shared field and its anchored builder"
$searchTab = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/search/SearchTab.qml")
Test-Policy ($searchTab.Contains('builderTitle: qsTr("Site search Regex Builder")') `
        -and $searchTab.Contains('Plain-text site query by default; the adjacent Regex Builder') `
        -and $searchTab.Contains('onRegexApplied:') `
        -and $searchTab.Contains('searchField.patternValid') `
        -and $searchTab.Contains('searchField.regexFlags')) `
    "the Search tab keeps plain text as the default and wires validated regex flags into the search"
$searchResultsModel = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/models/searchresultsmodel.h")
$searchResultsTab = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/search/SearchResultsTab.qml")
Test-Policy ($searchResultsModel.Contains('Q_PROPERTY(QString regexFlags') `
        -and $searchResultsModel.Contains('patternOptions(regexFlags)') `
        -and $searchResultsModel.Contains('if (!m_textRegex.isValid())') `
        -and $searchResultsTab.Contains('regexFlags: root.proxyModel')) `
    "search-result regex filters honor their flags and reject invalid patterns"

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
Test-Policy ($superConfirm.Contains('property bool terminalHandled: false') `
        -and $superConfirm.Contains('property bool authorizationPending: false') `
        -and $superConfirm.Contains('finishTimer.stop()') `
        -and $superConfirm.Contains('onClosed: root._cancel()') `
        -and $superConfirm.Contains('if (terminalHandled || !authorizationPending || !completion.done)') `
        -and $superConfirm -notmatch 'onClicked:\s*root\.reject\(\)') `
    "the destructive gate cancels delayed authorization on every dismissal and emits one terminal outcome"
Test-Policy ($superConfirm.Contains('readonly property real viewportBoundHeight: Math.max(0,') `
        -and $superConfirm.Contains('height: Math.min(implicitHeight, viewportBoundHeight)') `
        -and $superConfirm.Contains('contentItem: ScrollView {') `
        -and $superConfirm.Contains('id: confirmationScroll') `
        -and $superConfirm.Contains('contentHeight: confirmationBody.implicitHeight') `
        -and $superConfirm.Contains('ScrollBar.horizontal.policy: ScrollBar.AlwaysOff') `
        -and $superConfirm.Contains('ScrollBar.vertical.policy: ScrollBar.AsNeeded') `
        -and $superConfirm.Contains('Accessible.name: qsTr("Destructive action confirmation details")') `
        -and $superConfirm.Contains('footer: DialogButtonBox {') `
        -and $superConfirm.Contains('id: emergencyExit')) `
    "the destructive gate bounds its card and scrolls its body while Emergency exit stays reachable"
Test-Policy ($superConfirm.Contains('ThemeManager.reducedMotion === true') `
        -and $superConfirm.Contains('enabled: !root.reducedMotion')) `
    "the destructive gate honors reduced motion instead of playing its animations"
Test-Policy ($superConfirm.Contains('qsTr("This cannot be undone.")') `
        -and $superConfirm.Contains('root.actionText') `
        -and $superConfirm.Contains('qsTr("This affects: %1").arg(root.affectedText)')) `
    "the destructive gate states the exact action and what it affects"
$confirmDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/ConfirmDialog.qml")
$textInputDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/TextInputDialog.qml")
$lockPasswordDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/mainwindow/LockPasswordDialog.qml")
Test-Policy ($confirmDialog.Contains('rememberCheck.checked = false') `
        -and $confirmDialog.IndexOf('rememberCheck.checked = false') -lt $confirmDialog.IndexOf('if (rememberKey.length') `
        -and $confirmDialog -notmatch 'onClicked:\s*root\.(accept|reject)\(\)') `
    "confirmation opt-ins reset per attempt and footer roles cannot double-fire acceptance or rejection"
Test-Policy ($textInputDialog.Contains('property bool terminalHandled: false') `
        -and $textInputDialog.Contains('onClosed: {') `
        -and $textInputDialog.Contains('root.rejected()') `
        -and $textInputDialog.Contains('Accessible.name: root.label.length > 0') `
        -and $lockPasswordDialog.Contains('property bool terminalHandled: false') `
        -and $lockPasswordDialog.Contains('onClosed: {') `
        -and $lockPasswordDialog.Contains('root.rejected()')) `
    "Popup prompt Escape and dismissal paths reject exactly once and expose named text fields"
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
$transferController = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/transfercontroller.cpp")
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
Test-Policy ($transferController.Contains('Session *const session = BitTorrent::Session::instance()') `
        -and $transferController.Contains('Cannot remove tracker host without a torrent session')) `
    "tracker removal fails safely when the session is unavailable"
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

$notificationHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/notificationcontroller.h")
$notificationSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/notificationcontroller.cpp")
$notificationSheetSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/NotificationsSheet.qml")
$notificationSheetFrame = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/Sheet.qml")
$notificationAppHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/AppHeader.qml")
$snackbarSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/Snackbar.qml")
$iconButtonSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/IconButton.qml")
$notificationRegressionSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "test/testnotificationcontroller.cpp")
$rootCMakeForNotifications = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "CMakeLists.txt")
$appCMakeForNotifications = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/CMakeLists.txt")
$primarySnackbarHosts = @(
    Get-ChildItem -LiteralPath (Get-RepositoryPath "src/quick/qml") -Recurse -Filter "*.qml" |
        Select-String -Pattern 'primaryHost\s*:\s*true' -CaseSensitive
)
Test-Policy ($notificationHeader.Contains('Q_PROPERTY(int activeCount READ activeCount NOTIFY activeCountChanged)') `
        -and $notificationHeader.Contains('Q_INVOKABLE void dismissAll()') `
        -and $notificationSource.Contains('void NotificationController::dismissAll()') `
        -and $notificationSource.Contains('entry.dismissed = true;') `
        -and $notificationSource.Contains('emit allDismissed();')) `
    "bulk notification dismissal marks active entries dismissed without deleting history"
Test-Policy ($notificationSheetSource.Contains('qsTr("Dismiss all (%1)").arg(NotificationCenter.activeCount)') `
        -and $notificationSheetSource.Contains('Accessible.name: qsTr("Dismiss all %1 active notifications")') `
        -and $notificationSheetSource.Contains('onClicked: NotificationCenter.dismissAll()')) `
    "the notification centre exposes a keyboard-accessible dismiss-all action with the exact active count"
Test-Policy ($notificationSheetSource -match '(?m)^Sheet\s*\{' `
        -and $notificationSheetSource -notmatch 'x:\s*open\s*\?\s*0\s*:\s*width' `
        -and $notificationSheetFrame.Contains('enabled: open') `
        -and $notificationSheetFrame.Contains('transform: Translate') `
        -and $notificationSheetSource.Contains('I18n.language === I18n.Bilingual') `
        -and ([regex]::Matches($notificationSheetSource, 'GridLayout\s*\{')).Count -ge 2) `
    "the notification centre uses the bounded sheet motion and adapts controls for narrow bilingual layouts"
Test-Policy ($notificationSheetSource.Contains('const modelState = [NotificationCenter.count,') `
        -and $notificationSheetSource.Contains('required property bool dismissed') `
        -and $notificationSheetSource.Contains('activeFocusOnTab: included') `
        -and $notificationSheetSource.Contains('Accessible.description: readLabel + ". " + presentationLabel') `
        -and $notificationSheetSource.Contains('Keys.onDeletePressed:') `
        -and $notificationAppHeader.Contains('Accessible.checked: active') `
        -and $notificationAppHeader.Contains('qsTr("%1 unread · %2 total")')) `
    "notification search state, cards, dismiss controls, and the header expose reactive keyboard and assistive state"
Test-Policy ($notificationSheetSource.Contains('Clear history is unavailable until notification records can be restored from append-only local history.') `
        -and $notificationSheetSource -notmatch 'onClicked:\s*NotificationCenter\.clearAll\(\)' `
        -and $notificationSource.Contains('entry.actionId.startsWith(u"journal-undo:"_s)') `
        -and $notificationSource.Contains('if (oneShot && entry.dismissed)') `
        -and $notificationSource.Contains('entry.actionId.clear();')) `
    "history clearing is disabled without append-only restoration and one-shot undo actions cannot replay"
Test-Policy ($transfersPageSource.Contains('qsTr("Torrent file(s) exported."), "success"') `
        -and $transfersPageSource.Contains('qsTr("Could not export the selected torrent file(s)."), "error"') `
        -and $addTorrentDialog.Contains('qsTr("Torrent file exported."), "success"') `
        -and $addTorrentDialog.Contains('qsTr("Could not export the torrent file."), "error"') `
        -and ([regex]::Matches($workspaceViewSource, 'NotificationCenter\.notify\(')).Count -eq 1 `
        -and $workspaceViewSource -notmatch 'workspaceSnackbar') `
    "export outcomes keep truthful severity and each Workspace operation publishes one actionable notification"
Test-Policy ($snackbarSource.Contains('function onAllDismissed()') `
        -and $snackbarSource.Contains('function onNotificationDismissed(id)') `
        -and $snackbarSource.Contains('activeModel.clear()') `
        -and $snackbarSource.Contains('property bool primaryHost: false') `
        -and $snackbarSource.Contains('target: root.primaryHost ? NotificationCenter : null') `
        -and $snackbarSource -notmatch '_callbacks' `
        -and $snackbarSource.Contains('actionId === undefined ? "" : String(actionId)') `
        -and $notificationSource.Contains('kMaximumActionIdLength = 4096') `
        -and $primarySnackbarHosts.Count -eq 1 `
        -and $primarySnackbarHosts[0].Path -eq (Get-RepositoryPath "src/quick/qml/Main.qml") `
        -and $snackbarSource.Contains('qsTr("Dismiss all (%1)").arg(NotificationCenter.activeCount)') `
        -and $notificationHeader.Contains('void notificationDismissed(const QString &id)') `
        -and $notificationSource.Contains('emit notificationDismissed(id);') `
        -and $snackbarSource.Contains('onClicked: NotificationCenter.dismissAll()')) `
    "one primary snackbar host exposes truthful bulk dismissal and removes cards from every dismissal route"

$mainSnackbarSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/Main.qml")
Test-Policy (($mainSnackbarSource -match '(?s)Snackbar\s*\{\s*id:\s*snackbar[\s\S]{0,300}parent:\s*Overlay\.overlay') `
        -and ($snackbarSource -match '(?m)^\s*z:\s*-1\s*$')) `
    "the primary Snackbar shares the overlay stack but remains beneath modal dialogs"

$snackbarDismissAllIndex = $snackbarSource.IndexOf('id: dismissAllButton')
$snackbarScrollIndex = $snackbarSource.IndexOf('id: notificationScroll')
Test-Policy ($snackbarSource.Contains('id: snackbarViewport') `
        -and $snackbarSource -match 'anchors\.right:\s*parent\.right' `
        -and $snackbarSource -match 'anchors\.bottom:\s*parent\.bottom' `
        -and $snackbarSource -match 'width:\s*Math\.max\(0,\s*Math\.min\(480,' `
        -and $snackbarSource -match 'height:\s*Math\.max\(0,\s*Math\.min\(maximumHeight,' `
        -and $snackbarSource -notmatch 'Math\.max\(280' `
        -and $snackbarSource -notmatch 'maximumVisible') `
    "the Snackbar remains bottom-right and clamps both dimensions to narrow and high-scale viewports"
Test-Policy (([regex]::Matches($snackbarSource, 'ScrollView\s*\{')).Count -eq 1 `
        -and $snackbarDismissAllIndex -ge 0 `
        -and $snackbarScrollIndex -gt $snackbarDismissAllIndex `
        -and $snackbarSource.Contains('Layout.minimumHeight: 0') `
        -and $snackbarSource.Contains('contentWidth: availableWidth') `
        -and $snackbarSource.Contains('ScrollBar.horizontal.policy: ScrollBar.AlwaysOff') `
        -and $snackbarSource -match 'ScrollBar\.vertical:\s*ScrollBar\s*\{' `
        -and $snackbarSource.Contains('policy: ScrollBar.AsNeeded') `
        -and $snackbarSource.Contains('width: Math.max(0, notificationScroll.availableWidth)')) `
    "Dismiss all stays pinned outside the internally scrolling notification cards"
Test-Policy ($notificationHeader.Contains('Q_INVOKABLE QVariantList activeEntries() const') `
        -and $notificationSource.Contains('QVariantList NotificationController::activeEntries() const') `
        -and $notificationSource.Contains('m_entries.crbegin()') `
        -and $notificationSource.Contains('if (entry.dismissed)') `
        -and $snackbarSource.Contains('NotificationCenter.activeEntries()') `
        -and $snackbarSource.Contains('Component.onCompleted: hydrateActiveNotifications()') `
        -and $snackbarSource.Contains('activeModel.get(i).notificationId === id') `
        -and $snackbarSource.Contains('id: notificationAction') `
        -and $snackbarSource.Contains('id: notificationDismiss') `
        -and $snackbarSource.Contains('running: !card.persistent') `
        -and $snackbarSource.Contains('&& !snackbarViewport.keyboardInteractionActive') `
        -and $snackbarSource.Contains('&& !card.keyboardInteractionActive')) `
    "the primary Snackbar hydrates persisted cards without duplicates and pauses transient expiry while keyboard actions are focused"
Test-Policy ($snackbarSource -match 'IconButton\s*\{' `
        -and $snackbarSource.Contains('symbol: Icons.close') `
        -and $snackbarSource -notmatch 'icon\.name:\s*"close"' `
        -and ([regex]::Matches($snackbarSource, 'focusPolicy:\s*Qt\.StrongFocus')).Count -ge 3 `
        -and $snackbarSource.Contains('Accessible.role: Accessible.List') `
        -and $snackbarSource.Contains('Accessible.role: Accessible.AlertMessage') `
        -and $iconButtonSource.Contains('Accessible.name: root.tooltip.length > 0 ? root.tooltip : qsTr("Icon action")')) `
    "Snackbar dismissal and action controls use bundled icons and remain keyboard and screen-reader accessible"
Test-Policy ($notificationSource.Contains('entry.actionId.startsWith(u"journal-undo:"_s)') `
        -and $notificationSource.Contains('if (oneShot && entry.dismissed)') `
        -and $notificationSource.Contains('entry.actionLabel.clear()') `
        -and $notificationSource.Contains('entry.actionId.clear()') `
        -and $notificationSource.Contains('{ActionLabelRole, ActionIdRole}') `
        -and $notificationSource.Contains('emit actionRequested(actionId, id)')) `
    "journal undo notification actions are consumed once while file-opening actions stay repeatable"
Test-Policy ($notificationSource.Contains('constexpr int kMaximumEntries = 200') `
        -and $notificationSource.Contains('QVector<QString> evictedActiveIds') `
        -and $notificationSource.Contains('for (int row = kMaximumEntries; row < m_entries.size(); ++row)') `
        -and $notificationSource.Contains('emit notificationDismissed(evictedId);') `
        -and $notificationSource.IndexOf('emit notificationDismissed(evictedId);') -lt `
             $notificationSource.IndexOf('emit notificationRaised(entry.id')) `
    "active notification eviction removes the stale Snackbar id before announcing entry 201"
Test-Policy ($notificationRegressionSource.Contains('QCoreApplication application(argc, argv)') `
        -and $notificationRegressionSource.Contains('number <= 201') `
        -and $notificationRegressionSource.Contains('controller->count() == 200') `
        -and $notificationRegressionSource.Contains('dismissedIds.constFirst() == ids.constFirst()') `
        -and $notificationRegressionSource.Contains('controller->activateAction(actionNotificationId)') `
        -and $notificationRegressionSource.Contains('controller->dismiss(actionNotificationId)') `
        -and $notificationRegressionSource.Contains('controller->dismissAll()') `
        -and $notificationRegressionSource.Contains('controller->activeEntries().isEmpty()')) `
    "the opt-in non-GUI regression covers 201 persistent entries, eviction, action consumption, individual dismissal, and dismiss-all"
Test-Policy ($rootCMakeForNotifications.Contains('option(QBT_BUILD_NOTIFICATION_TESTS') `
        -and $rootCMakeForNotifications -match 'QBT_BUILD_NOTIFICATION_TESTS[\s\S]*?OFF\)' `
        -and $appCMakeForNotifications.Contains('testnotificationcontroller EXCLUDE_FROM_ALL') `
        -and $appCMakeForNotifications.Contains('QBT_NOTIFICATION_TEST_NO_PREFERENCES') `
        -and $appCMakeForNotifications.Contains('add_test(NAME testnotificationcontroller COMMAND testnotificationcontroller)') `
        -and $notificationSource.Contains('#if !defined(QBT_NOTIFICATION_TEST_NO_PREFERENCES)')) `
    "the notification regression is opt-in, excluded from release builds, registered with CTest, and cannot write user preferences"

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
$statusFilterPanel = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/StatusFilterPanel.qml")
Test-Policy ($statusFilterPanel.Contains('Accessible.role: Accessible.RadioButton') `
        -and $statusFilterPanel.Contains('Accessible.name: rowItem.model.label') `
        -and $statusFilterPanel.Contains('Accessible.description: qsTr("%1 torrents")') `
        -and $statusFilterPanel.Contains('Accessible.checked: rowItem.selected')) `
    "status filters expose their labels, counts, and checked radio state"
Test-Policy (([regex]::Matches($statusFilterPanel, 'activeFocusOnTab:')).Count -eq 1 `
        -and $statusFilterPanel.Contains('activeFocusOnTab: rowItem.index === root.rovingIndex') `
        -and $statusFilterPanel.Contains('id: statusRepeater') `
        -and $statusFilterPanel.Contains('statusRepeater.itemAt(') `
        -and $statusFilterPanel.Contains('function onModelReset()') `
        -and $statusFilterPanel.Contains('function onStatusFilterChanged()')) `
    "status filters expose one roving Tab stop synchronized through model resets"
Test-Policy ($statusFilterPanel.Contains('Qt.Key_Up') `
        -and $statusFilterPanel.Contains('Qt.Key_Left') `
        -and $statusFilterPanel.Contains('Qt.Key_Down') `
        -and $statusFilterPanel.Contains('Qt.Key_Right') `
        -and $statusFilterPanel.Contains('Qt.Key_Space') `
        -and $statusFilterPanel.Contains('Qt.Key_Return') `
        -and $statusFilterPanel.Contains('Qt.Key_Enter') `
        -and $statusFilterPanel.Contains('root.moveSelection(') `
        -and $statusFilterPanel.Contains('event.accepted = true')) `
    "status-filter arrows move and select while Space and Enter activate the focused radio"
Test-Policy ($statusFilterPanel.Contains('border.width: rowItem.activeFocus ? 2 : 0') `
        -and $statusFilterPanel.Contains('border.color: Theme.color("focusRing")') `
        -and $statusFilterPanel.Contains('onActiveFocusChanged:')) `
    "status filters paint a visible active-focus ring"
$statusClickHandlers = [regex]::Matches($statusFilterPanel, 'onClicked:').Count
$statusRightClick = [regex]::Match($statusFilterPanel,
    'if \(mouse\.button === Qt\.RightButton\) \{(?<body>[\s\S]*?)\n\s*\}')
Test-Policy ($statusClickHandlers -eq 1 `
        -and $statusRightClick.Success `
        -and $statusRightClick.Groups['body'].Value.Contains('contextMenu.popup()') `
        -and -not $statusRightClick.Groups['body'].Value.Contains('statusFilter =') `
        -and -not $statusRightClick.Groups['body'].Value.Contains('activateIndex')) `
    "right-click opens the status menu without changing the selected radio"

$experienceController = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/controllers/experiencecontroller.cpp")
$experienceHeader = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/controllers/experiencecontroller.h")
$dimSumSurface = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/DimSumSurprise.qml")
$settingsSheet = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/SettingsSheet.qml")
Test-Policy ($experienceController -match 'bounded\(10\)\s*!=\s*0') `
    "startup dim-sum surprise uses one fresh 10 percent draw"
Test-Policy ($experienceController.Contains('QStandardPaths::AppLocalDataLocation') `
        -and $experienceController.Contains('QTimer::singleShot(0') `
        -and $experienceController.Contains('m_cachedDishes.isEmpty()') `
        -and $experienceController.Contains('QSaveFile output') `
        -and $experienceController.Contains('QImageReader') `
        -and $experienceController.Contains('QCryptographicHash::Sha256') `
        -and $experienceController.Contains('QCryptographicHash::Sha1') `
        -and $experienceController.Contains('QNetworkRequest::ManualRedirectPolicy') `
        -and $experienceController.Contains('kMaximumCachedDishes') `
        -and $experienceController.Contains('kMaximumRedirects') `
        -and $experienceController.Contains('timeout->start()') `
        -and $experienceController.Contains('isAllowedUrl') `
        -and $experienceController.Contains('hasProcessArgumentPrefix(u"--capture-ui"_s)') `
        -and $experienceController -notmatch ':/experience/dim-sum\.json|qrc:/dim-sum/') `
    "startup dim-sum uses a bounded asynchronous verified app-data cache and fails open without local catalog assets"
Test-Policy ($experienceHeader.Contains('currentReleaseIdentity') `
        -and $experienceHeader.Contains('dimSumCacheStatus') `
        -and $dimSumSurface.Contains('dish.image') `
        -and $dimSumSurface.Contains('dish.publicPhotoUrl') `
        -and $dimSumSurface.Contains('dish.catalogRevision') `
        -and $dimSumSurface.Contains('dishImage.status === Image.Ready') `
        -and $dimSumSurface.Contains('Qt.openUrlExternally(root.publicPhotoUrl)')) `
    "desktop surfaces expose only decoded cached photos with authoritative public provenance"
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
Test-Policy ($appCMake -match 'QBT_WINDOWS_VERSION_RESOURCE') `
    "the Windows executable embeds the multi-resolution product icon"

$transfersPage = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/shell/TransfersPage.qml")
Test-Policy ($transfersPage -match 'enabled:\s*TransferController\.selectionCount\s*>\s*0' `
        -and $transfersPage.Contains('color: !splitDockActionButton.enabled') `
        -and $transfersPage.Contains('? Theme.color("outline")')) `
    "selection-only Split Dock actions and delete icons expose a muted disabled state"
Test-Policy ($transferControllerHeader.Contains('setDHTDisabled(bool disabled)') `
        -and $transferControllerHeader.Contains('setPEXDisabled(bool disabled)') `
        -and $transferControllerHeader.Contains('setLSDDisabled(bool disabled)') `
        -and $transfersPage.Contains('onOptionsAccepted') `
        -and $transfersPage.Contains('setShareLimitPolicy')) `
    "the redesigned Torrent Options dialog applies its accepted selection edits"

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
$filterTextFieldForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/FilterTextField.qml")
$appHeaderForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/shell/AppHeader.qml")
$appMenuForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/mainwindow/AppMenuBar.qml")
$centralTabsForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/mainwindow/CentralTabs.qml")
$searchTabForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/search/SearchTab.qml")
$mainQmlForPalette = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/Main.qml")
$optionsDialogForPalette = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/options/OptionsDialog.qml")
Test-Policy ($mainQmlForPalette -match 'id:\s*actionCommandPalette' `
        -and $mainQmlForPalette -match 'shortcut:\s*"Ctrl\+Shift\+F"' `
        -and $mainQmlForPalette -notmatch 'Ctrl\+K' `
        -and $mainQmlForPalette -match 'onTriggered:\s*commandPalette\.openPalette\(\)' `
        -and $mainQmlForPalette -match 'CommandPalette\s*\{' `
        -and $mainQmlForPalette -match 'invokePaletteCommand\(commandId\)' `
        -and $mainQmlForPalette -match 'function\s+openPanel\(panel\)' `
        -and $mainQmlForPalette -match 'openPanel\(commandId\.slice\(6\)\)' `
        -and $appHeaderForPalette -match 'actionCommandPalette\.trigger\(\)' `
        -and $appMenuForPalette -match 'action:\s*menuBar\.shell\.actionCommandPalette') `
    "Ctrl+Shift+F without a competing Ctrl+K binding and idempotent panel destinations open the wired desktop command palette"
Test-Policy ($commandPalette -match 'WorkspaceManager\.evaluateRegularExpression' `
        -and $commandPalette -match 'Keys\.onDownPressed' `
        -and $commandPalette -match 'Keys\.onUpPressed' `
        -and $commandPalette -match 'Keys\.onReturnPressed' `
        -and $commandPalette -match 'Accessible\.name:\s*qsTr\("Search command palette"\)') `
    "the command palette supports shared regex search, keyboard navigation, and accessible naming"
Test-Policy ($mainQmlForPalette -match 'function commandPaletteCommands\(\)' `
        -and $mainQmlForPalette -match 'var actionEntries = \[' `
        -and ([regex]::Matches($mainQmlForPalette, 'action:\s*action[A-Za-z]+')).Count -ge 50 `
        -and $mainQmlForPalette -match 'SearchController\.plugins' `
        -and $mainQmlForPalette -match 'pluginId:\s*plugin\.id' `
        -and $mainQmlForPalette -match 'centralTabs\.openSearchPlugins\(command\.pluginId\)' `
        -and $centralTabsForPalette -match 'function openSearchPlugin\(pluginId\)' `
        -and $searchTabForPalette -match 'function selectPlugin\(pluginId\)' `
        -and $commandPalette -match 'modelData\.checkable' `
        -and $commandPalette -match 'root\.commands\.length') `
    "the command palette covers the shared action catalog and live installed search plugins"
Test-Policy ($commandPalette -match 'GUI/CommandPalette/FullWindow' `
        -and $commandPalette -match 'color:\s*Theme\.color\("surface"\)' `
        -and $commandPalette -match 'clip:\s*true') `
    "the command palette persists card/full-window choice and paints a bounded scrollable surface"
Test-Policy ($filterTextFieldForPalette -match 'parent:\s*Overlay\.overlay' `
        -and $filterTextFieldForPalette -match 'availableBelow' `
        -and $filterTextFieldForPalette -match 'moveWithinViewport' `
        -and $filterTextFieldForPalette -match 'DragHandler\s*\{' `
        -and $filterTextFieldForPalette -match 'ScrollBar\.horizontal\.policy:\s*ScrollBar\.AlwaysOff') `
    "regex-builder overlays stay in the viewport, scroll vertically, and drag from their header"
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

$programUpdaterHeader = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/programupdater.h")
$programUpdaterSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/app/programupdater.cpp")
$updateReadyBanner = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/UpdateReadyBanner.qml")
$updateOperationBanner = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/components/UpdateOperationBanner.qml")
$mainQmlForUpdater = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/quick/qml/Main.qml")
$downloadHandler = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/base/net/downloadhandlerimpl.cpp")
$downloadManager = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/base/net/downloadmanager.cpp")
$appCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "src/CMakeLists.txt")
Test-Policy ($programUpdaterHeader.Contains('QPointer<QProcess> m_process') `
        -and $programUpdaterSource.Contains('--checkForUpdate=') `
        -and $programUpdaterSource.Contains('--update=') `
        -and $programUpdaterSource.Contains('kMaximumProcessOutput') `
        -and $programUpdaterSource.Contains('kCheckTimeoutMs') `
        -and $programUpdaterSource.Contains('kStageTimeoutMs') `
        -and $programUpdaterSource.Contains('scheduleRetry()') `
        -and $programUpdaterSource.Contains('QStandardPaths::isTestModeEnabled()') `
        -and $programUpdaterSource.Contains('QBT_DISABLE_PROGRAM_UPDATES')) `
    "the Squirrel updater checks, downloads, stages, retries, and stays bounded without blocking the UI"
Test-Policy ($programUpdaterSource.Contains('stagedExecutableExists(m_availableVersion)') `
        -and $programUpdaterSource.Contains('--processStartAndWait=') `
        -and $programUpdaterSource.Contains('UpdateRecovery::preservedLaunchArguments(') `
        -and $programUpdaterSource.Contains('joinWindowsCommandLine(targetArguments)') `
        -and $programUpdaterSource.Contains('--process-start-args=') `
        -and $programUpdaterHeader.Contains('Q_PROPERTY(QUrl releaseNotesUrl READ releaseNotesUrl NOTIFY availableVersionChanged)') `
        -and -not $programUpdaterHeader.Contains('Q_PROPERTY(QUrl releaseNotesUrl READ releaseNotesUrl CONSTANT)') `
        -and $updateReadyBanner -match 'ProgramUpdater\.readyToRestart' `
        -and $updateReadyBanner -match 'readonly property string versionText:\s*ProgramUpdater\.availableVersion' `
        -and $updateReadyBanner -notmatch 'the latest version' `
        -and $updateReadyBanner -match 'ProgramUpdater\.releaseNotesUrl' `
        -and $updateReadyBanner -match 'qsTr\("Release notes"\)' `
        -and $updateReadyBanner -match 'qsTr\("Later"\)' `
        -and $updateReadyBanner -match 'qsTr\("Restart to install update"\)' `
        -and $updateReadyBanner -match 'restartRequested\(root\.returnFocusItem\)' `
        -and $updateReadyBanner -match 'Accessible\.role:\s*Accessible\.AlertMessage' `
        -and $updateReadyBanner -match 'duration:\s*ThemeManager\.reducedMotion\s*\?\s*0\s*:\s*Spacing\.motionFast' `
        -and $mainQmlForUpdater -match 'ProgramUpdater\.restartToUpdate\(\)' `
        -and $mainQmlForUpdater -match 'id:\s*updateRestartConfirmDialog' `
        -and $mainQmlForUpdater -match 'acceptText:\s*qsTr\("Restart to install update"\)' `
        -and $mainQmlForUpdater -match 'rejectText:\s*qsTr\("Later"\)' `
        -and $mainQmlForUpdater -match 'WorkspaceManager\.dirty\s*&&\s*!WorkspaceManager\.syncNow\(\)' `
        -and $mainQmlForUpdater -match 'OptionsController\.modified' `
        -and $mainQmlForUpdater -match 'optionsDialog\.visible\s*=\s*true' `
        -and $mainQmlForUpdater -match 'restoreUpdateRestartFocus' `
        -and $mainQmlForUpdater -match 'UpdateReadyBanner\s*\{' `
        -and $mainQmlForUpdater -match 'target:\s*ProgramUpdater' `
        -and $mainQmlForUpdater -match 'NotificationCenter\.notify\(body, severity, title\)') `
    "a verified staged update exposes exact-version notes, Later and focus-safe restart actions without losing Workspace or staged Options edits"
Test-Policy ($programUpdaterHeader.Contains('Q_PROPERTY(bool retryAvailable READ retryAvailable NOTIFY stateChanged)') `
        -and $programUpdaterHeader.Contains('Q_PROPERTY(bool cancellable READ cancellable NOTIFY stateChanged)') `
        -and $programUpdaterSource.Contains('return isSupported() && ((m_state == Error) || (m_state == Recovered));') `
        -and $programUpdaterSource.Contains('return (m_state == Checking) || (m_state == Verifying) || (m_state == Downloading);') `
        -and $programUpdaterSource.Contains('if (m_state == Staging)') `
        -and $programUpdaterSource.Contains('Update cannot be cancelled safely') `
        -and $updateOperationBanner -match 'readonly property bool expanded:\s*busy \|\| retryAvailable' `
        -and $updateOperationBanner -match 'readonly property bool staging:\s*ProgramUpdater\.state === ProgramUpdater\.Staging' `
        -and $updateOperationBanner -match 'visible:\s*root\.cancellable' `
        -and $updateOperationBanner -match 'if \(ProgramUpdater\.cancellable\)' `
        -and $updateOperationBanner -match 'visible:\s*root\.retryAvailable' `
        -and $updateOperationBanner -match 'if \(ProgramUpdater\.retryAvailable\)' `
        -and $updateOperationBanner -match 'stagingExplanation' `
        -and $updateOperationBanner -match 'cannot be cancelled safely' `
        -and $updateOperationBanner -match 'ProgressBar\s*\{' `
        -and $updateOperationBanner -match 'indeterminate:\s*!root\.showPercent' `
        -and $updateOperationBanner -match 'Accessible\.role:\s*Accessible\.AlertMessage' `
        -and $mainQmlForUpdater -match 'UpdateOperationBanner\s*\{' `
        -and $mainQmlForUpdater -match 'onCancelRequested:\s*root\.cancelProgramUpdate\(\)' `
        -and $mainQmlForUpdater -match 'onRetryRequested:\s*root\.retryProgramUpdate\(\)' `
        -and $mainQmlForUpdater -match 'function cancelProgramUpdate\(\)' `
        -and $mainQmlForUpdater -match 'function retryProgramUpdate\(\)' `
        -and $mainQmlForUpdater -match 'action:\s*actionCancelUpdate' `
        -and $mainQmlForUpdater -match 'action:\s*actionRetryUpdate' `
        -and $mainQmlForUpdater -match 'Cancellation requested\. The current update check or download will stop' `
        -and $mainQmlForUpdater -match 'Retrying the signed update check') `
    "the non-blocking updater surface shows truthful progress, permits cancel only before staging, and exposes retry after failure or recovery"
$updateRecoverySource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/app/updaterecovery.cpp")
$applicationSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/app/application.cpp")
$watchdogIndex = $desktopMain.IndexOf('UpdateRecovery::runWatchdogIfRequested')
$applicationIndex = $desktopMain.IndexOf('Application app(argc, argv)')
$primaryIndex = $desktopMain.IndexOf('if (!app.isPrimaryInstance())')
$startedIndex = $desktopMain.IndexOf('UpdateRecovery::acknowledgeStarted')
$rootGuardIndex = $applicationSource.IndexOf('if (!m_engine->rootObjects().isEmpty())')
$readyIndex = $applicationSource.IndexOf('UpdateRecovery::acknowledgeReady')
Test-Policy ($updateRecoverySource.Contains('QStringList preservedLaunchArguments') `
        -and $updateRecoverySource.Contains('preservedArguments(arguments)') `
        -and $desktopMain.Contains('CommandLineToArgvW(GetCommandLineW()') `
        -and $watchdogIndex -ge 0 `
        -and $applicationIndex -gt $watchdogIndex `
        -and $primaryIndex -gt $applicationIndex `
        -and $startedIndex -gt $primaryIndex `
        -and $rootGuardIndex -ge 0 `
        -and $readyIndex -gt $rootGuardIndex `
        -and $applicationSource.Contains('QTimer::singleShot(0, this')) `
    "update recovery starts its watchdog before QApplication, preserves only safe launch selection, and marks ready only after Main.qml survives an event-loop turn"
$searchHandlerSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/search/searchhandler.cpp")
Test-Policy ($searchHandlerSource.Contains('constexpr qsizetype MAX_SEARCH_RESULTS = 10000;') `
        -and $searchHandlerSource.Contains('(m_resultCount + searchResultList.size()) > MAX_SEARCH_RESULTS') `
        -and $searchHandlerSource.Contains('searchResultList.resize(remainingResultSlots)') `
        -and $searchHandlerSource.Contains('parseSearchResult(trailingLine, finalSearchResult)') `
        -and $searchHandlerSource.Contains('m_resultCount >= MAX_SEARCH_RESULTS')) `
    "third-party search output preserves a valid final unterminated row and caps only overflow results"
$releaseNotesActionIndex = $updateReadyBanner.IndexOf('id: releaseNotesButton')
$laterActionIndex = $updateReadyBanner.IndexOf('id: laterButton')
$restartActionIndex = $updateReadyBanner.IndexOf('id: restartButton')
Test-Policy ($updateReadyBanner.Contains('id: actionLayout') `
        -and $updateReadyBanner.Contains('readonly property real requiredInlineWidth:') `
        -and $updateReadyBanner.Contains('I18n.language === I18n.Bilingual') `
        -and $updateReadyBanner.Contains('columns: stackActions ? 1 : 4') `
        -and ([regex]::Matches($updateReadyBanner, 'Layout\.maximumWidth:\s*actionLayout\.width')).Count -eq 3 `
        -and ([regex]::Matches($updateReadyBanner, 'wrapMode:\s*Text\.WordWrap')).Count -ge 5 `
        -and ([regex]::Matches($updateReadyBanner, 'activeFocusOnTab:\s*true')).Count -eq 3 `
        -and $updateReadyBanner.Contains('KeyNavigation.tab: laterButton') `
        -and $updateReadyBanner.Contains('KeyNavigation.tab: restartButton') `
        -and $releaseNotesActionIndex -ge 0 `
        -and $laterActionIndex -gt $releaseNotesActionIndex `
        -and $restartActionIndex -gt $laterActionIndex `
        -and $updateReadyBanner.Contains('leftPadding: Math.min(Spacing.lg, Math.max(0, width / 16))') `
        -and $updateReadyBanner.Contains('rightPadding: Math.min(Spacing.lg, Math.max(0, width / 16))')) `
    "ready-update actions stack for constrained or bilingual viewports, wrap without clipping at high scale, and keep Release notes, Later, Restart keyboard order"
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
$searchControllerHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/controllers/searchcontroller.h")
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
Test-Policy ($searchControllerHeader.Contains('QTimer m_pluginsChangedTimer') `
        -and $searchControllerSource.Contains('m_pluginsChangedTimer.setInterval(120)') `
        -and $searchControllerSource.Contains('void SearchController::schedulePluginsChanged') `
        -and $searchControllerSource -match 'unofficialCatalogStatusChanged[\s\S]{0,700}inProgress' `
        -and $searchControllerSource -match 'unofficialCatalogStatusChanged[\s\S]{0,700}schedulePluginsChanged\(true\)' `
        -and $searchControllerSource -notmatch 'unofficialCatalogStatusChanged[\s\S]{0,700}emit pluginsChanged\(\)') `
    "catalog progress coalesces plugin inventory updates instead of rebuilding the command palette per downloaded row"
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
Test-Policy ($searchManagerCtor -match 'QTimer::singleShot\(0,\s*this,\s*\[this\]\s*\{[\s\S]*?update\(true,\s*\[this\]\s*\{\s*startUnofficialCatalogSync\(\);\s*\}\);[\s\S]*?\}\);' `
        -and $searchPluginManager -match 'connect\(m_capabilityProcess,\s*&QProcess::finished' `
        -and $searchPluginManager -match 'connect\(m_capabilityProcess,\s*&QProcess::readyReadStandardOutput' `
        -and $searchPluginManager -match 'connect\(m_capabilityProcess,\s*&QProcess::readyReadStandardError' `
        -and $searchPluginManager.Contains('MAX_CAPABILITY_STDOUT_BYTES') `
        -and $searchPluginManager.Contains('MAX_CAPABILITY_STDERR_BYTES') `
        -and $searchPluginManager.Contains('emit pluginCatalogChanged();') `
        -and $searchPluginManager -match 'm_capabilityTimeout->setInterval\(10000\)' `
        -and $searchPluginManager -notmatch 'waitFor(?:Started|Finished)') `
    "startup and catalog capability probes are serialized, bounded, and asynchronous instead of blocking the UI thread"

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
Test-Policy ($workspaceStrip.Contains('root.appearanceValue(control.resolvedAppearance, "backgroundColor"') `
        -and $workspaceStrip.Contains('root.appearanceValue(control.resolvedAppearance, "hoverColor"') `
        -and $workspaceStrip.Contains('root.appearanceValue(control.resolvedAppearance, "checkedColor"') `
        -and $workspaceStrip.Contains('Theme.color("surface")') `
        -and $workspaceStrip.Contains('Theme.color("surfaceContainerHigh")') `
        -and $workspaceStrip.Contains('Theme.color("primaryContainer")')) `
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

# Transfer-list export is deliberately checked at both edges: the serializer
# must escape hostile cell content and the QML surface must state its scope and
# any format loss before the native SaveFile dialog runs.
$tabularExportHeader = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/utils/tabularexport.h")
$tabularExportSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/base/utils/tabularexport.cpp")
$tabularExportDialog = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/dialogs/TabularExportDialog.qml")
$tabularContextMenu = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TransferRowContextMenu.qml")
$legacyTransferListView = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "src/quick/qml/transferlist/TransferListView.qml")
Test-Policy ($tabularExportHeader.Contains("enum class Format") `
        -and $tabularExportSource.Contains("Format::JsonLines") `
        -and $tabularExportSource.Contains("escapeXml") `
        -and $tabularExportSource.Contains("escapeDelimited") `
        -and $tabularExportSource.Contains("escapeQuotedScalar") `
        -and $tabularExportSource.Contains("isFiniteNumeric") `
        -and $tabularExportSource.Contains("quoteSqlIdentifier")) `
    "the transfer exporter covers the ten formats and escapes structured output"
Test-Policy ($tabularExportSource.Contains("key.front().isDigit()") `
        -and $tabularExportSource.Contains("Qt::CaseInsensitive") `
        -and $tabularExportSource.Contains("field_")) `
    "export identifiers remain valid when localized or numeric headers are supplied"
Test-Policy ($tabularExportDialog.Contains("function openFor(onlySelected)") `
        -and $tabularExportDialog.Contains("selectedOnly") `
        -and $tabularExportDialog.Contains("14-column summary") `
        -and $tabularExportDialog.Contains("Before export:") `
        -and $tabularExportDialog.Contains("UTF-8 with LF line endings") `
        -and $tabularExportDialog.Contains("Platform.FileDialog.SaveFile") `
        -and $tabularExportDialog.Contains("toLocalFile")) `
    "the export dialog states scope, encoding, line endings, and format loss before saving"
Test-Policy ($tabularContextMenu.Contains("signal exportListRequested()") `
        -and $tabularContextMenu.Contains("Export transfer list…") `
        -and $transfersPage.Contains("tabularExportDialog.openFor(false)") `
        -and $transfersPage.Contains("tabularExportDialog.openFor(true)") `
        -and $legacyTransferListView.Contains("onExportListRequested") `
        -and $legacyTransferListView.Contains("tabularExportDialog.openFor(true)")) `
    "the transfer list offers export from both the page and its searchable row menu"
Test-Policy (Test-Path -LiteralPath `
        (Get-RepositoryPath "docs/features/transfers/tabular-export.md") -PathType Leaf) `
    "transfer-list export behaviour and verification are documented"

$workflowPath = Get-RepositoryPath ".github/workflows/release-every-push.yml"
Test-Policy (Test-Path -LiteralPath $workflowPath -PathType Leaf) "the push release workflow exists"
$squirrelBuildSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "scripts/build-squirrel-package.ps1")
$squirrelSmokeSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "scripts/test-squirrel-package.ps1")
$squirrelNuspec = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "installer/qbittorrent-material.nuspec")
$rootCMake = Get-Content -Raw -LiteralPath (Get-RepositoryPath "CMakeLists.txt")
$buildHelperSource = Get-Content -Raw -LiteralPath (Get-RepositoryPath "run.ps1")
Test-Policy ($squirrelBuildSource.Contains('$SquirrelVersion = "2.0.1"') `
        -and $squirrelBuildSource.Contains('$SquirrelSha256 = "923e18abb4fd50b5a4878a39dbcd042ed3f7eb68fc0f82c0955cd5380c921ac7"') `
        -and $squirrelBuildSource.Contains('$NuGetVersion = "7.6.0"') `
        -and $squirrelBuildSource.Contains('$NuGetSha256 = "12a7a2e0d11bd872c2a1e03c85b24a0288501f8b22084b47c90d4f2458c978d4"') `
        -and $squirrelBuildSource.Contains('https://api.nuget.org/v3-flatcontainer/')) `
    "Squirrel and NuGet downloads are pinned by version and verified SHA256 from the official feed"
Test-Policy ($squirrelBuildSource.Contains('$expectedDeltaCount = if ($hasPreviousFeed) { 1 } else { 0 }') `
        -and $squirrelBuildSource.Contains('Squirrel output for $feedDescription must contain exactly $expectedDeltaCount current delta package(s)') `
        -and $squirrelBuildSource.Contains('--signWithParams=$SignWithParams') `
        -and $squirrelBuildSource.Contains('$publicSigningPattern') `
        -and $squirrelBuildSource.Contains('$expectedSigningThumbprint') `
        -and $squirrelBuildSource.Contains('Get-AuthenticodeSignature') `
        -and $squirrelBuildSource.Contains('setup-embedded-Update.exe') `
        -and $squirrelBuildSource.Contains('lib/net45/qbittorrent.exe') `
        -and $squirrelBuildSource.Contains('lib/net45/qbittorrent_ExecutionStub.exe') `
        -and $squirrelBuildSource.Contains('Write-GitHubOutput "signed"')) `
    "Squirrel packaging mandates the expected delta shape and verifies safely parameterized Authenticode output"
Test-Policy ($squirrelBuildSource.Contains('Move-Item -LiteralPath $_.FullName -Destination $destination') `
        -and $squirrelBuildSource.Contains('@("[Paths]", "Prefix = .")') `
        -and $squirrelNuspec.Contains('<file src="**\*" target="lib\net45" />')) `
    "the Squirrel package flattens qbittorrent.exe and its DLLs beside qt.conf while preserving plugin/QML siblings"
Test-Policy ($squirrelSmokeSource.Contains('Current silent Setup') `
        -and $squirrelSmokeSource.Contains('Current normal Setup') `
        -and $squirrelSmokeSource.Contains('Expected one Squirrel Desktop shortcut and one Start Menu shortcut.') `
        -and $squirrelSmokeSource.Contains('did not register .torrent and magnet: to the stable execution stub') `
        -and $squirrelSmokeSource.Contains('Assert-AssociationBaseline') `
        -and $squirrelSmokeSource.Contains('KeyPresent = $current.KeyPresent') `
        -and $squirrelSmokeSource.Contains('$current.KeyPresent -ne $expected.KeyPresent') `
        -and $squirrelSmokeSource.Contains('Invoke-AssociationKeyPresenceSmoke $InstallerPath $PackageVersion') `
        -and $squirrelSmokeSource.Contains('Assert-AssociationKeyEmpty') `
        -and $squirrelSmokeSource.Contains('Assert-AssociationKeyAbsent') `
        -and $squirrelSmokeSource.Contains('Empty association-key silent Setup') `
        -and $squirrelSmokeSource.Contains('Absent association-key silent Setup') `
        -and $squirrelSmokeSource.Contains('Verified originally empty per-user .torrent and magnet association keys remain present and empty after uninstall.') `
        -and $squirrelSmokeSource.Contains('Verified originally absent per-user .torrent and magnet association keys remain absent after uninstall.') `
        -and $squirrelSmokeSource.Contains('Squirrel.Association.Sentinel') `
        -and $squirrelSmokeSource.Contains('[Microsoft.Win32.RegistryValueKind]::ExpandString') `
        -and $squirrelSmokeSource.Contains('Verified exact restoration of pre-existing per-user .torrent and magnet association values.') `
        -and $squirrelSmokeSource.Contains('[switch] $ExpectDelta') `
        -and $squirrelSmokeSource.Contains('$hasPriorFeed = $ExpectDelta.IsPresent') `
        -and $squirrelSmokeSource.Contains('$expectedDeltaCount = if ($hasPriorFeed) { 1 } else { 0 }') `
        -and $squirrelSmokeSource.Contains('without executing a prior Setup') `
        -and -not $squirrelSmokeSource.Contains('PreviousInstallerPath') `
        -and -not $squirrelSmokeSource.Contains('Previous silent Setup') `
        -and -not $squirrelSmokeSource.Contains('--update=$deltaOnlyFeed') `
        -and $squirrelSmokeSource.Contains('@("--uninstall", "--silent")') `
        -and $squirrelSmokeSource.Contains('gitExecutable -C $workspaceRoot fsck --strict')) `
    "installed-package smoke covers current Setup, feed-shaped deltas without executing a prior installer, shortcuts, association restoration, recovery, Git integrity, and uninstall"
Test-Policy ($rootCMake.Contains('QBT_PACKAGE_VERSION') `
        -and $rootCMake -notmatch '(?i)CPACK|NSIS' `
        -and $buildHelperSource.Contains('scripts\build-squirrel-package.ps1') `
        -and $buildHelperSource -notmatch '(?i)CPACK|NSIS|makensis' `
        -and -not (Test-Path -LiteralPath `
            (Get-RepositoryPath "installer/file_associations_install.nsh")) `
        -and -not (Test-Path -LiteralPath `
            (Get-RepositoryPath "installer/file_associations_uninstall.nsh"))) `
    "CMake and the one-click package path use Squirrel without retaining the dead NSIS/CPack path"
$releaseSelectorSource = Get-Content -Raw -LiteralPath `
    (Get-RepositoryPath "scripts/select-release-dim-sum.ps1")
Test-Policy ($releaseSelectorSource.Contains('Ding-Ding-Projects/dim-sum-photos') `
        -and $releaseSelectorSource.Contains('Invoke-GhJson') `
        -and $releaseSelectorSource.Contains('$ghTimeoutMilliseconds = 60000') `
        -and $releaseSelectorSource.Contains('^catalog-v1(?:-part-[0-9]{3})?$') `
        -and $releaseSelectorSource.Contains('$History.Digests.Contains($Asset.Digest)') `
        -and $releaseSelectorSource.Contains('dim-sum-id:') `
        -and $releaseSelectorSource.Contains('Dim-sum code name:') `
        -and $releaseSelectorSource.Contains('CatalogFixturePath') `
        -and $releaseSelectorSource.Contains('catalogBlobSha = $BlobSha') `
        -and $releaseSelectorSource.Contains('New-Result -Available $false') `
        -and $releaseSelectorSource -notmatch 'Invoke-WebRequest|Invoke-RestMethod') `
    "dim-sum release allocation uses bounded gh-only public provenance, legacy-use inference, offline fixtures, and version-only fallback"
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
    $runtimeStep = $stepLines["Run built QML startup smoke test"]
    $packageStep = $stepLines["Build and verify the Squirrel installer and update feed"]
    $publishStep = $stepLines["Publish one immutable non-draft release"]
    Test-Policy ($null -ne $policyStep -and $null -ne $buildStep `
            -and $null -ne $packageStep -and $null -ne $publishStep `
            -and $policyStep -lt $buildStep -and $buildStep -lt $packageStep `
            -and $packageStep -lt $publishStep) `
        "policy, build, installed-package tests, and publication are strictly ordered"
    Test-Policy ($null -ne $runtimeStep -and $buildStep -lt $runtimeStep `
            -and $runtimeStep -lt $packageStep `
            -and $workflow -match 'Install runtime for QML startup smoke test' `
            -and $workflow -match 'PlatformPluginPath') `
        "the built QML startup smoke test runs against a deployed runtime before packaging"

    $tokenPattern = 'secrets\.RELEASE_TOKEN\s*\|\|\s*secrets\.ORG_TOKEN\s*\|\|\s*secrets\.GITHUB_TOKEN'
    Test-Policy (([regex]::Matches($workflow, $tokenPattern)).Count -eq 4) `
        "release identity, prior-feed download, dim-sum allocation, and publication use the token fallback order"
    Test-Policy ($workflow -match 'Measure hosted runner resources') `
        "the workflow measures the hosted runner before relying on it"
    Test-Policy ($workflow -match 'GITHUB_WORKSPACE' -and $workflow -match 'RUNNER_TEMP') `
        "the workflow measures the actual workspace and temporary build volumes"
    Test-Policy ($workflow -match 'test-desktop-policy\.ps1') `
        "the workflow runs this desktop policy test before release"
    Test-Policy ($workflow -match 'count-lines\.ps1' `
            -and $workflow -match 'Project line count' `
            -and $workflow -match 'LINE_COUNT_PATH') `
        "the release notes include the committed CI line-count table"
    Test-Policy ($workflow -match 'gh api --include' `
            -and $workflow -match '\$latestStatus -eq 404' `
            -and $workflow -match 'Latest-release discovery failed closed' `
            -and $workflow -match 'partial or ambiguous Squirrel feed' `
            -and $workflow -match 'mismatched full-package and Setup versions' `
            -and $workflow -match 'PREVIOUS_FEED_AVAILABLE') `
        "prior-feed discovery permits only a proven 404 and requires a complete version-matched feed"
    Test-Policy ($workflow.Contains('Never download or execute the historical Setup.exe') -and $workflow.Contains('$smokeArguments.ExpectDelta = ($env:PREVIOUS_FEED_AVAILABLE -eq "true")') -and $workflow -notmatch 'PREVIOUS_INSTALLER_PATH|PreviousInstallerPath|steps\.previous\.outputs\.installer') "release CI derives deltas from prior feed data without executing a historical installer"
    Test-Policy ($workflow -match 'SQUIRREL_SIGN_WITH_PARAMS:.*secrets\.SQUIRREL_SIGN_WITH_PARAMS' `
            -and $workflow -match '\$packageArguments\.SignWithParams' `
            -and $workflow -match 'steps\.package\.outputs\.signed' `
            -and $workflow -match 'raw releasify arguments' `
            -and $workflow -match 'Authenticode signature:' `
            -and $workflow -match 'Not applied; update authenticity is enforced') `
        "optional Authenticode uses only non-secret store selectors and release notes state its verified or unapplied status"
    Test-Policy ($workflow -match 'SQUIRREL_FEED_SIGNING_PRIVATE_KEY_B64:.*secrets\.SQUIRREL_FEED_SIGNING_PRIVATE_KEY_B64' `
            -and $workflow -match 'resources/updates/squirrel-feed-public-key\.json' `
            -and $workflow -match 'ImportPkcs8PrivateKey' `
            -and $workflow -match 'RSASSA-PKCS1_v1_5-SHA256|RSASSA-PKCS1-v1_5-SHA256' `
            -and $workflow -match 'SignData\(' `
            -and $workflow -match 'VerifyData\(' `
            -and $workflow -match 'RELEASES\.sig' `
            -and $workflow -match '4479439dfb5bce538ab92e492dd677628060c8558d4c49ac7b253f3eeb4f36e8') `
        "publication requires an exact-byte RSA-SHA256 RELEASES signature bound to the committed public-key fingerprint"
    Test-Policy ($workflow -match 'publishedAsset\.digest' `
            -and $workflow -match 'publishedAsset\.size' `
            -and $workflow -match 'gh release download \$env:RELEASE_TAG' `
            -and $workflow -match 'Redownloaded Squirrel Setup differs from the exact locally tested bytes' `
            -and $workflow -match 'Redownloaded RELEASES/signature bytes differ' `
            -and $workflow -match 'Redownloaded RELEASES\.sig failed committed-public-key verification') `
        "staged assets retain tested sizes/digests and redownloaded Setup plus signed feed bytes are verified exactly"
    Test-Policy ($workflow -match 'master-updater' `
            -and $workflow -match 'feature-preview' `
            -and $workflow -match '"v\$packageVersion"' `
            -and $workflow -match 'Get-PublishedMasterSquirrelReleases' `
            -and $workflow -match '\$isNewestMasterPackage = \$env:GITHUB_REF_NAME -eq ''master''' `
            -and $workflow -match '\$makeLatest = if \(\$isNewestMasterPackage\) \{ ''true'' \} else \{ ''false'' \}' `
            -and $workflow -match '--raw-field "make_latest=\$makeLatest"' `
            -and $workflow -match '-f draft=false' `
            -and $workflow -notmatch 'latestChannelStable') `
        "the staged release receives its desired latest state during its sole publication transition"
    $releaseCreateOffset = $workflow.IndexOf('gh release create $env:RELEASE_TAG')
    $draftCreateOffset = $workflow.IndexOf('--draft', [Math]::Max(0, $releaseCreateOffset))
    $stagedAssetValidationOffset = $workflow.IndexOf(
        'Assert-TagReleaseAssetsAndSignedFeed "staged draft"',
        [Math]::Max(0, $draftCreateOffset))
    $workflowCompletedOffset = $workflow.IndexOf(
        '$workflowCompleted = [DateTimeOffset]::FromUnixTimeSeconds',
        [Math]::Max(0, $stagedAssetValidationOffset))
    $stagedNotesValidationOffset = $workflow.IndexOf(
        'Validated staged draft $env:RELEASE_TAG',
        [Math]::Max(0, $workflowCompletedOffset))
    $publishTransitionOffset = $workflow.IndexOf(
        '-f draft=false',
        [Math]::Max(0, $stagedNotesValidationOffset))
    $publishErrorOffset = $workflow.IndexOf(
        'throw "GitHub did not publish verified draft release $env:RELEASE_TAG."',
        [Math]::Max(0, $publishTransitionOffset))
    $publishErrorBlockEnd = if ($publishErrorOffset -ge 0) {
        $workflow.IndexOf("          }", $publishErrorOffset)
    }
    else { -1 }
    $postPublishTail = if ($publishErrorBlockEnd -ge 0) {
        $workflow.Substring($publishErrorBlockEnd + "          }".Length)
    }
    else { '' }
    Test-Policy ($workflow -match '(?m)^\s*actions:\s*read\s*$' `
            -and $workflow -match 'gh run view \$env:GITHUB_RUN_ID' `
            -and $workflow -match '--json jobs' `
            -and $workflow -match '\.startedAt' `
            -and $workflow -match 'Workflow started:' `
            -and $workflow -match 'Workflow completed:' `
            -and $workflow -match 'Workflow duration:' `
            -and $workflow -match 'yyyy-MM-dd''T''HH:mm:ss''Z''' `
            -and $workflow -match '\{0:D2\}:\{1:D2\}:\{2:D2\}' `
            -and $releaseCreateOffset -ge 0 `
            -and $draftCreateOffset -gt $releaseCreateOffset `
            -and $stagedAssetValidationOffset -gt $draftCreateOffset `
            -and $workflowCompletedOffset -gt $stagedAssetValidationOffset `
            -and $stagedNotesValidationOffset -gt $workflowCompletedOffset `
            -and $publishTransitionOffset -gt $stagedNotesValidationOffset `
            -and $publishErrorOffset -gt $publishTransitionOffset `
            -and $publishErrorBlockEnd -gt $publishErrorOffset `
            -and $workflow -match '\$missingStagedTimingLines\.Count -ne 0' `
            -and $postPublishTail -notmatch 'throw|Assert-TagReleaseAssetsAndSignedFeed|latestChannelStable|gh release download|gh api|gh release view') `
        "release assets and final notes are validated in a mutable draft before one immutable publication transition"
    Test-Policy ($workflow -match 'select-release-dim-sum\.ps1' `
            -and $workflow -match 'Stamp the selected public release identity into the desktop build' `
            -and $workflow -match 'DIM_SUM_CODE_NAME' `
            -and $workflow -match 'DIM_SUM_PHOTO_URL' `
            -and $workflow -match 'DIM_SUM_CATALOG_REVISION' `
            -and $workflow -match 'Public dim-sum photo:' `
            -and $workflow -match 'version-only release' `
            -and $workflow -notmatch 'DIM_SUM_PATH') `
        "the release stamps a public catalog identity, links its photo, and permits a truthful version-only fallback without attaching a copied image"
    Test-Policy ($workflow.Contains('$isNewestMasterPackage = $env:GITHUB_REF_NAME -eq ''master''') `
            -and $workflow.Contains('feature-preview') `
            -and $workflow.Contains('$makeLatest = if ($isNewestMasterPackage) { ''true'' } else { ''false'' }') `
            -and $workflow.Contains('--raw-field "make_latest=$makeLatest"')) `
        "feature-branch releases publish with make_latest=false during the sole transition"
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
    Test-Policy ($squirrelSmokeSource -match 'qoffscreen\.dll' `
            -and $squirrelSmokeSource -match 'qoffscreend\.dll' `
            -and $squirrelSmokeSource -match 'RedirectStandardOutput' `
            -and $squirrelSmokeSource -match 'Write-SmokeOutput') `
        "installed-package smoke tests assert release plugins and retain launch diagnostics"
    Test-Policy ($workflow -notmatch '(?i)NSIS|\bcpack\b' `
            -and $workflow -match 'QBT_PACKAGE_VERSION=\$packageVersion' `
            -and $workflow -match 'steps\.package\.outputs\.releases' `
            -and $workflow -match 'steps\.package\.outputs\.fullPackage' `
            -and $workflow -match 'steps\.package\.outputs\.deltaPackage') `
        "the workflow publishes one monotonic Squirrel Setup plus full, delta-when-available, and RELEASES update assets"
    Test-Policy ($workflow -match '(?ms)name:\s*Check out the pushed commit.*?fetch-depth:\s*0') `
        "the release checkout includes full history for changelog commit validation"
    Test-Policy ($workflow -match '(?ms)gh release create\s+\$env:RELEASE_TAG.*?--draft' `
            -and $workflow -match 'Staged release failed asset, note, timing, signature, channel, or target verification.' `
            -and $workflow -match 'Validated staged draft \$env:RELEASE_TAG' `
            -and $workflow -match 'databaseId' `
            -and $workflow -match 'gh api --method PATCH' `
            -and $workflow -match '-f draft=false' `
            -and $workflow -match '--raw-field "make_latest=\$makeLatest"' `
            -and $workflow -notmatch '--prerelease') `
        "the release stays a validated draft until the single non-prerelease publication transition"
    Test-Policy ($workflow -notmatch '--clobber') "the workflow never clobbers a release asset"
    Test-Policy ($workflow -notmatch 'gh release upload') `
        "the workflow never uploads assets into an existing release"
    Test-Policy ($workflow -notmatch '(?i)\btui\b') "the workflow remains Windows-desktop-only"
}

try {
    & (Join-Path $PSScriptRoot 'test-unofficial-plugin-catalog.ps1')
    Test-Policy $true "the verified unofficial-plugin catalog covers every canonical wiki entry and is integrated safely"
}
catch {
    Write-Host "  catalog policy detail: $($_.Exception.Message)"
    Test-Policy $false "the verified unofficial-plugin catalog covers every canonical wiki entry and is integrated safely"
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
