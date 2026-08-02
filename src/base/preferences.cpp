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

#include "preferences.h"

#include <algorithm>
#include <chrono>

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QList>
#include <QLocale>
#include <QNetworkCookie>
#include <QSettings>
#include <QTime>

#include "base/global.h"
#include "base/logging.h"
#include "base/profile.h"
#include "base/settingsstorage.h"
#include "base/utils/fs.h"
#include "base/utils/fs/path.h"

namespace
{
    template <typename T>
    T readSetting(const QString &key, const T &defaultValue = {})
    {
        return SettingsStorage::instance()->loadValue(key, defaultValue);
    }

    template <typename T>
    void writeSetting(const QString &key, const T &value)
    {
        // Every persisted change flows through here, so this single line satisfies
        // the "log every settings change" mandate. Values are intentionally NOT
        // logged (some are secrets, e.g. WebUI/UI-lock password hashes).
        qCDebug(lcApp).nospace() << "Preferences: setting [" << key << "]";
        SettingsStorage::instance()->storeValue(key, value);
    }

#ifdef Q_OS_WIN
    QString makeProfileID(const Path &profilePath, const QString &profileName)
    {
        return profilePath.isEmpty()
                ? profileName
                : profileName + u'@' + Utils::Fs::toValidFileName(profilePath.data(), {});
    }
#endif
}

Preferences *Preferences::m_instance = nullptr;

Preferences::Preferences() = default;

Preferences *Preferences::instance()
{
    return m_instance;
}

QVariant Preferences::value(const QString &key, const QVariant &defaultValue) const
{
    return SettingsStorage::instance()->loadValue<QVariant>(key, defaultValue);
}

void Preferences::setValue(const QString &key, const QVariant &value)
{
    SettingsStorage::instance()->storeValue(key, value);
}

void Preferences::initInstance()
{
    if (!m_instance)
    {
        qCDebug(lcApp) << "Preferences: creating singleton instance";
        m_instance = new Preferences;
    }
}

void Preferences::freeInstance()
{
    qCDebug(lcApp) << "Preferences: freeing singleton instance";
    delete m_instance;
    m_instance = nullptr;
}

// General options
QString Preferences::getLocale() const
{
    const auto localeName = readSetting<QString>(u"Preferences/General/Locale"_s);
    return (localeName.isEmpty() ? QLocale::system().name() : localeName);
}

void Preferences::setLocale(const QString &locale)
{
    if (locale == getLocale())
        return;

    writeSetting(u"Preferences/General/Locale"_s, locale);
}

bool Preferences::useCustomUITheme() const
{
    return readSetting(u"Preferences/General/UseCustomUITheme"_s, false) && !customUIThemePath().isEmpty();
}

void Preferences::setUseCustomUITheme(const bool use)
{
    if (use == useCustomUITheme())
        return;

    writeSetting(u"Preferences/General/UseCustomUITheme"_s, use);
}

Path Preferences::customUIThemePath() const
{
    return readSetting<Path>(u"Preferences/General/CustomUIThemePath"_s);
}

void Preferences::setCustomUIThemePath(const Path &path)
{
    if (path == customUIThemePath())
        return;

    writeSetting(u"Preferences/General/CustomUIThemePath"_s, path);
}

bool Preferences::removeTorrentContent() const
{
    return readSetting(u"Preferences/General/DeleteTorrentsFilesAsDefault"_s, false);
}

void Preferences::setRemoveTorrentContent(const bool remove)
{
    if (remove == removeTorrentContent())
        return;

    writeSetting(u"Preferences/General/DeleteTorrentsFilesAsDefault"_s, remove);
}

bool Preferences::confirmOnExit() const
{
    return readSetting(u"Preferences/General/ExitConfirm"_s, true);
}

void Preferences::setConfirmOnExit(const bool confirm)
{
    if (confirm == confirmOnExit())
        return;

    writeSetting(u"Preferences/General/ExitConfirm"_s, confirm);
}

bool Preferences::speedInTitleBar() const
{
    return readSetting(u"Preferences/General/SpeedInTitleBar"_s, false);
}

void Preferences::showSpeedInTitleBar(const bool show)
{
    if (show == speedInTitleBar())
        return;

    writeSetting(u"Preferences/General/SpeedInTitleBar"_s, show);
}

bool Preferences::useAlternatingRowColors() const
{
    return readSetting(u"Preferences/General/AlternatingRowColors"_s, true);
}

void Preferences::setAlternatingRowColors(const bool b)
{
    if (b == useAlternatingRowColors())
        return;

    writeSetting(u"Preferences/General/AlternatingRowColors"_s, b);
}

bool Preferences::useTorrentStatesColors() const
{
    return readSetting(u"GUI/TransferList/UseTorrentStatesColors"_s, true);
}

void Preferences::setUseTorrentStatesColors(const bool value)
{
    if (value == useTorrentStatesColors())
        return;

    writeSetting(u"GUI/TransferList/UseTorrentStatesColors"_s, value);
}

bool Preferences::getProgressBarFollowsTextColor() const
{
    return readSetting(u"GUI/TransferList/ProgressBarFollowsTextColor"_s, false);
}

void Preferences::setProgressBarFollowsTextColor(const bool value)
{
    if (value == getProgressBarFollowsTextColor())
        return;

    writeSetting(u"GUI/TransferList/ProgressBarFollowsTextColor"_s, value);
}

bool Preferences::getHideZeroValues() const
{
    return readSetting(u"Preferences/General/HideZeroValues"_s, false);
}

void Preferences::setHideZeroValues(const bool b)
{
    if (b == getHideZeroValues())
        return;

    writeSetting(u"Preferences/General/HideZeroValues"_s, b);
}

int Preferences::getHideZeroComboValues() const
{
    return readSetting<int>(u"Preferences/General/HideZeroComboValues"_s, 0);
}

void Preferences::setHideZeroComboValues(const int n)
{
    if (n == getHideZeroComboValues())
        return;

    writeSetting(u"Preferences/General/HideZeroComboValues"_s, n);
}

// In Mac OS X the dock is sufficient for our needs so we disable the sys tray functionality.
// See extensive discussion in https://github.com/qbittorrent/qBittorrent/pull/3018
#ifndef Q_OS_MACOS
bool Preferences::systemTrayEnabled() const
{
    return readSetting(u"Preferences/General/SystrayEnabled"_s, true);
}

void Preferences::setSystemTrayEnabled(const bool enabled)
{
    if (enabled == systemTrayEnabled())
        return;

    writeSetting(u"Preferences/General/SystrayEnabled"_s, enabled);
}

bool Preferences::minimizeToTray() const
{
    return readSetting(u"Preferences/General/MinimizeToTray"_s, false);
}

void Preferences::setMinimizeToTray(const bool b)
{
    if (b == minimizeToTray())
        return;

    writeSetting(u"Preferences/General/MinimizeToTray"_s, b);
}

bool Preferences::minimizeToTrayNotified() const
{
    return readSetting(u"Preferences/General/MinimizeToTrayNotified"_s, false);
}

void Preferences::setMinimizeToTrayNotified(const bool b)
{
    if (b == minimizeToTrayNotified())
        return;

    writeSetting(u"Preferences/General/MinimizeToTrayNotified"_s, b);
}

bool Preferences::closeToTray() const
{
    return readSetting(u"Preferences/General/CloseToTray"_s, true);
}

void Preferences::setCloseToTray(const bool b)
{
    if (b == closeToTray())
        return;

    writeSetting(u"Preferences/General/CloseToTray"_s, b);
}

bool Preferences::closeToTrayNotified() const
{
    return readSetting(u"Preferences/General/CloseToTrayNotified"_s, false);
}

void Preferences::setCloseToTrayNotified(const bool b)
{
    if (b == closeToTrayNotified())
        return;

    writeSetting(u"Preferences/General/CloseToTrayNotified"_s, b);
}

bool Preferences::iconsInMenusEnabled() const
{
    return readSetting(u"Preferences/Advanced/EnableIconsInMenus"_s, true);
}

void Preferences::setIconsInMenusEnabled(const bool enable)
{
    if (enable == iconsInMenusEnabled())
        return;

    writeSetting(u"Preferences/Advanced/EnableIconsInMenus"_s, enable);
}
#endif // Q_OS_MACOS

qint64 Preferences::getTorrentFileSizeLimit() const
{
    return readSetting(u"BitTorrent/TorrentFileSizeLimit"_s, (100 * 1024 * 1024));
}

void Preferences::setTorrentFileSizeLimit(const qint64 value)
{
    if (value == getTorrentFileSizeLimit())
        return;

    writeSetting(u"BitTorrent/TorrentFileSizeLimit"_s, value);
}

int Preferences::getBdecodeDepthLimit() const
{
    return readSetting(u"BitTorrent/BdecodeDepthLimit"_s, 100);
}

void Preferences::setBdecodeDepthLimit(const int value)
{
    if (value == getBdecodeDepthLimit())
        return;

    writeSetting(u"BitTorrent/BdecodeDepthLimit"_s, value);
}

int Preferences::getBdecodeTokenLimit() const
{
    return readSetting(u"BitTorrent/BdecodeTokenLimit"_s, 10'000'000);
}

void Preferences::setBdecodeTokenLimit(const int value)
{
    if (value == getBdecodeTokenLimit())
        return;

    writeSetting(u"BitTorrent/BdecodeTokenLimit"_s, value);
}

bool Preferences::isToolbarDisplayed() const
{
    return readSetting(u"Preferences/General/ToolbarDisplayed"_s, true);
}

void Preferences::setToolbarDisplayed(const bool displayed)
{
    if (displayed == isToolbarDisplayed())
        return;

    writeSetting(u"Preferences/General/ToolbarDisplayed"_s, displayed);
}

bool Preferences::isTorrentContentDragEnabled() const
{
    return readSetting(u"Preferences/General/TorrentContentDragEnabled"_s, false);
}

void Preferences::setTorrentContentDragEnabled(const bool enabled)
{
    if (enabled == isTorrentContentDragEnabled())
        return;

    writeSetting(u"Preferences/General/TorrentContentDragEnabled"_s, enabled);
}

bool Preferences::isStatusbarDisplayed() const
{
    return readSetting(u"Preferences/General/StatusbarDisplayed"_s, true);
}

void Preferences::setStatusbarDisplayed(const bool displayed)
{
    if (displayed == isStatusbarDisplayed())
        return;

    writeSetting(u"Preferences/General/StatusbarDisplayed"_s, displayed);
}

bool Preferences::isStatusbarFreeDiskSpaceDisplayed() const
{
    return readSetting(u"Preferences/General/StatusbarFreeDiskSpaceDisplayed"_s, false);
}

void Preferences::setStatusbarFreeDiskSpaceDisplayed(const bool displayed)
{
    if (displayed == isStatusbarFreeDiskSpaceDisplayed())
        return;

    writeSetting(u"Preferences/General/StatusbarFreeDiskSpaceDisplayed"_s, displayed);
}

bool Preferences::isStatusbarExternalIPDisplayed() const
{
    return readSetting(u"Preferences/General/StatusbarExternalIPDisplayed"_s, false);
}

void Preferences::setStatusbarExternalIPDisplayed(const bool displayed)
{
    if (displayed == isStatusbarExternalIPDisplayed())
        return;

    writeSetting(u"Preferences/General/StatusbarExternalIPDisplayed"_s, displayed);
}

bool Preferences::isSplashScreenDisabled() const
{
    return readSetting(u"Preferences/General/NoSplashScreen"_s, true);
}

void Preferences::setSplashScreenDisabled(const bool b)
{
    if (b == isSplashScreenDisabled())
        return;

    writeSetting(u"Preferences/General/NoSplashScreen"_s, b);
}

// Preventing from system suspend while active torrents are presented.
bool Preferences::preventFromSuspendWhenDownloading() const
{
    return readSetting(u"Preferences/General/PreventFromSuspendWhenDownloading"_s, false);
}

void Preferences::setPreventFromSuspendWhenDownloading(const bool b)
{
    if (b == preventFromSuspendWhenDownloading())
        return;

    writeSetting(u"Preferences/General/PreventFromSuspendWhenDownloading"_s, b);
}

bool Preferences::preventFromSuspendWhenSeeding() const
{
    return readSetting(u"Preferences/General/PreventFromSuspendWhenSeeding"_s, false);
}

void Preferences::setPreventFromSuspendWhenSeeding(const bool b)
{
    if (b == preventFromSuspendWhenSeeding())
        return;

    writeSetting(u"Preferences/General/PreventFromSuspendWhenSeeding"_s, b);
}

#ifdef Q_OS_WIN
bool Preferences::WinStartup() const
{
    const QString profileName = Profile::instance()->profileName();
    const Path profilePath = Profile::instance()->rootPath();
    const QString profileID = makeProfileID(profilePath, profileName);
    const QSettings settings {u"HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"_s, QSettings::NativeFormat};

    return settings.contains(profileID);
}

void Preferences::setWinStartup(const bool b)
{
    const QString profileName = Profile::instance()->profileName();
    const Path profilePath = Profile::instance()->rootPath();
    const QString profileID = makeProfileID(profilePath, profileName);
    QSettings settings {u"HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"_s, QSettings::NativeFormat};
    if (b)
    {
        const QString configuration = Profile::instance()->configurationName();

        const auto cmd = uR"("%1" "--profile=%2" "--configuration=%3")"_s
                .arg(Path(qApp->applicationFilePath()).toString(), profilePath.toString(), configuration);
        settings.setValue(profileID, cmd);
    }
    else
    {
        settings.remove(profileID);
    }
}
#endif // Q_OS_WIN

QString Preferences::getStyle() const
{
#ifdef Q_OS_WIN
    const QString defaultStyleName = u"Fusion"_s;
#else
    const QString defaultStyleName = u"system"_s;
#endif
    const auto styleName = readSetting<QString>(u"Appearance/Style"_s);
    return styleName.isEmpty() ? defaultStyleName : styleName;
}

void Preferences::setStyle(const QString &styleName)
{
    if (styleName == getStyle())
        return;

    writeSetting(u"Appearance/Style"_s, styleName);
}

// Downloads
Path Preferences::getScanDirsLastPath() const
{
    return readSetting<Path>(u"Preferences/Downloads/ScanDirsLastPath"_s);
}

void Preferences::setScanDirsLastPath(const Path &path)
{
    if (path == getScanDirsLastPath())
        return;

    writeSetting(u"Preferences/Downloads/ScanDirsLastPath"_s, path);
}

bool Preferences::isMailNotificationEnabled() const
{
    return readSetting(u"Preferences/MailNotification/enabled"_s, false);
}

void Preferences::setMailNotificationEnabled(const bool enabled)
{
    if (enabled == isMailNotificationEnabled())
        return;

    writeSetting(u"Preferences/MailNotification/enabled"_s, enabled);
}

QString Preferences::getMailNotificationSender() const
{
    return readSetting<QString>(u"Preferences/MailNotification/sender"_s);
}

void Preferences::setMailNotificationSender(const QString &mail)
{
    if (mail == getMailNotificationSender())
        return;

    writeSetting(u"Preferences/MailNotification/sender"_s, mail);
}

QString Preferences::getMailNotificationEmail() const
{
    return readSetting<QString>(u"Preferences/MailNotification/email"_s);
}

void Preferences::setMailNotificationEmail(const QString &mail)
{
    if (mail == getMailNotificationEmail())
        return;

    writeSetting(u"Preferences/MailNotification/email"_s, mail);
}

QString Preferences::getMailNotificationSMTP() const
{
    return readSetting<QString>(u"Preferences/MailNotification/smtp_server"_s);
}

void Preferences::setMailNotificationSMTP(const QString &smtpServer)
{
    if (smtpServer == getMailNotificationSMTP())
        return;

    writeSetting(u"Preferences/MailNotification/smtp_server"_s, smtpServer);
}

Net::SMTPEncryptionType Preferences::getMailNotificationSMTPEncryptionType() const
{
    return readSetting(u"Preferences/MailNotification/SMTPEncryptionType"_s, Net::SMTPEncryptionType::SMTPS);
}

void Preferences::setMailNotificationSMTPEncryptionType(const Net::SMTPEncryptionType mailEncryptionType)
{
    if (mailEncryptionType == getMailNotificationSMTPEncryptionType())
        return;

    writeSetting(u"Preferences/MailNotification/SMTPEncryptionType"_s, mailEncryptionType);
}

bool Preferences::getMailNotificationSMTPAuth() const
{
    return readSetting(u"Preferences/MailNotification/req_auth"_s, false);
}

void Preferences::setMailNotificationSMTPAuth(const bool use)
{
    if (use == getMailNotificationSMTPAuth())
        return;

    writeSetting(u"Preferences/MailNotification/req_auth"_s, use);
}

QString Preferences::getMailNotificationSMTPUsername() const
{
    return readSetting<QString>(u"Preferences/MailNotification/username"_s);
}

void Preferences::setMailNotificationSMTPUsername(const QString &username)
{
    if (username == getMailNotificationSMTPUsername())
        return;

    writeSetting(u"Preferences/MailNotification/username"_s, username);
}

QString Preferences::getMailNotificationSMTPPassword() const
{
    return readSetting<QString>(u"Preferences/MailNotification/password"_s);
}

void Preferences::setMailNotificationSMTPPassword(const QString &password)
{
    if (password == getMailNotificationSMTPPassword())
        return;

    writeSetting(u"Preferences/MailNotification/password"_s, password);
}

int Preferences::getActionOnDblClOnTorrentDl() const
{
    return readSetting<int>(u"Preferences/Downloads/DblClOnTorDl"_s, 0);
}

void Preferences::setActionOnDblClOnTorrentDl(const int act)
{
    if (act == getActionOnDblClOnTorrentDl())
        return;

    writeSetting(u"Preferences/Downloads/DblClOnTorDl"_s, act);
}

int Preferences::getActionOnDblClOnTorrentFn() const
{
    return readSetting<int>(u"Preferences/Downloads/DblClOnTorFn"_s, 1);
}

void Preferences::setActionOnDblClOnTorrentFn(const int act)
{
    if (act == getActionOnDblClOnTorrentFn())
        return;

    writeSetting(u"Preferences/Downloads/DblClOnTorFn"_s, act);
}

QTime Preferences::getSchedulerStartTime() const
{
    return readSetting(u"Preferences/Scheduler/start_time"_s, QTime(8, 0));
}

void Preferences::setSchedulerStartTime(const QTime &time)
{
    if (time == getSchedulerStartTime())
        return;

    writeSetting(u"Preferences/Scheduler/start_time"_s, time);
}

QTime Preferences::getSchedulerEndTime() const
{
    return readSetting(u"Preferences/Scheduler/end_time"_s, QTime(20, 0));
}

void Preferences::setSchedulerEndTime(const QTime &time)
{
    if (time == getSchedulerEndTime())
        return;

    writeSetting(u"Preferences/Scheduler/end_time"_s, time);
}

Scheduler::Days Preferences::getSchedulerDays() const
{
    return readSetting(u"Preferences/Scheduler/days"_s, Scheduler::Days::EveryDay);
}

void Preferences::setSchedulerDays(const Scheduler::Days days)
{
    if (days == getSchedulerDays())
        return;

    writeSetting(u"Preferences/Scheduler/days"_s, days);
}

// Search
bool Preferences::isSearchEnabled() const
{
    // Deliberately `true`, unlike upstream. This fork ships the nova3 runtime in
    // its own resources, so search is usable out of the box and the tab has no
    // reason to start hidden. When a prerequisite is missing the Search tab now
    // explains which one instead of appearing broken, so defaulting it on cannot
    // strand the user. Do not "restore" this to upstream's `false`.
    return readSetting(u"Preferences/Search/SearchEnabled"_s, true);
}

void Preferences::setSearchEnabled(const bool enabled)
{
    if (enabled == isSearchEnabled())
        return;

    writeSetting(u"Preferences/Search/SearchEnabled"_s, enabled);
}

int Preferences::searchHistoryLength() const
{
    const int val = readSetting(u"Search/HistoryLength"_s, 50);
    return std::clamp(val, 0, 99);
}

void Preferences::setSearchHistoryLength(const int length)
{
    const int clampedLength = std::clamp(length, 0, 99);
    if (clampedLength == searchHistoryLength())
        return;

    writeSetting(u"Search/HistoryLength"_s, clampedLength);
}

bool Preferences::storeOpenedSearchTabs() const
{
    return readSetting(u"Search/StoreOpenedSearchTabs"_s, false);
}

void Preferences::setStoreOpenedSearchTabs(const bool enabled)
{
    if (enabled == storeOpenedSearchTabs())
        return;

    writeSetting(u"Search/StoreOpenedSearchTabs"_s, enabled);
}

bool Preferences::storeOpenedSearchTabResults() const
{
    return readSetting(u"Search/StoreOpenedSearchTabResults"_s, false);
}

void Preferences::setStoreOpenedSearchTabResults(const bool enabled)
{
    if (enabled == storeOpenedSearchTabResults())
        return;

    writeSetting(u"Search/StoreOpenedSearchTabResults"_s, enabled);
}

bool Preferences::isWebUIEnabled() const
{
#ifdef DISABLE_GUI
    const bool defaultValue = true;
#else
    const bool defaultValue = false;
#endif
    return readSetting(u"Preferences/WebUI/Enabled"_s, defaultValue);
}

void Preferences::setWebUIEnabled(const bool enabled)
{
    if (enabled == isWebUIEnabled())
        return;

    writeSetting(u"Preferences/WebUI/Enabled"_s, enabled);
}

bool Preferences::isWebUILocalAuthEnabled() const
{
    return readSetting(u"Preferences/WebUI/LocalHostAuth"_s, true);
}

void Preferences::setWebUILocalAuthEnabled(const bool enabled)
{
    if (enabled == isWebUILocalAuthEnabled())
        return;

    writeSetting(u"Preferences/WebUI/LocalHostAuth"_s, enabled);
}

bool Preferences::isWebUIAuthSubnetWhitelistEnabled() const
{
    return readSetting(u"Preferences/WebUI/AuthSubnetWhitelistEnabled"_s, false);
}

void Preferences::setWebUIAuthSubnetWhitelistEnabled(const bool enabled)
{
    if (enabled == isWebUIAuthSubnetWhitelistEnabled())
        return;

    writeSetting(u"Preferences/WebUI/AuthSubnetWhitelistEnabled"_s, enabled);
}

QList<Utils::Net::Subnet> Preferences::getWebUIAuthSubnetWhitelist() const
{
    const auto subnets = readSetting<QStringList>(u"Preferences/WebUI/AuthSubnetWhitelist"_s);

    QList<Utils::Net::Subnet> ret;
    ret.reserve(subnets.size());

    for (const QString &rawSubnet : subnets)
    {
        const std::optional<Utils::Net::Subnet> subnet = Utils::Net::parseSubnet(rawSubnet.trimmed());
        if (subnet)
            ret.append(subnet.value());
    }

    return ret;
}

void Preferences::setWebUIAuthSubnetWhitelist(QStringList subnets)
{
    subnets.removeIf([](const QString &subnet)
    {
        return !Utils::Net::parseSubnet(subnet.trimmed()).has_value();
    });

    writeSetting(u"Preferences/WebUI/AuthSubnetWhitelist"_s, subnets);
}

QString Preferences::getServerDomains() const
{
    return readSetting<QString>(u"Preferences/WebUI/ServerDomains"_s, u"*"_s);
}

void Preferences::setServerDomains(const QString &str)
{
    if (str == getServerDomains())
        return;

    writeSetting(u"Preferences/WebUI/ServerDomains"_s, str);
}

QString Preferences::getWebUIAddress() const
{
    return readSetting<QString>(u"Preferences/WebUI/Address"_s, u"*"_s).trimmed();
}

void Preferences::setWebUIAddress(const QString &addr)
{
    if (addr == getWebUIAddress())
        return;

    writeSetting(u"Preferences/WebUI/Address"_s, addr.trimmed());
}

quint16 Preferences::getWebUIPort() const
{
    return readSetting<quint16>(u"Preferences/WebUI/Port"_s, 8080);
}

void Preferences::setWebUIPort(const quint16 port)
{
    if (port == getWebUIPort())
        return;

    // cast to `int` type so it will show human readable unit in configuration file
    writeSetting(u"Preferences/WebUI/Port"_s, static_cast<int>(port));
}

bool Preferences::useUPnPForWebUIPort() const
{
    return readSetting(u"Preferences/WebUI/UseUPnP"_s, false);
}

void Preferences::setUPnPForWebUIPort(const bool enabled)
{
    if (enabled == useUPnPForWebUIPort())
        return;

    writeSetting(u"Preferences/WebUI/UseUPnP"_s, enabled);
}

QString Preferences::getWebUIUsername() const
{
    return readSetting<QString>(u"Preferences/WebUI/Username"_s, u"admin"_s);
}

void Preferences::setWebUIUsername(const QString &username)
{
    if (username == getWebUIUsername())
        return;

    writeSetting(u"Preferences/WebUI/Username"_s, username);
}

QByteArray Preferences::getWebUIPassword() const
{
    return readSetting<QByteArray>(u"Preferences/WebUI/Password_PBKDF2"_s);
}

void Preferences::setWebUIPassword(const QByteArray &password)
{
    if (password == getWebUIPassword())
        return;

    writeSetting(u"Preferences/WebUI/Password_PBKDF2"_s, password);
}

QString Preferences::getWebUIApiKey() const
{
    return readSetting<QString>(u"Preferences/WebUI/APIKey"_s);
}

void Preferences::setWebUIApiKey(const QString &apiKey)
{
    if (apiKey == getWebUIApiKey())
        return;

    writeSetting(u"Preferences/WebUI/APIKey"_s, apiKey);
}

int Preferences::getWebUIMaxAuthFailCount() const
{
    return readSetting<int>(u"Preferences/WebUI/MaxAuthenticationFailCount"_s, 5);
}

void Preferences::setWebUIMaxAuthFailCount(const int count)
{
    if (count == getWebUIMaxAuthFailCount())
        return;

    writeSetting(u"Preferences/WebUI/MaxAuthenticationFailCount"_s, count);
}

std::chrono::seconds Preferences::getWebUIBanDuration() const
{
    return std::chrono::seconds(readSetting<int>(u"Preferences/WebUI/BanDuration"_s, 3600));
}

void Preferences::setWebUIBanDuration(const std::chrono::seconds duration)
{
    if (duration == getWebUIBanDuration())
        return;

    writeSetting(u"Preferences/WebUI/BanDuration"_s, static_cast<int>(duration.count()));
}

int Preferences::getWebUISessionTimeout() const
{
    return readSetting<int>(u"Preferences/WebUI/SessionTimeout"_s, 3600);
}

void Preferences::setWebUISessionTimeout(const int timeout)
{
    if (timeout == getWebUISessionTimeout())
        return;

    writeSetting(u"Preferences/WebUI/SessionTimeout"_s, timeout);
}

bool Preferences::isWebUIClickjackingProtectionEnabled() const
{
    return readSetting(u"Preferences/WebUI/ClickjackingProtection"_s, true);
}

void Preferences::setWebUIClickjackingProtectionEnabled(const bool enabled)
{
    if (enabled == isWebUIClickjackingProtectionEnabled())
        return;

    writeSetting(u"Preferences/WebUI/ClickjackingProtection"_s, enabled);
}

bool Preferences::isWebUICSRFProtectionEnabled() const
{
    return readSetting(u"Preferences/WebUI/CSRFProtection"_s, true);
}

void Preferences::setWebUICSRFProtectionEnabled(const bool enabled)
{
    if (enabled == isWebUICSRFProtectionEnabled())
        return;

    writeSetting(u"Preferences/WebUI/CSRFProtection"_s, enabled);
}

bool Preferences::isWebUISecureCookieEnabled() const
{
    return readSetting(u"Preferences/WebUI/SecureCookie"_s, true);
}

void Preferences::setWebUISecureCookieEnabled(const bool enabled)
{
    if (enabled == isWebUISecureCookieEnabled())
        return;

    writeSetting(u"Preferences/WebUI/SecureCookie"_s, enabled);
}

bool Preferences::isWebUIHostHeaderValidationEnabled() const
{
    return readSetting(u"Preferences/WebUI/HostHeaderValidation"_s, true);
}

void Preferences::setWebUIHostHeaderValidationEnabled(const bool enabled)
{
    if (enabled == isWebUIHostHeaderValidationEnabled())
        return;

    writeSetting(u"Preferences/WebUI/HostHeaderValidation"_s, enabled);
}

bool Preferences::isWebUIHttpsEnabled() const
{
    return readSetting(u"Preferences/WebUI/HTTPS/Enabled"_s, false);
}

void Preferences::setWebUIHttpsEnabled(const bool enabled)
{
    if (enabled == isWebUIHttpsEnabled())
        return;

    writeSetting(u"Preferences/WebUI/HTTPS/Enabled"_s, enabled);
}

Path Preferences::getWebUIHttpsCertificatePath() const
{
    return readSetting<Path>(u"Preferences/WebUI/HTTPS/CertificatePath"_s);
}

void Preferences::setWebUIHttpsCertificatePath(const Path &path)
{
    if (path == getWebUIHttpsCertificatePath())
        return;

    writeSetting(u"Preferences/WebUI/HTTPS/CertificatePath"_s, path);
}

Path Preferences::getWebUIHttpsKeyPath() const
{
    return readSetting<Path>(u"Preferences/WebUI/HTTPS/KeyPath"_s);
}

void Preferences::setWebUIHttpsKeyPath(const Path &path)
{
    if (path == getWebUIHttpsKeyPath())
        return;

    writeSetting(u"Preferences/WebUI/HTTPS/KeyPath"_s, path);
}

bool Preferences::isAltWebUIEnabled() const
{
    return readSetting(u"Preferences/WebUI/AlternativeUIEnabled"_s, false);
}

void Preferences::setAltWebUIEnabled(const bool enabled)
{
    if (enabled == isAltWebUIEnabled())
        return;

    writeSetting(u"Preferences/WebUI/AlternativeUIEnabled"_s, enabled);
}

Path Preferences::getWebUIRootFolder() const
{
    return readSetting<Path>(u"Preferences/WebUI/RootFolder"_s);
}

void Preferences::setWebUIRootFolder(const Path &path)
{
    if (path == getWebUIRootFolder())
        return;

    writeSetting(u"Preferences/WebUI/RootFolder"_s, path);
}

bool Preferences::isWebUICustomHTTPHeadersEnabled() const
{
    return readSetting(u"Preferences/WebUI/CustomHTTPHeadersEnabled"_s, false);
}

void Preferences::setWebUICustomHTTPHeadersEnabled(const bool enabled)
{
    if (enabled == isWebUICustomHTTPHeadersEnabled())
        return;

    writeSetting(u"Preferences/WebUI/CustomHTTPHeadersEnabled"_s, enabled);
}

QString Preferences::getWebUICustomHTTPHeaders() const
{
    return readSetting<QString>(u"Preferences/WebUI/CustomHTTPHeaders"_s);
}

void Preferences::setWebUICustomHTTPHeaders(const QString &headers)
{
    if (headers == getWebUICustomHTTPHeaders())
        return;

    writeSetting(u"Preferences/WebUI/CustomHTTPHeaders"_s, headers);
}

bool Preferences::isWebUIReverseProxySupportEnabled() const
{
    return readSetting(u"Preferences/WebUI/ReverseProxySupportEnabled"_s, false);
}

void Preferences::setWebUIReverseProxySupportEnabled(const bool enabled)
{
    if (enabled == isWebUIReverseProxySupportEnabled())
        return;

    writeSetting(u"Preferences/WebUI/ReverseProxySupportEnabled"_s, enabled);
}

QString Preferences::getWebUITrustedReverseProxiesList() const
{
    return readSetting<QString>(u"Preferences/WebUI/TrustedReverseProxiesList"_s);
}

void Preferences::setWebUITrustedReverseProxiesList(const QString &addr)
{
    if (addr == getWebUITrustedReverseProxiesList())
        return;

    writeSetting(u"Preferences/WebUI/TrustedReverseProxiesList"_s, addr);
}

bool Preferences::isDynDNSEnabled() const
{
    return readSetting(u"Preferences/DynDNS/Enabled"_s, false);
}

void Preferences::setDynDNSEnabled(const bool enabled)
{
    if (enabled == isDynDNSEnabled())
        return;

    writeSetting(u"Preferences/DynDNS/Enabled"_s, enabled);
}

DNS::Service Preferences::getDynDNSService() const
{
    return readSetting(u"Preferences/DynDNS/Service"_s, DNS::Service::DynDNS);
}

void Preferences::setDynDNSService(const DNS::Service service)
{
    if (service == getDynDNSService())
        return;

    writeSetting(u"Preferences/DynDNS/Service"_s, service);
}

QString Preferences::getDynDomainName() const
{
    return readSetting<QString>(u"Preferences/DynDNS/DomainName"_s, u"changeme.dyndns.org"_s);
}

void Preferences::setDynDomainName(const QString &name)
{
    if (name == getDynDomainName())
        return;

    writeSetting(u"Preferences/DynDNS/DomainName"_s, name);
}

QString Preferences::getDynDNSUsername() const
{
    return readSetting<QString>(u"Preferences/DynDNS/Username"_s);
}

void Preferences::setDynDNSUsername(const QString &username)
{
    if (username == getDynDNSUsername())
        return;

    writeSetting(u"Preferences/DynDNS/Username"_s, username);
}

QString Preferences::getDynDNSPassword() const
{
    return readSetting<QString>(u"Preferences/DynDNS/Password"_s);
}

void Preferences::setDynDNSPassword(const QString &password)
{
    if (password == getDynDNSPassword())
        return;

    writeSetting(u"Preferences/DynDNS/Password"_s, password);
}

// Advanced settings
QByteArray Preferences::getUILockPassword() const
{
    return readSetting<QByteArray>(u"Locking/password_PBKDF2"_s);
}

void Preferences::setUILockPassword(const QByteArray &password)
{
    if (password == getUILockPassword())
        return;

    writeSetting(u"Locking/password_PBKDF2"_s, password);
}

bool Preferences::isUILocked() const
{
    return readSetting(u"Locking/locked"_s, false);
}

void Preferences::setUILocked(const bool locked)
{
    if (locked == isUILocked())
        return;

    writeSetting(u"Locking/locked"_s, locked);
}

bool Preferences::isAutoRunOnTorrentAddedEnabled() const
{
    return readSetting(u"AutoRun/OnTorrentAdded/Enabled"_s, false);
}

void Preferences::setAutoRunOnTorrentAddedEnabled(const bool enabled)
{
    if (enabled == isAutoRunOnTorrentAddedEnabled())
        return;

    writeSetting(u"AutoRun/OnTorrentAdded/Enabled"_s, enabled);
}

QString Preferences::getAutoRunOnTorrentAddedProgram() const
{
    return readSetting<QString>(u"AutoRun/OnTorrentAdded/Program"_s);
}

void Preferences::setAutoRunOnTorrentAddedProgram(const QString &program)
{
    if (program == getAutoRunOnTorrentAddedProgram())
        return;

    writeSetting(u"AutoRun/OnTorrentAdded/Program"_s, program);
}

bool Preferences::isAutoRunOnTorrentFinishedEnabled() const
{
    return readSetting(u"AutoRun/enabled"_s, false);
}

void Preferences::setAutoRunOnTorrentFinishedEnabled(const bool enabled)
{
    if (enabled == isAutoRunOnTorrentFinishedEnabled())
        return;

    writeSetting(u"AutoRun/enabled"_s, enabled);
}

QString Preferences::getAutoRunOnTorrentFinishedProgram() const
{
    return readSetting<QString>(u"AutoRun/program"_s);
}

void Preferences::setAutoRunOnTorrentFinishedProgram(const QString &program)
{
    if (program == getAutoRunOnTorrentFinishedProgram())
        return;

    writeSetting(u"AutoRun/program"_s, program);
}

#if defined(Q_OS_WIN)
bool Preferences::isAutoRunConsoleEnabled() const
{
    return readSetting(u"AutoRun/ConsoleEnabled"_s, false);
}

void Preferences::setAutoRunConsoleEnabled(const bool enabled)
{
    if (enabled == isAutoRunConsoleEnabled())
        return;

    writeSetting(u"AutoRun/ConsoleEnabled"_s, enabled);
}
#endif

bool Preferences::shutdownWhenDownloadsComplete() const
{
    return readSetting(u"Preferences/Downloads/AutoShutDownOnCompletion"_s, false);
}

void Preferences::setShutdownWhenDownloadsComplete(const bool shutdown)
{
    if (shutdown == shutdownWhenDownloadsComplete())
        return;

    writeSetting(u"Preferences/Downloads/AutoShutDownOnCompletion"_s, shutdown);
}

bool Preferences::rebootWhenDownloadsComplete() const
{
    return readSetting(u"Preferences/Downloads/AutoRebootOnCompletion"_s, false);
}

void Preferences::setRebootWhenDownloadsComplete(const bool reboot)
{
    if (reboot == rebootWhenDownloadsComplete())
        return;

    writeSetting(u"Preferences/Downloads/AutoRebootOnCompletion"_s, reboot);
}

bool Preferences::suspendWhenDownloadsComplete() const
{
    return readSetting(u"Preferences/Downloads/AutoSuspendOnCompletion"_s, false);
}

void Preferences::setSuspendWhenDownloadsComplete(const bool suspend)
{
    if (suspend == suspendWhenDownloadsComplete())
        return;

    writeSetting(u"Preferences/Downloads/AutoSuspendOnCompletion"_s, suspend);
}

bool Preferences::hibernateWhenDownloadsComplete() const
{
    return readSetting(u"Preferences/Downloads/AutoHibernateOnCompletion"_s, false);
}

void Preferences::setHibernateWhenDownloadsComplete(const bool hibernate)
{
    if (hibernate == hibernateWhenDownloadsComplete())
        return;

    writeSetting(u"Preferences/Downloads/AutoHibernateOnCompletion"_s, hibernate);
}

bool Preferences::shutdownqBTWhenDownloadsComplete() const
{
    return readSetting(u"Preferences/Downloads/AutoShutDownqBTOnCompletion"_s, false);
}

void Preferences::setShutdownqBTWhenDownloadsComplete(const bool shutdown)
{
    if (shutdown == shutdownqBTWhenDownloadsComplete())
        return;

    writeSetting(u"Preferences/Downloads/AutoShutDownqBTOnCompletion"_s, shutdown);
}

bool Preferences::dontConfirmAutoExit() const
{
    return readSetting(u"ShutdownConfirmDlg/DontConfirmAutoExit"_s, false);
}

void Preferences::setDontConfirmAutoExit(const bool dontConfirmAutoExit)
{
    if (dontConfirmAutoExit == this->dontConfirmAutoExit())
        return;

    writeSetting(u"ShutdownConfirmDlg/DontConfirmAutoExit"_s, dontConfirmAutoExit);
}

bool Preferences::recheckTorrentsOnCompletion() const
{
    return readSetting(u"Preferences/Advanced/RecheckOnCompletion"_s, false);
}

void Preferences::recheckTorrentsOnCompletion(const bool recheck)
{
    if (recheck == recheckTorrentsOnCompletion())
        return;

    writeSetting(u"Preferences/Advanced/RecheckOnCompletion"_s, recheck);
}

bool Preferences::resolvePeerCountries() const
{
    return readSetting(u"Preferences/Connection/ResolvePeerCountries"_s, false);
}

void Preferences::resolvePeerCountries(const bool resolve)
{
    if (resolve == resolvePeerCountries())
        return;

    writeSetting(u"Preferences/Connection/ResolvePeerCountries"_s, resolve);
}

bool Preferences::resolvePeerHostNames() const
{
    return readSetting(u"Preferences/Connection/ResolvePeerHostNames"_s, false);
}

void Preferences::resolvePeerHostNames(const bool resolve)
{
    if (resolve == resolvePeerHostNames())
        return;

    writeSetting(u"Preferences/Connection/ResolvePeerHostNames"_s, resolve);
}

#if (defined(Q_OS_UNIX) && !defined(Q_OS_MACOS))
bool Preferences::useSystemIcons() const
{
    return readSetting(u"Preferences/Advanced/useSystemIconTheme"_s, false);
}

void Preferences::useSystemIcons(const bool enabled)
{
    if (enabled == useSystemIcons())
        return;

    writeSetting(u"Preferences/Advanced/useSystemIconTheme"_s, enabled);
}
#endif

bool Preferences::isRecursiveDownloadEnabled() const
{
    return !readSetting(u"Preferences/Advanced/DisableRecursiveDownload"_s, false);
}

void Preferences::setRecursiveDownloadEnabled(const bool enable)
{
    if (enable == isRecursiveDownloadEnabled())
        return;

    writeSetting(u"Preferences/Advanced/DisableRecursiveDownload"_s, !enable);
}

int Preferences::getTrackerPort() const
{
    return readSetting<int>(u"Preferences/Advanced/trackerPort"_s, 9000);
}

void Preferences::setTrackerPort(const int port)
{
    if (port == getTrackerPort())
        return;

    writeSetting(u"Preferences/Advanced/trackerPort"_s, port);
}

bool Preferences::isTrackerPortForwardingEnabled() const
{
    return readSetting(u"Preferences/Advanced/trackerPortForwarding"_s, false);
}

void Preferences::setTrackerPortForwardingEnabled(const bool enabled)
{
    if (enabled == isTrackerPortForwardingEnabled())
        return;

    writeSetting(u"Preferences/Advanced/trackerPortForwarding"_s, enabled);
}

bool Preferences::isMarkOfTheWebEnabled() const
{
    return readSetting(u"Preferences/Advanced/markOfTheWeb"_s, true);
}

void Preferences::setMarkOfTheWebEnabled(const bool enabled)
{
    if (enabled == isMarkOfTheWebEnabled())
        return;

    writeSetting(u"Preferences/Advanced/markOfTheWeb"_s, enabled);
}

bool Preferences::isIgnoreSSLErrors() const
{
    return readSetting(u"Preferences/Advanced/IgnoreSSLErrors"_s, false);
}

void Preferences::setIgnoreSSLErrors(const bool enabled)
{
    if (enabled == isIgnoreSSLErrors())
        return;

    writeSetting(u"Preferences/Advanced/IgnoreSSLErrors"_s, enabled);
}

Path Preferences::getPythonExecutablePath() const
{
    return readSetting(u"Preferences/Search/pythonExecutablePath"_s, Path());
}

void Preferences::setPythonExecutablePath(const Path &path)
{
    if (path == getPythonExecutablePath())
        return;

    writeSetting(u"Preferences/Search/pythonExecutablePath"_s, path);
}

#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
bool Preferences::isUpdateCheckEnabled() const
{
    return readSetting(u"Preferences/Advanced/updateCheck"_s, true);
}

void Preferences::setUpdateCheckEnabled(const bool enabled)
{
    if (enabled == isUpdateCheckEnabled())
        return;

    writeSetting(u"Preferences/Advanced/updateCheck"_s, enabled);
}
#endif

#ifdef Q_OS_MACOS
bool Preferences::isSpeedInDockEnabled() const
{
    return readSetting(u"Preferences/Desktop/ShowSpeedInDock"_s, true);
}

void Preferences::setSpeedInDockEnabled(const bool enabled)
{
    if (enabled == isSpeedInDockEnabled())
        return;

    writeSetting(u"Preferences/Desktop/ShowSpeedInDock"_s, enabled);
}

bool Preferences::isMacOSMenuBarIconEnabled() const
{
    return readSetting(u"Preferences/Desktop/ShowMacOSMenuBarIcon"_s, true);
}

void Preferences::setMacOSMenuBarIconEnabled(const bool enabled)
{
    if (enabled == isMacOSMenuBarIconEnabled())
        return;

    writeSetting(u"Preferences/Desktop/ShowMacOSMenuBarIcon"_s, enabled);
}
#endif

bool Preferences::confirmTorrentDeletion() const
{
    return readSetting(u"Preferences/Advanced/confirmTorrentDeletion"_s, true);
}

void Preferences::setConfirmTorrentDeletion(const bool enabled)
{
    if (enabled == confirmTorrentDeletion())
        return;

    writeSetting(u"Preferences/Advanced/confirmTorrentDeletion"_s, enabled);
}

bool Preferences::confirmTorrentRecheck() const
{
    return readSetting(u"Preferences/Advanced/confirmTorrentRecheck"_s, true);
}

void Preferences::setConfirmTorrentRecheck(const bool enabled)
{
    if (enabled == confirmTorrentRecheck())
        return;

    writeSetting(u"Preferences/Advanced/confirmTorrentRecheck"_s, enabled);
}

bool Preferences::confirmRemoveAllTags() const
{
    return readSetting(u"Preferences/Advanced/confirmRemoveAllTags"_s, true);
}

void Preferences::setConfirmRemoveAllTags(const bool enabled)
{
    if (enabled == confirmRemoveAllTags())
        return;

    writeSetting(u"Preferences/Advanced/confirmRemoveAllTags"_s, enabled);
}

bool Preferences::confirmMergeTrackers() const
{
    return readSetting(u"GUI/ConfirmActions/MergeTrackers"_s, true);
}

void Preferences::setConfirmMergeTrackers(const bool enabled)
{
    if (enabled == confirmMergeTrackers())
        return;

    writeSetting(u"GUI/ConfirmActions/MergeTrackers"_s, enabled);
}

bool Preferences::confirmRemoveTrackerFromAllTorrents() const
{
    return readSetting(u"GUI/ConfirmActions/RemoveTrackerFromAllTorrents"_s, true);
}

void Preferences::setConfirmRemoveTrackerFromAllTorrents(const bool enabled)
{
    if (enabled == confirmRemoveTrackerFromAllTorrents())
        return;

    writeSetting(u"GUI/ConfirmActions/RemoveTrackerFromAllTorrents"_s, enabled);
}

// Stuff that don't appear in the Options GUI but are saved
// in the same file.

QDateTime Preferences::getDNSLastUpd() const
{
    return readSetting<QDateTime>(u"DNSUpdater/lastUpdateTime"_s);
}

void Preferences::setDNSLastUpd(const QDateTime &date)
{
    if (date == getDNSLastUpd())
        return;

    writeSetting(u"DNSUpdater/lastUpdateTime"_s, date);
}

QString Preferences::getDNSLastIP() const
{
    return readSetting<QString>(u"DNSUpdater/lastIP"_s);
}

void Preferences::setDNSLastIP(const QString &ip)
{
    if (ip == getDNSLastIP())
        return;

    writeSetting(u"DNSUpdater/lastIP"_s, ip);
}

QByteArray Preferences::getMainGeometry() const
{
    return readSetting<QByteArray>(u"MainWindow/geometry"_s);
}

void Preferences::setMainGeometry(const QByteArray &geometry)
{
    if (geometry == getMainGeometry())
        return;

    writeSetting(u"MainWindow/geometry"_s, geometry);
}

bool Preferences::isFiltersSidebarVisible() const
{
    return readSetting(u"GUI/MainWindow/FiltersSidebarVisible"_s, true);
}

void Preferences::setFiltersSidebarVisible(const bool value)
{
    if (value == isFiltersSidebarVisible())
        return;

    writeSetting(u"GUI/MainWindow/FiltersSidebarVisible"_s, value);
}

int Preferences::getFiltersSidebarWidth() const
{
    return readSetting(u"GUI/MainWindow/FiltersSidebarWidth"_s, 120);
}

void Preferences::setFiltersSidebarWidth(const int value)
{
    if (value == getFiltersSidebarWidth())
        return;

    writeSetting(u"GUI/MainWindow/FiltersSidebarWidth"_s, value);
}

Path Preferences::getMainLastDir() const
{
    return readSetting(u"MainWindow/LastDir"_s, Utils::Fs::homePath());
}

void Preferences::setMainLastDir(const Path &path)
{
    if (path == getMainLastDir())
        return;

    writeSetting(u"MainWindow/LastDir"_s, path);
}

QByteArray Preferences::getPeerListState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/TorrentProperties/PeerListState"_s);
}

void Preferences::setPeerListState(const QByteArray &state)
{
    if (state == getPeerListState())
        return;

    writeSetting(u"GUI/Qt6/TorrentProperties/PeerListState"_s, state);
}

QString Preferences::getPropSplitterSizes() const
{
    return readSetting<QString>(u"TorrentProperties/SplitterSizes"_s);
}

void Preferences::setPropSplitterSizes(const QString &sizes)
{
    if (sizes == getPropSplitterSizes())
        return;

    writeSetting(u"TorrentProperties/SplitterSizes"_s, sizes);
}

QByteArray Preferences::getPropFileListState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/TorrentProperties/FilesListState"_s);
}

void Preferences::setPropFileListState(const QByteArray &state)
{
    if (state == getPropFileListState())
        return;

    writeSetting(u"GUI/Qt6/TorrentProperties/FilesListState"_s, state);
}

int Preferences::getPropCurTab() const
{
    return readSetting<int>(u"TorrentProperties/CurrentTab"_s, -1);
}

void Preferences::setPropCurTab(const int tab)
{
    if (tab == getPropCurTab())
        return;

    writeSetting(u"TorrentProperties/CurrentTab"_s, tab);
}

bool Preferences::getPropVisible() const
{
    return readSetting(u"TorrentProperties/Visible"_s, false);
}

void Preferences::setPropVisible(const bool visible)
{
    if (visible == getPropVisible())
        return;

    writeSetting(u"TorrentProperties/Visible"_s, visible);
}

QByteArray Preferences::getTrackerListState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/TorrentProperties/TrackerListState"_s);
}

void Preferences::setTrackerListState(const QByteArray &state)
{
    if (state == getTrackerListState())
        return;

    writeSetting(u"GUI/Qt6/TorrentProperties/TrackerListState"_s, state);
}

QStringList Preferences::getRssOpenFolders() const
{
    return readSetting<QStringList>(u"GUI/RSSWidget/OpenedFolders"_s);
}

void Preferences::setRssOpenFolders(const QStringList &folders)
{
    if (folders == getRssOpenFolders())
        return;

    writeSetting(u"GUI/RSSWidget/OpenedFolders"_s, folders);
}

QByteArray Preferences::getRssFeedListState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/RSSWidget/FeedListState"_s);
}

void Preferences::setRssFeedListState(const QByteArray &state)
{
    if (state == getRssFeedListState())
        return;

    writeSetting(u"GUI/Qt6/RSSWidget/FeedListState"_s, state);
}

QByteArray Preferences::getRssSideSplitterState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/RSSWidget/SideSplitterState"_s);
}

void Preferences::setRssSideSplitterState(const QByteArray &state)
{
    if (state == getRssSideSplitterState())
        return;

    writeSetting(u"GUI/Qt6/RSSWidget/SideSplitterState"_s, state);
}

QByteArray Preferences::getRssMainSplitterState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/RSSWidget/MainSplitterState"_s);
}

void Preferences::setRssMainSplitterState(const QByteArray &state)
{
    if (state == getRssMainSplitterState())
        return;

    writeSetting(u"GUI/Qt6/RSSWidget/MainSplitterState"_s, state);
}

QByteArray Preferences::getSearchTabHeaderState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/SearchTab/HeaderState"_s);
}

void Preferences::setSearchTabHeaderState(const QByteArray &state)
{
    if (state == getSearchTabHeaderState())
        return;

    writeSetting(u"GUI/Qt6/SearchTab/HeaderState"_s, state);
}

bool Preferences::getRegexAsFilteringPatternForSearchJob() const
{
    return readSetting(u"SearchTab/UseRegexAsFilteringPattern"_s, false);
}

void Preferences::setRegexAsFilteringPatternForSearchJob(const bool checked)
{
    if (checked == getRegexAsFilteringPatternForSearchJob())
        return;

    writeSetting(u"SearchTab/UseRegexAsFilteringPattern"_s, checked);
}

QStringList Preferences::getSearchEngDisabled() const
{
    return readSetting<QStringList>(u"SearchEngines/disabledEngines"_s);
}

void Preferences::setSearchEngDisabled(const QStringList &engines)
{
    if (engines == getSearchEngDisabled())
        return;

    writeSetting(u"SearchEngines/disabledEngines"_s, engines);
}

QStringList Preferences::getSeededSearchPlugins() const
{
    return readSetting<QStringList>(u"SearchEngines/seededPlugins"_s);
}

void Preferences::setSeededSearchPlugins(const QStringList &plugins)
{
    if (plugins == getSeededSearchPlugins())
        return;

    writeSetting(u"SearchEngines/seededPlugins"_s, plugins);
}

QString Preferences::getTorImportLastContentDir() const
{
    return readSetting(u"TorrentImport/LastContentDir"_s, QDir::homePath());
}

void Preferences::setTorImportLastContentDir(const QString &path)
{
    if (path == getTorImportLastContentDir())
        return;

    writeSetting(u"TorrentImport/LastContentDir"_s, path);
}

QByteArray Preferences::getTorImportGeometry() const
{
    return readSetting<QByteArray>(u"TorrentImportDlg/dimensions"_s);
}

void Preferences::setTorImportGeometry(const QByteArray &geometry)
{
    if (geometry == getTorImportGeometry())
        return;

    writeSetting(u"TorrentImportDlg/dimensions"_s, geometry);
}

bool Preferences::getStatusFilterState() const
{
    return readSetting(u"TransferListFilters/statusFilterState"_s, true);
}

void Preferences::setStatusFilterState(const bool checked)
{
    if (checked == getStatusFilterState())
        return;

    writeSetting(u"TransferListFilters/statusFilterState"_s, checked);
}

bool Preferences::getCategoryFilterState() const
{
    return readSetting(u"TransferListFilters/CategoryFilterState"_s, true);
}

void Preferences::setCategoryFilterState(const bool checked)
{
    if (checked == getCategoryFilterState())
        return;

    writeSetting(u"TransferListFilters/CategoryFilterState"_s, checked);
}

bool Preferences::getTagFilterState() const
{
    return readSetting(u"TransferListFilters/TagFilterState"_s, true);
}

void Preferences::setTagFilterState(const bool checked)
{
    if (checked == getTagFilterState())
        return;

    writeSetting(u"TransferListFilters/TagFilterState"_s, checked);
}

bool Preferences::getTrackerFilterState() const
{
    return readSetting(u"TransferListFilters/trackerFilterState"_s, true);
}

void Preferences::setTrackerFilterState(const bool checked)
{
    if (checked == getTrackerFilterState())
        return;

    writeSetting(u"TransferListFilters/trackerFilterState"_s, checked);
}

bool Preferences::getTrackerStatusFilterState() const
{
    return readSetting(u"TransferListFilters/TrackerStatusFilterState"_s, true);
}

void Preferences::setTrackerStatusFilterState(const bool checked)
{
    if (checked == getTrackerStatusFilterState())
        return;

    writeSetting(u"TransferListFilters/TrackerStatusFilterState"_s, checked);
}

bool Preferences::useSeparateTrackerStatusFilter() const
{
    return readSetting(u"TransferListFilters/SeparateTrackerStatusFilter"_s, false);
}

void Preferences::setUseSeparateTrackerStatusFilter(const bool value)
{
    if (value == useSeparateTrackerStatusFilter())
        return;

    writeSetting(u"TransferListFilters/SeparateTrackerStatusFilter"_s, value);
}

int Preferences::getTransSelFilter() const
{
    return readSetting<int>(u"TransferListFilters/selectedFilterIndex"_s, 0);
}

void Preferences::setTransSelFilter(const int index)
{
    if (index == getTransSelFilter())
        return;

    writeSetting(u"TransferListFilters/selectedFilterIndex"_s, index);
}

bool Preferences::getHideZeroStatusFilters() const
{
    return readSetting<bool>(u"TransferListFilters/HideZeroStatusFilters"_s, false);
}

void Preferences::setHideZeroStatusFilters(const bool hide)
{
    if (hide == getHideZeroStatusFilters())
        return;

    writeSetting(u"TransferListFilters/HideZeroStatusFilters"_s, hide);
}

QByteArray Preferences::getTransHeaderState() const
{
    return readSetting<QByteArray>(u"GUI/Qt6/TransferList/HeaderState"_s);
}

void Preferences::setTransHeaderState(const QByteArray &state)
{
    if (state == getTransHeaderState())
        return;

    writeSetting(u"GUI/Qt6/TransferList/HeaderState"_s, state);
}

bool Preferences::getRegexAsFilteringPatternForTransferList() const
{
    return readSetting(u"TransferList/UseRegexAsFilteringPattern"_s, false);
}

void Preferences::setRegexAsFilteringPatternForTransferList(const bool checked)
{
    if (checked == getRegexAsFilteringPatternForTransferList())
        return;

    writeSetting(u"TransferList/UseRegexAsFilteringPattern"_s, checked);
}

// From old RssSettings class
bool Preferences::isRSSWidgetEnabled() const
{
    return readSetting(u"GUI/RSSWidget/Enabled"_s, false);
}

void Preferences::setRSSWidgetVisible(const bool enabled)
{
    if (enabled == isRSSWidgetEnabled())
        return;

    writeSetting(u"GUI/RSSWidget/Enabled"_s, enabled);
}

int Preferences::getToolbarTextPosition() const
{
    return readSetting<int>(u"Toolbar/textPosition"_s, -1);
}

void Preferences::setToolbarTextPosition(const int position)
{
    if (position == getToolbarTextPosition())
        return;

    writeSetting(u"Toolbar/textPosition"_s, position);
}

QList<QNetworkCookie> Preferences::getNetworkCookies() const
{
    const auto rawCookies = readSetting<QStringList>(u"Network/Cookies"_s);
    QList<QNetworkCookie> cookies;
    cookies.reserve(rawCookies.size());
    for (const QString &rawCookie : rawCookies)
        cookies << QNetworkCookie::parseCookies(rawCookie.toUtf8());
    return cookies;
}

void Preferences::setNetworkCookies(const QList<QNetworkCookie> &cookies)
{
    QStringList rawCookies;
    rawCookies.reserve(cookies.size());
    for (const QNetworkCookie &cookie : cookies)
        rawCookies << QString::fromLatin1(cookie.toRawForm());
    writeSetting(u"Network/Cookies"_s, rawCookies);
}

bool Preferences::useProxyForBT() const
{
    return readSetting<bool>(u"Network/Proxy/Profiles/BitTorrent"_s);
}

void Preferences::setUseProxyForBT(const bool value)
{
    if (value == useProxyForBT())
        return;

    writeSetting(u"Network/Proxy/Profiles/BitTorrent"_s, value);
}

bool Preferences::useProxyForRSS() const
{
    return readSetting<bool>(u"Network/Proxy/Profiles/RSS"_s);
}

void Preferences::setUseProxyForRSS(const bool value)
{
    if (value == useProxyForRSS())
        return;

    writeSetting(u"Network/Proxy/Profiles/RSS"_s, value);
}

bool Preferences::useProxyForGeneralPurposes() const
{
    return readSetting<bool>(u"Network/Proxy/Profiles/Misc"_s);
}

void Preferences::setUseProxyForGeneralPurposes(const bool value)
{
    if (value == useProxyForGeneralPurposes())
        return;

    writeSetting(u"Network/Proxy/Profiles/Misc"_s, value);
}

bool Preferences::isSpeedWidgetEnabled() const
{
    return readSetting(u"SpeedWidget/Enabled"_s, true);
}

void Preferences::setSpeedWidgetEnabled(const bool enabled)
{
    if (enabled == isSpeedWidgetEnabled())
        return;

    writeSetting(u"SpeedWidget/Enabled"_s, enabled);
}

int Preferences::getSpeedWidgetPeriod() const
{
    return readSetting<int>(u"SpeedWidget/period"_s, 1);
}

void Preferences::setSpeedWidgetPeriod(const int period)
{
    if (period == getSpeedWidgetPeriod())
        return;

    writeSetting(u"SpeedWidget/period"_s, period);
}

bool Preferences::getSpeedWidgetGraphEnable(const int id) const
{
    // UP and DOWN graphs enabled by default
    return readSetting(u"SpeedWidget/graph_enable_%1"_s.arg(id), ((id == 0) || (id == 1)));
}

void Preferences::setSpeedWidgetGraphEnable(const int id, const bool enable)
{
    if (enable == getSpeedWidgetGraphEnable(id))
        return;

    writeSetting(u"SpeedWidget/graph_enable_%1"_s.arg(id), enable);
}

bool Preferences::isAddNewTorrentDialogEnabled() const
{
    return readSetting(u"AddNewTorrentDialog/Enabled"_s, true);
}

void Preferences::setAddNewTorrentDialogEnabled(const bool value)
{
    if (value == isAddNewTorrentDialogEnabled())
        return;

    writeSetting(u"AddNewTorrentDialog/Enabled"_s, value);
}

bool Preferences::isAddNewTorrentDialogTopLevel() const
{
    return readSetting(u"AddNewTorrentDialog/TopLevel"_s, true);
}

void Preferences::setAddNewTorrentDialogTopLevel(const bool value)
{
    if (value == isAddNewTorrentDialogTopLevel())
        return;

    writeSetting(u"AddNewTorrentDialog/TopLevel"_s, value);
}

int Preferences::addNewTorrentDialogSavePathHistoryLength() const
{
    const int defaultHistoryLength = 8;

    const int val = readSetting(u"AddNewTorrentDialog/SavePathHistoryLength"_s, defaultHistoryLength);
    return std::clamp(val, 0, 99);
}

void Preferences::setAddNewTorrentDialogSavePathHistoryLength(const int value)
{
    const int clampedValue = std::clamp(value, 0, 99);
    const int oldValue = addNewTorrentDialogSavePathHistoryLength();
    if (clampedValue == oldValue)
        return;

    writeSetting(u"AddNewTorrentDialog/SavePathHistoryLength"_s, clampedValue);
}

bool Preferences::isAddNewTorrentDialogAttached() const
{
    return readSetting(u"AddNewTorrentDialog/Attached"_s, false);
}

void Preferences::setAddNewTorrentDialogAttached(const bool attached)
{
    if (attached == isAddNewTorrentDialogAttached())
        return;

    writeSetting(u"AddNewTorrentDialog/Attached"_s, attached);
}

// New in the Material rewrite: UI language mode
// (0 = English, 1 = Cantonese, 2 = Bilingual). Key: "Appearance/Language".
int Preferences::getLanguageMode() const
{
    const int mode = readSetting<int>(u"Appearance/Language"_s, 0);
    return std::clamp(mode, 0, 2);
}

void Preferences::setLanguageMode(const int mode)
{
    const int clampedMode = std::clamp(mode, 0, 2);
    if (clampedMode == getLanguageMode())
        return;

    qCInfo(lcI18n) << "Preferences: UI language mode changed to" << clampedMode;
    writeSetting(u"Appearance/Language"_s, clampedMode);
}

void Preferences::apply()
{
    qCDebug(lcApp) << "Preferences: apply() requested; flushing settings";
    if (SettingsStorage::instance()->save())
    {
        qCInfo(lcApp) << "Preferences: settings applied, emitting changed()";
        emit changed();
    }
}
