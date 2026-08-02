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

#include "sessionimpl.h"

#include <algorithm>
#include <memory>
#include <vector>

#include <libtorrent/alert_types.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/extensions/smart_ban.hpp>
#include <libtorrent/extensions/ut_metadata.hpp>
#include <libtorrent/extensions/ut_pex.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>

#include <QDir>
#include <QFuture>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QString>
#include <QThread>
#include <QTimer>
#include <QUuid>

#include "base/global.h"
#include "base/logging.h"
#include "base/net/proxyconfigurationmanager.h"
#include "base/preferences.h"
#include "base/profile.h"
#include "base/settingsstorage.h"
#include "base/utils/fs.h"
#include "base/utils/io.h"
#include "base/utils/misc.h"
#include "base/utils/net.h"
#include "base/utils/string.h"
#include "base/version.h"
#include "addtorrentparams.h"
#include "bandwidthscheduler.h"
#include "common.h"
#include "filesearcher.h"
#include "loadtorrentparams.h"
#include "lttypecast.h"
#include "resumedatastorage.h"
#include "torrentdescriptor.h"
#include "torrentimpl.h"

using namespace BitTorrent;
using namespace Qt::Literals::StringLiterals;
using namespace std::chrono_literals;

Session *SessionImpl::m_instance = nullptr;

namespace
{
    const int MAX_PROCESSING_RESUMEDATA_COUNT = 50;
    const int STATISTICS_SAVE_INTERVAL = std::chrono::milliseconds(15min).count();

    template <typename T>
    struct LowerLimited
    {
        LowerLimited(T limit, T ret)
            : m_limit(limit)
            , m_ret(ret)
        {
        }

        explicit LowerLimited(T limit)
            : LowerLimited(limit, limit)
        {
        }

        T operator()(T val) const
        {
            return val <= m_limit ? m_ret : val;
        }

    private:
        const T m_limit;
        const T m_ret;
    };

    template <typename T>
    LowerLimited<T> lowerLimited(T limit) { return LowerLimited<T>(limit); }

    template <typename T>
    LowerLimited<T> lowerLimited(T limit, T ret) { return LowerLimited<T>(limit, ret); }

    QString toString(const lt::socket_type_t socketType)
    {
        switch (socketType)
        {
#ifdef QBT_USES_LIBTORRENT2
        case lt::socket_type_t::http:
            return u"HTTP"_s;
        case lt::socket_type_t::http_ssl:
            return u"HTTP_SSL"_s;
#endif
        case lt::socket_type_t::tcp:
            return u"TCP"_s;
        case lt::socket_type_t::tcp_ssl:
            return u"TCP_SSL"_s;
#ifdef QBT_USES_LIBTORRENT2
        case lt::socket_type_t::utp:
            return u"uTP"_s;
#else
        case lt::socket_type_t::udp:
            return u"UDP"_s;
#endif
        case lt::socket_type_t::utp_ssl:
            return u"uTP_SSL"_s;
#ifdef QBT_USES_LIBTORRENT2
        case lt::socket_type_t::i2p:
            return u"I2P"_s;
#endif
        default:
            return u"Unknown"_s;
        }
    }
}

// --- Singleton lifecycle -----------------------------------------------------

void Session::initInstance()
{
    if (!SessionImpl::m_instance)
    {
        SessionImpl::m_instance = new SessionImpl;
        qCInfo(lcSession) << "BitTorrent session instance created";
    }
}

void Session::freeInstance()
{
    delete SessionImpl::m_instance;
    SessionImpl::m_instance = nullptr;
    qCInfo(lcSession) << "BitTorrent session instance freed";
}

Session *Session::instance()
{
    return SessionImpl::m_instance;
}

// --- Static category helpers -------------------------------------------------

bool Session::isValidCategoryName(const QString &name)
{
    const QRegularExpression re {uR"(^([^\\\/]|[^\\\/]([^\\\/]|\/(?=[^\/]))*[^\\\/])$)"_s};
    return name.isEmpty() || (re.match(name).hasMatch());
}

QString Session::subcategoryName(const QString &category)
{
    const int sepIndex = category.lastIndexOf(u'/');
    if (sepIndex >= 0)
        return category.mid(sepIndex + 1);
    return category;
}

QString Session::parentCategoryName(const QString &category)
{
    const int sepIndex = category.lastIndexOf(u'/');
    if (sepIndex >= 0)
        return category.left(sepIndex);
    return {};
}

QStringList Session::expandCategory(const QString &category)
{
    QStringList result;
    if (!isValidCategoryName(category))
        return result;

    int index = 0;
    while ((index = category.indexOf(u'/', index)) >= 0)
    {
        result << category.left(index);
        ++index;
    }
    result << category;
    return result;
}

// --- Constructor / destructor ------------------------------------------------

#define BITTORRENT_KEY(name) u"BitTorrent/" name
#define BITTORRENT_SESSION_KEY(name) u"BitTorrent/Session/" name

SessionImpl::SessionImpl(QObject *parent)
    : Session(parent)
    , m_DHTBootstrapNodes(BITTORRENT_SESSION_KEY(u"DHTBootstrapNodes"_s), {})
    , m_isDHTEnabled(BITTORRENT_SESSION_KEY(u"DHTEnabled"_s), true)
    , m_isLSDEnabled(BITTORRENT_SESSION_KEY(u"LSDEnabled"_s), true)
    , m_isPeXEnabled(BITTORRENT_SESSION_KEY(u"PeXEnabled"_s), true)
    , m_isIPFilteringEnabled(BITTORRENT_SESSION_KEY(u"IPFilteringEnabled"_s), false)
    , m_isTrackerFilteringEnabled(BITTORRENT_SESSION_KEY(u"TrackerFilteringEnabled"_s), false)
    , m_IPFilterFile(BITTORRENT_SESSION_KEY(u"IPFilter"_s), {})
    , m_announceToAllTrackers(BITTORRENT_SESSION_KEY(u"AnnounceToAllTrackers"_s), false)
    , m_announceToAllTiers(BITTORRENT_SESSION_KEY(u"AnnounceToAllTiers"_s), true)
    , m_asyncIOThreads(BITTORRENT_SESSION_KEY(u"AsyncIOThreadsCount"_s), 10)
    , m_hashingThreads(BITTORRENT_SESSION_KEY(u"HashingThreadsCount"_s), 1)
    , m_filePoolSize(BITTORRENT_SESSION_KEY(u"FilePoolSize"_s), 5000)
    , m_checkingMemUsage(BITTORRENT_SESSION_KEY(u"CheckingMemUsageSize"_s), 32)
    , m_diskCacheSize(BITTORRENT_SESSION_KEY(u"DiskCacheSize"_s), -1)
    , m_diskCacheTTL(BITTORRENT_SESSION_KEY(u"DiskCacheTTL"_s), 60)
    , m_diskQueueSize(BITTORRENT_SESSION_KEY(u"DiskQueueSize"_s), (1024 * 1024))
    , m_diskIOType(BITTORRENT_SESSION_KEY(u"DiskIOType"_s), DiskIOType::Default)
    , m_diskIOReadMode(BITTORRENT_SESSION_KEY(u"DiskIOReadMode"_s), DiskIOReadMode::EnableOSCache)
    , m_diskIOWriteMode(BITTORRENT_SESSION_KEY(u"DiskIOWriteMode"_s), DiskIOWriteMode::EnableOSCache)
    , m_coalesceReadWriteEnabled(BITTORRENT_SESSION_KEY(u"CoalesceReadWrite"_s), false)
    , m_usePieceExtentAffinity(BITTORRENT_SESSION_KEY(u"PieceExtentAffinity"_s), false)
    , m_isSuggestMode(BITTORRENT_SESSION_KEY(u"SuggestMode"_s), false)
    , m_sendBufferWatermark(BITTORRENT_SESSION_KEY(u"SendBufferWatermark"_s), 500)
    , m_sendBufferLowWatermark(BITTORRENT_SESSION_KEY(u"SendBufferLowWatermark"_s), 10)
    , m_sendBufferWatermarkFactor(BITTORRENT_SESSION_KEY(u"SendBufferWatermarkFactor"_s), 50)
    , m_connectionSpeed(BITTORRENT_SESSION_KEY(u"ConnectionSpeed"_s), 30)
    , m_isSeedingOutgoingConnectionsEnabled(BITTORRENT_SESSION_KEY(u"SeedingOutgoingConnections"_s), true)
    , m_socketSendBufferSize(BITTORRENT_SESSION_KEY(u"SocketSendBufferSize"_s), 0)
    , m_socketReceiveBufferSize(BITTORRENT_SESSION_KEY(u"SocketReceiveBufferSize"_s), 0)
    , m_socketBacklogSize(BITTORRENT_SESSION_KEY(u"SocketBacklogSize"_s), 30)
    , m_isAnonymousModeEnabled(BITTORRENT_SESSION_KEY(u"AnonymousModeEnabled"_s), false)
    , m_isQueueingEnabled(BITTORRENT_SESSION_KEY(u"QueueingSystemEnabled"_s), false)
    , m_maxActiveDownloads(BITTORRENT_SESSION_KEY(u"MaxActiveDownloads"_s), 3, lowerLimited(-1))
    , m_maxActiveUploads(BITTORRENT_SESSION_KEY(u"MaxActiveUploads"_s), 3, lowerLimited(-1))
    , m_maxActiveTorrents(BITTORRENT_SESSION_KEY(u"MaxActiveTorrents"_s), 5, lowerLimited(-1))
    , m_ignoreSlowTorrentsForQueueing(BITTORRENT_SESSION_KEY(u"IgnoreSlowTorrentsForQueueing"_s), false)
    , m_downloadRateForSlowTorrents(BITTORRENT_SESSION_KEY(u"SlowTorrentsDownloadRate"_s), 2)
    , m_uploadRateForSlowTorrents(BITTORRENT_SESSION_KEY(u"SlowTorrentsUploadRate"_s), 2)
    , m_slowTorrentsInactivityTimer(BITTORRENT_SESSION_KEY(u"SlowTorrentsInactivityTimer"_s), 60)
    , m_outgoingPortsMin(BITTORRENT_SESSION_KEY(u"OutgoingPortsMin"_s), 0)
    , m_outgoingPortsMax(BITTORRENT_SESSION_KEY(u"OutgoingPortsMax"_s), 0)
    , m_UPnPLeaseDuration(BITTORRENT_SESSION_KEY(u"UPnPLeaseDuration"_s), 0)
    , m_peerDSCP(BITTORRENT_SESSION_KEY(u"PeerDSCP"_s), 0x04)
    , m_ignoreLimitsOnLAN(BITTORRENT_SESSION_KEY(u"IgnoreLimitsOnLAN"_s), false)
    , m_includeOverheadInLimits(BITTORRENT_SESSION_KEY(u"IncludeOverheadInLimits"_s), false)
    , m_announceIP(BITTORRENT_SESSION_KEY(u"AnnounceIP"_s), {})
    , m_announcePort(BITTORRENT_SESSION_KEY(u"AnnouncePort"_s), 0)
    , m_maxConcurrentHTTPAnnounces(BITTORRENT_SESSION_KEY(u"MaxConcurrentHTTPAnnounces"_s), 50)
    , m_isReannounceWhenAddressChangedEnabled(BITTORRENT_SESSION_KEY(u"ReannounceWhenAddressChanged"_s), false)
    , m_stopTrackerTimeout(BITTORRENT_SESSION_KEY(u"StopTrackerTimeout"_s), 2)
    , m_maxConnections(BITTORRENT_SESSION_KEY(u"MaxConnections"_s), 500, lowerLimited(0, -1))
    , m_maxUploads(BITTORRENT_SESSION_KEY(u"MaxUploads"_s), 20, lowerLimited(0, -1))
    , m_maxConnectionsPerTorrent(BITTORRENT_SESSION_KEY(u"MaxConnectionsPerTorrent"_s), 100, lowerLimited(0, -1))
    , m_maxUploadsPerTorrent(BITTORRENT_SESSION_KEY(u"MaxUploadsPerTorrent"_s), 4, lowerLimited(0, -1))
    , m_btProtocol(BITTORRENT_SESSION_KEY(u"BTProtocol"_s), BTProtocol::Both)
    , m_isUTPRateLimited(BITTORRENT_SESSION_KEY(u"uTPRateLimited"_s), true)
    , m_utpMixedMode(BITTORRENT_SESSION_KEY(u"uTPMixedMode"_s), MixedModeAlgorithm::TCP)
    , m_hostnameCacheTTL(BITTORRENT_SESSION_KEY(u"HostNameCacheTTL"_s), 1200)
    , m_IDNSupportEnabled(BITTORRENT_SESSION_KEY(u"IDNSupportEnabled"_s), false)
    , m_multiConnectionsPerIpEnabled(BITTORRENT_SESSION_KEY(u"MultiConnectionsPerIp"_s), false)
    , m_validateHTTPSTrackerCertificate(BITTORRENT_SESSION_KEY(u"ValidateHTTPSTrackerCertificate"_s), true)
    , m_SSRFMitigationEnabled(BITTORRENT_SESSION_KEY(u"SSRFMitigation"_s), true)
    , m_blockPeersOnPrivilegedPorts(BITTORRENT_SESSION_KEY(u"BlockPeersOnPrivilegedPorts"_s), false)
    , m_isAddTrackersEnabled(BITTORRENT_SESSION_KEY(u"AddTrackersEnabled"_s), false)
    , m_additionalTrackers(BITTORRENT_SESSION_KEY(u"AdditionalTrackers"_s), {})
    , m_isAddTrackersFromURLEnabled(BITTORRENT_SESSION_KEY(u"AddTrackersFromURLEnabled"_s), false)
    , m_additionalTrackersURL(BITTORRENT_SESSION_KEY(u"AdditionalTrackersURL"_s), {})
    , m_globalMaxRatio(BITTORRENT_SESSION_KEY(u"GlobalMaxRatio"_s), -1, [](qreal r) { return r < 0 ? -1. : r; })
    , m_globalMaxSeedingMinutes(BITTORRENT_SESSION_KEY(u"GlobalMaxSeedingMinutes"_s), -1, lowerLimited(-1))
    , m_globalMaxInactiveSeedingMinutes(BITTORRENT_SESSION_KEY(u"GlobalMaxInactiveSeedingMinutes"_s), -1, lowerLimited(-1))
    , m_isAddTorrentToQueueTop(BITTORRENT_SESSION_KEY(u"AddTorrentToTopOfQueue"_s), false)
    , m_isAddTorrentStopped(BITTORRENT_SESSION_KEY(u"AddTorrentStopped"_s), false)
    , m_torrentStopCondition(BITTORRENT_SESSION_KEY(u"TorrentStopCondition"_s), Torrent::StopCondition::None)
    , m_torrentContentLayout(BITTORRENT_SESSION_KEY(u"TorrentContentLayout"_s), TorrentContentLayout::Original)
    , m_isAppendExtensionEnabled(BITTORRENT_SESSION_KEY(u"AddExtensionToIncompleteFiles"_s), false)
    , m_isUnwantedFolderEnabled(BITTORRENT_SESSION_KEY(u"UseUnwantedFolder"_s), false)
    , m_refreshInterval(BITTORRENT_SESSION_KEY(u"RefreshInterval"_s), 1500)
    , m_isPreallocationEnabled(BITTORRENT_SESSION_KEY(u"Preallocation"_s), false)
    , m_torrentExportDirectory(BITTORRENT_SESSION_KEY(u"TorrentExportDirectory"_s), {})
    , m_finishedTorrentExportDirectory(BITTORRENT_SESSION_KEY(u"FinishedTorrentExportDirectory"_s), {})
    , m_globalDownloadSpeedLimit(BITTORRENT_SESSION_KEY(u"GlobalDLSpeedLimit"_s), 0, lowerLimited(0))
    , m_globalUploadSpeedLimit(BITTORRENT_SESSION_KEY(u"GlobalUPSpeedLimit"_s), 0, lowerLimited(0))
    , m_altGlobalDownloadSpeedLimit(BITTORRENT_SESSION_KEY(u"AlternativeGlobalDLSpeedLimit"_s), 10, lowerLimited(0))
    , m_altGlobalUploadSpeedLimit(BITTORRENT_SESSION_KEY(u"AlternativeGlobalUPSpeedLimit"_s), 10, lowerLimited(0))
    , m_isAltGlobalSpeedLimitEnabled(BITTORRENT_SESSION_KEY(u"UseAlternativeGlobalSpeedLimit"_s), false)
    , m_isBandwidthSchedulerEnabled(BITTORRENT_SESSION_KEY(u"BandwidthSchedulerEnabled"_s), false)
    , m_isPerformanceWarningEnabled(BITTORRENT_SESSION_KEY(u"PerformanceWarning"_s), false)
    , m_saveResumeDataInterval(BITTORRENT_SESSION_KEY(u"SaveResumeDataInterval"_s), 60)
    , m_saveStatisticsInterval(BITTORRENT_SESSION_KEY(u"SaveStatisticsInterval"_s), 15)
    , m_shutdownTimeout(BITTORRENT_SESSION_KEY(u"ShutdownTimeout"_s), -1)
    , m_port(BITTORRENT_SESSION_KEY(u"Port"_s), -1)
    , m_sslEnabled(BITTORRENT_SESSION_KEY(u"SSL/Enabled"_s), false)
    , m_sslPort(BITTORRENT_SESSION_KEY(u"SSL/Port"_s), -1)
    , m_networkInterface(BITTORRENT_SESSION_KEY(u"Interface"_s), {})
    , m_networkInterfaceName(BITTORRENT_SESSION_KEY(u"InterfaceName"_s), {})
    , m_networkInterfaceAddress(BITTORRENT_SESSION_KEY(u"InterfaceAddress"_s), {})
    , m_encryption(BITTORRENT_SESSION_KEY(u"Encryption"_s), 0)
    , m_maxActiveCheckingTorrents(BITTORRENT_SESSION_KEY(u"MaxActiveCheckingTorrents"_s), 1)
    , m_isProxyPeerConnectionsEnabled(BITTORRENT_SESSION_KEY(u"ProxyPeerConnections"_s), false)
    , m_chokingAlgorithm(BITTORRENT_SESSION_KEY(u"ChokingAlgorithm"_s), ChokingAlgorithm::FixedSlots)
    , m_seedChokingAlgorithm(BITTORRENT_SESSION_KEY(u"SeedChokingAlgorithm"_s), SeedChokingAlgorithm::FastestUpload)
    , m_storedTags(BITTORRENT_SESSION_KEY(u"Tags"_s), {})
    , m_shareLimitAction(BITTORRENT_SESSION_KEY(u"ShareLimitAction"_s), ShareLimitAction::Stop)
    , m_shareLimitsMode(BITTORRENT_SESSION_KEY(u"ShareLimitsMode"_s), ShareLimitsMode::MatchAny)
    , m_savePath(u"Downloads/SavePath"_s, Utils::Fs::homePath() / Path(u"qBittorrent/downloads"_s))
    , m_downloadPath(u"Downloads/DownloadPath"_s, (m_savePath.get() / Path(u"temp"_s)))
    , m_isDownloadPathEnabled(u"Downloads/DownloadPathEnabled"_s, false)
    , m_useCategoryPathsInManualMode(BITTORRENT_SESSION_KEY(u"UseCategoryPathsInManualMode"_s), false)
    , m_isAutoTMMDisabledByDefault(BITTORRENT_KEY(u"AutoTMMDisabledByDefault"_s), true)
    , m_isDisableAutoTMMWhenCategoryChanged(BITTORRENT_KEY(u"DisableAutoTMMTriggers/CategoryChanged"_s), false)
    , m_isDisableAutoTMMWhenDefaultSavePathChanged(BITTORRENT_KEY(u"DisableAutoTMMTriggers/DefaultSavePathChanged"_s), true)
    , m_isDisableAutoTMMWhenCategorySavePathChanged(BITTORRENT_KEY(u"DisableAutoTMMTriggers/CategorySavePathChanged"_s), true)
    , m_isTrackerEnabled(BITTORRENT_KEY(u"TrackerEnabled"_s), false)
    , m_peerTurnover(BITTORRENT_SESSION_KEY(u"PeerTurnover"_s), 4)
    , m_peerTurnoverCutoff(BITTORRENT_SESSION_KEY(u"PeerTurnoverCutOff"_s), 90)
    , m_peerTurnoverInterval(BITTORRENT_SESSION_KEY(u"PeerTurnoverInterval"_s), 300)
    , m_requestQueueSize(BITTORRENT_SESSION_KEY(u"RequestQueueSize"_s), 500)
    , m_isExcludedFileNamesEnabled(BITTORRENT_KEY(u"ExcludedFileNamesEnabled"_s), false)
    , m_excludedFileNames(BITTORRENT_SESSION_KEY(u"ExcludedFileNames"_s), {})
    , m_bannedIPs(u"State/BannedIPs"_s, {})
    , m_resumeDataStorageType(BITTORRENT_SESSION_KEY(u"ResumeDataStorageType"_s), ResumeDataStorageType::Legacy)
    , m_isMergeTrackersEnabled(BITTORRENT_KEY(u"MergeTrackersEnabled"_s), false)
    , m_isI2PEnabled(BITTORRENT_SESSION_KEY(u"I2P/Enabled"_s), false)
    , m_I2PAddress(BITTORRENT_SESSION_KEY(u"I2P/Address"_s), u"127.0.0.1"_s)
    , m_I2PPort(BITTORRENT_SESSION_KEY(u"I2P/Port"_s), 7656)
    , m_I2PMixedMode(BITTORRENT_SESSION_KEY(u"I2P/MixedMode"_s), false)
    , m_I2PInboundQuantity(BITTORRENT_SESSION_KEY(u"I2P/InboundQuantity"_s), 3)
    , m_I2POutboundQuantity(BITTORRENT_SESSION_KEY(u"I2P/OutboundQuantity"_s), 3)
    , m_I2PInboundLength(BITTORRENT_SESSION_KEY(u"I2P/InboundLength"_s), 3)
    , m_I2POutboundLength(BITTORRENT_SESSION_KEY(u"I2P/OutboundLength"_s), 3)
    , m_torrentContentRemoveOption(BITTORRENT_SESSION_KEY(u"TorrentContentRemoveOption"_s), TorrentContentRemoveOption::Delete)
    , m_startPaused(BITTORRENT_SESSION_KEY(u"StartPaused"_s))
{
    qCInfo(lcSession) << "Initializing BitTorrent session";

    m_seedingLimitTimer = new QTimer(this);
    m_seedingLimitTimer->setInterval(10s);
    connect(m_seedingLimitTimer, &QTimer::timeout, this, [this]() { updateShareLimitsTimer(); });

    m_resumeDataTimer = new QTimer(this);
    m_resumeDataTimer->setInterval(std::chrono::minutes(saveResumeDataInterval()));
    connect(m_resumeDataTimer, &QTimer::timeout, this, [this]() { generateResumeData(); });
    if (saveResumeDataInterval() > 0)
        m_resumeDataTimer->start();

    m_recentErroredTorrentsTimer = new QTimer(this);
    m_recentErroredTorrentsTimer->setSingleShot(true);
    m_recentErroredTorrentsTimer->setInterval(1s);
    connect(m_recentErroredTorrentsTimer, &QTimer::timeout, this
            , [this]() { m_recentErroredTorrents.clear(); });

    m_updateTrackersFromURLTimer = new QTimer(this);
    m_updateTrackersFromURLTimer->setInterval(1h);
    connect(m_updateTrackersFromURLTimer, &QTimer::timeout, this, [this]() { updateTrackersFromURL(); });

    // Proxy fields and the per-purpose enable flag live outside SessionImpl's
    // CachedSettingValue members. Re-apply native settings when either owner
    // changes so toggling only the BitTorrent profile still takes effect live.
    connect(Net::ProxyConfigurationManager::instance(),
        &Net::ProxyConfigurationManager::proxyConfigurationChanged,
        this, &SessionImpl::configureDeferred);
    connect(Preferences::instance(), &Preferences::changed,
        this, &SessionImpl::configureDeferred);

    m_ioThread.reset(new QThread);
    m_ioThread->setObjectName("BitTorrent session");

    m_asyncWorker = new QThreadPool(this);
    m_asyncWorker->setMaxThreadCount(1);

    m_resumeDataStorage = new ResumeDataStorage(
            specialFolderLocation(SpecialFolder::Data) / Path(u"resume-data"_s));
    if (!m_resumeDataStorage->isAvailable())
        qCWarning(lcSession) << "Resume data storage unavailable; the torrent list will not survive a restart";

    initializeNativeSession();
    configureComponents();

    loadCategories();
    if (m_needUpgradeDownloadPath)
        upgradeCategories();

    const TagSet storedTags {m_storedTags.get().begin(), m_storedTags.get().end()};
    for (const Tag &tag : storedTags)
        m_tags.insert(tag);

    enableBandwidthScheduler();
    populateAdditionalTrackers();
    if (isAddTrackersFromURLEnabled())
        updateTrackersFromURL();

    prepareStartup();

    // Kick off the periodic status-refresh loop (post_torrent_updates ->
    // state_update_alert -> enqueueRefresh -> ...). Without this first call
    // the loop never starts and transfer rows freeze at their added state.
    enqueueRefresh();

    qCInfo(lcSession) << "BitTorrent session initialized";
}

SessionImpl::~SessionImpl()
{
    qCInfo(lcSession) << "Shutting down BitTorrent session";

    if (m_nativeSession)
    {
        saveResumeData();

        // Give outstanding save_resume_data_alert(s) a bounded chance to arrive
        // and reach handleTorrentResumeDataReady() before the native session
        // (and its alert queue) goes away, or shutdown would silently drop
        // whatever changed since the last periodic/event-triggered save.
        if (m_numResumeData > 0)
        {
            const int timeoutMs = (shutdownTimeout() >= 0) ? shutdownTimeout() : 15000;
            QElapsedTimer shutdownTimer;
            shutdownTimer.start();
            while ((m_numResumeData > 0) && (shutdownTimer.elapsed() < timeoutMs))
            {
                fetchPendingAlerts(lt::milliseconds(100));
                for (const lt::alert *alert : m_alerts)
                    handleAlert(const_cast<lt::alert *>(alert));
            }
            if (m_numResumeData > 0)
            {
                qCWarning(lcSession) << "Shutdown timed out waiting for" << m_numResumeData
                                     << "resume data save(s) to complete";
            }
        }

        saveStatistics();

        // Do a graceful pause of libtorrent session
        m_nativeSession->pause();

        delete m_nativeSession;
        m_nativeSession = nullptr;
    }

    qDeleteAll(m_torrents);
    m_torrents.clear();

    delete m_resumeDataStorage;
    m_resumeDataStorage = nullptr;

    qCInfo(lcSession) << "BitTorrent session shut down";
}

// --- Native session setup (deep glue) ---------------------------------------

void SessionImpl::initializeNativeSession()
{
    // TODO(engine): construct the lt::session_params from loadLTSettings(), install
    // the ut_pex/ut_metadata/smart_ban extensions and the NativeSessionExtension,
    // then move the alert-processing loop onto the dedicated IO thread. The high-level
    // structure is wired; the low-level session_params assembly is engine-deep.
    lt::settings_pack pack = loadLTSettings();

    lt::session_params params {std::move(pack)};
    m_nativeSession = new lt::session(std::move(params));

    m_nativeSession->add_extension(&lt::create_ut_pex_plugin);
    m_nativeSession->add_extension(&lt::create_ut_metadata_plugin);
    m_nativeSession->add_extension(&lt::create_smart_ban_plugin);

    m_nativeSession->set_alert_notify([this]()
    {
        // Wake up the IO thread to drain pending alerts.
        invoke([this]() { readAlerts(); });
    });

    initMetrics();
    qCDebug(lcSession) << "Native libtorrent session created";
}

lt::settings_pack SessionImpl::loadLTSettings() const
{
    lt::settings_pack pack;

    pack.set_int(lt::settings_pack::alert_mask, lt::alert_category::status
            | lt::alert_category::file_progress
            | lt::alert_category::error | lt::alert_category::port_mapping
            | lt::alert_category::ip_block | lt::alert_category::performance_warning
            | lt::alert_category::tracker | lt::alert_category::connect
            | lt::alert_category::storage);

    pack.set_str(lt::settings_pack::peer_fingerprint, lt::generate_fingerprint("qB", QBT_VERSION_MAJOR, QBT_VERSION_MINOR, QBT_VERSION_BUGFIX, QBT_VERSION_BUILD));
    pack.set_bool(lt::settings_pack::listen_system_port_fallback, false);
    pack.set_str(lt::settings_pack::user_agent, QStringLiteral("qBittorrent/" QBT_VERSION_2).toStdString());

    pack.set_int(lt::settings_pack::aio_threads, asyncIOThreads());
    pack.set_int(lt::settings_pack::hashing_threads, hashingThreads());
    pack.set_int(lt::settings_pack::file_pool_size, filePoolSize());
    pack.set_int(lt::settings_pack::checking_mem_usage, checkingMemUsage() * 64);
    pack.set_int(lt::settings_pack::connections_limit, maxConnections());
    pack.set_int(lt::settings_pack::unchoke_slots_limit, maxUploads());
    pack.set_bool(lt::settings_pack::enable_dht, isDHTEnabled());
    pack.set_bool(lt::settings_pack::enable_lsd, isLSDEnabled());
    pack.set_int(lt::settings_pack::download_rate_limit, downloadSpeedLimit());
    pack.set_int(lt::settings_pack::upload_rate_limit, uploadSpeedLimit());
    pack.set_bool(lt::settings_pack::anonymous_mode, isAnonymousModeEnabled());

    // The UI persists qBittorrent's encryption order (allow, require,
    // disable), while libtorrent's enum order is forced, enabled, disabled.
    // Map explicitly so "Allow encryption" never becomes require-only.
    lt::settings_pack::enc_policy encryptionPolicy = lt::settings_pack::pe_enabled;
    switch (encryption())
    {
    case 1:
        encryptionPolicy = lt::settings_pack::pe_forced;
        break;
    case 2:
        encryptionPolicy = lt::settings_pack::pe_disabled;
        break;
    default:
        break;
    }
    pack.set_int(lt::settings_pack::out_enc_policy, encryptionPolicy);
    pack.set_int(lt::settings_pack::in_enc_policy, encryptionPolicy);
    pack.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_both);
    pack.set_bool(lt::settings_pack::announce_crypto_support,
        encryptionPolicy != lt::settings_pack::pe_disabled);

    // General-purpose downloads have their own QNetworkProxy. Libtorrent must
    // receive the same persisted proxy explicitly or the BitTorrent profile
    // and peer-connection checkbox are only cosmetic and traffic goes direct.
    const auto *proxyManager = Net::ProxyConfigurationManager::instance();
    const bool useProxy = proxyManager && Preferences::instance()->useProxyForBT();
    const Net::ProxyConfiguration proxy = proxyManager
        ? proxyManager->proxyConfiguration() : Net::ProxyConfiguration {};
    int nativeProxyType = lt::settings_pack::none;
    if (useProxy)
    {
        switch (proxy.type)
        {
        case Net::ProxyType::HTTP:
            nativeProxyType = proxy.authEnabled
                ? lt::settings_pack::http_pw : lt::settings_pack::http;
            break;
        case Net::ProxyType::SOCKS5:
            nativeProxyType = proxy.authEnabled
                ? lt::settings_pack::socks5_pw : lt::settings_pack::socks5;
            break;
        case Net::ProxyType::SOCKS4:
            nativeProxyType = lt::settings_pack::socks4;
            break;
        case Net::ProxyType::None:
            break;
        }
    }
    pack.set_int(lt::settings_pack::proxy_type, nativeProxyType);
    pack.set_str(lt::settings_pack::proxy_hostname, proxy.ip.toStdString());
    pack.set_int(lt::settings_pack::proxy_port, proxy.port);
    pack.set_str(lt::settings_pack::proxy_username,
        (proxy.authEnabled ? proxy.username : QString()).toStdString());
    pack.set_str(lt::settings_pack::proxy_password,
        (proxy.authEnabled ? proxy.password : QString()).toStdString());
    pack.set_bool(lt::settings_pack::proxy_hostnames, useProxy && proxy.hostnameLookupEnabled);
    pack.set_bool(lt::settings_pack::proxy_tracker_connections, useProxy);
    pack.set_bool(lt::settings_pack::proxy_peer_connections,
        useProxy && isProxyPeerConnectionsEnabled());

    applyNetworkInterfacesSettings(pack);

    // TODO(engine): map the remaining ~120 CachedSettingValue fields onto their
    // corresponding libtorrent settings_pack keys (encryption, choking algorithms,
    // buffer watermarks, queueing, I2P, proxy, etc.). The commonly exercised keys
    // are wired above.

    return pack;
}

void SessionImpl::applyNetworkInterfacesSettings(lt::settings_pack &settingsPack) const
{
    const int portValue = (port() < 0) ? static_cast<int>(QRandomGenerator::global()->bounded(1024, 65536)) : port();
    const QStringList endpoints = getListeningIPs();

    QStringList interfaces;
    interfaces.reserve(endpoints.size());
    for (const QString &ip : endpoints)
    {
        if (ip.isEmpty())
        {
            interfaces << u"0.0.0.0:%1"_s.arg(portValue) << u"[::]:%1"_s.arg(portValue);
        }
        else
        {
            const QHostAddress addr {ip};
            const QString formatted = (addr.protocol() == QAbstractSocket::IPv6Protocol)
                    ? u"[%1]:%2"_s.arg(ip).arg(portValue) : u"%1:%2"_s.arg(ip).arg(portValue);
            interfaces << formatted;
        }
    }

    settingsPack.set_str(lt::settings_pack::listen_interfaces, interfaces.join(u',').toStdString());
    m_listenInterfaceConfigured = true;
}

QStringList SessionImpl::getListeningIPs() const
{
    const QString ifaceAddress = networkInterfaceAddress();
    if (ifaceAddress.isEmpty())
        return {{}};

    return {ifaceAddress};
}

void SessionImpl::configureListeningInterface()
{
    m_listenInterfaceConfigured = false;
    configureDeferred();
}

void SessionImpl::initMetrics()
{
    const auto findMetricIndex = [](const char *name) -> int
    {
        return lt::find_metric_idx(name);
    };

    m_metricIndices.net.hasIncomingConnections = findMetricIndex("net.has_incoming_connections");
    m_metricIndices.net.sentPayloadBytes = findMetricIndex("net.sent_payload_bytes");
    m_metricIndices.net.recvPayloadBytes = findMetricIndex("net.recv_payload_bytes");
    m_metricIndices.net.sentBytes = findMetricIndex("net.sent_bytes");
    m_metricIndices.net.recvBytes = findMetricIndex("net.recv_bytes");
    m_metricIndices.net.sentIPOverheadBytes = findMetricIndex("net.sent_ip_overhead_bytes");
    m_metricIndices.net.recvIPOverheadBytes = findMetricIndex("net.recv_ip_overhead_bytes");
    m_metricIndices.net.sentTrackerBytes = findMetricIndex("net.sent_tracker_bytes");
    m_metricIndices.net.recvTrackerBytes = findMetricIndex("net.recv_tracker_bytes");
    m_metricIndices.net.recvRedundantBytes = findMetricIndex("net.recv_redundant_bytes");
    m_metricIndices.net.recvFailedBytes = findMetricIndex("net.recv_failed_bytes");
    m_metricIndices.peer.numPeersConnected = findMetricIndex("peer.num_peers_connected");
    m_metricIndices.peer.numPeersUpDisk = findMetricIndex("peer.num_peers_up_disk");
    m_metricIndices.peer.numPeersDownDisk = findMetricIndex("peer.num_peers_down_disk");
    m_metricIndices.dht.dhtBytesIn = findMetricIndex("dht.dht_bytes_in");
    m_metricIndices.dht.dhtBytesOut = findMetricIndex("dht.dht_bytes_out");
    m_metricIndices.dht.dhtNodes = findMetricIndex("dht.dht_nodes");
    m_metricIndices.disk.diskBlocksInUse = findMetricIndex("disk.disk_blocks_in_use");
    m_metricIndices.disk.numBlocksRead = findMetricIndex("disk.num_blocks_read");
    m_metricIndices.disk.writeJobs = findMetricIndex("disk.num_write_ops");
    m_metricIndices.disk.readJobs = findMetricIndex("disk.num_read_ops");
    m_metricIndices.disk.hashJobs = findMetricIndex("disk.num_blocks_hashed");
    m_metricIndices.disk.queuedDiskJobs = findMetricIndex("disk.queued_disk_jobs");
    m_metricIndices.disk.diskJobTime = findMetricIndex("disk.disk_job_time");
    m_metricIndices.tracker.numQueuedTrackerAnnounces = findMetricIndex("tracker.num_queued_tracker_announces");
}

void SessionImpl::configureComponents()
{
    configurePeerClasses();
}

void SessionImpl::configurePeerClasses()
{
    // TODO(engine): set up libtorrent peer classes for LAN / privileged-port
    // filtering. Not required for the common transfer flows.
}

void SessionImpl::prepareStartup()
{
    qCInfo(lcSession) << "Preparing session startup";

    // NOTE(engine): torrents are restored in whatever order the resume store
    // enumerates them (currently not the original queue order -- queue order
    // itself isn't persisted yet either; see the TODO on saveTorrentsQueue()).
    const QList<TorrentID> storedIds = m_resumeDataStorage
            ? m_resumeDataStorage->torrentIds() : QList<TorrentID>();

    int restoredCount = 0;
    for (const TorrentID &id : storedIds)
    {
        LoadTorrentParams loadTorrentParams;
        if (!m_resumeDataStorage->load(id, &loadTorrentParams))
        {
            qCWarning(lcSession) << "Skipping unreadable stored torrent" << id.toString();
            continue;
        }

        lt::add_torrent_params &p = loadTorrentParams.ltAddTorrentParams;
        p.flags |= lt::torrent_flags::update_subscribe;
        p.flags |= lt::torrent_flags::duplicate_is_error;

        // meta.json's savePath is authoritative for where the torrent lives;
        // re-apply it over the resume blob in case the two ever disagree
        // (e.g. a checkpoint that failed between its two file writes).
        if (!loadTorrentParams.savePath.isEmpty())
            p.save_path = loadTorrentParams.savePath.toString().toStdString();

        // Known-before-loaded: duplicate adds racing the restore must hit the
        // friendly isKnownTorrent() rejection, not libtorrent's silent error.
        m_restoringTorrents.insert(id);

        // Register a handler to create the TorrentImpl once libtorrent confirms
        // the add. The stored ltAddTorrentParams already carries piece-verified
        // resume state, so this does not trigger a full recheck.
        m_addTorrentAlertHandlers.append([this, id, loadTorrentParams](const lt::add_torrent_alert *alert) mutable
        {
            m_restoringTorrents.remove(id);

            if (alert->error)
            {
                qCWarning(lcSession) << "Failed to restore torrent:"
                                     << QString::fromStdString(alert->error.message());
                return;
            }

            TorrentImpl *torrent = createTorrent(alert->handle, std::move(loadTorrentParams));
            m_loadedTorrents.append(torrent);
            emit torrentAdded(torrent);
            qCInfo(lcSession) << "Torrent restored:" << torrent->name();
        });

        m_nativeSession->async_add_torrent(p);
        ++restoredCount;
    }

    if (restoredCount > 0)
        qCInfo(lcSession) << "Restoring" << restoredCount << "torrent(s) from the resume data store";

    m_isRestored = true;
    emit startupProgressUpdated(100);
    emit restored();
}

// --- Configuration deferral --------------------------------------------------

void SessionImpl::configureDeferred()
{
    if (m_deferredConfigureScheduled)
        return;

    m_deferredConfigureScheduled = true;
    QMetaObject::invokeMethod(this, qOverload<>(&SessionImpl::configure), Qt::QueuedConnection);
}

void SessionImpl::configure()
{
    qCDebug(lcSession) << "Applying deferred session configuration";
    lt::settings_pack pack = loadLTSettings();
    m_nativeSession->apply_settings(std::move(pack));
    configureComponents();
    m_deferredConfigureScheduled = false;
}

// --- Alert loop --------------------------------------------------------------

void SessionImpl::readAlerts()
{
    fetchPendingAlerts();

    Q_ASSERT(m_loadedTorrents.isEmpty());
    Q_ASSERT(m_receivedAddTorrentAlertsCount == 0);

    m_loadedTorrents.reserve(m_alerts.size());

    for (const lt::alert *alert : m_alerts)
        handleAlert(const_cast<lt::alert *>(alert));

    if (m_receivedAddTorrentAlertsCount > 0)
    {
        emit addTorrentAlertsReceived(m_receivedAddTorrentAlertsCount);
        m_receivedAddTorrentAlertsCount = 0;

        if (!m_loadedTorrents.isEmpty())
        {
            emit torrentsLoaded(m_loadedTorrents);
            m_loadedTorrents.clear();
        }
    }

    processPendingFinishedTorrents();
}

void SessionImpl::fetchPendingAlerts(const lt::time_duration time)
{
    if (time > lt::time_duration::zero())
        m_nativeSession->wait_for_alert(time);

    m_alerts.clear();
    m_nativeSession->pop_alerts(&m_alerts);
}

void SessionImpl::handleAlert(lt::alert *alert)
{
    try
    {
        switch (alert->type())
        {
        case lt::add_torrent_alert::alert_type:
            handleAddTorrentAlert(static_cast<lt::add_torrent_alert *>(alert));
            break;
        case lt::state_update_alert::alert_type:
            handleStateUpdateAlert(static_cast<lt::state_update_alert *>(alert));
            break;
        case lt::metadata_received_alert::alert_type:
            handleMetadataReceivedAlert(static_cast<lt::metadata_received_alert *>(alert));
            break;
        case lt::file_error_alert::alert_type:
            handleFileErrorAlert(static_cast<lt::file_error_alert *>(alert));
            break;
        case lt::torrent_removed_alert::alert_type:
            handleTorrentRemovedAlert(static_cast<lt::torrent_removed_alert *>(alert));
            break;
        case lt::torrent_deleted_alert::alert_type:
            handleTorrentDeletedAlert(static_cast<lt::torrent_deleted_alert *>(alert));
            break;
        case lt::torrent_delete_failed_alert::alert_type:
            handleTorrentDeleteFailedAlert(static_cast<lt::torrent_delete_failed_alert *>(alert));
            break;
        case lt::torrent_finished_alert::alert_type:
            handleTorrentFinishedAlert(static_cast<lt::torrent_finished_alert *>(alert));
            break;
        case lt::torrent_checked_alert::alert_type:
            handleTorrentCheckedAlert(static_cast<lt::torrent_checked_alert *>(alert));
            break;
        case lt::save_resume_data_alert::alert_type:
            handleSaveResumeDataAlert(static_cast<lt::save_resume_data_alert *>(alert));
            break;
        case lt::save_resume_data_failed_alert::alert_type:
            handleSaveResumeDataFailedAlert(static_cast<lt::save_resume_data_failed_alert *>(alert));
            break;
        case lt::fastresume_rejected_alert::alert_type:
            handleFastResumeRejectedAlert(static_cast<lt::fastresume_rejected_alert *>(alert));
            break;
        case lt::file_renamed_alert::alert_type:
            handleFileRenamedAlert(static_cast<lt::file_renamed_alert *>(alert));
            break;
        case lt::file_rename_failed_alert::alert_type:
            handleFileRenameFailedAlert(static_cast<lt::file_rename_failed_alert *>(alert));
            break;
        case lt::file_completed_alert::alert_type:
            handleFileCompletedAlert(static_cast<lt::file_completed_alert *>(alert));
            break;
        case lt::storage_moved_alert::alert_type:
            handleStorageMovedAlert(static_cast<lt::storage_moved_alert *>(alert));
            break;
        case lt::storage_moved_failed_alert::alert_type:
            handleStorageMovedFailedAlert(static_cast<lt::storage_moved_failed_alert *>(alert));
            break;
        case lt::performance_alert::alert_type:
            handlePerformanceAlert(static_cast<lt::performance_alert *>(alert));
            break;
        case lt::tracker_error_alert::alert_type:
        case lt::tracker_reply_alert::alert_type:
        case lt::tracker_warning_alert::alert_type:
            handleTrackerAlert(static_cast<lt::tracker_alert *>(alert));
            break;
        case lt::listen_succeeded_alert::alert_type:
            handleListenSucceededAlert(static_cast<lt::listen_succeeded_alert *>(alert));
            break;
        case lt::listen_failed_alert::alert_type:
            handleListenFailedAlert(static_cast<lt::listen_failed_alert *>(alert));
            break;
        case lt::external_ip_alert::alert_type:
            handleExternalIPAlert(static_cast<lt::external_ip_alert *>(alert));
            break;
        case lt::session_stats_alert::alert_type:
            handleSessionStatsAlert(static_cast<lt::session_stats_alert *>(alert));
            break;
        case lt::session_error_alert::alert_type:
            handleSessionErrorAlert(static_cast<lt::session_error_alert *>(alert));
            break;
        case lt::peer_blocked_alert::alert_type:
            handlePeerBlockedAlert(static_cast<lt::peer_blocked_alert *>(alert));
            break;
        case lt::peer_ban_alert::alert_type:
            handlePeerBanAlert(static_cast<lt::peer_ban_alert *>(alert));
            break;
        case lt::url_seed_alert::alert_type:
            handleUrlSeedAlert(static_cast<lt::url_seed_alert *>(alert));
            break;
        default:
            break;
        }
    }
    catch (const std::exception &exc)
    {
        qCWarning(lcSession) << "Caught exception in alert handler:" << exc.what();
    }
}

void SessionImpl::handleAddTorrentAlert(const lt::add_torrent_alert *alert)
{
    ++m_receivedAddTorrentAlertsCount;

    if (alert->error)
    {
        qCWarning(lcSession) << "Failed to add torrent:" << QString::fromStdString(alert->error.message());
        if (!m_addTorrentAlertHandlers.isEmpty())
            m_addTorrentAlertHandlers.takeFirst()(alert);
        return;
    }

    if (!m_addTorrentAlertHandlers.isEmpty())
    {
        m_addTorrentAlertHandlers.takeFirst()(alert);
    }
    else
    {
        // Torrent restored from resume data at startup, or added elsewhere.
        qCDebug(lcSession) << "add_torrent_alert received for" << QString::fromStdString(alert->handle.status(lt::torrent_handle::query_name).name);
    }
}

void SessionImpl::handleStateUpdateAlert(const lt::state_update_alert *alert)
{
    QList<Torrent *> updatedTorrents;
    updatedTorrents.reserve(static_cast<decltype(updatedTorrents)::size_type>(alert->status.size()));

    for (const lt::torrent_status &status : alert->status)
    {
        TorrentImpl *torrent = getTorrent(status.handle);
        if (!torrent)
            continue;

        torrent->handleStateUpdate(status);
        updatedTorrents.append(torrent);
    }

    if (!updatedTorrents.isEmpty())
        emit torrentsUpdated(updatedTorrents);

    if (m_refreshEnqueued)
        m_refreshEnqueued = false;
    else
        enqueueRefresh();
}

void SessionImpl::handleMetadataReceivedAlert(const lt::metadata_received_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
        torrent->handleMetadataReceived();
}

void SessionImpl::handleFileErrorAlert(const lt::file_error_alert *alert)
{
    TorrentImpl *torrent = getTorrent(alert->handle);
    if (!torrent)
        return;

    torrent->handleFileError({alert->error, alert->op});

    const TorrentID id = torrent->id();
    if (!m_recentErroredTorrents.contains(id))
    {
        m_recentErroredTorrents.insert(id);

        const QString msg = QString::fromStdString(alert->message());
        qCWarning(lcSession) << "File error on torrent" << torrent->name() << ':' << msg;
        emit torrentIOError(torrent, msg);
    }

    m_recentErroredTorrentsTimer->start();
}

void SessionImpl::handleTorrentFinishedAlert(const lt::torrent_finished_alert *alert)
{
    TorrentImpl *torrent = getTorrent(alert->handle);
    if (!torrent)
        return;

    qCInfo(lcSession) << "Torrent finished:" << torrent->name();
    torrent->handleTorrentFinished();

    if (!m_pendingFinishedTorrents.contains(torrent))
        m_pendingFinishedTorrents.append(torrent);
}

void SessionImpl::processPendingFinishedTorrents()
{
    if (m_pendingFinishedTorrents.isEmpty())
        return;

    for (TorrentImpl *torrent : asConst(m_pendingFinishedTorrents))
    {
        emit torrentFinished(torrent);
        exportTorrentFile(torrent, finishedTorrentExportDirectory());
    }
    m_pendingFinishedTorrents.clear();

    const bool allFinished = std::all_of(m_torrents.cbegin(), m_torrents.cend()
            , [](const TorrentImpl *torrent) { return torrent->isFinished(); });
    if (allFinished)
        emit allTorrentsFinished();
}

void SessionImpl::handleTorrentCheckedAlert(const lt::torrent_checked_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
    {
        torrent->handleTorrentChecked();
        emit torrentFinishedChecking(torrent);
    }
}

void SessionImpl::handleFileCompletedAlert(const lt::file_completed_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
        torrent->handleFileCompleted(alert->index);
}

void SessionImpl::handleFileRenamedAlert(const lt::file_renamed_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
    {
        torrent->handleFileRenamed(alert->index, Path(QString::fromUtf8(alert->new_name()))
                , Path(QString::fromUtf8(alert->old_name())));
    }
}

void SessionImpl::handleFileRenameFailedAlert(const lt::file_rename_failed_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
        torrent->handleFileRenameFailed(alert->index);
}

void SessionImpl::handleFastResumeRejectedAlert(const lt::fastresume_rejected_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
    {
        qCWarning(lcSession) << "Fast resume rejected for" << torrent->name() << ':'
                             << QString::fromStdString(alert->message());
        torrent->handleFastResumeRejected();
    }
}

void SessionImpl::handleSaveResumeDataAlert(lt::save_resume_data_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
        torrent->handleSaveResumeData(std::move(alert->params));

    --m_numResumeData;
}

void SessionImpl::handleSaveResumeDataFailedAlert(const lt::save_resume_data_failed_alert *alert)
{
    Q_UNUSED(alert);
    --m_numResumeData;
    qCWarning(lcSession) << "Save resume data failed:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleStorageMovedAlert(const lt::storage_moved_alert *alert)
{
    Q_ASSERT(!m_moveStorageQueue.isEmpty());
    const MoveStorageJob &currentJob = m_moveStorageQueue.first();
    Q_ASSERT(currentJob.torrentHandle == alert->handle);

    const Path newPath {QString::fromUtf8(alert->storage_path())};
    qCDebug(lcSession) << "Storage moved to" << newPath.data();
    handleMoveTorrentStorageJobFinished(newPath);
}

void SessionImpl::handleStorageMovedFailedAlert(const lt::storage_moved_failed_alert *alert)
{
    Q_ASSERT(!m_moveStorageQueue.isEmpty());
    const MoveStorageJob &currentJob = m_moveStorageQueue.first();
    Q_ASSERT(currentJob.torrentHandle == alert->handle);

    qCWarning(lcSession) << "Storage move failed:" << QString::fromStdString(alert->message());
    handleMoveTorrentStorageJobFinished(Path(currentJob.torrentHandle.status(lt::torrent_handle::query_save_path).save_path));
}

void SessionImpl::handleMoveTorrentStorageJobFinished(const Path &newPath)
{
    const MoveStorageJob finishedJob = m_moveStorageQueue.takeFirst();

    if (!m_moveStorageQueue.isEmpty())
        moveTorrentStorage(m_moveStorageQueue.first());

    const bool hasOutstandingJob = std::any_of(m_moveStorageQueue.cbegin(), m_moveStorageQueue.cend()
            , [&finishedJob](const MoveStorageJob &job) { return job.torrentHandle == finishedJob.torrentHandle; });

    if (TorrentImpl *torrent = getTorrent(finishedJob.torrentHandle))
        torrent->handleMoveStorageJobFinished(newPath, finishedJob.context, hasOutstandingJob);
}

void SessionImpl::handlePerformanceAlert(const lt::performance_alert *alert) const
{
    qCWarning(lcSession) << "Performance alert:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleTrackerAlert(const lt::tracker_alert *alert)
{
    TorrentImpl *torrent = getTorrent(alert->handle);
    if (!torrent)
        return;

    const QString trackerURL = QString::fromStdString(alert->tracker_url());

    switch (alert->type())
    {
    case lt::tracker_reply_alert::alert_type:
        emit trackerSuccess(torrent, trackerURL);
        break;
    case lt::tracker_warning_alert::alert_type:
        emit trackerWarning(torrent, trackerURL);
        break;
    case lt::tracker_error_alert::alert_type:
        emit trackerError(torrent, trackerURL);
        break;
    default:
        break;
    }

    updateTrackerEntryStatuses(alert->handle);
}

void SessionImpl::updateTrackerEntryStatuses(lt::torrent_handle torrentHandle)
{
    // TODO(engine): merge the per-endpoint tracker announce info accumulated in
    // m_updatedTrackerStatuses into the TorrentImpl tracker statuses on the IO thread.
    invoke([this, torrentHandle = std::move(torrentHandle)]()
    {
        TorrentImpl *torrent = getTorrent(torrentHandle);
        if (!torrent)
            return;

        QHash<QString, TrackerEntryStatus> updated;
        for (const lt::announce_entry &entry : torrentHandle.trackers())
        {
            const TrackerEntryStatus status = torrent->updateTrackerEntryStatus(entry, {});
            updated.insert(status.url, status);
        }

        if (!updated.isEmpty())
            emit trackerEntryStatusesUpdated(torrent, updated);
    });
}

void SessionImpl::handleListenSucceededAlert(const lt::listen_succeeded_alert *alert)
{
    qCInfo(lcSession) << "Successfully listening on" << QString::fromStdString(alert->address.to_string())
                      << ':' << alert->port << '(' << toString(alert->socket_type) << ')';
}

void SessionImpl::handleListenFailedAlert(const lt::listen_failed_alert *alert)
{
    qCWarning(lcSession) << "Failed to listen on" << QString::fromStdString(alert->address.to_string())
                         << ':' << alert->port << '-' << QString::fromStdString(alert->message());
}

void SessionImpl::handleExternalIPAlert(const lt::external_ip_alert *alert)
{
    const QString externalIP = QString::fromStdString(alert->external_address.to_string());
    qCInfo(lcSession) << "Detected external IP:" << externalIP;

    if (alert->external_address.is_v4())
        m_lastExternalIPv4Address = externalIP;
    else
        m_lastExternalIPv6Address = externalIP;
}

void SessionImpl::handleSessionErrorAlert(const lt::session_error_alert *alert) const
{
    qCCritical(lcSession) << "Session error:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleSessionStatsAlert(const lt::session_stats_alert *alert)
{
    const lt::span<const int64_t> stats = alert->counters();
    const auto getStat = [&stats](const int idx) -> qint64
    {
        return (idx >= 0) ? stats[idx] : 0;
    };

    const lt::time_point now = alert->timestamp();
    const qreal interval = lt::total_milliseconds(now - m_statsLastTimestamp) / 1000.;
    m_statsLastTimestamp = now;

    const auto calcRate = [interval](const qint64 previous, const qint64 current) -> qint64
    {
        if (interval <= 0)
            return 0;
        return static_cast<qint64>((current - previous) / interval);
    };

    SessionStatus &status = m_status;
    status.payloadDownloadRate = calcRate(status.totalPayloadDownload, getStat(m_metricIndices.net.recvPayloadBytes));
    status.payloadUploadRate = calcRate(status.totalPayloadUpload, getStat(m_metricIndices.net.sentPayloadBytes));
    status.downloadRate = calcRate(status.totalDownload, getStat(m_metricIndices.net.recvBytes));
    status.uploadRate = calcRate(status.totalUpload, getStat(m_metricIndices.net.sentBytes));

    status.totalPayloadDownload = getStat(m_metricIndices.net.recvPayloadBytes);
    status.totalPayloadUpload = getStat(m_metricIndices.net.sentPayloadBytes);
    status.totalDownload = getStat(m_metricIndices.net.recvBytes);
    status.totalUpload = getStat(m_metricIndices.net.sentBytes);
    status.totalWasted = getStat(m_metricIndices.net.recvRedundantBytes) + getStat(m_metricIndices.net.recvFailedBytes);
    status.dhtNodes = getStat(m_metricIndices.dht.dhtNodes);
    status.peersCount = getStat(m_metricIndices.peer.numPeersConnected);
    status.hasIncomingConnections = (getStat(m_metricIndices.net.hasIncomingConnections) > 0);
    status.queuedTrackerAnnounces = getStat(m_metricIndices.tracker.numQueuedTrackerAnnounces);

    m_isStatisticsDirty = true;
    emit statsUpdated();
}

void SessionImpl::handleAlertsDroppedAlert(const lt::alerts_dropped_alert *alert) const
{
    qCWarning(lcSession) << "Alerts dropped:" << QString::fromStdString(alert->message());
}

void SessionImpl::handlePeerBlockedAlert(const lt::peer_blocked_alert *alert)
{
    const QString ip = QString::fromStdString(alert->endpoint.address().to_string());
    qCDebug(lcSession) << "Peer blocked:" << ip;
}

void SessionImpl::handlePeerBanAlert(const lt::peer_ban_alert *alert)
{
    const QString ip = QString::fromStdString(alert->endpoint.address().to_string());
    qCInfo(lcSession) << "Peer banned:" << ip;
}

void SessionImpl::handleUrlSeedAlert(const lt::url_seed_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
    {
        qCWarning(lcSession) << "URL seed error for" << torrent->name() << ':'
                             << QString::fromStdString(alert->message());
    }
}

void SessionImpl::handleTorrentRemovedAlert(const lt::torrent_removed_alert *alert)
{
    const auto infoHash = InfoHash(alert->info_hashes);
    const TorrentID torrentID = infoHash.toTorrentID();
    if (const auto it = m_removingTorrents.find(torrentID); it != m_removingTorrents.end())
    {
        if (it->removeOption == TorrentRemoveOption::KeepContent)
            handleRemovedTorrent(torrentID);
    }
}

void SessionImpl::handleTorrentDeletedAlert(const lt::torrent_deleted_alert *alert)
{
    const auto infoHash = InfoHash(alert->info_hashes);
    const TorrentID torrentID = infoHash.toTorrentID();
    handleRemovedTorrent(torrentID);
}

void SessionImpl::handleTorrentDeleteFailedAlert(const lt::torrent_delete_failed_alert *alert)
{
    const auto infoHash = InfoHash(alert->info_hashes);
    const TorrentID torrentID = infoHash.toTorrentID();
    const QString errorMsg = QString::fromStdString(alert->error.message());
    qCWarning(lcSession) << "Failed to delete torrent content for" << torrentID.toString() << ':' << errorMsg;
    handleRemovedTorrent(torrentID, errorMsg);
}

void SessionImpl::handleTorrentNeedCertAlert(const lt::torrent_need_cert_alert *alert)
{
    if (TorrentImpl *torrent = getTorrent(alert->handle))
        torrent->applySSLParameters();
}

void SessionImpl::handlePortmapWarningAlert(const lt::portmap_error_alert *alert)
{
    qCWarning(lcSession) << "UPnP/NAT-PMP error:" << QString::fromStdString(alert->message());
}

void SessionImpl::handlePortmapAlert(const lt::portmap_alert *alert)
{
    qCDebug(lcSession) << "UPnP/NAT-PMP:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleSocks5Alert(const lt::socks5_alert *alert) const
{
    if (alert->error)
        qCWarning(lcSession) << "SOCKS5 error:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleI2PAlert(const lt::i2p_alert *alert) const
{
    if (alert->error)
        qCWarning(lcSession) << "I2P error:" << QString::fromStdString(alert->message());
}

#ifdef QBT_USES_LIBTORRENT2
void SessionImpl::handleTorrentConflictAlert(const lt::torrent_conflict_alert *alert)
{
    qCWarning(lcSession) << "Torrent conflict:" << QString::fromStdString(alert->message());
}

void SessionImpl::handleFilePrioAlert(const lt::file_prio_alert *alert)
{
    Q_UNUSED(alert);
}
#endif

void SessionImpl::enqueueRefresh()
{
    Q_ASSERT(!m_refreshEnqueued);

    QTimer::singleShot(refreshInterval(), this, [this]()
    {
        // Clear the flag as the scheduled refresh fires, so the resulting
        // state_update_alert re-enqueues the next cycle and the loop
        // self-sustains (see handleStateUpdateAlert).
        m_refreshEnqueued = false;
        if (m_nativeSession)
        {
            m_nativeSession->post_torrent_updates();
            m_nativeSession->post_session_stats();
        }
    });

    m_refreshEnqueued = true;
}

void SessionImpl::endAlertSequence(int alertType, qsizetype alertCount)
{
    Q_UNUSED(alertType);
    Q_UNUSED(alertCount);
}

// --- Torrent lookup ----------------------------------------------------------

Torrent *SessionImpl::getTorrent(const TorrentID &id) const
{
    return m_torrents.value(id);
}

TorrentImpl *SessionImpl::getTorrent(const lt::torrent_handle &nativeHandle) const
{
    return m_torrents.value(TorrentID::fromInfoHash(nativeHandle.info_hashes()));
}

Torrent *SessionImpl::findTorrent(const InfoHash &infoHash) const
{
    const TorrentID id = TorrentID::fromInfoHash(infoHash);
    if (TorrentImpl *torrent = m_torrents.value(id))
        return torrent;

    if (!infoHash.isHybrid())
        return m_hybridTorrentsByAltID.value(id);

    if (TorrentImpl *torrent = m_torrents.value(TorrentID::fromSHA1Hash(infoHash.v1())))
        return torrent;

    return m_torrents.value(TorrentID::fromSHA256Hash(infoHash.v2()));
}

QList<Torrent *> SessionImpl::torrents() const
{
    QList<Torrent *> result;
    result.reserve(m_torrents.size());
    for (TorrentImpl *torrent : asConst(m_torrents))
        result << torrent;

    return result;
}

qsizetype SessionImpl::torrentsCount() const
{
    return m_torrents.size();
}

bool SessionImpl::isKnownTorrent(const InfoHash &infoHash) const
{
    // Torrents queued for restore in prepareStartup() are known before their
    // add_torrent_alert lands in m_torrents -- without this, a duplicate add
    // in that window slips past the check and fails silently in libtorrent.
    const TorrentID id = infoHash.toTorrentID();
    if (m_restoringTorrents.contains(id))
        return true;
    if (infoHash.isHybrid() && m_restoringTorrents.contains(TorrentID::fromSHA1Hash(infoHash.v1())))
        return true;
    return (findTorrent(infoHash) != nullptr);
}

QList<TorrentImpl *> SessionImpl::getQueuedTorrentsByID(const QList<TorrentID> &torrentIDs) const
{
    QList<TorrentImpl *> result;
    result.reserve(torrentIDs.size());
    for (const TorrentID &id : torrentIDs)
    {
        if (TorrentImpl *torrent = m_torrents.value(id); torrent && !torrent->isStopped())
            result.append(torrent);
    }
    return result;
}

// --- Add / remove torrents ---------------------------------------------------

bool SessionImpl::addTorrent(const TorrentDescriptor &torrentDescr, const AddTorrentParams &params)
{
    if (!isRestored())
        return false;

    qCInfo(lcSession) << "Adding torrent:" << torrentDescr.name();
    return addTorrent_impl(torrentDescr, params);
}

bool SessionImpl::addTorrent_impl(const TorrentDescriptor &source, const AddTorrentParams &addTorrentParams)
{
    Q_ASSERT(isRestored());

    const bool hasMetadata = source.info().has_value();
    const InfoHash infoHash = source.infoHash();

    if (!infoHash.isValid())
    {
        qCWarning(lcSession) << "Cannot add torrent: invalid info hash";
        emit addTorrentFailed(infoHash, {AddTorrentError::Kind::Other, tr("Invalid info hash.")});
        return false;
    }

    if (isKnownTorrent(infoHash))
    {
        qCWarning(lcSession) << "Torrent already present in session:" << infoHash.toString();
        // TODO(engine): merge trackers/URL seeds into the existing torrent when
        // merge-trackers is enabled instead of rejecting the duplicate.
        emit addTorrentFailed(infoHash, {AddTorrentError::Kind::DuplicateTorrent, tr("Torrent is already present.")});
        return false;
    }

    LoadTorrentParams loadTorrentParams = initLoadTorrentParams(addTorrentParams);
    lt::add_torrent_params &p = loadTorrentParams.ltAddTorrentParams;
    p = source.ltAddTorrentParams();

    if (hasMetadata)
    {
        p.ti = source.info()->nativeInfo();
    }

    const bool useAutoTMM = loadTorrentParams.useAutoTMM;
    const Path savePath = useAutoTMM
            ? categorySavePath(loadTorrentParams.category) : loadTorrentParams.savePath;
    p.save_path = savePath.toString().toStdString();

    p.flags |= lt::torrent_flags::update_subscribe;
    p.flags |= lt::torrent_flags::duplicate_is_error;
    if (loadTorrentParams.stopped)
        p.flags |= lt::torrent_flags::paused;
    else
        p.flags &= ~lt::torrent_flags::paused;

    if (loadTorrentParams.operatingMode == TorrentOperatingMode::AutoManaged)
        p.flags |= lt::torrent_flags::auto_managed;
    else
        p.flags &= ~lt::torrent_flags::auto_managed;

    // Register a handler to create the TorrentImpl once libtorrent confirms the add.
    m_addTorrentAlertHandlers.append([this, loadTorrentParams](const lt::add_torrent_alert *alert) mutable
    {
        if (alert->error)
            return;

        TorrentImpl *torrent = createTorrent(alert->handle, std::move(loadTorrentParams));
        m_loadedTorrents.append(torrent);
        emit torrentAdded(torrent);
        qCInfo(lcSession) << "Torrent added:" << torrent->name();
    });

    m_nativeSession->async_add_torrent(p);
    return true;
}

LoadTorrentParams SessionImpl::initLoadTorrentParams(const AddTorrentParams &addTorrentParams)
{
    LoadTorrentParams loadTorrentParams;

    loadTorrentParams.name = addTorrentParams.name;
    loadTorrentParams.tags = addTorrentParams.tags;
    loadTorrentParams.firstLastPiecePriority = addTorrentParams.firstLastPiecePriority;
    loadTorrentParams.contentLayout = addTorrentParams.contentLayout.value_or(torrentContentLayout());
    loadTorrentParams.operatingMode = addTorrentParams.addForced
            ? TorrentOperatingMode::Forced : TorrentOperatingMode::AutoManaged;
    loadTorrentParams.stopped = addTorrentParams.addStopped.value_or(isAddTorrentStopped());
    loadTorrentParams.stopCondition = addTorrentParams.stopCondition.value_or(torrentStopCondition());
    loadTorrentParams.shareLimits = addTorrentParams.shareLimits;
    loadTorrentParams.sslParameters = addTorrentParams.sslParameters;

    const QString category = addTorrentParams.category;
    if (!category.isEmpty() && !m_categories.contains(category) && !addCategory(category))
        loadTorrentParams.category = u""_s;
    else
        loadTorrentParams.category = category;

    const bool useAutoTMM = addTorrentParams.useAutoTMM.value_or(
            !isAutoTMMDisabledByDefault() && !addTorrentParams.savePath.isAbsolute());
    loadTorrentParams.useAutoTMM = useAutoTMM;

    if (useAutoTMM)
    {
        loadTorrentParams.savePath = {};
        loadTorrentParams.downloadPath = {};
    }
    else
    {
        loadTorrentParams.savePath = addTorrentParams.savePath.isEmpty()
                ? savePath() : addTorrentParams.savePath;
        const bool useDownloadPath = addTorrentParams.useDownloadPath.value_or(isDownloadPathEnabled());
        loadTorrentParams.downloadPath = useDownloadPath
                ? (addTorrentParams.downloadPath.isEmpty() ? downloadPath() : addTorrentParams.downloadPath)
                : Path();
    }

    return loadTorrentParams;
}

TorrentImpl *SessionImpl::createTorrent(const lt::torrent_handle &nativeHandle, LoadTorrentParams params)
{
    auto *const torrent = new TorrentImpl(this, nativeHandle, std::move(params));
    m_torrents.insert(torrent->id(), torrent);
    if (const InfoHash infoHash = torrent->infoHash(); infoHash.isHybrid())
        m_hybridTorrentsByAltID.insert(TorrentID::fromSHA1Hash(infoHash.v1()), torrent);

    if (isAddTorrentToQueueTop())
        nativeHandle.queue_position_top();

    torrent->requestResumeData(lt::torrent_handle::save_info_dict);

    if (!m_seedingLimitTimer->isActive())
        m_seedingLimitTimer->start();

    return torrent;
}

bool SessionImpl::removeTorrent(const TorrentID &id, const TorrentRemoveOption deleteOption)
{
    TorrentImpl *torrent = m_torrents.value(id);
    if (!torrent)
        return false;

    qCInfo(lcSession) << "Removing torrent" << torrent->name()
                      << "deleteContent:" << (deleteOption == TorrentRemoveOption::RemoveContent);

    emit torrentAboutToBeRemoved(torrent, deleteOption);

    m_torrents.remove(id);
    if (const InfoHash infoHash = torrent->infoHash(); infoHash.isHybrid())
        m_hybridTorrentsByAltID.remove(TorrentID::fromSHA1Hash(infoHash.v1()));

    RemovingTorrentData &removingTorrentData = m_removingTorrents[id];
    removingTorrentData.name = torrent->name();
    removingTorrentData.removeOption = deleteOption;
    removingTorrentData.contentStoragePath = torrent->actualStorageLocation();
    removingTorrentData.fileNames = torrent->actualFilePaths();

    const lt::torrent_handle nativeHandle = torrent->nativeHandle();
    if (deleteOption == TorrentRemoveOption::KeepContent)
        m_nativeSession->remove_torrent(nativeHandle, lt::session::delete_partfile);
    else
        m_nativeSession->remove_torrent(nativeHandle, lt::session::delete_files);

    if (m_resumeDataStorage && !m_resumeDataStorage->remove(id))
    {
        qCWarning(lcSession) << "Failed to erase stored resume data for" << id.toString()
                             << "-- the torrent may reappear on next startup";
    }

    delete torrent;
    emit torrentRemoved(id);
    return true;
}

void SessionImpl::handleRemovedTorrent(const TorrentID &torrentID, const QString &partfileRemoveError)
{
    const auto it = m_removingTorrents.find(torrentID);
    if (it == m_removingTorrents.end())
        return;

    if (!partfileRemoveError.isEmpty())
    {
        qCWarning(lcSession) << "Failed to remove torrent content:" << it->name << partfileRemoveError;
    }
    else
    {
        qCInfo(lcSession) << "Torrent removed:" << it->name;
    }

    m_removingTorrents.erase(it);
}

bool SessionImpl::downloadMetadata(const TorrentDescriptor &torrentDescr)
{
    const InfoHash infoHash = torrentDescr.infoHash();
    if (!infoHash.isValid() || torrentDescr.info().has_value())
        return false;

    if (isKnownTorrent(infoHash))
        return false;

    qCInfo(lcSession) << "Downloading metadata for" << infoHash.toString();

    lt::add_torrent_params p = torrentDescr.ltAddTorrentParams();
    p.save_path = Utils::Fs::tempPath().toString().toStdString();
    p.flags |= lt::torrent_flags::upload_mode;
    p.flags &= ~lt::torrent_flags::paused;
    p.flags &= ~lt::torrent_flags::auto_managed;

    const TorrentID id = TorrentID::fromInfoHash(infoHash);
    m_addTorrentAlertHandlers.append([this, id](const lt::add_torrent_alert *alert)
    {
        if (!alert->error)
            m_downloadedMetadata.insert(id, alert->handle);
    });

    m_nativeSession->async_add_torrent(p);
    return true;
}

bool SessionImpl::cancelDownloadMetadata(const TorrentID &id)
{
    const auto it = m_downloadedMetadata.find(id);
    if (it == m_downloadedMetadata.end())
        return false;

    const lt::torrent_handle nativeHandle = it.value();
    m_downloadedMetadata.erase(it);
    if (nativeHandle.is_valid())
        m_nativeSession->remove_torrent(nativeHandle, lt::session::delete_files);

    qCDebug(lcSession) << "Cancelled metadata download for" << id.toString();
    return true;
}

// --- Queue operations --------------------------------------------------------

void SessionImpl::increaseTorrentsQueuePos(const QList<TorrentID> &ids)
{
    const QList<TorrentImpl *> torrents = getQueuedTorrentsByID(ids);
    for (TorrentImpl *torrent : torrents)
        torrent->nativeHandle().queue_position_up();

    m_torrentsQueueChanged = true;
    qCDebug(lcSession) << "Increased queue position of" << torrents.size() << "torrent(s)";
    saveTorrentsQueue();
}

void SessionImpl::decreaseTorrentsQueuePos(const QList<TorrentID> &ids)
{
    const QList<TorrentImpl *> torrents = getQueuedTorrentsByID(ids);
    for (TorrentImpl *torrent : torrents)
        torrent->nativeHandle().queue_position_down();

    m_torrentsQueueChanged = true;
    qCDebug(lcSession) << "Decreased queue position of" << torrents.size() << "torrent(s)";
    saveTorrentsQueue();
}

void SessionImpl::topTorrentsQueuePos(const QList<TorrentID> &ids)
{
    const QList<TorrentImpl *> torrents = getQueuedTorrentsByID(ids);
    for (TorrentImpl *torrent : torrents)
        torrent->nativeHandle().queue_position_top();

    m_torrentsQueueChanged = true;
    qCDebug(lcSession) << "Moved" << torrents.size() << "torrent(s) to top of queue";
    saveTorrentsQueue();
}

void SessionImpl::bottomTorrentsQueuePos(const QList<TorrentID> &ids)
{
    const QList<TorrentImpl *> torrents = getQueuedTorrentsByID(ids);
    for (TorrentImpl *torrent : torrents)
        torrent->nativeHandle().queue_position_bottom();

    m_torrentsQueueChanged = true;
    qCDebug(lcSession) << "Moved" << torrents.size() << "torrent(s) to bottom of queue";
    saveTorrentsQueue();
}

void SessionImpl::saveTorrentsQueue()
{
    m_needSaveTorrentsQueue = true;
    // TODO(engine): persist the queue order via ResumeDataStorage.
}

void SessionImpl::removeTorrentsQueue()
{
    // TODO(engine): clear the persisted queue order.
}

// --- Move storage ------------------------------------------------------------

bool SessionImpl::addMoveTorrentStorageJob(TorrentImpl *torrent, const Path &newPath, const MoveStorageMode mode, const MoveStorageContext context)
{
    Q_ASSERT(torrent);

    const lt::torrent_handle torrentHandle = torrent->nativeHandle();

    const auto iter = std::find_if(m_moveStorageQueue.begin(), m_moveStorageQueue.end()
            , [&torrentHandle](const MoveStorageJob &job) { return job.torrentHandle == torrentHandle; });

    if (iter != m_moveStorageQueue.end())
    {
        // Fold consecutive requests: just update the target of the queued job.
        iter->path = newPath;
        iter->mode = mode;
        iter->context = context;
        return true;
    }

    const MoveStorageJob job {torrentHandle, newPath, mode, context};
    m_moveStorageQueue.append(job);
    qCDebug(lcSession) << "Enqueued move storage job for" << torrent->name() << "->" << newPath.data();

    if (m_moveStorageQueue.size() == 1)
        moveTorrentStorage(job);

    return true;
}

void SessionImpl::moveTorrentStorage(const MoveStorageJob &job) const
{
    const lt::move_flags_t flags = (job.mode == MoveStorageMode::Overwrite)
            ? lt::move_flags_t::always_replace_files
            : ((job.mode == MoveStorageMode::KeepExistingFiles)
                    ? lt::move_flags_t::dont_replace : lt::move_flags_t::fail_if_exist);

    job.torrentHandle.move_storage(job.path.toString().toStdString(), flags);
}

lt::torrent_handle SessionImpl::reloadTorrent(const lt::torrent_handle &currentHandle, lt::add_torrent_params params)
{
    // TODO(engine): synchronously remove and re-add the torrent to apply changes
    // that cannot be modified on a live handle. Structure only.
    m_nativeSession->remove_torrent(currentHandle, lt::remove_flags_t {});
    return m_nativeSession->add_torrent(std::move(params));
}

// --- Pause / resume ----------------------------------------------------------

bool SessionImpl::isPaused() const
{
    return m_isPaused;
}

void SessionImpl::pause()
{
    if (m_isPaused)
        return;

    qCInfo(lcSession) << "Pausing session";
    m_nativeSession->pause();
    m_isPaused = true;
    emit paused();
}

void SessionImpl::resume()
{
    if (!m_isPaused)
        return;

    qCInfo(lcSession) << "Resuming session";
    m_nativeSession->resume();
    m_isPaused = false;
    emit resumed();
}

bool SessionImpl::isRestored() const
{
    return m_isRestored;
}

bool SessionImpl::isListening() const
{
    return m_nativeSession && m_nativeSession->is_listening();
}

// --- Status ------------------------------------------------------------------

const SessionStatus &SessionImpl::status() const
{
    return m_status;
}

const CacheStatus &SessionImpl::cacheStatus() const
{
    return m_cacheStatus;
}

QString SessionImpl::lastExternalIPv4Address() const
{
    return m_lastExternalIPv4Address;
}

QString SessionImpl::lastExternalIPv6Address() const
{
    return m_lastExternalIPv6Address;
}

qint64 SessionImpl::freeDiskSpace() const
{
    return m_freeDiskSpace;
}

void SessionImpl::banIP(const QString &ip)
{
    QStringList bannedIPs = m_bannedIPs.get();
    if (bannedIPs.contains(ip))
        return;

    lt::error_code ec;
    const lt::address addr = lt::make_address(ip.toStdString(), ec);
    if (ec)
        return;

    lt::ip_filter filter = m_nativeSession->get_ip_filter();
    filter.add_rule(addr, addr, lt::ip_filter::blocked);
    m_nativeSession->set_ip_filter(filter);

    bannedIPs << ip;
    bannedIPs.sort();
    m_bannedIPs = bannedIPs;
    qCInfo(lcSession) << "Banned IP:" << ip;
}

// --- Resume data / statistics ------------------------------------------------

void SessionImpl::saveResumeData()
{
    // requestResumeData() increments m_numResumeData via
    // handleTorrentResumeDataRequested(); the destructor drains the counter.
    for (TorrentImpl *torrent : asConst(m_torrents))
    {
        if (torrent->needSaveResumeData())
            torrent->requestResumeData();
    }

    qCDebug(lcSession) << "Requested resume data;" << m_numResumeData << "save(s) in flight";
}

void SessionImpl::generateResumeData()
{
    for (TorrentImpl *torrent : asConst(m_torrents))
    {
        if (torrent->needSaveResumeData())
            torrent->requestResumeData();
    }
}

void SessionImpl::saveStatistics() const
{
    if (!m_isStatisticsDirty)
        return;

    SettingsStorage::instance()->storeValue(u"Stats/AllStats"_s, QVariantHash {
        {u"AlltimeDL"_s, m_status.allTimeDownload},
        {u"AlltimeUL"_s, m_status.allTimeUpload}
    });
    m_isStatisticsDirty = false;
    qCDebug(lcSession) << "Session statistics saved";
}

void SessionImpl::loadStatistics()
{
    const QVariantHash stats = SettingsStorage::instance()->loadValue<QVariant>(u"Stats/AllStats"_s).toHash();
    m_previouslyDownloaded = stats.value(u"AlltimeDL"_s).toLongLong();
    m_previouslyUploaded = stats.value(u"AlltimeUL"_s).toLongLong();
}

void SessionImpl::updateShareLimitsTimer()
{
    for (TorrentImpl *torrent : asConst(m_torrents))
    {
        if (torrent->isFinished() && !torrent->isStopped())
            processTorrentShareLimits(torrent);
    }
}

void SessionImpl::processTorrentShareLimits(TorrentImpl *torrent)
{
    // TODO(engine): evaluate ratio / seeding-time / inactive-seeding limits against
    // effectiveShareLimits() and apply the configured ShareLimitAction. Structure only.
    Q_UNUSED(torrent);
}

void SessionImpl::exportTorrentFile(const Torrent *torrent, const Path &folderPath)
{
    if (folderPath.isEmpty())
        return;

    if (!Utils::Fs::mkpath(folderPath))
        return;

    const QString validName = Utils::Fs::toValidFileName(torrent->name());
    const Path newPath = folderPath / Path(validName + u".torrent");
    const auto result = torrent->exportToFile(newPath);
    if (!result)
        qCWarning(lcSession) << "Failed to export torrent file:" << result.error();
    else
        qCDebug(lcSession) << "Exported torrent file to" << newPath.data();
}

// --- Torrent-interface handlers (forward engine events to Session signals) ---

void SessionImpl::handleTorrentResumeDataRequested(const TorrentImpl *)
{
    // Every native save_resume_data() request produces exactly one
    // save_resume_data(_failed)_alert, which decrements this counter -- so it
    // must be incremented here, on the request, to track in-flight saves
    // (the destructor's bounded drain relies on it being balanced).
    ++m_numResumeData;
}

void SessionImpl::handleTorrentNeedSaveResumeData(TorrentImpl *torrent)
{
    // Schedule a (coalesced) resume-data save for the torrent. The torrent defers the
    // actual save_resume_data() request onto the event loop and collapses duplicates.
    torrent->deferredRequestResumeData();
}

void SessionImpl::handleTorrentResumeDataReady(TorrentImpl *torrent, LoadTorrentParams data)
{
    if (m_resumeDataStorage && torrent)
        m_resumeDataStorage->store(torrent->id(), data);
}

void SessionImpl::handleTorrentShareLimitChanged(TorrentImpl *torrent)
{
    updateShareLimitsTimer();
    Q_UNUSED(torrent);
}

void SessionImpl::handleTorrentNameChanged(TorrentImpl *torrent, const QString &oldName)
{
    emit torrentNameChanged(torrent, oldName);
}

void SessionImpl::handleTorrentConfigChanged(TorrentImpl *torrent)
{
    emit torrentConfigChanged(torrent);
}

void SessionImpl::handleTorrentSavePathChanged(TorrentImpl *torrent)
{
    emit torrentSavePathChanged(torrent);
}

void SessionImpl::handleTorrentSavingModeChanged(TorrentImpl *torrent)
{
    emit torrentSavingModeChanged(torrent);
}

void SessionImpl::handleTorrentCategoryChanged(TorrentImpl *torrent, const QString &oldCategory)
{
    emit torrentCategoryChanged(torrent, oldCategory);
}

void SessionImpl::handleTorrentTagAdded(TorrentImpl *torrent, const Tag &tag)
{
    emit torrentTagAdded(torrent, tag);
}

void SessionImpl::handleTorrentTagRemoved(TorrentImpl *torrent, const Tag &tag)
{
    emit torrentTagRemoved(torrent, tag);
}

void SessionImpl::handleTorrentMetadataReceived(TorrentImpl *torrent)
{
    emit torrentMetadataReceived(torrent);
}

void SessionImpl::handleTorrentStopped(TorrentImpl *torrent)
{
    torrent->requestResumeData();
    emit torrentStopped(torrent);
}

void SessionImpl::handleTorrentStarted(TorrentImpl *torrent)
{
    emit torrentStarted(torrent);
}

void SessionImpl::handleTorrentChecked(TorrentImpl *torrent)
{
    emit torrentFinishedChecking(torrent);
}

void SessionImpl::handleTorrentFinished(TorrentImpl *torrent)
{
    emit torrentFinished(torrent);
}

void SessionImpl::handleTorrentTrackersAdded(TorrentImpl *torrent, const QList<TrackerEntry> &newTrackers)
{
    emit trackersAdded(torrent, newTrackers);
}

void SessionImpl::handleTorrentTrackersRemoved(TorrentImpl *torrent, const QStringList &deletedTrackers)
{
    emit trackersRemoved(torrent, deletedTrackers);
}

void SessionImpl::handleTorrentTrackersReset(TorrentImpl *torrent, const QList<TrackerEntryStatus> &oldEntries, const QList<TrackerEntry> &newEntries)
{
    emit trackersReset(torrent, oldEntries, newEntries);
}

void SessionImpl::handleTorrentUrlSeedsAdded(TorrentImpl *, const QList<QUrl> &) {}

void SessionImpl::handleTorrentUrlSeedsRemoved(TorrentImpl *, const QList<QUrl> &) {}

void SessionImpl::handleTorrentInfoHashChanged(TorrentImpl *torrent, const InfoHash &prevInfoHash)
{
    Q_UNUSED(torrent);
    Q_UNUSED(prevInfoHash);
}

void SessionImpl::handleTorrentContentFileRenamed(TorrentImpl *torrent, const int index, const Path &oldFilePath)
{
    emit torrentContentFileRenamed(torrent, index, oldFilePath);
}

void SessionImpl::handleTorrentContentFolderRenamed(TorrentImpl *torrent, const Path &newFolderPath, const Path &oldFolderPath, const QHash<int, Path> &renamedFiles)
{
    emit torrentContentFolderRenamed(torrent, newFolderPath, oldFolderPath, renamedFiles);
}

void SessionImpl::handleTorrentContentFolderRenamingFailed(TorrentImpl *torrent, const Path &newFolderPath, const Path &oldFolderPath, const QHash<int, Path> &renamedFiles, const QList<int> &failedFileIndexes)
{
    emit torrentContentFolderRenamingFailed(torrent, newFolderPath, oldFolderPath, renamedFiles, failedFileIndexes);
}

void SessionImpl::handleTorrentStorageMovingStateChanged(TorrentImpl *) {}

// --- Categories --------------------------------------------------------------

QStringList SessionImpl::categories() const
{
    return m_categories.keys();
}

CategoryOptions SessionImpl::categoryOptions(const QString &categoryName) const
{
    return m_categories.value(categoryName);
}

Path SessionImpl::categorySavePath(const QString &categoryName) const
{
    return categorySavePath(categoryName, categoryOptions(categoryName));
}

Path SessionImpl::categorySavePath(const QString &categoryName, const CategoryOptions &options) const
{
    const Path basePath = savePath();
    if (categoryName.isEmpty())
        return basePath;

    Path path = options.savePath;
    if (path.isEmpty())
        path = Path(Utils::Fs::toValidFileName(categoryName)); // relative subfolder by category name

    return (path.isAbsolute() ? path : (basePath / path));
}

Path SessionImpl::categoryDownloadPath(const QString &categoryName) const
{
    return categoryDownloadPath(categoryName, categoryOptions(categoryName));
}

Path SessionImpl::categoryDownloadPath(const QString &categoryName, const CategoryOptions &options) const
{
    const DownloadPathOption resolved = resolveCategoryDownloadPathOption(categoryName, options.downloadPath);
    if (!resolved.enabled)
        return {};

    const Path basePath = downloadPath();
    Path path = resolved.path;
    if (path.isEmpty())
        path = Path(Utils::Fs::toValidFileName(categoryName));

    return (path.isAbsolute() ? path : (basePath / path));
}

DownloadPathOption SessionImpl::resolveCategoryDownloadPathOption(const QString &categoryName, const std::optional<DownloadPathOption> &option) const
{
    if (option.has_value())
        return *option;

    // Inherit from the parent category if unset.
    const QString parent = parentCategoryName(categoryName);
    if (!parent.isEmpty() && m_categories.contains(parent))
        return resolveCategoryDownloadPathOption(parent, m_categories.value(parent).downloadPath);

    return {isDownloadPathEnabled(), {}};
}

ShareLimits SessionImpl::categoryShareLimits(const QString &categoryName) const
{
    return categoryOptions(categoryName).shareLimits;
}

bool SessionImpl::setCategoryOptions(const QString &categoryName, const CategoryOptions &options)
{
    if (!m_categories.contains(categoryName))
        return false;

    const CategoryOptions oldOptions = m_categories.value(categoryName);
    if (oldOptions == options)
        return true;

    m_categories[categoryName] = options;
    storeCategories();
    emit categoryOptionsChanged(categoryName);
    qCDebug(lcSession) << "Category options changed:" << categoryName;

    // Re-adjust AutoTMM torrents in this category.
    if (isDisableAutoTMMWhenCategorySavePathChanged())
    {
        for (TorrentImpl *torrent : asConst(m_torrents))
        {
            if (torrent->belongsToCategory(categoryName))
                torrent->handleCategoryOptionsChanged();
        }
    }

    return true;
}

bool SessionImpl::addCategory(const QString &name, const CategoryOptions &options)
{
    if (name.isEmpty() || !isValidCategoryName(name) || m_categories.contains(name))
        return false;

    if (isSubcategoriesEnabled())
    {
        for (const QString &parent : asConst(expandCategory(name)))
        {
            if ((parent != name) && !m_categories.contains(parent))
            {
                m_categories[parent] = {};
                emit categoryAdded(parent);
            }
        }
    }

    m_categories[name] = options;
    storeCategories();
    emit categoryAdded(name);
    qCInfo(lcSession) << "Category added:" << name;
    return true;
}

bool SessionImpl::removeCategory(const QString &name)
{
    for (TorrentImpl *torrent : asConst(m_torrents))
    {
        if (torrent->belongsToCategory(name))
            torrent->setCategory(u""_s);
    }

    // Remove the category and any of its subcategories.
    bool result = false;
    const QStringList categoryNames = m_categories.keys();
    for (const QString &categoryName : categoryNames)
    {
        if ((categoryName == name) || categoryName.startsWith(name + u'/'))
        {
            m_categories.remove(categoryName);
            emit categoryRemoved(categoryName);
            result = true;
        }
    }

    if (result)
    {
        storeCategories();
        qCInfo(lcSession) << "Category removed:" << name;
    }

    return result;
}

bool SessionImpl::isSubcategoriesEnabled() const
{
    return SettingsStorage::instance()->loadValue(u"BitTorrent/Session/SubcategoriesEnabled"_s, false);
}

void SessionImpl::loadCategories()
{
    m_categories.clear();

    const auto readResult = Utils::IO::readFile(specialFolderLocation(SpecialFolder::Config) / Path(u"categories.json"_s), -1);
    if (!readResult)
    {
        qCDebug(lcSession) << "No stored categories to load";
        return;
    }

    lt::error_code ec;
    const QJsonDocument doc = QJsonDocument::fromJson(readResult.value());
    if (!doc.isObject())
        return;

    const QJsonObject jsonObj = doc.object();
    for (auto it = jsonObj.constBegin(); it != jsonObj.constEnd(); ++it)
        m_categories[it.key()] = CategoryOptions::fromJSON(it.value().toObject());

    qCInfo(lcSession) << "Loaded" << m_categories.size() << "categories";
}

void SessionImpl::storeCategories() const
{
    QJsonObject jsonObj;
    for (auto it = m_categories.cbegin(); it != m_categories.cend(); ++it)
        jsonObj[it.key()] = it.value().toJSON();

    const QByteArray data = QJsonDocument(jsonObj).toJson();
    const auto result = Utils::IO::saveToFile(
            specialFolderLocation(SpecialFolder::Config) / Path(u"categories.json"_s), data);
    if (!result)
        qCWarning(lcSession) << "Failed to store categories:" << result.error();
}

void SessionImpl::upgradeCategories()
{
    // TODO(engine): migrate legacy category storage / download-path formats.
}

bool SessionImpl::useCategoryPathsInManualMode() const
{
    return m_useCategoryPathsInManualMode;
}

void SessionImpl::setUseCategoryPathsInManualMode(const bool value)
{
    m_useCategoryPathsInManualMode = value;
}

Path SessionImpl::suggestedSavePath(const QString &categoryName, std::optional<bool> useAutoTMM) const
{
    const bool autoTMM = useAutoTMM.value_or(!isAutoTMMDisabledByDefault());
    return (autoTMM || useCategoryPathsInManualMode())
            ? categorySavePath(categoryName) : savePath();
}

Path SessionImpl::suggestedDownloadPath(const QString &categoryName, std::optional<bool> useAutoTMM) const
{
    const bool autoTMM = useAutoTMM.value_or(!isAutoTMMDisabledByDefault());
    return (autoTMM || useCategoryPathsInManualMode())
            ? categoryDownloadPath(categoryName) : downloadPath();
}

// --- Tags --------------------------------------------------------------------

TagSet SessionImpl::tags() const
{
    return m_tags;
}

bool SessionImpl::hasTag(const Tag &tag) const
{
    return m_tags.contains(tag);
}

bool SessionImpl::addTag(const Tag &tag)
{
    if (!tag.isValid() || hasTag(tag))
        return false;

    m_tags.insert(tag);
    QStringList tagList;
    tagList.reserve(static_cast<qsizetype>(m_tags.size()));
    for (const Tag &t : m_tags)
        tagList.append(t.toString());
    m_storedTags = tagList;
    emit tagAdded(tag);
    qCInfo(lcSession) << "Tag added:" << tag.toString();
    return true;
}

bool SessionImpl::removeTag(const Tag &tag)
{
    if (!m_tags.remove(tag))
        return false;

    for (TorrentImpl *torrent : asConst(m_torrents))
        torrent->removeTag(tag);

    QStringList tagList;
    tagList.reserve(static_cast<qsizetype>(m_tags.size()));
    for (const Tag &t : m_tags)
        tagList.append(t.toString());
    m_storedTags = tagList;
    emit tagRemoved(tag);
    qCInfo(lcSession) << "Tag removed:" << tag.toString();
    return true;
}

// --- Free disk space checking ------------------------------------------------

QFuture<FileSearchResult> SessionImpl::findIncompleteFiles(const Path &savePath, const Path &downloadPath, const PathList &filePaths) const
{
    // TODO(engine): dispatch to the FileSearcher on the IO thread and resolve which
    // files already exist in savePath vs downloadPath. Structure only.
    Q_UNUSED(savePath);
    Q_UNUSED(downloadPath);
    Q_UNUSED(filePaths);
    return {};
}

// --- Port mapping ------------------------------------------------------------

void SessionImpl::enablePortMapping()
{
    if (m_isPortMappingEnabled)
        return;

    lt::settings_pack settingsPack;
    settingsPack.set_bool(lt::settings_pack::enable_upnp, true);
    settingsPack.set_bool(lt::settings_pack::enable_natpmp, true);
    m_nativeSession->apply_settings(std::move(settingsPack));

    m_isPortMappingEnabled = true;
    qCInfo(lcSession) << "Port mapping enabled";
}

void SessionImpl::disablePortMapping()
{
    if (!m_isPortMappingEnabled)
        return;

    lt::settings_pack settingsPack;
    settingsPack.set_bool(lt::settings_pack::enable_upnp, false);
    settingsPack.set_bool(lt::settings_pack::enable_natpmp, false);
    m_nativeSession->apply_settings(std::move(settingsPack));

    m_mappedPorts.clear();
    m_isPortMappingEnabled = false;
    qCInfo(lcSession) << "Port mapping disabled";
}

void SessionImpl::addMappedPorts(const QSet<quint16> &ports)
{
    if (!m_isPortMappingEnabled)
        return;

    for (const quint16 port : ports)
    {
        if (!m_mappedPorts.contains(port))
        {
            m_mappedPorts.insert(port, m_nativeSession->add_port_mapping(lt::portmap_protocol::tcp, port, port));
        }
    }
}

void SessionImpl::removeMappedPorts(const QSet<quint16> &ports)
{
    for (const quint16 port : ports)
    {
        if (const auto it = m_mappedPorts.find(port); it != m_mappedPorts.end())
        {
            for (const lt::port_mapping_t &mapping : it.value())
                m_nativeSession->delete_port_mapping(mapping);
            m_mappedPorts.erase(it);
        }
    }
}

// --- Bandwidth scheduler / IP filter / trackers ------------------------------

void SessionImpl::enableBandwidthScheduler()
{
    if (isBandwidthSchedulerEnabled())
    {
        if (!m_bwScheduler)
        {
            m_bwScheduler = new BandwidthScheduler(this);
            connect(m_bwScheduler.data(), &BandwidthScheduler::bandwidthLimitRequested
                    , this, [this](const bool alternative) { emit speedLimitModeChanged(alternative); });
        }
        m_bwScheduler->start();
    }
    else if (m_bwScheduler)
    {
        delete m_bwScheduler;
    }
}

void SessionImpl::enableIPFilter()
{
    // TODO(engine): parse the IP filter file on a worker thread (FilterParserThread)
    // and apply the parsed ranges plus banned IPs to the native session.
    m_IPFilteringConfigured = true;
}

void SessionImpl::disableIPFilter()
{
    m_nativeSession->set_ip_filter(lt::ip_filter());
    m_IPFilteringConfigured = false;
}

void SessionImpl::processBannedIPs(lt::ip_filter &filter)
{
    for (const QString &ip : m_bannedIPs.get())
    {
        lt::error_code ec;
        const lt::address addr = lt::make_address(ip.toStdString(), ec);
        if (!ec)
            filter.add_rule(addr, addr, lt::ip_filter::blocked);
    }
}

void SessionImpl::handleIPFilterParsed(const int ruleCount)
{
    lt::ip_filter filter = m_nativeSession->get_ip_filter();
    processBannedIPs(filter);
    m_nativeSession->set_ip_filter(filter);
    emit IPFilterParsed(false, ruleCount);
    qCInfo(lcSession) << "IP filter parsed:" << ruleCount << "rules";
}

void SessionImpl::handleIPFilterError()
{
    lt::ip_filter filter = m_nativeSession->get_ip_filter();
    processBannedIPs(filter);
    m_nativeSession->set_ip_filter(filter);
    emit IPFilterParsed(true, 0);
    qCWarning(lcSession) << "IP filter parsing failed";
}

void SessionImpl::enableTracker(const bool enable)
{
    // TODO(engine): start/stop the embedded private tracker.
    Q_UNUSED(enable);
}

void SessionImpl::populateAdditionalTrackers()
{
    m_additionalTrackerEntries = parseTrackerEntries(m_additionalTrackers.get());
}

void SessionImpl::populateAdditionalTrackersFromURL()
{
    m_additionalTrackerEntriesFromURL = parseTrackerEntries(m_additionalTrackersFromURL);
}

void SessionImpl::updateTrackersFromURL()
{
    // TODO(engine): download the tracker list from additionalTrackersURL() via
    // Net::DownloadManager and refresh m_additionalTrackerEntriesFromURL. Structure only.
}

void SessionImpl::updateTrackersFromFile() {}

void SessionImpl::setAdditionalTrackersFromURL(const QString &trackers)
{
    if (m_additionalTrackersFromURL == trackers)
        return;

    m_additionalTrackersFromURL = trackers;
    populateAdditionalTrackersFromURL();
}

QString SessionImpl::additionalTrackersFromURL() const
{
    return m_additionalTrackersFromURL;
}

void SessionImpl::populateExcludedFileNamesRegExpList()
{
    m_excludedFileNamesRegExpList.clear();
    for (const QString &pattern : m_excludedFileNames.get())
    {
        const QString wildcard = QRegularExpression::wildcardToRegularExpression(pattern);
        m_excludedFileNamesRegExpList.append(QRegularExpression(wildcard, QRegularExpression::CaseInsensitiveOption));
    }
}

void SessionImpl::applyFilenameFilter(const PathList &files, QList<BitTorrent::DownloadPriority> &priorities)
{
    if (!isExcludedFileNamesEnabled())
        return;

    Q_ASSERT(files.size() == priorities.size());
    for (int i = 0; i < files.size(); ++i)
    {
        const QString fileName = files.at(i).filename();
        for (const QRegularExpression &re : asConst(m_excludedFileNamesRegExpList))
        {
            if (re.match(fileName).hasMatch())
            {
                priorities[i] = DownloadPriority::Ignored;
                break;
            }
        }
    }
}

// --- Bandwidth limits --------------------------------------------------------

void SessionImpl::applyBandwidthLimits()
{
    lt::settings_pack settingsPack;
    settingsPack.set_int(lt::settings_pack::download_rate_limit, downloadSpeedLimit());
    settingsPack.set_int(lt::settings_pack::upload_rate_limit, uploadSpeedLimit());
    m_nativeSession->apply_settings(std::move(settingsPack));
}

// =============================================================================
//  Settings getters / setters (backed by CachedSettingValue)
// =============================================================================

#define DEFINE_SIMPLE_GETTER_SETTER(type, getter, setter, member)                 \
    type SessionImpl::getter() const { return member; }                           \
    void SessionImpl::setter(const type value)                                    \
    {                                                                             \
        if (value == member) return;                                             \
        member = value;                                                           \
        qCDebug(lcSession) << #setter << value;                                   \
        configureDeferred();                                                      \
    }

Path SessionImpl::savePath() const { return m_savePath; }

void SessionImpl::setSavePath(const Path &path)
{
    const Path baseSavePath = (path.isEmpty() ? Utils::Fs::homePath() / Path(u"qBittorrent/downloads"_s) : path);
    if (baseSavePath == m_savePath.get())
        return;

    m_savePath = baseSavePath;
    qCInfo(lcSession) << "Default save path set to" << baseSavePath.data();

    if (isDisableAutoTMMWhenDefaultSavePathChanged())
    {
        for (TorrentImpl *torrent : asConst(m_torrents))
        {
            if (torrent->isAutoTMMEnabled())
                torrent->setAutoTMMEnabled(false);
        }
    }
    else
    {
        for (TorrentImpl *torrent : asConst(m_torrents))
        {
            if (torrent->isAutoTMMEnabled())
                torrent->handleCategoryOptionsChanged();
        }
    }
}

Path SessionImpl::downloadPath() const { return m_downloadPath; }

void SessionImpl::setDownloadPath(const Path &path)
{
    const Path resolved = (path.isEmpty() ? (savePath() / Path(u"temp"_s)) : path);
    if (resolved == m_downloadPath.get())
        return;

    m_downloadPath = resolved;
    qCInfo(lcSession) << "Default download path set to" << resolved.data();
}

bool SessionImpl::isDownloadPathEnabled() const { return m_isDownloadPathEnabled; }

void SessionImpl::setDownloadPathEnabled(const bool enabled)
{
    if (enabled == m_isDownloadPathEnabled)
        return;
    m_isDownloadPathEnabled = enabled;
    for (TorrentImpl *torrent : asConst(m_torrents))
        torrent->handleCategoryOptionsChanged();
}

QStringList SessionImpl::excludedFileNames() const { return m_excludedFileNames; }

void SessionImpl::setExcludedFileNames(const QStringList &excludedFileNames)
{
    if (excludedFileNames == m_excludedFileNames.get())
        return;
    m_excludedFileNames = excludedFileNames;
    populateExcludedFileNamesRegExpList();
}

bool SessionImpl::isExcludedFileNamesEnabled() const { return m_isExcludedFileNamesEnabled; }

void SessionImpl::setExcludedFileNamesEnabled(const bool enabled)
{
    if (enabled == m_isExcludedFileNamesEnabled)
        return;
    m_isExcludedFileNamesEnabled = enabled;
    if (enabled)
        populateExcludedFileNamesRegExpList();
    else
        m_excludedFileNamesRegExpList.clear();
}

QStringList SessionImpl::bannedIPs() const { return m_bannedIPs; }

void SessionImpl::setBannedIPs(const QStringList &newList)
{
    if (newList == m_bannedIPs.get())
        return;

    QStringList filtered;
    for (const QString &ip : newList)
    {
        lt::error_code ec;
        lt::make_address(ip.toStdString(), ec);
        if (!ec)
            filtered << ip;
    }
    filtered.sort();
    m_bannedIPs = filtered;
    configureDeferred();
}

const ShareLimits &SessionImpl::shareLimits() const { return m_shareLimits; }

void SessionImpl::setShareLimits(ShareLimits shareLimits)
{
    if (shareLimits == m_shareLimits)
        return;

    m_shareLimits = shareLimits;
    m_globalMaxRatio = shareLimits.ratioLimit;
    m_globalMaxSeedingMinutes = shareLimits.seedingTimeLimit;
    m_globalMaxInactiveSeedingMinutes = shareLimits.inactiveSeedingTimeLimit;
    updateShareLimitsTimer();
    qCDebug(lcSession) << "Global share limits updated";
}

// -- The remaining scalar settings all follow the same store-and-reconfigure form.

QString SessionImpl::getDHTBootstrapNodes() const { return m_DHTBootstrapNodes; }
void SessionImpl::setDHTBootstrapNodes(const QString &nodes)
{
    if (nodes == m_DHTBootstrapNodes.get()) return;
    m_DHTBootstrapNodes = nodes; configureDeferred();
}

bool SessionImpl::isDHTEnabled() const { return m_isDHTEnabled; }
void SessionImpl::setDHTEnabled(const bool enabled)
{
    if (enabled == m_isDHTEnabled) return;
    m_isDHTEnabled = enabled; configureDeferred();
    qCInfo(lcSession) << "DHT" << (enabled ? "enabled" : "disabled");
}

bool SessionImpl::isLSDEnabled() const { return m_isLSDEnabled; }
void SessionImpl::setLSDEnabled(const bool enabled)
{
    if (enabled == m_isLSDEnabled) return;
    m_isLSDEnabled = enabled; configureDeferred();
}

bool SessionImpl::isPeXEnabled() const { return m_isPeXEnabled; }
void SessionImpl::setPeXEnabled(const bool enabled)
{
    if (enabled == m_isPeXEnabled) return;
    m_isPeXEnabled = enabled;
    qCWarning(lcSession) << "PeX changes take effect after a restart";
}

bool SessionImpl::isAddTorrentToQueueTop() const { return m_isAddTorrentToQueueTop; }
void SessionImpl::setAddTorrentToQueueTop(const bool value) { m_isAddTorrentToQueueTop = value; }

bool SessionImpl::isAddTorrentStopped() const { return m_isAddTorrentStopped; }
void SessionImpl::setAddTorrentStopped(const bool value) { m_isAddTorrentStopped = value; }

Torrent::StopCondition SessionImpl::torrentStopCondition() const { return m_torrentStopCondition; }
void SessionImpl::setTorrentStopCondition(const Torrent::StopCondition stopCondition) { m_torrentStopCondition = stopCondition; }

TorrentContentLayout SessionImpl::torrentContentLayout() const { return m_torrentContentLayout; }
void SessionImpl::setTorrentContentLayout(const TorrentContentLayout value) { m_torrentContentLayout = value; }

bool SessionImpl::isTrackerEnabled() const { return m_isTrackerEnabled; }
void SessionImpl::setTrackerEnabled(const bool enabled)
{
    if (enabled == m_isTrackerEnabled) return;
    m_isTrackerEnabled = enabled;
    enableTracker(enabled);
}

bool SessionImpl::isAppendExtensionEnabled() const { return m_isAppendExtensionEnabled; }
void SessionImpl::setAppendExtensionEnabled(const bool enabled)
{
    if (enabled == m_isAppendExtensionEnabled) return;
    m_isAppendExtensionEnabled = enabled;
    for (TorrentImpl *torrent : asConst(m_torrents))
        torrent->handleAppendExtensionToggled();
}

bool SessionImpl::isUnwantedFolderEnabled() const { return m_isUnwantedFolderEnabled; }
void SessionImpl::setUnwantedFolderEnabled(const bool enabled)
{
    if (enabled == m_isUnwantedFolderEnabled) return;
    m_isUnwantedFolderEnabled = enabled;
    for (TorrentImpl *torrent : asConst(m_torrents))
        torrent->handleUnwantedFolderToggled();
}

int SessionImpl::refreshInterval() const { return m_refreshInterval; }
void SessionImpl::setRefreshInterval(const int value) { if (value != m_refreshInterval) m_refreshInterval = value; }

bool SessionImpl::isPreallocationEnabled() const { return m_isPreallocationEnabled; }
void SessionImpl::setPreallocationEnabled(const bool enabled) { m_isPreallocationEnabled = enabled; }

Path SessionImpl::torrentExportDirectory() const { return m_torrentExportDirectory; }
void SessionImpl::setTorrentExportDirectory(const Path &path) { if (path != m_torrentExportDirectory.get()) m_torrentExportDirectory = path; }

Path SessionImpl::finishedTorrentExportDirectory() const { return m_finishedTorrentExportDirectory; }
void SessionImpl::setFinishedTorrentExportDirectory(const Path &path) { if (path != m_finishedTorrentExportDirectory.get()) m_finishedTorrentExportDirectory = path; }

int SessionImpl::globalDownloadSpeedLimit() const { return m_globalDownloadSpeedLimit * 1024; }
void SessionImpl::setGlobalDownloadSpeedLimit(const int limit)
{
    const int kib = limit / 1024;
    if (kib == m_globalDownloadSpeedLimit) return;
    m_globalDownloadSpeedLimit = kib;
    if (!isAltGlobalSpeedLimitEnabled()) applyBandwidthLimits();
}

int SessionImpl::globalUploadSpeedLimit() const { return m_globalUploadSpeedLimit * 1024; }
void SessionImpl::setGlobalUploadSpeedLimit(const int limit)
{
    const int kib = limit / 1024;
    if (kib == m_globalUploadSpeedLimit) return;
    m_globalUploadSpeedLimit = kib;
    if (!isAltGlobalSpeedLimitEnabled()) applyBandwidthLimits();
}

int SessionImpl::altGlobalDownloadSpeedLimit() const { return m_altGlobalDownloadSpeedLimit * 1024; }
void SessionImpl::setAltGlobalDownloadSpeedLimit(const int limit)
{
    const int kib = limit / 1024;
    if (kib == m_altGlobalDownloadSpeedLimit) return;
    m_altGlobalDownloadSpeedLimit = kib;
    if (isAltGlobalSpeedLimitEnabled()) applyBandwidthLimits();
}

int SessionImpl::altGlobalUploadSpeedLimit() const { return m_altGlobalUploadSpeedLimit * 1024; }
void SessionImpl::setAltGlobalUploadSpeedLimit(const int limit)
{
    const int kib = limit / 1024;
    if (kib == m_altGlobalUploadSpeedLimit) return;
    m_altGlobalUploadSpeedLimit = kib;
    if (isAltGlobalSpeedLimitEnabled()) applyBandwidthLimits();
}

int SessionImpl::downloadSpeedLimit() const
{
    return isAltGlobalSpeedLimitEnabled() ? altGlobalDownloadSpeedLimit() : globalDownloadSpeedLimit();
}
void SessionImpl::setDownloadSpeedLimit(const int limit)
{
    if (isAltGlobalSpeedLimitEnabled()) setAltGlobalDownloadSpeedLimit(limit);
    else setGlobalDownloadSpeedLimit(limit);
}

int SessionImpl::uploadSpeedLimit() const
{
    return isAltGlobalSpeedLimitEnabled() ? altGlobalUploadSpeedLimit() : globalUploadSpeedLimit();
}
void SessionImpl::setUploadSpeedLimit(const int limit)
{
    if (isAltGlobalSpeedLimitEnabled()) setAltGlobalUploadSpeedLimit(limit);
    else setGlobalUploadSpeedLimit(limit);
}

bool SessionImpl::isAltGlobalSpeedLimitEnabled() const { return m_isAltGlobalSpeedLimitEnabled; }
void SessionImpl::setAltGlobalSpeedLimitEnabled(const bool enabled)
{
    if (enabled == isAltGlobalSpeedLimitEnabled()) return;
    m_isAltGlobalSpeedLimitEnabled = enabled;
    applyBandwidthLimits();
    emit speedLimitModeChanged(enabled);
    qCInfo(lcSession) << "Alternative speed limits" << (enabled ? "enabled" : "disabled");
}

bool SessionImpl::isBandwidthSchedulerEnabled() const { return m_isBandwidthSchedulerEnabled; }
void SessionImpl::setBandwidthSchedulerEnabled(const bool enabled)
{
    if (enabled == isBandwidthSchedulerEnabled()) return;
    m_isBandwidthSchedulerEnabled = enabled;
    enableBandwidthScheduler();
}

bool SessionImpl::isPerformanceWarningEnabled() const { return m_isPerformanceWarningEnabled; }
void SessionImpl::setPerformanceWarningEnabled(const bool enable) { if (enable != m_isPerformanceWarningEnabled) { m_isPerformanceWarningEnabled = enable; configureDeferred(); } }

int SessionImpl::saveResumeDataInterval() const { return m_saveResumeDataInterval; }
void SessionImpl::setSaveResumeDataInterval(const int value)
{
    if (value == m_saveResumeDataInterval) return;
    m_saveResumeDataInterval = value;
    if (value > 0)
    {
        m_resumeDataTimer->setInterval(std::chrono::minutes(value));
        m_resumeDataTimer->start();
    }
    else
    {
        m_resumeDataTimer->stop();
    }
}

std::chrono::minutes SessionImpl::saveStatisticsInterval() const { return std::chrono::minutes(m_saveStatisticsInterval.get()); }
void SessionImpl::setSaveStatisticsInterval(const std::chrono::minutes value) { m_saveStatisticsInterval = static_cast<int>(value.count()); }

int SessionImpl::shutdownTimeout() const { return m_shutdownTimeout; }
void SessionImpl::setShutdownTimeout(const int value) { m_shutdownTimeout = value; }

int SessionImpl::port() const { return m_port; }
void SessionImpl::setPort(const int port)
{
    if (port == m_port) return;
    m_port = port;
    configureListeningInterface();
    qCInfo(lcSession) << "Listen port set to" << port;
}

bool SessionImpl::isSSLEnabled() const { return m_sslEnabled; }
void SessionImpl::setSSLEnabled(const bool enabled) { if (enabled != m_sslEnabled) { m_sslEnabled = enabled; configureListeningInterface(); } }

int SessionImpl::sslPort() const { return m_sslPort; }
void SessionImpl::setSSLPort(const int port) { if (port != m_sslPort) { m_sslPort = port; configureListeningInterface(); } }

QString SessionImpl::networkInterface() const { return m_networkInterface; }
void SessionImpl::setNetworkInterface(const QString &iface) { if (iface != m_networkInterface.get()) { m_networkInterface = iface; configureListeningInterface(); } }

QString SessionImpl::networkInterfaceName() const { return m_networkInterfaceName; }
void SessionImpl::setNetworkInterfaceName(const QString &name) { m_networkInterfaceName = name; }

QString SessionImpl::networkInterfaceAddress() const { return m_networkInterfaceAddress; }
void SessionImpl::setNetworkInterfaceAddress(const QString &address) { if (address != m_networkInterfaceAddress.get()) { m_networkInterfaceAddress = address; configureListeningInterface(); } }

int SessionImpl::encryption() const { return m_encryption; }
void SessionImpl::setEncryption(const int state) { if (state != m_encryption) { m_encryption = state; configureDeferred(); } }

int SessionImpl::maxActiveCheckingTorrents() const { return m_maxActiveCheckingTorrents; }
void SessionImpl::setMaxActiveCheckingTorrents(const int val) { if (val != m_maxActiveCheckingTorrents) { m_maxActiveCheckingTorrents = val; configureDeferred(); } }

bool SessionImpl::isProxyPeerConnectionsEnabled() const { return m_isProxyPeerConnectionsEnabled; }
void SessionImpl::setProxyPeerConnectionsEnabled(const bool enabled) { if (enabled != m_isProxyPeerConnectionsEnabled) { m_isProxyPeerConnectionsEnabled = enabled; configureDeferred(); } }

ChokingAlgorithm SessionImpl::chokingAlgorithm() const { return m_chokingAlgorithm; }
void SessionImpl::setChokingAlgorithm(const ChokingAlgorithm mode) { if (mode != m_chokingAlgorithm) { m_chokingAlgorithm = mode; configureDeferred(); } }

SeedChokingAlgorithm SessionImpl::seedChokingAlgorithm() const { return m_seedChokingAlgorithm; }
void SessionImpl::setSeedChokingAlgorithm(const SeedChokingAlgorithm mode) { if (mode != m_seedChokingAlgorithm) { m_seedChokingAlgorithm = mode; configureDeferred(); } }

bool SessionImpl::isAddTrackersEnabled() const { return m_isAddTrackersEnabled; }
void SessionImpl::setAddTrackersEnabled(const bool enabled) { m_isAddTrackersEnabled = enabled; }

QString SessionImpl::additionalTrackers() const { return m_additionalTrackers; }
void SessionImpl::setAdditionalTrackers(const QString &trackers)
{
    if (trackers == m_additionalTrackers.get()) return;
    m_additionalTrackers = trackers;
    populateAdditionalTrackers();
}

bool SessionImpl::isIPFilteringEnabled() const { return m_isIPFilteringEnabled; }
void SessionImpl::setIPFilteringEnabled(const bool enabled)
{
    if (enabled == m_isIPFilteringEnabled) return;
    m_isIPFilteringEnabled = enabled;
    m_IPFilteringConfigured = false;
    configureDeferred();
}

Path SessionImpl::IPFilterFile() const { return m_IPFilterFile; }
void SessionImpl::setIPFilterFile(const Path &path)
{
    if (path == m_IPFilterFile.get()) return;
    m_IPFilterFile = path;
    m_IPFilteringConfigured = false;
    configureDeferred();
}

bool SessionImpl::announceToAllTrackers() const { return m_announceToAllTrackers; }
void SessionImpl::setAnnounceToAllTrackers(const bool val) { if (val != m_announceToAllTrackers) { m_announceToAllTrackers = val; configureDeferred(); } }

bool SessionImpl::announceToAllTiers() const { return m_announceToAllTiers; }
void SessionImpl::setAnnounceToAllTiers(const bool val) { if (val != m_announceToAllTiers) { m_announceToAllTiers = val; configureDeferred(); } }

int SessionImpl::peerTurnover() const { return m_peerTurnover; }
void SessionImpl::setPeerTurnover(const int val) { if (val != m_peerTurnover) { m_peerTurnover = val; configureDeferred(); } }

int SessionImpl::peerTurnoverCutoff() const { return m_peerTurnoverCutoff; }
void SessionImpl::setPeerTurnoverCutoff(const int val) { if (val != m_peerTurnoverCutoff) { m_peerTurnoverCutoff = val; configureDeferred(); } }

int SessionImpl::peerTurnoverInterval() const { return m_peerTurnoverInterval; }
void SessionImpl::setPeerTurnoverInterval(const int val) { if (val != m_peerTurnoverInterval) { m_peerTurnoverInterval = val; configureDeferred(); } }

int SessionImpl::requestQueueSize() const { return m_requestQueueSize; }
void SessionImpl::setRequestQueueSize(const int val) { if (val != m_requestQueueSize) { m_requestQueueSize = val; configureDeferred(); } }

int SessionImpl::asyncIOThreads() const { return std::clamp(m_asyncIOThreads.get(), 1, 1024); }
void SessionImpl::setAsyncIOThreads(const int num) { if (num != m_asyncIOThreads) { m_asyncIOThreads = num; configureDeferred(); } }

int SessionImpl::hashingThreads() const { return std::clamp(m_hashingThreads.get(), 1, 1024); }
void SessionImpl::setHashingThreads(const int num) { if (num != m_hashingThreads) { m_hashingThreads = num; configureDeferred(); } }

int SessionImpl::filePoolSize() const { return m_filePoolSize; }
void SessionImpl::setFilePoolSize(const int size) { if (size != m_filePoolSize) { m_filePoolSize = size; configureDeferred(); } }

int SessionImpl::checkingMemUsage() const { return std::max(1, m_checkingMemUsage.get()); }
void SessionImpl::setCheckingMemUsage(const int size) { if (size != m_checkingMemUsage) { m_checkingMemUsage = size; configureDeferred(); } }

int SessionImpl::diskCacheSize() const { return m_diskCacheSize; }
void SessionImpl::setDiskCacheSize(const int size) { if (size != m_diskCacheSize) { m_diskCacheSize = size; configureDeferred(); } }

int SessionImpl::diskCacheTTL() const { return m_diskCacheTTL; }
void SessionImpl::setDiskCacheTTL(const int ttl) { if (ttl != m_diskCacheTTL) { m_diskCacheTTL = ttl; configureDeferred(); } }

qint64 SessionImpl::diskQueueSize() const { return m_diskQueueSize; }
void SessionImpl::setDiskQueueSize(const qint64 size) { if (size != m_diskQueueSize) { m_diskQueueSize = size; configureDeferred(); } }

DiskIOType SessionImpl::diskIOType() const { return m_diskIOType; }
void SessionImpl::setDiskIOType(const DiskIOType type) { if (type != m_diskIOType) m_diskIOType = type; } // takes effect on restart

DiskIOReadMode SessionImpl::diskIOReadMode() const { return m_diskIOReadMode; }
void SessionImpl::setDiskIOReadMode(const DiskIOReadMode mode) { if (mode != m_diskIOReadMode) { m_diskIOReadMode = mode; configureDeferred(); } }

DiskIOWriteMode SessionImpl::diskIOWriteMode() const { return m_diskIOWriteMode; }
void SessionImpl::setDiskIOWriteMode(const DiskIOWriteMode mode) { if (mode != m_diskIOWriteMode) { m_diskIOWriteMode = mode; configureDeferred(); } }

bool SessionImpl::isCoalesceReadWriteEnabled() const { return m_coalesceReadWriteEnabled; }
void SessionImpl::setCoalesceReadWriteEnabled(const bool enabled) { if (enabled != m_coalesceReadWriteEnabled) { m_coalesceReadWriteEnabled = enabled; configureDeferred(); } }

bool SessionImpl::usePieceExtentAffinity() const { return m_usePieceExtentAffinity; }
void SessionImpl::setPieceExtentAffinity(const bool enabled) { if (enabled != m_usePieceExtentAffinity) { m_usePieceExtentAffinity = enabled; configureDeferred(); } }

bool SessionImpl::isSuggestModeEnabled() const { return m_isSuggestMode; }
void SessionImpl::setSuggestMode(const bool mode) { if (mode != m_isSuggestMode) { m_isSuggestMode = mode; configureDeferred(); } }

int SessionImpl::sendBufferWatermark() const { return m_sendBufferWatermark; }
void SessionImpl::setSendBufferWatermark(const int value) { if (value != m_sendBufferWatermark) { m_sendBufferWatermark = value; configureDeferred(); } }

int SessionImpl::sendBufferLowWatermark() const { return m_sendBufferLowWatermark; }
void SessionImpl::setSendBufferLowWatermark(const int value) { if (value != m_sendBufferLowWatermark) { m_sendBufferLowWatermark = value; configureDeferred(); } }

int SessionImpl::sendBufferWatermarkFactor() const { return m_sendBufferWatermarkFactor; }
void SessionImpl::setSendBufferWatermarkFactor(const int value) { if (value != m_sendBufferWatermarkFactor) { m_sendBufferWatermarkFactor = value; configureDeferred(); } }

int SessionImpl::connectionSpeed() const { return m_connectionSpeed; }
void SessionImpl::setConnectionSpeed(const int value) { if (value != m_connectionSpeed) { m_connectionSpeed = value; configureDeferred(); } }

bool SessionImpl::isSeedingOutgoingConnectionsEnabled() const { return m_isSeedingOutgoingConnectionsEnabled; }
void SessionImpl::setSeedingOutgoingConnections(const bool enabled) { if (enabled != m_isSeedingOutgoingConnectionsEnabled) { m_isSeedingOutgoingConnectionsEnabled = enabled; configureDeferred(); } }

int SessionImpl::socketSendBufferSize() const { return m_socketSendBufferSize; }
void SessionImpl::setSocketSendBufferSize(const int value) { if (value != m_socketSendBufferSize) { m_socketSendBufferSize = value; configureDeferred(); } }

int SessionImpl::socketReceiveBufferSize() const { return m_socketReceiveBufferSize; }
void SessionImpl::setSocketReceiveBufferSize(const int value) { if (value != m_socketReceiveBufferSize) { m_socketReceiveBufferSize = value; configureDeferred(); } }

int SessionImpl::socketBacklogSize() const { return m_socketBacklogSize; }
void SessionImpl::setSocketBacklogSize(const int value) { if (value != m_socketBacklogSize) { m_socketBacklogSize = value; configureDeferred(); } }

bool SessionImpl::isAnonymousModeEnabled() const { return m_isAnonymousModeEnabled; }
void SessionImpl::setAnonymousModeEnabled(const bool enabled)
{
    if (enabled != m_isAnonymousModeEnabled) { m_isAnonymousModeEnabled = enabled; configureDeferred();
        qCInfo(lcSession) << "Anonymous mode" << (enabled ? "enabled" : "disabled"); }
}

bool SessionImpl::isQueueingSystemEnabled() const { return m_isQueueingEnabled; }
void SessionImpl::setQueueingSystemEnabled(const bool enabled)
{
    if (enabled == m_isQueueingEnabled) return;
    m_isQueueingEnabled = enabled;
    configureDeferred();
    if (enabled) saveTorrentsQueue();
    else removeTorrentsQueue();
    emit subcategoriesSupportChanged();
}

bool SessionImpl::ignoreSlowTorrentsForQueueing() const { return m_ignoreSlowTorrentsForQueueing; }
void SessionImpl::setIgnoreSlowTorrentsForQueueing(const bool ignore) { if (ignore != m_ignoreSlowTorrentsForQueueing) { m_ignoreSlowTorrentsForQueueing = ignore; configureDeferred(); } }

int SessionImpl::downloadRateForSlowTorrents() const { return m_downloadRateForSlowTorrents; }
void SessionImpl::setDownloadRateForSlowTorrents(const int rateInKibiBytes) { if (rateInKibiBytes != m_downloadRateForSlowTorrents) { m_downloadRateForSlowTorrents = rateInKibiBytes; configureDeferred(); } }

int SessionImpl::uploadRateForSlowTorrents() const { return m_uploadRateForSlowTorrents; }
void SessionImpl::setUploadRateForSlowTorrents(const int rateInKibiBytes) { if (rateInKibiBytes != m_uploadRateForSlowTorrents) { m_uploadRateForSlowTorrents = rateInKibiBytes; configureDeferred(); } }

int SessionImpl::slowTorrentsInactivityTimer() const { return m_slowTorrentsInactivityTimer; }
void SessionImpl::setSlowTorrentsInactivityTimer(const int timeInSeconds) { if (timeInSeconds != m_slowTorrentsInactivityTimer) { m_slowTorrentsInactivityTimer = timeInSeconds; configureDeferred(); } }

int SessionImpl::outgoingPortsMin() const { return m_outgoingPortsMin; }
void SessionImpl::setOutgoingPortsMin(const int min) { if (min != m_outgoingPortsMin) { m_outgoingPortsMin = min; configureDeferred(); } }

int SessionImpl::outgoingPortsMax() const { return m_outgoingPortsMax; }
void SessionImpl::setOutgoingPortsMax(const int max) { if (max != m_outgoingPortsMax) { m_outgoingPortsMax = max; configureDeferred(); } }

int SessionImpl::UPnPLeaseDuration() const { return m_UPnPLeaseDuration; }
void SessionImpl::setUPnPLeaseDuration(const int duration) { if (duration != m_UPnPLeaseDuration) { m_UPnPLeaseDuration = duration; configureDeferred(); } }

int SessionImpl::peerDSCP() const { return m_peerDSCP; }
void SessionImpl::setPeerDSCP(const int value) { const int clamped = std::clamp(value, 0, 63); if (clamped != m_peerDSCP) { m_peerDSCP = clamped; configureDeferred(); } }

bool SessionImpl::ignoreLimitsOnLAN() const { return m_ignoreLimitsOnLAN; }
void SessionImpl::setIgnoreLimitsOnLAN(const bool ignore) { if (ignore != m_ignoreLimitsOnLAN) { m_ignoreLimitsOnLAN = ignore; configureDeferred(); } }

bool SessionImpl::includeOverheadInLimits() const { return m_includeOverheadInLimits; }
void SessionImpl::setIncludeOverheadInLimits(const bool include) { if (include != m_includeOverheadInLimits) { m_includeOverheadInLimits = include; configureDeferred(); } }

QString SessionImpl::announceIP() const { return m_announceIP; }
void SessionImpl::setAnnounceIP(const QString &ip) { if (ip != m_announceIP.get()) { m_announceIP = ip; configureDeferred(); } }

int SessionImpl::announcePort() const { return m_announcePort; }
void SessionImpl::setAnnouncePort(const int port) { if (port != m_announcePort) { m_announcePort = port; configureDeferred(); } }

int SessionImpl::maxConcurrentHTTPAnnounces() const { return m_maxConcurrentHTTPAnnounces; }
void SessionImpl::setMaxConcurrentHTTPAnnounces(const int value) { if (value != m_maxConcurrentHTTPAnnounces) { m_maxConcurrentHTTPAnnounces = value; configureDeferred(); } }

bool SessionImpl::isReannounceWhenAddressChangedEnabled() const { return m_isReannounceWhenAddressChangedEnabled; }
void SessionImpl::setReannounceWhenAddressChangedEnabled(const bool enabled) { if (enabled != m_isReannounceWhenAddressChangedEnabled) m_isReannounceWhenAddressChangedEnabled = enabled; }

void SessionImpl::reannounceToAllTrackers() const
{
    for (const lt::torrent_handle &torrent : m_nativeSession->get_torrents())
        torrent.force_reannounce(0, -1, lt::torrent_handle::ignore_min_interval);
    qCDebug(lcSession) << "Reannounced to all trackers";
}

int SessionImpl::stopTrackerTimeout() const { return m_stopTrackerTimeout; }
void SessionImpl::setStopTrackerTimeout(const int value) { if (value != m_stopTrackerTimeout) { m_stopTrackerTimeout = value; configureDeferred(); } }

int SessionImpl::maxConnections() const { return m_maxConnections; }
void SessionImpl::setMaxConnections(const int max) { const int val = (max <= 0) ? -1 : max; if (val != m_maxConnections) { m_maxConnections = val; configureDeferred(); } }

int SessionImpl::maxConnectionsPerTorrent() const { return m_maxConnectionsPerTorrent; }
void SessionImpl::setMaxConnectionsPerTorrent(const int max)
{
    const int val = (max <= 0) ? -1 : max;
    if (val == m_maxConnectionsPerTorrent) return;
    m_maxConnectionsPerTorrent = val;
    for (const lt::torrent_handle &handle : m_nativeSession->get_torrents())
        handle.set_max_connections(val);
}

int SessionImpl::maxUploads() const { return m_maxUploads; }
void SessionImpl::setMaxUploads(const int max) { const int val = (max <= 0) ? -1 : max; if (val != m_maxUploads) { m_maxUploads = val; configureDeferred(); } }

int SessionImpl::maxUploadsPerTorrent() const { return m_maxUploadsPerTorrent; }
void SessionImpl::setMaxUploadsPerTorrent(const int max)
{
    const int val = (max <= 0) ? -1 : max;
    if (val == m_maxUploadsPerTorrent) return;
    m_maxUploadsPerTorrent = val;
    for (const lt::torrent_handle &handle : m_nativeSession->get_torrents())
        handle.set_max_uploads(val);
}

int SessionImpl::maxActiveDownloads() const { return m_maxActiveDownloads; }
void SessionImpl::setMaxActiveDownloads(const int max) { if (max != m_maxActiveDownloads) { m_maxActiveDownloads = max; configureDeferred(); } }

int SessionImpl::maxActiveUploads() const { return m_maxActiveUploads; }
void SessionImpl::setMaxActiveUploads(const int max) { if (max != m_maxActiveUploads) { m_maxActiveUploads = max; configureDeferred(); } }

int SessionImpl::maxActiveTorrents() const { return m_maxActiveTorrents; }
void SessionImpl::setMaxActiveTorrents(const int max) { if (max != m_maxActiveTorrents) { m_maxActiveTorrents = max; configureDeferred(); } }

BTProtocol SessionImpl::btProtocol() const { return m_btProtocol; }
void SessionImpl::setBTProtocol(const BTProtocol protocol)
{
    if ((protocol < BTProtocol::Both) || (protocol > BTProtocol::UTP)) return;
    if (protocol != m_btProtocol) { m_btProtocol = protocol; configureDeferred(); }
}

bool SessionImpl::isUTPRateLimited() const { return m_isUTPRateLimited; }
void SessionImpl::setUTPRateLimited(const bool limited) { if (limited != m_isUTPRateLimited) { m_isUTPRateLimited = limited; configureDeferred(); } }

MixedModeAlgorithm SessionImpl::utpMixedMode() const { return m_utpMixedMode; }
void SessionImpl::setUtpMixedMode(const MixedModeAlgorithm mode) { if (mode != m_utpMixedMode) { m_utpMixedMode = mode; configureDeferred(); } }

int SessionImpl::hostnameCacheTTL() const { return m_hostnameCacheTTL; }
void SessionImpl::setHostnameCacheTTL(const int value) { if (value != m_hostnameCacheTTL) { m_hostnameCacheTTL = value; configureDeferred(); } }

bool SessionImpl::isIDNSupportEnabled() const { return m_IDNSupportEnabled; }
void SessionImpl::setIDNSupportEnabled(const bool enabled) { if (enabled != m_IDNSupportEnabled) { m_IDNSupportEnabled = enabled; configureDeferred(); } }

bool SessionImpl::multiConnectionsPerIpEnabled() const { return m_multiConnectionsPerIpEnabled; }
void SessionImpl::setMultiConnectionsPerIpEnabled(const bool enabled) { if (enabled != m_multiConnectionsPerIpEnabled) { m_multiConnectionsPerIpEnabled = enabled; configureDeferred(); } }

bool SessionImpl::validateHTTPSTrackerCertificate() const { return m_validateHTTPSTrackerCertificate; }
void SessionImpl::setValidateHTTPSTrackerCertificate(const bool enabled) { if (enabled != m_validateHTTPSTrackerCertificate) { m_validateHTTPSTrackerCertificate = enabled; configureDeferred(); } }

bool SessionImpl::isSSRFMitigationEnabled() const { return m_SSRFMitigationEnabled; }
void SessionImpl::setSSRFMitigationEnabled(const bool enabled) { if (enabled != m_SSRFMitigationEnabled) { m_SSRFMitigationEnabled = enabled; configureDeferred(); } }

bool SessionImpl::blockPeersOnPrivilegedPorts() const { return m_blockPeersOnPrivilegedPorts; }
void SessionImpl::setBlockPeersOnPrivilegedPorts(const bool enabled) { if (enabled != m_blockPeersOnPrivilegedPorts) { m_blockPeersOnPrivilegedPorts = enabled; configureDeferred(); } }

bool SessionImpl::isTrackerFilteringEnabled() const { return m_isTrackerFilteringEnabled; }
void SessionImpl::setTrackerFilteringEnabled(const bool enabled) { if (enabled != m_isTrackerFilteringEnabled) { m_isTrackerFilteringEnabled = enabled; configureDeferred(); } }

ResumeDataStorageType SessionImpl::resumeDataStorageType() const { return m_resumeDataStorageType; }
void SessionImpl::setResumeDataStorageType(const ResumeDataStorageType type) { m_resumeDataStorageType = type; }

bool SessionImpl::isMergeTrackersEnabled() const { return m_isMergeTrackersEnabled; }
void SessionImpl::setMergeTrackersEnabled(const bool enabled) { m_isMergeTrackersEnabled = enabled; }

bool SessionImpl::isStartPaused() const { return m_startPaused.get(isAddTorrentStopped()); }
void SessionImpl::setStartPaused(const bool value) { m_startPaused = value; }

TorrentContentRemoveOption SessionImpl::torrentContentRemoveOption() const { return m_torrentContentRemoveOption; }
void SessionImpl::setTorrentContentRemoveOption(const TorrentContentRemoveOption option) { m_torrentContentRemoveOption = option; }

bool SessionImpl::isAddTrackersFromURLEnabled() const { return m_isAddTrackersFromURLEnabled; }
void SessionImpl::setAddTrackersFromURLEnabled(const bool enabled)
{
    if (enabled == m_isAddTrackersFromURLEnabled) return;
    m_isAddTrackersFromURLEnabled = enabled;
    if (enabled) { updateTrackersFromURL(); m_updateTrackersFromURLTimer->start(); }
    else m_updateTrackersFromURLTimer->stop();
}

QString SessionImpl::additionalTrackersURL() const { return m_additionalTrackersURL; }
void SessionImpl::setAdditionalTrackersURL(const QString &url)
{
    if (url == m_additionalTrackersURL.get()) return;
    m_additionalTrackersURL = url;
    if (isAddTrackersFromURLEnabled()) updateTrackersFromURL();
}

// --- AutoTMM configuration ---------------------------------------------------

bool SessionImpl::isAutoTMMDisabledByDefault() const { return m_isAutoTMMDisabledByDefault; }
void SessionImpl::setAutoTMMDisabledByDefault(const bool value) { m_isAutoTMMDisabledByDefault = value; }

bool SessionImpl::isDisableAutoTMMWhenCategoryChanged() const { return m_isDisableAutoTMMWhenCategoryChanged; }
void SessionImpl::setDisableAutoTMMWhenCategoryChanged(const bool value) { m_isDisableAutoTMMWhenCategoryChanged = value; }

bool SessionImpl::isDisableAutoTMMWhenDefaultSavePathChanged() const { return m_isDisableAutoTMMWhenDefaultSavePathChanged; }
void SessionImpl::setDisableAutoTMMWhenDefaultSavePathChanged(const bool value) { m_isDisableAutoTMMWhenDefaultSavePathChanged = value; }

bool SessionImpl::isDisableAutoTMMWhenCategorySavePathChanged() const { return m_isDisableAutoTMMWhenCategorySavePathChanged; }
void SessionImpl::setDisableAutoTMMWhenCategorySavePathChanged(const bool value) { m_isDisableAutoTMMWhenCategorySavePathChanged = value; }

// --- I2P ---------------------------------------------------------------------

bool SessionImpl::isI2PEnabled() const { return m_isI2PEnabled; }
void SessionImpl::setI2PEnabled(const bool enabled) { if (enabled != m_isI2PEnabled) { m_isI2PEnabled = enabled; configureDeferred(); } }

QString SessionImpl::I2PAddress() const { return m_I2PAddress; }
void SessionImpl::setI2PAddress(const QString &address) { if (address != m_I2PAddress.get()) { m_I2PAddress = address; configureDeferred(); } }

int SessionImpl::I2PPort() const { return m_I2PPort; }
void SessionImpl::setI2PPort(const int port) { if (port != m_I2PPort) { m_I2PPort = port; configureDeferred(); } }

bool SessionImpl::I2PMixedMode() const { return m_I2PMixedMode; }
void SessionImpl::setI2PMixedMode(const bool enabled) { if (enabled != m_I2PMixedMode) { m_I2PMixedMode = enabled; configureDeferred(); } }

int SessionImpl::I2PInboundQuantity() const { return m_I2PInboundQuantity; }
void SessionImpl::setI2PInboundQuantity(const int value) { if (value != m_I2PInboundQuantity) { m_I2PInboundQuantity = value; configureDeferred(); } }

int SessionImpl::I2POutboundQuantity() const { return m_I2POutboundQuantity; }
void SessionImpl::setI2POutboundQuantity(const int value) { if (value != m_I2POutboundQuantity) { m_I2POutboundQuantity = value; configureDeferred(); } }

int SessionImpl::I2PInboundLength() const { return m_I2PInboundLength; }
void SessionImpl::setI2PInboundLength(const int value) { if (value != m_I2PInboundLength) { m_I2PInboundLength = value; configureDeferred(); } }

int SessionImpl::I2POutboundLength() const { return m_I2POutboundLength; }
void SessionImpl::setI2POutboundLength(const int value) { if (value != m_I2POutboundLength) { m_I2POutboundLength = value; configureDeferred(); } }

void SessionImpl::torrentContentRemovingFinished(const QString &torrentName, const QString &errorMessage)
{
    if (errorMessage.isEmpty())
        qCInfo(lcSession) << "Torrent content removed. Torrent:" << torrentName;
    else
        qCWarning(lcSession) << "Failed to remove torrent content. Torrent:" << torrentName
                             << "Error:" << errorMessage;
}
