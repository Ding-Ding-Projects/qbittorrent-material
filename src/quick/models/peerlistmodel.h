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

#include <algorithm>

#include <QAbstractListModel>
#include <QFuture>
#include <QFutureWatcher>
#include <QHash>
#include <QHostAddress>
#include <QList>
#include <QMetaType>
#include <QPointer>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariant>

#include "base/bittorrent/peeraddress.h"
#include "base/bittorrent/peerinfo.h"
#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/torrentinfo.h"
#include "base/logging.h"
#include "base/preferences.h"
#include "base/utils/fs/path.h"
#include "base/utils/misc.h"
#include "base/utils/string.h"

/**
 * @file peerlistmodel.h
 * @brief The @c PeerListModel — flat list model backing the Properties → Peers table.
 *
 * One row per connected peer. Data is fetched asynchronously through
 * @c Torrent::fetchPeerInfo() and bridged with a @c QFutureWatcher (never blocked
 * on, never polled). A refresh is triggered off @c Session::torrentsUpdated while
 * the model is @ref active (the Peers tab is visible). Each column exposes a
 * formatted display role plus, for numeric columns, a raw @c *Value role a sort
 * proxy can order on.
 */
class PeerListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged FINAL)

public:
    enum Roles
    {
        CountryCodeRole = Qt::UserRole + 1, // "countryCode"
        CountryNameRole,                    // "countryName"
        IpRole,                             // "ip"
        PortRole,                           // "port"
        PortValueRole,                      // "portValue"
        ConnectionRole,                     // "connection"
        FlagsRole,                          // "flags"
        FlagsDescriptionRole,               // "flagsDescription"
        ClientRole,                         // "client"
        PeerIdClientRole,                   // "peerIdClient"
        ProgressRole,                       // "progress"
        ProgressValueRole,                  // "progressValue"
        DownSpeedRole,                      // "downSpeed"
        DownSpeedValueRole,                 // "downSpeedValue"
        UpSpeedRole,                        // "upSpeed"
        UpSpeedValueRole,                   // "upSpeedValue"
        TotalDownloadRole,                  // "totalDownload"
        TotalDownloadValueRole,             // "totalDownloadValue"
        TotalUploadRole,                    // "totalUpload"
        TotalUploadValueRole,               // "totalUploadValue"
        RelevanceRole,                      // "relevance"
        RelevanceValueRole,                 // "relevanceValue"
        ContributionRole,                   // "contribution"
        ContributionValueRole,              // "contributionValue"
        FilesRole                           // "files"
    };

    explicit PeerListModel(QObject *parent = nullptr)
        : QAbstractListModel(parent)
    {
        connect(BitTorrent::Session::instance(), &BitTorrent::Session::torrentsUpdated
                , this, &PeerListModel::onTorrentsUpdated);
        qCDebug(lcModel) << "PeerListModel constructed";
    }

    /// Bind the model to a torrent (nullptr clears it). Refreshes immediately.
    void setTorrent(BitTorrent::Torrent *torrent)
    {
        if (m_torrent == torrent)
            return;

        m_torrent = torrent;
        qCDebug(lcModel) << "PeerListModel torrent ->" << (torrent ? torrent->name() : QStringLiteral("<none>"));
        if (!m_torrent)
        {
            beginResetModel();
            m_rows.clear();
            endResetModel();
            emit countChanged();
        }
        else
        {
            refresh();
        }
    }

    [[nodiscard]] bool isActive() const { return m_active; }
    void setActive(const bool active)
    {
        if (m_active == active)
            return;

        m_active = active;
        emit activeChanged();
        if (m_active)
            refresh();
    }

    int rowCount(const QModelIndex &parent = {}) const override
    {
        return parent.isValid() ? 0 : static_cast<int>(m_rows.size());
    }

    QVariant data(const QModelIndex &index, const int role = Qt::DisplayRole) const override
    {
        if (!index.isValid() || (index.row() < 0) || (index.row() >= m_rows.size()))
            return {};

        const Row &r = m_rows.at(index.row());
        switch (role)
        {
        case CountryCodeRole:        return r.countryCode;
        case CountryNameRole:        return r.countryName;
        case IpRole:                 return r.ip;
        case PortRole:               return QString::number(r.port);
        case PortValueRole:          return r.port;
        case ConnectionRole:         return r.connection;
        case FlagsRole:              return r.flags;
        case FlagsDescriptionRole:   return r.flagsDescription;
        case ClientRole:             return r.client;
        case PeerIdClientRole:       return r.peerIdClient;
        case ProgressRole:           return percent(r.progress);
        case ProgressValueRole:      return r.progress;
        case DownSpeedRole:          return speed(r.downSpeed);
        case DownSpeedValueRole:     return r.downSpeed;
        case UpSpeedRole:            return speed(r.upSpeed);
        case UpSpeedValueRole:       return r.upSpeed;
        case TotalDownloadRole:      return size(r.totalDownload);
        case TotalDownloadValueRole: return r.totalDownload;
        case TotalUploadRole:        return size(r.totalUpload);
        case TotalUploadValueRole:   return r.totalUpload;
        case RelevanceRole:          return percent(r.relevance);
        case RelevanceValueRole:     return r.relevance;
        case ContributionRole:       return percent(r.contribution);
        case ContributionValueRole:  return r.contribution;
        case FilesRole:              return r.files;
        default:                     return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return {
            {CountryCodeRole, "countryCode"}, {CountryNameRole, "countryName"},
            {IpRole, "ip"}, {PortRole, "port"}, {PortValueRole, "portValue"},
            {ConnectionRole, "connection"}, {FlagsRole, "flags"},
            {FlagsDescriptionRole, "flagsDescription"}, {ClientRole, "client"},
            {PeerIdClientRole, "peerIdClient"}, {ProgressRole, "progress"},
            {ProgressValueRole, "progressValue"}, {DownSpeedRole, "downSpeed"},
            {DownSpeedValueRole, "downSpeedValue"}, {UpSpeedRole, "upSpeed"},
            {UpSpeedValueRole, "upSpeedValue"}, {TotalDownloadRole, "totalDownload"},
            {TotalDownloadValueRole, "totalDownloadValue"}, {TotalUploadRole, "totalUpload"},
            {TotalUploadValueRole, "totalUploadValue"}, {RelevanceRole, "relevance"},
            {RelevanceValueRole, "relevanceValue"}, {ContributionRole, "contribution"},
            {ContributionValueRole, "contributionValue"}, {FilesRole, "files"}
        };
    }

    /// Sort a visible table role, using raw numeric values for measured columns.
    Q_INVOKABLE void sortByRole(const QString &roleName, const int order)
    {
        m_sortRole = roleName;
        m_sortOrder = static_cast<Qt::SortOrder>(order);
        sortRows();
    }

    /// Return the "ip:port" string for @p row (bracketed for IPv6), or empty.
    Q_INVOKABLE QString peerEndpoint(const int row) const
    {
        if ((row < 0) || (row >= m_rows.size()))
            return {};

        const Row &r = m_rows.at(row);
        if (r.ip.contains(QLatin1Char(':'))) // IPv6
            return QStringLiteral("[") + r.ip + QStringLiteral("]:") + QString::number(r.port);
        return r.ip + QLatin1Char(':') + QString::number(r.port);
    }

    /// Permanently ban the given peer IPs (Session-wide), then refresh.
    Q_INVOKABLE void banPeers(const QStringList &ips)
    {
        qCInfo(lcModel) << "Banning" << ips.size() << "peer(s)";
        auto *session = BitTorrent::Session::instance();
        for (const QString &ip : ips)
        {
            session->banIP(ip);
            qCInfo(lcModel) << "Peer manually banned:" << ip;
        }
        refresh();
    }

    /// Try to connect the given "ip:port" endpoints. Returns the count accepted.
    Q_INVOKABLE int addPeers(const QStringList &endpoints)
    {
        if (!m_torrent)
            return 0;

        int accepted = 0;
        for (const QString &endpoint : endpoints)
        {
            const BitTorrent::PeerAddress addr = BitTorrent::PeerAddress::parse(endpoint);
            if (addr.ip.isNull())
            {
                qCWarning(lcModel) << "Ignoring malformed peer endpoint:" << endpoint;
                continue;
            }
            if (m_torrent->connectPeer(addr))
                ++accepted;
        }
        qCInfo(lcModel) << "addPeers: accepted" << accepted << "of" << endpoints.size();
        refresh();
        return accepted;
    }

    /// Re-fetch the peer list asynchronously (safe to call repeatedly).
    Q_INVOKABLE void refresh()
    {
        if (!m_torrent)
            return;

        const quint64 generation = ++m_generation;
        auto *watcher = new QFutureWatcher<QList<BitTorrent::PeerInfo>>(this);
        connect(watcher, &QFutureWatcherBase::finished, this
                , [this, watcher, generation, torrent = QPointer<BitTorrent::Torrent>(m_torrent)]
        {
            watcher->deleteLater();
            if ((generation != m_generation) || (m_torrent != torrent) || !m_torrent)
                return;
            applyPeers(watcher->result());
        });
        watcher->setFuture(m_torrent->fetchPeerInfo());
    }

signals:
    void activeChanged();
    void countChanged();

private:
    struct Row
    {
        QString countryCode;
        QString countryName;
        QString ip;
        ushort port = 0;
        QString connection;
        QString flags;
        QString flagsDescription;
        QString client;
        QString peerIdClient;
        qreal progress = 0;
        int downSpeed = 0;
        int upSpeed = 0;
        qlonglong totalDownload = 0;
        qlonglong totalUpload = 0;
        qreal relevance = 0;
        qreal contribution = 0;
        QString files;
    };

    void onTorrentsUpdated(const QList<BitTorrent::Torrent *> &torrents)
    {
        if (m_active && m_torrent && torrents.contains(m_torrent))
            refresh();
    }

    void applyPeers(const QList<BitTorrent::PeerInfo> &peers)
    {
        const Preferences *pref = Preferences::instance();
        m_hideZeroValues = pref->getHideZeroValues() && (pref->getHideZeroComboValues() == 0);

        const BitTorrent::TorrentInfo info = m_torrent->hasMetadata() ? m_torrent->info() : BitTorrent::TorrentInfo();
        const qlonglong torrentSize = m_torrent->totalSize();

        QList<Row> rows;
        rows.reserve(peers.size());
        for (const BitTorrent::PeerInfo &peer : peers)
        {
            Row row;
            row.countryCode = peer.country().toLower();
            row.countryName = row.countryCode;

            const BitTorrent::PeerAddress addr = peer.address();
            row.ip = peer.useI2PSocket() ? peer.I2PAddress() : addr.ip.toString();
            row.port = addr.port;
            row.connection = peer.connectionType();
            row.flags = peer.flags();
            row.flagsDescription = peer.flagsDescription();
            row.client = peer.client();
            row.peerIdClient = peer.peerIdClient();
            row.progress = peer.progress();
            row.downSpeed = peer.payloadDownSpeed();
            row.upSpeed = peer.payloadUpSpeed();
            row.totalDownload = peer.totalDownload();
            row.totalUpload = peer.totalUpload();
            row.relevance = peer.relevance();

            // Match upstream qBittorrent: the fraction of the peer's current
            // progress that this client supplied, with safe zero-size fallbacks.
            if (row.totalUpload > 0)
            {
                const qlonglong totalSize = (torrentSize <= 0) ? row.totalUpload : torrentSize;
                const qreal progressBytes = row.progress * totalSize;
                row.contribution = static_cast<qreal>(row.totalUpload)
                        / ((progressBytes <= 0) ? totalSize : progressBytes);
            }

            if (info.isValid())
            {
                QStringList files;
                const PathList paths = info.filesForPiece(peer.downloadingPieceIndex());
                files.reserve(paths.size());
                for (const Path &p : paths)
                    files.append(p.toString());
                row.files = files.join(QLatin1Char('\n'));
            }

            rows.append(std::move(row));
        }

        beginResetModel();
        m_rows = std::move(rows);
        sortRowsInPlace();
        endResetModel();
        emit countChanged();
        qCDebug(lcModel) << "PeerListModel refreshed:" << m_rows.size() << "peer(s)";
    }

    [[nodiscard]] QString speed(const qlonglong bytesPerSec) const
    {
        if (m_hideZeroValues && (bytesPerSec <= 0))
            return {};
        return Utils::Misc::friendlyUnit(bytesPerSec, true);
    }

    [[nodiscard]] QString size(const qlonglong bytes) const
    {
        if (m_hideZeroValues && (bytes <= 0))
            return {};
        return Utils::Misc::friendlyUnit(bytes);
    }

    static QString percent(const qreal fraction)
    {
        return Utils::String::fromDouble(fraction * 100, 1) + u'%';
    }

    void sortRows()
    {
        beginResetModel();
        sortRowsInPlace();
        endResetModel();
    }

    void sortRowsInPlace()
    {
        if (m_sortRole.isEmpty())
            return;

        const auto value = [this](const Row &row) -> QVariant
        {
            if (m_sortRole == u"port") return row.port;
            if (m_sortRole == u"progress") return row.progress;
            if (m_sortRole == u"downSpeed") return row.downSpeed;
            if (m_sortRole == u"upSpeed") return row.upSpeed;
            if (m_sortRole == u"totalDownload") return row.totalDownload;
            if (m_sortRole == u"totalUpload") return row.totalUpload;
            if (m_sortRole == u"relevance") return row.relevance;
            if (m_sortRole == u"contribution") return row.contribution;
            if (m_sortRole == u"countryCode") return row.countryName;
            if (m_sortRole == u"ip") return row.ip;
            if (m_sortRole == u"connection") return row.connection;
            if (m_sortRole == u"flags") return row.flags;
            if (m_sortRole == u"client") return row.client;
            if (m_sortRole == u"peerIdClient") return row.peerIdClient;
            if (m_sortRole == u"files") return row.files;
            return {};
        };
        const bool ascending = (m_sortOrder == Qt::AscendingOrder);
        std::stable_sort(m_rows.begin(), m_rows.end(), [&value, ascending](const Row &left, const Row &right)
        {
            const QVariant l = value(left);
            const QVariant r = value(right);
            int comparison = 0;
            if ((l.metaType().id() == QMetaType::QString) || (r.metaType().id() == QMetaType::QString))
                comparison = QString::localeAwareCompare(l.toString(), r.toString());
            else if (l.toDouble() < r.toDouble())
                comparison = -1;
            else if (l.toDouble() > r.toDouble())
                comparison = 1;
            return ascending ? (comparison < 0) : (comparison > 0);
        });
    }

    BitTorrent::Torrent *m_torrent = nullptr;
    QList<Row> m_rows;
    bool m_active = false;
    bool m_hideZeroValues = false;
    QString m_sortRole;
    Qt::SortOrder m_sortOrder = Qt::AscendingOrder;
    quint64 m_generation = 0;
};
