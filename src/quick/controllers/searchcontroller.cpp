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

#include "searchcontroller.h"

#include <algorithm>

#include <QClipboard>
#include <QDesktopServices>
#include <QFileInfo>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QUrl>
#include <QVariantMap>

#include "base/logging.h"
#include "base/preferences.h"
#include "base/search/searchdownloadhandler.h"
#include "base/search/searchhandler.h"
#include "base/search/searchpluginmanager.h"
#include "base/settingsstorage.h"
#include "base/utils/foreignapps.h"
#include "base/utils/fs/path.h"
#include "models/searchresultsmodel.h"

using namespace Qt::StringLiterals;

namespace
{
    const QString kHistoryKey = u"Search/History"_s;
    const QString kFilteringModeKey = u"Search/FilteringMode"_s;
    const QString kFilteringFlagsKey = u"Search/FilteringFlags"_s;

    QRegularExpression::PatternOptions regexOptions(const QString &flags)
    {
        QRegularExpression::PatternOptions options;
        if (flags.contains(u"i"_s))
            options |= QRegularExpression::CaseInsensitiveOption;
        if (flags.contains(u"m"_s))
            options |= QRegularExpression::MultilineOption;
        if (flags.contains(u"s"_s))
            options |= QRegularExpression::DotMatchesEverythingOption;
        if (flags.contains(u"u"_s))
            options |= QRegularExpression::UseUnicodePropertiesOption;
        return options;
    }
}

SearchController *SearchController::s_instance = nullptr;

SearchController::SearchController(QObject *parent)
    : QObject(parent)
{
    // Catalog bootstrap reports one status transition per verified plugin. A
    // direct pluginsChanged() for every row forces the always-live command
    // palette to rebuild hundreds of QML command objects and re-hash every
    // candidate file on the GUI thread. Coalesce those presentation updates;
    // the authoritative final signal still lands immediately after a batch.
    m_pluginsChangedTimer.setSingleShot(true);
    m_pluginsChangedTimer.setInterval(120);
    connect(&m_pluginsChangedTimer, &QTimer::timeout, this, [this]
    {
        if (!m_pluginsChangedPending)
            return;
        m_pluginsChangedPending = false;
        emit pluginsChanged();
    });

    detectPython();
    loadHistory();

    if (auto *mgr = SearchPluginManager::instance())
    {
        // Keep the combos / empty-page in sync as plugins come and go.
        connect(mgr, &SearchPluginManager::pluginEnabled, this,
                [this] { schedulePluginsChanged(); });
        connect(mgr, &SearchPluginManager::pluginCatalogChanged, this, [this] {
            finishRuntimeRecovery();
            schedulePluginsChanged(true);
        });

        // Forward install/update/uninstall outcomes to QML (dialog feedback),
        // and refresh the scope/category combos.
        connect(mgr, &SearchPluginManager::pluginInstalled, this, [this](const QString &name) {
            qCInfo(lcSearch) << "Plugin installed:" << name;
            setPluginDiagnostic(name, {});
            recordPluginBatchOutcome(name, true);
            emit pluginInstalled(name);
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::pluginInstallationFailed, this,
                [this](const QString &name, const QString &reason) {
            qCWarning(lcSearch) << "Plugin install failed:" << name << reason;
            setPluginDiagnostic(name, reason);
            recordPluginBatchOutcome(name, false, reason);
            emit pluginInstallFailed(name, reason);
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::pluginUpdated, this, [this](const QString &name) {
            qCInfo(lcSearch) << "Plugin updated:" << name;
            setPluginDiagnostic(name, {});
            recordPluginBatchOutcome(name, true);
            emit pluginUpdated(name);
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::pluginUpdateFailed, this,
                [this](const QString &name, const QString &reason) {
            qCWarning(lcSearch) << "Plugin update failed:" << name << reason;
            setPluginDiagnostic(name, reason);
            recordPluginBatchOutcome(name, false, reason);
            emit pluginUpdateFailed(name, reason);
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::pluginUninstalled, this, [this](const QString &name) {
            qCInfo(lcSearch) << "Plugin uninstalled:" << name;
            emit pluginUninstalled(name);
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::checkForUpdatesFinished, this,
                [this, mgr](const QHash<QString, SearchPluginVersion> &updateInfo) {
            qCInfo(lcSearch) << "Update check finished; outdated:" << updateInfo.size();
            if (!m_pluginBatch.active() || (m_pluginBatch.kind != u"update"_s)
                || !m_pluginBatch.awaitingUpdateList)
            {
                return;
            }

            // versions.txt contains engines that are not installed. Updating
            // those entries would reinstall user-removed defaults and used to
            // generate one failure notification for every unknown engine.
            QHash<QString, QVariantMap> inventory;
            for (const QVariant &entry : mgr->palettePluginCatalog())
            {
                const QVariantMap row = entry.toMap();
                inventory.insert(row.value(u"id"_s).toString(), row);
            }

            QStringList eligibleIDs;
            for (auto it = updateInfo.cbegin(); it != updateInfo.cend(); ++it)
            {
                const QVariantMap row = inventory.value(it.key());
                const bool installed = row.value(u"installedOnDisk"_s).toBool()
                    || row.value(u"registered"_s).toBool();
                if (installed && !row.value(u"userRemoved"_s).toBool())
                    eligibleIDs.append(it.key());
            }
            eligibleIDs.removeDuplicates();
            eligibleIDs.sort(Qt::CaseInsensitive);

            m_pluginBatch.awaitingUpdateList = false;
            m_pluginBatch.requested = eligibleIDs.size();
            m_pluginBatch.skipped = updateInfo.size() - eligibleIDs.size();
            m_pluginBatch.pending = QSet<QString>(eligibleIDs.cbegin(), eligibleIDs.cend());

            emit pluginUpdatesChecked(!eligibleIDs.isEmpty());
            if (eligibleIDs.isEmpty())
            {
                finishPluginBatch(u"no-updates"_s);
                return;
            }

            for (const QString &id : std::as_const(eligibleIDs))
                mgr->updatePlugin(id);
        });
        connect(mgr, &SearchPluginManager::checkForUpdatesFailed, this, [this](const QString &reason) {
            qCWarning(lcSearch) << "Update check failed:" << reason;
            if (m_pluginBatch.active() && (m_pluginBatch.kind == u"update"_s)
                && m_pluginBatch.awaitingUpdateList)
            {
                m_pluginBatch.awaitingUpdateList = false;
                m_pluginBatch.requested = 1;
                m_pluginBatch.failures.insert(u"update-check"_s, reason);
                finishPluginBatch(u"failed"_s);
            }
            emit pluginUpdateCheckFailed(reason);
        });
        // The nova runtime can only be probed once the manager exists, so the
        // empty state has to react to it rather than read it once at startup.
        connect(mgr, &SearchPluginManager::runtimeErrorChanged, this, [this](const QString &reason) {
            qCWarning(lcSearch) << "Search runtime state changed:" << (reason.isEmpty() ? u"ok"_s : reason);
            if (!reason.isEmpty() && m_pluginBatch.active()
                && (m_pluginBatch.kind == u"runtime-recovery"_s))
            {
                const QStringList pending = m_pluginBatch.pending.values();
                for (const QString &id : pending)
                {
                    setPluginDiagnostic(id, reason);
                    m_pluginBatch.failures.insert(id, reason);
                }
                m_pluginBatch.pending.clear();
                finishPluginBatch(u"runtime-unavailable"_s, reason);
            }
            emit unavailableReasonChanged();
            schedulePluginsChanged();
        });
        connect(mgr, &SearchPluginManager::unofficialCatalogStatusChanged, this,
                [this](const QVariantMap &status)
                {
                    // Progress belongs to its own lightweight status property.
                    // Do not rebuild the command palette for every downloaded
                    // row; the final sync signal below publishes the complete
                    // inventory once the asynchronous batch is settled.
                    if (!status.value(u"inProgress"_s).toBool())
                        schedulePluginsChanged(true);
                    emit unofficialPluginStatusChanged();
                });
        connect(mgr, &SearchPluginManager::unofficialCatalogSyncFinished, this,
                [this](const QVariantMap &status) {
            importCatalogDiagnostics(status);
            schedulePluginsChanged(true);
            emit unofficialPluginStatusChanged();
            emit unofficialPluginSyncFinished(status);
            QVariantMap summary = status;
            summary[u"kind"_s] = u"catalog"_s;
            summary[u"requested"_s] = status.value(u"canonicalCount"_s);
            summary[u"succeeded"_s] = status.value(u"registered"_s);
            publishPluginOperationSummary(summary);
        });
        connect(mgr, &SearchPluginManager::unofficialPluginTrusted,
                this, &SearchController::unofficialPluginTrusted);
        connect(mgr, &SearchPluginManager::unofficialPluginTrustFailed,
                this, &SearchController::unofficialPluginTrustFailed);
    }

    qCInfo(lcSearch) << "SearchController constructed; pythonAvailable=" << m_pythonAvailable
                     << "plugins=" << pluginsInstalled();
}

SearchController::~SearchController()
{
    closeAllTabs();
    qCDebug(lcSearch) << "SearchController destroyed";
}

SearchController *SearchController::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)

    if (!s_instance)
        s_instance = new SearchController;
    QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    qCDebug(lcSearch) << "SearchController singleton handed to QML";
    return s_instance;
}

// ---- State ----------------------------------------------------------------

bool SearchController::pluginsInstalled() const
{
    auto *mgr = SearchPluginManager::instance();
    return mgr && !mgr->allPlugins().isEmpty();
}

QVariantList SearchController::tabs() const
{
    QVariantList list;
    list.reserve(m_tabs.size());
    for (const SearchTab *tab : m_tabs)
    {
        QVariantMap entry;
        entry.insert(u"id"_s, tab->id);
        entry.insert(u"pattern"_s, tab->pattern);
        entry.insert(u"status"_s, static_cast<int>(tab->status));
        list.append(entry);
    }
    return list;
}

QVariantList SearchController::pluginScopes() const
{
    QVariantList list;

    const auto addItem = [&list](const QString &label, const QString &value) {
        QVariantMap m;
        m.insert(u"label"_s, label);
        m.insert(u"value"_s, value);
        list.append(m);
    };

    addItem(tr("Only enabled"), u"enabled"_s);
    addItem(tr("All plugins"), u"all"_s);
    addItem(tr("Select..."), u"multi"_s);

    if (auto *mgr = SearchPluginManager::instance())
    {
        QStringList enabled = mgr->enabledPlugins();
        std::sort(enabled.begin(), enabled.end(), [mgr](const QString &a, const QString &b) {
            return QString::localeAwareCompare(mgr->pluginFullName(a), mgr->pluginFullName(b)) < 0;
        });
        for (const QString &id : enabled)
            addItem(mgr->pluginFullName(id), id);
    }

    return list;
}

QVariantList SearchController::plugins() const
{
    if (auto *mgr = SearchPluginManager::instance())
    {
        QVariantList result = mgr->palettePluginCatalog();
        for (QVariant &entry : result)
        {
            QVariantMap row = entry.toMap();
            const QString id = row.value(u"id"_s).toString();

            // Preserve richer manager/security fields when they exist, and
            // overlay only the transient controller diagnostic otherwise.
            if (row.value(u"diagnostic"_s).toString().isEmpty())
            {
                QString diagnostic = m_pluginDiagnostics.value(id);
                if (diagnostic.isEmpty() && row.value(u"runtimeWaiting"_s).toBool())
                    diagnostic = mgr->runtimeError();
                row[u"diagnostic"_s] = diagnostic;
            }
            row[u"hasDiagnostic"_s] = !row.value(u"diagnostic"_s).toString().isEmpty();

            // Main's rich palette names the verified source explicitly. Keep
            // the older `url` field for compatibility while exposing the same
            // value under the unambiguous catalog-source name.
            if (!row.contains(u"catalogSourceUrl"_s))
                row[u"catalogSourceUrl"_s] = row.value(u"url"_s);
            entry = row;
        }
        return result;
    }
    return {};
}

QVariantMap SearchController::unofficialPluginStatus() const
{
    if (auto *mgr = SearchPluginManager::instance())
        return mgr->unofficialCatalogStatus();
    return {};
}

QVariantMap SearchController::pluginDiagnostics() const
{
    QVariantMap result;
    for (auto it = m_pluginDiagnostics.cbegin(); it != m_pluginDiagnostics.cend(); ++it)
        result.insert(it.key(), it.value());
    return result;
}

bool SearchController::pluginOperationInProgress() const
{
    return m_pluginBatch.active();
}

QString SearchController::pluginDiagnostic(const QString &id) const
{
    return m_pluginDiagnostics.value(id);
}

void SearchController::acknowledgePluginOperationSummary(const qulonglong serial)
{
    for (qsizetype i = 0; i < m_pendingPluginOperationSummaries.size(); ++i)
    {
        if (m_pendingPluginOperationSummaries.at(i).toMap().value(u"serial"_s).toULongLong() != serial)
            continue;

        m_pendingPluginOperationSummaries.removeAt(i);
        emit pendingPluginOperationSummariesChanged();
        return;
    }
}

QVariantList SearchController::categoriesForScope(const QString &scope) const
{
    QVariantList list;

    const auto addItem = [&list](const QString &label, const QString &value) {
        QVariantMap m;
        m.insert(u"label"_s, label);
        m.insert(u"value"_s, value);
        list.append(m);
    };

    // "All categories" is always first.
    addItem(SearchPluginManager::categoryFullName(u"all"_s), u"all"_s);

    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return list;

    QStringList cats = mgr->getPluginCategories(scope);
    cats.removeAll(u"all"_s);

    struct Item { QString label; QString id; };
    QList<Item> items;
    items.reserve(cats.size());
    for (const QString &cat : std::as_const(cats))
        items.append({SearchPluginManager::categoryFullName(cat), cat});

    std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
        return QString::localeAwareCompare(a.label, b.label) < 0;
    });

    for (const Item &it : std::as_const(items))
        addItem(it.label, it.id);

    return list;
}

// ---- Search lifecycle ------------------------------------------------------

QStringList SearchController::pluginsForScope(const QString &scope) const
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return {};

    if (scope == "all"_L1)
        return mgr->allPlugins();
    if ((scope == "enabled"_L1) || (scope == "multi"_L1))
        return mgr->enabledPlugins();
    return {scope};
}

int SearchController::startSearch(const QString &pattern, const QString &category, const QString &scope
        , const bool regexEnabled, const QString &regexFlags)
{
    const QString trimmed = pattern.trimmed();
    qCInfo(lcSearch) << "startSearch requested; pattern=" << trimmed
                     << "category=" << category << "scope=" << scope;

    if (!m_pythonAvailable)
    {
        qCWarning(lcSearch) << "startSearch blocked: Python not available";
        emit notify(tr("Please install Python to use the Search Engine."));
        return -1;
    }

    if (trimmed.isEmpty())
    {
        qCWarning(lcSearch) << "startSearch blocked: empty pattern";
        emit notify(tr("Please type a search pattern first"));
        return -1;
    }

    if (regexEnabled)
    {
        const QRegularExpression expression {trimmed, regexOptions(regexFlags)};
        if (!expression.isValid())
        {
            const QString message = tr("Invalid regular expression at offset %1: %2")
                    .arg(expression.patternErrorOffset()).arg(expression.errorString());
            qCWarning(lcSearch) << "startSearch blocked: invalid regex" << expression.errorString();
            emit notify(message);
            return -1;
        }
    }

    auto *mgr = SearchPluginManager::instance();
    if (!mgr || !mgr->runtimeReady())
    {
        QString reason = unavailableReason();
        if (reason.isEmpty())
            reason = tr("The search plugin runtime is not ready yet.");
        qCWarning(lcSearch) << "startSearch blocked: plugin runtime unavailable" << reason;
        emit notify(reason);
        return -1;
    }

    const QStringList plugins = pluginsForScope(scope);
    if (plugins.isEmpty())
    {
        qCWarning(lcSearch) << "startSearch blocked: no usable plugins";
        emit notify(tr("There aren't any search plugins installed."));
        return -1;
    }

    auto *tab = new SearchTab;
    tab->id = m_nextTabId++;
    tab->pattern = trimmed;
    tab->category = category;
    tab->plugins = plugins;
    tab->scope = scope;
    tab->regexEnabled = regexEnabled;
    tab->regexFlags = regexFlags;
    tab->model = new SearchResultsModel(this);
    tab->proxy = new SearchResultsProxyModel(this);
    tab->proxy->setSourceModel(tab->model);
    tab->proxy->setQueryPattern(trimmed, regexEnabled, regexFlags);
    tab->proxy->setNameFilteringMode(nameFilteringMode());
    tab->proxy->setRegexEnabled(resultsFilterUsesRegex());
    tab->proxy->setRegexFlags(resultsFilterRegexFlags());
    tab->handler = mgr->startSearch(trimmed, category, plugins);
    tab->status = Ongoing;

    m_tabs.append(tab);
    wireHandler(tab);
    addToHistory(trimmed);

    qCInfo(lcSearch) << "Search started: tab" << tab->id << "pattern" << trimmed
                     << "category" << category << "plugins" << plugins.size();
    emit tabsChanged();
    return tab->id;
}

void SearchController::refreshTab(int tabId)
{
    SearchTab *tab = tabById(tabId);
    if (!tab)
        return;
    if (tab->handler && tab->status == Ongoing)
    {
        qCDebug(lcSearch) << "refreshTab ignored: tab" << tabId << "still ongoing";
        return;
    }
    if (!m_pythonAvailable)
    {
        emit notify(tr("Please install Python to use the Search Engine."));
        return;
    }

    auto *mgr = SearchPluginManager::instance();
    if (!mgr || !mgr->runtimeReady())
    {
        QString reason = unavailableReason();
        if (reason.isEmpty())
            reason = tr("The search plugin runtime is not ready yet.");
        qCWarning(lcSearch) << "refreshTab blocked: plugin runtime unavailable" << reason;
        emit notify(reason);
        return;
    }

    tab->model->clearResults();
    tab->proxy->setQueryPattern(tab->pattern, tab->regexEnabled, tab->regexFlags);
    if (tab->handler)
        tab->handler->deleteLater();
    tab->handler = mgr->startSearch(tab->pattern, tab->category, tab->plugins);
    wireHandler(tab);
    setTabStatus(tab, Ongoing);
    qCInfo(lcSearch) << "Search refreshed: tab" << tabId;
}

void SearchController::stopSearch(int tabId)
{
    SearchTab *tab = tabById(tabId);
    if (!tab || !tab->handler)
        return;
    qCInfo(lcSearch) << "Stopping search: tab" << tabId;
    tab->handler->cancelSearch();
}

void SearchController::closeTab(int tabId)
{
    const auto it = std::find_if(m_tabs.begin(), m_tabs.end(),
                                 [tabId](const SearchTab *t) { return t->id == tabId; });
    if (it == m_tabs.end())
        return;

    SearchTab *tab = *it;
    if (tab->handler)
    {
        tab->handler->cancelSearch();
        tab->handler->deleteLater();
    }
    if (tab->proxy)
        tab->proxy->deleteLater();
    if (tab->model)
        tab->model->deleteLater();

    m_tabs.erase(it);
    delete tab;
    qCInfo(lcSearch) << "Closed tab" << tabId;
    emit tabsChanged();
}

void SearchController::closeAllTabs()
{
    const QList<SearchTab *> snapshot = m_tabs;
    for (const SearchTab *tab : snapshot)
        closeTab(tab->id);
}

// ---- Per-tab accessors -----------------------------------------------------

SearchResultsProxyModel *SearchController::resultsModel(int tabId) const
{
    const SearchTab *tab = tabById(tabId);
    return tab ? tab->proxy : nullptr;
}

QString SearchController::tabPattern(int tabId) const
{
    const SearchTab *tab = tabById(tabId);
    return tab ? tab->pattern : QString();
}

int SearchController::tabStatus(int tabId) const
{
    const SearchTab *tab = tabById(tabId);
    return tab ? static_cast<int>(tab->status) : static_cast<int>(Ready);
}

QString SearchController::statusText(int status) const
{
    switch (static_cast<Status>(status))
    {
    case Ongoing:   return tr("Searching...");
    case Finished:  return tr("Search has finished");
    case Aborted:   return tr("Search aborted");
    case Error:     return tr("An error occurred during search...");
    case NoResults: return tr("Search returned no results");
    case Ready:     break;
    }
    return tr("Ready");
}

QString SearchController::statusIcon(int status) const
{
    switch (static_cast<Status>(status))
    {
    case Ongoing:   return u"hourglass_empty"_s;
    case Finished:  return u"check_circle"_s;
    case Aborted:   return u"block"_s;
    case Error:     return u"error"_s;
    case NoResults: return u"warning"_s;
    case Ready:     break;
    }
    return u"search"_s;
}

// ---- Result actions --------------------------------------------------------

void SearchController::downloadTorrent(int tabId, int proxyRow, int option)
{
    SearchTab *tab = tabById(tabId);
    if (!tab || !tab->proxy)
        return;
    const int sourceRow = tab->proxy->sourceRow(proxyRow);
    if (sourceRow < 0)
        return;
    const bool showDialog = (option == ShowDialog);
    doDownload(tab, sourceRow, showDialog);
}

void SearchController::doDownload(SearchTab *tab, int sourceRow, bool showDialog)
{
    if ((sourceRow < 0) || (sourceRow >= tab->model->resultCount()))
        return;

    const SearchResult &result = tab->model->resultAt(sourceRow);
    tab->model->setVisited(sourceRow);

    if (result.fileUrl.startsWith(u"magnet:"_s, Qt::CaseInsensitive))
    {
        qCInfo(lcSearch) << "Download (magnet) row" << sourceRow << "->" << result.fileUrl;
        emit addTorrentRequested(result.fileUrl, showDialog);
        return;
    }

    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;

    qCInfo(lcSearch) << "Download (fetch .torrent) row" << sourceRow << "via" << result.engineName;
    SearchDownloadHandler *dl = mgr->downloadTorrent(result.engineName, result.fileUrl);
    connect(dl, &SearchDownloadHandler::downloadFinished, this,
            [this, showDialog, dl](const QString &path, const QString &errorMessage) {
        if (errorMessage.isEmpty() && !path.isEmpty() && QFileInfo(path).isFile())
        {
            qCInfo(lcSearch) << "Fetched .torrent to" << path;
            emit addTorrentRequested(path, showDialog);
        }
        else
        {
            qCWarning(lcSearch) << "Torrent fetch failed:" << errorMessage;
            emit notify(tr("Download error: %1").arg(errorMessage));
        }
        dl->deleteLater();
    });
}

void SearchController::openDescriptionPages(int tabId, const QList<int> &proxyRows)
{
    SearchTab *tab = tabById(tabId);
    if (!tab || !tab->proxy)
        return;

    for (const int proxyRow : proxyRows)
    {
        const int sourceRow = tab->proxy->sourceRow(proxyRow);
        if ((sourceRow < 0) || (sourceRow >= tab->model->resultCount()))
            continue;

        const QString link = tab->model->resultAt(sourceRow).descrLink;
        if (link.isEmpty())
        {
            emit notify(tr("The description page is unavailable for this result."));
            continue;
        }

        const QUrl url(link);
        if (url.isLocalFile() || (url.scheme().compare(u"file"_s, Qt::CaseInsensitive) == 0))
        {
            qCWarning(lcSearch) << "Refusing to open local-file description URL:" << link;
            emit notify(tr("This description page points to a local file and was not opened."));
            continue;
        }

        qCInfo(lcSearch) << "Opening description page:" << link;
        QDesktopServices::openUrl(url);
    }
}

void SearchController::copyNames(int tabId, const QList<int> &proxyRows) const
{
    const SearchTab *tab = tabById(tabId);
    if (!tab)
        return;
    QStringList values;
    for (const int proxyRow : proxyRows)
    {
        const int sourceRow = tab->proxy->sourceRow(proxyRow);
        if ((sourceRow >= 0) && (sourceRow < tab->model->resultCount()))
            values.append(tab->model->resultAt(sourceRow).fileName);
    }
    QGuiApplication::clipboard()->setText(values.join(u'\n'));
    qCDebug(lcSearch) << "Copied" << values.size() << "name(s) to clipboard";
}

void SearchController::copyDownloadLinks(int tabId, const QList<int> &proxyRows) const
{
    const SearchTab *tab = tabById(tabId);
    if (!tab)
        return;
    QStringList values;
    for (const int proxyRow : proxyRows)
    {
        const int sourceRow = tab->proxy->sourceRow(proxyRow);
        if ((sourceRow >= 0) && (sourceRow < tab->model->resultCount()))
            values.append(tab->model->resultAt(sourceRow).fileUrl);
    }
    QGuiApplication::clipboard()->setText(values.join(u'\n'));
    qCDebug(lcSearch) << "Copied" << values.size() << "download link(s) to clipboard";
}

void SearchController::copyDescriptionPages(int tabId, const QList<int> &proxyRows) const
{
    const SearchTab *tab = tabById(tabId);
    if (!tab)
        return;
    QStringList values;
    for (const int proxyRow : proxyRows)
    {
        const int sourceRow = tab->proxy->sourceRow(proxyRow);
        if ((sourceRow >= 0) && (sourceRow < tab->model->resultCount()))
            values.append(tab->model->resultAt(sourceRow).descrLink);
    }
    QGuiApplication::clipboard()->setText(values.join(u'\n'));
    qCDebug(lcSearch) << "Copied" << values.size() << "description URL(s) to clipboard";
}

// ---- Plugin management -----------------------------------------------------

void SearchController::enablePlugin(const QString &id, bool enabled)
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;
    qCInfo(lcSearch) << "Enable plugin" << id << "->" << enabled;
    mgr->enablePlugin(id, enabled);
}

void SearchController::enablePlugins(const QStringList &ids, bool enabled)
{
    for (const QString &id : ids)
        enablePlugin(id, enabled);
}

void SearchController::uninstallPlugins(const QStringList &ids)
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;

    int bundledCount = 0;
    for (const QString &id : ids)
    {
        if (!mgr->uninstallPlugin(id))
        {
            // Bundled plugin: cannot be removed, so it is disabled instead.
            ++bundledCount;
            mgr->enablePlugin(id, false);
        }
    }

    qCInfo(lcSearch) << "Uninstalled" << (ids.size() - bundledCount) << "plugin(s);"
                     << bundledCount << "bundled and only disabled";
    if (bundledCount > 0)
    {
        emit notify(tr("Some plugins could not be uninstalled because they are included "
                       "in qBittorrent. Only the ones you added yourself can be uninstalled. "
                       "Those plugins were disabled."));
    }
    else
    {
        emit notify(tr("All selected plugins were uninstalled successfully"));
    }
}

void SearchController::installPluginsFromFiles(const QStringList &paths)
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr || paths.isEmpty())
        return;

    if (m_pluginBatch.active())
    {
        emit notify(tr("A search-plugin operation is already in progress."));
        return;
    }
    if (const QString reason = pluginRuntimeBlockReason(); !reason.isEmpty())
    {
        beginPluginBatch(u"install"_s, {});
        m_pluginBatch.requested = paths.size();
        finishPluginBatch(u"runtime-unavailable"_s, reason);
        return;
    }

    QHash<QString, QString> sourcesByID;
    for (const QString &path : paths)
    {
        const QFileInfo info {path};
        if (info.suffix().compare(u"py"_s, Qt::CaseInsensitive) == 0)
            sourcesByID.insert(info.completeBaseName(), path);
    }

    QStringList ids = sourcesByID.keys();
    ids.sort(Qt::CaseInsensitive);
    beginPluginBatch(u"install"_s, ids, false, paths.size() - ids.size());
    if (ids.isEmpty())
    {
        m_pluginBatch.failures.insert(u"source"_s, tr("No valid .py plugin files were selected."));
        finishPluginBatch(u"failed"_s);
        return;
    }

    for (const QString &id : std::as_const(ids))
    {
        const QString path = sourcesByID.value(id);
        qCInfo(lcSearch) << "Installing plugin from file:" << path;
        mgr->installPlugin(path);
    }
}

void SearchController::installPluginFromUrl(const QString &url)
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;
    if (m_pluginBatch.active())
    {
        emit notify(tr("A search-plugin operation is already in progress."));
        return;
    }
    if (!url.endsWith(u".py"_s, Qt::CaseInsensitive))
    {
        qCWarning(lcSearch) << "Rejected plugin URL (not .py):" << url;
        beginPluginBatch(u"install"_s);
        m_pluginBatch.requested = 1;
        m_pluginBatch.failures.insert(u"source"_s, tr("The link doesn't seem to point to a search engine plugin."));
        finishPluginBatch(u"failed"_s);
        return;
    }
    if (const QString reason = pluginRuntimeBlockReason(); !reason.isEmpty())
    {
        beginPluginBatch(u"install"_s);
        m_pluginBatch.requested = 1;
        finishPluginBatch(u"runtime-unavailable"_s, reason);
        return;
    }

    QString id = QFileInfo {QUrl(url).path()}.completeBaseName();
    if (id.isEmpty())
        id = u"download"_s;
    beginPluginBatch(u"install"_s, {id});
    qCInfo(lcSearch) << "Installing plugin from URL:" << url;
    mgr->installPlugin(url);
}

void SearchController::checkForPluginUpdates()
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;
    if (m_pluginBatch.active())
    {
        emit notify(tr("A search-plugin operation is already in progress."));
        return;
    }
    if (const QString reason = pluginRuntimeBlockReason(); !reason.isEmpty())
    {
        beginPluginBatch(u"update"_s);
        finishPluginBatch(u"runtime-unavailable"_s, reason);
        return;
    }

    beginPluginBatch(u"update"_s, {}, true);
    qCInfo(lcSearch) << "Checking for plugin updates";
    mgr->checkForUpdates();
}

void SearchController::retryUnofficialPluginSync()
{
    if (auto *mgr = SearchPluginManager::instance())
        mgr->retryUnofficialCatalogSync();
}

void SearchController::trustUnofficialPlugin(const QString &id)
{
    if (auto *mgr = SearchPluginManager::instance())
        mgr->trustUnofficialPlugin(id);
}

QString SearchController::pluginFullName(const QString &id) const
{
    auto *mgr = SearchPluginManager::instance();
    return mgr ? mgr->pluginFullName(id) : id;
}

QString SearchController::pluginRuntimeBlockReason() const
{
    if (!m_pythonAvailable)
        return unavailableReason();
    if (auto *mgr = SearchPluginManager::instance())
        return mgr->runtimeError();
    return tr("The search plugin manager is unavailable.");
}

QStringList SearchController::runtimeRecoveryPluginIDs() const
{
    QStringList result;
    if (auto *mgr = SearchPluginManager::instance())
    {
        for (const QVariant &entry : mgr->palettePluginCatalog())
        {
            const QVariantMap row = entry.toMap();
            if (row.value(u"installedOnDisk"_s).toBool()
                && !row.value(u"registered"_s).toBool()
                && !row.value(u"userRemoved"_s).toBool())
            {
                result.append(row.value(u"id"_s).toString());
            }
        }
    }
    result.removeAll(QString {});
    result.removeDuplicates();
    result.sort(Qt::CaseInsensitive);
    return result;
}

void SearchController::beginPluginBatch(const QString &kind, const QStringList &ids,
                                        const bool awaitingUpdateList, const int skipped)
{
    Q_ASSERT(!m_pluginBatch.active());

    m_pluginBatch = {};
    m_pluginBatch.kind = kind;
    m_pluginBatch.pending = QSet<QString>(ids.cbegin(), ids.cend());
    m_pluginBatch.requested = m_pluginBatch.pending.size();
    m_pluginBatch.skipped = std::max(0, skipped);
    m_pluginBatch.awaitingUpdateList = awaitingUpdateList;

    bool diagnosticsChanged = false;
    for (const QString &id : ids)
        diagnosticsChanged = (m_pluginDiagnostics.remove(id) > 0) || diagnosticsChanged;
    if (diagnosticsChanged)
    {
        emit pluginDiagnosticsChanged();
        schedulePluginsChanged();
    }
    emit pluginOperationInProgressChanged();
}

void SearchController::recordPluginBatchOutcome(const QString &id, const bool succeeded,
                                                const QString &reason)
{
    if (!m_pluginBatch.active() || !m_pluginBatch.pending.remove(id))
        return;

    if (succeeded)
        ++m_pluginBatch.succeeded;
    else
        m_pluginBatch.failures.insert(id, reason);

    if (m_pluginBatch.pending.isEmpty() && !m_pluginBatch.awaitingUpdateList)
        finishPluginBatch();
}

void SearchController::finishPluginBatch(const QString &forcedState, const QString &runtimeReason)
{
    if (!m_pluginBatch.active())
        return;

    QVariantList details;
    QStringList failedIDs = m_pluginBatch.failures.keys();
    failedIDs.sort(Qt::CaseInsensitive);
    for (const QString &id : std::as_const(failedIDs))
    {
        details.append(QVariantMap {
            {u"id"_s, id},
            {u"reason"_s, m_pluginBatch.failures.value(id)}
        });
    }

    QString state = forcedState;
    if (state.isEmpty())
    {
        if (m_pluginBatch.failures.isEmpty())
            state = u"success"_s;
        else if (m_pluginBatch.succeeded == 0)
            state = u"failed"_s;
        else
            state = u"partial"_s;
    }

    QVariantMap summary {
        {u"kind"_s, m_pluginBatch.kind},
        {u"state"_s, state},
        {u"requested"_s, m_pluginBatch.requested},
        {u"succeeded"_s, m_pluginBatch.succeeded},
        {u"failed"_s, m_pluginBatch.failures.size()},
        {u"skipped"_s, m_pluginBatch.skipped},
        {u"details"_s, details}
    };
    if (!runtimeReason.isEmpty())
        summary[u"runtimeError"_s] = runtimeReason;

    m_pluginBatch = {};
    emit pluginOperationInProgressChanged();
    publishPluginOperationSummary(summary);
}

void SearchController::finishRuntimeRecovery()
{
    if (!m_pluginBatch.active() || (m_pluginBatch.kind != u"runtime-recovery"_s))
        return;

    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
    {
        finishPluginBatch(u"failed"_s);
        return;
    }

    QHash<QString, QVariantMap> inventory;
    for (const QVariant &entry : mgr->palettePluginCatalog())
    {
        const QVariantMap row = entry.toMap();
        inventory.insert(row.value(u"id"_s).toString(), row);
    }

    bool diagnosticsChanged = false;
    const QStringList pending = m_pluginBatch.pending.values();
    for (const QString &id : pending)
    {
        const QVariantMap row = inventory.value(id);
        if (row.value(u"registered"_s).toBool())
        {
            m_pluginBatch.pending.remove(id);
            ++m_pluginBatch.succeeded;
            diagnosticsChanged = (m_pluginDiagnostics.remove(id) > 0) || diagnosticsChanged;
            continue;
        }

        QString reason = row.value(u"diagnostic"_s).toString();
        if (reason.isEmpty())
            reason = m_pluginDiagnostics.value(id);
        if (reason.isEmpty())
            reason = tr("The search runtime did not register this plugin.");
        m_pluginBatch.pending.remove(id);
        m_pluginBatch.failures.insert(id, reason);
        if (m_pluginDiagnostics.value(id) != reason)
        {
            m_pluginDiagnostics.insert(id, reason);
            diagnosticsChanged = true;
        }
    }

    if (diagnosticsChanged)
    {
        emit pluginDiagnosticsChanged();
        schedulePluginsChanged();
    }
    finishPluginBatch();
}

void SearchController::publishPluginOperationSummary(QVariantMap summary)
{
    summary[u"serial"_s] = m_nextPluginOperationSerial++;
    m_pendingPluginOperationSummaries.append(summary);
    emit pendingPluginOperationSummariesChanged();
    emit pluginOperationSummaryReady(summary);
}

void SearchController::setPluginDiagnostic(const QString &id, const QString &reason)
{
    if (id.isEmpty())
        return;

    if (reason.isEmpty())
    {
        if (m_pluginDiagnostics.remove(id) == 0)
            return;
    }
    else
    {
        if (m_pluginDiagnostics.value(id) == reason)
            return;
        m_pluginDiagnostics.insert(id, reason);
    }

    emit pluginDiagnosticsChanged();
    schedulePluginsChanged();
}

void SearchController::schedulePluginsChanged(const bool immediate)
{
    if (immediate)
    {
        m_pluginsChangedPending = false;
        m_pluginsChangedTimer.stop();
        emit pluginsChanged();
        return;
    }

    m_pluginsChangedPending = true;
    if (!m_pluginsChangedTimer.isActive())
        m_pluginsChangedTimer.start();
}

void SearchController::importCatalogDiagnostics(const QVariantMap &status)
{
    auto *mgr = SearchPluginManager::instance();
    if (!mgr)
        return;

    const QVariantList inventory = mgr->palettePluginCatalog();
    QHash<QString, QString> newDiagnostics;
    for (const QString &error : status.value(u"errors"_s).toStringList())
    {
        for (const QVariant &entry : inventory)
        {
            const QString id = entry.toMap().value(u"id"_s).toString();
            const QString colonPrefix = id + u":"_s;
            const QString spacePrefix = id + u" "_s;
            if (!error.startsWith(colonPrefix) && !error.startsWith(spacePrefix))
                continue;

            QString reason = error.sliced(id.size()).trimmed();
            if (reason.startsWith(u":"_s))
                reason = reason.sliced(1).trimmed();
            newDiagnostics.insert(id, reason);
            break;
        }
    }

    bool changed = false;
    for (const QVariant &entry : inventory)
    {
        const QVariantMap row = entry.toMap();
        if (!row.value(u"catalogDefault"_s).toBool())
            continue;
        const QString id = row.value(u"id"_s).toString();
        if (newDiagnostics.contains(id))
        {
            if (m_pluginDiagnostics.value(id) != newDiagnostics.value(id))
            {
                m_pluginDiagnostics.insert(id, newDiagnostics.value(id));
                changed = true;
            }
        }
        else if (row.value(u"registered"_s).toBool())
        {
            changed = (m_pluginDiagnostics.remove(id) > 0) || changed;
        }
    }

    if (changed)
        emit pluginDiagnosticsChanged();
}

// ---- History ---------------------------------------------------------------

void SearchController::clearHistory()
{
    m_history.clear();
    saveHistoryAsync();
    emit historyChanged();
    qCInfo(lcSearch) << "Search history cleared";
}

void SearchController::addToHistory(const QString &pattern)
{
    const int maxLen = qBound(0, Preferences::instance()->searchHistoryLength(), 99);
    if (maxLen <= 0)
        return;

    m_history.removeAll(pattern);
    m_history.prepend(pattern);
    while (m_history.size() > maxLen)
        m_history.removeLast();

    saveHistoryAsync();
    emit historyChanged();
    qCDebug(lcSearch) << "History updated; size" << m_history.size();
}

void SearchController::loadHistory()
{
    m_history = SettingsStorage::instance()->loadValue<QStringList>(kHistoryKey);
    qCDebug(lcSearch) << "Loaded search history:" << m_history.size() << "entries";
}

void SearchController::saveHistoryAsync() const
{
    // SettingsStorage batches disk writes on its own timer (deferred IO), so a
    // direct store here does not block the UI thread.
    // TODO(engine): mirror the legacy <Data>/SearchUI/ file-based DataStorage
    // (History.txt + Session.json + per-tab result JSON) on a dedicated IO
    // thread, including open-tab/result session restore.
    SettingsStorage::instance()->storeValue(kHistoryKey, m_history);
}

// ---- Results-filter settings ----------------------------------------------

int SearchController::nameFilteringMode() const
{
    return SettingsStorage::instance()->loadValue<int>(kFilteringModeKey, OnlyNames);
}

void SearchController::setNameFilteringMode(int mode)
{
    SettingsStorage::instance()->storeValue<int>(kFilteringModeKey, mode);
    for (SearchTab *tab : std::as_const(m_tabs))
    {
        if (tab->proxy)
            tab->proxy->setNameFilteringMode(mode);
    }
    qCDebug(lcSearch) << "Name filtering mode ->" << mode;
}

bool SearchController::resultsFilterUsesRegex() const
{
    return Preferences::instance()->getRegexAsFilteringPatternForSearchJob();
}

void SearchController::setResultsFilterUsesRegex(bool enabled)
{
    Preferences::instance()->setRegexAsFilteringPatternForSearchJob(enabled);
    for (SearchTab *tab : std::as_const(m_tabs))
    {
        if (tab->proxy)
            tab->proxy->setRegexEnabled(enabled);
    }
    qCDebug(lcSearch) << "Results-filter regex ->" << enabled;
}

QString SearchController::resultsFilterRegexFlags() const
{
    return SettingsStorage::instance()->loadValue<QString>(kFilteringFlagsKey, u"iu"_s);
}

void SearchController::setResultsFilterRegexFlags(const QString &flags)
{
    SettingsStorage::instance()->storeValue(kFilteringFlagsKey, flags);
    for (SearchTab *tab : std::as_const(m_tabs))
    {
        if (tab->proxy)
            tab->proxy->setRegexFlags(flags);
    }
    qCDebug(lcSearch) << "Results-filter regex flags ->" << flags;
}

// ---- Internals -------------------------------------------------------------

void SearchController::wireHandler(SearchTab *tab)
{
    SearchHandler *handler = tab->handler;
    if (!handler)
        return;
    const int tabId = tab->id;

    connect(handler, &SearchHandler::newSearchResults, this,
            [this, tabId](const QList<SearchResult> &results) {
        SearchTab *t = tabById(tabId);
        if (!t)
            return;
        t->model->appendResults(results);
        emit tabResultsChanged(tabId);
    });

    connect(handler, &SearchHandler::searchFinished, this, [this, tabId](bool cancelled) {
        SearchTab *t = tabById(tabId);
        if (!t)
            return;
        Status status;
        if (cancelled)
            status = Aborted;
        else if (t->model->resultCount() == 0)
            status = NoResults;
        else
            status = Finished;
        setTabStatus(t, status);
        qCInfo(lcSearch) << "Search finished: tab" << tabId << "status" << static_cast<int>(status)
                         << "results" << t->model->resultCount();
        emit searchFinished(tabId, false);
    });

    connect(handler, &SearchHandler::searchFailed, this, [this, tabId](const QString &errorMessage) {
        SearchTab *t = tabById(tabId);
        if (!t)
            return;
        setTabStatus(t, Error);
        qCWarning(lcSearch) << "Search failed: tab" << tabId << ':' << errorMessage;
        emit notify(tr("Search has failed"));
        emit searchFinished(tabId, true);
    });
}

void SearchController::setTabStatus(SearchTab *tab, Status status)
{
    if (tab->status == status)
        return;
    tab->status = status;
    emit tabStatusChanged(tab->id, static_cast<int>(status));
    emit tabsChanged();
}

SearchController::SearchTab *SearchController::tabById(int id)
{
    for (SearchTab *tab : std::as_const(m_tabs))
    {
        if (tab->id == id)
            return tab;
    }
    return nullptr;
}

const SearchController::SearchTab *SearchController::tabById(int id) const
{
    for (const SearchTab *tab : std::as_const(m_tabs))
    {
        if (tab->id == id)
            return tab;
    }
    return nullptr;
}

void SearchController::detectPython()
{
    // Utils::ForeignApps::pythonInfo() actually executes the candidate with
    // `--version`. That matters on Windows, where %LOCALAPPDATA%\Microsoft\
    // WindowsApps contains zero-byte "python.exe"/"python3.exe" App Execution
    // Alias stubs that are on PATH even when Python is not installed — a plain
    // PATH lookup reports those as a real interpreter and search then dies with
    // an unexplained process failure.
    // It also honours (and validates) the interpreter configured in Options,
    // and searches the registry-known install paths on Windows.
    const Utils::ForeignApps::PythonInfo pyInfo = Utils::ForeignApps::pythonInfo();

    const bool wasAvailable = m_pythonAvailable;
    m_pythonAvailable = pyInfo.isValid();

    if (m_pythonAvailable)
    {
        qCInfo(lcSearch) << "Python detected:" << pyInfo.executablePath.toString()
                         << "version" << pyInfo.version.toString()
                         << "supported:" << pyInfo.isSupportedVersion();
    }
    else
    {
        qCWarning(lcSearch) << "No usable Python interpreter detected; search is unavailable";
    }

    if (wasAvailable != m_pythonAvailable)
        emit pythonAvailableChanged();
}

void SearchController::refreshPythonDetection()
{
    qCDebug(lcSearch) << "Re-running Python detection on request";
    detectPython();

    // Re-probing Python alone would leave the manager's stale runtime error in
    // place, so a user who has just installed Python would still be told it is
    // missing. Re-extract the runtime and re-query capabilities as well; that
    // also picks up plugins that could not be registered while search was down.
    if (m_pythonAvailable)
    {
        if (auto *mgr = SearchPluginManager::instance())
        {
            const QStringList recoveryIDs = runtimeRecoveryPluginIDs();
            if (!m_pluginBatch.active() && !recoveryIDs.isEmpty())
                beginPluginBatch(u"runtime-recovery"_s, recoveryIDs);
            mgr->reload();
        }
    }

    emit unavailableReasonChanged();
    schedulePluginsChanged(true);
}

QString SearchController::unavailableReason() const
{
    if (!m_pythonAvailable)
    {
        return tr("Python was not found. Search needs a Python %1 or later interpreter on PATH, "
                  "or one selected in Options.")
            .arg(Utils::ForeignApps::PythonInfo::MINIMUM_SUPPORTED_VERSION.toString());
    }

    if (auto *mgr = SearchPluginManager::instance())
        return mgr->runtimeError();

    return {};
}
