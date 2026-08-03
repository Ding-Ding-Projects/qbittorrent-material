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

#include <memory>

#include <QDir>
#include <QDirIterator>
#include <QDomDocument>
#include <QDomElement>
#include <QDomNode>
#include <QFile>
#include <QProcess>
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
#include "searchdownloadhandler.h"
#include "searchhandler.h"

namespace
{
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
    , m_proxyEnv {QProcessEnvironment::systemEnvironment()}
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

    // Defer the capabilities probe off the construction path. update() spawns
    // Python and blocks on waitForFinished(); measured at ~175 ms here. Search
    // is enabled by default in this fork, so doing that inline would stall every
    // startup on the GUI thread. Deferring also means the signals it emits
    // (pluginInstalled, runtimeErrorChanged) reach SearchController, which
    // connects to them after this constructor returns — inline, they were
    // emitted before anything was listening.
    QTimer::singleShot(0, this, [this] { update(); });

    qCInfo(lcSearch) << "Search plugin manager ready; capabilities probe queued";
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

QStringList SearchPluginManager::enabledPlugins() const
{
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

    if (destPath != srcPath)
    {
        // Plugin is not already at the destination path, otherwise there is nothing to copy.

        // Backup in case the install fails.
        if (hasExistingPlugin)
        {
            hasBackup = Utils::Fs::copyFile(destPath, backupPath);
            Utils::Fs::removeFile(destPath);
            qCDebug(lcSearch) << "Backed up existing plugin" << name << "->" << backupPath.toString() << "success:" << hasBackup;
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

    // Update the supported plugins catalog.
    update();

    // Check if it was correctly installed.
    if (m_plugins.contains(name))
    {
        // Installation successful.
        qCInfo(lcSearch).noquote() << tr("Search plugin has been updated. Plugin name: \"%1\". Version: %2.")
            .arg(name, incomingVersion.toString());

        if (hasBackup)
            Utils::Fs::removeFile(backupPath);
    }
    else
    {
        qCWarning(lcSearch).noquote() << tr("Search plugin installation failed. Plugin name: \"%1\"").arg(name);

        // Roll back.
        Utils::Fs::removeFile(destPath);
        if (hasBackup)
        {
            // Restore backup.
            if (Utils::Fs::copyFile(backupPath, destPath))
            {
                Utils::Fs::removeFile(backupPath);
                update(); // Update the supported plugins catalog.
            }
            else
            {
                Utils::Fs::removeFile(destPath);
            }
        }

        const QString errMsg = tr("Plugin is not supported.");
        if (hasExistingPlugin)
            emit pluginUpdateFailed(name, errMsg);
        else
            emit pluginInstallationFailed(name, errMsg);
    }
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

    qCInfo(lcSearch) << "Search plugin uninstalled:" << name;
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
    DownloadManager::instance()->download({m_updateUrl + u"versions.txt"}
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
            const QString credential = proxyConfig.authEnabled
                ? (proxyConfig.username + u':' + proxyConfig.password + u'@')
                : QString();
            const QString proxyURL = u"http://%1%2:%3"_s
                .arg(credential, proxyConfig.ip, QString::number(proxyConfig.port));

            m_proxyEnv.insert(HTTP_PROXY, proxyURL);
            m_proxyEnv.insert(HTTPS_PROXY, proxyURL);
            m_proxyEnv.remove(SOCKS_PROXY);
            qCDebug(lcSearch) << "Applied HTTP proxy to search environment:" << proxyConfig.ip << proxyConfig.port;
        }
        break;

    case Net::ProxyType::SOCKS5:
        {
            const QString scheme = proxyConfig.hostnameLookupEnabled ? u"socks5h"_s : u"socks5"_s;
            const QString credential = proxyConfig.authEnabled
                ? (proxyConfig.username + u':' + proxyConfig.password + u'@')
                : QString();
            const QString proxyURL = u"%1://%2%3:%4"_s
                .arg(scheme, credential, proxyConfig.ip, QString::number(proxyConfig.port));

            m_proxyEnv.remove(HTTP_PROXY);
            m_proxyEnv.remove(HTTPS_PROXY);
            m_proxyEnv.insert(SOCKS_PROXY, proxyURL);
            qCDebug(lcSearch) << "Applied SOCKS5 proxy to search environment:" << proxyConfig.ip << proxyConfig.port;
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

// Write the plugins bundled in our own resources into the profile, so the
// Search tab has sources without the user having to install anything.
void SearchPluginManager::seedBundledPlugins()
{
    const Path bundledDir {u":/searchengine/nova3/engines"_s};
    QDirIterator it {bundledDir.data(), {u"*.py"_s}, QDir::Files};
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

    qCInfo(lcSearch) << "Bundled search plugins seeded:" << written << "written,"
        << seeded.size() << "known";
}

void SearchPluginManager::update()
{
    qCDebug(lcSearch) << "Refreshing search engine capabilities via nova2.py --capabilities";

    // Fail loudly on the two prerequisites the user can actually act on, rather
    // than letting QProcess fail obscurely and leaving the Search tab claiming
    // that no plugins are installed.
    const Utils::ForeignApps::PythonInfo pyInfo = Utils::ForeignApps::pythonInfo();
    if (!pyInfo.isValid())
    {
        const QString reason = tr("Python was not found. Search needs a Python %1 or later interpreter on PATH, or one selected in Options.")
            .arg(Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
        qCWarning(lcSearch).noquote() << reason;
        setRuntimeError(reason);
        return;
    }
    if (!pyInfo.isSupportedVersion())
    {
        // Not fatal — nova may still run — but record it so a later failure is
        // attributable instead of looking like "no plugins installed".
        qCWarning(lcSearch).noquote() << QStringLiteral("Python %1 is below the supported minimum %2")
            .arg(pyInfo.version.toString(), Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
    }
    const Path pythonPath = pyInfo.executablePath;

    const Path novaScript = engineLocation() / Path(u"nova2.py"_s);
    if (!novaScript.exists())
    {
        const QString reason = tr("The bundled search runtime is missing. Expected \"%1\".").arg(novaScript.toString());
        qCWarning(lcSearch).noquote() << reason;
        setRuntimeError(reason);
        return;
    }

    QProcess nova;
    nova.setProcessEnvironment(proxyEnvironment());
#ifdef Q_OS_UNIX
    nova.setUnixProcessParameters(QProcess::UnixProcessFlag::CloseFileDescriptors);
#endif

    const QStringList params
    {
        Utils::ForeignApps::PYTHON_ISOLATE_MODE_FLAG,
        Utils::ForeignApps::PYTHON_UTF8_MODE_FLAG,
        novaScript.toString(),
        u"--capabilities"_s
    };
    nova.start(pythonPath.data(), params, QIODevice::ReadOnly);
    if (!nova.waitForFinished(10000))
    {
        qCWarning(lcSearch) << "Timed out while fetching search engine capabilities";
        nova.kill();
        nova.waitForFinished(1000);
        setRuntimeError(tr("The search runtime did not respond within 10 seconds."));
        return;
    }

    const auto stdErrMsg = QString::fromUtf8(nova.readAllStandardError()).trimmed();
    if (!stdErrMsg.isEmpty())
    {
        qCWarning(lcSearch).noquote() << tr("Error occurred when fetching search engine capabilities. Error: \"%1\".").arg(stdErrMsg);
    }

    const auto capabilities = QString::fromUtf8(nova.readAllStandardOutput());
    QDomDocument xmlDoc;
    if (!xmlDoc.setContent(capabilities))
    {
        const QString reason = stdErrMsg.isEmpty()
            ? tr("The search runtime returned no usable plugin capabilities.")
            : tr("The search runtime failed to start. Error: \"%1\".").arg(stdErrMsg);
        qCWarning(lcSearch).noquote() << QStringLiteral("Could not parse nova search engine capabilities. Output: %1").arg(capabilities);
        setRuntimeError(reason);
        return;
    }

    const QDomElement root = xmlDoc.documentElement();
    if (root.tagName() != u"capabilities")
    {
        qCWarning(lcSearch).noquote() << QStringLiteral("Invalid XML for nova search engine capabilities. Output: %1").arg(capabilities);
        setRuntimeError(tr("The search runtime reported malformed plugin capabilities."));
        return;
    }

    setRuntimeError({});

    for (QDomNode engineNode = root.firstChild(); !engineNode.isNull(); engineNode = engineNode.nextSibling())
    {
        const QDomElement engineElem = engineNode.toElement();
        if (engineElem.isNull())
            continue;

        const QString pluginName = engineElem.tagName();

        auto plugin = std::make_unique<SearchPluginInfo>();
        plugin->name = pluginName;
        plugin->version = getPluginVersion(pluginPath(pluginName));
        plugin->fullName = engineElem.elementsByTagName(u"name"_s).at(0).toElement().text();
        plugin->url = engineElem.elementsByTagName(u"url"_s).at(0).toElement().text();

        const QStringList categories = engineElem.elementsByTagName(u"categories"_s).at(0).toElement().text().split(u' ');
        for (QString cat : categories)
        {
            cat = cat.trimmed();
            if (!cat.isEmpty())
                plugin->supportedCategories << cat;
        }

        const QStringList disabledEngines = Preferences::instance()->getSearchEngDisabled();
        plugin->enabled = !disabledEngines.contains(pluginName);

        updateIconPath(plugin.get());

        if (!m_plugins.contains(pluginName))
        {
            const SearchPluginVersion version = plugin->version;
            m_plugins[pluginName] = plugin.release();
            qCInfo(lcSearch).noquote() << QStringLiteral("Search plugin discovered: \"%1\" version %2 (enabled: %3)")
                .arg(pluginName, version.toString(), (m_plugins[pluginName]->enabled ? u"yes"_s : u"no"_s));
            emit pluginInstalled(pluginName);
        }
        else if (m_plugins[pluginName]->version != plugin->version)
        {
            const SearchPluginVersion version = plugin->version;
            delete m_plugins.take(pluginName);
            m_plugins[pluginName] = plugin.release();
            qCInfo(lcSearch).noquote() << QStringLiteral("Search plugin updated: \"%1\" now version %2")
                .arg(pluginName, version.toString());
            emit pluginUpdated(pluginName);
        }
    }
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
    const SearchPluginInfo *plugin = pluginInfo(pluginName);
    if (!plugin)
        return true;

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
