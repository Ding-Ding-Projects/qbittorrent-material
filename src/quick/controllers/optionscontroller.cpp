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

#include "optionscontroller.h"

#include <algorithm>
#include <chrono>
#include <utility>

#include <QClipboard>
#include <QDesktopServices>
#include <QFile>
#include <QGuiApplication>
#include <QHash>
#include <QHostAddress>
#include <QNetworkInterface>
#include <QProcess>
#include <QQmlEngine>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSet>
#include <QTextStream>
#include <QTime>
#include <QUrl>

#include <libtorrent/address.hpp>
#include <libtorrent/error_code.hpp>

#include "base/bittorrent/session.h"
#include "base/bittorrent/sharelimits.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/torrentcontentlayout.h"
#include "base/logging.h"
#include "base/net/portforwarder.h"
#include "base/net/proxyconfigurationmanager.h"
#include "base/net/dnsupdater.h"
#include "base/net/smtpclient.h"
#include "base/net/smtpencryptiontype.h"
#include "base/preferences.h"
#include "base/rss/rss_autodownloader.h"
#include "base/rss/rss_session.h"
#include "base/torrentfileguard.h"
#include "base/utils/fs/path.h"
#include "base/utils/net.h"
#include "base/utils/os.h"

#include "../models/advancedsettingsmodel.h"
#include "../models/watchedfoldersmodel.h"
#include "../theme/thememanager.h"

using BitTorrent::Session;

OptionsController *OptionsController::s_instance = nullptr;

bool OptionsController::windowsDefaultAppsAvailable() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

namespace
{
    const QString ENGLISH_FUNNY_LEVEL_KEY =
        QStringLiteral("Appearance/EnglishFunnyLevel");
    const QString CANTONESE_FUNNY_LEVEL_KEY =
        QStringLiteral("Appearance/CantoneseFunnyLevel");
    constexpr int DEFAULT_ENGLISH_FUNNY_LEVEL = 1;
    constexpr int DEFAULT_CANTONESE_FUNNY_LEVEL = 3;

    /// Staged keys whose change only takes effect after an application restart.
    const QSet<QString> RESTART_KEYS = {
        QStringLiteral("style"),
        QStringLiteral("colorScheme"),
        QStringLiteral("useCustomTheme"),
        QStringLiteral("customThemePath")
    };

    /// Public QML keys deliberately remain identical to qBittorrent's legacy
    /// configuration paths. The engine-facing staging map uses short stable
    /// names, so every typed setting crosses this single compatibility table.
    const QHash<QString, QString> &legacyAliases()
    {
        static const QHash<QString, QString> aliases = {
            // Behavior
            {QStringLiteral("Preferences/General/UseCustomUITheme"), QStringLiteral("useCustomTheme")},
            {QStringLiteral("Preferences/General/CustomUIThemePath"), QStringLiteral("customThemePath")},
            {QStringLiteral("Preferences/Advanced/confirmTorrentDeletion"), QStringLiteral("confirmDeletion")},
            {QStringLiteral("Preferences/General/AlternatingRowColors"), QStringLiteral("alternatingRowColors")},
            {QStringLiteral("GUI/TransferList/UseTorrentStatesColors"), QStringLiteral("useTorrentStatesColors")},
            {QStringLiteral("GUI/TransferList/ProgressBarFollowsTextColor"), QStringLiteral("progressBarFollowsTextColor")},
            {QStringLiteral("Preferences/General/HideZeroValues"), QStringLiteral("hideZeroValues")},
            {QStringLiteral("Preferences/General/HideZeroComboValues"), QStringLiteral("hideZeroComboValues")},
            {QStringLiteral("Preferences/Downloads/DblClOnTorDl"), QStringLiteral("actionDblClickDl")},
            {QStringLiteral("Preferences/Downloads/DblClOnTorFn"), QStringLiteral("actionDblClickFn")},
            {QStringLiteral("TransferListFilters/HideZeroStatusFilters"), QStringLiteral("hideZeroStatusFilters")},
            {QStringLiteral("TransferListFilters/SeparateTrackerStatusFilter"), QStringLiteral("useSeparateTrackerStatusFilter")},
            {QStringLiteral("Preferences/General/TorrentContentDragEnabled"), QStringLiteral("torrentContentDrag")},
            {QStringLiteral("Preferences/General/StatusbarFreeDiskSpaceDisplayed"), QStringLiteral("statusbarFreeDiskSpace")},
            {QStringLiteral("Preferences/General/StatusbarExternalIPDisplayed"), QStringLiteral("statusbarExternalIP")},
            {QStringLiteral("GUI/ShowSplashScreen"), QStringLiteral("showSplashScreen")},
            {QStringLiteral("Preferences/General/ExitConfirm"), QStringLiteral("confirmOnExit")},
            {QStringLiteral("GUI/ConfirmAutoExit"), QStringLiteral("confirmAutoExit")},
            {QStringLiteral("Preferences/General/SystrayEnabled"), QStringLiteral("systrayEnabled")},
            {QStringLiteral("Preferences/General/MinimizeToTray"), QStringLiteral("minimizeToTray")},
            {QStringLiteral("Preferences/General/CloseToTray"), QStringLiteral("closeToTray")},
            {QStringLiteral("Preferences/General/PreventFromSuspendWhenDownloading"), QStringLiteral("preventSuspendDownloading")},
            {QStringLiteral("Preferences/General/PreventFromSuspendWhenSeeding"), QStringLiteral("preventSuspendSeeding")},
            {QStringLiteral("BitTorrent/Session/PerformanceWarning"), QStringLiteral("performanceWarning")},

            // Downloads
            {QStringLiteral("AddNewTorrentDialog/Enabled"), QStringLiteral("additionDialog")},
            {QStringLiteral("AddNewTorrentDialog/TopLevel"), QStringLiteral("additionDialogFront")},
            {QStringLiteral("BitTorrent/Session/TorrentContentLayout"), QStringLiteral("contentLayout")},
            {QStringLiteral("BitTorrent/Session/AddTorrentToTopOfQueue"), QStringLiteral("addToQueueTop")},
            {QStringLiteral("BitTorrent/Session/AddTorrentStopped"), QStringLiteral("addStopped")},
            {QStringLiteral("BitTorrent/Session/TorrentStopCondition"), QStringLiteral("stopCondition")},
            {QStringLiteral("BitTorrent/MergeTrackersEnabled"), QStringLiteral("mergeTrackers")},
            {QStringLiteral("GUI/ConfirmActions/MergeTrackers"), QStringLiteral("confirmMergeTrackers")},
            {QStringLiteral("Downloads/DeleteTorrentAfter"), QStringLiteral("deleteTorrentFiles")},
            {QStringLiteral("Downloads/DeleteTorrentAfterCancelled"), QStringLiteral("deleteTorrentFilesWhenCancelled")},
            {QStringLiteral("BitTorrent/Session/Preallocation"), QStringLiteral("preallocateAll")},
            {QStringLiteral("BitTorrent/Session/AddExtensionToIncompleteFiles"), QStringLiteral("appendExtension")},
            {QStringLiteral("BitTorrent/Session/UseUnwantedFolder"), QStringLiteral("unwantedFolder")},
            {QStringLiteral("Preferences/Advanced/RecursiveDownloadEnabled"), QStringLiteral("recursiveDownload")},
            {QStringLiteral("Downloads/DefaultTMM"), QStringLiteral("savingModeAutomatic")},
            {QStringLiteral("Downloads/OnCategoryChanged"), QStringLiteral("tmmRelocateOnCategoryChanged")},
            {QStringLiteral("Downloads/OnDefaultSavePathChanged"), QStringLiteral("tmmRelocateOnDefaultPathChanged")},
            {QStringLiteral("Downloads/OnCategorySavePathChanged"), QStringLiteral("tmmRelocateOnCategorySavePathChanged")},
            {QStringLiteral("BitTorrent/Session/UseCategoryPathsInManualMode"), QStringLiteral("useCategoryPaths")},
            {QStringLiteral("BitTorrent/Session/DefaultSavePath"), QStringLiteral("savePath")},
            {QStringLiteral("BitTorrent/Session/TempPathEnabled"), QStringLiteral("useDownloadPath")},
            {QStringLiteral("BitTorrent/Session/TempPath"), QStringLiteral("downloadPath")},
            {QStringLiteral("Downloads/ExportDirEnabled"), QStringLiteral("exportDirEnabled")},
            {QStringLiteral("BitTorrent/Session/TorrentExportDirectory"), QStringLiteral("exportDir")},
            {QStringLiteral("Downloads/FinishedExportDirEnabled"), QStringLiteral("exportDirFinishedEnabled")},
            {QStringLiteral("BitTorrent/Session/FinishedTorrentExportDirectory"), QStringLiteral("exportDirFinished")},
            {QStringLiteral("BitTorrent/ExcludedFileNamesEnabled"), QStringLiteral("excludedFileNamesEnabled")},
            {QStringLiteral("BitTorrent/Session/ExcludedFileNames"), QStringLiteral("excludedFileNames")},
            {QStringLiteral("Preferences/MailNotification/enabled"), QStringLiteral("mailEnabled")},
            {QStringLiteral("Preferences/MailNotification/sender"), QStringLiteral("mailSender")},
            {QStringLiteral("Preferences/MailNotification/email"), QStringLiteral("mailDest")},
            {QStringLiteral("Preferences/MailNotification/smtp_server"), QStringLiteral("mailSMTP")},
            {QStringLiteral("Preferences/MailNotification/SMTPEncryptionType"), QStringLiteral("mailSMTPEncryption")},
            {QStringLiteral("Preferences/MailNotification/req_auth"), QStringLiteral("mailAuth")},
            {QStringLiteral("Preferences/MailNotification/username"), QStringLiteral("mailUsername")},
            {QStringLiteral("Preferences/MailNotification/password"), QStringLiteral("mailPassword")},
            {QStringLiteral("AutoRun/OnTorrentAdded/Enabled"), QStringLiteral("autoRunOnAdded")},
            {QStringLiteral("AutoRun/OnTorrentAdded/Program"), QStringLiteral("autoRunOnAddedProgram")},
            {QStringLiteral("AutoRun/enabled"), QStringLiteral("autoRunOnFinished")},
            {QStringLiteral("AutoRun/program"), QStringLiteral("autoRunOnFinishedProgram")},

            // Connection
            {QStringLiteral("BitTorrent/Session/BTProtocol"), QStringLiteral("btProtocol")},
            {QStringLiteral("BitTorrent/Session/Port"), QStringLiteral("port")},
            {QStringLiteral("Network/PortForwardingEnabled"), QStringLiteral("upnp")},
            {QStringLiteral("Connection/MaxConnectionsEnabled"), QStringLiteral("maxConnectionsEnabled")},
            {QStringLiteral("BitTorrent/Session/MaxConnections"), QStringLiteral("maxConnections")},
            {QStringLiteral("Connection/MaxConnectionsPerTorrentEnabled"), QStringLiteral("maxConnectionsPerTorrentEnabled")},
            {QStringLiteral("BitTorrent/Session/MaxConnectionsPerTorrent"), QStringLiteral("maxConnectionsPerTorrent")},
            {QStringLiteral("Connection/MaxUploadsEnabled"), QStringLiteral("maxUploadsEnabled")},
            {QStringLiteral("BitTorrent/Session/MaxUploads"), QStringLiteral("maxUploads")},
            {QStringLiteral("Connection/MaxUploadsPerTorrentEnabled"), QStringLiteral("maxUploadsPerTorrentEnabled")},
            {QStringLiteral("BitTorrent/Session/MaxUploadsPerTorrent"), QStringLiteral("maxUploadsPerTorrent")},
            {QStringLiteral("BitTorrent/Session/I2P/Enabled"), QStringLiteral("i2pEnabled")},
            {QStringLiteral("BitTorrent/Session/I2P/Address"), QStringLiteral("i2pAddress")},
            {QStringLiteral("BitTorrent/Session/I2P/Port"), QStringLiteral("i2pPort")},
            {QStringLiteral("BitTorrent/Session/I2P/MixedMode"), QStringLiteral("i2pMixedMode")},
            {QStringLiteral("Network/Proxy/Type"), QStringLiteral("proxyType")},
            {QStringLiteral("Network/Proxy/IP"), QStringLiteral("proxyIP")},
            {QStringLiteral("Network/Proxy/Port"), QStringLiteral("proxyPort")},
            {QStringLiteral("Network/Proxy/AuthEnabled"), QStringLiteral("proxyAuth")},
            {QStringLiteral("Network/Proxy/Username"), QStringLiteral("proxyUsername")},
            {QStringLiteral("Network/Proxy/Password"), QStringLiteral("proxyPassword")},
            {QStringLiteral("Network/Proxy/HostnameLookupEnabled"), QStringLiteral("proxyHostnameLookup")},
            {QStringLiteral("BitTorrent/Session/ProxyPeerConnections"), QStringLiteral("proxyPeerConnections")},
            {QStringLiteral("Network/Proxy/Profiles/BitTorrent"), QStringLiteral("useProxyForBT")},
            {QStringLiteral("Network/Proxy/Profiles/RSS"), QStringLiteral("useProxyForRSS")},
            {QStringLiteral("Network/Proxy/Profiles/Misc"), QStringLiteral("useProxyForGeneral")},
            {QStringLiteral("BitTorrent/Session/IPFilteringEnabled"), QStringLiteral("ipFilterEnabled")},
            {QStringLiteral("BitTorrent/Session/IPFilter"), QStringLiteral("ipFilterFile")},
            {QStringLiteral("BitTorrent/Session/TrackerFilteringEnabled"), QStringLiteral("ipFilterTrackers")},
            {QStringLiteral("BitTorrent/Session/BannedIPs"), QStringLiteral("bannedIPs")},

            // Speed
            {QStringLiteral("BitTorrent/Session/GlobalDLSpeedLimit"), QStringLiteral("globalDownloadLimit")},
            {QStringLiteral("BitTorrent/Session/GlobalUPSpeedLimit"), QStringLiteral("globalUploadLimit")},
            {QStringLiteral("BitTorrent/Session/AlternativeGlobalDLSpeedLimit"), QStringLiteral("altDownloadLimit")},
            {QStringLiteral("BitTorrent/Session/AlternativeGlobalUPSpeedLimit"), QStringLiteral("altUploadLimit")},
            {QStringLiteral("BitTorrent/Session/BandwidthSchedulerEnabled"), QStringLiteral("schedulerEnabled")},
            {QStringLiteral("Preferences/Scheduler/start_time"), QStringLiteral("schedulerStart")},
            {QStringLiteral("Preferences/Scheduler/end_time"), QStringLiteral("schedulerEnd")},
            {QStringLiteral("Preferences/Scheduler/days"), QStringLiteral("schedulerDays")},
            {QStringLiteral("BitTorrent/Session/uTPRateLimited"), QStringLiteral("limitUTPRate")},
            {QStringLiteral("BitTorrent/Session/IncludeOverheadInLimits"), QStringLiteral("limitTCPOverhead")},
            {QStringLiteral("Speed/ApplyLimitToLAN"), QStringLiteral("applyLimitsToLAN")},

            // BitTorrent
            {QStringLiteral("BitTorrent/Session/DHTEnabled"), QStringLiteral("dht")},
            {QStringLiteral("BitTorrent/Session/PeXEnabled"), QStringLiteral("pex")},
            {QStringLiteral("BitTorrent/Session/LSDEnabled"), QStringLiteral("lsd")},
            {QStringLiteral("BitTorrent/Session/Encryption"), QStringLiteral("encryption")},
            {QStringLiteral("BitTorrent/Session/AnonymousModeEnabled"), QStringLiteral("anonymousMode")},
            {QStringLiteral("BitTorrent/Session/MaxActiveCheckingTorrents"), QStringLiteral("maxActiveCheckingTorrents")},
            {QStringLiteral("BitTorrent/Session/QueueingSystemEnabled"), QStringLiteral("queueingEnabled")},
            {QStringLiteral("BitTorrent/Session/MaxActiveDownloads"), QStringLiteral("maxActiveDownloads")},
            {QStringLiteral("BitTorrent/Session/MaxActiveUploads"), QStringLiteral("maxActiveUploads")},
            {QStringLiteral("BitTorrent/Session/MaxActiveTorrents"), QStringLiteral("maxActiveTorrents")},
            {QStringLiteral("BitTorrent/Session/IgnoreSlowTorrentsForQueueing"), QStringLiteral("ignoreSlowTorrents")},
            {QStringLiteral("BitTorrent/Session/SlowTorrentsDownloadRate"), QStringLiteral("slowDownloadRate")},
            {QStringLiteral("BitTorrent/Session/SlowTorrentsUploadRate"), QStringLiteral("slowUploadRate")},
            {QStringLiteral("BitTorrent/Session/SlowTorrentsInactivityTimer"), QStringLiteral("slowInactivityTimer")},
            {QStringLiteral("Seeding/MaxRatioEnabled"), QStringLiteral("shareRatioLimitEnabled")},
            {QStringLiteral("BitTorrent/Session/GlobalMaxRatio"), QStringLiteral("shareRatioLimit")},
            {QStringLiteral("Seeding/MaxSeedingMinutesEnabled"), QStringLiteral("shareSeedingTimeLimitEnabled")},
            {QStringLiteral("BitTorrent/Session/GlobalMaxSeedingMinutes"), QStringLiteral("shareSeedingTimeLimit")},
            {QStringLiteral("Seeding/MaxInactiveSeedingMinutesEnabled"), QStringLiteral("shareInactiveSeedingTimeLimitEnabled")},
            {QStringLiteral("BitTorrent/Session/GlobalMaxInactiveSeedingMinutes"), QStringLiteral("shareInactiveSeedingTimeLimit")},
            {QStringLiteral("BitTorrent/Session/ShareLimitsMode"), QStringLiteral("shareLimitsMode")},
            {QStringLiteral("BitTorrent/Session/ShareLimitAction"), QStringLiteral("shareLimitAction")},
            {QStringLiteral("BitTorrent/Session/AddTrackersEnabled"), QStringLiteral("addTrackersEnabled")},
            {QStringLiteral("BitTorrent/Session/AdditionalTrackers"), QStringLiteral("additionalTrackers")},
            {QStringLiteral("BitTorrent/Session/AddTrackersFromURLEnabled"), QStringLiteral("addTrackersFromURLEnabled")},
            {QStringLiteral("BitTorrent/Session/AdditionalTrackersURL"), QStringLiteral("additionalTrackersURL")},
            {QStringLiteral("BitTorrent/Session/AdditionalTrackersFromURL"), QStringLiteral("additionalTrackersFromURL")},

            // RSS
            {QStringLiteral("RSS/Session/EnableProcessing"), QStringLiteral("rssProcessingEnabled")},
            {QStringLiteral("RSS/Session/RefreshInterval"), QStringLiteral("rssRefreshInterval")},
            {QStringLiteral("RSS/Session/FetchDelay"), QStringLiteral("rssFetchDelay")},
            {QStringLiteral("RSS/Session/MaxArticlesPerFeed"), QStringLiteral("rssMaxArticlesPerFeed")},
            {QStringLiteral("RSS/AutoDownloader/EnableProcessing"), QStringLiteral("rssAutoDownloadEnabled")},
            {QStringLiteral("RSS/AutoDownloader/DownloadRepacks"), QStringLiteral("rssDownloadRepacks")},
            {QStringLiteral("RSS/AutoDownloader/SmartEpisodeFilter"), QStringLiteral("rssSmartEpisodeFilters")},

            // Web UI / DynDNS
            {QStringLiteral("Preferences/WebUI/Enabled"), QStringLiteral("webUIEnabled")},
            {QStringLiteral("Preferences/WebUI/Address"), QStringLiteral("webUIAddress")},
            {QStringLiteral("Preferences/WebUI/Port"), QStringLiteral("webUIPort")},
            {QStringLiteral("Preferences/WebUI/UseUPnP"), QStringLiteral("webUIUPnP")},
            {QStringLiteral("Preferences/WebUI/ServerDomains"), QStringLiteral("webUIServerDomains")},
            {QStringLiteral("Preferences/WebUI/Username"), QStringLiteral("webUIUsername")},
            {QStringLiteral("Preferences/WebUI/Password_Plaintext"), QStringLiteral("webUIPassword")},
            {QStringLiteral("WebUI/BypassLocalAuth"), QStringLiteral("webUILocalAuth")},
            {QStringLiteral("Preferences/WebUI/AuthSubnetWhitelistEnabled"), QStringLiteral("webUIAuthSubnetWhitelistEnabled")},
            {QStringLiteral("Preferences/WebUI/AuthSubnetWhitelist"), QStringLiteral("webUIAuthSubnetWhitelist")},
            {QStringLiteral("Preferences/WebUI/MaxAuthenticationFailCount"), QStringLiteral("webUIMaxAuthFailCount")},
            {QStringLiteral("Preferences/WebUI/BanDuration"), QStringLiteral("webUIBanDuration")},
            {QStringLiteral("Preferences/WebUI/SessionTimeout"), QStringLiteral("webUISessionTimeout")},
            {QStringLiteral("Preferences/WebUI/ClickjackingProtection"), QStringLiteral("webUIClickjacking")},
            {QStringLiteral("Preferences/WebUI/CSRFProtection"), QStringLiteral("webUICSRF")},
            {QStringLiteral("Preferences/WebUI/SecureCookie"), QStringLiteral("webUISecureCookie")},
            {QStringLiteral("Preferences/WebUI/HostHeaderValidation"), QStringLiteral("webUIHostHeaderValidation")},
            {QStringLiteral("Preferences/WebUI/HTTPS/Enabled"), QStringLiteral("webUIHttps")},
            {QStringLiteral("Preferences/WebUI/HTTPS/CertificatePath"), QStringLiteral("webUIHttpsCert")},
            {QStringLiteral("Preferences/WebUI/HTTPS/KeyPath"), QStringLiteral("webUIHttpsKey")},
            {QStringLiteral("Preferences/WebUI/AlternativeUIEnabled"), QStringLiteral("webUIAltEnabled")},
            {QStringLiteral("Preferences/WebUI/RootFolder"), QStringLiteral("webUIRootFolder")},
            {QStringLiteral("Preferences/WebUI/CustomHTTPHeadersEnabled"), QStringLiteral("webUICustomHeadersEnabled")},
            {QStringLiteral("Preferences/WebUI/CustomHTTPHeaders"), QStringLiteral("webUICustomHeaders")},
            {QStringLiteral("Preferences/WebUI/ReverseProxySupportEnabled"), QStringLiteral("webUIReverseProxyEnabled")},
            {QStringLiteral("Preferences/WebUI/TrustedReverseProxiesList"), QStringLiteral("webUIReverseProxyList")},
            {QStringLiteral("Preferences/DynDNS/Enabled"), QStringLiteral("dynDNSEnabled")},
            {QStringLiteral("Preferences/DynDNS/Service"), QStringLiteral("dynDNSService")},
            {QStringLiteral("Preferences/DynDNS/DomainName"), QStringLiteral("dynDNSDomain")},
            {QStringLiteral("Preferences/DynDNS/Username"), QStringLiteral("dynDNSUsername")},
            {QStringLiteral("Preferences/DynDNS/Password"), QStringLiteral("dynDNSPassword")},

            // Advanced settings also used by typed core appliers.
            {QStringLiteral("BitTorrent/Session/Interface"), QStringLiteral("networkInterface")},
            {QStringLiteral("BitTorrent/Session/InterfaceAddress"), QStringLiteral("networkInterfaceAddress")},
            {QStringLiteral("Preferences/Search/pythonExecutablePath"), QStringLiteral("pythonExecutablePath")}
        };
        return aliases;
    }

    /// AdvancedPage is static QML, while AdvancedSettingsModel owns the complete
    /// typed getter/setter table. Routing through it avoids a second, divergent
    /// implementation of dozens of libtorrent settings.
    const QHash<QString, QString> &advancedAliases()
    {
        static const QHash<QString, QString> aliases = {
            {QStringLiteral("BitTorrent/Session/ResumeDataStorageType"), QStringLiteral("resumeDataStorageType")},
            {QStringLiteral("BitTorrent/Session/TorrentContentRemoveOption"), QStringLiteral("torrentContentRemoveOption")},
            {QStringLiteral("BitTorrent/Session/SaveResumeDataInterval"), QStringLiteral("saveResumeDataInterval")},
            {QStringLiteral("BitTorrent/Session/SaveStatisticsInterval"), QStringLiteral("saveStatisticsInterval")},
            {QStringLiteral("BitTorrent/TorrentFileSizeLimit"), QStringLiteral("torrentFileSizeLimit")},
            {QStringLiteral("Preferences/Advanced/confirmTorrentRecheck"), QStringLiteral("confirmTorrentRecheck")},
            {QStringLiteral("Preferences/Advanced/RecheckOnCompletion"), QStringLiteral("recheckCompleted")},
            {QStringLiteral("BitTorrent/Session/RefreshInterval"), QStringLiteral("refreshInterval")},
            {QStringLiteral("Preferences/Connection/ResolvePeerCountries"), QStringLiteral("resolveCountries")},
            {QStringLiteral("Preferences/Connection/ResolvePeerHostNames"), QStringLiteral("resolveHosts")},
            {QStringLiteral("Preferences/Advanced/confirmRemoveAllTags"), QStringLiteral("confirmRemoveAllTags")},
            {QStringLiteral("GUI/ConfirmActions/RemoveTrackerFromAllTorrents"), QStringLiteral("confirmRemoveTrackerFromAllTorrents")},
            {QStringLiteral("BitTorrent/Session/ReannounceWhenAddressChanged"), QStringLiteral("reannounceWhenAddressChanged")},
            {QStringLiteral("AddNewTorrentDialog/SavePathHistoryLength"), QStringLiteral("savePathHistoryLength")},
            {QStringLiteral("SpeedWidget/Enabled"), QStringLiteral("speedWidgetEnabled")},
            {QStringLiteral("Preferences/Advanced/EnableIconsInMenus"), QStringLiteral("iconsInMenus")},
            {QStringLiteral("AddNewTorrentDialog/Attached"), QStringLiteral("attachedAddNewTorrentDialog")},
            {QStringLiteral("BitTorrent/TrackerEnabled"), QStringLiteral("trackerEnabled")},
            {QStringLiteral("Preferences/Advanced/trackerPort"), QStringLiteral("trackerPort")},
            {QStringLiteral("Preferences/Advanced/trackerPortForwarding"), QStringLiteral("trackerPortForwarding")},
            {QStringLiteral("Preferences/Advanced/markOfTheWeb"), QStringLiteral("markOfTheWeb")},
            {QStringLiteral("Preferences/Advanced/IgnoreSSLErrors"), QStringLiteral("ignoreSSLErrors")},
            {QStringLiteral("BitTorrent/Session/StartPaused"), QStringLiteral("startSessionPaused")},
            {QStringLiteral("BitTorrent/Session/ShutdownTimeout"), QStringLiteral("sessionShutdownTimeout")},
            {QStringLiteral("BitTorrent/BdecodeDepthLimit"), QStringLiteral("bdecodeDepthLimit")},
            {QStringLiteral("BitTorrent/BdecodeTokenLimit"), QStringLiteral("bdecodeTokenLimit")},
            {QStringLiteral("BitTorrent/Session/AsyncIOThreadsCount"), QStringLiteral("asyncIOThreads")},
            {QStringLiteral("BitTorrent/Session/HashingThreadsCount"), QStringLiteral("hashingThreads")},
            {QStringLiteral("BitTorrent/Session/FilePoolSize"), QStringLiteral("filePoolSize")},
            {QStringLiteral("BitTorrent/Session/CheckingMemUsageSize"), QStringLiteral("checkingMemUsage")},
            {QStringLiteral("BitTorrent/Session/DiskQueueSize"), QStringLiteral("diskQueueSize")},
            {QStringLiteral("BitTorrent/Session/DiskIOType"), QStringLiteral("diskIOType")},
            {QStringLiteral("BitTorrent/Session/DiskIOReadMode"), QStringLiteral("diskIOReadMode")},
            {QStringLiteral("BitTorrent/Session/DiskIOWriteMode"), QStringLiteral("diskIOWriteMode")},
            {QStringLiteral("BitTorrent/Session/PieceExtentAffinity"), QStringLiteral("pieceExtentAffinity")},
            {QStringLiteral("BitTorrent/Session/SuggestMode"), QStringLiteral("suggestMode")},
            {QStringLiteral("BitTorrent/Session/SendBufferWatermark"), QStringLiteral("sendBufferWatermark")},
            {QStringLiteral("BitTorrent/Session/SendBufferLowWatermark"), QStringLiteral("sendBufferLowWatermark")},
            {QStringLiteral("BitTorrent/Session/SendBufferWatermarkFactor"), QStringLiteral("sendBufferWatermarkFactor")},
            {QStringLiteral("BitTorrent/Session/ConnectionSpeed"), QStringLiteral("connectionSpeed")},
            {QStringLiteral("BitTorrent/Session/SeedingOutgoingConnectionsEnabled"), QStringLiteral("seedingOutgoingConnections")},
            {QStringLiteral("BitTorrent/Session/SocketSendBufferSize"), QStringLiteral("socketSendBufferSize")},
            {QStringLiteral("BitTorrent/Session/SocketReceiveBufferSize"), QStringLiteral("socketReceiveBufferSize")},
            {QStringLiteral("BitTorrent/Session/SocketBacklogSize"), QStringLiteral("socketBacklogSize")},
            {QStringLiteral("BitTorrent/Session/OutgoingPortsMin"), QStringLiteral("outgoingPortsMin")},
            {QStringLiteral("BitTorrent/Session/OutgoingPortsMax"), QStringLiteral("outgoingPortsMax")},
            {QStringLiteral("BitTorrent/Session/UPnPLeaseDuration"), QStringLiteral("upnpLeaseDuration")},
            {QStringLiteral("BitTorrent/Session/PeerToS"), QStringLiteral("peerDSCP")},
            {QStringLiteral("BitTorrent/Session/uTPMixedMode"), QStringLiteral("utpMixedMode")},
            {QStringLiteral("BitTorrent/Session/HostnameCacheTTL"), QStringLiteral("hostnameCacheTTL")},
            {QStringLiteral("BitTorrent/Session/IDNSupportEnabled"), QStringLiteral("idnSupport")},
            {QStringLiteral("BitTorrent/Session/MultiConnectionsPerIp"), QStringLiteral("multiConnectionsPerIp")},
            {QStringLiteral("BitTorrent/Session/ValidateHTTPSTrackerCertificate"), QStringLiteral("validateHTTPSTrackerCertificate")},
            {QStringLiteral("BitTorrent/Session/SSRFMitigation"), QStringLiteral("ssrfMitigation")},
            {QStringLiteral("BitTorrent/Session/BlockPeersOnPrivilegedPorts"), QStringLiteral("blockPeersOnPrivilegedPorts")},
            {QStringLiteral("BitTorrent/Session/ChokingAlgorithm"), QStringLiteral("chokingAlgorithm")},
            {QStringLiteral("BitTorrent/Session/SeedChokingAlgorithm"), QStringLiteral("seedChokingAlgorithm")},
            {QStringLiteral("BitTorrent/Session/AnnounceToAllTrackers"), QStringLiteral("announceAllTrackers")},
            {QStringLiteral("BitTorrent/Session/AnnounceToAllTiers"), QStringLiteral("announceAllTiers")},
            {QStringLiteral("BitTorrent/Session/AnnounceIP"), QStringLiteral("announceIP")},
            {QStringLiteral("BitTorrent/Session/AnnouncePort"), QStringLiteral("announcePort")},
            {QStringLiteral("BitTorrent/Session/MaxConcurrentHTTPAnnounces"), QStringLiteral("maxConcurrentHTTPAnnounces")},
            {QStringLiteral("BitTorrent/Session/StopTrackerTimeout"), QStringLiteral("stopTrackerTimeout")},
            {QStringLiteral("BitTorrent/Session/PeerTurnover"), QStringLiteral("peerTurnover")},
            {QStringLiteral("BitTorrent/Session/PeerTurnoverCutOff"), QStringLiteral("peerTurnoverCutoff")},
            {QStringLiteral("BitTorrent/Session/PeerTurnoverInterval"), QStringLiteral("peerTurnoverInterval")},
            {QStringLiteral("BitTorrent/Session/RequestQueueSize"), QStringLiteral("requestQueueSize")},
            {QStringLiteral("BitTorrent/Session/DHTBootstrapNodes"), QStringLiteral("dhtBootstrapNodes")},
            {QStringLiteral("BitTorrent/Session/I2P/InboundQuantity"), QStringLiteral("i2pInboundQuantity")},
            {QStringLiteral("BitTorrent/Session/I2P/OutboundQuantity"), QStringLiteral("i2pOutboundQuantity")},
            {QStringLiteral("BitTorrent/Session/I2P/InboundLength"), QStringLiteral("i2pInboundLength")},
            {QStringLiteral("BitTorrent/Session/I2P/OutboundLength"), QStringLiteral("i2pOutboundLength")}
        };
        return aliases;
    }

    const QSet<QString> ADVANCED_RESTART_KEYS = {
        QStringLiteral("BitTorrent/Session/ResumeDataStorageType"),
        QStringLiteral("BitTorrent/Session/DiskIOType"),
        QStringLiteral("BitTorrent/Session/AnnounceIP"),
        QStringLiteral("BitTorrent/Session/AnnouncePort")
    };

    QString timeToString(const QTime &time)
    {
        return time.toString(QStringLiteral("HH:mm"));
    }

    QTime stringToTime(const QString &str)
    {
        const QTime time = QTime::fromString(str, QStringLiteral("HH:mm"));
        return time.isValid() ? time : QTime(0, 0);
    }
}

OptionsController *OptionsController::create(QQmlEngine *, QJSEngine *)
{
    static auto *instance = new OptionsController;
    // Ownership stays with the app; QML must not delete the singleton.
    QQmlEngine::setObjectOwnership(instance, QQmlEngine::CppOwnership);
    return instance;
}

OptionsController *OptionsController::existingInstance()
{
    return s_instance;
}

OptionsController::OptionsController(QObject *parent)
    : QObject(parent)
    , m_watchedFoldersModel(new WatchedFoldersModel(this))
    , m_advancedSettingsModel(new AdvancedSettingsModel(this))
{
    if (!s_instance)
        s_instance = this;
    qCDebug(lcUi) << "OptionsController: constructing";

    connect(m_watchedFoldersModel, &WatchedFoldersModel::modifiedChanged, this, [this]
    {
        emit modifiedChanged();
        bumpRevision();
    });
    connect(m_advancedSettingsModel, &AdvancedSettingsModel::modifiedChanged, this, [this]
    {
        emit modifiedChanged();
        bumpRevision();
    });
    if (auto *session = Session::instance())
        connect(session, &Session::IPFilterParsed, this, &OptionsController::ipFilterParsed);

    load();
}

OptionsController::~OptionsController()
{
    if (s_instance == this)
        s_instance = nullptr;
}

bool OptionsController::isModified() const
{
    return m_modified
        || (m_watchedFoldersModel && m_watchedFoldersModel->isModified())
        || (m_advancedSettingsModel && m_advancedSettingsModel->isModified());
}

QObject *OptionsController::watchedFoldersModel() const
{
    return m_watchedFoldersModel;
}

bool OptionsController::apiKeyValid() const
{
    return !staged(QStringLiteral("webUIApiKey")).toString().trimmed().isEmpty();
}

int OptionsController::lastViewedTab() const
{
    // Stored generically; default to the Behavior tab.
    return m_values.value(QStringLiteral("__lastViewedTab"), BehaviorTab).toInt();
}

void OptionsController::setLastViewedTab(int tab)
{
    if (lastViewedTab() == tab)
        return;
    qCDebug(lcUi) << "OptionsController: last viewed tab ->" << tab;
    m_values[QStringLiteral("__lastViewedTab")] = tab;
    emit lastViewedTabChanged();
}

// ---------------------------------------------------------------------------
// Staging helpers
// ---------------------------------------------------------------------------

QVariant OptionsController::staged(const QString &key, const QVariant &def) const
{
    return m_values.value(key, def);
}

void OptionsController::stage(const QString &key, const QVariant &value)
{
    m_values[key] = value;
}

QVariant OptionsController::value(const QString &key, const QVariant &defaultValue) const
{
    // This UI-only key is expressed in KiB; the persisted engine key is bytes.
    if (key == QStringLiteral("Application/FileLogger/MaxSizeKiB"))
    {
        const QString rawKey = QStringLiteral("Application/FileLogger/MaxSizeBytes");
        const qlonglong defaultBytes = defaultValue.toLongLong() * 1024;
        const QVariant bytes = m_values.contains(rawKey)
            ? m_values.value(rawKey)
            : Preferences::instance()->value(rawKey, defaultBytes);
        return bytes.toLongLong() / 1024;
    }

    const QString advancedKey = advancedAliases().value(key);
    if (!advancedKey.isEmpty())
    {
        const int row = advancedRowForKey(advancedKey);
        if (row >= 0)
            return m_advancedSettingsModel->value(row);
    }

    const auto &aliases = legacyAliases();
    const QString canonicalKey = aliases.value(key, key);

    // QML presents scheduler times as minutes since midnight; the typed engine
    // bridge deliberately stores an HH:mm string.
    if ((key == QStringLiteral("Preferences/Scheduler/start_time"))
            || (key == QStringLiteral("Preferences/Scheduler/end_time")))
    {
        const QTime time = stringToTime(staged(canonicalKey).toString());
        return time.isValid() ? ((time.hour() * 60) + time.minute()) : defaultValue;
    }

    if (key == QStringLiteral("Downloads/DefaultTMM"))
        return staged(canonicalKey, defaultValue.toInt() != 0).toBool() ? 1 : 0;

    if ((key == QStringLiteral("Downloads/OnCategoryChanged"))
            || (key == QStringLiteral("Downloads/OnDefaultSavePathChanged"))
            || (key == QStringLiteral("Downloads/OnCategorySavePathChanged")))
    {
        // QML index 0 means relocate, while the engine getter is a positive
        // "relocate" flag (itself the inverse of DisableAutoTMM...).
        return staged(canonicalKey, defaultValue.toInt() == 0).toBool() ? 0 : 1;
    }

    if (key == QStringLiteral("WebUI/BypassLocalAuth"))
        return !staged(canonicalKey, !defaultValue.toBool()).toBool();

    if (key == QStringLiteral("BitTorrent/Session/ShareLimitAction"))
    {
        // ShareLimitAction preserves legacy enum values: SuperSeeding=2 and
        // RemoveWithContent=3, while the QML combo displays those in reverse.
        const int engineValue = staged(canonicalKey, 0).toInt();
        return (engineValue == 2) ? 3 : ((engineValue == 3) ? 2 : qMax(0, engineValue));
    }

    if (m_values.contains(canonicalKey) || aliases.contains(key))
        return m_values.value(canonicalKey, defaultValue);

    // Exact legacy keys without a dedicated engine accessor still round-trip
    // through SettingsStorage, but only changed keys are written on Apply.
    return m_values.contains(key)
        ? m_values.value(key)
        : Preferences::instance()->value(key, defaultValue);
}

void OptionsController::setValue(const QString &key, const QVariant &value)
{
    if (key == QStringLiteral("Application/FileLogger/MaxSizeKiB"))
    {
        const QString rawKey = QStringLiteral("Application/FileLogger/MaxSizeBytes");
        const QVariant bytes = value.toLongLong() * 1024;
        const QVariant current = m_values.contains(rawKey)
            ? m_values.value(rawKey)
            : Preferences::instance()->value(rawKey, 65 * 1024);
        if (current == bytes)
            return;

        qCDebug(lcUi) << "OptionsController: stage" << rawKey;
        m_values[rawKey] = bytes;
        m_passthroughKeys.insert(rawKey);
        markModified();
        bumpRevision();
        return;
    }

    const QString advancedKey = advancedAliases().value(key);
    if (!advancedKey.isEmpty())
    {
        const int row = advancedRowForKey(advancedKey);
        if (row >= 0)
        {
            if (m_advancedSettingsModel->value(row) == value)
                return;
            m_advancedSettingsModel->setValue(row, value);
            if (ADVANCED_RESTART_KEYS.contains(key))
                markRestartRequired();
            return;
        }
    }

    const auto &aliases = legacyAliases();
    const QString canonicalKey = aliases.value(key, key);
    QVariant canonicalValue = value;

    if ((key == QStringLiteral("Preferences/Scheduler/start_time"))
            || (key == QStringLiteral("Preferences/Scheduler/end_time")))
    {
        const int minutes = qBound(0, value.toInt(), (24 * 60) - 1);
        canonicalValue = timeToString(QTime(minutes / 60, minutes % 60));
    }
    else if (key == QStringLiteral("Downloads/DefaultTMM"))
    {
        canonicalValue = (value.toInt() != 0);
    }
    else if ((key == QStringLiteral("Downloads/OnCategoryChanged"))
            || (key == QStringLiteral("Downloads/OnDefaultSavePathChanged"))
            || (key == QStringLiteral("Downloads/OnCategorySavePathChanged")))
    {
        canonicalValue = (value.toInt() == 0);
    }
    else if (key == QStringLiteral("WebUI/BypassLocalAuth"))
    {
        canonicalValue = !value.toBool();
    }
    else if (key == QStringLiteral("BitTorrent/Session/ShareLimitAction"))
    {
        const int comboIndex = value.toInt();
        canonicalValue = (comboIndex == 2) ? 3 : ((comboIndex == 3) ? 2 : comboIndex);
    }

    const bool isCoreValue = aliases.contains(key) || m_values.contains(canonicalKey);
    const QVariant current = isCoreValue
        ? m_values.value(canonicalKey)
        : (m_values.contains(key) ? m_values.value(key) : Preferences::instance()->value(key));
    if (current == canonicalValue)
        return;

    const bool oldApiKeyValid = apiKeyValid();
    const QString storageKey = isCoreValue ? canonicalKey : key;
    qCDebug(lcUi) << "OptionsController: stage" << storageKey;
    m_values[storageKey] = canonicalValue;
    if (!isCoreValue)
        m_passthroughKeys.insert(storageKey);
    markModified();
    bumpRevision();

    if (RESTART_KEYS.contains(canonicalKey))
        markRestartRequired();

    if ((canonicalKey == QStringLiteral("webUIApiKey")) && (oldApiKeyValid != apiKeyValid()))
        emit apiKeyValidChanged();
}

void OptionsController::markModified()
{
    const bool wasModified = isModified();
    m_modified = true;
    if (!wasModified)
        emit modifiedChanged();
}

void OptionsController::markRestartRequired()
{
    if (!m_restartRequired)
    {
        qCInfo(lcUi) << "OptionsController: a staged change requires an application restart";
        m_restartRequired = true;
        emit restartRequiredChanged();
    }
}

void OptionsController::bumpRevision()
{
    ++m_revision;
    emit revisionChanged();
}

int OptionsController::advancedRowForKey(const QString &key) const
{
    if (!m_advancedSettingsModel)
        return -1;

    for (int row = 0; row < m_advancedSettingsModel->rowCount(); ++row)
    {
        const QModelIndex idx = m_advancedSettingsModel->index(row, 0);
        if (m_advancedSettingsModel->data(idx, AdvancedSettingsModel::KeyRole).toString() == key)
            return row;
    }
    return -1;
}

int OptionsController::randomPort() const
{
    return QRandomGenerator::global()->bounded(1024, 65536);
}

QVariantList OptionsController::networkInterfaces() const
{
    QVariantList result;
    result.append(QVariantMap {
        {QStringLiteral("text"), tr("Any interface")},
        {QStringLiteral("value"), QString()}
    });

    QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    std::sort(interfaces.begin(), interfaces.end(), [](const QNetworkInterface &lhs, const QNetworkInterface &rhs)
    {
        return lhs.humanReadableName().localeAwareCompare(rhs.humanReadableName()) < 0;
    });

    QSet<QString> seenNames;
    for (const QNetworkInterface &iface : interfaces)
    {
        if (!iface.isValid() || iface.name().isEmpty() || seenNames.contains(iface.name()))
            continue;
        seenNames.insert(iface.name());
        const QString label = iface.humanReadableName().isEmpty()
            ? iface.name()
            : iface.humanReadableName();
        result.append(QVariantMap {
            {QStringLiteral("text"), label},
            {QStringLiteral("value"), iface.name()}
        });
    }
    return result;
}

QVariantList OptionsController::networkInterfaceAddresses() const
{
    QVariantList result = {
        QVariantMap {{QStringLiteral("text"), tr("All addresses")}, {QStringLiteral("value"), QString()}},
        QVariantMap {{QStringLiteral("text"), tr("All IPv4 addresses")}, {QStringLiteral("value"), QStringLiteral("0.0.0.0")}},
        QVariantMap {{QStringLiteral("text"), tr("All IPv6 addresses")}, {QStringLiteral("value"), QStringLiteral("::")}}
    };

    const QString selectedInterface = staged(QStringLiteral("networkInterface")).toString();
    QSet<QString> addresses;
    for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces())
    {
        if (!selectedInterface.isEmpty() && (iface.name() != selectedInterface))
            continue;
        for (const QNetworkAddressEntry &entry : iface.addressEntries())
        {
            const QHostAddress address = entry.ip();
            if (address.isNull() || (address.protocol() == QAbstractSocket::UnknownNetworkLayerProtocol))
                continue;
            addresses.insert(address.toString());
        }
    }

    QStringList sortedAddresses(addresses.cbegin(), addresses.cend());
    sortedAddresses.sort(Qt::CaseInsensitive);
    for (const QString &address : sortedAddresses)
    {
        result.append(QVariantMap {
            {QStringLiteral("text"), address},
            {QStringLiteral("value"), address}
        });
    }
    return result;
}

QVariantMap OptionsController::watchedFolderOptions(const int row) const
{
    if (!m_watchedFoldersModel)
        return {};

    QVariantMap flat = m_watchedFoldersModel->folderOptions(row);
    if (flat.isEmpty() && m_watchedFoldersModel->folderPath(row).isEmpty())
        return {};

    QVariantMap result;
    result.insert(QStringLiteral("path"), m_watchedFoldersModel->folderPath(row));
    result.insert(QStringLiteral("recursive"), flat.take(QStringLiteral("recursive")));
    result.insert(QStringLiteral("params"), flat);
    return result;
}

namespace
{
    QVariantMap flattenWatchedFolderOptions(const QVariantMap &options)
    {
        QVariantMap flat = options.value(QStringLiteral("params")).toMap();
        if (flat.isEmpty())
            flat = options;
        flat.remove(QStringLiteral("path"));
        flat.remove(QStringLiteral("params"));
        flat.insert(QStringLiteral("recursive"), options.value(QStringLiteral("recursive"), false));
        return flat;
    }
}

bool OptionsController::addWatchedFolder(const QString &path, const QVariantMap &options)
{
    return m_watchedFoldersModel
        && m_watchedFoldersModel->addFolder(path, flattenWatchedFolderOptions(options));
}

void OptionsController::setWatchedFolderOptions(const int row, const QVariantMap &options)
{
    if (m_watchedFoldersModel)
        m_watchedFoldersModel->setFolderOptions(row, flattenWatchedFolderOptions(options));
}

void OptionsController::removeWatchedFolder(const int row)
{
    if (m_watchedFoldersModel)
        m_watchedFoldersModel->removeFolder(row);
}

QString OptionsController::maskedApiKey() const
{
    const QString apiKey = staged(QStringLiteral("webUIApiKey")).toString();
    if (apiKey.isEmpty())
        return {};
    return QString(12, QChar(0x2022)) + apiKey.right(4);
}

void OptionsController::rotateApiKey()
{
    QByteArray generated;
    generated.reserve(64);
    for (int i = 0; i < 8; ++i)
    {
        generated += QByteArray::number(QRandomGenerator::system()->generate(), 16)
            .rightJustified(8, '0');
    }
    setValue(QStringLiteral("webUIApiKey"), QString::fromLatin1(generated));
}

void OptionsController::deleteApiKey()
{
    setValue(QStringLiteral("webUIApiKey"), QString());
}

bool OptionsController::copyApiKeyToClipboard() const
{
    const QString apiKey = staged(QStringLiteral("webUIApiKey")).toString();
    if (apiKey.isEmpty() || !QGuiApplication::clipboard())
        return false;
    QGuiApplication::clipboard()->setText(apiKey);
    return true;
}

bool OptionsController::isValidBannedIPAddress(const QString &address) const
{
    // Keep this deliberately identical to SessionImpl::setBannedIPs(): a
    // value accepted in the editor must survive the engine's final filter.
    lt::error_code error;
    [[maybe_unused]] const lt::address parsed = lt::make_address(address.toStdString(), error);
    return !error;
}

bool OptionsController::isValidWebUISubnet(const QString &subnet) const
{
    // Preferences::setWebUIAuthSubnetWhitelist() applies this same filter as
    // defense in depth when the staged values are committed.
    return Utils::Net::parseSubnet(subnet.trimmed()).has_value();
}

void OptionsController::reloadIPFilter()
{
    if (!staged(QStringLiteral("ipFilterEnabled"), false).toBool())
    {
        emit ipFilterParsed(true, 0);
        return;
    }

    const QString fileName = staged(QStringLiteral("ipFilterFile")).toString().trimmed();
    QFile file(fileName);
    if (fileName.isEmpty() || !file.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        qCWarning(lcUi) << "OptionsController: cannot read staged IP filter" << fileName;
        emit ipFilterParsed(true, 0);
        return;
    }

    // The engine currently exposes parse completion but no public force-reload
    // entry point. Validate the staged file without mutating live settings; Apply
    // remains the only path that changes Session. Accept plain ranges/CIDR and
    // common PeerGuardian/eMule lines containing an IPv4 range plus metadata.
    static const QRegularExpression ipv4RangePattern(QStringLiteral(
        R"(((?:\d{1,3}\.){3}\d{1,3}(?:\s*(?:-|/)\s*(?:(?:\d{1,3}\.){3}\d{1,3}|\d{1,2}))?))"));

    int ruleCount = 0;
    int ignoredMalformedLines = 0;
    QTextStream stream(&file);
    while (!stream.atEnd())
    {
        const QString line = stream.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')) || line.startsWith(QLatin1Char(';')))
            continue;

        QString candidate = line;
        std::optional<Utils::Net::IPRange> range = Utils::Net::parseIPRange(candidate);
        if (!range)
        {
            const QRegularExpressionMatch match = ipv4RangePattern.match(line);
            if (match.hasMatch())
            {
                candidate = match.captured(1);
                range = Utils::Net::parseIPRange(candidate, true);
            }
        }

        if (range)
            ++ruleCount;
        else
            ++ignoredMalformedLines;
    }

    if (ignoredMalformedLines > 0)
        qCWarning(lcUi) << "OptionsController: ignored" << ignoredMalformedLines << "malformed IP-filter line(s)";
    emit ipFilterParsed(ruleCount == 0, ruleCount);
}

void OptionsController::sendTestEmail()
{
    auto *pref = Preferences::instance();
    const bool stagedSettingsDiffer =
        (staged(QStringLiteral("mailSender")).toString() != pref->getMailNotificationSender())
        || (staged(QStringLiteral("mailDest")).toString() != pref->getMailNotificationEmail())
        || (staged(QStringLiteral("mailSMTP")).toString() != pref->getMailNotificationSMTP())
        || (staged(QStringLiteral("mailSMTPEncryption")).toInt()
            != static_cast<int>(pref->getMailNotificationSMTPEncryptionType()))
        || (staged(QStringLiteral("mailAuth")).toBool() != pref->getMailNotificationSMTPAuth())
        || (staged(QStringLiteral("mailUsername")).toString() != pref->getMailNotificationSMTPUsername())
        || (staged(QStringLiteral("mailPassword")).toString() != pref->getMailNotificationSMTPPassword());

    if (stagedSettingsDiffer)
    {
        emit actionFeedback(QStringLiteral("testEmail"), false,
            tr("Apply the email settings before sending a test message."));
        return;
    }

    const QString sender = pref->getMailNotificationSender().trimmed();
    const QString destination = pref->getMailNotificationEmail().trimmed();
    const QString server = pref->getMailNotificationSMTP().trimmed();
    if (sender.isEmpty() || destination.isEmpty() || server.isEmpty())
    {
        emit actionFeedback(QStringLiteral("testEmail"), false,
            tr("Sender, recipient, and SMTP server are required."));
        return;
    }

    Net::SMTPClient::sendMail(sender, destination,
        tr("qBittorrent test email"),
        tr("This is a test email from qBittorrent."), this);
    emit actionFeedback(QStringLiteral("testEmail"), true,
        tr("Test email queued. Delivery details are available in the execution log."));
}

void OptionsController::openDynDNSRegistration()
{
    const int serviceValue = staged(QStringLiteral("dynDNSService"), 0).toInt();
    if ((serviceValue < static_cast<int>(DNS::Service::DynDNS))
            || (serviceValue > static_cast<int>(DNS::Service::NoIP)))
    {
        emit actionFeedback(QStringLiteral("dynDNS"), false,
            tr("No Dynamic DNS provider is selected."));
        return;
    }

    const QUrl url = Net::DNSUpdater::getRegistrationUrl(static_cast<DNS::Service>(serviceValue));
    const bool opened = url.isValid() && QDesktopServices::openUrl(url);
    emit actionFeedback(QStringLiteral("dynDNS"), opened,
        opened ? tr("Opened the provider registration page.")
               : tr("Could not open the provider registration page."));
}

void OptionsController::openWindowsDefaultApps()
{
#ifdef Q_OS_WIN
    // Match upstream qBittorrent: ask the trusted system Explorer to dispatch
    // the Settings URI instead of depending on a browser URL handler.
    const Path explorer = Utils::OS::windowsSystemPath().parentPath()
        / Path(QStringLiteral("explorer.exe"));
    const bool opened = QProcess::startDetached(explorer.data(),
        {QStringLiteral("ms-settings:defaultapps")});
    emit actionFeedback(QStringLiteral("windowsDefaultApps"), opened,
        opened ? tr("Opened Windows Default Apps settings.")
               : tr("Could not open Windows Default Apps settings."));
#else
    emit actionFeedback(QStringLiteral("windowsDefaultApps"), false,
        tr("Windows Default Apps settings are unavailable on this platform."));
#endif
}

// ---------------------------------------------------------------------------
// load() — engine -> staging map
// ---------------------------------------------------------------------------

void OptionsController::load()
{
    qCInfo(lcUi) << "OptionsController: loading all tabs from engine";
    const bool wasModified = isModified();
    const bool oldApiKeyValid = apiKeyValid();
    m_values.clear();
    m_passthroughKeys.clear();
    m_modified = false;

    if (m_watchedFoldersModel)
        m_watchedFoldersModel->reset();
    if (m_advancedSettingsModel)
        m_advancedSettingsModel->reset();

    loadBehavior();
    loadDownloads();
    loadConnection();
    loadSpeed();
    loadBitTorrent();
    loadSearch();
    loadRSS();
    loadWebUI();

    if (wasModified != isModified())
        emit modifiedChanged();
    if (m_restartRequired)
    {
        m_restartRequired = false;
        emit restartRequiredChanged();
    }
    if (oldApiKeyValid != apiKeyValid())
        emit apiKeyValidChanged();
    bumpRevision();
}

void OptionsController::reset()
{
    qCDebug(lcUi) << "OptionsController: reset() — discarding staged edits";
    load();
}

void OptionsController::loadBehavior()
{
    auto *pref = Preferences::instance();
    auto *session = Session::instance();
    auto *theme = ThemeManager::instance();

    stage(QStringLiteral("language"), pref->getLanguageMode());
    stage(QStringLiteral("englishFunnyLevel"), pref->value(
        ENGLISH_FUNNY_LEVEL_KEY, DEFAULT_ENGLISH_FUNNY_LEVEL).toInt());
    stage(QStringLiteral("cantoneseFunnyLevel"), pref->value(
        CANTONESE_FUNNY_LEVEL_KEY, DEFAULT_CANTONESE_FUNNY_LEVEL).toInt());
    stage(QStringLiteral("style"), pref->getStyle());
    stage(QStringLiteral("colorScheme"), static_cast<int>(theme->colorScheme()));
    stage(QStringLiteral("useCustomTheme"), pref->useCustomUITheme());
    stage(QStringLiteral("customThemePath"), pref->customUIThemePath().toString());

    stage(QStringLiteral("confirmDeletion"), pref->confirmTorrentDeletion());
    stage(QStringLiteral("alternatingRowColors"), pref->useAlternatingRowColors());
    stage(QStringLiteral("useTorrentStatesColors"), pref->useTorrentStatesColors());
    stage(QStringLiteral("progressBarFollowsTextColor"), pref->getProgressBarFollowsTextColor());
    stage(QStringLiteral("hideZeroValues"), pref->getHideZeroValues());
    stage(QStringLiteral("hideZeroComboValues"), pref->getHideZeroComboValues());
    stage(QStringLiteral("actionDblClickDl"), pref->getActionOnDblClOnTorrentDl());
    stage(QStringLiteral("actionDblClickFn"), pref->getActionOnDblClOnTorrentFn());
    stage(QStringLiteral("hideZeroStatusFilters"), pref->getHideZeroStatusFilters());
    stage(QStringLiteral("useSeparateTrackerStatusFilter"), pref->useSeparateTrackerStatusFilter());
    stage(QStringLiteral("torrentContentDrag"), pref->isTorrentContentDragEnabled());

    stage(QStringLiteral("statusbarFreeDiskSpace"), pref->isStatusbarFreeDiskSpaceDisplayed());
    stage(QStringLiteral("statusbarExternalIP"), pref->isStatusbarExternalIPDisplayed());

    // "Show splash screen" is the inverse of the stored "disabled" flag.
    stage(QStringLiteral("showSplashScreen"), !pref->isSplashScreenDisabled());
    stage(QStringLiteral("confirmOnExit"), pref->confirmOnExit());
    // "Confirm auto-exit" is the inverse of the stored "don't confirm" flag.
    stage(QStringLiteral("confirmAutoExit"), !pref->dontConfirmAutoExit());

#ifndef Q_OS_MACOS
    stage(QStringLiteral("systrayEnabled"), pref->systemTrayEnabled());
    stage(QStringLiteral("minimizeToTray"), pref->minimizeToTray());
    stage(QStringLiteral("closeToTray"), pref->closeToTray());
#endif
    stage(QStringLiteral("trayIconStyle"), static_cast<int>(theme->trayIconStyle()));

    stage(QStringLiteral("preventSuspendDownloading"), pref->preventFromSuspendWhenDownloading());
    stage(QStringLiteral("preventSuspendSeeding"), pref->preventFromSuspendWhenSeeding());

    stage(QStringLiteral("performanceWarning"), session->isPerformanceWarningEnabled());

#ifdef Q_OS_WIN
    stage(QStringLiteral("winStartup"), pref->WinStartup());
#endif
}

void OptionsController::loadDownloads()
{
    auto *pref = Preferences::instance();
    auto *session = Session::instance();

    stage(QStringLiteral("additionDialog"), pref->isAddNewTorrentDialogEnabled());
    stage(QStringLiteral("additionDialogFront"), pref->isAddNewTorrentDialogTopLevel());
    stage(QStringLiteral("contentLayout"), static_cast<int>(session->torrentContentLayout()));
    stage(QStringLiteral("addToQueueTop"), session->isAddTorrentToQueueTop());
    stage(QStringLiteral("addStopped"), session->isAddTorrentStopped());
    stage(QStringLiteral("stopCondition"), static_cast<int>(session->torrentStopCondition()));

    stage(QStringLiteral("mergeTrackers"), session->isMergeTrackersEnabled());
    stage(QStringLiteral("confirmMergeTrackers"), pref->confirmMergeTrackers());

    const TorrentFileGuard::AutoDeleteMode mode = TorrentFileGuard::autoDeleteMode();
    stage(QStringLiteral("deleteTorrentFiles"), (mode != TorrentFileGuard::Never));
    stage(QStringLiteral("deleteTorrentFilesWhenCancelled"), (mode == TorrentFileGuard::Always));

    stage(QStringLiteral("preallocateAll"), session->isPreallocationEnabled());
    stage(QStringLiteral("appendExtension"), session->isAppendExtensionEnabled());
    stage(QStringLiteral("unwantedFolder"), session->isUnwantedFolderEnabled());
    stage(QStringLiteral("recursiveDownload"), pref->isRecursiveDownloadEnabled());

    // TMM combos: index 0 == Manual, 1 == Automatic.
    stage(QStringLiteral("savingModeAutomatic"), !session->isAutoTMMDisabledByDefault());
    stage(QStringLiteral("tmmRelocateOnCategoryChanged"), !session->isDisableAutoTMMWhenCategoryChanged());
    stage(QStringLiteral("tmmRelocateOnDefaultPathChanged"), !session->isDisableAutoTMMWhenDefaultSavePathChanged());
    stage(QStringLiteral("tmmRelocateOnCategorySavePathChanged"), !session->isDisableAutoTMMWhenCategorySavePathChanged());
    stage(QStringLiteral("useCategoryPaths"), session->useCategoryPathsInManualMode());

    stage(QStringLiteral("savePath"), session->savePath().toString());
    stage(QStringLiteral("useDownloadPath"), session->isDownloadPathEnabled());
    stage(QStringLiteral("downloadPath"), session->downloadPath().toString());
    const QString exportDir = session->torrentExportDirectory().toString();
    const QString exportDirFinished = session->finishedTorrentExportDirectory().toString();
    stage(QStringLiteral("exportDirEnabled"), !exportDir.isEmpty());
    stage(QStringLiteral("exportDir"), exportDir);
    stage(QStringLiteral("exportDirFinishedEnabled"), !exportDirFinished.isEmpty());
    stage(QStringLiteral("exportDirFinished"), exportDirFinished);

    stage(QStringLiteral("excludedFileNamesEnabled"), session->isExcludedFileNamesEnabled());
    stage(QStringLiteral("excludedFileNames"), session->excludedFileNames().join(QLatin1Char('\n')));

    stage(QStringLiteral("mailEnabled"), pref->isMailNotificationEnabled());
    stage(QStringLiteral("mailSender"), pref->getMailNotificationSender());
    stage(QStringLiteral("mailDest"), pref->getMailNotificationEmail());
    stage(QStringLiteral("mailSMTP"), pref->getMailNotificationSMTP());
    stage(QStringLiteral("mailSMTPEncryption"), static_cast<int>(pref->getMailNotificationSMTPEncryptionType()));
    stage(QStringLiteral("mailAuth"), pref->getMailNotificationSMTPAuth());
    stage(QStringLiteral("mailUsername"), pref->getMailNotificationSMTPUsername());
    stage(QStringLiteral("mailPassword"), pref->getMailNotificationSMTPPassword());

    stage(QStringLiteral("autoRunOnAdded"), pref->isAutoRunOnTorrentAddedEnabled());
    stage(QStringLiteral("autoRunOnAddedProgram"), pref->getAutoRunOnTorrentAddedProgram());
    stage(QStringLiteral("autoRunOnFinished"), pref->isAutoRunOnTorrentFinishedEnabled());
    stage(QStringLiteral("autoRunOnFinishedProgram"), pref->getAutoRunOnTorrentFinishedProgram());
#ifdef Q_OS_WIN
    stage(QStringLiteral("autoRunConsole"), pref->isAutoRunConsoleEnabled());
#endif
}

void OptionsController::loadConnection()
{
    auto *session = Session::instance();
    auto *proxyMgr = Net::ProxyConfigurationManager::instance();
    auto *pref = Preferences::instance();

    stage(QStringLiteral("btProtocol"), static_cast<int>(session->btProtocol()));
    stage(QStringLiteral("port"), session->port());
    // The UPnP/NAT-PMP port forwarder is an abstract, session-provided component
    // that may be absent in builds without a concrete implementation; default to
    // disabled when it is not available.
    auto *portForwarder = Net::PortForwarder::instance();
    stage(QStringLiteral("upnp"), portForwarder ? portForwarder->isEnabled() : false);

    // Keep a usable spin value even when the engine stores -1 (unlimited).
    const auto stageLimit = [this](const QString &valueKey, const QString &enabledKey
            , const int liveValue, const int defaultValue)
    {
        stage(enabledKey, liveValue > 0);
        stage(valueKey, (liveValue > 0) ? liveValue : defaultValue);
    };
    stageLimit(QStringLiteral("maxConnections"), QStringLiteral("maxConnectionsEnabled"),
        session->maxConnections(), 500);
    stageLimit(QStringLiteral("maxConnectionsPerTorrent"), QStringLiteral("maxConnectionsPerTorrentEnabled"),
        session->maxConnectionsPerTorrent(), 100);
    stageLimit(QStringLiteral("maxUploads"), QStringLiteral("maxUploadsEnabled"),
        session->maxUploads(), 20);
    stageLimit(QStringLiteral("maxUploadsPerTorrent"), QStringLiteral("maxUploadsPerTorrentEnabled"),
        session->maxUploadsPerTorrent(), 4);

    stage(QStringLiteral("networkInterface"), session->networkInterface());
    stage(QStringLiteral("networkInterfaceAddress"), session->networkInterfaceAddress());

    const Net::ProxyConfiguration proxy = proxyMgr->proxyConfiguration();
    stage(QStringLiteral("proxyType"), static_cast<int>(proxy.type));
    stage(QStringLiteral("proxyIP"), proxy.ip);
    stage(QStringLiteral("proxyPort"), proxy.port);
    stage(QStringLiteral("proxyAuth"), proxy.authEnabled);
    stage(QStringLiteral("proxyUsername"), proxy.username);
    stage(QStringLiteral("proxyPassword"), proxy.password);
    stage(QStringLiteral("proxyHostnameLookup"), proxy.hostnameLookupEnabled);
    stage(QStringLiteral("proxyPeerConnections"), session->isProxyPeerConnectionsEnabled());
    stage(QStringLiteral("useProxyForBT"), pref->useProxyForBT());
    stage(QStringLiteral("useProxyForRSS"), pref->useProxyForRSS());
    stage(QStringLiteral("useProxyForGeneral"), pref->useProxyForGeneralPurposes());

    stage(QStringLiteral("ipFilterEnabled"), session->isIPFilteringEnabled());
    stage(QStringLiteral("ipFilterFile"), session->IPFilterFile().toString());
    stage(QStringLiteral("ipFilterTrackers"), session->isTrackerFilteringEnabled());
    stage(QStringLiteral("bannedIPs"), session->bannedIPs());

    stage(QStringLiteral("addTrackersEnabled"), session->isAddTrackersEnabled());
    stage(QStringLiteral("additionalTrackers"), session->additionalTrackers());
    stage(QStringLiteral("addTrackersFromURLEnabled"), session->isAddTrackersFromURLEnabled());
    stage(QStringLiteral("additionalTrackersURL"), session->additionalTrackersURL());
    stage(QStringLiteral("additionalTrackersFromURL"), session->additionalTrackersFromURL());
}

void OptionsController::loadSpeed()
{
    auto *session = Session::instance();
    auto *pref = Preferences::instance();

    stage(QStringLiteral("globalDownloadLimit"), session->globalDownloadSpeedLimit() / 1024);
    stage(QStringLiteral("globalUploadLimit"), session->globalUploadSpeedLimit() / 1024);
    stage(QStringLiteral("altDownloadLimit"), session->altGlobalDownloadSpeedLimit() / 1024);
    stage(QStringLiteral("altUploadLimit"), session->altGlobalUploadSpeedLimit() / 1024);
    stage(QStringLiteral("altSpeedEnabled"), session->isAltGlobalSpeedLimitEnabled());

    stage(QStringLiteral("schedulerEnabled"), session->isBandwidthSchedulerEnabled());
    stage(QStringLiteral("schedulerStart"), timeToString(pref->getSchedulerStartTime()));
    stage(QStringLiteral("schedulerEnd"), timeToString(pref->getSchedulerEndTime()));
    stage(QStringLiteral("schedulerDays"), static_cast<int>(pref->getSchedulerDays()));

    stage(QStringLiteral("limitUTPRate"), session->isUTPRateLimited());
    stage(QStringLiteral("limitTCPOverhead"), session->includeOverheadInLimits());
    // UI checkbox is "apply to LAN" == NOT ignoreLimitsOnLAN.
    stage(QStringLiteral("applyLimitsToLAN"), !session->ignoreLimitsOnLAN());
}

void OptionsController::loadBitTorrent()
{
    auto *session = Session::instance();

    stage(QStringLiteral("dht"), session->isDHTEnabled());
    stage(QStringLiteral("pex"), session->isPeXEnabled());
    stage(QStringLiteral("lsd"), session->isLSDEnabled());
    stage(QStringLiteral("encryption"), session->encryption());
    stage(QStringLiteral("anonymousMode"), session->isAnonymousModeEnabled());

    stage(QStringLiteral("queueingEnabled"), session->isQueueingSystemEnabled());
    stage(QStringLiteral("maxActiveDownloads"), session->maxActiveDownloads());
    stage(QStringLiteral("maxActiveUploads"), session->maxActiveUploads());
    stage(QStringLiteral("maxActiveTorrents"), session->maxActiveTorrents());
    stage(QStringLiteral("ignoreSlowTorrents"), session->ignoreSlowTorrentsForQueueing());
    stage(QStringLiteral("slowDownloadRate"), session->downloadRateForSlowTorrents());
    stage(QStringLiteral("slowUploadRate"), session->uploadRateForSlowTorrents());
    stage(QStringLiteral("slowInactivityTimer"), session->slowTorrentsInactivityTimer());

    const BitTorrent::ShareLimits limits = session->shareLimits();
    stage(QStringLiteral("shareRatioLimitEnabled"), limits.ratioLimit >= 0);
    stage(QStringLiteral("shareRatioLimit"), (limits.ratioLimit >= 0) ? limits.ratioLimit : 1.0);
    stage(QStringLiteral("shareSeedingTimeLimitEnabled"), limits.seedingTimeLimit >= 0);
    stage(QStringLiteral("shareSeedingTimeLimit"),
        (limits.seedingTimeLimit >= 0) ? limits.seedingTimeLimit : 1440);
    stage(QStringLiteral("shareInactiveSeedingTimeLimitEnabled"), limits.inactiveSeedingTimeLimit >= 0);
    stage(QStringLiteral("shareInactiveSeedingTimeLimit"),
        (limits.inactiveSeedingTimeLimit >= 0) ? limits.inactiveSeedingTimeLimit : 1440);
    stage(QStringLiteral("shareLimitsMode"), static_cast<int>(limits.mode));
    stage(QStringLiteral("shareLimitAction"), static_cast<int>(limits.action));

    stage(QStringLiteral("maxActiveCheckingTorrents"), session->maxActiveCheckingTorrents());
    stage(QStringLiteral("i2pEnabled"), session->isI2PEnabled());
    stage(QStringLiteral("i2pAddress"), session->I2PAddress());
    stage(QStringLiteral("i2pPort"), session->I2PPort());
    stage(QStringLiteral("i2pMixedMode"), session->I2PMixedMode());
}

void OptionsController::loadSearch()
{
    auto *pref = Preferences::instance();

    stage(QStringLiteral("searchEnabled"), pref->isSearchEnabled());
    stage(QStringLiteral("searchHistoryLength"), pref->searchHistoryLength());
    stage(QStringLiteral("storeOpenedSearchTabs"), pref->storeOpenedSearchTabs());
    stage(QStringLiteral("storeOpenedSearchTabResults"), pref->storeOpenedSearchTabResults());
    stage(QStringLiteral("pythonExecutablePath"), pref->getPythonExecutablePath().toString());
}

void OptionsController::loadRSS()
{
    auto *rss = RSS::Session::instance();
    auto *autoDl = RSS::AutoDownloader::instance();
    auto *pref = Preferences::instance();

    stage(QStringLiteral("rssProcessingEnabled"), rss->isProcessingEnabled());
    stage(QStringLiteral("rssRefreshInterval"), rss->refreshInterval());
    stage(QStringLiteral("rssFetchDelay"), static_cast<int>(rss->fetchDelay().count()));
    stage(QStringLiteral("rssMaxArticlesPerFeed"), rss->maxArticlesPerFeed());
    // The RSS auto-downloader is an optional component (it needs an IApplication
    // host and may be uninitialised); fall back to disabled defaults when absent,
    // matching the null-guard used in RSSController.
    stage(QStringLiteral("rssAutoDownloadEnabled"), autoDl ? autoDl->isProcessingEnabled() : false);
    stage(QStringLiteral("rssDownloadRepacks"), autoDl ? autoDl->downloadRepacks() : false);
    stage(QStringLiteral("rssSmartEpisodeFilters"),
        autoDl ? autoDl->smartEpisodeFilters().join(QLatin1Char('\n')) : QString());
    stage(QStringLiteral("rssWidgetEnabled"), pref->isRSSWidgetEnabled());
}

void OptionsController::loadWebUI()
{
    auto *pref = Preferences::instance();

    stage(QStringLiteral("webUIEnabled"), pref->isWebUIEnabled());
    stage(QStringLiteral("webUIAddress"), pref->getWebUIAddress());
    stage(QStringLiteral("webUIPort"), pref->getWebUIPort());
    stage(QStringLiteral("webUIUPnP"), pref->useUPnPForWebUIPort());
    stage(QStringLiteral("webUIServerDomains"), pref->getServerDomains());

    stage(QStringLiteral("webUIUsername"), pref->getWebUIUsername());
    stage(QStringLiteral("webUIPassword"), QString());
    stage(QStringLiteral("webUIApiKey"), pref->getWebUIApiKey());
    stage(QStringLiteral("webUILocalAuth"), pref->isWebUILocalAuthEnabled());
    stage(QStringLiteral("webUIAuthSubnetWhitelistEnabled"), pref->isWebUIAuthSubnetWhitelistEnabled());
    QStringList whitelist;
    for (const Utils::Net::Subnet &subnet : pref->getWebUIAuthSubnetWhitelist())
        whitelist.append(Utils::Net::subnetToString(subnet));
    stage(QStringLiteral("webUIAuthSubnetWhitelist"), whitelist);
    stage(QStringLiteral("webUIMaxAuthFailCount"), pref->getWebUIMaxAuthFailCount());
    stage(QStringLiteral("webUIBanDuration"), static_cast<int>(pref->getWebUIBanDuration().count()));
    stage(QStringLiteral("webUISessionTimeout"), pref->getWebUISessionTimeout());

    stage(QStringLiteral("webUIClickjacking"), pref->isWebUIClickjackingProtectionEnabled());
    stage(QStringLiteral("webUICSRF"), pref->isWebUICSRFProtectionEnabled());
    stage(QStringLiteral("webUISecureCookie"), pref->isWebUISecureCookieEnabled());
    stage(QStringLiteral("webUIHostHeaderValidation"), pref->isWebUIHostHeaderValidationEnabled());

    stage(QStringLiteral("webUIHttps"), pref->isWebUIHttpsEnabled());
    stage(QStringLiteral("webUIHttpsCert"), pref->getWebUIHttpsCertificatePath().toString());
    stage(QStringLiteral("webUIHttpsKey"), pref->getWebUIHttpsKeyPath().toString());

    stage(QStringLiteral("webUIAltEnabled"), pref->isAltWebUIEnabled());
    stage(QStringLiteral("webUIRootFolder"), pref->getWebUIRootFolder().toString());

    stage(QStringLiteral("webUICustomHeadersEnabled"), pref->isWebUICustomHTTPHeadersEnabled());
    stage(QStringLiteral("webUICustomHeaders"), pref->getWebUICustomHTTPHeaders());
    stage(QStringLiteral("webUIReverseProxyEnabled"), pref->isWebUIReverseProxySupportEnabled());
    stage(QStringLiteral("webUIReverseProxyList"), pref->getWebUITrustedReverseProxiesList());

    stage(QStringLiteral("dynDNSEnabled"), pref->isDynDNSEnabled());
    stage(QStringLiteral("dynDNSService"), static_cast<int>(pref->getDynDNSService()));
    stage(QStringLiteral("dynDNSDomain"), pref->getDynDomainName());
    stage(QStringLiteral("dynDNSUsername"), pref->getDynDNSUsername());
    stage(QStringLiteral("dynDNSPassword"), pref->getDynDNSPassword());
}

// ---------------------------------------------------------------------------
// apply() — staging map -> engine
// ---------------------------------------------------------------------------

bool OptionsController::validate()
{
    // Speed: bandwidth scheduler needs distinct start/end times.
    if (staged(QStringLiteral("schedulerEnabled")).toBool())
    {
        if (staged(QStringLiteral("schedulerStart")).toString() == staged(QStringLiteral("schedulerEnd")).toString())
        {
            const QString msg = tr("The start time and the end time can't be the same.");
            qCWarning(lcUi) << "OptionsController: validation failed (Speed):" << msg;
            emit validationFailed(SpeedTab, msg);
            return false;
        }
    }

    // WebUI: a username is required when the server is enabled.
    if (staged(QStringLiteral("webUIEnabled")).toBool())
    {
        if (staged(QStringLiteral("webUIUsername")).toString().trimmed().length() < 3)
        {
            const QString msg = tr("The Web UI username must be at least 3 characters long.");
            qCWarning(lcUi) << "OptionsController: validation failed (WebUI):" << msg;
            emit validationFailed(WebUITab, msg);
            return false;
        }
    }

    return true;
}

bool OptionsController::apply()
{
    qCInfo(lcUi) << "OptionsController: apply() requested";
    if (!validate())
        return false;

    const bool wasModified = isModified();

    applyBehavior();
    applyDownloads();
    applyConnection();
    applySpeed();
    applyBitTorrent();
    applySearch();
    applyRSS();
    applyWebUI();
    if (m_advancedSettingsModel)
        m_advancedSettingsModel->apply();
    if (m_watchedFoldersModel)
        m_watchedFoldersModel->apply();
    applyPassthroughValues();

    // Flush persisted preferences to disk once.
    Preferences::instance()->apply();

    m_modified = false;
    m_passthroughKeys.clear();
    if (wasModified)
        emit modifiedChanged();
    bumpRevision();
    emit applied();
    qCInfo(lcUi) << "OptionsController: settings applied";
    return true;
}

void OptionsController::applyPassthroughValues()
{
    auto *pref = Preferences::instance();
    for (const QString &key : std::as_const(m_passthroughKeys))
        pref->setValue(key, m_values.value(key));
}

void OptionsController::applyBehavior()
{
    auto *pref = Preferences::instance();
    auto *session = Session::instance();
    auto *theme = ThemeManager::instance();

    const int newLanguage = std::clamp(staged(QStringLiteral("language"), 0).toInt(), 0, 2);
    const int newEnglishFunnyLevel = std::clamp(
        staged(QStringLiteral("englishFunnyLevel"), DEFAULT_ENGLISH_FUNNY_LEVEL).toInt(), 1, 5);
    const int newCantoneseFunnyLevel = std::clamp(
        staged(QStringLiteral("cantoneseFunnyLevel"), DEFAULT_CANTONESE_FUNNY_LEVEL).toInt(), 1, 5);
    const bool languageChanged = (newLanguage != pref->getLanguageMode());
    const bool englishFunnyLevelChanged = (newEnglishFunnyLevel != pref->value(
        ENGLISH_FUNNY_LEVEL_KEY, DEFAULT_ENGLISH_FUNNY_LEVEL).toInt());
    const bool cantoneseFunnyLevelChanged = (newCantoneseFunnyLevel != pref->value(
        CANTONESE_FUNNY_LEVEL_KEY, DEFAULT_CANTONESE_FUNNY_LEVEL).toInt());

    if (languageChanged || englishFunnyLevelChanged || cantoneseFunnyLevelChanged)
    {
        qCInfo(lcUi) << "OptionsController: language settings ->"
                     << newLanguage << newEnglishFunnyLevel << newCantoneseFunnyLevel;
        pref->setLanguageMode(newLanguage);
        pref->setValue(ENGLISH_FUNNY_LEVEL_KEY, newEnglishFunnyLevel);
        pref->setValue(CANTONESE_FUNNY_LEVEL_KEY, newCantoneseFunnyLevel);

        // The live retranslate is performed atomically by the QML I18n bridge.
        emit languageSettingsChangeRequested(newLanguage, newEnglishFunnyLevel,
                                             newCantoneseFunnyLevel);
        // Preserve the existing signal for compatibility with external views.
        if (languageChanged)
            emit languageChangeRequested(newLanguage);
    }

    pref->setStyle(staged(QStringLiteral("style")).toString());
    theme->setColorScheme(static_cast<ThemeManager::ColorScheme>(staged(QStringLiteral("colorScheme")).toInt()));
    pref->setUseCustomUITheme(staged(QStringLiteral("useCustomTheme")).toBool());
    pref->setCustomUIThemePath(Path(staged(QStringLiteral("customThemePath")).toString()));

    pref->setConfirmTorrentDeletion(staged(QStringLiteral("confirmDeletion")).toBool());
    pref->setAlternatingRowColors(staged(QStringLiteral("alternatingRowColors")).toBool());
    pref->setUseTorrentStatesColors(staged(QStringLiteral("useTorrentStatesColors")).toBool());
    pref->setProgressBarFollowsTextColor(staged(QStringLiteral("progressBarFollowsTextColor")).toBool());
    pref->setHideZeroValues(staged(QStringLiteral("hideZeroValues")).toBool());
    pref->setHideZeroComboValues(staged(QStringLiteral("hideZeroComboValues")).toInt());
    pref->setActionOnDblClOnTorrentDl(staged(QStringLiteral("actionDblClickDl")).toInt());
    pref->setActionOnDblClOnTorrentFn(staged(QStringLiteral("actionDblClickFn")).toInt());
    pref->setHideZeroStatusFilters(staged(QStringLiteral("hideZeroStatusFilters")).toBool());
    pref->setUseSeparateTrackerStatusFilter(staged(QStringLiteral("useSeparateTrackerStatusFilter")).toBool());
    pref->setTorrentContentDragEnabled(staged(QStringLiteral("torrentContentDrag")).toBool());

    pref->setStatusbarFreeDiskSpaceDisplayed(staged(QStringLiteral("statusbarFreeDiskSpace")).toBool());
    pref->setStatusbarExternalIPDisplayed(staged(QStringLiteral("statusbarExternalIP")).toBool());

    pref->setSplashScreenDisabled(!staged(QStringLiteral("showSplashScreen")).toBool());
    pref->setConfirmOnExit(staged(QStringLiteral("confirmOnExit")).toBool());
    pref->setDontConfirmAutoExit(!staged(QStringLiteral("confirmAutoExit")).toBool());

#ifndef Q_OS_MACOS
    pref->setSystemTrayEnabled(staged(QStringLiteral("systrayEnabled")).toBool());
    pref->setMinimizeToTray(staged(QStringLiteral("minimizeToTray")).toBool());
    pref->setCloseToTray(staged(QStringLiteral("closeToTray")).toBool());
#endif
    theme->setTrayIconStyle(static_cast<ThemeManager::TrayIconStyle>(staged(QStringLiteral("trayIconStyle")).toInt()));

    pref->setPreventFromSuspendWhenDownloading(staged(QStringLiteral("preventSuspendDownloading")).toBool());
    pref->setPreventFromSuspendWhenSeeding(staged(QStringLiteral("preventSuspendSeeding")).toBool());

    session->setPerformanceWarningEnabled(staged(QStringLiteral("performanceWarning")).toBool());

#ifdef Q_OS_WIN
    pref->setWinStartup(staged(QStringLiteral("winStartup")).toBool());
#endif
}

void OptionsController::applyDownloads()
{
    auto *pref = Preferences::instance();
    auto *session = Session::instance();

    pref->setAddNewTorrentDialogEnabled(staged(QStringLiteral("additionDialog")).toBool());
    pref->setAddNewTorrentDialogTopLevel(staged(QStringLiteral("additionDialogFront")).toBool());
    session->setTorrentContentLayout(static_cast<BitTorrent::TorrentContentLayout>(staged(QStringLiteral("contentLayout")).toInt()));
    session->setAddTorrentToQueueTop(staged(QStringLiteral("addToQueueTop")).toBool());
    session->setAddTorrentStopped(staged(QStringLiteral("addStopped")).toBool());
    session->setTorrentStopCondition(static_cast<BitTorrent::Torrent::StopCondition>(staged(QStringLiteral("stopCondition")).toInt()));

    session->setMergeTrackersEnabled(staged(QStringLiteral("mergeTrackers")).toBool());
    pref->setConfirmMergeTrackers(staged(QStringLiteral("confirmMergeTrackers")).toBool());

    // .torrent auto-delete tri-state: Never / IfAdded / Always.
    const bool deleteFiles = staged(QStringLiteral("deleteTorrentFiles")).toBool();
    const bool deleteWhenCancelled = staged(QStringLiteral("deleteTorrentFilesWhenCancelled")).toBool();
    const TorrentFileGuard::AutoDeleteMode mode = !deleteFiles
        ? TorrentFileGuard::Never
        : (deleteWhenCancelled ? TorrentFileGuard::Always : TorrentFileGuard::IfAdded);
    TorrentFileGuard::setAutoDeleteMode(mode);

    session->setPreallocationEnabled(staged(QStringLiteral("preallocateAll")).toBool());
    session->setAppendExtensionEnabled(staged(QStringLiteral("appendExtension")).toBool());
    session->setUnwantedFolderEnabled(staged(QStringLiteral("unwantedFolder")).toBool());
    pref->setRecursiveDownloadEnabled(staged(QStringLiteral("recursiveDownload")).toBool());

    session->setAutoTMMDisabledByDefault(!staged(QStringLiteral("savingModeAutomatic")).toBool());
    session->setDisableAutoTMMWhenCategoryChanged(!staged(QStringLiteral("tmmRelocateOnCategoryChanged")).toBool());
    session->setDisableAutoTMMWhenDefaultSavePathChanged(!staged(QStringLiteral("tmmRelocateOnDefaultPathChanged")).toBool());
    session->setDisableAutoTMMWhenCategorySavePathChanged(!staged(QStringLiteral("tmmRelocateOnCategorySavePathChanged")).toBool());
    session->setUseCategoryPathsInManualMode(staged(QStringLiteral("useCategoryPaths")).toBool());

    session->setSavePath(Path(staged(QStringLiteral("savePath")).toString()));
    session->setDownloadPathEnabled(staged(QStringLiteral("useDownloadPath")).toBool());
    session->setDownloadPath(Path(staged(QStringLiteral("downloadPath")).toString()));
    session->setTorrentExportDirectory(Path(staged(QStringLiteral("exportDirEnabled")).toBool()
        ? staged(QStringLiteral("exportDir")).toString() : QString()));
    session->setFinishedTorrentExportDirectory(Path(staged(QStringLiteral("exportDirFinishedEnabled")).toBool()
        ? staged(QStringLiteral("exportDirFinished")).toString() : QString()));

    session->setExcludedFileNamesEnabled(staged(QStringLiteral("excludedFileNamesEnabled")).toBool());
    session->setExcludedFileNames(staged(QStringLiteral("excludedFileNames")).toString()
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts));

    pref->setMailNotificationEnabled(staged(QStringLiteral("mailEnabled")).toBool());
    pref->setMailNotificationSender(staged(QStringLiteral("mailSender")).toString());
    pref->setMailNotificationEmail(staged(QStringLiteral("mailDest")).toString());
    pref->setMailNotificationSMTP(staged(QStringLiteral("mailSMTP")).toString());
    pref->setMailNotificationSMTPEncryptionType(static_cast<Net::SMTPEncryptionType>(staged(QStringLiteral("mailSMTPEncryption")).toInt()));
    pref->setMailNotificationSMTPAuth(staged(QStringLiteral("mailAuth")).toBool());
    pref->setMailNotificationSMTPUsername(staged(QStringLiteral("mailUsername")).toString());
    pref->setMailNotificationSMTPPassword(staged(QStringLiteral("mailPassword")).toString());

    pref->setAutoRunOnTorrentAddedEnabled(staged(QStringLiteral("autoRunOnAdded")).toBool());
    pref->setAutoRunOnTorrentAddedProgram(staged(QStringLiteral("autoRunOnAddedProgram")).toString().trimmed());
    pref->setAutoRunOnTorrentFinishedEnabled(staged(QStringLiteral("autoRunOnFinished")).toBool());
    pref->setAutoRunOnTorrentFinishedProgram(staged(QStringLiteral("autoRunOnFinishedProgram")).toString().trimmed());
#ifdef Q_OS_WIN
    pref->setAutoRunConsoleEnabled(staged(QStringLiteral("autoRunConsole")).toBool());
#endif
}

void OptionsController::applyConnection()
{
    auto *session = Session::instance();
    auto *proxyMgr = Net::ProxyConfigurationManager::instance();
    auto *pref = Preferences::instance();

    session->setBTProtocol(static_cast<BitTorrent::BTProtocol>(staged(QStringLiteral("btProtocol")).toInt()));
    session->setPort(staged(QStringLiteral("port")).toInt());
    if (auto *portForwarder = Net::PortForwarder::instance())
        portForwarder->setEnabled(staged(QStringLiteral("upnp")).toBool());

    session->setMaxConnections(staged(QStringLiteral("maxConnectionsEnabled")).toBool()
        ? staged(QStringLiteral("maxConnections")).toInt() : -1);
    session->setMaxConnectionsPerTorrent(staged(QStringLiteral("maxConnectionsPerTorrentEnabled")).toBool()
        ? staged(QStringLiteral("maxConnectionsPerTorrent")).toInt() : -1);
    session->setMaxUploads(staged(QStringLiteral("maxUploadsEnabled")).toBool()
        ? staged(QStringLiteral("maxUploads")).toInt() : -1);
    session->setMaxUploadsPerTorrent(staged(QStringLiteral("maxUploadsPerTorrentEnabled")).toBool()
        ? staged(QStringLiteral("maxUploadsPerTorrent")).toInt() : -1);

    const QString interfaceName = staged(QStringLiteral("networkInterface")).toString();
    session->setNetworkInterface(interfaceName);
    QString humanReadableInterfaceName;
    for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces())
    {
        if (iface.name() == interfaceName)
        {
            humanReadableInterfaceName = iface.humanReadableName();
            break;
        }
    }
    session->setNetworkInterfaceName(humanReadableInterfaceName);
    session->setNetworkInterfaceAddress(staged(QStringLiteral("networkInterfaceAddress")).toString());

    Net::ProxyConfiguration proxy;
    proxy.type = static_cast<Net::ProxyType>(staged(QStringLiteral("proxyType")).toInt());
    proxy.ip = staged(QStringLiteral("proxyIP")).toString();
    proxy.port = static_cast<ushort>(staged(QStringLiteral("proxyPort")).toUInt());
    proxy.authEnabled = staged(QStringLiteral("proxyAuth")).toBool();
    proxy.username = staged(QStringLiteral("proxyUsername")).toString();
    proxy.password = staged(QStringLiteral("proxyPassword")).toString();
    proxy.hostnameLookupEnabled = staged(QStringLiteral("proxyHostnameLookup")).toBool();
    proxyMgr->setProxyConfiguration(proxy);

    session->setProxyPeerConnectionsEnabled(staged(QStringLiteral("proxyPeerConnections")).toBool());
    pref->setUseProxyForBT(staged(QStringLiteral("useProxyForBT")).toBool());
    pref->setUseProxyForRSS(staged(QStringLiteral("useProxyForRSS")).toBool());
    pref->setUseProxyForGeneralPurposes(staged(QStringLiteral("useProxyForGeneral")).toBool());

    session->setIPFilteringEnabled(staged(QStringLiteral("ipFilterEnabled")).toBool());
    session->setIPFilterFile(Path(staged(QStringLiteral("ipFilterFile")).toString()));
    session->setTrackerFilteringEnabled(staged(QStringLiteral("ipFilterTrackers")).toBool());
    session->setBannedIPs(staged(QStringLiteral("bannedIPs")).toStringList());

    session->setAddTrackersEnabled(staged(QStringLiteral("addTrackersEnabled")).toBool());
    session->setAdditionalTrackers(staged(QStringLiteral("additionalTrackers")).toString());
    session->setAddTrackersFromURLEnabled(staged(QStringLiteral("addTrackersFromURLEnabled")).toBool());
    session->setAdditionalTrackersURL(staged(QStringLiteral("additionalTrackersURL")).toString());
}

void OptionsController::applySpeed()
{
    auto *session = Session::instance();
    auto *pref = Preferences::instance();

    session->setGlobalDownloadSpeedLimit(staged(QStringLiteral("globalDownloadLimit")).toInt() * 1024);
    session->setGlobalUploadSpeedLimit(staged(QStringLiteral("globalUploadLimit")).toInt() * 1024);
    session->setAltGlobalDownloadSpeedLimit(staged(QStringLiteral("altDownloadLimit")).toInt() * 1024);
    session->setAltGlobalUploadSpeedLimit(staged(QStringLiteral("altUploadLimit")).toInt() * 1024);
    session->setAltGlobalSpeedLimitEnabled(staged(QStringLiteral("altSpeedEnabled")).toBool());

    session->setBandwidthSchedulerEnabled(staged(QStringLiteral("schedulerEnabled")).toBool());
    pref->setSchedulerStartTime(stringToTime(staged(QStringLiteral("schedulerStart")).toString()));
    pref->setSchedulerEndTime(stringToTime(staged(QStringLiteral("schedulerEnd")).toString()));
    pref->setSchedulerDays(static_cast<Scheduler::Days>(staged(QStringLiteral("schedulerDays")).toInt()));

    session->setUTPRateLimited(staged(QStringLiteral("limitUTPRate")).toBool());
    session->setIncludeOverheadInLimits(staged(QStringLiteral("limitTCPOverhead")).toBool());
    session->setIgnoreLimitsOnLAN(!staged(QStringLiteral("applyLimitsToLAN")).toBool());
}

void OptionsController::applyBitTorrent()
{
    auto *session = Session::instance();

    session->setDHTEnabled(staged(QStringLiteral("dht")).toBool());
    session->setPeXEnabled(staged(QStringLiteral("pex")).toBool());
    session->setLSDEnabled(staged(QStringLiteral("lsd")).toBool());
    session->setEncryption(staged(QStringLiteral("encryption")).toInt());
    session->setAnonymousModeEnabled(staged(QStringLiteral("anonymousMode")).toBool());

    session->setQueueingSystemEnabled(staged(QStringLiteral("queueingEnabled")).toBool());
    session->setMaxActiveDownloads(staged(QStringLiteral("maxActiveDownloads")).toInt());
    session->setMaxActiveUploads(staged(QStringLiteral("maxActiveUploads")).toInt());
    session->setMaxActiveTorrents(staged(QStringLiteral("maxActiveTorrents")).toInt());
    session->setIgnoreSlowTorrentsForQueueing(staged(QStringLiteral("ignoreSlowTorrents")).toBool());
    session->setDownloadRateForSlowTorrents(staged(QStringLiteral("slowDownloadRate")).toInt());
    session->setUploadRateForSlowTorrents(staged(QStringLiteral("slowUploadRate")).toInt());
    session->setSlowTorrentsInactivityTimer(staged(QStringLiteral("slowInactivityTimer")).toInt());

    BitTorrent::ShareLimits limits = session->shareLimits();
    limits.ratioLimit = staged(QStringLiteral("shareRatioLimitEnabled")).toBool()
        ? staged(QStringLiteral("shareRatioLimit")).toReal()
        : BitTorrent::NO_RATIO_LIMIT;
    limits.seedingTimeLimit = staged(QStringLiteral("shareSeedingTimeLimitEnabled")).toBool()
        ? staged(QStringLiteral("shareSeedingTimeLimit")).toInt()
        : BitTorrent::NO_SEEDING_TIME_LIMIT;
    limits.inactiveSeedingTimeLimit = staged(QStringLiteral("shareInactiveSeedingTimeLimitEnabled")).toBool()
        ? staged(QStringLiteral("shareInactiveSeedingTimeLimit")).toInt()
        : BitTorrent::NO_SEEDING_TIME_LIMIT;
    limits.mode = static_cast<BitTorrent::ShareLimitsMode>(staged(QStringLiteral("shareLimitsMode")).toInt());
    limits.action = static_cast<BitTorrent::ShareLimitAction>(staged(QStringLiteral("shareLimitAction")).toInt());
    session->setShareLimits(limits);

    session->setMaxActiveCheckingTorrents(staged(QStringLiteral("maxActiveCheckingTorrents")).toInt());
    session->setI2PEnabled(staged(QStringLiteral("i2pEnabled")).toBool());
    session->setI2PAddress(staged(QStringLiteral("i2pAddress")).toString());
    session->setI2PPort(staged(QStringLiteral("i2pPort")).toInt());
    session->setI2PMixedMode(staged(QStringLiteral("i2pMixedMode")).toBool());
}

void OptionsController::applySearch()
{
    auto *pref = Preferences::instance();

    pref->setSearchEnabled(staged(QStringLiteral("searchEnabled")).toBool());
    pref->setSearchHistoryLength(staged(QStringLiteral("searchHistoryLength")).toInt());
    pref->setStoreOpenedSearchTabs(staged(QStringLiteral("storeOpenedSearchTabs")).toBool());
    pref->setStoreOpenedSearchTabResults(staged(QStringLiteral("storeOpenedSearchTabResults")).toBool());
    pref->setPythonExecutablePath(Path(staged(QStringLiteral("pythonExecutablePath")).toString()));
}

void OptionsController::applyRSS()
{
    auto *rss = RSS::Session::instance();
    auto *autoDl = RSS::AutoDownloader::instance();
    auto *pref = Preferences::instance();

    rss->setProcessingEnabled(staged(QStringLiteral("rssProcessingEnabled")).toBool());
    rss->setRefreshInterval(staged(QStringLiteral("rssRefreshInterval")).toInt());
    rss->setFetchDelay(std::chrono::seconds(staged(QStringLiteral("rssFetchDelay")).toInt()));
    rss->setMaxArticlesPerFeed(staged(QStringLiteral("rssMaxArticlesPerFeed")).toInt());
    // Only touch the auto-downloader when it is actually present (see loadRSS).
    if (autoDl)
    {
        autoDl->setProcessingEnabled(staged(QStringLiteral("rssAutoDownloadEnabled")).toBool());
        autoDl->setDownloadRepacks(staged(QStringLiteral("rssDownloadRepacks")).toBool());
        autoDl->setSmartEpisodeFilters(staged(QStringLiteral("rssSmartEpisodeFilters")).toString()
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts));
    }
    pref->setRSSWidgetVisible(staged(QStringLiteral("rssWidgetEnabled")).toBool());
}

void OptionsController::applyWebUI()
{
    auto *pref = Preferences::instance();

    pref->setWebUIEnabled(staged(QStringLiteral("webUIEnabled")).toBool());
    pref->setWebUIAddress(staged(QStringLiteral("webUIAddress")).toString());
    pref->setWebUIPort(static_cast<quint16>(staged(QStringLiteral("webUIPort")).toUInt()));
    pref->setUPnPForWebUIPort(staged(QStringLiteral("webUIUPnP")).toBool());
    pref->setServerDomains(staged(QStringLiteral("webUIServerDomains")).toString());

    pref->setWebUIUsername(staged(QStringLiteral("webUIUsername")).toString());
    // The password is only rewritten when the user actually typed a new one.
    const QString newPassword = staged(QStringLiteral("webUIPassword")).toString();
    if (!newPassword.isEmpty())
        pref->setWebUIPassword(newPassword.toUtf8());
    pref->setWebUIApiKey(staged(QStringLiteral("webUIApiKey")).toString());
    pref->setWebUILocalAuthEnabled(staged(QStringLiteral("webUILocalAuth")).toBool());
    pref->setWebUIAuthSubnetWhitelistEnabled(staged(QStringLiteral("webUIAuthSubnetWhitelistEnabled")).toBool());
    pref->setWebUIAuthSubnetWhitelist(staged(QStringLiteral("webUIAuthSubnetWhitelist")).toStringList());
    pref->setWebUIMaxAuthFailCount(staged(QStringLiteral("webUIMaxAuthFailCount")).toInt());
    pref->setWebUIBanDuration(std::chrono::seconds(staged(QStringLiteral("webUIBanDuration")).toInt()));
    pref->setWebUISessionTimeout(staged(QStringLiteral("webUISessionTimeout")).toInt());

    pref->setWebUIClickjackingProtectionEnabled(staged(QStringLiteral("webUIClickjacking")).toBool());
    pref->setWebUICSRFProtectionEnabled(staged(QStringLiteral("webUICSRF")).toBool());
    pref->setWebUISecureCookieEnabled(staged(QStringLiteral("webUISecureCookie")).toBool());
    pref->setWebUIHostHeaderValidationEnabled(staged(QStringLiteral("webUIHostHeaderValidation")).toBool());

    pref->setWebUIHttpsEnabled(staged(QStringLiteral("webUIHttps")).toBool());
    pref->setWebUIHttpsCertificatePath(Path(staged(QStringLiteral("webUIHttpsCert")).toString()));
    pref->setWebUIHttpsKeyPath(Path(staged(QStringLiteral("webUIHttpsKey")).toString()));

    pref->setAltWebUIEnabled(staged(QStringLiteral("webUIAltEnabled")).toBool());
    pref->setWebUIRootFolder(Path(staged(QStringLiteral("webUIRootFolder")).toString()));

    pref->setWebUICustomHTTPHeadersEnabled(staged(QStringLiteral("webUICustomHeadersEnabled")).toBool());
    pref->setWebUICustomHTTPHeaders(staged(QStringLiteral("webUICustomHeaders")).toString());
    pref->setWebUIReverseProxySupportEnabled(staged(QStringLiteral("webUIReverseProxyEnabled")).toBool());
    pref->setWebUITrustedReverseProxiesList(staged(QStringLiteral("webUIReverseProxyList")).toString());

    pref->setDynDNSEnabled(staged(QStringLiteral("dynDNSEnabled")).toBool());
    pref->setDynDNSService(static_cast<DNS::Service>(staged(QStringLiteral("dynDNSService")).toInt()));
    pref->setDynDomainName(staged(QStringLiteral("dynDNSDomain")).toString());
    pref->setDynDNSUsername(staged(QStringLiteral("dynDNSUsername")).toString());
    pref->setDynDNSPassword(staged(QStringLiteral("dynDNSPassword")).toString());
}
