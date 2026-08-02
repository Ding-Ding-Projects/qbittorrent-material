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

#include <QRegularExpression>
#include <QSortFilterProxyModel>
#include <QString>

#include <qqmlintegration.h>

#include "torrentfilter.h"

/**
 * @file torrentfilterproxymodel.h
 * @brief @c TorrentFilterProxyModel — the sort/filter proxy over
 *        @c TransferListModel driving the visible transfer list.
 *
 * Holds a @ref TorrentFilter (status + category + tag + tracker host + announce
 * status + id set + private) plus a selectable free-text column filter
 * (wildcard or regex).
 * Implements a natural, type-aware two-level sort: the active sort column plus a
 * remembered previous column as the tie-breaker (matching legacy qBittorrent's
 * `TransferListSortModel`).
 *
 * QML instantiates one per view: `TorrentFilterProxyModel { sourceModel: TransferListModel }`.
 */
class TorrentFilterProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int statusFilter READ statusFilter WRITE setStatusFilter NOTIFY filterChanged)
    Q_PROPERTY(QString categoryFilter READ categoryFilter WRITE setCategoryFilter NOTIFY filterChanged)
    Q_PROPERTY(QString tagFilter READ tagFilter WRITE setTagFilter NOTIFY filterChanged)
    Q_PROPERTY(QString trackerFilter READ trackerFilter WRITE setTrackerFilter NOTIFY filterChanged)
    Q_PROPERTY(QString textFilter READ textFilter WRITE setTextFilter NOTIFY filterChanged)
    Q_PROPERTY(int textFilterColumn READ textFilterColumn WRITE setTextFilterColumn NOTIFY filterChanged)
    Q_PROPERTY(bool useRegex READ useRegex WRITE setUseRegex NOTIFY filterChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    explicit TorrentFilterProxyModel(QObject *parent = nullptr);

    // --- filter accessors ---
    [[nodiscard]] int statusFilter() const;
    void setStatusFilter(int status);
    [[nodiscard]] QString categoryFilter() const;
    void setCategoryFilter(const QString &category);
    [[nodiscard]] QString tagFilter() const;
    void setTagFilter(const QString &tag);
    [[nodiscard]] QString trackerFilter() const;
    void setTrackerFilter(const QString &trackerHost);
    [[nodiscard]] QString textFilter() const;
    void setTextFilter(const QString &text);
    [[nodiscard]] int textFilterColumn() const;
    void setTextFilterColumn(int column);
    [[nodiscard]] bool useRegex() const;
    void setUseRegex(bool enabled);

    /// Clear the category criterion entirely (matches "All categories").
    Q_INVOKABLE void clearCategoryFilter();
    /// Clear the tag criterion entirely (matches "All tags").
    Q_INVOKABLE void clearTagFilter();
    /// Apply an announce-status filter (Warning/TrackerError/OtherError) or clear
    /// it with -1. Used by the Tracker-status sidebar panel.
    Q_INVOKABLE void setAnnounceStatusFilter(int flag);

    /// Sort by a transfer-list column (see @c TransferListModel::Column),
    /// remembering the previous column as the sub-sort tie-breaker.
    Q_INVOKABLE void sortByColumn(int column, Qt::SortOrder order);

    /// The TorrentID hex strings currently visible, in view order.
    [[nodiscard]] Q_INVOKABLE QStringList visibleIds() const;
    /// The TorrentID hex string at proxy @p row.
    [[nodiscard]] Q_INVOKABLE QString idAt(int row) const;

signals:
    void filterChanged();
    void countChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    [[nodiscard]] int compareColumn(const QModelIndex &left, const QModelIndex &right, int column) const;

    TorrentFilter m_filter;
    QString m_textPattern;
    int m_textFilterColumn = 1;    ///< TransferListModel::TR_NAME by default
    bool m_useRegex = false;
    QRegularExpression m_regex;

    int m_sortColumn = 1;          ///< TR_NAME by default
    int m_subSortColumn = 1;       ///< remembered previous sort column
    Qt::SortOrder m_subSortOrder = Qt::AscendingOrder;
};
