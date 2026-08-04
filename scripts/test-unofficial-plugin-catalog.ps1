[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'resources/searchengine/unofficial-plugins.json'
$managerPath = Join-Path $repoRoot 'src/base/search/searchpluginmanager.cpp'
$managerHeaderPath = Join-Path $repoRoot 'src/base/search/searchpluginmanager.h'
$controllerPath = Join-Path $repoRoot 'src/quick/controllers/searchcontroller.cpp'
$controllerHeaderPath = Join-Path $repoRoot 'src/quick/controllers/searchcontroller.h'
$pluginsModelPath = Join-Path $repoRoot 'src/quick/models/searchpluginsmodel.h'
$mainQmlPath = Join-Path $repoRoot 'src/quick/qml/Main.qml'
$pluginsDialogPath = Join-Path $repoRoot 'src/quick/qml/search/SearchPluginsDialog.qml'
$novaPath = Join-Path $repoRoot 'resources/searchengine/nova3/nova2.py'
$downloadHandlerPath = Join-Path $repoRoot 'src/base/net/downloadhandlerimpl.cpp'
$cmakePath = Join-Path $repoRoot 'src/CMakeLists.txt'
$qrcPath = Join-Path $repoRoot 'resources/resources.qrc'

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schema -ne 2) { throw 'Unofficial catalog schema must be 2.' }
if ([string]$manifest.source -notmatch '^https://') { throw 'Catalog provenance must use HTTPS.' }

$rows = @($manifest.plugins)
$ids = @($rows | ForEach-Object { [string]$_.id })
$idSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($id in $ids) {
    if (-not $idSet.Add($id)) { throw "Duplicate catalog row id: $id" }
}

$canonical = {
    param([string]$id)
    if ($id -match '^(.*)_([2-9][0-9]*)$' -and $idSet.Contains($Matches[1])) {
        return $Matches[1]
    }
    return $id
}

$availableRows = @($rows | Where-Object { $_.available -eq $true })
$unavailableRows = @($rows | Where-Object { $_.available -ne $true })
$canonicalIds = @($rows | ForEach-Object { & $canonical ([string]$_.id) } | Sort-Object -Unique)
$availableCanonicalIds = @($availableRows | ForEach-Object { & $canonical ([string]$_.id) } | Sort-Object -Unique)

if ($rows.Count -ne 100) { throw "Expected 100 wiki rows, found $($rows.Count)." }
if ($availableRows.Count -ne 97) { throw "Expected 97 available pinned sources, found $($availableRows.Count)." }
if ($unavailableRows.Count -ne 3) { throw "Expected three unavailable duplicate variants, found $($unavailableRows.Count)." }
if ($canonicalIds.Count -ne 92) { throw "Expected 92 canonical plugins, found $($canonicalIds.Count)." }
if ($availableCanonicalIds.Count -ne 92) { throw "Every canonical plugin needs a source; found $($availableCanonicalIds.Count) of 92." }

foreach ($row in $availableRows) {
    $uri = [Uri]([string]$row.url)
    if ($uri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host) -or -not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        throw "Unsafe source URL for $($row.id): $($row.url)"
    }
    if ([string]$row.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Missing or malformed SHA-256 pin for $($row.id)."
    }
}

foreach ($row in $unavailableRows) {
    $base = & $canonical ([string]$row.id)
    if ($base -eq [string]$row.id -or $availableCanonicalIds -notcontains $base) {
        throw "Unavailable row $($row.id) is not covered by a verified canonical alternative."
    }
}

$manager = Get-Content -Raw -LiteralPath $managerPath
$managerHeader = Get-Content -Raw -LiteralPath $managerHeaderPath
$controller = Get-Content -Raw -LiteralPath $controllerPath
$controllerHeader = Get-Content -Raw -LiteralPath $controllerHeaderPath
$pluginsModel = Get-Content -Raw -LiteralPath $pluginsModelPath
$mainQml = Get-Content -Raw -LiteralPath $mainQmlPath
$pluginsDialog = Get-Content -Raw -LiteralPath $pluginsDialogPath
$nova = Get-Content -Raw -LiteralPath $novaPath
$downloadHandler = Get-Content -Raw -LiteralPath $downloadHandlerPath
$cmake = Get-Content -Raw -LiteralPath $cmakePath
$qrc = Get-Content -Raw -LiteralPath $qrcPath

$requiredManagerEvidence = @(
    'MAX_UNOFFICIAL_PLUGIN_BYTES',
    'QCryptographicHash::Sha256',
    'canonicalCatalogID',
    'seeded.contains(entry.id)',
    'update(true',
    'unofficialCatalogSyncFinished',
    'm_catalogPreexisting',
    'retryUnofficialCatalogSync',
    'DownloadRequest(source.url).limit(MAX_UNOFFICIAL_PLUGIN_BYTES)',
    'MAX_CAPABILITY_STDOUT_BYTES',
    'MAX_CAPABILITY_STDERR_BYTES',
    'readyReadStandardOutput',
    'readyReadStandardError',
    'outputOverflow',
    'emit pluginCatalogChanged()',
    'runtimeUnavailable',
    'awaitingRuntime',
    'u"waiting-runtime"_s'
)
foreach ($needle in $requiredManagerEvidence) {
    if (-not $manager.Contains($needle) -and -not $managerHeader.Contains($needle)) {
        throw "Catalog manager is missing required evidence: $needle"
    }
}

if ($nova -notmatch 'PLUGIN_IMPORT_ERROR:' -or $nova -match 'except Exception:\s*\r?\n\s*pass') {
    throw 'nova2.py must return concrete import diagnostics instead of silently swallowing them.'
}
if ($manager.Contains('Plugin is not supported.')) {
    throw 'The misleading generic unsupported-plugin error returned.'
}
if ($manager -match 'waitFor(?:Started|Finished)') {
    throw 'Search capability probes must not wait synchronously on the UI thread.'
}
if ($manager -match 'if \(!m_runtimeError\.isEmpty\(\) && !m_catalogQueue\.isEmpty\(\)\)' `
        -or $manager -match 'Automatic plugin installation is waiting for the search runtime') {
    throw 'A missing search runtime must not abort verified catalog downloads or count every queued file as failed.'
}
if ($manager -notmatch 'catalogQuarantinePath\(m_currentCatalogEntry\.id, source\.sha256\)' `
        -or $manager -notmatch 'state\.integrityState = preserveOwnedActive \? u"pending-update-trust"_s : u"pending-trust"_s' `
        -or $manager -notmatch 'A user-managed active file was preserved; the pinned catalog file is quarantined' `
        -or $manager -notmatch 'state\.runtimeState = u"import-failed"_s') {
    throw 'Verified downloads must remain quarantined until explicit trust, preserve user-managed active files, and retain real import diagnostics.'
}
if ($pluginsDialog -notmatch 'summary\.runtimeUnavailable' `
        -or $pluginsDialog -notmatch 'summary\.awaitingRuntime' `
        -or $pluginsDialog -notmatch 'state === "waiting-runtime"') {
    throw 'The plugin UI must report one aggregate waiting-for-runtime warning and retain its retry path.'
}
if ($manager -notmatch 'm_capabilityStdOut\.clear\(\)' `
        -or $manager -notmatch 'm_capabilityStdErr\.clear\(\)' `
        -or $manager -match 'result\.standardOutput\s*=\s*QString::fromUtf8\(m_capabilityProcess->readAllStandardOutput\(\)\)') {
    throw 'Search capability process output must be drained incrementally into bounded buffers.'
}
if ($controller -notmatch '&SearchPluginManager::pluginCatalogChanged' `
        -or $pluginsModel -notmatch 'Q_PROPERTY\(QVariantList inventory' `
        -or $pluginsDialog -notmatch 'inventory:\s*SearchController\.plugins') {
    throw 'Suppressed startup reconciliation must refresh the controller inventory and its canonically bound dialog model.'
}
if ($downloadHandler -notmatch 'Refused an insecure redirect from HTTPS') {
    throw 'HTTPS downloads must reject a redirect downgrade.'
}
if ($controller -notmatch 'QVariantList SearchController::plugins\(\) const') {
    throw 'SearchController does not expose the full enabled-and-disabled inventory.'
}
if ($managerHeader -notmatch 'QVariantList palettePluginCatalog\(\) const' `
        -or $managerHeader -notmatch 'QHash<QString, CatalogEntry> m_catalogEntries' `
        -or $managerHeader -notmatch 'QStringList m_bundledPluginIDs') {
    throw 'The manager does not retain a validated palette catalog plus bundled-default identities.'
}
$paletteMethodStart = $manager.IndexOf('QVariantList SearchPluginManager::palettePluginCatalog() const', [StringComparison]::Ordinal)
$paletteMethodEnd = if ($paletteMethodStart -ge 0) {
    $manager.IndexOf('QStringList SearchPluginManager::enabledPlugins() const', $paletteMethodStart, [StringComparison]::Ordinal)
} else {
    -1
}
if ($paletteMethodStart -lt 0 -or $paletteMethodEnd -le $paletteMethodStart) {
    throw 'The palette plugin catalog implementation is missing or malformed.'
}
$paletteMethod = $manager.Substring($paletteMethodStart, $paletteMethodEnd - $paletteMethodStart)
foreach ($field in @('installedOnDisk', 'registered', 'enabled', 'version', 'url', 'runtimeWaiting', 'canRetry', 'canManage')) {
    if ($paletteMethod -notmatch ('u"' + [regex]::Escape($field) + '"_s')) {
        throw "Palette plugin rows are missing the '$field' state field."
    }
}
if ($paletteMethod -match 'QJson(?:Document|Object|Array)' `
        -or $paletteMethod -notmatch 'm_catalogEntries' `
        -or $paletteMethod -notmatch 'ids\.append\(m_bundledPluginIDs\)' `
        -or $manager -notmatch 'm_catalogEntries\s*=\s*std::move\(validatedEntries\)') {
    throw 'Palette rows must reuse the fully validated in-memory catalog and bundled defaults instead of reparsing JSON.'
}
if ($controller -notmatch 'QVariantList result = mgr->palettePluginCatalog\(\)' `
        -or $controllerHeader -notmatch 'installedOnDisk, registered, enabled' `
        -or $controller -notmatch '&SearchPluginManager::runtimeErrorChanged[\s\S]{0,1200}emit pluginsChanged\(\)' `
        -or $controller -notmatch '&SearchPluginManager::unofficialCatalogStatusChanged[\s\S]{0,360}emit pluginsChanged\(\)' `
        -or $controller -notmatch '&SearchPluginManager::pluginEnabled[\s\S]{0,140}emit pluginsChanged\(\)') {
    throw 'SearchController does not expose or notify every palette catalog state transition.'
}
if ($controllerHeader -notmatch 'Q_PROPERTY\(QVariantMap pluginDiagnostics' `
        -or $controllerHeader -notmatch 'Q_PROPERTY\(bool pluginOperationInProgress' `
        -or $controllerHeader -notmatch 'Q_PROPERTY\(QVariantList pendingPluginOperationSummaries' `
        -or $controller -notmatch 'row\[u"diagnostic"_s\]' `
        -or $controller -notmatch 'row\[u"catalogSourceUrl"_s\]' `
        -or $pluginsModel -notmatch 'DiagnosticRole' `
        -or $pluginsModel -notmatch '\{DiagnosticRole, "diagnostic"\}' `
        -or $pluginsDialog -notmatch 'inventory:\s*SearchController\.plugins' `
        -or $pluginsDialog -notmatch 'role:\s*"diagnostic"') {
    throw 'Per-plugin diagnostics must survive in controller palette rows, the canonical dialog model, and the visible dialog row.'
}
if ($pluginsModel -notmatch 'Q_PROPERTY\(QVariantList inventory' `
        -or $pluginsModel -match 'm_ids\s*=\s*mgr->allPlugins\(\)' `
        -or $pluginsModel -notmatch 'Q_INVOKABLE QVariantMap pluginRecord\(int row\) const' `
        -or $pluginsModel -notmatch 'm_rowById\.value\(id, -1\)' `
        -or $pluginsModel -notmatch 'IntegrityStateRole' `
        -or $pluginsModel -notmatch 'RuntimeStateRole' `
        -or $pluginsModel -notmatch 'CatalogOwnedRole' `
        -or $pluginsModel -notmatch 'TrustedRole' `
        -or $pluginsModel -notmatch 'CanTrustRole' `
        -or $pluginsModel -notmatch 'UserRemovedRole') {
    throw 'SearchPluginsModel must retain the complete canonical controller union and expose stable ids plus security/runtime overlays.'
}
if ($pluginsDialog -notmatch 'pluginsModel\.flushPendingInventory\(\)' `
        -or $pluginsDialog -notmatch 'pluginsModel\.indexOfPlugin\(pluginId\)' `
        -or $pluginsDialog -notmatch 'pluginsModel\.highlightPlugin\(pluginId\)' `
        -or $pluginsDialog -notmatch 'pluginsTable\.revealRow\(row\)' `
        -or $pluginsDialog -notmatch 'highlightClearTimer\.restart\(\)' `
        -or $pluginsDialog -notmatch 'onTriggered:\s*pluginsModel\.clearHighlight\(\)' `
        -or $pluginsDialog -notmatch '!pluginsModel\.isRegistered\(row\)' `
        -or $pluginsDialog -notmatch 'visible:\s*pluginsModel\.isRegistered\(enabledRoot\.cell\.cellRow\)') {
    throw 'Every palette plugin id must reveal, focus, and transiently highlight its canonical row without enabling controls for unregistered plugins.'
}
if ($controller -notmatch 'installedOnDisk"_s\)\.toBool\(\)[\s\S]{0,120}registered"_s\)\.toBool\(\)' `
        -or $controller -notmatch '!row\.value\(u"userRemoved"_s\)\.toBool\(\)' `
        -or $controller -notmatch 'for \(const QString &id : std::as_const\(eligibleIDs\)\)\s*\r?\n\s*mgr->updatePlugin\(id\);' `
        -or $controller -match 'for \(auto it = updateInfo\.cbegin\(\);[^\r\n]*\)\s*\r?\n\s*m(?:gr)?->updatePlugin\(it\.key\(\)\);') {
    throw 'Update checks must update only installed/registered, non-user-removed plugins instead of every versions.txt entry.'
}
if ($controller -notmatch 'pluginRuntimeBlockReason\(\)' `
        -or $controller -notmatch 'beginPluginBatch\(u"runtime-recovery"_s, recoveryIDs\)' `
        -or $controller -notmatch 'finishRuntimeRecovery\(\)' `
        -or $controller -notmatch 'recordPluginBatchOutcome' `
        -or $controller -notmatch 'm_pluginBatch\.pending\.isEmpty\(\)[\s\S]{0,100}finishPluginBatch\(\)' `
        -or $controller -notmatch 'publishPluginOperationSummary\(summary\)') {
    throw 'Install/update/runtime recovery must short-circuit a blocked runtime and publish one completion summary after all expected outcomes.'
}
$globalPluginNotificationCount = [regex]::Matches($pluginsDialog, 'NotificationCenter\.notify\(').Count
if ($globalPluginNotificationCount -ne 1 `
        -or $pluginsDialog -match 'function onPlugin(?:InstallFailed|UpdateFailed|Installed|Updated)' `
        -or $pluginsDialog -notmatch 'function onPluginOperationSummaryReady\(summary\)' `
        -or $pluginsDialog -notmatch 'pendingPluginOperationSummaries' `
        -or $pluginsDialog -notmatch 'acknowledgePluginOperationSummary' `
        -or $pluginsModel -notmatch 'QTimer::singleShot\(0, this, \[this\] \{ flushPendingInventory\(\); \}\)') {
    throw 'The dialog must emit exactly one global notification per completed batch, replay lazy summaries, and coalesce model reloads.'
}
if ($mainQml -notmatch 'var plugins = SearchController\.plugins' -or $mainQml -match 'var scopes = SearchController\.pluginScopes') {
    throw 'The command palette is not built from the full plugin inventory.'
}
if ($cmake -notmatch 'searchengine/\*\.json' -or $qrc -notmatch 'searchengine/unofficial-plugins\.json') {
    throw 'The verified manifest is not wired into both resource build paths.'
}

Write-Host 'Unofficial plugin catalog policy passed: 100 rows, 97 available sources, 92/92 canonical plugins covered.'
