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

#include <QBitArray>
#include <QList>
#include <QObject>
#include <QString>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;

class PeerListModel;
class TrackerListModel;
class TrackerListSortModel;
class WebSeedListModel;
class SpeedPlotModel;

namespace BitTorrent
{
    class Torrent;
}

/**
 * @file propertiescontroller.h
 * @brief The @c PropertiesController QML singleton — backs the whole Properties
 *        panel (General / Trackers / Peers / HTTP Sources / Content / Speed).
 *
 * It owns the current torrent selection and the per-tab models
 * (@ref peerModel, @ref trackerModel, @ref webSeedModel, @ref speedPlotModel),
 * exposes the General tab's fully-formatted value strings as notifiable
 * properties, and bridges the async piece reads (downloading pieces + piece
 * availability) into @c QBitArray / @c QList<int> properties that the
 * @c PiecesBarItem binds to.
 *
 * The panel is refreshed reactively off @c BitTorrent::Session::torrentsUpdated
 * for the *currently shown* tab only (never polled). The QML view sets
 * @ref currentTorrentId (from the transfer-list selection) and @ref currentTab.
 */
class PropertiesController final : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(PropertiesController)

    Q_PROPERTY(QString currentTorrentId READ currentTorrentId WRITE setCurrentTorrentId NOTIFY currentTorrentChanged FINAL)
    Q_PROPERTY(bool hasTorrent READ hasTorrent NOTIFY currentTorrentChanged FINAL)
    Q_PROPERTY(int currentTab READ currentTab WRITE setCurrentTab NOTIFY currentTabChanged FINAL)

    // Owned per-tab models (created once, shared for the panel's lifetime).
    Q_PROPERTY(QObject *peerModel READ peerModel CONSTANT FINAL)
    Q_PROPERTY(QObject *trackerModel READ trackerModel CONSTANT FINAL)
    Q_PROPERTY(QObject *webSeedModel READ webSeedModel CONSTANT FINAL)
    Q_PROPERTY(QObject *speedPlotModel READ speedPlotModel CONSTANT FINAL)
    Q_PROPERTY(QObject *contentHandler READ contentHandler NOTIFY currentTorrentChanged FINAL)

    // --- General tab (all already formatted + translated) ---
    Q_PROPERTY(QString name READ name NOTIFY generalChanged FINAL)
    Q_PROPERTY(bool hasMetadata READ hasMetadata NOTIFY generalChanged FINAL)
    Q_PROPERTY(bool showAvailability READ showAvailability NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString savePath READ savePath NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString comment READ comment NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString createdBy READ createdBy NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString createdOn READ createdOn NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString totalSize READ totalSize NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString pieces READ pieces NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString isPrivate READ isPrivate NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString infoHashV1 READ infoHashV1 NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString infoHashV2 READ infoHashV2 NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString addedOn READ addedOn NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString completedOn READ completedOn NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString lastSeenComplete READ lastSeenComplete NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString wasted READ wasted NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString uploaded READ uploaded NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString downloaded READ downloaded NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString uploadLimit READ uploadLimit NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString downloadLimit READ downloadLimit NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString timeElapsed READ timeElapsed NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString connections READ connections NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString eta READ eta NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString reannounceIn READ reannounceIn NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString shareRatio READ shareRatio NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString popularity READ popularity NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString seeds READ seeds NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString peers READ peers NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString downloadSpeed READ downloadSpeed NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString uploadSpeed READ uploadSpeed NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString progress READ progress NOTIFY generalChanged FINAL)
    Q_PROPERTY(qreal progressValue READ progressValue NOTIFY generalChanged FINAL)
    Q_PROPERTY(QString averageAvailability READ averageAvailability NOTIFY generalChanged FINAL)

    // --- Piece bars (bound by PiecesBarItem) ---
    Q_PROPERTY(QBitArray havePieces READ havePieces NOTIFY piecesChanged FINAL)
    Q_PROPERTY(QBitArray downloadingPieces READ downloadingPieces NOTIFY piecesChanged FINAL)
    Q_PROPERTY(QList<int> pieceAvailability READ pieceAvailability NOTIFY availabilityChanged FINAL)

public:
    /// The property tabs, in display order (matches the legacy PropTabBar).
    enum Tab
    {
        General = 0,
        Trackers,
        Peers,
        HttpSources,
        Content,
        Speed
    };
    Q_ENUM(Tab)

    /// QML singleton factory — returns the shared app-owned instance.
    static PropertiesController *create(QQmlEngine *engine, QJSEngine *jsEngine);

    [[nodiscard]] QString currentTorrentId() const { return m_currentTorrentId; }
    void setCurrentTorrentId(const QString &id);
    /// Convenience alias used by QML selection wiring.
    Q_INVOKABLE void setCurrentTorrent(const QString &id) { setCurrentTorrentId(id); }

    [[nodiscard]] bool hasTorrent() const { return m_torrent != nullptr; }

    [[nodiscard]] int currentTab() const { return m_currentTab; }
    void setCurrentTab(int tab);

    [[nodiscard]] QObject *peerModel() const;
    [[nodiscard]] QObject *trackerModel() const;
    [[nodiscard]] QObject *webSeedModel() const;
    [[nodiscard]] QObject *speedPlotModel() const;
    [[nodiscard]] QObject *contentHandler() const;

    // --- General tab getters ---
    [[nodiscard]] QString name() const { return m_name; }
    [[nodiscard]] bool hasMetadata() const { return m_hasMetadata; }
    [[nodiscard]] bool showAvailability() const { return m_showAvailability; }
    [[nodiscard]] QString savePath() const { return m_savePath; }
    [[nodiscard]] QString comment() const { return m_comment; }
    [[nodiscard]] QString createdBy() const { return m_createdBy; }
    [[nodiscard]] QString createdOn() const { return m_createdOn; }
    [[nodiscard]] QString totalSize() const { return m_totalSize; }
    [[nodiscard]] QString pieces() const { return m_pieces; }
    [[nodiscard]] QString isPrivate() const { return m_isPrivate; }
    [[nodiscard]] QString infoHashV1() const { return m_infoHashV1; }
    [[nodiscard]] QString infoHashV2() const { return m_infoHashV2; }
    [[nodiscard]] QString addedOn() const { return m_addedOn; }
    [[nodiscard]] QString completedOn() const { return m_completedOn; }
    [[nodiscard]] QString lastSeenComplete() const { return m_lastSeenComplete; }
    [[nodiscard]] QString wasted() const { return m_wasted; }
    [[nodiscard]] QString uploaded() const { return m_uploaded; }
    [[nodiscard]] QString downloaded() const { return m_downloaded; }
    [[nodiscard]] QString uploadLimit() const { return m_uploadLimit; }
    [[nodiscard]] QString downloadLimit() const { return m_downloadLimit; }
    [[nodiscard]] QString timeElapsed() const { return m_timeElapsed; }
    [[nodiscard]] QString connections() const { return m_connections; }
    [[nodiscard]] QString eta() const { return m_eta; }
    [[nodiscard]] QString reannounceIn() const { return m_reannounceIn; }
    [[nodiscard]] QString shareRatio() const { return m_shareRatio; }
    [[nodiscard]] QString popularity() const { return m_popularity; }
    [[nodiscard]] QString seeds() const { return m_seeds; }
    [[nodiscard]] QString peers() const { return m_peers; }
    [[nodiscard]] QString downloadSpeed() const { return m_downloadSpeed; }
    [[nodiscard]] QString uploadSpeed() const { return m_uploadSpeed; }
    [[nodiscard]] QString progress() const { return m_progress; }
    [[nodiscard]] qreal progressValue() const { return m_progressValue; }
    [[nodiscard]] QString averageAvailability() const { return m_averageAvailability; }

    [[nodiscard]] const QBitArray &havePieces() const { return m_havePieces; }
    [[nodiscard]] const QBitArray &downloadingPieces() const { return m_downloadingPieces; }
    [[nodiscard]] const QList<int> &pieceAvailability() const { return m_pieceAvailability; }

    /// Force a refresh of the active tab (e.g. after it becomes visible).
    Q_INVOKABLE void refresh();

    // --- Trackers tab actions ------------------------------------------------
    // These back the Trackers tab's context menu and dialogs. Every one of them
    // reports its outcome through @ref trackerActionFinished so the UI can never
    // present a command as having worked when it did not.

    /// Adds every tracker URL in @a multilineUrls to the current torrent. One
    /// URL per line; a blank line starts a new tier.
    Q_INVOKABLE void addTrackers(const QString &multilineUrls);

    /// Replaces @a oldUrl with @a newUrl, keeping that tracker's tier.
    Q_INVOKABLE void editTracker(const QString &oldUrl, const QString &newUrl);

    /// Removes every tracker whose URL appears in @a urls.
    Q_INVOKABLE void removeTrackers(const QStringList &urls);

    /// Reannounces to only the trackers whose URLs appear in @a urls.
    Q_INVOKABLE void reannounceToTrackers(const QStringList &urls);

    /// Reannounces to every tracker of the current torrent.
    Q_INVOKABLE void reannounceToAllTrackers();

    /// Downloads a newline-separated tracker list from @a url and adds it to the
    /// current torrent. Bounded, proxied per preference, and always terminated
    /// by @ref trackerListFetchFinished so the caller's progress state resets
    /// even on failure.
    Q_INVOKABLE void fetchTrackerList(const QString &url);

signals:
    /// Outcome of a Trackers-tab action. @a ok is false when nothing was
    /// changed, and @a message is always a translated, user-facing sentence.
    void trackerActionFinished(bool ok, const QString &message);

    /// Always emitted when a @ref fetchTrackerList attempt ends, successfully
    /// or not, so a busy indicator can never be left spinning.
    void trackerListFetchFinished();

    void currentTorrentChanged();
    void currentTabChanged();
    void generalChanged();
    void piecesChanged();
    void availabilityChanged();

private:
    explicit PropertiesController(QObject *parent = nullptr);

    void onTorrentsUpdated(const QList<BitTorrent::Torrent *> &torrents);
    void onTorrentAboutToBeRemoved(BitTorrent::Torrent *torrent);
    void onSavePathChanged(BitTorrent::Torrent *torrent);
    void onMetadataReceived(BitTorrent::Torrent *torrent);

    void bindModelsToTorrent();
    void refreshActiveTab();
    void refreshGeneral();
    void fetchPieceData();
    void clearGeneral();

    QString m_currentTorrentId;
    BitTorrent::Torrent *m_torrent = nullptr;
    int m_currentTab = General;

    PeerListModel *m_peerModel = nullptr;
    TrackerListModel *m_trackerModel = nullptr;
    TrackerListSortModel *m_trackerSortModel = nullptr;
    WebSeedListModel *m_webSeedModel = nullptr;
    SpeedPlotModel *m_speedPlotModel = nullptr;

    quint64 m_pieceGeneration = 0;

    // General-tab formatted values.
    QString m_name;
    bool m_hasMetadata = false;
    bool m_showAvailability = false;
    QString m_savePath;
    QString m_comment;
    QString m_createdBy;
    QString m_createdOn;
    QString m_totalSize;
    QString m_pieces;
    QString m_isPrivate;
    QString m_infoHashV1;
    QString m_infoHashV2;
    QString m_addedOn;
    QString m_completedOn;
    QString m_lastSeenComplete;
    QString m_wasted;
    QString m_uploaded;
    QString m_downloaded;
    QString m_uploadLimit;
    QString m_downloadLimit;
    QString m_timeElapsed;
    QString m_connections;
    QString m_eta;
    QString m_reannounceIn;
    QString m_shareRatio;
    QString m_popularity;
    QString m_seeds;
    QString m_peers;
    QString m_downloadSpeed;
    QString m_uploadSpeed;
    QString m_progress;
    qreal m_progressValue = 0;
    QString m_averageAvailability;

    QBitArray m_havePieces;
    QBitArray m_downloadingPieces;
    QList<int> m_pieceAvailability;
};
