/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QAbstractListModel>
#include <QDate>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include <qqmlintegration.h>

#include "base/torrentjournal/torrentjournalop.h"

/**
 * @brief Newest-first list model over one journal repo ("actions" or
 *        "settings") for the History panel.
 *
 * Supports the design's composed commit search (plain or regex over message +
 * sha + diff text), date range, and action facets. Row 0 is the newest commit,
 * so "restore to row i" reverts exactly i newer actions.
 */
class JournalHistoryModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString repo READ repo WRITE setRepo NOTIFY repoChanged)
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterChanged)
    Q_PROPERTY(bool filterRegex READ filterRegex WRITE setFilterRegex NOTIFY filterChanged)
    Q_PROPERTY(QString filterRegexFlags READ filterRegexFlags WRITE setFilterRegexFlags NOTIFY filterChanged)
    Q_PROPERTY(QString fromDate READ fromDate WRITE setFromDate NOTIFY filterChanged)
    Q_PROPERTY(QString toDate READ toDate WRITE setToDate NOTIFY filterChanged)
    Q_PROPERTY(QStringList actionFilter READ actionFilter WRITE setActionFilter NOTIFY filterChanged)
    Q_PROPERTY(bool filterValid READ filterValid NOTIFY filterChanged)
    Q_PROPERTY(QString filterError READ filterError NOTIFY filterChanged)
    Q_PROPERTY(QVariantList actionFacets READ actionFacets NOTIFY facetsChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles
    {
        CommitIdRole = Qt::UserRole + 1,
        ShaRole,
        MessageRole,
        TimeTextRole,
        DateKeyRole,
        DiffLinesRole,
        UndoableRole,
        CanRestoreRole,
        OriginRole,
        OpCountRole
    };

    explicit JournalHistoryModel(QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QString repo() const;
    void setRepo(const QString &repo);
    [[nodiscard]] QString filterText() const;
    void setFilterText(const QString &text);
    [[nodiscard]] bool filterRegex() const;
    void setFilterRegex(bool regex);
    [[nodiscard]] QString filterRegexFlags() const;
    void setFilterRegexFlags(const QString &flags);
    [[nodiscard]] QString fromDate() const;
    void setFromDate(const QString &date);
    [[nodiscard]] QString toDate() const;
    void setToDate(const QString &date);
    [[nodiscard]] QStringList actionFilter() const;
    void setActionFilter(const QStringList &actions);
    [[nodiscard]] bool filterValid() const;
    [[nodiscard]] QString filterError() const;
    [[nodiscard]] QVariantList actionFacets() const;
    [[nodiscard]] int count() const;

    Q_INVOKABLE void refresh();

signals:
    void repoChanged();
    void filterChanged();
    void facetsChanged();
    void countChanged();

private:
    void reload();
    [[nodiscard]] bool matchesFilter(const TorrentJournalNS::JournalEntry &entry) const;
    [[nodiscard]] bool matchesTextFilter(const TorrentJournalNS::JournalEntry &entry) const;
    [[nodiscard]] bool matchesDateFilter(const TorrentJournalNS::JournalEntry &entry) const;
    [[nodiscard]] QStringList actionIds(const TorrentJournalNS::JournalEntry &entry) const;
    void updateDateFilterState();

    QString m_repo = QStringLiteral("actions");
    QString m_filterText;
    bool m_filterRegex = false;
    QString m_filterRegexFlags = QStringLiteral("iu");
    QString m_fromDateText;
    QString m_toDateText;
    QStringList m_actionFilter;
    bool m_filterValid = true;
    QString m_filterError;
    QDate m_fromDateValue;
    QDate m_toDateValue;
    QVariantList m_actionFacets;
    QList<TorrentJournalNS::JournalEntry> m_entries;
};
