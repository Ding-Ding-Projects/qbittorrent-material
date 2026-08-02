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
 */

#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcessEnvironment>

#include "base/path.h"
#include "base/utils/version.h"

/// Two-component version (major.minor) of a Python search plugin.
using SearchPluginVersion = Utils::Version<2>;

namespace Net
{
    struct DownloadResult;
}

/// Metadata describing an installed search engine plugin (the Python "nova" plugins).
struct SearchPluginInfo
{
    QString name;
    SearchPluginVersion version;
    QString fullName;
    QString url;
    QStringList supportedCategories;
    Path iconPath;
    bool enabled = false;
};

class SearchDownloadHandler;
class SearchHandler;

/// Singleton manager over the Python-driven search subsystem. Owns the installed
/// plugin catalog, install/uninstall/enable/update lifecycle, and spawns
/// `SearchHandler`/`SearchDownloadHandler` processes. Bridged to QML via
/// `SearchController` + `SearchPluginsModel`; consumers subscribe to the signals
/// below rather than polling. Log every plugin action/state change via `lcSearch`.
class SearchPluginManager final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SearchPluginManager)

public:
    SearchPluginManager();
    ~SearchPluginManager() override;

    static SearchPluginManager *instance();
    static void freeInstance();

    QStringList allPlugins() const;
    QStringList enabledPlugins() const;
    QStringList supportedCategories() const;
    QStringList getPluginCategories(const QString &pluginName) const;
    SearchPluginInfo *pluginInfo(const QString &name) const;
    QString pluginNameBySiteURL(const QString &siteURL) const;

    void enablePlugin(const QString &name, bool enabled = true);
    void updatePlugin(const QString &name);
    void installPlugin(const QString &source);
    bool uninstallPlugin(const QString &name);
    static void updateIconPath(SearchPluginInfo *plugin);
    void checkForUpdates();

    /// Starts an asynchronous search; the returned handler streams results via its
    /// own signals and is owned by the caller's context.
    SearchHandler *startSearch(const QString &pattern, const QString &category, const QStringList &usedPlugins);
    /// Downloads a result's torrent through the owning plugin (may resolve a magnet).
    SearchDownloadHandler *downloadTorrent(const QString &pluginName, const QString &url);

    QProcessEnvironment proxyEnvironment() const;

    /// Human-readable reason the nova runtime could not be queried, or an empty
    /// string when the last `nova2.py --capabilities` run succeeded. Lets the UI
    /// distinguish "no plugins installed yet" from "search cannot run at all".
    [[nodiscard]] QString runtimeError() const;

    /// Re-extracts the bundled runtime and re-runs the capabilities query. Used
    /// when the user fixes a prerequisite (installs Python, points Options at an
    /// interpreter) and asks to try again without restarting.
    void reload();

    static SearchPluginVersion getPluginVersion(const Path &filePath);
    static QString categoryFullName(const QString &categoryName);
    QString pluginFullName(const QString &pluginName) const;
    static Path pluginsLocation();
    static Path engineLocation();

signals:
    void pluginEnabled(const QString &name, bool enabled);
    void pluginInstalled(const QString &name);
    void pluginInstallationFailed(const QString &name, const QString &reason);
    void pluginUninstalled(const QString &name);
    void pluginUpdated(const QString &name);
    void pluginUpdateFailed(const QString &name, const QString &reason);

    void checkForUpdatesFinished(const QHash<QString, SearchPluginVersion> &updateInfo);
    void checkForUpdatesFailed(const QString &reason);

    /// Emitted whenever the outcome of `nova2.py --capabilities` changes.
    /// @p reason is empty once the runtime works again.
    void runtimeErrorChanged(const QString &reason);

private:
    void applyProxySettings();
    void update();
    void updateNova();
    void seedBundledPlugins();
    void parseVersionInfo(const QByteArray &info);
    void installPlugin_impl(const QString &name, const Path &srcPath);
    bool isUpdateNeeded(const QString &pluginName, const SearchPluginVersion &newVersion) const;

    void versionInfoDownloadFinished(const Net::DownloadResult &result);
    void pluginDownloadFinished(const Net::DownloadResult &result);

    static Path pluginPath(const QString &name);

    void setRuntimeError(const QString &reason);

    static QPointer<SearchPluginManager> m_instance;

    const QString m_updateUrl;

    QHash<QString, SearchPluginInfo *> m_plugins;
    QProcessEnvironment m_proxyEnv;
    QString m_runtimeError;
};
