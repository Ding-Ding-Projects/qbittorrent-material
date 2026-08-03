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
#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantList>

// SearchResultsModel/SearchResultsProxyModel must be COMPLETE here: resultsModel()
// is a Q_INVOKABLE returning SearchResultsProxyModel*, so moc records the type in
// the metatype array and it must be a complete type (else staticMetaObject fails
// to constinit — MSVC C2737).
#include "models/searchresultsmodel.h"

class QJSEngine;
class QQmlEngine;

class SearchHandler;
class SearchDownloadHandler;
class SearchPluginManager;

/**
 * @file searchcontroller.h
 * @brief The @c SearchController QML singleton — the thin bridge between the
 *        QML Search tab and the process-driven @c SearchPluginManager /
 *        @c SearchHandler engine layer.
 *
 * Responsibilities:
 *  - Own one search "tab" per running/finished query, each with its own
 *    @c SearchResultsModel + @c SearchResultsProxyModel, and stream engine
 *    results into them (subscribing to @c SearchHandler signals — never polling).
 *  - Guard every search / refresh on Python availability.
 *  - Feed the top-bar combos (category scope, plugin scope) and the search
 *    history completer.
 *  - Route result downloads: magnets and description pages are forwarded to the
 *    add-torrent pipeline; non-magnet links are fetched via
 *    @c SearchDownloadHandler first.
 *
 * Accessed from QML by name: `SearchController.startSearch(...)`,
 * `SearchController.tabs`, `SearchController.resultsModel(id)`, …
 */
class SearchController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    /// Whether a usable Python interpreter was detected (search is disabled
    /// entirely without it).
    Q_PROPERTY(bool pythonAvailable READ pythonAvailable NOTIFY pythonAvailableChanged)
    /// Why search cannot run at all, or an empty string when it can. Lets the
    /// empty page distinguish "no plugins installed yet" (actionable: install
    /// some) from "Python or the nova runtime is missing" (installing plugins
    /// would fail too).
    Q_PROPERTY(QString unavailableReason READ unavailableReason NOTIFY unavailableReasonChanged)
    /// Whether at least one search plugin is installed (drives the empty page).
    Q_PROPERTY(bool pluginsInstalled READ pluginsInstalled NOTIFY pluginsChanged)
    /// Open tabs, as a list of `{ id, pattern, status }` objects (for the TabBar).
    Q_PROPERTY(QVariantList tabs READ tabs NOTIFY tabsChanged)
    /// The plugin-scope combo items, as `{ label, value }` objects.
    Q_PROPERTY(QVariantList pluginScopes READ pluginScopes NOTIFY pluginsChanged)
    /// The search-input history (most-recent first).
    Q_PROPERTY(QStringList history READ history NOTIFY historyChanged)

public:
    /// Per-tab lifecycle status (numeric values mirror the legacy enum).
    enum Status
    {
        Ready = 0,
        Ongoing,
        Finished,
        Error,
        Aborted,
        NoResults
    };
    Q_ENUM(Status)

    /// How a result download interacts with the add-torrent dialog.
    enum AddTorrentOption
    {
        DefaultOption = 0,
        ShowDialog,
        SkipDialog
    };
    Q_ENUM(AddTorrentOption)

    /// "Search in" results filter mode (persisted numeric values).
    enum NameFilteringMode
    {
        Everywhere = 0,
        OnlyNames = 1
    };
    Q_ENUM(NameFilteringMode)

    explicit SearchController(QObject *parent = nullptr);
    ~SearchController() override;

    /// QML singleton factory — returns the app-owned shared instance.
    static SearchController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    [[nodiscard]] bool pythonAvailable() const { return m_pythonAvailable; }
    [[nodiscard]] QString unavailableReason() const;
    [[nodiscard]] bool pluginsInstalled() const;

    /// Re-probes for a Python interpreter (e.g. after the user installs one or
    /// points Options at a different executable).
    Q_INVOKABLE void refreshPythonDetection();
    [[nodiscard]] QVariantList tabs() const;
    [[nodiscard]] QVariantList pluginScopes() const;
    [[nodiscard]] QStringList history() const { return m_history; }

    // ---- Combo population ---------------------------------------------------

    /// Category items `{ label, value }` for a given plugin scope
    /// ("enabled" / "all" / "multi" / a specific plugin id).
    Q_INVOKABLE QVariantList categoriesForScope(const QString &scope) const;

    // ---- Search lifecycle ---------------------------------------------------

    /// Start a new search. Returns the new tab id, or -1 if it could not start
    /// (no Python, empty pattern, no plugins). @p scope is a plugin-scope token.
    Q_INVOKABLE int startSearch(const QString &pattern, const QString &category,
                                const QString &scope, bool regexEnabled = false,
                                const QString &regexFlags = QStringLiteral("iu"));

    /// Re-run the query owned by @p tabId in place (context-menu "Refresh tab").
    Q_INVOKABLE void refreshTab(int tabId);

    /// Cancel the running search in @p tabId (context-menu "Stop search").
    Q_INVOKABLE void stopSearch(int tabId);

    /// Close a tab and free its models/handler.
    Q_INVOKABLE void closeTab(int tabId);

    /// Close every tab.
    Q_INVOKABLE void closeAllTabs();

    // ---- Per-tab accessors --------------------------------------------------

    /// The proxy model QML binds a DataTable to (nullptr for an unknown id).
    Q_INVOKABLE SearchResultsProxyModel *resultsModel(int tabId) const;

    [[nodiscard]] Q_INVOKABLE QString tabPattern(int tabId) const;
    [[nodiscard]] Q_INVOKABLE int tabStatus(int tabId) const;

    /// Human status text / status-icon id for a @c Status value.
    [[nodiscard]] Q_INVOKABLE QString statusText(int status) const;
    [[nodiscard]] Q_INVOKABLE QString statusIcon(int status) const;

    // ---- Result actions -----------------------------------------------------

    /// Download the result at @p proxyRow of @p tabId. Magnets are added
    /// directly; other links are fetched to a .torrent first. @p option chooses
    /// whether the add dialog is shown.
    Q_INVOKABLE void downloadTorrent(int tabId, int proxyRow, int option);

    /// Open each selected row's description page in the external browser.
    Q_INVOKABLE void openDescriptionPages(int tabId, const QList<int> &proxyRows);

    /// Clipboard helpers for the results context menu.
    Q_INVOKABLE void copyNames(int tabId, const QList<int> &proxyRows) const;
    Q_INVOKABLE void copyDownloadLinks(int tabId, const QList<int> &proxyRows) const;
    Q_INVOKABLE void copyDescriptionPages(int tabId, const QList<int> &proxyRows) const;

    // ---- Plugin management (Search Plugins dialog) --------------------------

    /// Enable / disable a single plugin.
    Q_INVOKABLE void enablePlugin(const QString &id, bool enabled);
    /// Enable / disable a batch of plugins.
    Q_INVOKABLE void enablePlugins(const QStringList &ids, bool enabled);
    /// Uninstall a batch of plugins; bundled ones are disabled instead and a
    /// summary is reported via @c notify().
    Q_INVOKABLE void uninstallPlugins(const QStringList &ids);
    /// Install one or more plugins from local @c .py files.
    Q_INVOKABLE void installPluginsFromFiles(const QStringList &paths);
    /// Install a plugin from an http(s)/file URL (must end in @c .py).
    Q_INVOKABLE void installPluginFromUrl(const QString &url);
    /// Download @c versions.txt and update any out-of-date plugins.
    Q_INVOKABLE void checkForPluginUpdates();
    /// The human display name for a plugin id (for feedback strings).
    [[nodiscard]] Q_INVOKABLE QString pluginFullName(const QString &id) const;

    // ---- History ------------------------------------------------------------

    Q_INVOKABLE void clearHistory();

    // ---- Persisted results-filter settings (shared across tabs) -------------

    [[nodiscard]] Q_INVOKABLE int nameFilteringMode() const;
    Q_INVOKABLE void setNameFilteringMode(int mode);
    [[nodiscard]] Q_INVOKABLE bool resultsFilterUsesRegex() const;
    Q_INVOKABLE void setResultsFilterUsesRegex(bool enabled);
    [[nodiscard]] Q_INVOKABLE QString resultsFilterRegexFlags() const;
    Q_INVOKABLE void setResultsFilterRegexFlags(const QString &flags);

signals:
    void pythonAvailableChanged();
    void unavailableReasonChanged();
    void pluginsChanged();
    void tabsChanged();
    void historyChanged();

    /// A tab's status changed (drives its TabButton icon/tooltip).
    void tabStatusChanged(int tabId, int status);
    /// A tab received new rows (drives the "Results (X of Y)" label refresh).
    void tabResultsChanged(int tabId);

    /// A search finished; @p failed true on error. When the Search tab is not
    /// focused the shell shows a Snackbar / tray notification.
    void searchFinished(int tabId, bool failed);

    /// Forward an add source (magnet / URL / local .torrent path) to the
    /// add-torrent pipeline. @p showDialog picks the add-dialog behavior.
    void addTorrentRequested(const QString &source, bool showDialog);

    /// Non-blocking user feedback (shown via Snackbar / tray).
    void notify(const QString &message);

    /// The Search Plugins dialog should be opened (scope combo picked "Select…").
    void pluginSelectionRequested();

    // Plugin-management outcomes (forwarded from SearchPluginManager) — the
    // Search Plugins dialog turns these into inline feedback.
    void pluginInstalled(const QString &name);
    void pluginInstallFailed(const QString &name, const QString &reason);
    void pluginUpdated(const QString &name);
    void pluginUpdateFailed(const QString &name, const QString &reason);
    void pluginUninstalled(const QString &name);
    /// Update check finished; @p hasUpdates false means everything was current.
    void pluginUpdatesChecked(bool hasUpdates);
    void pluginUpdateCheckFailed(const QString &reason);

private:
    /// One open search tab: its query, engine handler, and models.
    struct SearchTab
    {
        int id = 0;
        QString pattern;
        QString category;
        QStringList plugins;
        QString scope;
        bool regexEnabled = false;
        QString regexFlags = QStringLiteral("iu");
        Status status = Ready;
        SearchHandler *handler = nullptr;
        SearchResultsModel *model = nullptr;
        SearchResultsProxyModel *proxy = nullptr;
    };

    [[nodiscard]] SearchTab *tabById(int id);
    [[nodiscard]] const SearchTab *tabById(int id) const;
    [[nodiscard]] QStringList pluginsForScope(const QString &scope) const;

    void wireHandler(SearchTab *tab);
    void setTabStatus(SearchTab *tab, Status status);
    void addToHistory(const QString &pattern);
    void loadHistory();
    void saveHistoryAsync() const;
    void detectPython();
    void doDownload(SearchTab *tab, int sourceRow, bool showDialog);

    bool m_pythonAvailable = false;
    int m_nextTabId = 1;
    QList<SearchTab *> m_tabs;
    QStringList m_history;

    static SearchController *s_instance;
};
