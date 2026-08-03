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

#include "propertiescontroller.h"

#include <algorithm>

#include <QBitArray>
#include <QDateTime>
#include <QFutureWatcher>
#include <QJSEngine>
#include <QList>
#include <QLocale>
#include <QPointer>
#include <QQmlEngine>

#include "base/bittorrent/infohash.h"
#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/torrentinfo.h"
#include "base/bittorrent/trackerentry.h"
#include "base/bittorrent/trackerentrystatus.h"
#include "base/logging.h"
#include "base/net/downloadmanager.h"
#include "base/preferences.h"
#include "base/unicodestrings.h"
#include "base/utils/fs/path.h"
#include "base/utils/misc.h"
#include "base/utils/string.h"
#include "models/peerlistmodel.h"
#include "models/speedplotmodel.h"
#include "models/trackerlistmodel.h"
#include "models/webseedlistmodel.h"

using namespace Qt::StringLiterals;

namespace
{
    /// Bound for a downloaded tracker list, which is a few KiB of plain text.
    constexpr qint64 MaxTrackerListSize = 1024 * 1024;

    /// Cap for the "ETA" field — mirrors the legacy MAX_ETA (100 days) so that an
    /// arbitrarily large ETA renders as the ∞ sentinel via userFriendlyDuration.
    constexpr qlonglong MAX_ETA = 8640000;

    /// Shared instance backing the QML singleton.
    PropertiesController *s_instance = nullptr;

    /// A torrent timestamp formatted as a localized short date/time, or empty.
    QString formatDateTime(const QDateTime &dt)
    {
        if (!dt.isValid())
            return {};
        return QLocale().toString(dt.toLocalTime(), QLocale::ShortFormat);
    }
}

PropertiesController::PropertiesController(QObject *parent)
    : QObject(parent)
    , m_peerModel(new PeerListModel(this))
    , m_trackerModel(new TrackerListModel(this))
    , m_trackerSortModel(new TrackerListSortModel(this))
    , m_webSeedModel(new WebSeedListModel(this))
    , m_speedPlotModel(new SpeedPlotModel(this))
{
    m_trackerSortModel->setSourceModel(m_trackerModel);

    auto *session = BitTorrent::Session::instance();
    connect(session, &BitTorrent::Session::torrentsUpdated
            , this, &PropertiesController::onTorrentsUpdated);
    connect(session, &BitTorrent::Session::torrentAboutToBeRemoved
            , this, &PropertiesController::onTorrentAboutToBeRemoved);
    connect(session, &BitTorrent::Session::torrentSavePathChanged
            , this, &PropertiesController::onSavePathChanged);
    connect(session, &BitTorrent::Session::torrentMetadataReceived
            , this, &PropertiesController::onMetadataReceived);

    qCDebug(lcUi) << "PropertiesController constructed";
}

PropertiesController *PropertiesController::create(QQmlEngine *engine, QJSEngine *jsEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(jsEngine)

    if (s_instance == nullptr)
        s_instance = new PropertiesController;
    // The controller lives for the whole application; keep it C++-owned so the
    // QML garbage collector never reclaims the shared singleton.
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

QObject *PropertiesController::peerModel() const
{
    return m_peerModel;
}

QObject *PropertiesController::trackerModel() const
{
    // The proxy is exposed so the QML TreeView sorts while pinning DHT/PeX/LSD.
    return m_trackerSortModel;
}

QObject *PropertiesController::webSeedModel() const
{
    return m_webSeedModel;
}

QObject *PropertiesController::speedPlotModel() const
{
    return m_speedPlotModel;
}

QObject *PropertiesController::contentHandler() const
{
    return m_torrent;
}

void PropertiesController::setCurrentTorrentId(const QString &id)
{
    if (m_currentTorrentId == id)
        return;

    m_currentTorrentId = id;

    auto *session = BitTorrent::Session::instance();
    m_torrent = id.isEmpty() ? nullptr : session->getTorrent(BitTorrent::TorrentID::fromString(id));

    qCInfo(lcUi) << "Properties current torrent ->"
                 << (m_torrent ? m_torrent->name() : u"<none>"_s);

    bindModelsToTorrent();
    emit currentTorrentChanged();

    if (m_torrent)
    {
        refreshGeneral();
        refreshActiveTab();
    }
    else
    {
        clearGeneral();
    }
}

void PropertiesController::setCurrentTab(const int tab)
{
    if (m_currentTab == tab)
        return;

    m_currentTab = tab;
    qCDebug(lcUi) << "Properties tab ->" << tab;
    emit currentTabChanged();

    // The Peers table only fetches while its tab is shown.
    m_peerModel->setActive(m_currentTab == Peers);

    refreshActiveTab();
}

void PropertiesController::refresh()
{
    if (!m_torrent)
        return;

    refreshGeneral();
    refreshActiveTab();
}

// ---- Trackers tab actions --------------------------------------------------

void PropertiesController::addTrackers(const QString &multilineUrls)
{
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        return;
    }

    // parseTrackerEntries handles the one-per-line/blank-line-is-a-new-tier
    // convention, so the tier the user typed is the tier that is stored.
    const QList<BitTorrent::TrackerEntry> entries =
        BitTorrent::parseTrackerEntries(multilineUrls);
    if (entries.isEmpty())
    {
        emit trackerActionFinished(false, tr("No valid tracker URL was given."));
        return;
    }

    m_torrent->addTrackers(entries);
    qCInfo(lcUi) << "Added" << entries.size() << "tracker(s) to" << m_torrent->name();
    emit trackerActionFinished(true, tr("Added %n tracker(s).", "", static_cast<int>(entries.size())));
    refresh();
}

void PropertiesController::editTracker(const QString &oldUrl, const QString &newUrl)
{
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        return;
    }

    const QString trimmed = newUrl.trimmed();
    if (trimmed.isEmpty())
    {
        emit trackerActionFinished(false, tr("The new tracker URL is empty."));
        return;
    }
    if (trimmed == oldUrl)
        return;

    // Rebuild the full list so the edited tracker keeps its position and tier;
    // removing and re-adding would silently move it to the end of tier 0.
    const QList<BitTorrent::TrackerEntryStatus> current = m_torrent->trackers();
    QList<BitTorrent::TrackerEntry> replacement;
    replacement.reserve(current.size());
    bool found = false;
    for (const BitTorrent::TrackerEntryStatus &status : current)
    {
        if (status.url == trimmed)
        {
            emit trackerActionFinished(false, tr("That tracker is already in the list."));
            return;
        }
        if (status.url == oldUrl)
        {
            replacement.append({trimmed, status.tier});
            found = true;
        }
        else
        {
            replacement.append({status.url, status.tier});
        }
    }

    if (!found)
    {
        emit trackerActionFinished(false, tr("That tracker is no longer in the list."));
        return;
    }

    m_torrent->replaceTrackers(replacement);
    qCInfo(lcUi) << "Replaced tracker" << oldUrl << "with" << trimmed;
    emit trackerActionFinished(true, tr("Tracker updated."));
    refresh();
}

void PropertiesController::removeTrackers(const QStringList &urls)
{
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        return;
    }
    if (urls.isEmpty())
        return;

    m_torrent->removeTrackers(urls);
    qCInfo(lcUi) << "Removed" << urls.size() << "tracker(s) from" << m_torrent->name();
    emit trackerActionFinished(true, tr("Removed %n tracker(s).", "", static_cast<int>(urls.size())));
    refresh();
}

void PropertiesController::reannounceToTrackers(const QStringList &urls)
{
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        return;
    }
    if (urls.isEmpty())
        return;

    // forceReannounce works on tracker indexes, so resolve each URL against the
    // torrent's current list rather than assuming the view's row order matches.
    const QList<BitTorrent::TrackerEntryStatus> current = m_torrent->trackers();
    int announced = 0;
    for (int index = 0; index < current.size(); ++index)
    {
        if (!urls.contains(current.at(index).url))
            continue;

        m_torrent->forceReannounce(index);
        ++announced;
    }

    if (announced == 0)
    {
        emit trackerActionFinished(false, tr("Those trackers are no longer in the list."));
        return;
    }

    qCInfo(lcUi) << "Reannounced to" << announced << "tracker(s)";
    emit trackerActionFinished(true, tr("Reannounced to %n tracker(s).", "", announced));
}

void PropertiesController::reannounceToAllTrackers()
{
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        return;
    }

    m_torrent->forceReannounce();
    qCInfo(lcUi) << "Reannounced to all trackers of" << m_torrent->name();
    emit trackerActionFinished(true, tr("Reannounced to every tracker."));
}

void PropertiesController::fetchTrackerList(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (trimmed.isEmpty())
    {
        emit trackerActionFinished(false, tr("No tracker list URL was given."));
        emit trackerListFetchFinished();
        return;
    }
    if (!m_torrent)
    {
        emit trackerActionFinished(false, tr("No torrent is selected."));
        emit trackerListFetchFinished();
        return;
    }

    // Bounded: a tracker list is a few kilobytes of text, and an unbounded
    // download here would buffer whatever the URL happens to serve.
    const auto request = Net::DownloadRequest(trimmed)
        .limit(MaxTrackerListSize);
    const QString torrentId = m_currentTorrentId;

    qCInfo(lcUi) << "Downloading tracker list from" << trimmed;
    Net::DownloadManager::instance()->download(request
        , Preferences::instance()->useProxyForGeneralPurposes()
        , this, [this, torrentId](const Net::DownloadResult &result)
    {
        emit trackerListFetchFinished();

        if (result.status != Net::DownloadStatus::Success)
        {
            qCWarning(lcUi) << "Tracker list download failed:" << result.errorString;
            emit trackerActionFinished(false
                , tr("Could not download the tracker list. %1").arg(result.errorString));
            return;
        }

        // The selection can change while the download is in flight; adding the
        // list to whatever happens to be selected now would be wrong.
        if (!m_torrent || (m_currentTorrentId != torrentId))
        {
            emit trackerActionFinished(false
                , tr("The torrent changed while the tracker list was downloading."));
            return;
        }

        addTrackers(QString::fromUtf8(result.data));
    });
}

void PropertiesController::bindModelsToTorrent()
{
    m_peerModel->setTorrent(m_torrent);
    m_peerModel->setActive(m_currentTab == Peers);
    m_trackerModel->setTorrent(m_torrent);
    m_webSeedModel->setTorrent(m_torrent);
    // SpeedPlotModel is session-wide and needs no per-torrent binding.
}

void PropertiesController::refreshActiveTab()
{
    if (!m_torrent)
        return;

    switch (m_currentTab)
    {
    case General:
        refreshGeneral();
        fetchPieceData();
        break;
    case Peers:
        m_peerModel->setActive(true);
        m_peerModel->refresh();
        break;
    case HttpSources:
        m_webSeedModel->refresh();
        break;
    case Trackers:
    case Content:
    case Speed:
    default:
        // Trackers refresh off Session signals; Content is owned by another
        // feature; Speed streams off statsUpdated inside SpeedPlotModel.
        break;
    }
}

void PropertiesController::onTorrentsUpdated(const QList<BitTorrent::Torrent *> &torrents)
{
    if (!m_torrent || !torrents.contains(m_torrent))
        return;

    // The Peers/WebSeed models self-refresh from their own signal handlers; here
    // we only need to re-pull the General-tab dynamic fields and piece bars.
    if (m_currentTab == General)
    {
        refreshGeneral();
        fetchPieceData();
    }
}

void PropertiesController::onTorrentAboutToBeRemoved(BitTorrent::Torrent *torrent)
{
    if (torrent != m_torrent)
        return;

    qCInfo(lcUi) << "Properties current torrent is being removed; clearing panel";
    m_currentTorrentId.clear();
    m_torrent = nullptr;
    bindModelsToTorrent();
    clearGeneral();
    emit currentTorrentChanged();
}

void PropertiesController::onSavePathChanged(BitTorrent::Torrent *torrent)
{
    if (torrent != m_torrent)
        return;

    m_savePath = m_torrent->savePath().toString();
    qCDebug(lcUi) << "Properties save path updated ->" << m_savePath;
    emit generalChanged();
}

void PropertiesController::onMetadataReceived(BitTorrent::Torrent *torrent)
{
    if (torrent != m_torrent)
        return;

    qCDebug(lcUi) << "Properties torrent received metadata; reloading static fields";
    refreshGeneral();
    fetchPieceData();
}

void PropertiesController::refreshGeneral()
{
    if (!m_torrent)
    {
        clearGeneral();
        return;
    }

    const BitTorrent::Torrent *t = m_torrent;
    m_hasMetadata = t->hasMetadata();
    m_name = t->name();

    // --- Pieces bars (visibility + captions) ---
    m_progressValue = t->progress();
    m_progress = Utils::String::fromDouble(m_progressValue * 100, 1) + u'%';

    const qreal copies = t->distributedCopies();
    m_averageAvailability = (copies >= 0)
            ? Utils::String::fromDouble(copies, 3)
            : tr("N/A");

    m_showAvailability = m_hasMetadata && !t->isFinished() && !t->isStopped()
            && !t->isQueued() && !t->isChecking();

    // --- Transfer group ---
    const qlonglong activeTime = t->activeTime();
    const qlonglong finishedTime = t->finishedTime();
    m_timeElapsed = t->isFinished()
            ? tr("%1 (seeded for %2)", "e.g. 4m39s (seeded for 3m10s)")
                  .arg(Utils::Misc::userFriendlyDuration(activeTime)
                       , Utils::Misc::userFriendlyDuration(finishedTime))
            : Utils::Misc::userFriendlyDuration(activeTime);

    m_eta = Utils::Misc::userFriendlyDuration(t->eta(), MAX_ETA);

    const int connectionsLimit = t->connectionsLimit();
    m_connections = tr("%1 (%2 max)", "e.g. 44 (12 max)")
            .arg(QString::number(t->connectionsCount())
                 , (connectionsLimit < 0) ? C_INFINITY : QString::number(connectionsLimit));

    m_downloaded = tr("%1 (%2 this session)")
            .arg(Utils::Misc::friendlyUnit(t->totalDownload())
                 , Utils::Misc::friendlyUnit(t->totalPayloadDownload()));
    m_uploaded = tr("%1 (%2 this session)")
            .arg(Utils::Misc::friendlyUnit(t->totalUpload())
                 , Utils::Misc::friendlyUnit(t->totalPayloadUpload()));

    m_seeds = tr("%1 (%2 total)", "e.g. 3 (10 total)")
            .arg(QString::number(t->seedsCount()), QString::number(t->totalSeedsCount()));
    m_peers = tr("%1 (%2 total)", "e.g. 3 (10 total)")
            .arg(QString::number(t->leechsCount()), QString::number(t->totalLeechersCount()));

    const qlonglong dlDenominator = std::max<qlonglong>(1, activeTime - finishedTime);
    const qlonglong ulDenominator = std::max<qlonglong>(1, activeTime);
    m_downloadSpeed = tr("%1 (%2 avg.)")
            .arg(Utils::Misc::friendlyUnit(t->downloadPayloadRate(), true)
                 , Utils::Misc::friendlyUnit((t->totalDownload() / dlDenominator), true));
    m_uploadSpeed = tr("%1 (%2 avg.)")
            .arg(Utils::Misc::friendlyUnit(t->uploadPayloadRate(), true)
                 , Utils::Misc::friendlyUnit((t->totalUpload() / ulDenominator), true));

    m_downloadLimit = (t->downloadLimit() <= 0)
            ? C_INFINITY : Utils::Misc::friendlyUnit(t->downloadLimit(), true);
    m_uploadLimit = (t->uploadLimit() <= 0)
            ? C_INFINITY : Utils::Misc::friendlyUnit(t->uploadLimit(), true);

    m_wasted = Utils::Misc::friendlyUnit(t->wastedSize());

    const qreal ratio = t->realRatio();
    m_shareRatio = (ratio >= BitTorrent::Torrent::MAX_RATIO)
            ? C_INFINITY : Utils::String::fromDouble(ratio, 2);

    m_reannounceIn = Utils::Misc::userFriendlyDuration(t->nextAnnounce());
    m_lastSeenComplete = t->lastSeenComplete().isValid()
            ? formatDateTime(t->lastSeenComplete()) : tr("Never");

    const qreal popularity = t->popularity();
    m_popularity = (popularity >= BitTorrent::Torrent::MAX_RATIO)
            ? C_INFINITY : Utils::String::fromDouble(popularity, 2);

    // --- Information group ---
    m_totalSize = m_hasMetadata ? Utils::Misc::friendlyUnit(t->totalSize()) : QString();
    m_pieces = m_hasMetadata
            ? tr("%1 x %2 (have %3)", "e.g. 152 x 4MB (have 25)")
                  .arg(QString::number(t->piecesCount())
                       , Utils::Misc::friendlyUnit(t->pieceLength())
                       , QString::number(t->piecesHave()))
            : QString();
    m_createdBy = t->creator();
    m_addedOn = formatDateTime(t->addedTime());
    m_completedOn = formatDateTime(t->completedTime());
    m_createdOn = formatDateTime(t->creationDate());

    m_isPrivate = m_hasMetadata ? (t->isPrivate() ? tr("Yes") : tr("No")) : tr("N/A");

    const BitTorrent::InfoHash infoHash = t->infoHash();
    m_infoHashV1 = infoHash.v1().isValid() ? infoHash.v1().toString() : tr("N/A");
    m_infoHashV2 = infoHash.v2().isValid() ? infoHash.v2().toString() : tr("N/A");
    m_savePath = t->savePath().toString();

    const QString comment = t->comment();
    m_comment = comment.isEmpty() ? QString() : Utils::Misc::parseHtmlLinks(comment.toHtmlEscaped());

    emit generalChanged();
}

void PropertiesController::fetchPieceData()
{
    if (!m_torrent || !m_torrent->hasMetadata())
    {
        m_havePieces.clear();
        m_downloadingPieces.clear();
        m_pieceAvailability.clear();
        emit piecesChanged();
        emit availabilityChanged();
        return;
    }

    // The have-pieces bitfield is available synchronously.
    m_havePieces = m_torrent->pieces();
    emit piecesChanged();

    const quint64 generation = ++m_pieceGeneration;
    const QPointer<BitTorrent::Torrent> guard(m_torrent);

    // In-progress ("partial") pieces — async.
    auto *dlWatcher = new QFutureWatcher<QBitArray>(this);
    connect(dlWatcher, &QFutureWatcherBase::finished, this, [this, dlWatcher, generation, guard]
    {
        dlWatcher->deleteLater();
        if ((generation != m_pieceGeneration) || (m_torrent != guard) || !m_torrent)
            return;
        m_downloadingPieces = dlWatcher->result();
        emit piecesChanged();
    });
    dlWatcher->setFuture(m_torrent->fetchDownloadingPieces());

    // Per-piece availability — only meaningful while the availability bar shows.
    if (m_showAvailability)
    {
        auto *avWatcher = new QFutureWatcher<QList<int>>(this);
        connect(avWatcher, &QFutureWatcherBase::finished, this, [this, avWatcher, generation, guard]
        {
            avWatcher->deleteLater();
            if ((generation != m_pieceGeneration) || (m_torrent != guard) || !m_torrent)
                return;
            m_pieceAvailability = avWatcher->result();
            emit availabilityChanged();
        });
        avWatcher->setFuture(m_torrent->fetchPieceAvailability());
    }
    else if (!m_pieceAvailability.isEmpty())
    {
        m_pieceAvailability.clear();
        emit availabilityChanged();
    }
}

void PropertiesController::clearGeneral()
{
    // Invalidate any in-flight piece fetches.
    ++m_pieceGeneration;

    m_name.clear();
    m_hasMetadata = false;
    m_showAvailability = false;
    m_savePath.clear();
    m_comment.clear();
    m_createdBy.clear();
    m_createdOn.clear();
    m_totalSize.clear();
    m_pieces.clear();
    m_isPrivate.clear();
    m_infoHashV1.clear();
    m_infoHashV2.clear();
    m_addedOn.clear();
    m_completedOn.clear();
    m_lastSeenComplete.clear();
    m_wasted.clear();
    m_uploaded.clear();
    m_downloaded.clear();
    m_uploadLimit.clear();
    m_downloadLimit.clear();
    m_timeElapsed.clear();
    m_connections.clear();
    m_eta.clear();
    m_reannounceIn.clear();
    m_shareRatio.clear();
    m_popularity.clear();
    m_seeds.clear();
    m_peers.clear();
    m_downloadSpeed.clear();
    m_uploadSpeed.clear();
    m_progress.clear();
    m_progressValue = 0;
    m_averageAvailability.clear();

    m_havePieces.clear();
    m_downloadingPieces.clear();
    m_pieceAvailability.clear();

    emit generalChanged();
    emit piecesChanged();
    emit availabilityChanged();
}
