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

#include "desktopintegration.h"

#include <QApplication>
#include <QDir>
#include <QIcon>
#include <QFileInfo>
#include <QHash>
#include <QProcess>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QUrl>

#include "base/logging.h"
#include "app/application.h"
#include "quick/theme/thememanager.h"

#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

using namespace Qt::StringLiterals;

namespace
{
    const QString kNotificationsKey = u"Preferences/General/NotificationEnabled"_qs;
    const QString kSelectedEditorKey = u"Preferences/ExternalEditor/Selected"_qs;
    const QString kCustomEditorKey = u"Preferences/ExternalEditor/CustomPath"_qs;

    QString trayIconResource(const ThemeManager::TrayIconStyle style)
    {
        switch (style)
        {
        case ThemeManager::Normal:
            return u":/branding/logo-mark.png"_qs;
        case ThemeManager::Monochrome:
        default:
            // Legacy profiles may retain the historic dark-monochrome value
            // (2). Treat every non-normal value as monochrome so their tray
            // artwork remains visually compatible.
            return u":/branding/logo-monochrome.png"_qs;
        }
    }
}

DesktopIntegration::DesktopIntegration(QObject *parent)
    : QObject(parent)
{
    qCDebug(lcUi) << "DesktopIntegration constructing";

#ifdef QBT_HAS_PREFERENCES
    m_notificationsEnabled = Preferences::instance()->value(kNotificationsKey, true).toBool();
    m_selectedEditor = Preferences::instance()->value(kSelectedEditorKey).toString();
    m_customEditorPath = Preferences::instance()->value(kCustomEditorKey).toString();
#endif

    refreshEditors();

    // OptionsController commits this setting through ThemeManager on Apply.
    // Updating the native icon here keeps the actual system tray in sync with
    // the committed style without making a staged edit visible prematurely.
    connect(ThemeManager::instance(), &ThemeManager::trayIconStyleChanged,
        this, &DesktopIntegration::refreshTrayIcon);

    if (QSystemTrayIcon::isSystemTrayAvailable())
    {
        createTrayIcon();
    }
    else
    {
        qCWarning(lcUi) << "System tray is not available on this platform/session";
    }
}

DesktopIntegration::~DesktopIntegration()
{
    qCDebug(lcUi) << "DesktopIntegration destroyed";
    if (m_trayIcon)
        m_trayIcon->hide();
}

DesktopIntegration *DesktopIntegration::create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
{
    Q_UNUSED(qmlEngine)
    Q_UNUSED(jsEngine)

    Application *app = Application::instance();
    Q_ASSERT_X(app, "DesktopIntegration::create", "Application instance must exist");
    DesktopIntegration *di = app ? app->desktopIntegration() : nullptr;
    Q_ASSERT_X(di, "DesktopIntegration::create", "DesktopIntegration instance must exist");

    QQmlEngine::setObjectOwnership(di, QQmlEngine::CppOwnership);
    qCDebug(lcUi) << "DesktopIntegration singleton handed to QML";
    return di;
}

void DesktopIntegration::createTrayIcon()
{
    m_trayIcon = new QSystemTrayIcon(resolveTrayIcon(), this);
    m_trayIcon->setToolTip(m_toolTip.isEmpty() ? u"qBittorrent"_qs : m_toolTip);

    connect(m_trayIcon, &QSystemTrayIcon::activated, this,
        [this](QSystemTrayIcon::ActivationReason reason)
        {
            qCDebug(lcUi) << "Tray activated, reason =" << reason;
            switch (reason)
            {
            case QSystemTrayIcon::Trigger:
            case QSystemTrayIcon::DoubleClick:
                emit activationRequested();
                break;
            case QSystemTrayIcon::Context:
                emit contextMenuRequested();
                break;
            default:
                break;
            }
        });

    connect(m_trayIcon, &QSystemTrayIcon::messageClicked, this, [this]
    {
        qCDebug(lcUi) << "Tray notification clicked";
        emit notificationClicked();
    });

    m_trayIcon->show();
    qCInfo(lcUi) << "System tray icon created and shown";
}

QIcon DesktopIntegration::resolveTrayIcon() const
{
    const QString resource = trayIconResource(ThemeManager::instance()->trayIconStyle());
    QIcon icon(resource);
    if (icon.isNull())
    {
        qCWarning(lcUi) << "Tray icon resource missing:" << resource
                        << "— falling back to window icon";
        icon = QApplication::windowIcon();
    }
    return icon;
}

void DesktopIntegration::refreshTrayIcon()
{
    if (!m_trayIcon)
        return;
    qCDebug(lcUi) << "Refreshing tray icon artwork";
    m_trayIcon->setIcon(resolveTrayIcon());
}

bool DesktopIntegration::isAvailable() const
{
    return (m_trayIcon != nullptr);
}

bool DesktopIntegration::isVisible() const
{
    return m_trayIcon && m_trayIcon->isVisible();
}

void DesktopIntegration::setVisible(bool visible)
{
    if (!m_trayIcon || (m_trayIcon->isVisible() == visible))
        return;
    qCInfo(lcUi) << "Tray icon visibility ->" << visible;
    m_trayIcon->setVisible(visible);
    emit visibleChanged();
}

bool DesktopIntegration::isNotificationsEnabled() const
{
    return m_notificationsEnabled;
}

void DesktopIntegration::setNotificationsEnabled(bool enabled)
{
    if (m_notificationsEnabled == enabled)
        return;
    m_notificationsEnabled = enabled;
    qCInfo(lcUi) << "Desktop notifications ->" << enabled;
#ifdef QBT_HAS_PREFERENCES
    Preferences::instance()->setValue(kNotificationsKey, enabled);
    Preferences::instance()->apply();
#endif
    emit notificationsEnabledChanged();
}

QString DesktopIntegration::toolTip() const
{
    return m_toolTip;
}

void DesktopIntegration::setToolTip(const QString &toolTip)
{
    if (m_toolTip == toolTip)
        return;
    m_toolTip = toolTip;
    if (m_trayIcon)
        m_trayIcon->setToolTip(toolTip.isEmpty() ? u"qBittorrent"_qs : toolTip);
    qCDebug(lcUi) << "Tray tooltip updated";
    emit toolTipChanged();
}

QVariantList DesktopIntegration::availableEditors() const
{
    return m_availableEditors;
}

QString DesktopIntegration::selectedEditor() const
{
    return m_selectedEditor;
}

void DesktopIntegration::setSelectedEditor(const QString &editorId)
{
    QString resolved = editorId.trimmed();
    bool known = false;
    for (const QVariant &value : m_availableEditors)
    {
        if (value.toMap().value(u"id"_qs).toString() == resolved)
        {
            known = true;
            break;
        }
    }
    if (!known)
        resolved.clear();
    if (m_selectedEditor == resolved)
        return;
    m_selectedEditor = resolved;
#ifdef QBT_HAS_PREFERENCES
    Preferences::instance()->setValue(kSelectedEditorKey, resolved);
    Preferences::instance()->apply();
#endif
    emit selectedEditorChanged();
}

QString DesktopIntegration::customEditorPath() const
{
    return m_customEditorPath;
}

void DesktopIntegration::setCustomEditorPath(const QString &path)
{
    const QUrl url(path.trimmed());
    const QString normalized = QDir::toNativeSeparators(url.isLocalFile()
        ? url.toLocalFile() : path.trimmed());
    if (m_customEditorPath == normalized)
        return;
    m_customEditorPath = normalized;
#ifdef QBT_HAS_PREFERENCES
    Preferences::instance()->setValue(kCustomEditorKey, normalized);
    Preferences::instance()->apply();
#endif
    refreshEditors();
}

bool DesktopIntegration::externalEditorAvailable() const
{
    return !m_availableEditors.isEmpty();
}

QString DesktopIntegration::findWellKnownEditor(const QString &id)
{
#ifdef Q_OS_WIN
    // A PATH lookup misses every VS Code installed without the "add to PATH"
    // option, which is the default for the user-scope installer, and misses
    // Insiders and portable builds entirely. Check where they actually land.
    static const QHash<QString, QStringList> relativePaths {
        {u"vscode"_qs, {
            uR"(Programs\Microsoft VS Code\Code.exe)"_qs,
            uR"(Programs\Microsoft VS Code Insiders\Code - Insiders.exe)"_qs}},
        {u"vscodium"_qs, {uR"(Programs\VSCodium\VSCodium.exe)"_qs}},
        {u"cursor"_qs, {uR"(Programs\cursor\Cursor.exe)"_qs}}
    };

    const auto it = relativePaths.constFind(id);
    if (it == relativePaths.cend())
        return {};

    const QStringList roots {
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation),
        qEnvironmentVariable("LOCALAPPDATA"),
        qEnvironmentVariable("ProgramFiles"),
        qEnvironmentVariable("ProgramFiles(x86)")
    };

    for (const QString &root : roots)
    {
        if (root.isEmpty())
            continue;
        for (const QString &relative : it.value())
        {
            const QString candidate = QDir(root).absoluteFilePath(relative);
            if (QFileInfo(candidate).isExecutable())
                return QDir::toNativeSeparators(candidate);
        }
    }
#else
    Q_UNUSED(id)
#endif
    return {};
}

void DesktopIntegration::refreshEditors()
{
    struct Candidate { const char *id; const char *name; const char *binary; };
    static constexpr Candidate candidates[] = {
        {"vscode", "Visual Studio Code", "code"},
        {"vscodium", "VSCodium", "codium"},
        {"cursor", "Cursor", "cursor"},
        {"sublime", "Sublime Text", "subl"},
        {"notepadpp", "Notepad++", "notepad++"},
        {"notepad", "Notepad", "notepad"}
    };

    QVariantList editors;
    for (const Candidate &candidate : candidates)
    {
        QString executable = QStandardPaths::findExecutable(QString::fromLatin1(candidate.binary));
        if (executable.isEmpty())
            executable = findWellKnownEditor(QString::fromLatin1(candidate.id));
        if (executable.isEmpty())
            continue;
        editors.append(QVariantMap {{u"id"_qs, QString::fromLatin1(candidate.id)},
            {u"name"_qs, QString::fromLatin1(candidate.name)}, {u"path"_qs, executable}});
    }
    if (QFileInfo(m_customEditorPath).isExecutable())
    {
        editors.append(QVariantMap {{u"id"_qs, u"custom"_qs}, {u"name"_qs, tr("Custom editor")},
            {u"path"_qs, m_customEditorPath}});
    }

    m_availableEditors = editors;
    bool selectedExists = false;
    for (const QVariant &value : m_availableEditors)
        selectedExists = selectedExists || (value.toMap().value(u"id"_qs).toString() == m_selectedEditor);
    if (!selectedExists)
        m_selectedEditor = m_availableEditors.isEmpty() ? QString() : m_availableEditors.first().toMap().value(u"id"_qs).toString();
    emit availableEditorsChanged();
    emit selectedEditorChanged();
}

bool DesktopIntegration::openInExternalEditor(const QString &path)
{
    QString localPath = path.trimmed();
    const QUrl asUrl(localPath);
    if (asUrl.isLocalFile())
        localPath = asUrl.toLocalFile();
    const QFileInfo target(localPath);
    if (!target.exists())
    {
        emit editorLaunchFinished(false, tr("The selected file or folder does not exist: %1").arg(localPath));
        return false;
    }

    QVariantMap editor;
    for (const QVariant &value : m_availableEditors)
    {
        const QVariantMap candidate = value.toMap();
        if (candidate.value(u"id"_qs).toString() == m_selectedEditor)
        {
            editor = candidate;
            break;
        }
    }
    if (editor.isEmpty())
    {
        emit editorLaunchFinished(false, tr("No external editor is configured. Choose one in Settings."));
        return false;
    }
    if (target.isDir() && editor.value(u"id"_qs).toString() == u"notepad"_qs)
    {
        emit editorLaunchFinished(false, tr("Notepad cannot open a project folder. Choose a project-capable editor."));
        return false;
    }

    const QString executable = editor.value(u"path"_qs).toString();
    const bool started = QProcess::startDetached(executable, {QDir::toNativeSeparators(target.absoluteFilePath())});
    emit editorLaunchFinished(started,
        started ? tr("Opened %1 in %2.").arg(target.fileName(), editor.value(u"name"_qs).toString())
                : tr("Could not start %1. Check the configured executable.").arg(editor.value(u"name"_qs).toString()));
    return started;
}

void DesktopIntegration::showNotification(const QString &title, const QString &message) const
{
    if (!m_notificationsEnabled)
    {
        qCDebug(lcUi) << "Notification suppressed (disabled):" << title;
        return;
    }
    if (!m_trayIcon)
    {
        qCWarning(lcUi) << "Cannot show notification, no tray:" << title << '-' << message;
        return;
    }
    qCInfo(lcUi) << "Showing notification:" << title;
    m_trayIcon->showMessage(title, message, QSystemTrayIcon::Information, 5000);
}
