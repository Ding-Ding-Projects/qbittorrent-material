/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Derived from the original qBittorrent (GPLv2+) search subsystem. The class
 * and method names, the persisted disabled-plugin key, the `nova3` on-disk
 * layout, the update-server URL, and the category ids are preserved verbatim so
 * that the existing Python search plugins keep working and the QML bridge
 * (SearchController / SearchPluginsModel) can rely on a stable contract
 * (see docs/CONTRACTS.md §6, docs/ARCHITECTURE.md). All plugin lifecycle steps
 * and state changes are logged aggressively through the `lcSearch` category.
 */

#include "searchpluginmanager.h"

#include <algorithm>
#include <memory>
#include <utility>

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QDomDocument>
#include <QDomElement>
#include <QDomNode>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTimer>
#include <QUrl>

#include "base/global.h"
#include "base/logging.h"
#include "base/net/downloadmanager.h"
#include "base/net/proxyconfigurationmanager.h"
#include "base/preferences.h"
#include "base/profile.h"
#include "base/utils/bytearray.h"
#include "base/utils/foreignapps.h"
#include "base/utils/fs.h"
#include "base/utils/io.h"
#include "searchdownloadhandler.h"
#include "searchhandler.h"

namespace
{
    constexpr qint64 MAX_UNOFFICIAL_PLUGIN_BYTES = 512 * 1024;
    constexpr qint64 MAX_UNOFFICIAL_MANIFEST_BYTES = 512 * 1024;
    constexpr qint64 MAX_PLUGIN_VERSION_INFO_BYTES = 512 * 1024;
    constexpr qint64 MAX_CATALOG_LEDGER_BYTES = 1024 * 1024;
    constexpr int CATALOG_LEDGER_SCHEMA = 1;
    constexpr qsizetype MAX_CAPABILITY_STDOUT_BYTES = 2 * 1024 * 1024;
    constexpr qsizetype MAX_CAPABILITY_STDERR_BYTES = 512 * 1024;
    const QString UNOFFICIAL_MANIFEST_PATH = u":/searchengine/unofficial-plugins.json"_s;

    bool isSafeCatalogID(const QString &id)
    {
        static const QRegularExpression pattern {u"^[A-Za-z][A-Za-z0-9_]*$"_s};
        return pattern.match(id).hasMatch();
    }

    bool isSha256(const QByteArray &hash)
    {
        static const QRegularExpression pattern {u"^[0-9a-f]{64}$"_s};
        return pattern.match(QString::fromLatin1(hash)).hasMatch();
    }

    bool isGitRevision(const QString &revision)
    {
        static const QRegularExpression pattern {u"^[0-9a-f]{40}$"_s};
        return pattern.match(revision).hasMatch();
    }

    QProcessEnvironment minimalPythonEnvironment()
    {
        const QProcessEnvironment ambient = QProcessEnvironment::systemEnvironment();
        QProcessEnvironment result;
        // Python is launched by absolute path. Keep only operating-system,
        // locale, temporary-directory and executable-discovery values which
        // the interpreter/runtime may require. In particular, cloud tokens,
        // developer credentials and arbitrary application variables never
        // cross into third-party plugin code.
        const QStringList allowed
        {
            u"SystemRoot"_s, u"WINDIR"_s, u"COMSPEC"_s, u"PATHEXT"_s,
            u"PATH"_s, u"TEMP"_s, u"TMP"_s, u"TMPDIR"_s,
            u"LANG"_s, u"LANGUAGE"_s, u"LC_ALL"_s, u"LC_CTYPE"_s,
            u"TZ"_s, u"SSL_CERT_FILE"_s, u"SSL_CERT_DIR"_s
        };
        for (const QString &name : allowed)
        {
            if (ambient.contains(name))
                result.insert(name, ambient.value(name));
        }
        return result;
    }

    bool atomicCopyFile(const Path &source, const Path &destination, QString *error = nullptr)
    {
        QFile input {source.data()};
        if (!input.open(QIODevice::ReadOnly))
        {
            if (error)
                *error = input.errorString();
            return false;
        }

        if (const Path parent = destination.parentPath(); !parent.isEmpty())
            Utils::Fs::mkpath(parent);
        QSaveFile output {destination.data()};
        if (!output.open(QIODevice::WriteOnly))
        {
            if (error)
                *error = output.errorString();
            return false;
        }

        while (!input.atEnd())
        {
            const QByteArray chunk = input.read(64 * 1024);
            if (chunk.isEmpty() && (input.error() != QFileDevice::NoError))
            {
                if (error)
                    *error = input.errorString();
                output.cancelWriting();
                return false;
            }
            if (output.write(chunk) != chunk.size())
            {
                if (error)
                    *error = output.errorString();
                output.cancelWriting();
                return false;
            }
        }

        if (!output.commit())
        {
            if (error)
                *error = output.errorString();
            return false;
        }
        return true;
    }

    QString canonicalCatalogID(const QString &rawID, const QSet<QString> &allIDs)
    {
        static const QRegularExpression variantSuffix {u"_([2-9][0-9]*)$"_s};
        const QRegularExpressionMatch match = variantSuffix.match(rawID);
        if (!match.hasMatch())
            return rawID;

        const QString base = rawID.first(match.capturedStart());
        return allIDs.contains(base) ? base : rawID;
    }

    QByteArray fileSha256(const Path &path)
    {
        QFile file {path.data()};
        if (!file.open(QIODevice::ReadOnly))
            return {};

        QCryptographicHash hash {QCryptographicHash::Sha256};
        if (!hash.addData(&file))
            return {};
        return hash.result().toHex();
    }

    /// Remove Python bytecode cache artifacts (`__pycache__` folders and `*.pyc`
    /// files) under @p path so a freshly installed/updated plugin is picked up
    /// instead of a stale compiled copy.
    void clearPythonCache(const Path &path)
    {
        PathList dirs = {path};
        QDirIterator iter {path.data(), (QDir::AllDirs | QDir::NoDotAndDotDot), QDirIterator::Subdirectories};
        while (iter.hasNext())
            dirs += Path(iter.next());

        for (const Path &dir : asConst(dirs))
        {
            // Python 3: remove "__pycache__" folders.
            if (dir.filename() == u"__pycache__")
            {
                Utils::Fs::removeDirRecursively(dir);
                continue;
            }

            // Python 2: remove "*.pyc" files.
            QDirIterator it {dir.data(), {u"*.pyc"_s}, QDir::Files};
            while (it.hasNext())
            {
                const QString filePath = it.next();
                Utils::Fs::removeFile(Path(filePath));
            }
        }
    }
}

QPointer<SearchPluginManager> SearchPluginManager::m_instance = nullptr;

SearchPluginManager::SearchPluginManager()
    : m_updateUrl(u"https://raw.githubusercontent.com/qbittorrent/search-plugins/refs/heads/master/nova3/engines/"_s)
    , m_proxyEnv {minimalPythonEnvironment()}
{
    Q_ASSERT(!m_instance); // only one instance is allowed
    m_instance = this;

    qCInfo(lcSearch) << "Initializing search plugin manager";

    connect(Net::ProxyConfigurationManager::instance(), &Net::ProxyConfigurationManager::proxyConfigurationChanged
            , this, &SearchPluginManager::applyProxySettings);
    connect(Preferences::instance(), &Preferences::changed
            , this, &SearchPluginManager::applyProxySettings);
    applyProxySettings();

    updateNova();
    seedBundledPlugins();
    loadCatalogLedger();

    // Defer the capability probe until SearchController has connected, then run
    // Python in a separate process and consume it through asynchronous signals.
    // Parsing/reconciliation stays on the manager thread after the child exits;
    // a slow interpreter can never freeze startup.
    QTimer::singleShot(0, this, [this]
    {
        update(true, [this] { startUnofficialCatalogSync(); });
    });

    qCInfo(lcSearch) << "Search plugin manager ready; capabilities probe and verified catalog sync queued";
}

SearchPluginManager::~SearchPluginManager()
{
    qCDebug(lcSearch) << "Destroying search plugin manager; releasing" << m_plugins.size() << "plugin(s)";
    qDeleteAll(m_plugins);
}

SearchPluginManager *SearchPluginManager::instance()
{
    if (!m_instance)
        m_instance = new SearchPluginManager;
    return m_instance;
}

void SearchPluginManager::freeInstance()
{
    qCDebug(lcSearch) << "Freeing search plugin manager instance";
    delete m_instance;
}

QStringList SearchPluginManager::allPlugins() const
{
    return m_plugins.keys();
}

QVariantList SearchPluginManager::palettePluginCatalog() const
{
    // Start from the two trusted default inventories, then retain custom
    // runtime plugins as well. m_catalogEntries is replaced only after the
    // complete embedded manifest passes validation; this getter deliberately
    // never reparses JSON or treats an on-disk Python file as catalog metadata.
    QStringList ids = m_catalogCanonicalIDs;
    ids.append(m_bundledPluginIDs);
    ids.append(m_plugins.keys());
    ids.removeDuplicates();

    const auto displayName = [this](const QString &id)
    {
        const SearchPluginInfo *info = m_plugins.value(id, nullptr);
        return (info && !info->fullName.isEmpty()) ? info->fullName : id;
    };
    std::sort(ids.begin(), ids.end(), [&displayName](const QString &left, const QString &right)
    {
        return QString::localeAwareCompare(displayName(left), displayName(right)) < 0;
    });

    const QStringList seeded = Preferences::instance()->getSeededSearchPlugins();
    QVariantList result;
    result.reserve(ids.size());
    for (const QString &id : std::as_const(ids))
    {
        const auto catalogIt = m_catalogEntries.constFind(id);
        const bool catalogDefault = catalogIt != m_catalogEntries.cend();
        const bool catalogUnavailable = catalogDefault && catalogIt.value().sources.isEmpty();
        const bool bundledDefault = m_bundledPluginIDs.contains(id);
        const bool defaultPlugin = catalogDefault || bundledDefault;
        const Path activePath = pluginPath(id);
        const bool activeOnDisk = activePath.exists();
        const auto ledgerIt = m_catalogLedger.constFind(id);
        const bool hasLedger = ledgerIt != m_catalogLedger.cend();
        const CatalogLedgerEntry ledger = hasLedger ? ledgerIt.value() : CatalogLedgerEntry {};
        const Path candidatePath = (hasLedger && isSha256(ledger.expectedHash))
            ? catalogQuarantinePath(id, ledger.expectedHash) : Path {};
        const bool candidateOnDisk = !candidatePath.isEmpty() && candidatePath.exists()
            && (fileSha256(candidatePath) == ledger.observedHash)
            && (ledger.observedHash == ledger.expectedHash);
        const bool installedOnDisk = activeOnDisk || candidateOnDisk;
        const QByteArray activeHash = activeOnDisk ? fileSha256(activePath) : QByteArray {};
        const SearchPluginInfo *info = m_plugins.value(id, nullptr);
        const bool registered = (info != nullptr) && runtimeReady();
        const bool runtimeWaiting = activeOnDisk && !runtimeReady();
        const bool userRemoved = (hasLedger && ledger.userRemoved)
            || (defaultPlugin && seeded.contains(id) && !installedOnDisk);

        SearchPluginVersion version;
        if (info)
            version = info->version;
        else if (activeOnDisk)
            version = getPluginVersion(activePath);
        else if (candidateOnDisk)
            version = getPluginVersion(candidatePath);
        else if (bundledDefault)
        {
            const Path bundledPath = Path(u":/searchengine/nova3/engines"_s) / Path(id + u".py"_s);
            version = getPluginVersion(bundledPath);
        }

        QString url;
        if (info && !info->url.isEmpty())
            url = info->url;
        QString catalogSourceUrl = hasLedger ? ledger.sourceUrl : QString {};
        if (catalogSourceUrl.isEmpty() && catalogDefault && !catalogIt.value().sources.isEmpty())
            catalogSourceUrl = catalogIt.value().sources.constFirst().url;

        QString integrityState = ledger.integrityState;
        if (integrityState.isEmpty())
        {
            if (catalogDefault && activeOnDisk)
            {
                const bool current = std::ranges::any_of(catalogIt.value().sources,
                    [&activeHash](const CatalogSource &source) { return source.sha256 == activeHash; });
                integrityState = current ? u"verified-external"_s : u"user-modified"_s;
            }
            else if (activeOnDisk)
                integrityState = u"user-managed"_s;
            else if (catalogUnavailable)
                integrityState = u"unavailable"_s;
            else
                integrityState = userRemoved ? u"user-removed"_s : u"missing"_s;
        }

        QString runtimeState = ledger.runtimeState;
        if (runtimeWaiting)
            runtimeState = m_registrationStale ? u"stale-registration"_s : u"waiting-python"_s;
        else if (registered)
            runtimeState = u"ready"_s;
        else if (candidateOnDisk && runtimeState.isEmpty())
            runtimeState = u"quarantined"_s;
        else if (activeOnDisk && runtimeState.isEmpty())
            runtimeState = u"import-failed"_s;
        else if (catalogUnavailable && runtimeState.isEmpty())
            runtimeState = u"unavailable"_s;
        else if (runtimeState.isEmpty())
            runtimeState = userRemoved ? u"user-removed"_s : u"not-installed"_s;

        const bool catalogOwned = hasLedger && ledger.catalogOwned && activeOnDisk
            && isSha256(ledger.activeHash) && (activeHash == ledger.activeHash);
        const bool trusted = bundledDefault || (!catalogDefault && activeOnDisk)
            || (catalogDefault && activeOnDisk && !catalogOwned)
            || (catalogOwned && ledger.trusted);
        const bool canTrust = catalogDefault && candidateOnDisk && !userRemoved
            && (ledger.runtimeState != u"validating")
            && (!activeOnDisk || (catalogOwned && ledger.trusted))
            && (!ledger.trusted || (ledger.activeHash != ledger.expectedHash));
        QString diagnostic = ledger.diagnostic;
        if (diagnostic.isEmpty() && runtimeWaiting)
            diagnostic = m_runtimeError;
        else if (diagnostic.isEmpty() && catalogUnavailable && !activeOnDisk)
        {
            diagnostic = catalogIt.value().unavailableReason.isEmpty()
                ? tr("No verified source compatible with the bundled search runtime is available.")
                : catalogIt.value().unavailableReason;
        }

        QVariantMap item;
        item.insert(u"id"_s, id);
        item.insert(u"label"_s, displayName(id));
        item.insert(u"installedOnDisk"_s, installedOnDisk);
        item.insert(u"registered"_s, registered);
        // QML receives a stable bool, but must consult `registered` before
        // presenting it as a live setting or attempting to toggle the plugin.
        item.insert(u"enabled"_s, registered && info->enabled);
        item.insert(u"version"_s, version.isValid() ? version.toString() : QString {});
        item.insert(u"url"_s, url);
        item.insert(u"catalogSourceUrl"_s, catalogSourceUrl);
        item.insert(u"runtimeWaiting"_s, runtimeWaiting);
        item.insert(u"integrityState"_s, integrityState);
        item.insert(u"runtimeState"_s, runtimeState);
        item.insert(u"catalogOwned"_s, catalogOwned);
        item.insert(u"trusted"_s, trusted);
        item.insert(u"diagnostic"_s, diagnostic);
        item.insert(u"canTrust"_s, canTrust);
        item.insert(u"canRetry"_s, !m_catalogSyncInProgress && defaultPlugin && !userRemoved
            && (runtimeWaiting || !installedOnDisk || (!registered && !canTrust)));
        item.insert(u"canManage"_s, registered || installedOnDisk);
        item.insert(u"catalogDefault"_s, catalogDefault);
        item.insert(u"catalogUnavailable"_s, catalogUnavailable);
        item.insert(u"bundledDefault"_s, bundledDefault);
        item.insert(u"userRemoved"_s, userRemoved);
        result.append(item);
    }

    return result;
}

QStringList SearchPluginManager::enabledPlugins() const
{
    if (!runtimeReady())
        return {};
    QStringList plugins;
    for (const SearchPluginInfo *plugin : asConst(m_plugins))
    {
        if (plugin->enabled)
            plugins << plugin->name;
    }

    return plugins;
}

QStringList SearchPluginManager::supportedCategories() const
{
    QStringList result;
    for (const SearchPluginInfo *plugin : asConst(m_plugins))
    {
        if (plugin->enabled)
        {
            for (const QString &cat : plugin->supportedCategories)
            {
                if (!result.contains(cat))
                    result << cat;
            }
        }
    }

    return result;
}

QStringList SearchPluginManager::getPluginCategories(const QString &pluginName) const
{
    QStringList plugins;
    if (pluginName == u"all")
        plugins = allPlugins();
    else if ((pluginName == u"enabled") || (pluginName == u"multi"))
        plugins = enabledPlugins();
    else
        plugins << pluginName.trimmed();

    QSet<QString> categories;
    for (const QString &name : asConst(plugins))
    {
        const SearchPluginInfo *plugin = pluginInfo(name);
        if (!plugin)
            continue; // plugin wasn't found
        for (const QString &category : plugin->supportedCategories)
            categories << category;
    }

    return categories.values();
}

SearchPluginInfo *SearchPluginManager::pluginInfo(const QString &name) const
{
    return m_plugins.value(name);
}

QString SearchPluginManager::pluginNameBySiteURL(const QString &siteURL) const
{
    for (const SearchPluginInfo *plugin : asConst(m_plugins))
    {
        if (plugin->url == siteURL)
            return plugin->name;
    }

    return {};
}

void SearchPluginManager::enablePlugin(const QString &name, const bool enabled)
{
    SearchPluginInfo *plugin = m_plugins.value(name, nullptr);
    if (!plugin)
    {
        qCWarning(lcSearch) << "Cannot enable/disable unknown search plugin:" << name;
        return;
    }

    plugin->enabled = enabled;

    // Persist the disabled-plugins list.
    Preferences *const pref = Preferences::instance();
    QStringList disabledPlugins = pref->getSearchEngDisabled();
    if (enabled)
        disabledPlugins.removeAll(name);
    else if (!disabledPlugins.contains(name))
        disabledPlugins.append(name);
    pref->setSearchEngDisabled(disabledPlugins);

    qCInfo(lcSearch) << "Search plugin" << name << (enabled ? "enabled" : "disabled");
    emit pluginEnabled(name, enabled);
}

// Updates a shipped plugin from the update server.
void SearchPluginManager::updatePlugin(const QString &name)
{
    qCInfo(lcSearch) << "Updating search plugin from update server:" << name;
    installPlugin(u"%1%2.py"_s.arg(m_updateUrl, name));
}

// Install or update a plugin from a file path or a URL.
void SearchPluginManager::installPlugin(const QString &source)
{
    qCInfo(lcSearch).noquote() << QStringLiteral("Installing search plugin from source: \"%1\"").arg(source);

    clearPythonCache(engineLocation());

    if (Net::DownloadManager::hasSupportedScheme(source))
    {
        using namespace Net;
        qCDebug(lcSearch) << "Plugin source is a remote URL; downloading" << source;
        DownloadManager::instance()->download(DownloadRequest(source).saveToFile(true)
                , Preferences::instance()->useProxyForGeneralPurposes()
                , this, &SearchPluginManager::pluginDownloadFinished);
    }
    else
    {
        const Path path {source.startsWith(u"file:", Qt::CaseInsensitive) ? QUrl(source).toLocalFile() : source};
        if (const QString pyExt = u".py"_s; path.hasExtension(pyExt))
        {
            installPlugin_impl(path.removedExtension(pyExt).filename(), path);
        }
        else
        {
            qCWarning(lcSearch).noquote() << tr("Unknown search engine plugin file format.");
            emit pluginInstallationFailed(path.filename(), tr("Unknown search engine plugin file format."));
        }
    }
}

void SearchPluginManager::installPlugin_impl(const QString &name, const Path &srcPath)
{
    const SearchPluginVersion incomingVersion = getPluginVersion(srcPath);
    const SearchPluginInfo *plugin = pluginInfo(name);
    if (plugin && (plugin->version >= incomingVersion))
    {
        qCInfo(lcSearch).noquote() << tr("Same or newer version of search plugin is already installed. Plugin name: \"%1\". Current version: %2. Incoming version: %3")
            .arg(plugin->name, plugin->version.toString(), incomingVersion.toString());
        emit pluginUpdateFailed(name, tr("A more recent version of this plugin is already installed."));
        return;
    }

    // Proceed to install.
    const Path destPath = pluginPath(name);
    const Path backupPath = destPath + u".bak";
    const bool hasExistingPlugin = destPath.exists();
    bool hasBackup = false;

    const bool copiedIntoDestination = (destPath != srcPath);
    if (copiedIntoDestination)
    {
        // Plugin is not already at the destination path, otherwise there is nothing to copy.

        // Backup in case the install fails.
        if (hasExistingPlugin)
        {
            hasBackup = Utils::Fs::copyFile(destPath, backupPath);
            qCDebug(lcSearch) << "Backed up existing plugin" << name << "->" << backupPath.toString() << "success:" << hasBackup;
            if (!hasBackup)
            {
                const QString errMsg = tr("The existing plugin could not be backed up, so the update was cancelled without changing it.");
                qCWarning(lcSearch).noquote() << QStringLiteral("%1 Plugin name: \"%2\".").arg(errMsg, name);
                emit pluginUpdateFailed(name, errMsg);
                return;
            }
            Utils::Fs::removeFile(destPath);
        }

        // Copy the plugin to the destination path.
        if (!Utils::Fs::copyFile(srcPath, destPath))
        {
            // Roll back.
            Utils::Fs::removeFile(destPath);
            if (hasBackup)
            {
                // Restore backup.
                if (Utils::Fs::copyFile(backupPath, destPath))
                    Utils::Fs::removeFile(backupPath);
                else
                    Utils::Fs::removeFile(destPath);
            }

            const QString errMsg = tr("Search plugin installation failed.");
            qCWarning(lcSearch).noquote() << QStringLiteral("%1 Plugin name: \"%2\".").arg(errMsg, name);
            if (hasExistingPlugin)
                emit pluginUpdateFailed(name, errMsg);
            else
                emit pluginInstallationFailed(name, errMsg);

            return;
        }
    }

    // Validate asynchronously without leaking an optimistic install/update
    // signal before the post-copy check and rollback decision.
    update(true, [this, name, incomingVersion, destPath, backupPath,
                  hasExistingPlugin, hasBackup, copiedIntoDestination]
    {
        if (m_plugins.contains(name))
        {
            qCInfo(lcSearch).noquote() << tr("Search plugin has been updated. Plugin name: \"%1\". Version: %2.")
                .arg(name, incomingVersion.toString());
            if (hasBackup)
                Utils::Fs::removeFile(backupPath);
            if (hasExistingPlugin)
                emit pluginUpdated(name);
            else
                emit pluginInstalled(name);
            return;
        }

        qCWarning(lcSearch).noquote() << tr("Search plugin installation failed. Plugin name: \"%1\"").arg(name);
        const QString importDiagnostic = m_pluginImportErrors.value(name);
        const QString runtimeDiagnostic = m_runtimeError;
        const QString errMsg = !runtimeDiagnostic.isEmpty()
            ? runtimeDiagnostic
            : (!importDiagnostic.isEmpty()
                ? tr("The plugin failed to import: %1").arg(importDiagnostic)
                : tr("The runtime did not register an engine named \"%1\". The Python class name must match the file name.").arg(name));

        if (copiedIntoDestination)
            Utils::Fs::removeFile(destPath);

        const auto reportFailure = [this, name, hasExistingPlugin, errMsg]
        {
            if (hasExistingPlugin)
                emit pluginUpdateFailed(name, errMsg);
            else
                emit pluginInstallationFailed(name, errMsg);
        };

        if (!hasBackup)
        {
            reportFailure();
            return;
        }

        if (!Utils::Fs::copyFile(backupPath, destPath))
        {
            Utils::Fs::removeFile(destPath);
            reportFailure();
            return;
        }

        Utils::Fs::removeFile(backupPath);
        update(true, reportFailure); // Reconcile the restored plugin silently.
    });
}

bool SearchPluginManager::uninstallPlugin(const QString &name)
{
    qCInfo(lcSearch) << "Uninstalling search plugin:" << name;

    clearPythonCache(engineLocation());

    // Remove it from the hard drive (the .py plus any icon files).
    QDirIterator iter {pluginsLocation().data(), {name + u".*"}, QDir::Files};
    while (iter.hasNext())
    {
        const QString filePath = iter.next();
        qCDebug(lcSearch) << "Removing plugin file:" << filePath;
        Utils::Fs::removeFile(Path(filePath));
    }

    // Remove it from the supported engines.
    delete m_plugins.take(name);

    auto ledgerIt = m_catalogLedger.find(name);
    if (ledgerIt != m_catalogLedger.end())
    {
        CatalogLedgerEntry &state = ledgerIt.value();
        const Path candidatePath = catalogQuarantinePath(name, state.expectedHash);
        if (!candidatePath.isEmpty() && candidatePath.exists()
            && (state.expectedHash == state.observedHash)
            && (fileSha256(candidatePath) == state.expectedHash))
        {
            Utils::Fs::removeFile(candidatePath);
        }
        state.activeHash.clear();
        state.catalogOwned = false;
        state.trusted = false;
        state.userRemoved = true;
        state.integrityState = u"user-removed"_s;
        state.runtimeState = u"user-removed"_s;
        state.diagnostic = tr("The default plugin was removed by the user and will not be restored automatically.");
        state.generation += 1;
        saveCatalogLedger();
    }

    qCInfo(lcSearch) << "Search plugin uninstalled:" << name;
    emit pluginCatalogChanged();
    emit pluginUninstalled(name);
    return true;
}

void SearchPluginManager::updateIconPath(SearchPluginInfo *const plugin)
{
    if (!plugin)
        return;

    const Path pluginsPath = pluginsLocation();
    Path iconPath = pluginsPath / Path(plugin->name + u".png");
    if (iconPath.exists())
    {
        plugin->iconPath = iconPath;
    }
    else
    {
        iconPath = pluginsPath / Path(plugin->name + u".ico");
        if (iconPath.exists())
            plugin->iconPath = iconPath;
    }
}

void SearchPluginManager::checkForUpdates()
{
    qCInfo(lcSearch) << "Checking for search plugin updates from" << (m_updateUrl + u"versions.txt");

    // Download the version file from the update server.
    using namespace Net;
    DownloadManager::instance()->download(DownloadRequest(m_updateUrl + u"versions.txt").limit(MAX_PLUGIN_VERSION_INFO_BYTES)
            , Preferences::instance()->useProxyForGeneralPurposes()
            , this, &SearchPluginManager::versionInfoDownloadFinished);
}

SearchDownloadHandler *SearchPluginManager::downloadTorrent(const QString &pluginName, const QString &url)
{
    qCInfo(lcSearch).noquote() << QStringLiteral("Downloading torrent via plugin \"%1\": %2").arg(pluginName, url);
    return new SearchDownloadHandler(pluginName, url, this);
}

SearchHandler *SearchPluginManager::startSearch(const QString &pattern, const QString &category, const QStringList &usedPlugins)
{
    // No search pattern entered.
    Q_ASSERT(!pattern.isEmpty());
    if (!runtimeReady())
    {
        qCWarning(lcSearch) << "Refusing to start a search against a stale or failed plugin registry";
        return nullptr;
    }

    qCInfo(lcSearch).noquote() << QStringLiteral("startSearch. Pattern: \"%1\". Category: \"%2\". Plugins: \"%3\".")
        .arg(pattern, category, usedPlugins.join(u", "_s));
    return new SearchHandler(pattern, category, usedPlugins, this);
}

QProcessEnvironment SearchPluginManager::proxyEnvironment() const
{
    return m_proxyEnv;
}

QString SearchPluginManager::categoryFullName(const QString &categoryName)
{
    const QHash<QString, QString> categoryTable
    {
        {u"all"_s, tr("All categories")},
        {u"anime"_s, tr("Anime")},
        {u"books"_s, tr("Books")},
        {u"games"_s, tr("Games")},
        {u"movies"_s, tr("Movies")},
        {u"music"_s, tr("Music")},
        {u"pictures"_s, tr("Pictures")},
        {u"software"_s, tr("Software")},
        {u"tv"_s, tr("TV shows")}
    };
    return categoryTable.value(categoryName);
}

QString SearchPluginManager::pluginFullName(const QString &pluginName) const
{
    return pluginInfo(pluginName) ? pluginInfo(pluginName)->fullName : QString();
}

Path SearchPluginManager::pluginsLocation()
{
    return (engineLocation() / Path(u"engines"_s));
}

Path SearchPluginManager::engineLocation()
{
    static Path location;
    if (location.isEmpty())
    {
        location = specialFolderLocation(SpecialFolder::Data) / Path(u"nova3"_s);
        Utils::Fs::mkpath(location);
        qCDebug(lcSearch) << "Search engine location:" << location.toString();
    }

    return location;
}

Path SearchPluginManager::catalogQuarantineLocation()
{
    const Path location = engineLocation() / Path(u"catalog-quarantine"_s);
    Utils::Fs::mkpath(location);
    return location;
}

Path SearchPluginManager::catalogQuarantinePath(const QString &name, const QByteArray &sha256)
{
    if (!isSafeCatalogID(name) || !isSha256(sha256))
        return {};
    return catalogQuarantineLocation() / Path(u"%1-%2.py"_s.arg(name, QString::fromLatin1(sha256)));
}

Path SearchPluginManager::catalogLedgerPath()
{
    return engineLocation() / Path(u"unofficial-catalog-state.json"_s);
}

void SearchPluginManager::loadCatalogLedger()
{
    m_catalogLedger.clear();
    QFile file {catalogLedgerPath().data()};
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly))
    {
        qCWarning(lcSearch) << "Could not open unofficial catalog state:" << file.errorString();
        return;
    }

    const QByteArray bytes = file.read(MAX_CATALOG_LEDGER_BYTES + 1);
    if (bytes.size() > MAX_CATALOG_LEDGER_BYTES)
    {
        qCWarning(lcSearch) << "Unofficial catalog state exceeds its safety limit; preserving the file and ignoring it";
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
    if ((parseError.error != QJsonParseError::NoError) || !document.isObject()
        || (document.object().value(u"schema"_s).toInt() != CATALOG_LEDGER_SCHEMA)
        || !document.object().value(u"entries"_s).isArray())
    {
        qCWarning(lcSearch) << "Unofficial catalog state is invalid; preserving the file and ignoring it:" << parseError.errorString();
        return;
    }

    QSet<QString> seen;
    for (const QJsonValue &value : document.object().value(u"entries"_s).toArray())
    {
        if (!value.isObject())
            continue;
        const QJsonObject object = value.toObject();
        const QString id = object.value(u"id"_s).toString();
        const QByteArray expected = object.value(u"expectedHash"_s).toString().toLatin1().toLower();
        const QByteArray observed = object.value(u"observedHash"_s).toString().toLatin1().toLower();
        const QByteArray active = object.value(u"activeHash"_s).toString().toLatin1().toLower();
        const QUrl source {object.value(u"sourceUrl"_s).toString()};
        if (!isSafeCatalogID(id) || seen.contains(id)
            || (!expected.isEmpty() && !isSha256(expected))
            || (!observed.isEmpty() && !isSha256(observed))
            || (!active.isEmpty() && !isSha256(active))
            || (!source.isEmpty() && (!source.isValid() || (source.scheme() != u"https")
                || source.host().isEmpty() || !source.userInfo().isEmpty())))
        {
            qCWarning(lcSearch) << "Ignoring unsafe unofficial catalog state row:" << id;
            continue;
        }

        bool generationOK = false;
        const quint64 generation = object.value(u"generation"_s).toString().toULongLong(&generationOK);
        CatalogLedgerEntry entry;
        entry.expectedHash = expected;
        entry.observedHash = observed;
        entry.activeHash = active;
        entry.sourceUrl = source.toString();
        entry.integrityState = object.value(u"integrityState"_s).toString().left(64);
        entry.runtimeState = object.value(u"runtimeState"_s).toString().left(64);
        entry.diagnostic = object.value(u"diagnostic"_s).toString().left(4096);
        entry.generation = generationOK ? generation : 0;
        entry.catalogOwned = object.value(u"catalogOwned"_s).toBool(false);
        entry.trusted = object.value(u"trusted"_s).toBool(false);
        entry.userRemoved = object.value(u"userRemoved"_s).toBool(false);
        m_catalogLedger.insert(id, entry);
        seen.insert(id);
    }
    qCInfo(lcSearch) << "Loaded" << m_catalogLedger.size() << "unofficial catalog state row(s)";
}

bool SearchPluginManager::saveCatalogLedger()
{
    QStringList ids = m_catalogLedger.keys();
    ids.sort();
    QJsonArray rows;
    for (const QString &id : std::as_const(ids))
    {
        const CatalogLedgerEntry &entry = m_catalogLedger[id];
        QJsonObject object;
        object.insert(u"id"_s, id);
        object.insert(u"expectedHash"_s, QString::fromLatin1(entry.expectedHash));
        object.insert(u"observedHash"_s, QString::fromLatin1(entry.observedHash));
        object.insert(u"activeHash"_s, QString::fromLatin1(entry.activeHash));
        object.insert(u"sourceUrl"_s, entry.sourceUrl);
        object.insert(u"integrityState"_s, entry.integrityState);
        object.insert(u"runtimeState"_s, entry.runtimeState);
        object.insert(u"diagnostic"_s, entry.diagnostic.left(4096));
        object.insert(u"generation"_s, QString::number(entry.generation));
        object.insert(u"catalogOwned"_s, entry.catalogOwned);
        object.insert(u"trusted"_s, entry.trusted);
        object.insert(u"userRemoved"_s, entry.userRemoved);
        rows.append(object);
    }

    QJsonObject root;
    root.insert(u"schema"_s, CATALOG_LEDGER_SCHEMA);
    root.insert(u"entries"_s, rows);
    const auto result = Utils::IO::saveToFile(catalogLedgerPath(), QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!result)
    {
        qCWarning(lcSearch) << "Could not persist unofficial catalog state:" << result.error();
        return false;
    }
    return true;
}

void SearchPluginManager::applyProxySettings()
{
    // For python `urllib`: https://docs.python.org/3/library/urllib.request.html#urllib.request.ProxyHandler
    const QString HTTP_PROXY = u"http_proxy"_s;
    const QString HTTPS_PROXY = u"https_proxy"_s;
    // For `helpers.setupSOCKSProxy()`: https://everything.curl.dev/usingcurl/proxies/socks.html
    const QString SOCKS_PROXY = u"qbt_socks_proxy"_s;

    if (!Preferences::instance()->useProxyForGeneralPurposes())
    {
        qCDebug(lcSearch) << "Proxy disabled for general purposes; clearing search proxy environment";
        m_proxyEnv.remove(HTTP_PROXY);
        m_proxyEnv.remove(HTTPS_PROXY);
        m_proxyEnv.remove(SOCKS_PROXY);
        return;
    }

    const Net::ProxyConfiguration proxyConfig = Net::ProxyConfigurationManager::instance()->proxyConfiguration();
    switch (proxyConfig.type)
    {
    case Net::ProxyType::None:
        qCDebug(lcSearch) << "Proxy type None; clearing search proxy environment";
        m_proxyEnv.remove(HTTP_PROXY);
        m_proxyEnv.remove(HTTPS_PROXY);
        m_proxyEnv.remove(SOCKS_PROXY);
        break;

    case Net::ProxyType::HTTP:
        {
            // Never place proxy credentials in a child-process environment:
            // every search engine is third-party Python and can read os.environ.
            // An authenticated proxy therefore needs a future native broker;
            // the child receives only the non-secret endpoint today.
            const QString proxyURL = u"http://%1:%2"_s
                .arg(proxyConfig.ip, QString::number(proxyConfig.port));

            m_proxyEnv.insert(HTTP_PROXY, proxyURL);
            m_proxyEnv.insert(HTTPS_PROXY, proxyURL);
            m_proxyEnv.remove(SOCKS_PROXY);
            qCDebug(lcSearch) << "Applied HTTP proxy to search environment:" << proxyConfig.ip << proxyConfig.port;
            if (proxyConfig.authEnabled)
                qCWarning(lcSearch) << "Search plugins receive no proxy credentials; authenticated proxy access requires a native credential broker";
        }
        break;

    case Net::ProxyType::SOCKS5:
        {
            const QString scheme = proxyConfig.hostnameLookupEnabled ? u"socks5h"_s : u"socks5"_s;
            const QString proxyURL = u"%1://%2:%3"_s
                .arg(scheme, proxyConfig.ip, QString::number(proxyConfig.port));

            m_proxyEnv.remove(HTTP_PROXY);
            m_proxyEnv.remove(HTTPS_PROXY);
            m_proxyEnv.insert(SOCKS_PROXY, proxyURL);
            qCDebug(lcSearch) << "Applied SOCKS5 proxy to search environment:" << proxyConfig.ip << proxyConfig.port;
            if (proxyConfig.authEnabled)
                qCWarning(lcSearch) << "Search plugins receive no proxy credentials; authenticated proxy access requires a native credential broker";
        }
        break;

    case Net::ProxyType::SOCKS4:
        {
            const QString scheme = proxyConfig.hostnameLookupEnabled ? u"socks4a"_s : u"socks4"_s;
            const QString proxyURL = u"%1://%2:%3"_s
                .arg(scheme, proxyConfig.ip, QString::number(proxyConfig.port));

            m_proxyEnv.remove(HTTP_PROXY);
            m_proxyEnv.remove(HTTPS_PROXY);
            m_proxyEnv.insert(SOCKS_PROXY, proxyURL);
            qCDebug(lcSearch) << "Applied SOCKS4 proxy to search environment:" << proxyConfig.ip << proxyConfig.port;
        }
        break;
    }
}

void SearchPluginManager::versionInfoDownloadFinished(const Net::DownloadResult &result)
{
    if (result.status == Net::DownloadStatus::Success)
    {
        qCDebug(lcSearch) << "Fetched plugin version info," << result.data.size() << "bytes; parsing";
        parseVersionInfo(result.data);
    }
    else
    {
        qCWarning(lcSearch).noquote() << tr("Update server is temporarily unavailable. %1").arg(result.errorString);
        emit checkForUpdatesFailed(tr("Update server is temporarily unavailable. %1").arg(result.errorString));
    }
}

void SearchPluginManager::pluginDownloadFinished(const Net::DownloadResult &result)
{
    if (result.status == Net::DownloadStatus::Success)
    {
        const Path filePath = result.filePath;

        const auto downloadedPluginPath = Path(QUrl(result.url).path()).removedExtension();
        qCDebug(lcSearch) << "Plugin file downloaded to" << filePath.toString()
            << "for plugin" << downloadedPluginPath.filename();
        installPlugin_impl(downloadedPluginPath.filename(), filePath);
        Utils::Fs::removeFile(filePath);
    }
    else
    {
        const QString &url = result.url;
        const QString pluginName = url.sliced(url.lastIndexOf(u'/') + 1)
            .replace(u".py"_s, u""_s, Qt::CaseInsensitive);

        qCWarning(lcSearch).noquote() << tr("Failed to download the plugin file. %1").arg(result.errorString);
        if (pluginInfo(pluginName))
            emit pluginUpdateFailed(pluginName, tr("Failed to download the plugin file. %1").arg(result.errorString));
        else
            emit pluginInstallationFailed(pluginName, tr("Failed to download the plugin file. %1").arg(result.errorString));
    }
}

// Update the bundled nova.py runtime files on disk if newer versions are shipped.
void SearchPluginManager::updateNova()
{
    qCDebug(lcSearch) << "Updating bundled nova search runtime";

    // Create the nova directory (and its Python package markers) if necessary.
    const Path enginePath = engineLocation();

    QFile packageFile {(enginePath / Path(u"__init__.py"_s)).data()};
    if (packageFile.open(QIODevice::WriteOnly))
        packageFile.close();

    Utils::Fs::mkdir(enginePath / Path(u"engines"_s));

    QFile packageFile2 {(enginePath / Path(u"engines/__init__.py"_s)).data()};
    if (packageFile2.open(QIODevice::WriteOnly))
        packageFile2.close();

    // Copy the bundled search-plugin runtime files (only if newer than on disk).
    const auto updateFile = [&enginePath](const Path &filename)
    {
        const Path filePathBundled = Path(u":/searchengine/nova3"_s) / filename;
        const Path filePathDisk = enginePath / filename;

        if (!filePathBundled.exists())
        {
            // The build did not embed the nova runtime. Every search and every
            // plugin install will fail; say so once, here, where it is provable.
            qCCritical(lcSearch).noquote() << QStringLiteral("Bundled search runtime file is missing from the application resources: %1")
                .arg(filePathBundled.toString());
            return;
        }

        if (getPluginVersion(filePathBundled) <= getPluginVersion(filePathDisk))
            return;

        qCDebug(lcSearch) << "Updating bundled nova file on disk:" << filename.toString();
        Utils::Fs::removeFile(filePathDisk);
        if (!Utils::Fs::copyFile(filePathBundled, filePathDisk))
        {
            qCWarning(lcSearch).noquote() << QStringLiteral("Could not extract the search runtime file %1 to %2")
                .arg(filename.toString(), filePathDisk.toString());
        }
    };

    updateFile(Path(u"helpers.py"_s));
    updateFile(Path(u"nova2.py"_s));
    updateFile(Path(u"nova2dl.py"_s));
    updateFile(Path(u"novaprinter.py"_s));
    updateFile(Path(u"socks.py"_s));
}

QString SearchPluginManager::runtimeError() const
{
    return m_runtimeError;
}

bool SearchPluginManager::runtimeReady() const
{
    return !m_registrationStale && m_runtimeError.isEmpty();
}

QVariantMap SearchPluginManager::unofficialCatalogStatus() const
{
    return m_catalogStatus;
}

void SearchPluginManager::retryUnofficialCatalogSync()
{
    if (m_catalogSyncInProgress)
    {
        m_catalogRetryPending = true;
        return;
    }
    if (m_catalogRetryPending)
        return;

    qCInfo(lcSearch) << "Retrying verified unofficial search-plugin sync on request";
    m_catalogRetryPending = true;
    m_catalogStatus[u"state"_s] = u"probing-runtime"_s;
    m_catalogStatus[u"inProgress"_s] = true;
    emit unofficialCatalogStatusChanged(m_catalogStatus);
    // The automatic detector intentionally caches a missing interpreter to
    // avoid repeated synchronous PATH probes. A user-triggered retry is the
    // explicit recovery point after Python may have been installed.
    Utils::ForeignApps::resetAutomaticPythonDetection();
    update(true, [this]
    {
        m_catalogRetryPending = false;
        startUnofficialCatalogSync();
    });
}

void SearchPluginManager::trustUnofficialPlugin(const QString &id)
{
    const auto failWithoutMutation = [this, &id](const QString &reason, const QString &runtimeState,
                                                  const QString &integrityState)
    {
        auto it = m_catalogLedger.find(id);
        if (it != m_catalogLedger.end())
        {
            it->runtimeState = runtimeState;
            it->integrityState = integrityState;
            it->diagnostic = reason;
            saveCatalogLedger();
        }
        qCWarning(lcSearch).noquote() << QStringLiteral("Could not trust unofficial plugin \"%1\": %2").arg(id, reason);
        emit pluginCatalogChanged();
        emit unofficialPluginTrustFailed(id, reason);
    };

    if (!isSafeCatalogID(id) || !m_catalogEntries.contains(id))
    {
        failWithoutMutation(tr("The requested plugin is not in the validated unofficial catalog."),
            u"not-installed"_s, u"invalid-request"_s);
        return;
    }
    if (m_catalogSyncInProgress)
    {
        failWithoutMutation(tr("The catalog is still synchronizing. Retry trust after the current sync finishes."),
            u"quarantined"_s, u"pending-trust"_s);
        return;
    }

    auto ledgerIt = m_catalogLedger.find(id);
    if (ledgerIt == m_catalogLedger.end())
    {
        failWithoutMutation(tr("No persisted trust record exists for this catalog plugin."),
            u"not-installed"_s, u"missing"_s);
        return;
    }

    CatalogLedgerEntry &state = ledgerIt.value();
    if (state.runtimeState == u"validating")
    {
        failWithoutMutation(tr("This plugin is already being validated."),
            u"validating"_s, state.integrityState);
        return;
    }

    const CatalogEntry catalogEntry = m_catalogEntries.value(id);
    const bool pinStillCurrent = std::ranges::any_of(catalogEntry.sources,
        [&state](const CatalogSource &source)
        {
            return (source.sha256 == state.expectedHash) && (source.url == state.sourceUrl);
        });
    const Path candidatePath = catalogQuarantinePath(id, state.expectedHash);
    const QByteArray candidateHash = candidatePath.exists() ? fileSha256(candidatePath) : QByteArray {};
    if (!pinStillCurrent || !isSha256(state.expectedHash)
        || (state.expectedHash != state.observedHash) || (candidateHash != state.expectedHash))
    {
        failWithoutMutation(tr("The quarantined file no longer matches its current expected and observed SHA-256 values."),
            u"quarantined"_s, u"integrity-failed"_s);
        return;
    }

    const Utils::ForeignApps::PythonInfo pyInfo = Utils::ForeignApps::pythonInfo();
    if (!pyInfo.isValid() || !pyInfo.isSupportedVersion())
    {
        const QString reason = tr("Python %1 or later is required before a quarantined plugin can be validated.")
            .arg(Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
        failWithoutMutation(reason, u"waiting-python"_s, u"pending-trust"_s);
        return;
    }

    const Path activePath = pluginPath(id);
    const bool hadActive = activePath.exists();
    const QByteArray previousActiveHash = hadActive ? fileSha256(activePath) : QByteArray {};
    if (hadActive && (!state.catalogOwned || !state.trusted || !isSha256(state.activeHash)
        || (previousActiveHash != state.activeHash)))
    {
        failWithoutMutation(tr("A user-managed active file is present. It was preserved; remove it explicitly before trusting the catalog file."),
            runtimeReady() ? u"ready"_s : u"stale-registration"_s, u"user-modified"_s);
        return;
    }

    const quint64 generation = state.generation + 1;
    const Path backupPath = hadActive
        ? (catalogQuarantineLocation() / Path(u"%1-active-backup-%2-%3.py"_s
            .arg(id, QString::number(generation), QString::fromLatin1(previousActiveHash))))
        : Path {};
    state.generation = generation;
    state.runtimeState = u"validating"_s;
    state.integrityState = hadActive ? u"validating-update"_s : u"validating"_s;
    state.diagnostic = tr("Validating the quarantined plugin in an isolated Python capability probe.");
    state.userRemoved = false;
    if (!saveCatalogLedger())
    {
        failWithoutMutation(tr("The trust generation could not be persisted, so the active file was not changed."),
            u"quarantined"_s, u"ledger-write-failed"_s);
        return;
    }

    if (hadActive)
    {
        if (backupPath.exists())
        {
            failWithoutMutation(tr("A transaction backup already exists. It was preserved and the active file was not changed."),
                u"quarantined"_s, u"transaction-conflict"_s);
            return;
        }
        QString backupError;
        if (!atomicCopyFile(activePath, backupPath, &backupError)
            || (fileSha256(backupPath) != previousActiveHash))
        {
            failWithoutMutation(tr("The trusted active plugin could not be backed up: %1").arg(backupError),
                u"quarantined"_s, u"backup-failed"_s);
            return;
        }
    }

    QString promotionError;
    if (!atomicCopyFile(candidatePath, activePath, &promotionError)
        || (fileSha256(activePath) != candidateHash))
    {
        failWithoutMutation(tr("The quarantined plugin could not be promoted atomically: %1").arg(promotionError),
            u"quarantined"_s, u"promotion-failed"_s);
        return;
    }

    clearPythonCache(engineLocation());
    update(true, [this, id, generation, candidateHash, previousActiveHash, backupPath, hadActive]
    {
        auto currentIt = m_catalogLedger.find(id);
        if (currentIt == m_catalogLedger.end() || (currentIt->generation != generation))
        {
            const QString reason = tr("The trust transaction generation changed while validation was running; no rollback was attempted.");
            emit unofficialPluginTrustFailed(id, reason);
            return;
        }

        CatalogLedgerEntry &current = currentIt.value();
        const Path currentActivePath = pluginPath(id);
        const QByteArray currentActiveHash = currentActivePath.exists() ? fileSha256(currentActivePath) : QByteArray {};
        if (currentActiveHash != candidateHash)
        {
            // A manual replacement won the race. The generation and hash guard
            // deliberately runs before every rollback copy or deletion below.
            current.catalogOwned = false;
            current.trusted = false;
            current.activeHash.clear();
            current.integrityState = u"user-modified"_s;
            current.runtimeState = u"transaction-conflict"_s;
            current.diagnostic = tr("The active file changed during validation. It was preserved and no rollback was attempted.");
            saveCatalogLedger();
            emit pluginCatalogChanged();
            emit unofficialPluginTrustFailed(id, current.diagnostic);
            return;
        }

        if (runtimeReady() && m_plugins.contains(id))
        {
            current.activeHash = candidateHash;
            current.catalogOwned = true;
            current.trusted = true;
            current.userRemoved = false;
            current.integrityState = u"verified-current"_s;
            current.runtimeState = u"ready"_s;
            current.diagnostic.clear();
            if (!saveCatalogLedger())
            {
                current.diagnostic = tr("The plugin validated, but its trust ledger could not be persisted. Recovery files were preserved.");
                emit pluginCatalogChanged();
                emit unofficialPluginTrustFailed(id, current.diagnostic);
                return;
            }

            const Path candidate = catalogQuarantinePath(id, candidateHash);
            if (candidate.exists() && (fileSha256(candidate) == candidateHash))
                Utils::Fs::removeFile(candidate);
            if (hadActive && backupPath.exists() && (fileSha256(backupPath) == previousActiveHash))
                Utils::Fs::removeFile(backupPath);

            QStringList seeded = Preferences::instance()->getSeededSearchPlugins();
            if (!seeded.contains(id))
            {
                seeded.append(id);
                seeded.sort();
                Preferences::instance()->setSeededSearchPlugins(seeded);
            }
            emit pluginCatalogChanged();
            if (hadActive)
                emit pluginUpdated(id);
            else
                emit pluginInstalled(id);
            emit unofficialPluginTrusted(id);
            return;
        }

        const QString importDiagnostic = m_pluginImportErrors.value(id);
        QString reason = !m_runtimeError.isEmpty()
            ? m_runtimeError
            : (!importDiagnostic.isEmpty()
                ? tr("The plugin failed to import: %1").arg(importDiagnostic)
                : tr("The runtime did not register an engine named \"%1\".").arg(id));

        bool rolledBack = false;
        if (hadActive && backupPath.exists() && (fileSha256(backupPath) == previousActiveHash))
        {
            QString restoreError;
            rolledBack = atomicCopyFile(backupPath, currentActivePath, &restoreError)
                && (fileSha256(currentActivePath) == previousActiveHash);
            if (!rolledBack)
                reason += tr(" The prior verified file could not be restored: %1").arg(restoreError);
        }
        else if (!hadActive)
        {
            // This exact active file is transaction-owned and still guarded by
            // candidateHash, so removing it cannot delete a manual replacement.
            const auto removeResult = Utils::Fs::removeFile(currentActivePath);
            rolledBack = static_cast<bool>(removeResult);
        }

        if (!rolledBack && currentActivePath.exists() && (fileSha256(currentActivePath) == candidateHash))
        {
            // A missing/tampered backup must not leave failed third-party code
            // active on the next launch. Only the exact transaction bytes are
            // removed; an independently changed file was handled above.
            Utils::Fs::removeFile(currentActivePath);
            reason += tr(" The prior file was unavailable, so the failed transaction bytes were removed from the active engine directory.");
        }
        if (rolledBack && hadActive && backupPath.exists() && (fileSha256(backupPath) == previousActiveHash))
            Utils::Fs::removeFile(backupPath);

        current.catalogOwned = hadActive && rolledBack;
        current.trusted = hadActive && rolledBack;
        current.activeHash = (hadActive && rolledBack) ? previousActiveHash : QByteArray {};
        current.integrityState = u"verification-failed"_s;
        current.runtimeState = runtimeReady() ? u"import-failed"_s : u"stale-registration"_s;
        current.diagnostic = reason;
        saveCatalogLedger();
        clearPythonCache(engineLocation());
        update(true);
        emit pluginCatalogChanged();
        emit unofficialPluginTrustFailed(id, reason);
    });
}

void SearchPluginManager::reload()
{
    qCInfo(lcSearch) << "Reloading the search runtime on request";
    updateNova();
    update();
}

void SearchPluginManager::setRuntimeError(const QString &reason)
{
    if (m_runtimeError == reason)
        return;

    m_runtimeError = reason;
    emit runtimeErrorChanged(reason);
}

void SearchPluginManager::failCapabilityGeneration(const QString &reason)
{
    m_registrationStale = true;
    setRuntimeError(reason);
    emit pluginCatalogChanged();
}

// Write the plugins bundled in our own resources into the profile, so the
// Search tab has sources without the user having to install anything.
void SearchPluginManager::seedBundledPlugins()
{
    const Path bundledDir {u":/searchengine/nova3/engines"_s};
    QDirIterator it {bundledDir.data(), {u"*.py"_s}, QDir::Files};
    m_bundledPluginIDs.clear();
    if (!it.hasNext())
    {
        qCCritical(lcSearch) << "No bundled search plugins found in the application resources";
        return;
    }

    QStringList seeded = Preferences::instance()->getSeededSearchPlugins();
    const QStringList alreadySeeded = seeded;
    int written = 0;

    while (it.hasNext())
    {
        const Path bundledPath {it.next()};
        const QString name = bundledPath.removedExtension().filename();
        m_bundledPluginIDs.append(name);
        const Path diskPath = pluginPath(name);

        if (!diskPath.exists())
        {
            // Absent because the user removed it, not because this is a fresh
            // profile — leave it alone. Uninstalling a bundled plugin must stick.
            if (alreadySeeded.contains(name))
                continue;
        }
        else if (getPluginVersion(bundledPath) <= getPluginVersion(diskPath))
        {
            // Never downgrade a plugin the user updated from the upstream feed.
            if (!seeded.contains(name))
                seeded.append(name);
            continue;
        }

        Utils::Fs::removeFile(diskPath);
        if (Utils::Fs::copyFile(bundledPath, diskPath))
        {
            ++written;
            qCInfo(lcSearch).noquote() << QStringLiteral("Seeded bundled search plugin \"%1\" version %2")
                .arg(name, getPluginVersion(bundledPath).toString());
        }
        else
        {
            qCWarning(lcSearch).noquote() << QStringLiteral("Could not seed bundled search plugin \"%1\" to %2")
                .arg(name, diskPath.toString());
            continue;
        }

        if (!seeded.contains(name))
            seeded.append(name);
    }

    if (seeded != alreadySeeded)
    {
        seeded.sort();
        Preferences::instance()->setSeededSearchPlugins(seeded);
    }

    m_bundledPluginIDs.removeDuplicates();
    m_bundledPluginIDs.sort();

    qCInfo(lcSearch) << "Bundled search plugins seeded:" << written << "written,"
        << seeded.size() << "known";
}

void SearchPluginManager::startUnofficialCatalogSync()
{
    if (m_catalogSyncInProgress)
        return;

    m_catalogQueue.clear();
    m_catalogPendingSeeded.clear();
    m_catalogFailures.clear();
    m_currentCatalogFailure.clear();
    m_currentCatalogSource = 0;
    m_catalogPreexisting = false;
    m_catalogAutoActivationAttempted = false;
    m_catalogAutoActivationInProgress = false;
    m_catalogActivationTransactions.clear();

    QFile manifest {UNOFFICIAL_MANIFEST_PATH};
    if (!manifest.open(QIODevice::ReadOnly))
    {
        failUnofficialCatalogSync(tr("The verified unofficial search-plugin catalog is missing from this build."));
        return;
    }

    const QByteArray bytes = manifest.read(MAX_UNOFFICIAL_MANIFEST_BYTES + 1);
    if (bytes.size() > MAX_UNOFFICIAL_MANIFEST_BYTES)
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog exceeds the 512 KiB safety limit."));
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
    if ((parseError.error != QJsonParseError::NoError) || !document.isObject())
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog is invalid JSON: %1")
            .arg(parseError.errorString()));
        return;
    }

    const QJsonObject root = document.object();
    if ((root.value(u"schema"_s).toInt() != 2) || !root.value(u"plugins"_s).isArray())
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog uses an unsupported schema."));
        return;
    }

    const QUrl sourceURL {root.value(u"source"_s).toString()};
    if (!sourceURL.isValid() || (sourceURL.scheme() != u"https") || sourceURL.host().isEmpty()
        || !sourceURL.userInfo().isEmpty())
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog source is not a safe HTTPS URL."));
        return;
    }

    const QString sourceRevision = root.value(u"sourceRevision"_s).toString().toLower();
    if (!isGitRevision(sourceRevision))
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog has an invalid source revision."));
        return;
    }

    const QJsonArray rows = root.value(u"plugins"_s).toArray();
    if (rows.isEmpty())
    {
        failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains no plugin rows."));
        return;
    }

    QSet<QString> allIDs;
    QSet<QString> caseFoldedIDs;
    for (const QJsonValue &value : rows)
    {
        if (!value.isObject())
        {
            failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains a non-object row."));
            return;
        }

        const QString rawID = value.toObject().value(u"id"_s).toString();
        const QString foldedID = rawID.toCaseFolded();
        if (!isSafeCatalogID(rawID))
        {
            failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains an unsafe plugin id: %1")
                .arg(rawID));
            return;
        }
        if (allIDs.contains(rawID) || caseFoldedIDs.contains(foldedID))
        {
            failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains a duplicate or ambiguous plugin id: %1")
                .arg(rawID));
            return;
        }
        allIDs.insert(rawID);
        caseFoldedIDs.insert(foldedID);
    }

    QList<CatalogEntry> entries;
    QHash<QString, qsizetype> entryIndexes;
    QHash<QString, QSet<QString>> sourceKeys;
    int availableSources = 0;
    int unavailableSources = 0;

    for (const QJsonValue &value : rows)
    {
        const QJsonObject object = value.toObject();
        const QString rawID = object.value(u"id"_s).toString();
        const QString canonicalID = canonicalCatalogID(rawID, allIDs);
        if (!entryIndexes.contains(canonicalID))
        {
            entryIndexes.insert(canonicalID, entries.size());
            entries.append(CatalogEntry {canonicalID, {}, {}});
        }

        if (!object.value(u"available"_s).toBool(false))
        {
            const QString unavailableReason = object.value(u"unavailableReason"_s).toString().trimmed().left(512);
            CatalogEntry &entry = entries[entryIndexes.value(canonicalID)];
            if (entry.unavailableReason.isEmpty() && !unavailableReason.isEmpty())
                entry.unavailableReason = unavailableReason;
            ++unavailableSources;
            continue;
        }

        const QUrl url {object.value(u"url"_s).toString()};
        const QByteArray expectedHash = object.value(u"sha256"_s).toString().toLatin1().toLower();
        if (!url.isValid() || (url.scheme() != u"https") || url.host().isEmpty()
            || !url.userInfo().isEmpty() || !isSha256(expectedHash))
        {
            failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains an unsafe or unpinned source for %1.")
                .arg(rawID));
            return;
        }

        const QString sourceKey = url.toString(QUrl::FullyEncoded) + u'|' + QString::fromLatin1(expectedHash);
        if (sourceKeys[canonicalID].contains(sourceKey))
        {
            failUnofficialCatalogSync(tr("The unofficial search-plugin catalog contains a duplicate source for %1.")
                .arg(canonicalID));
            return;
        }
        sourceKeys[canonicalID].insert(sourceKey);
        entries[entryIndexes.value(canonicalID)].sources.append({url.toString(), expectedHash});
        ++availableSources;
    }

    // Publish no catalog data until every row above has passed validation. A
    // later retry that somehow encounters a damaged embedded resource retains
    // the prior validated snapshot instead of replacing it with partial input.
    QHash<QString, CatalogEntry> validatedEntries;
    QStringList validatedCanonicalIDs;
    int canonicalAvailable = 0;
    for (const CatalogEntry &entry : std::as_const(entries))
    {
        validatedEntries.insert(entry.id, entry);
        validatedCanonicalIDs.append(entry.id);
        if (!entry.sources.isEmpty())
            ++canonicalAvailable;
    }
    validatedCanonicalIDs.sort();
    m_catalogEntries = std::move(validatedEntries);
    m_catalogCanonicalIDs = std::move(validatedCanonicalIDs);

    m_catalogStatus = {
        {u"state"_s, u"starting"_s},
        {u"inProgress"_s, true},
        {u"source"_s, sourceURL.toString()},
        {u"revision"_s, sourceRevision},
        {u"rowCount"_s, rows.size()},
        {u"availableSourceCount"_s, availableSources},
        {u"unavailableSourceCount"_s, unavailableSources},
        {u"canonicalCount"_s, entries.size()},
        {u"canonicalAvailableCount"_s, canonicalAvailable},
        {u"queued"_s, 0},
        {u"completed"_s, 0},
        {u"newlyInstalled"_s, 0},
        {u"quarantined"_s, 0},
        {u"awaitingTrust"_s, 0},
        {u"alreadyPresent"_s, 0},
        {u"verifiedPresent"_s, 0},
        {u"preservedExisting"_s, 0},
        {u"userRemoved"_s, 0},
        {u"failed"_s, 0},
        {u"registered"_s, 0},
        {u"runtimeUnavailable"_s, false},
        {u"runtimeError"_s, QString {}},
        {u"awaitingRuntime"_s, 0},
        {u"unavailable"_s, 0},
        {u"automaticallyActivated"_s, 0},
        {u"automaticActivationPending"_s, 0},
        {u"errors"_s, QStringList {}}
    };
    m_catalogSyncInProgress = true;

    Preferences *const preferences = Preferences::instance();
    QStringList seeded = preferences->getSeededSearchPlugins();
    const auto sourceForHash = [](const CatalogEntry &entry, const QByteArray &hash) -> const CatalogSource *
    {
        for (const CatalogSource &source : entry.sources)
        {
            if (source.sha256 == hash)
                return &source;
        }
        return nullptr;
    };

    for (const CatalogEntry &entry : std::as_const(entries))
    {
        if (entry.sources.isEmpty())
        {
            // A manifest may intentionally retain a canonical wiki entry that
            // cannot run against our bundled Nova ABI. Keep it searchable with
            // a concrete unavailable state, but do not turn one unavailable
            // source into a startup installation failure or retry storm.
            m_catalogStatus[u"unavailable"_s] = m_catalogStatus.value(u"unavailable"_s).toInt() + 1;
            m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
            continue;
        }

        const Path activePath = pluginPath(entry.id);
        const bool activeExists = activePath.exists();
        const QByteArray activeHash = activeExists ? fileSha256(activePath) : QByteArray {};
        auto ledgerIt = m_catalogLedger.find(entry.id);
        const bool hasLedger = ledgerIt != m_catalogLedger.end();
        CatalogLedgerEntry ledger = hasLedger ? ledgerIt.value() : CatalogLedgerEntry {};
        const CatalogSource *activeSource = sourceForHash(entry, activeHash);
        const CatalogSource *pendingSource = sourceForHash(entry, ledger.expectedHash);
        const Path candidatePath = (pendingSource && (ledger.observedHash == ledger.expectedHash))
            ? catalogQuarantinePath(entry.id, ledger.expectedHash) : Path {};
        const bool candidateVerified = !candidatePath.isEmpty() && candidatePath.exists()
            && isSha256(ledger.expectedHash) && (fileSha256(candidatePath) == ledger.expectedHash);
        const bool ownedActiveVerified = activeExists && hasLedger && ledger.catalogOwned && ledger.trusted
            && isSha256(ledger.activeHash) && (activeHash == ledger.activeHash);

        if (activeExists)
        {
            m_catalogPreexisting = true;
            m_catalogStatus[u"alreadyPresent"_s] = m_catalogStatus.value(u"alreadyPresent"_s).toInt() + 1;
            if (!seeded.contains(entry.id))
                seeded.append(entry.id);

            if (activeSource)
            {
                // A current pinned file already satisfies the catalog. Preserve
                // pre-ledger installs as trusted external files; never claim
                // ownership merely because their bytes happen to match.
                m_catalogStatus[u"verifiedPresent"_s] = m_catalogStatus.value(u"verifiedPresent"_s).toInt() + 1;
                m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
                if (hasLedger)
                {
                    ledger.expectedHash = activeHash;
                    ledger.observedHash = activeHash;
                    ledger.sourceUrl = activeSource->url;
                    ledger.userRemoved = false;
                    ledger.runtimeState = runtimeReady() && m_plugins.contains(entry.id)
                        ? u"ready"_s : (runtimeReady() ? u"import-failed"_s : u"stale-registration"_s);
                    if (ownedActiveVerified)
                    {
                        ledger.integrityState = u"verified-current"_s;
                        ledger.diagnostic.clear();
                    }
                    else
                    {
                        ledger.catalogOwned = false;
                        ledger.trusted = false;
                        ledger.activeHash.clear();
                        ledger.integrityState = u"verified-external"_s;
                        ledger.diagnostic = tr("A pre-existing SHA-256-verified plugin is active and was preserved as user-managed.");
                    }
                    ledgerIt.value() = ledger;
                }
                continue;
            }

            // The active bytes do not match the current pin. They may be a
            // manual replacement. Preserve them, and stage catalog bytes only
            // in the quarantine directory.
            m_catalogStatus[u"preservedExisting"_s] = m_catalogStatus.value(u"preservedExisting"_s).toInt() + 1;
            if (hasLedger && ledger.catalogOwned && !ownedActiveVerified)
            {
                ledger.catalogOwned = false;
                ledger.trusted = false;
                ledger.activeHash.clear();
                ledger.integrityState = u"user-modified"_s;
                ledger.runtimeState = runtimeReady() ? u"ready"_s : u"stale-registration"_s;
                ledger.diagnostic = tr("The active plugin changed outside the catalog transaction and was preserved as user-managed.");
                ledgerIt.value() = ledger;
            }

            if (candidateVerified)
            {
                CatalogLedgerEntry &state = m_catalogLedger[entry.id];
                state.integrityState = ownedActiveVerified ? u"pending-update-trust"_s : u"pending-trust"_s;
                state.runtimeState = u"quarantined"_s;
                state.userRemoved = false;
                state.diagnostic = ownedActiveVerified
                    ? tr("A pinned update is quarantined until you explicitly trust and validate it.")
                    : tr("A user-managed active file was preserved; the pinned catalog file remains quarantined.");
                m_catalogStatus[u"quarantined"_s] = m_catalogStatus.value(u"quarantined"_s).toInt() + 1;
                m_catalogStatus[u"awaitingTrust"_s] = m_catalogStatus.value(u"awaitingTrust"_s).toInt() + 1;
                m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
            }
            else
            {
                m_catalogQueue.enqueue(entry);
            }
            continue;
        }

        // A previously trusted catalog file disappearing is an explicit user
        // removal, even when a newer candidate was already staged. A pending
        // first-install candidate, however, is not mistaken for a removal just
        // because the active engine directory is intentionally still empty.
        const bool removedAfterTrust = hasLedger && ledger.catalogOwned && ledger.trusted
            && !ledger.activeHash.isEmpty() && seeded.contains(entry.id);
        const bool userRemoved = (hasLedger && ledger.userRemoved)
            || removedAfterTrust || (seeded.contains(entry.id) && !hasLedger);
        if (userRemoved)
        {
            CatalogLedgerEntry &state = m_catalogLedger[entry.id];
            state.userRemoved = true;
            state.catalogOwned = false;
            state.trusted = false;
            state.activeHash.clear();
            state.integrityState = u"user-removed"_s;
            state.runtimeState = u"user-removed"_s;
            state.diagnostic = tr("The default plugin was removed by the user and will not be restored automatically.");
            if (state.expectedHash.isEmpty())
            {
                state.expectedHash = entry.sources.constFirst().sha256;
                state.sourceUrl = entry.sources.constFirst().url;
            }
            m_catalogStatus[u"userRemoved"_s] = m_catalogStatus.value(u"userRemoved"_s).toInt() + 1;
            m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
            continue;
        }

        if (candidateVerified)
        {
            CatalogLedgerEntry &state = m_catalogLedger[entry.id];
            state.userRemoved = false;
            state.integrityState = u"pending-trust"_s;
            state.runtimeState = u"quarantined"_s;
            state.diagnostic = tr("The SHA-256-verified plugin is installed in quarantine and awaits explicit trust.");
            m_catalogStatus[u"alreadyPresent"_s] = m_catalogStatus.value(u"alreadyPresent"_s).toInt() + 1;
            m_catalogStatus[u"quarantined"_s] = m_catalogStatus.value(u"quarantined"_s).toInt() + 1;
            m_catalogStatus[u"awaitingTrust"_s] = m_catalogStatus.value(u"awaitingTrust"_s).toInt() + 1;
            m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
            continue;
        }

        m_catalogQueue.enqueue(entry);
    }

    seeded.removeDuplicates();
    seeded.sort();
    preferences->setSeededSearchPlugins(seeded);
    saveCatalogLedger();
    m_catalogStatus[u"queued"_s] = m_catalogQueue.size();
    m_catalogStatus[u"state"_s] = m_catalogQueue.isEmpty() ? u"finalizing"_s : u"downloading"_s;
    emit unofficialCatalogStatusChanged(m_catalogStatus);

    downloadNextUnofficialPlugin();
}

void SearchPluginManager::downloadNextUnofficialPlugin()
{
    if (!m_catalogSyncInProgress)
        return;

    if (m_catalogQueue.isEmpty())
    {
        finishUnofficialCatalogSync();
        return;
    }

    m_currentCatalogEntry = m_catalogQueue.dequeue();
    m_currentCatalogSource = 0;
    m_currentCatalogFailure.clear();
    downloadCurrentUnofficialSource();
}

void SearchPluginManager::downloadCurrentUnofficialSource()
{
    if (m_currentCatalogSource >= m_currentCatalogEntry.sources.size())
    {
        const QString reason = m_currentCatalogFailure.isEmpty()
            ? tr("No verified source succeeded.")
            : m_currentCatalogFailure;
        m_catalogFailures.append(u"%1: %2"_s.arg(m_currentCatalogEntry.id, reason));
        m_catalogStatus[u"failed"_s] = m_catalogStatus.value(u"failed"_s).toInt() + 1;
        m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
        emit unofficialCatalogStatusChanged(m_catalogStatus);
        downloadNextUnofficialPlugin();
        return;
    }

    const CatalogSource &source = m_currentCatalogEntry.sources.at(m_currentCatalogSource);
    qCInfo(lcSearch).noquote() << QStringLiteral("Downloading verified default search plugin \"%1\" from HTTPS source %2 (%3/%4)")
        .arg(m_currentCatalogEntry.id, source.url)
        .arg(m_currentCatalogSource + 1)
        .arg(m_currentCatalogEntry.sources.size());

    using namespace Net;
    DownloadManager::instance()->download(
        DownloadRequest(source.url).limit(MAX_UNOFFICIAL_PLUGIN_BYTES),
        Preferences::instance()->useProxyForGeneralPurposes(),
        this, &SearchPluginManager::unofficialPluginDownloadFinished);
}

void SearchPluginManager::unofficialPluginDownloadFinished(const Net::DownloadResult &result)
{
    const CatalogSource source = m_currentCatalogEntry.sources.at(m_currentCatalogSource);
    QString failure;

    if (result.status != Net::DownloadStatus::Success)
    {
        failure = tr("Download failed: %1").arg(result.errorString);
    }
    else if (result.data.isEmpty())
    {
        failure = tr("The verified source returned an empty file.");
    }
    else
    {
        const QByteArray actualHash = QCryptographicHash::hash(result.data, QCryptographicHash::Sha256).toHex();
        if (actualHash != source.sha256)
        {
            failure = tr("SHA-256 verification failed (expected %1, received %2).")
                .arg(QString::fromLatin1(source.sha256), QString::fromLatin1(actualHash));
        }
        else
        {
            const Path destination = catalogQuarantinePath(m_currentCatalogEntry.id, source.sha256);
            if (destination.exists())
            {
                if (fileSha256(destination) != source.sha256)
                {
                    // Never overwrite an unexpected file, even inside the
                    // application-owned quarantine namespace. A concurrent or
                    // manually placed replacement wins the race and remains.
                    failure = tr("The quarantine destination already contains different bytes and was preserved.");
                }
                else
                {
                    m_catalogStatus[u"alreadyPresent"_s] = m_catalogStatus.value(u"alreadyPresent"_s).toInt() + 1;
                }
            }
            else
            {
                const auto saveResult = Utils::IO::saveToFile(destination, result.data);
                if (!saveResult)
                {
                    failure = tr("Could not save the verified plugin: %1").arg(saveResult.error());
                }
                else
                {
                    m_catalogStatus[u"newlyInstalled"_s] = m_catalogStatus.value(u"newlyInstalled"_s).toInt() + 1;
                    qCInfo(lcSearch) << "Verified default search plugin quarantined:" << m_currentCatalogEntry.id;
                }
            }

            if (failure.isEmpty())
            {
                CatalogLedgerEntry state = m_catalogLedger.value(m_currentCatalogEntry.id);
                const Path activePath = pluginPath(m_currentCatalogEntry.id);
                const QByteArray activeHash = activePath.exists() ? fileSha256(activePath) : QByteArray {};
                const bool preserveOwnedActive = activePath.exists() && state.catalogOwned && state.trusted
                    && isSha256(state.activeHash) && (activeHash == state.activeHash);

                state.expectedHash = source.sha256;
                state.observedHash = source.sha256;
                state.sourceUrl = source.url;
                state.generation += 1;
                state.userRemoved = false;
                if (!preserveOwnedActive)
                {
                    state.catalogOwned = false;
                    state.trusted = false;
                    state.activeHash.clear();
                }
                state.integrityState = preserveOwnedActive ? u"pending-update-trust"_s : u"pending-trust"_s;
                state.runtimeState = u"quarantined"_s;
                if (activePath.exists() && !preserveOwnedActive)
                    state.diagnostic = tr("A user-managed active file was preserved; the pinned catalog file is quarantined.");
                else if (preserveOwnedActive)
                    state.diagnostic = tr("A pinned update is quarantined until you explicitly trust and validate it.");
                else
                    state.diagnostic = tr("The SHA-256-verified plugin is installed in quarantine and awaits explicit trust.");
                m_catalogLedger.insert(m_currentCatalogEntry.id, state);

                if (!saveCatalogLedger())
                    failure = tr("The verified plugin was quarantined, but its trust ledger could not be persisted.");
                else
                {
                    m_catalogStatus[u"quarantined"_s] = m_catalogStatus.value(u"quarantined"_s).toInt() + 1;
                    m_catalogStatus[u"awaitingTrust"_s] = m_catalogStatus.value(u"awaitingTrust"_s).toInt() + 1;
                }
            }
        }
    }

    if (!failure.isEmpty())
    {
        qCWarning(lcSearch).noquote() << QStringLiteral("Verified source failed for search plugin \"%1\": %2")
            .arg(m_currentCatalogEntry.id, failure);
        m_currentCatalogFailure = failure;
        ++m_currentCatalogSource;
        downloadCurrentUnofficialSource();
        return;
    }

    m_catalogStatus[u"completed"_s] = m_catalogStatus.value(u"completed"_s).toInt() + 1;
    emit unofficialCatalogStatusChanged(m_catalogStatus);
    downloadNextUnofficialPlugin();
}

void SearchPluginManager::recordUnofficialCatalogActivationFailure(const QString &id, const QString &reason)
{
    const QString detail = u"%1: %2"_s.arg(id, reason);
    m_catalogFailures.append(detail);
    m_catalogStatus[u"failed"_s] = m_catalogStatus.value(u"failed"_s).toInt() + 1;
    qCWarning(lcSearch).noquote() << QStringLiteral("Verified catalog plugin \"%1\" was not activated: %2")
        .arg(id, reason);
}

void SearchPluginManager::startUnofficialCatalogActivation()
{
    if (m_catalogAutoActivationInProgress || !runtimeReady())
        return;

    for (const QString &id : std::as_const(m_catalogCanonicalIDs))
    {
        const auto catalogIt = m_catalogEntries.constFind(id);
        auto ledgerIt = m_catalogLedger.find(id);
        if ((catalogIt == m_catalogEntries.cend()) || (ledgerIt == m_catalogLedger.end()))
            continue;

        const CatalogEntry &entry = catalogIt.value();
        CatalogLedgerEntry &state = ledgerIt.value();
        if (entry.sources.isEmpty() || state.userRemoved
            || (state.integrityState == u"runtime-incompatible"_s))
        {
            continue;
        }

        const bool pinStillCurrent = std::ranges::any_of(entry.sources,
            [&state](const CatalogSource &source)
            {
                return (source.sha256 == state.expectedHash) && (source.url == state.sourceUrl);
            });
        const Path candidatePath = catalogQuarantinePath(id, state.expectedHash);
        const QByteArray candidateHash = candidatePath.exists() ? fileSha256(candidatePath) : QByteArray {};
        if (!pinStillCurrent || !isSha256(state.expectedHash)
            || (state.expectedHash != state.observedHash) || (candidateHash != state.expectedHash))
        {
            continue;
        }

        const Path activePath = pluginPath(id);
        const bool hadActive = activePath.exists();
        const QByteArray previousActiveHash = hadActive ? fileSha256(activePath) : QByteArray {};
        const bool activeIsCatalogOwned = hadActive && state.catalogOwned && state.trusted
            && isSha256(state.activeHash) && (previousActiveHash == state.activeHash);
        if (hadActive && !activeIsCatalogOwned)
        {
            // Never replace a manual/custom plugin just because an identically
            // named catalog candidate is available.
            continue;
        }

        if (hadActive && (previousActiveHash == candidateHash) && m_plugins.contains(id))
        {
            state.catalogOwned = true;
            state.trusted = true;
            state.userRemoved = false;
            state.activeHash = candidateHash;
            state.integrityState = u"verified-current"_s;
            state.runtimeState = u"ready"_s;
            state.diagnostic.clear();
            if (candidatePath.exists())
                Utils::Fs::removeFile(candidatePath);
            if (!m_catalogPendingSeeded.contains(id))
                m_catalogPendingSeeded.append(id);
            continue;
        }

        const quint64 generation = state.generation + 1;
        const Path backupPath = hadActive
            ? (catalogQuarantineLocation() / Path(u"%1-active-backup-%2-%3.py"_s
                .arg(id, QString::number(generation), QString::fromLatin1(previousActiveHash))))
            : Path {};
        state.generation = generation;
        state.runtimeState = u"validating"_s;
        state.integrityState = hadActive ? u"validating-update"_s : u"validating"_s;
        state.diagnostic = tr("Automatically validating this SHA-256-verified catalog plugin.");
        state.userRemoved = false;
        if (!saveCatalogLedger())
        {
            state.runtimeState = u"quarantined"_s;
            state.integrityState = hadActive ? u"pending-update-trust"_s : u"pending-trust"_s;
            state.diagnostic = tr("The automatic activation transaction could not be persisted, so the active file was not changed.");
            recordUnofficialCatalogActivationFailure(id, state.diagnostic);
            continue;
        }

        if (hadActive)
        {
            if (backupPath.exists())
            {
                state.runtimeState = u"quarantined"_s;
                state.integrityState = u"pending-update-trust"_s;
                state.diagnostic = tr("An automatic activation backup already exists. The active file was preserved.");
                saveCatalogLedger();
                recordUnofficialCatalogActivationFailure(id, state.diagnostic);
                continue;
            }

            QString backupError;
            if (!atomicCopyFile(activePath, backupPath, &backupError)
                || (fileSha256(backupPath) != previousActiveHash))
            {
                state.runtimeState = u"quarantined"_s;
                state.integrityState = u"pending-update-trust"_s;
                state.diagnostic = tr("The current catalog plugin could not be backed up before automatic activation: %1")
                    .arg(backupError);
                saveCatalogLedger();
                recordUnofficialCatalogActivationFailure(id, state.diagnostic);
                continue;
            }
        }

        QString promotionError;
        if (!atomicCopyFile(candidatePath, activePath, &promotionError)
            || (fileSha256(activePath) != candidateHash))
        {
            state.runtimeState = u"quarantined"_s;
            state.integrityState = hadActive ? u"pending-update-trust"_s : u"pending-trust"_s;
            state.diagnostic = tr("The SHA-256-verified catalog file could not be activated automatically: %1")
                .arg(promotionError);
            if (hadActive && backupPath.exists() && (fileSha256(backupPath) == previousActiveHash))
                Utils::Fs::removeFile(backupPath);
            saveCatalogLedger();
            recordUnofficialCatalogActivationFailure(id, state.diagnostic);
            continue;
        }

        m_catalogActivationTransactions.insert(id, CatalogActivationTransaction {
            candidateHash, previousActiveHash, backupPath, generation, hadActive
        });
    }

    if (m_catalogActivationTransactions.isEmpty())
        return;

    m_catalogAutoActivationInProgress = true;
    m_catalogStatus[u"state"_s] = u"validating"_s;
    m_catalogStatus[u"automaticActivationPending"_s] = m_catalogActivationTransactions.size();
    emit unofficialCatalogStatusChanged(m_catalogStatus);

    // All candidates have already passed their immutable SHA-256 pins. Run one
    // capability process for the entire batch so default setup does not launch
    // a Python interpreter once per catalog row or emit per-plugin feedback.
    clearPythonCache(engineLocation());
    update(true, [this] { finishUnofficialCatalogActivation(); });
}

void SearchPluginManager::finishUnofficialCatalogActivation()
{
    if (!m_catalogAutoActivationInProgress)
        return;

    m_catalogAutoActivationInProgress = false;
    bool requiresReconciliation = false;
    for (auto transactionIt = m_catalogActivationTransactions.cbegin();
         transactionIt != m_catalogActivationTransactions.cend(); ++transactionIt)
    {
        const QString &id = transactionIt.key();
        const CatalogActivationTransaction &transaction = transactionIt.value();
        auto ledgerIt = m_catalogLedger.find(id);
        if (ledgerIt == m_catalogLedger.end())
            continue;

        CatalogLedgerEntry &state = ledgerIt.value();
        const Path activePath = pluginPath(id);
        const QByteArray activeHash = activePath.exists() ? fileSha256(activePath) : QByteArray {};
        if (state.userRemoved || (state.generation != transaction.generation)
            || (activeHash != transaction.candidateHash))
        {
            // The user removed or replaced this engine while the aggregate
            // capability process ran. The generation and hash guard must run
            // before every ledger mutation, rollback copy, or active-file
            // deletion so a catalog transaction can never resurrect or erase
            // a newer user decision.
            qCInfo(lcSearch) << "Skipping stale automatic catalog activation transaction:" << id;
            requiresReconciliation = true;
            continue;
        }
        if ((activeHash == transaction.candidateHash) && runtimeReady() && m_plugins.contains(id))
        {
            state.catalogOwned = true;
            state.trusted = true;
            state.userRemoved = false;
            state.activeHash = transaction.candidateHash;
            state.integrityState = u"verified-current"_s;
            state.runtimeState = u"ready"_s;
            state.diagnostic.clear();

            const Path candidatePath = catalogQuarantinePath(id, transaction.candidateHash);
            if (candidatePath.exists() && (fileSha256(candidatePath) == transaction.candidateHash))
                Utils::Fs::removeFile(candidatePath);
            if (transaction.hadActive && transaction.backupPath.exists()
                && (fileSha256(transaction.backupPath) == transaction.previousActiveHash))
            {
                Utils::Fs::removeFile(transaction.backupPath);
            }
            if (!m_catalogPendingSeeded.contains(id))
                m_catalogPendingSeeded.append(id);
            m_catalogStatus[u"automaticallyActivated"_s] = m_catalogStatus.value(u"automaticallyActivated"_s).toInt() + 1;
            continue;
        }

        const QString importDiagnostic = m_pluginImportErrors.value(id);
        QString reason = !m_runtimeError.isEmpty()
            ? m_runtimeError
            : (!importDiagnostic.isEmpty()
                ? tr("The plugin failed to import: %1").arg(importDiagnostic)
                : tr("The runtime did not register an engine named \"%1\".").arg(id));

        bool restored = false;
        if (transaction.hadActive && transaction.backupPath.exists()
            && (fileSha256(transaction.backupPath) == transaction.previousActiveHash))
        {
            QString restoreError;
            restored = atomicCopyFile(transaction.backupPath, activePath, &restoreError)
                && (fileSha256(activePath) == transaction.previousActiveHash);
            if (!restored)
                reason += tr(" The prior catalog file could not be restored: %1").arg(restoreError);
        }
        else if (!transaction.hadActive && (activeHash == transaction.candidateHash))
        {
            // This exact candidate is transaction-owned. Removing it cannot
            // discard a manual replacement that arrived during validation.
            Utils::Fs::removeFile(activePath);
        }

        if (!restored && activePath.exists() && (fileSha256(activePath) == transaction.candidateHash))
        {
            Utils::Fs::removeFile(activePath);
            reason += tr(" The unsupported transaction bytes were removed from the active engine directory.");
        }
        if (transaction.hadActive && restored && transaction.backupPath.exists()
            && (fileSha256(transaction.backupPath) == transaction.previousActiveHash))
        {
            Utils::Fs::removeFile(transaction.backupPath);
        }

        state.catalogOwned = transaction.hadActive && restored;
        state.trusted = transaction.hadActive && restored;
        state.userRemoved = false;
        state.activeHash = (transaction.hadActive && restored) ? transaction.previousActiveHash : QByteArray {};
        state.integrityState = u"runtime-incompatible"_s;
        state.runtimeState = transaction.hadActive && restored ? u"stale-registration"_s : u"unavailable"_s;
        state.diagnostic = reason;
        recordUnofficialCatalogActivationFailure(id, reason);
        requiresReconciliation = requiresReconciliation || transaction.hadActive;
    }
    m_catalogActivationTransactions.clear();
    m_catalogStatus[u"automaticActivationPending"_s] = 0;
    saveCatalogLedger();

    if (requiresReconciliation)
    {
        clearPythonCache(engineLocation());
        update(true, [this] { finishUnofficialCatalogSync(); });
        return;
    }

    finishUnofficialCatalogSync();
}

void SearchPluginManager::finishUnofficialCatalogSync()
{
    if (!m_catalogSyncInProgress)
        return;

    if (!m_catalogAutoActivationAttempted)
    {
        m_catalogAutoActivationAttempted = true;
        if (runtimeReady())
        {
            startUnofficialCatalogActivation();
            if (m_catalogAutoActivationInProgress)
                return;
        }
    }

    m_catalogStatus[u"state"_s] = u"finalizing"_s;
    emit unofficialCatalogStatusChanged(m_catalogStatus);

    QStringList seeded = Preferences::instance()->getSeededSearchPlugins();
    for (const QString &id : std::as_const(m_catalogPendingSeeded))
    {
        if (!seeded.contains(id))
            seeded.append(id);
    }
    seeded.removeDuplicates();
    seeded.sort();
    Preferences::instance()->setSeededSearchPlugins(seeded);

    const bool runtimeUnavailable = !runtimeReady();
    int registered = 0;
    int awaitingRuntime = 0;
    int awaitingTrust = 0;
    for (const QString &id : std::as_const(m_catalogCanonicalIDs))
    {
        const Path activePath = pluginPath(id);
        const bool activeExists = activePath.exists();

        auto ledgerIt = m_catalogLedger.find(id);
        if (ledgerIt == m_catalogLedger.end())
        {
            if (!runtimeUnavailable && activeExists && m_plugins.contains(id))
                ++registered;
            continue;
        }

        CatalogLedgerEntry &state = ledgerIt.value();
        const Path candidatePath = catalogQuarantinePath(id, state.expectedHash);
        const bool candidateVerified = !state.userRemoved && !candidatePath.isEmpty()
            && candidatePath.exists() && (state.expectedHash == state.observedHash)
            && (fileSha256(candidatePath) == state.expectedHash);
        if (runtimeUnavailable && (activeExists || candidateVerified))
            ++awaitingRuntime;
        else if (!runtimeUnavailable && activeExists && m_plugins.contains(id))
            ++registered;
        const QByteArray activeHash = activeExists ? fileSha256(activePath) : QByteArray {};
        const bool activeOwned = activeExists && state.catalogOwned && state.trusted
            && isSha256(state.activeHash) && (activeHash == state.activeHash);
        const bool promotable = candidateVerified && (!activeExists || activeOwned);
        if (!runtimeUnavailable && promotable && (!state.trusted || (state.activeHash != state.expectedHash)))
            ++awaitingTrust;

        if (runtimeUnavailable && (activeExists || candidateVerified))
        {
            state.runtimeState = m_registrationStale ? u"stale-registration"_s : u"waiting-python"_s;
            if (state.diagnostic.isEmpty())
                state.diagnostic = m_runtimeError;
        }
        else if (!runtimeUnavailable && activeExists && m_plugins.contains(id))
        {
            state.runtimeState = u"ready"_s;
        }
        else if (!runtimeUnavailable && activeExists)
        {
            state.runtimeState = u"import-failed"_s;
            const QString diagnostic = m_pluginImportErrors.value(id);
            state.diagnostic = diagnostic.isEmpty()
                ? tr("The active file is present, but the runtime did not register its matching engine class.")
                : tr("The active plugin failed to import: %1").arg(diagnostic);
            m_catalogFailures.append(u"%1: %2"_s.arg(id, state.diagnostic));
            m_catalogStatus[u"failed"_s] = m_catalogStatus.value(u"failed"_s).toInt() + 1;
        }
    }
    m_catalogStatus[u"registered"_s] = registered;
    m_catalogStatus[u"runtimeUnavailable"_s] = runtimeUnavailable;
    m_catalogStatus[u"runtimeError"_s] = runtimeUnavailable
        ? (m_runtimeError.isEmpty() ? tr("Search plugin registration is stale.") : m_runtimeError)
        : QString {};
    m_catalogStatus[u"awaitingRuntime"_s] = awaitingRuntime;
    m_catalogStatus[u"awaitingTrust"_s] = awaitingTrust;
    m_catalogStatus[u"errors"_s] = m_catalogFailures;
    m_catalogStatus[u"inProgress"_s] = false;
    if (runtimeUnavailable && (awaitingRuntime > 0))
        m_catalogStatus[u"state"_s] = u"waiting-runtime"_s;
    else if (m_catalogStatus.value(u"failed"_s).toInt() > 0)
        m_catalogStatus[u"state"_s] = u"partial"_s;
    else if (awaitingTrust > 0)
        m_catalogStatus[u"state"_s] = u"waiting-trust"_s;
    else
        m_catalogStatus[u"state"_s] = u"complete"_s;
    saveCatalogLedger();
    m_catalogSyncInProgress = false;

    qCInfo(lcSearch) << "Verified unofficial search-plugin sync finished:" << m_catalogStatus;
    emit pluginCatalogChanged();
    emit unofficialCatalogStatusChanged(m_catalogStatus);
    emit unofficialCatalogSyncFinished(m_catalogStatus);

    const bool retryQueued = std::exchange(m_catalogRetryPending, false);
    if (retryQueued)
        QTimer::singleShot(0, this, &SearchPluginManager::retryUnofficialCatalogSync);
}

void SearchPluginManager::failUnofficialCatalogSync(const QString &reason)
{
    qCWarning(lcSearch).noquote() << reason;
    m_catalogSyncInProgress = false;
    m_catalogStatus = {
        {u"state"_s, u"failed"_s},
        {u"inProgress"_s, false},
        {u"failed"_s, 1},
        {u"errors"_s, QStringList {reason}}
    };
    emit unofficialCatalogStatusChanged(m_catalogStatus);
    emit unofficialCatalogSyncFinished(m_catalogStatus);

    const bool retryQueued = std::exchange(m_catalogRetryPending, false);
    if (retryQueued)
        QTimer::singleShot(0, this, &SearchPluginManager::retryUnofficialCatalogSync);
}

void SearchPluginManager::update(const bool suppressSignals, std::function<void()> completed)
{
    m_capabilityRequests.enqueue({suppressSignals, std::move(completed)});
    startNextCapabilityProbe();
}

void SearchPluginManager::startNextCapabilityProbe()
{
    if (m_capabilityProbeRunning || m_capabilityRequests.isEmpty())
        return;

    m_capabilityProbeRunning = true;
    if (!m_registrationStale)
    {
        m_registrationStale = true;
        emit pluginCatalogChanged();
    }
    m_capabilityProbeStarted = false;
    m_capabilityProbeTimedOut = false;
    m_capabilityProbeCompleting = false;
    m_capabilityStdOut.clear();
    m_capabilityStdErr.clear();
    m_capabilityOutputOverflow = false;
    m_activeCapabilityRequest = m_capabilityRequests.dequeue();
    m_pluginImportErrors.clear();
    qCDebug(lcSearch) << "Refreshing search engine capabilities asynchronously via nova2.py --capabilities";

    const Utils::ForeignApps::PythonInfo pyInfo = Utils::ForeignApps::pythonInfo();
    if (!pyInfo.isValid())
    {
        const QString reason = tr("Python was not found. Search needs a Python %1 or later interpreter on PATH, or one selected in Options.")
            .arg(Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
        qCWarning(lcSearch).noquote() << reason;
        failCapabilityGeneration(reason);
        const CapabilityRequest request = m_activeCapabilityRequest;
        QTimer::singleShot(0, this, [this, request] { finishCapabilityRequest(request); });
        return;
    }
    if (!pyInfo.isSupportedVersion())
    {
        const QString reason = tr("Python %1 is below the supported minimum %2.")
            .arg(pyInfo.version.toString(), Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
        qCWarning(lcSearch).noquote() << reason;
        failCapabilityGeneration(reason);
        const CapabilityRequest request = m_activeCapabilityRequest;
        QTimer::singleShot(0, this, [this, request] { finishCapabilityRequest(request); });
        return;
    }

    const Path novaScript = engineLocation() / Path(u"nova2.py"_s);
    if (!novaScript.exists())
    {
        const QString reason = tr("The bundled search runtime is missing. Expected \"%1\".").arg(novaScript.toString());
        qCWarning(lcSearch).noquote() << reason;
        failCapabilityGeneration(reason);
        const CapabilityRequest request = m_activeCapabilityRequest;
        QTimer::singleShot(0, this, [this, request] { finishCapabilityRequest(request); });
        return;
    }

    m_capabilityProcess = new QProcess(this);
    m_capabilityProcess->setProcessEnvironment(proxyEnvironment());
#ifdef Q_OS_UNIX
    m_capabilityProcess->setUnixProcessParameters(QProcess::UnixProcessFlag::CloseFileDescriptors);
#endif

    connect(m_capabilityProcess, &QProcess::started, this, [this]
    {
        m_capabilityProbeStarted = true;
    });
    connect(m_capabilityProcess, &QProcess::errorOccurred, this, [this](const QProcess::ProcessError error)
    {
        if (error == QProcess::FailedToStart)
            QTimer::singleShot(0, this, &SearchPluginManager::completeCapabilityProbe);
    });
    connect(m_capabilityProcess, &QProcess::readyReadStandardOutput,
            this, &SearchPluginManager::drainCapabilityOutput);
    connect(m_capabilityProcess, &QProcess::readyReadStandardError,
            this, &SearchPluginManager::drainCapabilityOutput);
    connect(m_capabilityProcess, &QProcess::finished, this,
            [this](int, QProcess::ExitStatus) { completeCapabilityProbe(); });

    m_capabilityTimeout = new QTimer(this);
    m_capabilityTimeout->setSingleShot(true);
    m_capabilityTimeout->setInterval(10000);
    connect(m_capabilityTimeout, &QTimer::timeout, this, [this]
    {
        if (!m_capabilityProcess || m_capabilityProbeCompleting)
            return;
        m_capabilityProbeTimedOut = true;
        qCWarning(lcSearch) << "Timed out while fetching search engine capabilities";
        m_capabilityProcess->kill();
    });

    const QStringList params
    {
        Utils::ForeignApps::PYTHON_ISOLATE_MODE_FLAG,
        Utils::ForeignApps::PYTHON_UTF8_MODE_FLAG,
        novaScript.toString(),
        u"--capabilities"_s
    };
    m_capabilityTimeout->start();
    m_capabilityProcess->start(pyInfo.executablePath.data(), params, QIODevice::ReadOnly);
}

void SearchPluginManager::drainCapabilityOutput()
{
    if (!m_capabilityProcess)
        return;

    const bool alreadyOverflowed = m_capabilityOutputOverflow;
    const auto appendBounded = [this](QByteArray &buffer, const QByteArray &chunk, const qsizetype limit)
    {
        const qsizetype remaining = std::max<qsizetype>(0, limit - buffer.size());
        if (chunk.size() > remaining)
        {
            if (remaining > 0)
                buffer.append(chunk.constData(), remaining);
            m_capabilityOutputOverflow = true;
            return;
        }
        buffer.append(chunk);
    };

    appendBounded(m_capabilityStdOut, m_capabilityProcess->readAllStandardOutput(), MAX_CAPABILITY_STDOUT_BYTES);
    appendBounded(m_capabilityStdErr, m_capabilityProcess->readAllStandardError(), MAX_CAPABILITY_STDERR_BYTES);

    if (!alreadyOverflowed && m_capabilityOutputOverflow
        && !m_capabilityProbeCompleting && (m_capabilityProcess->state() != QProcess::NotRunning))
    {
        qCWarning(lcSearch) << "Search runtime exceeded its bounded capability-output allowance; terminating it";
        m_capabilityProcess->kill();
    }
}

void SearchPluginManager::completeCapabilityProbe()
{
    if (m_capabilityProbeCompleting || !m_capabilityProcess)
        return;
    m_capabilityProbeCompleting = true;

    if (m_capabilityTimeout)
        m_capabilityTimeout->stop();

    drainCapabilityOutput();

    CapabilityProbeResult result;
    result.started = m_capabilityProbeStarted;
    result.timedOut = m_capabilityProbeTimedOut;
    result.outputOverflow = m_capabilityOutputOverflow;
    result.standardOutput = QString::fromUtf8(m_capabilityStdOut);
    result.standardError = QString::fromUtf8(m_capabilityStdErr).trimmed();
    result.processError = m_capabilityProcess->errorString();

    const CapabilityRequest request = m_activeCapabilityRequest;
    m_capabilityProcess->deleteLater();
    m_capabilityProcess = nullptr;
    if (m_capabilityTimeout)
    {
        m_capabilityTimeout->deleteLater();
        m_capabilityTimeout = nullptr;
    }

    applyCapabilityProbeResult(result, request.suppressSignals);
    finishCapabilityRequest(request);
}

void SearchPluginManager::finishCapabilityRequest(const CapabilityRequest &request)
{
    if (request.completed)
        request.completed();

    m_activeCapabilityRequest = {};
    m_capabilityProbeRunning = false;
    m_capabilityProbeCompleting = false;
    startNextCapabilityProbe();
}

void SearchPluginManager::applyCapabilityProbeResult(const CapabilityProbeResult &result, const bool suppressSignals)
{
    if (result.outputOverflow)
    {
        failCapabilityGeneration(tr("The search runtime exceeded its output safety limit."));
        return;
    }
    if (result.timedOut)
    {
        failCapabilityGeneration(tr("The search runtime did not respond within 10 seconds."));
        return;
    }
    if (!result.started)
    {
        failCapabilityGeneration(tr("The search runtime failed to start. Error: \"%1\".").arg(result.processError));
        return;
    }

    const QString stdErrMsg = result.standardError;
    static const QString importErrorPrefix = u"PLUGIN_IMPORT_ERROR:"_s;
    for (const QString &line : stdErrMsg.split(u'\n', Qt::SkipEmptyParts))
    {
        const QString diagnostic = line.trimmed();
        if (!diagnostic.startsWith(importErrorPrefix))
            continue;

        const qsizetype nameStart = importErrorPrefix.size();
        const qsizetype nameEnd = diagnostic.indexOf(u':', nameStart);
        if (nameEnd <= nameStart)
            continue;
        const QString name = diagnostic.sliced(nameStart, nameEnd - nameStart);
        if (isSafeCatalogID(name))
            m_pluginImportErrors.insert(name, diagnostic.sliced(nameEnd + 1).left(2048));
    }
    if (!stdErrMsg.isEmpty())
    {
        qCWarning(lcSearch).noquote() << tr("Error occurred when fetching search engine capabilities. Error: \"%1\".").arg(stdErrMsg.left(2048));
    }

    const QString capabilities = result.standardOutput;
    QDomDocument xmlDoc;
    if (!xmlDoc.setContent(capabilities))
    {
        const QString reason = stdErrMsg.isEmpty()
            ? tr("The search runtime returned no usable plugin capabilities.")
            : tr("The search runtime failed to start. Error: \"%1\".").arg(stdErrMsg.left(2048));
        qCWarning(lcSearch).noquote() << QStringLiteral("Could not parse nova search engine capabilities. Output excerpt: %1").arg(capabilities.left(2048));
        failCapabilityGeneration(reason);
        return;
    }

    const QDomElement root = xmlDoc.documentElement();
    if (root.tagName() != u"capabilities")
    {
        qCWarning(lcSearch).noquote() << QStringLiteral("Invalid XML for nova search engine capabilities. Output excerpt: %1").arg(capabilities.left(2048));
        failCapabilityGeneration(tr("The search runtime reported malformed plugin capabilities."));
        return;
    }

    QSet<QString> discoveredPlugins;
    QSet<QString> caseFoldedPlugins;
    QHash<QString, SearchPluginInfo> parsedPlugins;
    const QStringList disabledEngines = Preferences::instance()->getSearchEngDisabled();
    for (QDomNode engineNode = root.firstChild(); !engineNode.isNull(); engineNode = engineNode.nextSibling())
    {
        const QDomElement engineElem = engineNode.toElement();
        if (engineElem.isNull())
            continue;

        const QString pluginName = engineElem.tagName();
        const QString foldedName = pluginName.toCaseFolded();
        if (!isSafeCatalogID(pluginName) || discoveredPlugins.contains(pluginName)
            || caseFoldedPlugins.contains(foldedName))
        {
            failCapabilityGeneration(tr("The search runtime reported a duplicate, ambiguous, or unsafe engine id: %1")
                .arg(pluginName));
            return;
        }

        const QDomNodeList nameNodes = engineElem.elementsByTagName(u"name"_s);
        const QDomNodeList urlNodes = engineElem.elementsByTagName(u"url"_s);
        const QDomNodeList categoryNodes = engineElem.elementsByTagName(u"categories"_s);
        if ((nameNodes.count() != 1) || (urlNodes.count() != 1) || (categoryNodes.count() != 1))
        {
            failCapabilityGeneration(tr("The search runtime reported incomplete capabilities for engine %1.")
                .arg(pluginName));
            return;
        }

        discoveredPlugins.insert(pluginName);
        caseFoldedPlugins.insert(foldedName);

        SearchPluginInfo plugin;
        plugin.name = pluginName;
        plugin.version = getPluginVersion(pluginPath(pluginName));
        plugin.fullName = nameNodes.at(0).toElement().text().left(512);
        plugin.url = urlNodes.at(0).toElement().text().left(4096);

        const QStringList categories = categoryNodes.at(0).toElement().text().split(u' ');
        for (QString cat : categories)
        {
            cat = cat.trimmed();
            if (!cat.isEmpty())
                plugin.supportedCategories << cat.left(64);
        }

        plugin.enabled = !disabledEngines.contains(pluginName);
        updateIconPath(&plugin);
        parsedPlugins.insert(pluginName, plugin);
    }

    // Publish only after the whole XML generation has passed structural and
    // duplicate-id validation. A malformed late row cannot partially replace
    // the last known registry.
    m_registrationStale = false;
    setRuntimeError({});
    for (auto parsedIt = parsedPlugins.cbegin(); parsedIt != parsedPlugins.cend(); ++parsedIt)
    {
        const QString pluginName = parsedIt.key();
        const SearchPluginInfo &plugin = parsedIt.value();

        if (!m_plugins.contains(pluginName))
        {
            m_plugins[pluginName] = new SearchPluginInfo(plugin);
            qCInfo(lcSearch).noquote() << QStringLiteral("Search plugin discovered: \"%1\" version %2 (enabled: %3)")
                .arg(pluginName, plugin.version.toString(), (plugin.enabled ? u"yes"_s : u"no"_s));
            if (!suppressSignals)
                emit pluginInstalled(pluginName);
        }
        else
        {
            SearchPluginInfo *existing = m_plugins[pluginName];
            const bool versionChanged = existing->version != plugin.version;
            *existing = plugin;
            if (versionChanged)
            {
                qCInfo(lcSearch).noquote() << QStringLiteral("Search plugin updated: \"%1\" now version %2")
                    .arg(pluginName, plugin.version.toString());
                if (!suppressSignals)
                    emit pluginUpdated(pluginName);
            }
        }
    }

    // A failed import must remove an older in-memory entry. Without this
    // reconciliation an update that replaced a working file with a broken one
    // still looked successful merely because the previous capability object
    // remained in m_plugins.
    for (auto it = m_plugins.begin(); it != m_plugins.end();)
    {
        if (discoveredPlugins.contains(it.key()))
        {
            ++it;
            continue;
        }

        qCWarning(lcSearch) << "Search plugin no longer registered by the runtime:" << it.key();
        delete it.value();
        it = m_plugins.erase(it);
    }

    emit pluginCatalogChanged();
}

void SearchPluginManager::parseVersionInfo(const QByteArray &info)
{
    QHash<QString, SearchPluginVersion> updateInfo;
    int numCorrectData = 0;
    int numInvalidData = 0;

    const QList<QByteArrayView> lines = Utils::ByteArray::splitToViews(info, "\n");
    for (QByteArrayView line : lines)
    {
        line = line.trimmed();

        if (line.isEmpty())
            continue;
        if (line.startsWith('#'))
            continue;

        const QList<QByteArrayView> list = Utils::ByteArray::splitToViews(line, ":");
        if (list.size() != 2)
        {
            ++numInvalidData;
            continue;
        }

        const auto version = SearchPluginVersion::fromString(QString::fromLatin1(list.last().trimmed()));
        if (!version.isValid())
        {
            ++numInvalidData;
            continue;
        }

        ++numCorrectData;

        const auto pluginName = QString::fromUtf8(list.first().trimmed());
        if (isUpdateNeeded(pluginName, version))
        {
            qCInfo(lcSearch).noquote() << tr("Plugin \"%1\" is outdated, updating to version %2").arg(pluginName, version.toString());
            updateInfo[pluginName] = version;
        }
    }

    if (numInvalidData > 0)
    {
        qCWarning(lcSearch).noquote() << tr("Incorrect update info received for %1 out of %2 plugins.")
            .arg(QString::number(numInvalidData), QString::number(numCorrectData + numInvalidData));
        emit checkForUpdatesFailed(tr("Incorrect update info received for %1 out of %2 plugins.")
            .arg(QString::number(numInvalidData), QString::number(numCorrectData + numInvalidData)));
    }
    else
    {
        qCInfo(lcSearch) << "Plugin update check complete;" << updateInfo.size() << "plugin(s) need updating";
        emit checkForUpdatesFinished(updateInfo);
    }
}

bool SearchPluginManager::isUpdateNeeded(const QString &pluginName, const SearchPluginVersion &newVersion) const
{
    if (!isSafeCatalogID(pluginName) || !runtimeReady() || m_catalogEntries.contains(pluginName)
        || !pluginPath(pluginName).exists())
        return false;

    const SearchPluginInfo *plugin = pluginInfo(pluginName);
    if (!plugin)
        return false;

    const SearchPluginVersion oldVersion = plugin->version;
    return (newVersion > oldVersion);
}

Path SearchPluginManager::pluginPath(const QString &name)
{
    return (pluginsLocation() / Path(name + u".py"));
}

SearchPluginVersion SearchPluginManager::getPluginVersion(const Path &filePath)
{
    const int lineMaxLength = 16;

    QFile pluginFile {filePath.data()};
    if (!pluginFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    while (!pluginFile.atEnd())
    {
        const auto line = QString::fromUtf8(pluginFile.readLine(lineMaxLength)).remove(u' ');
        if (!line.startsWith(u"#VERSION:", Qt::CaseInsensitive))
            continue;

        const QString versionStr = line.sliced(9);
        const auto version = SearchPluginVersion::fromString(versionStr);
        if (version.isValid())
            return version;

        qCWarning(lcSearch).noquote() << tr("Search plugin '%1' contains invalid version string ('%2')")
            .arg(filePath.filename(), versionStr);
        break;
    }

    return {};
}
