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

#include <functional>

#include <QByteArray>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QProcessEnvironment>
#include <QQueue>
#include <QVariantList>
#include <QVariantMap>

#include "base/path.h"
#include "base/utils/version.h"

/// Two-component version (major.minor) of a Python search plugin.
using SearchPluginVersion = Utils::Version<2>;

namespace Net
{
    struct DownloadResult;
}

class QProcess;
class QTimer;

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
    /// True only when the most recent capabilities generation completed and
    /// the in-memory plugin registry belongs to that successful generation.
    [[nodiscard]] bool runtimeReady() const;

    /// Snapshot of the verified unofficial-plugin catalog bootstrap. The map
    /// contains row/source/canonical counts plus live completed/installed/
    /// failed/skipped counts, so the UI can report one honest aggregate state
    /// instead of opening a notification for every third-party engine.
    [[nodiscard]] QVariantMap unofficialCatalogStatus() const;
    /// Palette-facing union of every validated canonical catalog entry, every
    /// bundled default, and every runtime-registered custom plugin. Unlike
    /// allPlugins(), this inventory remains useful while Python is unavailable.
    /// Each map explicitly reports disk/registration/runtime state and which
    /// recovery or management actions are currently meaningful.
    [[nodiscard]] QVariantList palettePluginCatalog() const;
    void retryUnofficialCatalogSync();
    /// Promotes one SHA-256-verified catalog candidate out of quarantine and
    /// validates it before it can remain in the active Python engine folder.
    /// New and changed third-party bytes are never imported before this
    /// explicit user action.
    void trustUnofficialPlugin(const QString &id);

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

    /// Emitted once after a successful full runtime reconciliation, including
    /// silent startup/catalog probes where the per-plugin signals are suppressed.
    void pluginCatalogChanged();

    void checkForUpdatesFinished(const QHash<QString, SearchPluginVersion> &updateInfo);
    void checkForUpdatesFailed(const QString &reason);

    /// Emitted whenever the outcome of `nova2.py --capabilities` changes.
    /// @p reason is empty once the runtime works again.
    void runtimeErrorChanged(const QString &reason);

    /// Aggregate lifecycle for the verified default unofficial catalog.
    /// Individual bootstrap downloads deliberately do not emit the ordinary
    /// install/update signals, preventing a 90-plus notification storm.
    void unofficialCatalogStatusChanged(const QVariantMap &status);
    void unofficialCatalogSyncFinished(const QVariantMap &status);
    void unofficialPluginTrusted(const QString &id);
    void unofficialPluginTrustFailed(const QString &id, const QString &reason);

private:
    struct CatalogSource
    {
        QString url;
        QByteArray sha256;
    };

    struct CatalogEntry
    {
        QString id;
        QList<CatalogSource> sources;
        QString unavailableReason;
    };

    struct CatalogActivationTransaction
    {
        QByteArray candidateHash;
        QByteArray previousActiveHash;
        Path backupPath;
        quint64 generation = 0;
        bool hadActive = false;
    };

    struct CapabilityRequest
    {
        bool suppressSignals = false;
        std::function<void()> completed;
    };

    struct CapabilityProbeResult
    {
        QString standardOutput;
        QString standardError;
        QString processError;
        bool started = false;
        bool timedOut = false;
        bool outputOverflow = false;
    };

    struct CatalogLedgerEntry
    {
        QByteArray expectedHash;
        QByteArray observedHash;
        QByteArray activeHash;
        QString sourceUrl;
        QString integrityState;
        QString runtimeState;
        QString diagnostic;
        quint64 generation = 0;
        bool catalogOwned = false;
        bool trusted = false;
        bool userRemoved = false;
    };

    void applyProxySettings();
    void update(bool suppressSignals = false, std::function<void()> completed = {});
    void startNextCapabilityProbe();
    void drainCapabilityOutput();
    void completeCapabilityProbe();
    void applyCapabilityProbeResult(const CapabilityProbeResult &result, bool suppressSignals);
    void finishCapabilityRequest(const CapabilityRequest &request);
    void failCapabilityGeneration(const QString &reason);
    void updateNova();
    void seedBundledPlugins();
    void loadCatalogLedger();
    bool saveCatalogLedger();
    void startUnofficialCatalogSync();
    void downloadNextUnofficialPlugin();
    void downloadCurrentUnofficialSource();
    void unofficialPluginDownloadFinished(const Net::DownloadResult &result);
    void startUnofficialCatalogActivation();
    void finishUnofficialCatalogActivation();
    void recordUnofficialCatalogActivationFailure(const QString &id, const QString &reason);
    void finishUnofficialCatalogSync();
    void failUnofficialCatalogSync(const QString &reason);
    void parseVersionInfo(const QByteArray &info);
    void installPlugin_impl(const QString &name, const Path &srcPath);
    bool isUpdateNeeded(const QString &pluginName, const SearchPluginVersion &newVersion) const;

    void versionInfoDownloadFinished(const Net::DownloadResult &result);
    void pluginDownloadFinished(const Net::DownloadResult &result);

    static Path pluginPath(const QString &name);
    static Path catalogQuarantineLocation();
    static Path catalogQuarantinePath(const QString &name, const QByteArray &sha256);
    static Path catalogLedgerPath();

    void setRuntimeError(const QString &reason);

    static QPointer<SearchPluginManager> m_instance;

    const QString m_updateUrl;

    QHash<QString, SearchPluginInfo *> m_plugins;
    QProcessEnvironment m_proxyEnv;
    QString m_runtimeError;
    bool m_registrationStale = true;
    QHash<QString, QString> m_pluginImportErrors;
    QHash<QString, CatalogLedgerEntry> m_catalogLedger;

    QQueue<CatalogEntry> m_catalogQueue;
    /// Last completely validated manifest, retained across retries. Never fill
    /// this map from a partial or failed parse: palette consumers must not turn
    /// unvalidated JSON into commands.
    QHash<QString, CatalogEntry> m_catalogEntries;
    CatalogEntry m_currentCatalogEntry;
    int m_currentCatalogSource = 0;
    QStringList m_catalogPendingSeeded;
    QStringList m_catalogCanonicalIDs;
    QStringList m_bundledPluginIDs;
    QStringList m_catalogFailures;
    QString m_currentCatalogFailure;
    QVariantMap m_catalogStatus;
    QHash<QString, CatalogActivationTransaction> m_catalogActivationTransactions;
    // True when at least one catalog entry was already present on disk before
    // this synchronization. Kept separately from the counters so the UI and
    // diagnostics can distinguish a no-op bootstrap from a fresh install.
    bool m_catalogPreexisting = false;
    bool m_catalogSyncInProgress = false;
    bool m_catalogRetryPending = false;
    // A user explicitly requested another catalog run after a stored runtime
    // incompatibility. Consume this one-shot intent at sync start; background
    // startup/reconciliation must retain the incompatibility diagnosis.
    bool m_catalogRuntimeIncompatibleRetryRequested = false;
    bool m_catalogAutoActivationAttempted = false;
    bool m_catalogAutoActivationInProgress = false;

    QQueue<CapabilityRequest> m_capabilityRequests;
    CapabilityRequest m_activeCapabilityRequest;
    QProcess *m_capabilityProcess = nullptr;
    QTimer *m_capabilityTimeout = nullptr;
    bool m_capabilityProbeRunning = false;
    bool m_capabilityProbeStarted = false;
    bool m_capabilityProbeTimedOut = false;
    bool m_capabilityProbeCompleting = false;
    QByteArray m_capabilityStdOut;
    QByteArray m_capabilityStdErr;
    bool m_capabilityOutputOverflow = false;
};
