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

#include "torrentimpl.h"

#include <algorithm>
#include <limits>
#include <memory>

#include <libtorrent/address.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/storage_defs.hpp>
#include <libtorrent/time.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <QtSystemDetection>
#include <QByteArray>
#include <QDebug>
#include <QFuture>
#include <QPromise>
#include <QSet>
#include <QStringList>
#include <QUrl>

#include "base/global.h"
#include "base/logging.h"
#include "base/preferences.h"
#include "base/settingsstorage.h"
#include "base/types.h"
#include "base/utils/fs.h"
#include "base/utils/io.h"
#include "base/utils/string.h"
#include "common.h"
#include "downloadpriority.h"
#include "loadtorrentparams.h"
#include "ltqbitarray.h"
#include "lttypecast.h"
#include "peeraddress.h"
#include "peerinfo.h"
#include "sessionimpl.h"
#include "torrentdescriptor.h"
#include "trackerentry.h"

using namespace BitTorrent;
using namespace Qt::Literals::StringLiterals;

namespace
{
    lt::announce_entry makeNativeAnnounceEntry(const QString &url, const int tier)
    {
        lt::announce_entry entry {url.toStdString()};
        entry.tier = tier;
        return entry;
    }

    QString toString(const lt::tcp::endpoint &ltTCPEndpoint)
    {
        QString ret;
        try
        {
            ret = QString::fromStdString((std::stringstream() << ltTCPEndpoint).str());
        }
        catch (const std::exception &) {}
        return ret;
    }

    void updateTrackerEntryStatus(TrackerEntryStatus &trackerEntryStatus, const lt::announce_entry &nativeEntry
            , const QSet<int> &btProtocols, const QHash<lt::tcp::endpoint, QMap<int, int>> &updateInfo)
    {
        Q_ASSERT(trackerEntryStatus.url == QString::fromStdString(nativeEntry.url));

        // TODO(engine): fully translate per-endpoint libtorrent announce state into
        // our TrackerEndpointStatus map. The common single-endpoint path is wired below.
        trackerEntryStatus.tier = nativeEntry.tier;
    }

    // This is an imitation of the limit normalization performed by libtorrent itself.
    // We need to perform it to keep cached values in line with the ones used by libtorrent.
    int cleanLimitValue(const int value)
    {
        return ((value < 0) || (value == std::numeric_limits<int>::max())) ? 0 : value;
    }

    // Seed the native status snapshot from the add_torrent_params so that the torrent
    // exposes sane values before libtorrent delivers the first status update alert.
    void initializeStatus(lt::torrent_status &status, const lt::add_torrent_params &params)
    {
        status.flags = params.flags;
        status.save_path = params.save_path;
        status.added_time = params.added_time;
        status.completed_time = params.completed_time;
        status.last_seen_complete = params.last_seen_complete;
        status.all_time_upload = params.total_uploaded;
        status.all_time_download = params.total_downloaded;
    }

    // Torrent is paused internally by libtorrent (as opposed to being user-stopped).
    bool isPaused(const lt::torrent_status &nativeStatus)
    {
        return static_cast<bool>(nativeStatus.flags & lt::torrent_flags::paused);
    }

    // Torrent is "queued" when libtorrent auto-manages it but currently keeps it paused.
    bool isQueuedInternal(const lt::torrent_status &nativeStatus)
    {
        return static_cast<bool>(nativeStatus.flags & lt::torrent_flags::paused);
    }
}

// TorrentImpl

TorrentImpl::TorrentImpl(SessionImpl *session, const lt::torrent_handle &nativeHandle, LoadTorrentParams params)
    : Torrent(session)
    , m_session {session}
    , m_nativeHandle {nativeHandle}
    , m_infoHash {m_nativeHandle.info_hashes()}
    , m_id {params.id.isValid() ? params.id : m_infoHash.toTorrentID()}
    , m_name {params.name}
    , m_savePath {params.savePath}
    , m_downloadPath {params.downloadPath}
    , m_category {params.category}
    , m_tags {params.tags}
    , m_comment {params.comment}
    , m_commentIsCustom {params.commentIsCustom}
    , m_shareLimits {params.shareLimits}
    , m_operatingMode {params.operatingMode}
    , m_contentLayout {params.contentLayout}
    , m_hasFinishedStatus {params.hasFinishedStatus}
    , m_hasFirstLastPiecePriority {params.firstLastPiecePriority}
    , m_useAutoTMM {params.useAutoTMM}
    , m_isStopped {params.stopped}
    , m_stopCondition {params.stopCondition}
    , m_sslParams {params.sslParameters}
    , m_ltAddTorrentParams {params.ltAddTorrentParams}
{
    qCInfo(lcTorrent) << "Creating TorrentImpl for" << m_name << '(' << m_infoHash.toString() << ')';

    if (m_ltAddTorrentParams.ti)
    {
        // Torrent was added with metadata
        m_torrentInfo = TorrentInfo(*m_ltAddTorrentParams.ti);
        rebuildFileStateFromNative();
        m_creationDate = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.ti->creation_date());
        m_creator = QString::fromStdString(m_ltAddTorrentParams.ti->creator());
        if (!m_commentIsCustom)
            m_comment = QString::fromStdString(m_ltAddTorrentParams.ti->comment());
    }

    const auto now = QDateTime::currentDateTime();
    m_addedTime = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.added_time);
    if (!m_addedTime.isValid())
        m_addedTime = now;
    m_completedTime = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.completed_time);
    m_lastSeenComplete = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.last_seen_complete);

    m_downloadLimit = cleanLimitValue(m_ltAddTorrentParams.download_limit);
    m_uploadLimit = cleanLimitValue(m_ltAddTorrentParams.upload_limit);

    initializeStatus(m_nativeStatus, m_ltAddTorrentParams);
    updateState();

    if (hasMetadata())
        updateProgress();
}

TorrentImpl::~TorrentImpl()
{
    qCDebug(lcTorrent) << "Destroying TorrentImpl for" << m_name;
}

bool TorrentImpl::isValid() const
{
    return m_nativeHandle.is_valid();
}

Session *TorrentImpl::session() const
{
    return m_session;
}

TorrentID TorrentImpl::id() const
{
    return m_id;
}

InfoHash TorrentImpl::infoHash() const
{
    return m_infoHash;
}

QString TorrentImpl::name() const
{
    if (!m_name.isEmpty())
        return m_name;

    if (hasMetadata())
        return m_torrentInfo.name();

    // Metadata isn't available (e.g. a magnet still fetching it, or resume
    // data that was checkpointed without the info dict) -- libtorrent still
    // carries a display-name hint on add_torrent_params in that case.
    const QString hintName = QString::fromStdString(m_ltAddTorrentParams.name);
    if (!hintName.isEmpty())
        return hintName;

    const QString commonName = m_infoHash.toTorrentID().toString();
    return commonName;
}

QDateTime TorrentImpl::creationDate() const
{
    return m_creationDate;
}

QString TorrentImpl::creator() const
{
    return m_creator;
}

QString TorrentImpl::comment() const
{
    return m_comment;
}

void TorrentImpl::setComment(const QString &comment)
{
    if ((m_comment == comment) && m_commentIsCustom)
        return;

    m_comment = comment;
    m_commentIsCustom = true;
    deferredRequestResumeData();
}

bool TorrentImpl::isPrivate() const
{
    return hasMetadata() && m_torrentInfo.isPrivate();
}

qlonglong TorrentImpl::totalSize() const
{
    return hasMetadata() ? m_torrentInfo.totalSize() : -1;
}

qlonglong TorrentImpl::wantedSize() const
{
    return m_nativeStatus.total_wanted;
}

qlonglong TorrentImpl::completedSize() const
{
    return m_nativeStatus.total_wanted_done;
}

qlonglong TorrentImpl::pieceLength() const
{
    return hasMetadata() ? m_torrentInfo.pieceLength() : -1;
}

qlonglong TorrentImpl::wastedSize() const
{
    return (m_nativeStatus.total_failed_bytes + m_nativeStatus.total_redundant_bytes);
}

QString TorrentImpl::currentTracker() const
{
    return QString::fromStdString(m_nativeStatus.current_tracker);
}

bool TorrentImpl::isAutoTMMEnabled() const
{
    return m_useAutoTMM;
}

void TorrentImpl::setAutoTMMEnabled(const bool enabled)
{
    if (m_useAutoTMM == enabled)
        return;

    qCDebug(lcTorrent) << "Setting AutoTMM for" << name() << "to" << enabled;
    m_useAutoTMM = enabled;
    deferredRequestResumeData();
    m_session->handleTorrentSavingModeChanged(this);

    if (m_useAutoTMM)
    {
        adjustStorageLocation();
        manageActualFilePaths();
    }
}

Path TorrentImpl::savePath() const
{
    return isAutoTMMEnabled() ? m_session->categorySavePath(category()) : m_savePath;
}

void TorrentImpl::setSavePath(const Path &path)
{
    Q_ASSERT(!isAutoTMMEnabled());

    const Path resolvedPath = (path.isAbsolute() ? path : (m_session->savePath() / path));
    if (resolvedPath == savePath())
        return;

    qCDebug(lcTorrent) << "Setting save path of" << name() << "to" << resolvedPath.data();
    m_savePath = resolvedPath;
    m_session->handleTorrentNeedSaveResumeData(this);
    m_session->handleTorrentSavePathChanged(this);
    deferredRequestResumeData();

    adjustStorageLocation();
    manageActualFilePaths();
}

Path TorrentImpl::downloadPath() const
{
    return isAutoTMMEnabled() ? m_session->categoryDownloadPath(category()) : m_downloadPath;
}

void TorrentImpl::setDownloadPath(const Path &path)
{
    Q_ASSERT(!isAutoTMMEnabled());

    const Path resolvedPath = (path.isEmpty() || path.isAbsolute()) ? path : (m_session->downloadPath() / path);
    if (resolvedPath == m_downloadPath)
        return;

    qCDebug(lcTorrent) << "Setting download path of" << name() << "to" << resolvedPath.data();
    m_downloadPath = resolvedPath;
    deferredRequestResumeData();

    adjustStorageLocation();
    manageActualFilePaths();
}

Path TorrentImpl::actualStorageLocation() const
{
    return Path(m_nativeStatus.save_path);
}

Path TorrentImpl::rootPath() const
{
    if (!hasMetadata())
        return {};

    const Path relativeRootPath = Path::findRootFolder(filePaths());
    if (relativeRootPath.isEmpty())
        return {};

    return actualStorageLocation() / relativeRootPath;
}

Path TorrentImpl::contentPath() const
{
    if (!hasMetadata())
        return {};

    if (m_torrentInfo.filesCount() == 1)
        return actualStorageLocation() / actualFilePath(0);

    const Path rootPath = this->rootPath();
    return rootPath.isEmpty() ? actualStorageLocation() : rootPath;
}

QString TorrentImpl::category() const
{
    return m_category;
}

bool TorrentImpl::belongsToCategory(const QString &category) const
{
    if (m_category.isEmpty())
        return category.isEmpty();

    if (m_category == category)
        return true;

    return SettingsStorage::instance()->loadValue(u"BitTorrent/Session/SubcategoriesEnabled"_s, false)
            && (m_category.startsWith(category + u'/'));
}

bool TorrentImpl::setCategory(const QString &category)
{
    if (m_category == category)
        return true;

    if (!category.isEmpty() && !m_session->categories().contains(category))
    {
        qCWarning(lcTorrent) << "Cannot set unknown category" << category << "on torrent" << name();
        return false;
    }

    const QString oldCategory = m_category;
    m_category = category;
    deferredRequestResumeData();
    m_session->handleTorrentCategoryChanged(this, oldCategory);
    qCInfo(lcTorrent) << "Category of" << name() << "changed:" << oldCategory << "->" << category;

    if (m_useAutoTMM)
    {
        adjustStorageLocation();
        manageActualFilePaths();
    }

    return true;
}

TagSet TorrentImpl::tags() const
{
    return m_tags;
}

bool TorrentImpl::hasTag(const Tag &tag) const
{
    return m_tags.contains(tag);
}

bool TorrentImpl::addTag(const Tag &tag)
{
    if (hasTag(tag))
        return false;

    if (!m_session->hasTag(tag) && !m_session->addTag(tag))
        return false;

    m_tags.insert(tag);
    deferredRequestResumeData();
    m_session->handleTorrentTagAdded(this, tag);
    qCDebug(lcTorrent) << "Tag" << tag.toString() << "added to" << name();
    return true;
}

bool TorrentImpl::removeTag(const Tag &tag)
{
    if (m_tags.remove(tag))
    {
        deferredRequestResumeData();
        m_session->handleTorrentTagRemoved(this, tag);
        qCDebug(lcTorrent) << "Tag" << tag.toString() << "removed from" << name();
        return true;
    }
    return false;
}

void TorrentImpl::clearTags()
{
    const TagSet tags = m_tags;
    for (const Tag &tag : tags)
        removeTag(tag);
}

int TorrentImpl::filesCount() const
{
    return m_torrentInfo.filesCount();
}

int TorrentImpl::piecesCount() const
{
    return m_torrentInfo.piecesCount();
}

int TorrentImpl::piecesHave() const
{
    return m_nativeStatus.num_pieces;
}

qreal TorrentImpl::progress() const
{
    if (isChecking())
        return m_nativeStatus.progress;

    if (m_nativeStatus.total_wanted == 0)
        return isPaused(m_nativeStatus) ? 0 : 1;

    if (m_nativeStatus.total_wanted_done == m_nativeStatus.total_wanted)
        return 1;

    const qreal progress = static_cast<qreal>(m_nativeStatus.total_wanted_done) / m_nativeStatus.total_wanted;
    Q_ASSERT((progress >= 0.f) && (progress <= 1.f));
    return progress;
}

QDateTime TorrentImpl::addedTime() const
{
    return m_addedTime;
}

QDateTime TorrentImpl::completedTime() const
{
    return m_completedTime;
}

QDateTime TorrentImpl::lastSeenComplete() const
{
    return m_lastSeenComplete;
}

qlonglong TorrentImpl::activeTime() const
{
    return lt::total_seconds(m_nativeStatus.active_duration);
}

qlonglong TorrentImpl::finishedTime() const
{
    return lt::total_seconds(m_nativeStatus.finished_duration);
}

qlonglong TorrentImpl::timeSinceUpload() const
{
    if (m_nativeStatus.last_upload.time_since_epoch().count() == 0)
        return -1;
    return lt::total_seconds(lt::clock_type::now() - m_nativeStatus.last_upload);
}

qlonglong TorrentImpl::timeSinceDownload() const
{
    if (m_nativeStatus.last_download.time_since_epoch().count() == 0)
        return -1;
    return lt::total_seconds(lt::clock_type::now() - m_nativeStatus.last_download);
}

qlonglong TorrentImpl::timeSinceActivity() const
{
    const qlonglong upTime = timeSinceUpload();
    const qlonglong downTime = timeSinceDownload();
    return ((upTime < 0) != (downTime < 0))
            ? std::max(upTime, downTime)
            : std::min(upTime, downTime);
}

const ShareLimits &TorrentImpl::shareLimits() const
{
    return m_shareLimits;
}

void TorrentImpl::setShareLimits(ShareLimits shareLimits)
{
    if (m_shareLimits == shareLimits)
        return;

    qCDebug(lcTorrent) << "Setting share limits for" << name();
    m_shareLimits = shareLimits;
    deferredRequestResumeData();
    m_session->handleTorrentShareLimitChanged(this);
}

ShareLimits TorrentImpl::effectiveShareLimits() const
{
    ShareLimits result = m_shareLimits;
    const ShareLimits sessionLimits = m_session->shareLimits();
    const ShareLimits categoryLimits = m_session->categoryShareLimits(m_category);

    const auto resolveRatio = [&](const qreal value) -> qreal
    {
        if (value != DEFAULT_RATIO_LIMIT)
            return value;
        if (categoryLimits.ratioLimit != DEFAULT_RATIO_LIMIT)
            return categoryLimits.ratioLimit;
        return sessionLimits.ratioLimit;
    };
    const auto resolveSeedingTime = [&](const int value, const int catValue, const int sesValue) -> int
    {
        if (value != DEFAULT_SEEDING_TIME_LIMIT)
            return value;
        if (catValue != DEFAULT_SEEDING_TIME_LIMIT)
            return catValue;
        return sesValue;
    };

    result.ratioLimit = resolveRatio(m_shareLimits.ratioLimit);
    result.seedingTimeLimit = resolveSeedingTime(m_shareLimits.seedingTimeLimit
            , categoryLimits.seedingTimeLimit, sessionLimits.seedingTimeLimit);
    result.inactiveSeedingTimeLimit = resolveSeedingTime(m_shareLimits.inactiveSeedingTimeLimit
            , categoryLimits.inactiveSeedingTimeLimit, sessionLimits.inactiveSeedingTimeLimit);
    return result;
}

Path TorrentImpl::filePath(const int index) const
{
    return ((index >= 0) && (index < m_filePaths.size()))
        ? m_filePaths.at(index) : Path();
}

Path TorrentImpl::actualFilePath(const int index) const
{
    if ((index < 0) || (index >= m_filePaths.size()))
        return {};

    return makeActualPath(index, m_filePaths.at(index));
}

qlonglong TorrentImpl::fileSize(const int index) const
{
    return m_torrentInfo.fileSize(index);
}

PathList TorrentImpl::filePaths() const
{
    return m_filePaths;
}

PathList TorrentImpl::actualFilePaths() const
{
    PathList result;
    result.reserve(m_filePaths.size());
    for (int i = 0; i < m_filePaths.size(); ++i)
        result.append(actualFilePath(i));
    return result;
}

QList<DownloadPriority> TorrentImpl::filePriorities() const
{
    return m_filePriorities;
}

TorrentInfo TorrentImpl::info() const
{
    return m_torrentInfo;
}

bool TorrentImpl::isFinished() const
{
    return m_hasFinishedStatus;
}

bool TorrentImpl::isStopped() const
{
    return m_isStopped;
}

bool TorrentImpl::isQueued() const
{
    if (!m_session->isQueueingSystemEnabled())
        return false;

    return (m_nativeStatus.flags & lt::torrent_flags::auto_managed)
            && (m_nativeStatus.state == lt::torrent_status::checking_files
                || m_nativeStatus.state == lt::torrent_status::downloading
                || m_nativeStatus.state == lt::torrent_status::seeding)
            && isQueuedInternal(m_nativeStatus);
}

bool TorrentImpl::isForced() const
{
    return !isStopped() && (m_operatingMode == TorrentOperatingMode::Forced);
}

bool TorrentImpl::isChecking() const
{
    return ((m_nativeStatus.state == lt::torrent_status::checking_files)
            || (m_nativeStatus.state == lt::torrent_status::checking_resume_data));
}

bool TorrentImpl::isDownloading() const
{
    switch (m_state)
    {
    case TorrentState::Downloading:
    case TorrentState::DownloadingMetadata:
    case TorrentState::ForcedDownloadingMetadata:
    case TorrentState::StalledDownloading:
    case TorrentState::CheckingDownloading:
    case TorrentState::QueuedDownloading:
    case TorrentState::ForcedDownloading:
        return true;
    default:
        return false;
    }
}

bool TorrentImpl::isMoving() const
{
    return m_storageIsMoving;
}

bool TorrentImpl::isUploading() const
{
    switch (m_state)
    {
    case TorrentState::Uploading:
    case TorrentState::StalledUploading:
    case TorrentState::CheckingUploading:
    case TorrentState::QueuedUploading:
    case TorrentState::ForcedUploading:
        return true;
    default:
        return false;
    }
}

bool TorrentImpl::isCompleted() const
{
    return m_hasFinishedStatus || (m_nativeStatus.state == lt::torrent_status::seeding);
}

bool TorrentImpl::isActive() const
{
    if (m_state == TorrentState::StalledDownloading)
        return (uploadPayloadRate() > 0);

    switch (m_state)
    {
    case TorrentState::DownloadingMetadata:
    case TorrentState::ForcedDownloadingMetadata:
    case TorrentState::Downloading:
    case TorrentState::ForcedDownloading:
    case TorrentState::Uploading:
    case TorrentState::ForcedUploading:
    case TorrentState::Moving:
        return true;
    default:
        return false;
    }
}

bool TorrentImpl::isInactive() const
{
    return !isActive();
}

bool TorrentImpl::isErrored() const
{
    return (m_state == TorrentState::MissingFiles) || (m_state == TorrentState::Error);
}

bool TorrentImpl::isSequentialDownload() const
{
    return static_cast<bool>(m_nativeStatus.flags & lt::torrent_flags::sequential_download);
}

bool TorrentImpl::hasFirstLastPiecePriority() const
{
    return m_hasFirstLastPiecePriority;
}

TorrentState TorrentImpl::state() const
{
    return m_state;
}

bool TorrentImpl::hasMetadata() const
{
    return m_torrentInfo.isValid();
}

bool TorrentImpl::hasMissingFiles() const
{
    return m_hasMissingFiles;
}

bool TorrentImpl::hasError() const
{
    return static_cast<bool>(m_nativeStatus.errc);
}

int TorrentImpl::queuePosition() const
{
    return static_cast<int>(m_nativeStatus.queue_position);
}

QList<TrackerEntryStatus> TorrentImpl::trackers() const
{
    return m_trackerEntryStatuses;
}

QList<QUrl> TorrentImpl::urlSeeds() const
{
    return m_urlSeeds;
}

QString TorrentImpl::error() const
{
    if (m_nativeStatus.errc)
        return QString::fromLocal8Bit(m_nativeStatus.errc.message().c_str());

    if (m_lastFileError.error)
    {
        return tr("Couldn't write to file. Reason: \"%1\".")
                .arg(QString::fromLocal8Bit(m_lastFileError.error.message().c_str()));
    }

    return {};
}

qlonglong TorrentImpl::totalDownload() const
{
    return m_nativeStatus.all_time_download;
}

qlonglong TorrentImpl::totalUpload() const
{
    return m_nativeStatus.all_time_upload;
}

qlonglong TorrentImpl::eta() const
{
    if (isStopped())
        return MAX_ETA;

    const SpeedSampleAvg speedAverage = m_payloadRateMonitor.average();

    if (isFinished())
    {
        const ShareLimits limits = effectiveShareLimits();
        if ((limits.ratioLimit < 0) && (limits.seedingTimeLimit < 0) && (limits.inactiveSeedingTimeLimit < 0))
            return MAX_ETA;

        // TODO(engine): estimate ETA against ratio / seeding time limits.
        return MAX_ETA;
    }

    if (!isDownloading())
        return MAX_ETA;

    const qlonglong remainingBytes = wantedSize() - completedSize();
    if (speedAverage.download == 0)
        return MAX_ETA;

    return (remainingBytes / speedAverage.download);
}

QList<qreal> TorrentImpl::filesProgress() const
{
    if (!hasMetadata())
        return {};

    const int count = filesCount();
    QList<qreal> result;
    result.reserve(count);

    if (m_filesProgress.size() != count)
        return QList<qreal>(count, 0);

    for (int i = 0; i < count; ++i)
    {
        const qlonglong size = fileSize(i);
        if (size <= 0)
            result << 1;
        else
            result << (std::min<qreal>(m_filesProgress[i], size) / size);
    }

    return result;
}

int TorrentImpl::seedsCount() const
{
    return m_nativeStatus.num_seeds;
}

int TorrentImpl::peersCount() const
{
    return m_nativeStatus.num_peers;
}

int TorrentImpl::leechsCount() const
{
    return (m_nativeStatus.num_peers - m_nativeStatus.num_seeds);
}

int TorrentImpl::totalSeedsCount() const
{
    return (m_nativeStatus.num_complete > 0) ? m_nativeStatus.num_complete : m_nativeStatus.list_seeds;
}

int TorrentImpl::totalPeersCount() const
{
    const int peers = m_nativeStatus.num_complete + m_nativeStatus.num_incomplete;
    return (peers > 0) ? peers : m_nativeStatus.list_peers;
}

int TorrentImpl::totalLeechersCount() const
{
    return (m_nativeStatus.num_incomplete > 0) ? m_nativeStatus.num_incomplete : (m_nativeStatus.list_peers - m_nativeStatus.list_seeds);
}

int TorrentImpl::downloadLimit() const
{
    return m_downloadLimit;
}

int TorrentImpl::uploadLimit() const
{
    return m_uploadLimit;
}

bool TorrentImpl::superSeeding() const
{
    return static_cast<bool>(m_nativeStatus.flags & lt::torrent_flags::super_seeding);
}

bool TorrentImpl::isDHTDisabled() const
{
    return static_cast<bool>(m_nativeStatus.flags & lt::torrent_flags::disable_dht);
}

bool TorrentImpl::isPEXDisabled() const
{
    return static_cast<bool>(m_nativeStatus.flags & lt::torrent_flags::disable_pex);
}

bool TorrentImpl::isLSDDisabled() const
{
    return static_cast<bool>(m_nativeStatus.flags & lt::torrent_flags::disable_lsd);
}

QBitArray TorrentImpl::pieces() const
{
    return m_pieces;
}

qreal TorrentImpl::distributedCopies() const
{
    return m_nativeStatus.distributed_copies;
}

qreal TorrentImpl::realRatio() const
{
    const int64_t upload = m_nativeStatus.all_time_upload;
    const int64_t download = m_nativeStatus.all_time_download;

    if (download == 0)
        return (upload == 0) ? 0 : MAX_RATIO;

    const qreal ratio = static_cast<qreal>(upload) / download;
    Q_ASSERT(ratio >= 0);
    return (ratio > MAX_RATIO) ? MAX_RATIO : ratio;
}

qreal TorrentImpl::popularity() const
{
    const qlonglong seedingTime = finishedTime();
    if (seedingTime == 0)
        return 0;

    return realRatio() / (static_cast<qreal>(seedingTime) / 86400);
}

int TorrentImpl::uploadPayloadRate() const
{
    return m_nativeStatus.upload_payload_rate;
}

int TorrentImpl::downloadPayloadRate() const
{
    return m_nativeStatus.download_payload_rate;
}

qlonglong TorrentImpl::totalPayloadUpload() const
{
    return m_nativeStatus.total_payload_upload;
}

qlonglong TorrentImpl::totalPayloadDownload() const
{
    return m_nativeStatus.total_payload_download;
}

int TorrentImpl::connectionsCount() const
{
    return m_nativeStatus.num_connections;
}

int TorrentImpl::connectionsLimit() const
{
    return m_nativeStatus.connections_limit;
}

qlonglong TorrentImpl::nextAnnounce() const
{
    return lt::total_seconds(m_nativeStatus.next_announce);
}

TorrentAnnounceStatus TorrentImpl::announceStatus() const
{
    // TODO(engine): compute a coalesced announce status from the tracker endpoints.
    if (m_announceStatus)
        return *m_announceStatus;
    return {};
}

// --- Actions ---

void TorrentImpl::setName(const QString &name)
{
    if (m_name == name)
        return;

    qCDebug(lcTorrent) << "Renaming torrent" << m_name << "->" << name;
    const QString oldName = m_name;
    m_name = name;
    deferredRequestResumeData();
    m_session->handleTorrentNameChanged(this, oldName);
}

void TorrentImpl::setSequentialDownload(const bool enable)
{
    if (enable == isSequentialDownload())
        return;

    qCDebug(lcTorrent) << "Setting sequential download for" << name() << "to" << enable;
    if (enable)
        m_nativeHandle.set_flags(lt::torrent_flags::sequential_download);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::sequential_download);

    deferredRequestResumeData();
}

void TorrentImpl::setFirstLastPiecePriority(const bool enabled)
{
    if (m_hasFirstLastPiecePriority == enabled)
        return;

    qCDebug(lcTorrent) << "Setting first/last piece priority for" << name() << "to" << enabled;
    m_hasFirstLastPiecePriority = enabled;
    if (hasMetadata())
        applyFirstLastPiecePriority(enabled);

    deferredRequestResumeData();
}

void TorrentImpl::applyFirstLastPiecePriority(const bool enabled)
{
    // Download first and last pieces first for every file in the torrent
    auto piecePriorities = m_nativeHandle.get_piece_priorities();

    for (int index = 0; index < filesCount(); ++index)
    {
        const DownloadPriority filePrio = m_filePriorities.value(index, DownloadPriority::Normal);
        if (filePrio <= DownloadPriority::Ignored)
            continue;

        const TorrentInfo::PieceRange extremities = m_torrentInfo.filePieces(index);
        const lt::download_priority_t piecePrio = enabled
                ? LT::toNative(DownloadPriority::Maximum) : LT::toNative(filePrio);
        piecePriorities[extremities.first()] = piecePrio;
        piecePriorities[extremities.last()] = piecePrio;
    }

    m_nativeHandle.prioritize_pieces(piecePriorities);
}

void TorrentImpl::stop()
{
    if (m_isStopped)
        return;

    qCInfo(lcTorrent) << "Stopping torrent" << name();
    m_stopCondition = StopCondition::None;
    m_isStopped = true;
    deferredRequestResumeData();

    if (m_maintenanceJob == MaintenanceJob::None)
    {
        setAutoManaged(false);
        m_nativeHandle.pause();
    }

    m_session->handleTorrentStopped(this);
}

void TorrentImpl::start(const TorrentOperatingMode mode)
{
    qCInfo(lcTorrent) << "Starting torrent" << name() << "in mode" << static_cast<int>(mode);
    m_operatingMode = mode;

    if (hasError())
    {
        m_nativeHandle.clear_error();
        m_nativeHandle.unset_flags(lt::torrent_flags::auto_managed);
        m_nativeHandle.resume();
    }

    if (m_isStopped)
    {
        m_isStopped = false;
        m_stopCondition = StopCondition::None;
        deferredRequestResumeData();
    }

    if (m_hasMissingFiles)
    {
        m_hasMissingFiles = false;
        m_nativeHandle.clear_error();
        m_nativeHandle.force_recheck();
    }

    setAutoManaged(mode == TorrentOperatingMode::AutoManaged);
    if (mode == TorrentOperatingMode::Forced)
        m_nativeHandle.resume();

    m_session->handleTorrentStarted(this);
}

void TorrentImpl::forceReannounce(const int index)
{
    qCDebug(lcTorrent) << "Forcing reannounce for" << name() << "tracker index" << index;
    m_nativeHandle.force_reannounce(0, index);
}

void TorrentImpl::forceDHTAnnounce()
{
    qCDebug(lcTorrent) << "Forcing DHT announce for" << name();
    m_nativeHandle.force_dht_announce();
}

void TorrentImpl::forceRecheck()
{
    if (!hasMetadata())
        return;

    qCInfo(lcTorrent) << "Force rechecking torrent" << name();
    m_nativeHandle.force_recheck();
    m_unchecked = false;

    if (m_isStopped)
    {
        m_nativeHandle.unset_flags(lt::torrent_flags::auto_managed);
        m_nativeHandle.resume();
        m_isStopped = false;
        m_session->handleTorrentStarted(this);
        deferredRequestResumeData();
    }
}

void TorrentImpl::renameFile(const int index, const Path &path)
{
    qCDebug(lcTorrent) << "Renaming file" << index << "of" << name() << "to" << path.data();
    doRenameFile(index, path);
}

void TorrentImpl::doRenameFile(const int index, const Path &path, const int folderRenameJobID)
{
    Q_ASSERT((index >= 0) && (index < filesCount()));
    if ((index < 0) || (index >= filesCount()))
        return;

    const lt::file_index_t nativeIndex = m_torrentInfo.nativeIndexes().at(index);
    m_renamingFiles[nativeIndex].enqueue({index, folderRenameJobID});
    const Path actualPath = makeActualPath(index, path);
    m_nativeHandle.rename_file(nativeIndex, actualPath.toString().toStdString());
}

void TorrentImpl::doRenameFolder(const Path &oldFolderPath, const Path &newFolderPath)
{
    // Rename every child through libtorrent and keep one acknowledgement job so
    // the completion signal fires only after all child requests have settled.
    const int jobID = m_nextFolderRenameJobID++;
    FolderRenameInfo jobInfo;
    jobInfo.folderRenameJobID = jobID;
    jobInfo.oldFolderPath = oldFolderPath;
    jobInfo.newFolderPath = newFolderPath;

    bool anyRenamed = false;
    for (int i = 0; i < filesCount(); ++i)
    {
        const Path filePath = this->filePath(i);
        if (!filePath.hasAncestor(oldFolderPath))
            continue;

        const Path newFilePath = newFolderPath / oldFolderPath.relativePathOf(filePath);

        jobInfo.renamedFiles.insert(i, filePath);
        jobInfo.pendingFileIndexes.insert(i);
        doRenameFile(i, newFilePath, jobID);
        anyRenamed = true;
    }

    if (anyRenamed)
        m_renamingFolders.enqueue(jobInfo);
    else
        m_session->handleTorrentContentFolderRenamed(this, newFolderPath, oldFolderPath, {});
}

void TorrentImpl::prioritizeFiles(const QList<DownloadPriority> &priorities)
{
    if (!hasMetadata())
        return;

    Q_ASSERT(priorities.size() == filesCount());
    if (priorities.size() != filesCount())
        return;

    qCDebug(lcTorrent) << "Prioritizing files for" << name();

    // Reset the priorities that already match
    const QList<DownloadPriority> oldPriorities = filePriorities();
    if (oldPriorities == priorities)
        return;

    std::vector<lt::download_priority_t> nativePriorities = m_nativeHandle.get_file_priorities();
    const QList<lt::file_index_t> nativeIndexes = m_torrentInfo.nativeIndexes();
    for (int i = 0; i < priorities.size(); ++i)
        nativePriorities[LT::toUnderlyingType(nativeIndexes[i])] = LT::toNative(priorities[i]);

    m_nativeHandle.prioritize_files(nativePriorities);
    m_filePriorities = priorities;

    if (m_hasFirstLastPiecePriority)
        applyFirstLastPiecePriority(true);

    deferredRequestResumeData();
    manageActualFilePaths();
}

void TorrentImpl::setUploadLimit(const int limit)
{
    const int cleanValue = cleanLimitValue(limit);
    if (cleanValue == m_uploadLimit)
        return;

    qCDebug(lcTorrent) << "Setting upload limit of" << name() << "to" << cleanValue;
    m_uploadLimit = cleanValue;
    m_nativeHandle.set_upload_limit(cleanValue);
    deferredRequestResumeData();
}

void TorrentImpl::setDownloadLimit(const int limit)
{
    const int cleanValue = cleanLimitValue(limit);
    if (cleanValue == m_downloadLimit)
        return;

    qCDebug(lcTorrent) << "Setting download limit of" << name() << "to" << cleanValue;
    m_downloadLimit = cleanValue;
    m_nativeHandle.set_download_limit(cleanValue);
    deferredRequestResumeData();
}

void TorrentImpl::setSuperSeeding(const bool enable)
{
    if (enable == superSeeding())
        return;

    qCDebug(lcTorrent) << "Setting super seeding for" << name() << "to" << enable;
    if (enable)
        m_nativeHandle.set_flags(lt::torrent_flags::super_seeding);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::super_seeding);

    deferredRequestResumeData();
}

void TorrentImpl::setDHTDisabled(const bool disable)
{
    if (disable == isDHTDisabled())
        return;

    if (disable)
        m_nativeHandle.set_flags(lt::torrent_flags::disable_dht);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::disable_dht);

    deferredRequestResumeData();
}

void TorrentImpl::setPEXDisabled(const bool disable)
{
    if (disable == isPEXDisabled())
        return;

    if (disable)
        m_nativeHandle.set_flags(lt::torrent_flags::disable_pex);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::disable_pex);

    deferredRequestResumeData();
}

void TorrentImpl::setLSDDisabled(const bool disable)
{
    if (disable == isLSDDisabled())
        return;

    if (disable)
        m_nativeHandle.set_flags(lt::torrent_flags::disable_lsd);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::disable_lsd);

    deferredRequestResumeData();
}

void TorrentImpl::flushCache() const
{
    m_nativeHandle.flush_cache();
}

void TorrentImpl::addTrackers(QList<TrackerEntry> trackers)
{
    QSet<TrackerEntry> currentTrackers;
    for (const lt::announce_entry &entry : m_nativeHandle.trackers())
        currentTrackers.insert({QString::fromStdString(entry.url), entry.tier});

    QList<TrackerEntry> newTrackers;
    newTrackers.reserve(trackers.size());
    for (TrackerEntry &tracker : trackers)
    {
        if (!currentTrackers.contains(tracker))
        {
            m_nativeHandle.add_tracker(makeNativeAnnounceEntry(tracker.url, tracker.tier));
            newTrackers.append(tracker);
        }
    }

    if (!newTrackers.isEmpty())
    {
        qCInfo(lcTorrent) << "Added" << newTrackers.size() << "trackers to" << name();
        m_session->handleTorrentTrackersAdded(this, newTrackers);
        deferredRequestResumeData();
    }
}

void TorrentImpl::removeTrackers(const QStringList &trackers)
{
    QStringList removedTrackers = trackers;
    std::vector<lt::announce_entry> remainingTrackers;
    for (const lt::announce_entry &entry : m_nativeHandle.trackers())
    {
        const QString url = QString::fromStdString(entry.url);
        if (!removedTrackers.removeOne(url))
            remainingTrackers.push_back(entry);
    }

    if (remainingTrackers.size() == m_nativeHandle.trackers().size())
        return;

    m_nativeHandle.replace_trackers(remainingTrackers);
    qCInfo(lcTorrent) << "Removed trackers from" << name() << ':' << trackers;
    m_session->handleTorrentTrackersRemoved(this, trackers);
    deferredRequestResumeData();
}

void TorrentImpl::replaceTrackers(QList<TrackerEntry> trackers)
{
    // Filter out duplicate trackers, preserving the input order.
    QList<TrackerEntry> cleanTrackers;
    QSet<QString> seen;
    for (const TrackerEntry &tracker : trackers)
    {
        if (!seen.contains(tracker.url))
        {
            cleanTrackers.append(tracker);
            seen.insert(tracker.url);
        }
    }

    const QList<TrackerEntryStatus> oldEntries = m_trackerEntryStatuses;

    std::vector<lt::announce_entry> nativeTrackers;
    nativeTrackers.reserve(cleanTrackers.size());
    for (const TrackerEntry &tracker : cleanTrackers)
        nativeTrackers.push_back(makeNativeAnnounceEntry(tracker.url, tracker.tier));

    m_nativeHandle.replace_trackers(nativeTrackers);

    qCInfo(lcTorrent) << "Replaced trackers of" << name() << "with" << cleanTrackers.size() << "entries";
    m_session->handleTorrentTrackersReset(this, oldEntries, cleanTrackers);
    resetTrackerEntryStatuses();
    deferredRequestResumeData();
}

void TorrentImpl::addUrlSeeds(const QList<QUrl> &urlSeeds)
{
    QList<QUrl> addedUrlSeeds;
    for (const QUrl &url : urlSeeds)
    {
        if (!m_urlSeeds.contains(url))
        {
            m_nativeHandle.add_url_seed(url.toString().toStdString());
            m_urlSeeds.append(url);
            addedUrlSeeds.append(url);
        }
    }

    if (!addedUrlSeeds.isEmpty())
    {
        qCInfo(lcTorrent) << "Added URL seeds to" << name() << ':' << addedUrlSeeds;
        m_session->handleTorrentUrlSeedsAdded(this, addedUrlSeeds);
        deferredRequestResumeData();
    }
}

void TorrentImpl::removeUrlSeeds(const QList<QUrl> &urlSeeds)
{
    QList<QUrl> removedUrlSeeds;
    for (const QUrl &url : urlSeeds)
    {
        if (m_urlSeeds.removeOne(url))
        {
            m_nativeHandle.remove_url_seed(url.toString().toStdString());
            removedUrlSeeds.append(url);
        }
    }

    if (!removedUrlSeeds.isEmpty())
    {
        qCInfo(lcTorrent) << "Removed URL seeds from" << name() << ':' << removedUrlSeeds;
        m_session->handleTorrentUrlSeedsRemoved(this, removedUrlSeeds);
        deferredRequestResumeData();
    }
}

bool TorrentImpl::connectPeer(const PeerAddress &peerAddress)
{
    lt::error_code ec;
    const lt::address addr = lt::make_address(peerAddress.ip.toString().toStdString(), ec);
    if (ec)
        return false;

    const lt::tcp::endpoint endpoint(addr, peerAddress.port);
    try
    {
        qCDebug(lcTorrent) << "Connecting peer" << peerAddress.ip.toString() << "to" << name();
        m_nativeHandle.connect_peer(endpoint);
    }
    catch (const lt::system_error &err)
    {
        qCWarning(lcTorrent) << "Failed to connect peer:" << err.what();
        return false;
    }

    return true;
}

void TorrentImpl::clearPeers()
{
    m_nativeHandle.clear_peers();
}

void TorrentImpl::setMetadata(const TorrentInfo &torrentInfo)
{
    if (hasMetadata())
        return;

    if (!torrentInfo.matchesInfoHash(m_infoHash))
    {
        qCWarning(lcTorrent) << "Rejected metadata with a different info hash for" << name();
        return;
    }

    const QByteArray metadata = torrentInfo.rawData();
    if (metadata.isEmpty() || !m_nativeHandle.set_metadata(
            lt::span<char const>(metadata.constData(), metadata.size())))
    {
        qCWarning(lcTorrent) << "Failed to set metadata for" << name();
    }
}

Torrent::StopCondition TorrentImpl::stopCondition() const
{
    return m_stopCondition;
}

void TorrentImpl::setStopCondition(const StopCondition stopCondition)
{
    if (stopCondition == m_stopCondition)
        return;

    if (isStopped())
        return;

    if ((stopCondition == StopCondition::MetadataReceived) && hasMetadata())
        return;

    if ((stopCondition == StopCondition::FilesChecked) && hasMetadata() && !isChecking())
        return;

    qCDebug(lcTorrent) << "Setting stop condition of" << name() << "to" << static_cast<int>(stopCondition);
    m_stopCondition = stopCondition;
}

SSLParameters TorrentImpl::getSSLParameters() const
{
    return m_sslParams;
}

void TorrentImpl::setSSLParameters(const SSLParameters &sslParams)
{
    if (sslParams == getSSLParameters())
        return;

    qCDebug(lcTorrent) << "Setting SSL parameters for" << name();
    m_sslParams = sslParams;
    applySSLParameters();
    deferredRequestResumeData();
}

bool TorrentImpl::applySSLParameters()
{
    if (!m_sslParams.isValid())
        return false;

    // TODO(engine): push the certificate/key/DH params into the native handle.
    m_nativeHandle.set_ssl_certificate_buffer(m_sslParams.certificate.toPem().toStdString()
            , m_sslParams.privateKey.toPem().toStdString()
            , m_sslParams.dhParams.toStdString());
    return true;
}

QString TorrentImpl::createMagnetURI() const
{
    return QString::fromStdString(lt::make_magnet_uri(m_nativeHandle));
}

nonstd::expected<QByteArray, QString> TorrentImpl::exportToBuffer() const
{
    const nonstd::expected<lt::entry, QString> preparedEntry = exportTorrent();
    if (!preparedEntry)
        return nonstd::make_unexpected(preparedEntry.error());

    try
    {
        QByteArray buffer;
        lt::bencode(std::back_inserter(buffer), preparedEntry.value());
        return buffer;
    }
    catch (const std::exception &err)
    {
        return nonstd::make_unexpected(QString::fromLocal8Bit(err.what()));
    }
}

nonstd::expected<void, QString> TorrentImpl::exportToFile(const Path &path) const
{
    const nonstd::expected<QByteArray, QString> buffer = exportToBuffer();
    if (!buffer)
        return nonstd::make_unexpected(buffer.error());

    const auto result = Utils::IO::saveToFile(path, buffer.value());
    if (!result)
        return nonstd::make_unexpected(result.error());

    return {};
}

nonstd::expected<lt::entry, QString> TorrentImpl::exportTorrent() const
{
    if (!hasMetadata())
        return nonstd::make_unexpected(tr("Missing metadata"));

    try
    {
        lt::entry torrentEntry = lt::write_torrent_file(m_ltAddTorrentParams);
        return torrentEntry;
    }
    catch (const std::exception &err)
    {
        return nonstd::make_unexpected(QString::fromLocal8Bit(err.what()));
    }
}

// --- Async fetches (bridged into QFuture, resolved on the IO thread) ---

template <typename Func>
QFuture<std::invoke_result_t<Func>> TorrentImpl::invokeAsync(Func &&func) const
{
    auto promise = std::make_shared<QPromise<std::invoke_result_t<Func>>>();
    QFuture<std::invoke_result_t<Func>> future = promise->future();
    promise->start();
    m_session->invokeAsync([func = std::forward<Func>(func), promise]() mutable
    {
        try
        {
            promise->addResult(func());
        }
        catch (const std::exception &) {}
        promise->finish();
    });
    return future;
}

QFuture<QList<PeerInfo>> TorrentImpl::fetchPeerInfo() const
{
    return invokeAsync([nativeHandle = m_nativeHandle, allPieces = pieces()]() -> QList<PeerInfo>
    {
        std::vector<lt::peer_info> nativePeers;
        nativeHandle.get_peer_info(nativePeers);

        QList<PeerInfo> peers;
        peers.reserve(static_cast<decltype(peers)::size_type>(nativePeers.size()));
        for (const lt::peer_info &peer : nativePeers)
            peers.append(PeerInfo(peer, allPieces));
        return peers;
    });
}

QFuture<QList<QUrl>> TorrentImpl::fetchURLSeeds() const
{
    return invokeAsync([nativeHandle = m_nativeHandle]() -> QList<QUrl>
    {
        const std::set<std::string> nativeSeeds = nativeHandle.url_seeds();

        QList<QUrl> urlSeeds;
        urlSeeds.reserve(static_cast<decltype(urlSeeds)::size_type>(nativeSeeds.size()));
        for (const std::string &urlSeed : nativeSeeds)
            urlSeeds.append(QString::fromStdString(urlSeed));
        return urlSeeds;
    });
}

QFuture<QList<int>> TorrentImpl::fetchPieceAvailability() const
{
    return invokeAsync([nativeHandle = m_nativeHandle]() -> QList<int>
    {
        std::vector<int> piecesAvailability;
        nativeHandle.piece_availability(piecesAvailability);
        return {piecesAvailability.cbegin(), piecesAvailability.cend()};
    });
}

QFuture<QBitArray> TorrentImpl::fetchDownloadingPieces() const
{
    return invokeAsync([nativeHandle = m_nativeHandle, piecesCount = piecesCount()]() -> QBitArray
    {
        QBitArray result {piecesCount};
        std::vector<lt::partial_piece_info> queue;
        nativeHandle.get_download_queue(queue);
        for (const lt::partial_piece_info &info : queue)
            result.setBit(LT::toUnderlyingType(info.piece_index));
        return result;
    });
}

QFuture<QList<qreal>> TorrentImpl::fetchAvailableFileFractions() const
{
    return invokeAsync([this]() -> QList<qreal>
    {
        const int count = filesCount();
        if (count <= 0)
            return {};

        std::vector<int> piecesAvailability;
        m_nativeHandle.piece_availability(piecesAvailability);
        if (piecesAvailability.empty())
            return QList<qreal>(count, -1);

        QList<qreal> result;
        result.reserve(count);
        for (int i = 0; i < count; ++i)
        {
            const TorrentInfo::PieceRange filePieces = m_torrentInfo.filePieces(i);
            int availablePieces = 0;
            for (const int piece : filePieces)
                availablePieces += (piecesAvailability[piece] > 0) ? 1 : 0;
            const int totalPieces = filePieces.size();
            result << ((totalPieces > 0) ? (static_cast<qreal>(availablePieces) / totalPieces) : -1);
        }
        return result;
    });
}

// --- Session-interface helpers ---

lt::torrent_handle TorrentImpl::nativeHandle() const
{
    return m_nativeHandle;
}

std::shared_ptr<const lt::torrent_info> TorrentImpl::nativeTorrentInfo() const
{
    return m_ltAddTorrentParams.ti;
}

int TorrentImpl::fileIndexFromNative(const lt::file_index_t nativeFileIndex) const
{
    return m_indexMap.value(nativeFileIndex, -1);
}

bool TorrentImpl::needSaveResumeData() const
{
    return m_nativeHandle.need_save_resume_data();
}

void TorrentImpl::requestResumeData(const lt::resume_data_flags_t flags)
{
    m_nativeHandle.save_resume_data(flags);
    m_session->handleTorrentResumeDataRequested(this);
}

void TorrentImpl::deferredRequestResumeData()
{
    // Every configuration mutator funnels through here, so this is the single
    // observation point for "something about this torrent changed". The
    // notification stays on the calling thread; only the resume-data request
    // below is deferred.
    m_session->handleTorrentConfigChanged(this);

    if (!m_deferredRequestResumeDataInvoked)
    {
        // The queued call outlives us if the torrent is removed before the
        // event loop dispatches it (the invoke context is the session, not
        // this torrent) -- re-look ourselves up before touching any member.
        SessionImpl *session = m_session;
        const TorrentID torrentID = id();
        session->invoke([this, session, torrentID]()
        {
            if (session->getTorrent(torrentID) != this)
                return;
            requestResumeData();
            m_deferredRequestResumeDataInvoked = false;
        });
        m_deferredRequestResumeDataInvoked = true;
    }
}

// --- Alert-driven state updates ---

void TorrentImpl::handleStateUpdate(const lt::torrent_status &nativeStatus)
{
    updateStatus(nativeStatus);
}

void TorrentImpl::updateStatus(const lt::torrent_status &nativeStatus)
{
    const lt::torrent_status oldStatus = std::exchange(m_nativeStatus, nativeStatus);

    m_payloadRateMonitor.addSample({nativeStatus.download_payload_rate, nativeStatus.upload_payload_rate});

    updateState();
    updateProgress();

    while (!m_statusUpdatedTriggers.isEmpty())
        m_statusUpdatedTriggers.dequeue()();
}

void TorrentImpl::updateProgress()
{
    if (!hasMetadata())
        return;

    m_pieces = LT::toQBitArray(m_nativeStatus.pieces);

    std::vector<int64_t> fp;
    m_nativeHandle.file_progress(fp, lt::torrent_handle::piece_granularity);
    m_filesProgress.clear();
    m_filesProgress.reserve(filesCount());
    const QList<lt::file_index_t> nativeIndexes = m_torrentInfo.nativeIndexes();
    for (const lt::file_index_t idx : nativeIndexes)
        m_filesProgress.append(fp[LT::toUnderlyingType(idx)]);
}

void TorrentImpl::updateState()
{
    if (m_nativeStatus.state == lt::torrent_status::checking_resume_data)
    {
        m_state = TorrentState::CheckingResumeData;
    }
    else if (isMoveInProgress())
    {
        m_state = TorrentState::Moving;
    }
    else if (hasError())
    {
        m_state = TorrentState::Error;
    }
    else if (hasMissingFiles())
    {
        m_state = TorrentState::MissingFiles;
    }
    else if (m_isStopped)
    {
        m_state = isFinished() ? TorrentState::StoppedUploading : TorrentState::StoppedDownloading;
    }
    else if (m_session->isQueueingSystemEnabled() && isQueued())
    {
        m_state = isFinished() ? TorrentState::QueuedUploading : TorrentState::QueuedDownloading;
    }
    else
    {
        switch (m_nativeStatus.state)
        {
        case lt::torrent_status::checking_resume_data:
            m_state = TorrentState::CheckingResumeData;
            break;
        case lt::torrent_status::checking_files:
            m_state = isFinished() ? TorrentState::CheckingUploading : TorrentState::CheckingDownloading;
            break;
        case lt::torrent_status::downloading_metadata:
            m_state = isForced() ? TorrentState::ForcedDownloadingMetadata : TorrentState::DownloadingMetadata;
            break;
        case lt::torrent_status::downloading:
            if (m_nativeStatus.download_payload_rate > 0)
                m_state = isForced() ? TorrentState::ForcedDownloading : TorrentState::Downloading;
            else
                m_state = TorrentState::StalledDownloading;
            break;
        case lt::torrent_status::seeding:
            if (m_nativeStatus.upload_payload_rate > 0)
                m_state = isForced() ? TorrentState::ForcedUploading : TorrentState::Uploading;
            else
                m_state = TorrentState::StalledUploading;
            break;
        default:
            m_state = TorrentState::Unknown;
            break;
        }
    }
}

void TorrentImpl::handleFastResumeRejected()
{
    qCWarning(lcTorrent) << "Fast resume rejected for" << name();
    m_hasMissingFiles = true;
    updateState();
}

void TorrentImpl::handleFileCompleted(const lt::file_index_t nativeFileIndex)
{
    const int index = fileIndexFromNative(nativeFileIndex);
    if (index < 0)
        return;

    qCDebug(lcTorrent) << "File" << index << "completed for" << name();
    if (index < m_completedFiles.size())
        m_completedFiles.setBit(index);
}

void TorrentImpl::handleFileError(const FileErrorInfo fileError)
{
    m_lastFileError = fileError;
    m_session->invoke([this]() { updateState(); });
    qCWarning(lcTorrent) << "File error on" << name() << ':'
                         << QString::fromLocal8Bit(fileError.error.message().c_str());
}

void TorrentImpl::handleFileRenamed(const lt::file_index_t nativeFileIndex, const Path &newActualFilePath, const Path &oldActualFilePath)
{
    auto pending = m_renamingFiles.find(nativeFileIndex);
    if (pending == m_renamingFiles.end() || pending->isEmpty())
        return;

    const FileRenameInfo renameInfo = pending->dequeue();
    if (pending->isEmpty())
        m_renamingFiles.erase(pending);
    const int index = renameInfo.index;
    if ((index >= 0) && (index < m_filePaths.size()))
    {
        m_filePaths[index] = makeUserPath(newActualFilePath);
        m_ltAddTorrentParams.renamed_files[nativeFileIndex] = newActualFilePath.data().toStdString();
    }

    if (renameInfo.folderRenameJobID < 0)
    {
        m_session->handleTorrentContentFileRenamed(this, index, makeUserPath(oldActualFilePath));
    }
    else
    {
        for (int i = 0; i < m_renamingFolders.size(); ++i)
        {
            FolderRenameInfo &folder = m_renamingFolders[i];
            if (folder.folderRenameJobID != renameInfo.folderRenameJobID)
                continue;

            folder.pendingFileIndexes.remove(index);
            if (folder.pendingFileIndexes.isEmpty())
            {
                m_session->handleTorrentContentFolderRenamed(this, folder.newFolderPath
                        , folder.oldFolderPath, folder.renamedFiles);
                m_renamingFolders.removeAt(i);
            }
            break;
        }
    }

    deferredRequestResumeData();
}

void TorrentImpl::handleFileRenameFailed(const lt::file_index_t nativeFileIndex)
{
    auto pending = m_renamingFiles.find(nativeFileIndex);
    if (pending == m_renamingFiles.end() || pending->isEmpty())
        return;

    const FileRenameInfo renameInfo = pending->dequeue();
    if (pending->isEmpty())
        m_renamingFiles.erase(pending);
    qCWarning(lcTorrent) << "File rename failed for" << name() << "index" << renameInfo.index;

    if (renameInfo.folderRenameJobID >= 0)
    {
        for (int i = 0; i < m_renamingFolders.size(); ++i)
        {
            FolderRenameInfo &folder = m_renamingFolders[i];
            if (folder.folderRenameJobID != renameInfo.folderRenameJobID)
                continue;

            folder.failedFileIndexes.append(renameInfo.index);
            folder.pendingFileIndexes.remove(renameInfo.index);
            if (folder.pendingFileIndexes.isEmpty())
            {
                m_session->handleTorrentContentFolderRenamingFailed(this, folder.newFolderPath
                        , folder.oldFolderPath, folder.renamedFiles, folder.failedFileIndexes);
                m_renamingFolders.removeAt(i);
            }
            break;
        }
    }
}

void TorrentImpl::handleMetadataReceived()
{
    qCInfo(lcTorrent) << "Metadata received for" << name();
    m_maintenanceJob = MaintenanceJob::HandleMetadata;
    m_session->invoke([this]()
    {
        const std::shared_ptr<const lt::torrent_info> nativeInfo = m_nativeHandle.torrent_file();
        if (!nativeInfo)
            return;

        m_torrentInfo = TorrentInfo(*nativeInfo);
        m_infoHash = InfoHash {m_nativeHandle.info_hashes()};
        m_ltAddTorrentParams.ti = std::const_pointer_cast<lt::torrent_info>(nativeInfo);
        rebuildFileStateFromNative();

        endReceivedMetadataHandling(savePath(), m_torrentInfo.filePaths());
        m_maintenanceJob = MaintenanceJob::None;

        emit metadataReceived();
        m_session->handleTorrentMetadataReceived(this);
    });
}

void TorrentImpl::endReceivedMetadataHandling(const Path &savePath, const PathList &fileNames)
{
    // TODO(engine): apply saved file priorities/content layout to the freshly
    // received metadata and reload the torrent so it starts downloading content.
    Q_UNUSED(savePath);
    Q_UNUSED(fileNames);

    if (hasMetadata() && (m_stopCondition == StopCondition::MetadataReceived))
    {
        m_stopCondition = StopCondition::None;
        stop();
    }

    updateStatus(m_nativeStatus);
}

void TorrentImpl::reload()
{
    // TODO(engine): rebuild the native add_torrent_params from persistent fields
    // and reload the torrent via SessionImpl::reloadTorrent(). Wired lightly here.
    m_nativeHandle = m_session->reloadTorrent(m_nativeHandle, m_ltAddTorrentParams);
}

void TorrentImpl::handleSaveResumeData(lt::add_torrent_params params)
{
    m_ltAddTorrentParams = params;
    prepareResumeData(std::move(params));
}

void TorrentImpl::prepareResumeData(lt::add_torrent_params resumeData)
{
    // Persist our qBittorrent-managed metadata onto the resume data.
    LoadTorrentParams data;
    data.ltAddTorrentParams = std::move(resumeData);
    data.name = m_name;
    data.category = m_category;
    data.tags = m_tags;
    data.savePath = m_savePath;
    data.downloadPath = m_downloadPath;
    data.comment = m_comment;
    data.commentIsCustom = m_commentIsCustom;
    data.contentLayout = m_contentLayout;
    data.operatingMode = m_operatingMode;
    data.firstLastPiecePriority = m_hasFirstLastPiecePriority;
    data.hasFinishedStatus = m_hasFinishedStatus;
    data.stopped = m_isStopped;
    data.stopCondition = m_stopCondition;
    data.shareLimits = m_shareLimits;
    data.useAutoTMM = m_useAutoTMM;
    data.sslParameters = m_sslParams;

    m_session->handleTorrentResumeDataReady(this, std::move(data));
}

void TorrentImpl::handleTorrentChecked()
{
    qCDebug(lcTorrent) << "Torrent checked:" << name();
    m_unchecked = false;
    updateState();

    if ((m_stopCondition == StopCondition::FilesChecked) && !isStopped())
    {
        m_stopCondition = StopCondition::None;
        stop();
    }

    m_session->handleTorrentChecked(this);
}

void TorrentImpl::handleTorrentFinished()
{
    qCInfo(lcTorrent) << "Torrent finished:" << name();
    m_hasMissingFiles = false;
    if (!isStopped() && !isCompleted())
        m_hasFinishedStatus = true;

    if (!m_completedTime.isValid())
        m_completedTime = QDateTime::currentDateTime();

    updateState();
    adjustStorageLocation();
    manageActualFilePaths();

    m_session->handleTorrentFinished(this);
    deferredRequestResumeData();
}

void TorrentImpl::handleQueueingModeChanged()
{
    updateState();
}

void TorrentImpl::handleCategoryOptionsChanged()
{
    if (m_useAutoTMM)
        adjustStorageLocation();
}

void TorrentImpl::handleAppendExtensionToggled()
{
    if (!hasMetadata())
        return;

    manageActualFilePaths();
}

void TorrentImpl::handleUnwantedFolderToggled()
{
    if (!hasMetadata())
        return;

    manageActualFilePaths();
}

void TorrentImpl::handleMoveStorageJobFinished(const Path &path, const MoveStorageContext context, const bool hasOutstandingJob)
{
    qCDebug(lcTorrent) << "Move storage job finished for" << name() << "->" << path.data();

    m_nativeStatus.save_path = path.toString().toStdString();

    if (!hasOutstandingJob)
    {
        m_storageIsMoving = false;
        updateStatus(m_nativeStatus);

        while (!m_moveFinishedTriggers.isEmpty())
            m_moveFinishedTriggers.dequeue()();
    }

    if (context == MoveStorageContext::ChangeSavePath)
        m_session->handleTorrentSavePathChanged(this);
}

TrackerEntryStatus TorrentImpl::updateTrackerEntryStatus(const lt::announce_entry &announceEntry, const QHash<lt::tcp::endpoint, QMap<int, int>> &updateInfo)
{
    const QString url = QString::fromStdString(announceEntry.url);
    const auto it = std::find_if(m_trackerEntryStatuses.begin(), m_trackerEntryStatuses.end()
            , [&url](const TrackerEntryStatus &status) { return status.url == url; });
    if (it == m_trackerEntryStatuses.end())
        return {};

    ::updateTrackerEntryStatus(*it, announceEntry, {1, 2}, updateInfo);
    return *it;
}

void TorrentImpl::resetTrackerEntryStatuses()
{
    for (TrackerEntryStatus &status : m_trackerEntryStatuses)
        status.clear();
}

// --- Private helpers ---

void TorrentImpl::rebuildFileStateFromNative()
{
    if (!hasMetadata())
        return;

    m_indexMap.clear();
    m_filePaths.clear();
    m_filePriorities.clear();

    const QList<lt::file_index_t> nativeIndexes = m_torrentInfo.nativeIndexes();
    const std::vector<lt::download_priority_t> nativePriorities = m_nativeHandle.get_file_priorities();
    m_filePaths.reserve(nativeIndexes.size());
    m_filePriorities.reserve(nativeIndexes.size());

    for (int index = 0; index < nativeIndexes.size(); ++index)
    {
        const lt::file_index_t nativeIndex = nativeIndexes.at(index);
        m_indexMap.insert(nativeIndex, index);
        m_filePaths.append(m_torrentInfo.filePath(index));
        m_filePriorities.append((LT::toUnderlyingType(nativeIndex) < nativePriorities.size())
                ? LT::fromNative(nativePriorities[LT::toUnderlyingType(nativeIndex)])
                : DownloadPriority::Normal);
    }

    for (const auto &[nativeIndex, nativePath] : m_ltAddTorrentParams.renamed_files)
    {
        const auto index = m_indexMap.constFind(nativeIndex);
        if (index == m_indexMap.cend())
            continue;

        m_filePaths[*index] = makeUserPath(Path(QString::fromStdString(nativePath)));
    }

    m_completedFiles.fill(false, m_filePaths.size());
}

bool TorrentImpl::isMoveInProgress() const
{
    return m_storageIsMoving;
}

void TorrentImpl::setAutoManaged(const bool enable)
{
    if (enable)
        m_nativeHandle.set_flags(lt::torrent_flags::auto_managed);
    else
        m_nativeHandle.unset_flags(lt::torrent_flags::auto_managed);
}

Path TorrentImpl::makeActualPath(const int index, const Path &path) const
{
    Path result = path;

    if (m_session->isUnwantedFolderEnabled()
            && (m_filePriorities.value(index, DownloadPriority::Normal) == DownloadPriority::Ignored))
    {
        result = Path(u".unwanted"_s) / result;
    }

    const bool fileComplete = m_hasFinishedStatus || ((index >= 0)
            && (index < m_filesProgress.size())
            && (m_filesProgress.at(index) >= fileSize(index)));
    if (m_session->isAppendExtensionEnabled() && !fileComplete
            && !result.hasExtension(u".!qB"_s))
    {
        result = Path(result.data() + u".!qB"_s);
    }

    return result;
}

Path TorrentImpl::makeUserPath(const Path &path) const
{
    // Strip the reserved unwanted root and ".!qB" append extension so the
    // content model and user actions continue to address logical paths.
    Path result = path;
    const Path unwantedRoot {u".unwanted"_s};
    if (result.hasAncestor(unwantedRoot))
        result = unwantedRoot.relativePathOf(result);
    if (result.hasExtension(u".!qB"_s))
        result = result.removedExtension();
    return result;
}

void TorrentImpl::adjustStorageLocation()
{
    const Path downloadPath = this->downloadPath();
    const Path targetPath = ((isFinished() || m_hasFinishedStatus || downloadPath.isEmpty())
            ? savePath() : downloadPath);

    if ((targetPath != actualStorageLocation()) || isMoveInProgress())
        moveStorage(targetPath, MoveStorageContext::AdjustCurrentLocation);
}

void TorrentImpl::moveStorage(const Path &newPath, const MoveStorageContext context)
{
    const MoveStorageMode mode = (context == MoveStorageContext::ChangeDownloadPath)
            ? MoveStorageMode::Overwrite : MoveStorageMode::KeepExistingFiles;

    if (m_session->addMoveTorrentStorageJob(this, newPath, mode, context))
    {
        m_storageIsMoving = true;
        updateState();
    }
}

void TorrentImpl::manageActualFilePaths()
{
    if (!hasMetadata())
        return;

    const QList<lt::file_index_t> nativeIndexes = m_torrentInfo.nativeIndexes();
    for (int index = 0; index < m_filePaths.size(); ++index)
    {
        if (index >= nativeIndexes.size())
            break;
        const lt::file_index_t nativeIndex = nativeIndexes.at(index);

        Path currentPath = m_torrentInfo.filePath(index);
        if (const auto it = m_ltAddTorrentParams.renamed_files.find(nativeIndex);
                it != m_ltAddTorrentParams.renamed_files.end())
        {
            currentPath = Path(QString::fromStdString(it->second));
        }

        // doRenameFile() accepts the logical user path and applies the
        // storage transform exactly once. Passing the already-transformed
        // desired path here would duplicate .unwanted/ or .!qB.
        const Path logicalPath = m_filePaths.at(index);
        if (currentPath != makeActualPath(index, logicalPath))
            doRenameFile(index, logicalPath);
    }
}
