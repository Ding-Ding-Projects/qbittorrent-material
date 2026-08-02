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

#include "appcontroller.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QQuickWindow>
#include <QRegularExpression>

#include "base/logging.h"
#include "app/application.h"
#include "app/updatecheck.h"
#include "base/net/downloadmanager.h"

#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

#if __has_include("base/utils/password.h")
#include "base/utils/password.h"
#define QBT_HAS_PASSWORD 1
#endif

using namespace Qt::StringLiterals;

namespace
{
    const QString kLockPasswordKey = u"Locking/password_PBKDF2"_qs;

    /// Recognize a string worth handing to the add-torrent pipeline.
    bool looksAddable(const QString &text)
    {
        const QString t = text.trimmed();
        if (t.isEmpty())
            return false;
        if (t.startsWith(u"magnet:", Qt::CaseInsensitive))
            return true;
        if (t.startsWith(u"http://", Qt::CaseInsensitive)
            || t.startsWith(u"https://", Qt::CaseInsensitive))
            return true;
        // A local .torrent file (as passed by the OS on double-click / file
        // association) — accept both a plain path and a file:// URL.
        if (t.startsWith(u"file:", Qt::CaseInsensitive))
            return true;
        if (t.endsWith(u".torrent", Qt::CaseInsensitive) && QFileInfo::exists(t))
            return true;
        // Bare v1 (40 hex) or v2 (64 hex) info-hash.
        static const QRegularExpression hashRe(u"^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$"_qs);
        return hashRe.match(t).hasMatch();
    }
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    qCDebug(lcUi) << "AppController constructed";
}

AppController::~AppController()
{
    qCDebug(lcUi) << "AppController destroyed";
}

AppController *AppController::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)

    Application *app = Application::instance();
    Q_ASSERT_X(app, "AppController::create", "Application instance must exist");
    AppController *controller = app ? app->appController() : nullptr;
    Q_ASSERT_X(controller, "AppController::create", "AppController instance must exist");

    // The instance is owned by Application, not the QML engine.
    QQmlEngine::setObjectOwnership(controller, QQmlEngine::CppOwnership);
    qCDebug(lcUi) << "AppController singleton handed to QML";
    return controller;
}

bool AppController::isLocked() const
{
    return m_locked;
}

QString AppController::storedPasswordHash()
{
#ifdef QBT_HAS_PREFERENCES
    return Preferences::instance()->value(kLockPasswordKey).toString();
#else
    return {};
#endif
}

bool AppController::isLockPasswordSet() const
{
    return !storedPasswordHash().isEmpty();
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------
void AppController::exit(bool force)
{
    qCInfo(lcUi) << "exit() requested; force =" << force;

    bool confirm = false;
#ifdef QBT_HAS_PREFERENCES
    confirm = Preferences::instance()->value(u"Preferences/General/ExitConfirm"_qs, true).toBool();
#endif
    if (!force && confirm)
    {
        qCDebug(lcUi) << "Exit needs confirmation — asking the shell";
        emit confirmExitRequested();
        return;
    }

    qCInfo(lcUi) << "Quitting application";
    // Deferred: exit() is typically invoked from a QML signal handler, and
    // quitting synchronously would run Application::cleanup() -- which tears
    // down the QML engine -- while that handler is still on the stack.
    QMetaObject::invokeMethod(QCoreApplication::instance(), &QCoreApplication::quit,
            Qt::QueuedConnection);
}

void AppController::minimizeToTray()
{
    qCInfo(lcUi) << "minimizeToTray()";
    emit hideMainWindowRequested();
}

void AppController::showMainWindow()
{
    qCInfo(lcUi) << "showMainWindow()";
    emit showMainWindowRequested();
}

void AppController::toggleMainWindow()
{
    qCInfo(lcUi) << "toggleMainWindow()";
    emit toggleMainWindowRequested();
}

void AppController::lock()
{
    if (!isLockPasswordSet())
    {
        qCWarning(lcUi) << "lock() ignored — no UI-lock password configured";
        emit notify(tr("Set a UI lock password first."));
        return;
    }
    if (m_locked)
        return;

    m_locked = true;
    qCInfo(lcUi) << "UI locked";
    emit lockedChanged();
}

bool AppController::unlock(const QString &password)
{
    qCDebug(lcUi) << "unlock() attempt";
    const QString stored = storedPasswordHash();
    if (stored.isEmpty())
    {
        // Nothing to unlock against — just clear the lock.
        m_locked = false;
        emit lockedChanged();
        return true;
    }

    bool ok = false;
#ifdef QBT_HAS_PASSWORD
    ok = Utils::Password::PBKDF2::verify(stored.toUtf8(), password);
#else
    // Fallback verification: compare a SHA-256 hex of the password.
    const QString candidate = QString::fromLatin1(
        QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex());
    ok = (candidate == stored);
#endif

    if (ok)
    {
        m_locked = false;
        qCInfo(lcUi) << "UI unlocked";
        emit lockedChanged();
    }
    else
    {
        qCWarning(lcUi) << "unlock() failed — wrong password";
    }
    return ok;
}

void AppController::setLockPassword(const QString &password)
{
#ifdef QBT_HAS_PREFERENCES
    if (password.isEmpty())
    {
        Preferences::instance()->setValue(kLockPasswordKey, QString());
        qCInfo(lcUi) << "UI-lock password cleared";
    }
    else
    {
        QString hash;
#ifdef QBT_HAS_PASSWORD
        hash = QString::fromLatin1(Utils::Password::PBKDF2::generate(password));
#else
        hash = QString::fromLatin1(
            QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex());
#endif
        Preferences::instance()->setValue(kLockPasswordKey, hash);
        qCInfo(lcUi) << "UI-lock password updated";
    }
    Preferences::instance()->apply();
    emit lockedChanged();
#else
    Q_UNUSED(password)
    qCWarning(lcUi) << "setLockPassword() ignored — Preferences unavailable";
#endif
}

void AppController::checkForUpdates()
{
    if (m_updateCheckInProgress)
    {
        emit notify(tr("An update check is already in progress."));
        return;
    }

    qCInfo(lcUi) << "checkForUpdates() requested";
    emit notify(tr("Checking for updates…"));
    m_updateCheckInProgress = true;

    constexpr qint64 maxReleaseResponseSize = 256 * 1024;
    const auto request = Net::DownloadRequest(
        u"https://api.github.com/repos/Ding-Ding-Projects/qbittorrent-material/releases/latest"_s)
        .userAgent(QStringLiteral("qBittorrent-Material/" QBT_BUILD_ID " ProgramUpdater"))
        .limit(maxReleaseResponseSize);

    bool useProxy = false;
#ifdef QBT_HAS_PREFERENCES
    useProxy = Preferences::instance()->useProxyForGeneralPurposes();
#endif

    Net::DownloadManager::instance()->download(request, useProxy, this,
        [this](const Net::DownloadResult &result)
    {
        m_updateCheckInProgress = false;
        if (result.status != Net::DownloadStatus::Success)
        {
            qCWarning(lcUi) << "Update check download failed:" << result.errorString;
            emit notify(tr("Could not check for updates. Please try again later."));
            return;
        }

        QString parseError;
        const UpdateCheck::Release latest = UpdateCheck::parseLatestRelease(result.data, &parseError);
        if (!latest.isValid())
        {
            qCWarning(lcUi) << "Update check response rejected:" << parseError;
            emit notify(tr("Could not understand the latest release information."));
            return;
        }

        const bool available = UpdateCheck::isNewer(
            latest, QStringLiteral(QBT_BUILD_ID));
        emit updateCheckFinished(available, latest.tagName);
        qCInfo(lcUi) << "Update check completed; current build" << QBT_BUILD_ID
                     << "latest" << latest.tagName << "available" << available;
    });
}

void AppController::pasteAdd()
{
    const QString clip = QGuiApplication::clipboard()->text();
    qCInfo(lcUi) << "pasteAdd() — clipboard length" << clip.size();
    if (looksAddable(clip))
    {
        addTorrentFromSource(clip.trimmed());
    }
    else
    {
        qCDebug(lcUi) << "Clipboard content is not an addable torrent source";
        emit notify(tr("Clipboard does not contain a torrent link."));
    }
}

void AppController::addTorrentFromSource(const QString &source)
{
    if (source.trimmed().isEmpty())
    {
        qCDebug(lcUi) << "addTorrentFromSource() ignored empty source";
        return;
    }
    qCInfo(lcUi) << "Requesting torrent add for source:" << source.left(80);
    emit addTorrentRequested(source.trimmed());
}

bool AppController::captureMainWindow(const QString &filePath) const
{
    const QFileInfo output(filePath);
    if (output.absoluteFilePath().isEmpty())
        return false;

    QDir().mkpath(output.absolutePath());
    for (QWindow *const window : QGuiApplication::topLevelWindows())
    {
        auto *const quickWindow = qobject_cast<QQuickWindow *>(window);
        if (!quickWindow || !quickWindow->isVisible())
            continue;

        const QImage image = quickWindow->grabWindow();
        const bool saved = !image.isNull() && image.save(output.absoluteFilePath(), "PNG");
        if (saved)
            qCInfo(lcUi) << "Captured main window ->" << output.absoluteFilePath();
        else
            qCWarning(lcUi) << "Failed to capture main window ->" << output.absoluteFilePath();
        return saved;
    }

    qCWarning(lcUi) << "No visible Qt Quick window available for capture";
    return false;
}

void AppController::handleActivationRequest(const QString &payload)
{
    qCInfo(lcUi) << "Activation request payload:" << payload.left(80);
    if (looksAddable(payload))
        addTorrentFromSource(payload);
    emit showMainWindowRequested();
}
