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

#include "transfercontroller.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QMap>
#include <QSet>
#include <QStringView>
#include <QUrl>

#include "base/bittorrent/infohash.h"
#include "base/bittorrent/session.h"
#include "base/bittorrent/sharelimits.h"
#include "base/bittorrent/trackerentry.h"
#include "base/bittorrent/trackerentrystatus.h"
#include "base/bittorrent/torrent.h"
#include "base/logging.h"
#include "base/tag.h"
#include "base/utils/fs.h"
#include "base/utils/fs/path.h"
#include "base/utils/misc.h"

using namespace BitTorrent;

TransferController *TransferController::m_instance = nullptr;

TransferController::TransferController(QObject *parent)
    : QObject(parent)
{
    qCDebug(lcUi) << "TransferController created";
}

TransferController *TransferController::create(QQmlEngine *, QJSEngine *)
{
    qCInfo(lcUi) << "TransferController QML singleton requested";
    return instance();
}

TransferController *TransferController::instance()
{
    if (!m_instance)
        m_instance = new TransferController;
    return m_instance;
}

// --- selection ---

QStringList TransferController::selectedIds() const
{
    return m_selectedIds;
}

void TransferController::setSelectedIds(const QStringList &ids)
{
    if (m_selectedIds == ids)
        return;
    m_selectedIds = ids;
    qCDebug(lcUi) << "TransferController selection ->" << ids.size() << "torrent(s)";
    emit selectionChanged();
}

int TransferController::selectionCount() const
{
    return static_cast<int>(m_selectedIds.size());
}

BitTorrent::Torrent *TransferController::torrentFromId(const QString &id) const
{
    Session *const session = Session::instance();
    if (!session)
        return nullptr;
    return session->getTorrent(TorrentID::fromString(id));
}

QList<BitTorrent::Torrent *> TransferController::selectedTorrents() const
{
    QList<Torrent *> torrents;
    torrents.reserve(m_selectedIds.size());
    for (const QString &id : m_selectedIds)
    {
        if (Torrent *const torrent = torrentFromId(id))
            torrents.append(torrent);
    }
    return torrents;
}

QList<BitTorrent::TorrentID> TransferController::selectedTorrentIDs() const
{
    QList<TorrentID> ids;
    ids.reserve(m_selectedIds.size());
    for (const QString &id : m_selectedIds)
        ids.append(TorrentID::fromString(id));
    return ids;
}

// --- run state ---

void TransferController::start()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Start" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->start();
}

void TransferController::stop()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Stop" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->stop();
}

void TransferController::forceStart()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Force start" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->start(TorrentOperatingMode::Forced);
}

void TransferController::pauseSession()
{
    Session *const session = Session::instance();
    if (!session || session->isPaused())
        return;
    qCInfo(lcUi) << "Pause BitTorrent session";
    session->pause();
}

void TransferController::resumeSession()
{
    Session *const session = Session::instance();
    if (!session || !session->isPaused())
        return;
    qCInfo(lcUi) << "Resume BitTorrent session";
    session->resume();
}

// --- removal ---

void TransferController::deleteSelected(bool deleteFiles)
{
    Session *const session = Session::instance();
    if (!session)
        return;

    const QList<TorrentID> ids = selectedTorrentIDs();
    qCInfo(lcUi) << "Delete" << ids.size() << "torrent(s), deleteFiles=" << deleteFiles;
    const TorrentRemoveOption option = deleteFiles
            ? TorrentRemoveOption::RemoveContent
            : TorrentRemoveOption::KeepContent;
    for (const TorrentID &id : ids)
        session->removeTorrent(id, option);
}

// --- location / naming ---

void TransferController::setLocation(const QString &path)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set location of" << torrents.size() << "torrent(s) ->" << path;
    const Path newLocation {path};
    for (Torrent *const torrent : torrents)
    {
        torrent->setAutoTMMEnabled(false);
        torrent->setSavePath(newLocation);
    }
}

void TransferController::rename(const QString &newName)
{
    const QList<Torrent *> torrents = selectedTorrents();
    if (torrents.size() != 1)
    {
        qCWarning(lcUi) << "Rename requested with" << torrents.size() << "selected; ignoring";
        return;
    }
    QString collapsed = newName;
    collapsed.replace(u'\n', u' ').replace(u'\r', u' ');
    collapsed = collapsed.trimmed();
    if (collapsed.isEmpty())
        return;
    qCInfo(lcUi) << "Rename torrent ->" << collapsed;
    torrents.first()->setName(collapsed);
}

// --- category / tags ---

void TransferController::setCategory(const QString &category)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set category" << category << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setCategory(category);
}

void TransferController::addTags(const QStringList &tags)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Add tags" << tags << "to" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
    {
        for (const QString &tagStr : tags)
        {
            const Tag tag {tagStr};
            if (tag.isValid())
                torrent->addTag(tag);
        }
    }
}

void TransferController::removeTags(const QStringList &tags)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Remove tags" << tags << "from" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
    {
        for (const QString &tagStr : tags)
            torrent->removeTag(Tag(tagStr));
    }
}

void TransferController::removeAllTags()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Remove all tags from" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->clearTags();
}

// --- trackers / torrent files ---

int TransferController::removeTrackerFromAll(const QString &host)
{
    const QString trimmed = host.trimmed();
    if (trimmed.isEmpty())
        return 0;

    // The filter list groups trackers by host, so match on the URL's host
    // rather than on the whole URL: one host commonly serves several announce
    // URLs, and removing only the exact string would leave the rest behind and
    // the filter row still populated.
    int changed = 0;
    const QList<Torrent *> torrents = BitTorrent::Session::instance()->torrents();
    for (Torrent *const torrent : torrents)
    {
        QStringList doomed;
        const QList<BitTorrent::TrackerEntryStatus> trackers = torrent->trackers();
        for (const BitTorrent::TrackerEntryStatus &status : trackers)
        {
            if (QUrl(status.url).host() == trimmed)
                doomed.append(status.url);
        }

        if (doomed.isEmpty())
            continue;

        torrent->removeTrackers(doomed);
        ++changed;
    }

    qCInfo(lcUi) << "Removed tracker host" << trimmed << "from" << changed << "torrent(s)";
    return changed;
}

QString TransferController::trackersText() const
{
    const QList<Torrent *> torrents = selectedTorrents();
    if (torrents.isEmpty())
        return {};

    const QList<TrackerEntryStatus> firstTrackers = torrents.first()->trackers();
    QSet<QString> commonUrls;
    for (const TrackerEntryStatus &tracker : firstTrackers)
    {
        if (!tracker.url.isEmpty())
            commonUrls.insert(tracker.url);
    }

    for (qsizetype i = 1; i < torrents.size(); ++i)
    {
        QSet<QString> urls;
        for (const TrackerEntryStatus &tracker : torrents.at(i)->trackers())
        {
            if (!tracker.url.isEmpty())
                urls.insert(tracker.url);
        }
        commonUrls.intersect(urls);
    }

    // Preserve the first selected torrent's tiering and order while displaying
    // only URLs shared by every selected torrent.
    QMap<int, QStringList> urlsByTier;
    QSet<QString> emitted;
    for (const TrackerEntryStatus &tracker : firstTrackers)
    {
        if (tracker.url.isEmpty() || !commonUrls.contains(tracker.url)
                || emitted.contains(tracker.url))
        {
            continue;
        }
        urlsByTier[qMax(0, tracker.tier)].append(tracker.url);
        emitted.insert(tracker.url);
    }

    QStringList tiers;
    for (auto it = urlsByTier.cbegin(); it != urlsByTier.cend(); ++it)
        tiers.append(it.value().join(u'\n'));
    return tiers.join(QStringLiteral("\n\n"));
}

void TransferController::setTrackers(const QString &text)
{
    const QList<Torrent *> torrents = selectedTorrents();
    if (torrents.isEmpty())
        return;

    const QList<TrackerEntry> trackers = parseTrackerEntries(QStringView {text});
    qCInfo(lcUi) << "Replace trackers on" << torrents.size() << "torrent(s) with"
                 << trackers.size() << "entry(s)";
    for (Torrent *const torrent : torrents)
        torrent->replaceTrackers(trackers);
}

bool TransferController::exportTorrent(const QString &directory)
{
    const QList<Torrent *> torrents = selectedTorrents();
    const Path exportDirectory {directory.trimmed()};
    if (torrents.isEmpty() || exportDirectory.isEmpty() || !Utils::Fs::isDir(exportDirectory))
    {
        qCWarning(lcUi) << "Export torrent requested without a selection or valid directory";
        return false;
    }

    bool succeeded = true;
    QSet<QString> outputNames;
    for (const Torrent *const torrent : torrents)
    {
        QString baseName = Utils::Fs::toValidFileName(torrent->name());
        if (baseName.isEmpty())
            baseName = QStringLiteral("torrent");

        QString fileName;
        Path outputPath;
        for (int suffix = 1; ; ++suffix)
        {
            fileName = (suffix == 1)
                ? baseName + QStringLiteral(".torrent")
                : baseName + QStringLiteral(" (%1).torrent").arg(suffix);
            outputPath = exportDirectory / Path(fileName);
            if (!outputNames.contains(fileName) && !outputPath.exists())
                break;
        }
        outputNames.insert(fileName);

        const auto result = torrent->exportToFile(outputPath);
        if (!result)
        {
            qCWarning(lcUi) << "Failed to export torrent" << torrent->name()
                            << "to" << outputPath.data() << ':' << result.error();
            succeeded = false;
            continue;
        }

        qCInfo(lcUi) << "Exported torrent" << torrent->name() << "to" << outputPath.data();
    }
    return succeeded;
}

// --- queue ---

void TransferController::queueTop()
{
    Session *const session = Session::instance();
    if (!session)
        return;
    qCInfo(lcUi) << "Queue: move to top";
    session->topTorrentsQueuePos(selectedTorrentIDs());
}

void TransferController::queueUp()
{
    Session *const session = Session::instance();
    if (!session)
        return;
    qCInfo(lcUi) << "Queue: move up";
    session->increaseTorrentsQueuePos(selectedTorrentIDs());
}

void TransferController::queueDown()
{
    Session *const session = Session::instance();
    if (!session)
        return;
    qCInfo(lcUi) << "Queue: move down";
    session->decreaseTorrentsQueuePos(selectedTorrentIDs());
}

void TransferController::queueBottom()
{
    Session *const session = Session::instance();
    if (!session)
        return;
    qCInfo(lcUi) << "Queue: move to bottom";
    session->bottomTorrentsQueuePos(selectedTorrentIDs());
}

// --- maintenance ---

void TransferController::forceRecheck()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Force recheck" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->forceRecheck();
}

void TransferController::forceReannounce()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Force reannounce" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
    {
        torrent->forceReannounce();
        torrent->forceDHTAnnounce();
    }
}

// --- per-torrent toggles ---

void TransferController::setSuperSeeding(bool enabled)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set super seeding" << enabled << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
    {
        if (torrent->hasMetadata())
            torrent->setSuperSeeding(enabled);
    }
}

void TransferController::setSequential(bool enabled)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set sequential download" << enabled << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setSequentialDownload(enabled);
}

void TransferController::setFirstLastPiece(bool enabled)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set first/last piece priority" << enabled << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setFirstLastPiecePriority(enabled);
}

void TransferController::setAutoTMM(bool enabled)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set AutoTMM" << enabled << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setAutoTMMEnabled(enabled);
}

// --- limits / share limits ---

void TransferController::setDownloadLimit(int limitBytesPerSec)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set download limit" << limitBytesPerSec << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setDownloadLimit(limitBytesPerSec);
}

void TransferController::setUploadLimit(int limitBytesPerSec)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set upload limit" << limitBytesPerSec << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
        torrent->setUploadLimit(limitBytesPerSec);
}

void TransferController::setShareLimits(double ratioLimit, int seedingTimeMinutes, int inactiveSeedingTimeMinutes)
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Set share limits ratio=" << ratioLimit << "seedTime=" << seedingTimeMinutes
                 << "inactiveSeedTime=" << inactiveSeedingTimeMinutes << "on" << torrents.size() << "torrent(s)";
    for (Torrent *const torrent : torrents)
    {
        ShareLimits limits = torrent->shareLimits();
        limits.ratioLimit = static_cast<qreal>(ratioLimit);
        limits.seedingTimeLimit = seedingTimeMinutes;
        limits.inactiveSeedingTimeLimit = inactiveSeedingTimeMinutes;
        torrent->setShareLimits(limits);
    }
}

// --- clipboard ---

void TransferController::copyName()
{
    QStringList names;
    for (const Torrent *const torrent : selectedTorrents())
        names.append(torrent->name());
    qCInfo(lcUi) << "Copy name(s):" << names.size();
    if (QClipboard *const clipboard = QGuiApplication::clipboard())
        clipboard->setText(names.join(u'\n'));
}

void TransferController::copyHash()
{
    QStringList hashes;
    for (const Torrent *const torrent : selectedTorrents())
    {
        const InfoHash infoHash = torrent->infoHash();
        if (infoHash.v1().isValid())
            hashes.append(infoHash.v1().toString());
        else if (infoHash.v2().isValid())
            hashes.append(infoHash.v2().toString());
    }
    qCInfo(lcUi) << "Copy hash(es):" << hashes.size();
    if (QClipboard *const clipboard = QGuiApplication::clipboard())
        clipboard->setText(hashes.join(u'\n'));
}

void TransferController::copyMagnet()
{
    QStringList magnets;
    for (const Torrent *const torrent : selectedTorrents())
        magnets.append(torrent->createMagnetURI());
    qCInfo(lcUi) << "Copy magnet link(s):" << magnets.size();
    if (QClipboard *const clipboard = QGuiApplication::clipboard())
        clipboard->setText(magnets.join(u'\n'));
}

// --- shell / dialogs ---

void TransferController::openDestination()
{
    const QList<Torrent *> torrents = selectedTorrents();
    qCInfo(lcUi) << "Open destination for" << torrents.size() << "torrent(s)";
    for (const Torrent *const torrent : torrents)
    {
        const Path path = torrent->contentPath().isEmpty() ? torrent->savePath() : torrent->contentPath();
        const QString local = path.toString();
        if (!local.isEmpty())
            QDesktopServices::openUrl(QUrl::fromLocalFile(local));
    }
}

void TransferController::preview()
{
    if (m_selectedIds.isEmpty())
        return;
    qCInfo(lcUi) << "Preview requested for" << m_selectedIds.size() << "torrent(s)";
    emit previewRequested(m_selectedIds);
}

// --- drag & drop add ---

void TransferController::dropUrls(const QStringList &urls)
{
    qCInfo(lcUi) << "Drop received:" << urls.size() << "item(s)";

    QStringList torrentSources;
    QString firstOtherFile;
    for (const QString &raw : urls)
    {
        const QUrl url {raw};
        const QString candidate = url.isLocalFile() ? url.toLocalFile() : raw;

        if (Utils::Misc::isTorrentLink(candidate)
                || Path(candidate).hasExtension(u".torrent"))
        {
            torrentSources.append(candidate);
        }
        else if (firstOtherFile.isEmpty())
        {
            firstOtherFile = candidate;
        }
    }

    if (!torrentSources.isEmpty())
    {
        qCDebug(lcUi) << "Requesting add of" << torrentSources.size() << "dropped torrent source(s)";
        emit addTorrentsRequested(torrentSources);
    }
    else if (!firstOtherFile.isEmpty())
    {
        qCDebug(lcUi) << "Requesting Torrent Creator for dropped file" << firstOtherFile;
        emit createTorrentRequested(firstOtherFile);
    }
}
