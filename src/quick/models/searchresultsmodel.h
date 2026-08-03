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

#include <QAbstractListModel>
#include <QByteArray>
#include <QCollator>
#include <QDateTime>
#include <QHash>
#include <QList>
#include <QLocale>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSortFilterProxyModel>
#include <QString>
#include <QVector>

#include "base/search/searchhandler.h"
#include "base/utils/misc.h"
#include "base/utils/string.h"
#include "base/logging.h"

using namespace Qt::StringLiterals;

/**
 * @file searchresultsmodel.h
 * @brief The per-tab search results model and its sort/filter proxy.
 *
 * One @c SearchResultsModel backs each open search tab; the owning
 * @c SearchController creates them and streams @c SearchResult rows in as the
 * Python engine emits them. Each row carries the formatted display value for
 * every visible column plus raw "underlying" values (bytes, seed counts, epoch
 * seconds) used by @c SearchResultsProxyModel to sort and filter naturally.
 *
 * Both classes are QML_UNCREATABLE: QML never instantiates them directly, it
 * binds to the proxy handed back by @c SearchController::resultsModel().
 */
class SearchResultsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("SearchResultsModel is created by SearchController")

public:
    /// Named roles — string names (via roleNames()) are what DataTable columns
    /// and QML delegates reference as @c model.<role>.
    enum Roles
    {
        NameRole = Qt::UserRole + 1, ///< "name"        — torrent/file name
        SizeRole,                    ///< "size"        — friendly size string
        SeedersRole,                 ///< "seeders"     — seeders (display)
        LeechersRole,                ///< "leechers"    — leechers (display)
        EngineRole,                  ///< "engine"      — plugin full/short name
        EngineUrlRole,               ///< "engineUrl"   — engine site URL
        PublishedRole,               ///< "published"   — localized publish date
        DescrLinkRole,               ///< "descrLink"   — description page URL
        FileUrlRole,                 ///< "fileUrl"     — magnet / .torrent link
        VisitedRole,                 ///< "visited"     — bool, greyed once downloaded
        SizeBytesRole,               ///< "sizeBytes"   — raw size (sort/filter)
        SeedersValueRole,            ///< "seedersValue"— raw seeders (sort/filter)
        LeechersValueRole,           ///< "leechersValue"— raw leechers (sort/filter)
        PublishedValueRole           ///< "publishedValue" — epoch secs (sort)
    };
    Q_ENUM(Roles)

    explicit SearchResultsModel(QObject *parent = nullptr)
        : QAbstractListModel(parent)
    {
        qCDebug(lcSearch) << "SearchResultsModel constructed";
    }

    ~SearchResultsModel() override
    {
        qCDebug(lcSearch) << "SearchResultsModel destroyed with" << m_results.size() << "rows";
    }

    // ---- QAbstractListModel ------------------------------------------------

    int rowCount(const QModelIndex &parent = {}) const override
    {
        return parent.isValid() ? 0 : static_cast<int>(m_results.size());
    }

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override
    {
        const int row = index.row();
        if ((row < 0) || (row >= m_results.size()))
            return {};

        const SearchResult &r = m_results.at(row);
        switch (role)
        {
        case NameRole:          return r.fileName;
        case SizeRole:          return (r.fileSize >= 0) ? Utils::Misc::friendlyUnit(r.fileSize) : QString();
        case SeedersRole:       return (r.nbSeeders >= 0) ? QString::number(r.nbSeeders) : QString();
        case LeechersRole:      return (r.nbLeechers >= 0) ? QString::number(r.nbLeechers) : QString();
        case EngineRole:        return r.engineName;
        case EngineUrlRole:     return r.siteUrl;
        case PublishedRole:     return r.pubDate.isValid()
                                       ? QLocale().toString(r.pubDate.toLocalTime(), QLocale::ShortFormat)
                                       : QString();
        case DescrLinkRole:     return r.descrLink;
        case FileUrlRole:       return r.fileUrl;
        case VisitedRole:       return m_visited.value(row, false);
        case SizeBytesRole:     return static_cast<qlonglong>(r.fileSize);
        case SeedersValueRole:  return static_cast<qlonglong>(r.nbSeeders);
        case LeechersValueRole: return static_cast<qlonglong>(r.nbLeechers);
        case PublishedValueRole:return r.pubDate.isValid() ? r.pubDate.toSecsSinceEpoch() : qint64(-1);
        default:                return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return {
            {NameRole, "name"},
            {SizeRole, "size"},
            {SeedersRole, "seeders"},
            {LeechersRole, "leechers"},
            {EngineRole, "engine"},
            {EngineUrlRole, "engineUrl"},
            {PublishedRole, "published"},
            {DescrLinkRole, "descrLink"},
            {FileUrlRole, "fileUrl"},
            {VisitedRole, "visited"},
            {SizeBytesRole, "sizeBytes"},
            {SeedersValueRole, "seedersValue"},
            {LeechersValueRole, "leechersValue"},
            {PublishedValueRole, "publishedValue"}
        };
    }

    // ---- Bridge helpers (used by SearchController / the proxy) -------------

    /// Append a streamed batch of results (fired from newSearchResults).
    void appendResults(const QList<SearchResult> &batch)
    {
        if (batch.isEmpty())
            return;
        const int first = static_cast<int>(m_results.size());
        beginInsertRows({}, first, first + static_cast<int>(batch.size()) - 1);
        m_results.append(batch);
        m_visited.resize(m_results.size());
        endInsertRows();
        qCDebug(lcSearch) << "SearchResultsModel appended" << batch.size()
                          << "rows, total" << m_results.size();
    }

    /// Replace all rows at once (session restore path).
    void setResults(const QList<SearchResult> &results)
    {
        beginResetModel();
        m_results = results;
        m_visited.fill(false, m_results.size());
        endResetModel();
        qCDebug(lcSearch) << "SearchResultsModel reset with" << m_results.size() << "rows";
    }

    /// Drop every row (used by "Refresh tab" before re-running the query).
    void clearResults()
    {
        beginResetModel();
        m_results.clear();
        m_visited.clear();
        endResetModel();
        qCDebug(lcSearch) << "SearchResultsModel cleared";
    }

    /// Flag a row as visited (downloaded) so views can grey it out.
    void setVisited(int row)
    {
        if ((row < 0) || (row >= m_results.size()))
            return;
        if (m_visited.value(row, false))
            return;
        m_visited[row] = true;
        const QModelIndex idx = index(row, 0);
        emit dataChanged(idx, idx, {VisitedRole});
        qCDebug(lcSearch) << "SearchResultsModel row" << row << "marked visited";
    }

    [[nodiscard]] bool isVisited(int row) const { return m_visited.value(row, false); }
    [[nodiscard]] const SearchResult &resultAt(int row) const { return m_results.at(row); }
    [[nodiscard]] int resultCount() const { return static_cast<int>(m_results.size()); }

private:
    QList<SearchResult> m_results;
    QVector<bool> m_visited;
};

/**
 * @brief Sort/filter proxy over a @c SearchResultsModel.
 *
 * Provides natural (human) sorting on Name / Engine URL, numeric sorting on the
 * underlying value roles, and the results-tab filters: the free-text results
 * filter (wildcard or raw regex), the "Search in" name-word filter, and the
 * seeds / size range filters. Exposes @c visibleCount / @c totalCount for the
 * "Results (showing X out of Y)" label.
 */
class SearchResultsProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("SearchResultsProxyModel is created by SearchController")

    Q_PROPERTY(int visibleCount READ visibleCount NOTIFY countsChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY countsChanged)
    Q_PROPERTY(bool regexEnabled READ regexEnabled WRITE setRegexEnabled NOTIFY filtersChanged)
    Q_PROPERTY(QString regexFlags READ regexFlags WRITE setRegexFlags NOTIFY filtersChanged)
    Q_PROPERTY(int nameFilteringMode READ nameFilteringMode WRITE setNameFilteringMode NOTIFY filtersChanged)

public:
    /// Mirrors the legacy @c NameFilteringMode enum (persisted numeric values).
    enum NameFilteringMode
    {
        Everywhere = 0,
        OnlyNames = 1
    };
    Q_ENUM(NameFilteringMode)

    explicit SearchResultsProxyModel(QObject *parent = nullptr)
        : QSortFilterProxyModel(parent)
    {
        m_collator.setNumericMode(true);
        m_collator.setCaseSensitivity(Qt::CaseInsensitive);
        setDynamicSortFilter(true);
        connect(this, &QAbstractItemModel::rowsInserted, this, &SearchResultsProxyModel::countsChanged);
        connect(this, &QAbstractItemModel::rowsRemoved, this, &SearchResultsProxyModel::countsChanged);
        connect(this, &QAbstractItemModel::modelReset, this, &SearchResultsProxyModel::countsChanged);
        qCDebug(lcSearch) << "SearchResultsProxyModel constructed";
    }

    [[nodiscard]] int visibleCount() const { return rowCount(); }

    [[nodiscard]] int totalCount() const
    {
        return sourceModel() ? sourceModel()->rowCount() : 0;
    }

    [[nodiscard]] bool regexEnabled() const { return m_regexEnabled; }
    [[nodiscard]] QString regexFlags() const { return m_regexFlags; }
    [[nodiscard]] int nameFilteringMode() const { return m_nameFilteringMode; }

    /// The original search query — needed for the "Torrent names only" filter.
    void setQueryPattern(const QString &pattern, const bool regexEnabled = false
            , const QString &regexFlags = u"iu"_s)
    {
        m_queryTokens = tokenizeQuery(pattern);
        m_queryRegexEnabled = regexEnabled;
        m_queryRegexFlags = regexFlags;
        m_queryRegex = regexEnabled
                ? QRegularExpression(pattern, patternOptions(regexFlags)) : QRegularExpression();
        invalidateFilter();
        emit countsChanged();
    }

    // ---- QML-facing filter setters ----------------------------------------

    Q_INVOKABLE void setResultsFilter(const QString &text)
    {
        if (m_filterText == text)
            return;
        m_filterText = text;
        rebuildTextRegex();
        invalidateFilter();
        emit filtersChanged();
        emit countsChanged();
        qCDebug(lcSearch) << "Results filter ->" << text;
    }

    Q_INVOKABLE void setRegexEnabled(bool enabled)
    {
        if (m_regexEnabled == enabled)
            return;
        m_regexEnabled = enabled;
        rebuildTextRegex();
        invalidateFilter();
        emit filtersChanged();
        emit countsChanged();
        qCDebug(lcSearch) << "Results filter regex ->" << enabled;
    }

    Q_INVOKABLE void setRegexFlags(const QString &flags)
    {
        if (m_regexFlags == flags)
            return;
        m_regexFlags = flags;
        rebuildTextRegex();
        invalidateFilter();
        emit filtersChanged();
        emit countsChanged();
        qCDebug(lcSearch) << "Results filter regex flags ->" << flags;
    }

    Q_INVOKABLE void setNameFilteringMode(int mode)
    {
        if (m_nameFilteringMode == mode)
            return;
        m_nameFilteringMode = mode;
        invalidateFilter();
        emit filtersChanged();
        emit countsChanged();
        qCDebug(lcSearch) << "Name filtering mode ->" << mode;
    }

    /// @p maxSeeds < 0 means "unlimited".
    Q_INVOKABLE void setSeedsFilter(int minSeeds, int maxSeeds)
    {
        m_minSeeds = minSeeds;
        m_maxSeeds = maxSeeds;
        invalidateFilter();
        emit countsChanged();
        qCDebug(lcSearch) << "Seeds filter ->" << minSeeds << ".." << maxSeeds;
    }

    /// Sizes in bytes; @p maxBytes < 0 means "unlimited".
    Q_INVOKABLE void setSizeFilter(qlonglong minBytes, qlonglong maxBytes)
    {
        m_minSize = minBytes;
        m_maxSize = maxBytes;
        invalidateFilter();
        emit countsChanged();
        qCDebug(lcSearch) << "Size filter ->" << minBytes << ".." << maxBytes;
    }

    /// DataTable calls this to change the sort column/order.
    Q_INVOKABLE void sortByRole(const QString &roleName, int order)
    {
        m_sortRole = roleName;
        sort(0, static_cast<Qt::SortOrder>(order));
        emit countsChanged();
        qCDebug(lcSearch) << "Results sorted by" << roleName << "order" << order;
    }

    /// Convenience for the results context menu: map a proxy row to the source.
    Q_INVOKABLE int sourceRow(int proxyRow) const
    {
        return mapToSource(index(proxyRow, 0)).row();
    }

    Q_INVOKABLE bool isVisited(int proxyRow) const
    {
        auto *src = qobject_cast<SearchResultsModel *>(sourceModel());
        if (!src)
            return false;
        return src->isVisited(sourceRow(proxyRow));
    }

signals:
    void countsChanged();
    void filtersChanged();

protected:
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override
    {
        auto *src = qobject_cast<SearchResultsModel *>(sourceModel());
        if (!src)
            return QSortFilterProxyModel::lessThan(left, right);

        const SearchResult &l = src->resultAt(left.row());
        const SearchResult &r = src->resultAt(right.row());

        if ((m_sortRole == "name"_L1) || m_sortRole.isEmpty())
            return m_collator.compare(l.fileName, r.fileName) < 0;
        if (m_sortRole == "engineUrl"_L1)
            return m_collator.compare(l.siteUrl, r.siteUrl) < 0;
        if (m_sortRole == "engine"_L1)
            return m_collator.compare(l.engineName, r.engineName) < 0;
        if (m_sortRole == "size"_L1)
            return l.fileSize < r.fileSize;
        if (m_sortRole == "seeders"_L1)
            return l.nbSeeders < r.nbSeeders;
        if (m_sortRole == "leechers"_L1)
            return l.nbLeechers < r.nbLeechers;
        if (m_sortRole == "published"_L1)
        {
            const qint64 ls = l.pubDate.isValid() ? l.pubDate.toSecsSinceEpoch() : -1;
            const qint64 rs = r.pubDate.isValid() ? r.pubDate.toSecsSinceEpoch() : -1;
            return ls < rs;
        }
        return QSortFilterProxyModel::lessThan(left, right);
    }

    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override
    {
        Q_UNUSED(sourceParent)
        auto *src = qobject_cast<SearchResultsModel *>(sourceModel());
        if (!src)
            return true;

        const SearchResult &r = src->resultAt(sourceRow);

        // (a) The top-level query may be a locally evaluated regular
        // expression. The external search engine still receives the same
        // query string, while this proxy applies the selected dialect and
        // flags to the rows that actually arrived.
        if (m_queryRegexEnabled)
        {
            if (!m_queryRegex.isValid() || m_queryRegex.pattern().isEmpty())
                return false;

            QString haystack = r.fileName;
            if (m_nameFilteringMode == Everywhere)
                haystack += u' ' + r.fileUrl + u' ' + r.engineName + u' '
                    + r.siteUrl + u' ' + r.descrLink;
            if (!m_queryRegex.match(haystack).hasMatch())
                return false;
        }
        // Plain mode preserves the existing token-based query semantics.
        else if ((m_nameFilteringMode == OnlyNames) && !m_queryTokens.isEmpty())
        {
            for (const QString &token : m_queryTokens)
            {
                if (!r.fileName.contains(token, Qt::CaseInsensitive))
                    return false;
            }
        }

        // (b) size range (bytes).
        if ((m_minSize > 0) && (r.fileSize < m_minSize))
            return false;
        if ((m_maxSize >= 0) && (r.fileSize > m_maxSize))
            return false;

        // (c) seeds range.
        if ((m_minSeeds > 0) && (r.nbSeeders < m_minSeeds))
            return false;
        if ((m_maxSeeds >= 0) && (r.nbSeeders > m_maxSeeds))
            return false;

        // (d) free-text results filter, applied to the name.
        if (!m_filterText.isEmpty())
        {
            if (!m_textRegex.isValid())
                return false;
            if (!m_textRegex.match(r.fileName).hasMatch())
                return false;
        }

        return true;
    }

private:
    static QStringList tokenizeQuery(const QString &pattern)
    {
        const QString trimmed = pattern.trimmed();
        if (trimmed.isEmpty())
            return {};
        // A fully double-quoted phrase is matched verbatim.
        if ((trimmed.size() >= 2) && trimmed.startsWith(u'"') && trimmed.endsWith(u'"'))
            return {trimmed.mid(1, trimmed.size() - 2)};
        return trimmed.split(QRegularExpression(u"\\s+"_s), Qt::SkipEmptyParts);
    }

    static QRegularExpression::PatternOptions patternOptions(const QString &flags)
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

    void rebuildTextRegex()
    {
        if (m_filterText.isEmpty())
        {
            m_textRegex = QRegularExpression();
            return;
        }
        const QString pattern = m_regexEnabled
                                    ? m_filterText
                                    : Utils::String::wildcardToRegexPattern(m_filterText);
        m_textRegex = QRegularExpression(pattern, m_regexEnabled
                ? patternOptions(m_regexFlags) : QRegularExpression::CaseInsensitiveOption);
    }

    mutable QCollator m_collator;
    QString m_sortRole;
    QString m_filterText;
    QRegularExpression m_textRegex;
    QStringList m_queryTokens;
    QRegularExpression m_queryRegex;
    QString m_queryRegexFlags = u"iu"_s;
    bool m_queryRegexEnabled = false;
    bool m_regexEnabled = false;
    QString m_regexFlags = u"iu"_s;
    int m_nameFilteringMode = OnlyNames;
    int m_minSeeds = 0;
    int m_maxSeeds = -1;
    qlonglong m_minSize = 0;
    qlonglong m_maxSize = -1;
};
