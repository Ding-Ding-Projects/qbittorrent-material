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

#include "torrentfilterproxymodel.h"

#include <QDateTime>

#include "base/bittorrent/torrent.h"
#include "base/logging.h"
#include "base/utils/compare.h"
#include "base/utils/string.h"
#include "transferlistmodel.h"

using namespace BitTorrent;

namespace
{
    // Column groups sharing a comparison strategy.
    bool isStringColumn(int column)
    {
        switch (column)
        {
        case TransferListModel::TR_NAME:
        case TransferListModel::TR_CATEGORY:
        case TransferListModel::TR_TAGS:
        case TransferListModel::TR_TRACKER:
        case TransferListModel::TR_SAVE_PATH:
        case TransferListModel::TR_DOWNLOAD_PATH:
        case TransferListModel::TR_INFOHASH_V1:
        case TransferListModel::TR_INFOHASH_V2:
            return true;
        default:
            return false;
        }
    }

    bool isDateColumn(int column)
    {
        switch (column)
        {
        case TransferListModel::TR_ADD_DATE:
        case TransferListModel::TR_SEED_DATE:
        case TransferListModel::TR_SEEN_COMPLETE_DATE:
        case TransferListModel::TR_CREATE_DATE:
            return true;
        default:
            return false;
        }
    }
}

TorrentFilterProxyModel::TorrentFilterProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    qCDebug(lcModel) << "TorrentFilterProxyModel created";

    connect(this, &QAbstractItemModel::rowsInserted, this, &TorrentFilterProxyModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &TorrentFilterProxyModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &TorrentFilterProxyModel::countChanged);
}

// --- status ---

int TorrentFilterProxyModel::statusFilter() const
{
    return static_cast<int>(m_filter.status);
}

void TorrentFilterProxyModel::setStatusFilter(int status)
{
    const auto value = static_cast<TorrentFilter::Status>(status);
    if (m_filter.status == value)
        return;
    qCInfo(lcModel) << "TorrentFilterProxyModel: status filter ->" << status;
    m_filter.status = value;
    invalidateFilter();
    emit filterChanged();
}

// --- category ---

QString TorrentFilterProxyModel::categoryFilter() const
{
    return m_filter.category.value_or(QString());
}

void TorrentFilterProxyModel::setCategoryFilter(const QString &category)
{
    qCInfo(lcModel) << "TorrentFilterProxyModel: category filter ->" << category;
    m_filter.category = category;
    invalidateFilter();
    emit filterChanged();
}

void TorrentFilterProxyModel::clearCategoryFilter()
{
    if (!m_filter.category.has_value())
        return;
    qCDebug(lcModel) << "TorrentFilterProxyModel: category filter cleared";
    m_filter.category.reset();
    invalidateFilter();
    emit filterChanged();
}

// --- tag ---

QString TorrentFilterProxyModel::tagFilter() const
{
    return (m_filter.tag.has_value()) ? m_filter.tag->toString() : QString();
}

void TorrentFilterProxyModel::setTagFilter(const QString &tag)
{
    qCInfo(lcModel) << "TorrentFilterProxyModel: tag filter ->" << tag;
    m_filter.tag = Tag(tag);
    invalidateFilter();
    emit filterChanged();
}

void TorrentFilterProxyModel::clearTagFilter()
{
    if (!m_filter.tag.has_value())
        return;
    qCDebug(lcModel) << "TorrentFilterProxyModel: tag filter cleared";
    m_filter.tag.reset();
    invalidateFilter();
    emit filterChanged();
}

// --- tracker ---

QString TorrentFilterProxyModel::trackerFilter() const
{
    return m_filter.trackerHost.value_or(QString());
}

void TorrentFilterProxyModel::setTrackerFilter(const QString &trackerHost)
{
    qCInfo(lcModel) << "TorrentFilterProxyModel: tracker filter ->" << trackerHost;
    m_filter.trackerHost = trackerHost;
    m_filter.announceStatus.reset();
    invalidateFilter();
    emit filterChanged();
}

void TorrentFilterProxyModel::setAnnounceStatusFilter(int flag)
{
    if (flag < 0)
    {
        qCDebug(lcModel) << "TorrentFilterProxyModel: announce-status filter cleared";
        m_filter.announceStatus.reset();
    }
    else
    {
        qCInfo(lcModel) << "TorrentFilterProxyModel: announce-status filter ->" << flag;
        m_filter.announceStatus = static_cast<TorrentAnnounceStatusFlag>(flag);
        m_filter.trackerHost.reset();
    }
    invalidateFilter();
    emit filterChanged();
}

// --- text ---

QString TorrentFilterProxyModel::textFilter() const
{
    return m_textPattern;
}

void TorrentFilterProxyModel::setTextFilter(const QString &text)
{
    if (m_textPattern == text)
        return;
    m_textPattern = text;
    const QString pattern = m_useRegex ? text : Utils::String::wildcardToRegexPattern(text);
    m_regex = QRegularExpression(pattern, QRegularExpression::CaseInsensitiveOption);
    qCDebug(lcModel) << "TorrentFilterProxyModel: text filter ->" << text << "regex=" << m_useRegex;
    invalidateFilter();
    emit filterChanged();
}

void TorrentFilterProxyModel::clearTrackerFilter()
{
    if (!m_filter.trackerHost.has_value())
        return;
    qCDebug(lcModel) << "TorrentFilterProxyModel: tracker filter cleared";
    m_filter.trackerHost.reset();
    invalidateFilter();
    emit filterChanged();
}

int TorrentFilterProxyModel::textFilterColumn() const
{
    return m_textFilterColumn;
}

void TorrentFilterProxyModel::setTextFilterColumn(const int column)
{
    switch (column)
    {
    case TransferListModel::TR_NAME:
    case TransferListModel::TR_SAVE_PATH:
    case TransferListModel::TR_INFOHASH_V1:
    case TransferListModel::TR_INFOHASH_V2:
        break;
    default:
        qCWarning(lcModel) << "TorrentFilterProxyModel: unsupported text filter column" << column;
        return;
    }

    if (m_textFilterColumn == column)
        return;

    m_textFilterColumn = column;
    qCDebug(lcModel) << "TorrentFilterProxyModel: text filter column ->" << column;
    invalidateFilter();
    emit filterChanged();
}

bool TorrentFilterProxyModel::useRegex() const
{
    return m_useRegex;
}

void TorrentFilterProxyModel::setUseRegex(bool enabled)
{
    if (m_useRegex == enabled)
        return;
    m_useRegex = enabled;
    const QString pattern = enabled ? m_textPattern : Utils::String::wildcardToRegexPattern(m_textPattern);
    m_regex = QRegularExpression(pattern, QRegularExpression::CaseInsensitiveOption);
    invalidateFilter();
    emit filterChanged();
}

// --- filtering ---

bool TorrentFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const auto *const model = qobject_cast<const TransferListModel *>(sourceModel());
    if (!model)
        return false;

    const Torrent *const torrent = model->torrentAtRow(sourceRow);
    if (!torrent)
        return false;

    Q_UNUSED(sourceParent);

    if (!m_filter.match(torrent))
        return false;

    if (!m_textPattern.isEmpty() && m_regex.isValid())
    {
        QString candidate;
        switch (m_textFilterColumn)
        {
        case TransferListModel::TR_SAVE_PATH:
            candidate = torrent->savePath().toString();
            break;
        case TransferListModel::TR_INFOHASH_V1:
            candidate = torrent->infoHash().v1().toString();
            break;
        case TransferListModel::TR_INFOHASH_V2:
            candidate = torrent->infoHash().v2().toString();
            break;
        case TransferListModel::TR_NAME:
        default:
            candidate = torrent->name();
            break;
        }
        return m_regex.match(candidate).hasMatch();
    }

    return true;
}

// --- sorting ---

void TorrentFilterProxyModel::sortByColumn(int column, Qt::SortOrder order)
{
    if (column != m_sortColumn)
    {
        // The previously-active column becomes the sub-sort tie-breaker.
        m_subSortColumn = m_sortColumn;
        m_subSortOrder = sortOrder();
    }
    m_sortColumn = column;
    qCDebug(lcModel) << "TorrentFilterProxyModel: sort by column" << column << "order" << order
                     << "sub-sort" << m_subSortColumn;
    sort(0, order);
}

int TorrentFilterProxyModel::compareColumn(const QModelIndex &left, const QModelIndex &right, int column) const
{
    const auto *const model = qobject_cast<const TransferListModel *>(sourceModel());
    if (!model)
        return 0;

    const Torrent *const l = model->torrentAtRow(left.row());
    const Torrent *const r = model->torrentAtRow(right.row());
    if (!l || !r)
        return 0;

    if (isStringColumn(column))
    {
        return Utils::Compare::naturalCompare(model->rawValue(l, column).toString()
                , model->rawValue(r, column).toString(), Qt::CaseInsensitive);
    }

    if (isDateColumn(column))
    {
        const QDateTime dl = model->rawValue(l, column).toDateTime();
        const QDateTime dr = model->rawValue(r, column).toDateTime();
        if (dl == dr)
            return 0;
        return (dl < dr) ? -1 : 1;
    }

    if ((column == TransferListModel::TR_SEEDS) || (column == TransferListModel::TR_PEERS))
    {
        const int la = model->rawValue(l, column).toInt();
        const int ra = model->rawValue(r, column).toInt();
        if (la != ra)
            return (la < ra) ? -1 : 1;
        const int lt = model->rawValue(l, column, true).toInt();
        const int rt = model->rawValue(r, column, true).toInt();
        if (lt == rt)
            return 0;
        return (lt < rt) ? -1 : 1;
    }

    // Numeric (integral or real) — compare as doubles; a negative value denotes
    // "invalid" and sorts last regardless of order (handled by the caller order).
    const double dl = model->rawValue(l, column).toDouble();
    const double dr = model->rawValue(r, column).toDouble();
    if (qFuzzyCompare(dl + 1.0, dr + 1.0))
        return 0;
    return (dl < dr) ? -1 : 1;
}

bool TorrentFilterProxyModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    int result = compareColumn(left, right, m_sortColumn);
    if (result == 0)
    {
        // Two-level sort: break ties by the remembered previous column, honoring
        // its own persisted order relative to the primary order.
        const int sub = compareColumn(left, right, m_subSortColumn);
        if (m_subSortOrder == sortOrder())
            result = sub;
        else
            result = -sub;
    }
    return result < 0;
}

// --- id helpers ---

QStringList TorrentFilterProxyModel::visibleIds() const
{
    QStringList ids;
    ids.reserve(rowCount());
    for (int i = 0; i < rowCount(); ++i)
        ids.append(idAt(i));
    return ids;
}

QString TorrentFilterProxyModel::idAt(int row) const
{
    if ((row < 0) || (row >= rowCount()))
        return {};
    return data(index(row, 0), TransferListModel::IdRole).toString();
}
