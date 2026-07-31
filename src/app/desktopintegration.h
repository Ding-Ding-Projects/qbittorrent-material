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

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QIcon;
class QQmlEngine;
class QJSEngine;
class QSystemTrayIcon;

/**
 * @brief System-tray icon + desktop notifications bridge (shared QML singleton).
 *
 * Owns the process' @c QSystemTrayIcon and surfaces its lifecycle to QML:
 *   - `available` / `visible` — whether a tray exists and is shown;
 *   - `notificationsEnabled` — persisted balloon-notification toggle;
 *   - `showNotification(title, msg)` — native balloon / OS notification;
 *   - `activationRequested()` — the user activated the tray (show/hide window);
 *   - `contextMenuRequested()` — right-click; Main.qml pops the Material
 *     `SystemTrayMenu` at the cursor (we intentionally do NOT attach a native
 *     QMenu so the tray menu stays Material like the rest of the UI).
 *
 * The tray icon artwork follows ThemeManager's legacy
 * `Appearance/TrayIconStyle` setting (Normal / Monochrome).
 */
class DesktopIntegration : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ isAvailable CONSTANT)
    Q_PROPERTY(bool visible READ isVisible WRITE setVisible NOTIFY visibleChanged)
    Q_PROPERTY(bool notificationsEnabled READ isNotificationsEnabled
            WRITE setNotificationsEnabled NOTIFY notificationsEnabledChanged)
    Q_PROPERTY(QString toolTip READ toolTip WRITE setToolTip NOTIFY toolTipChanged)
    Q_PROPERTY(QVariantList availableEditors READ availableEditors NOTIFY availableEditorsChanged)
    Q_PROPERTY(QString selectedEditor READ selectedEditor WRITE setSelectedEditor NOTIFY selectedEditorChanged)
    Q_PROPERTY(QString customEditorPath READ customEditorPath WRITE setCustomEditorPath NOTIFY availableEditorsChanged)
    Q_PROPERTY(bool externalEditorAvailable READ externalEditorAvailable NOTIFY availableEditorsChanged)

public:
    ~DesktopIntegration() override;

    /// QML singleton factory — returns the app-owned instance.
    static DesktopIntegration *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    [[nodiscard]] bool isAvailable() const;

    [[nodiscard]] bool isVisible() const;
    void setVisible(bool visible);

    [[nodiscard]] bool isNotificationsEnabled() const;
    void setNotificationsEnabled(bool enabled);

    [[nodiscard]] QString toolTip() const;
    void setToolTip(const QString &toolTip);

    [[nodiscard]] QVariantList availableEditors() const;
    [[nodiscard]] QString selectedEditor() const;
    void setSelectedEditor(const QString &editorId);
    [[nodiscard]] QString customEditorPath() const;
    void setCustomEditorPath(const QString &path);
    [[nodiscard]] bool externalEditorAvailable() const;
    Q_INVOKABLE void refreshEditors();
    Q_INVOKABLE bool openInExternalEditor(const QString &path);

    /// Show a native desktop / tray notification (no-op if unavailable/disabled).
    Q_INVOKABLE void showNotification(const QString &title, const QString &message) const;

    /// Re-read the tray icon artwork after a theme / tray-style change.
    Q_INVOKABLE void refreshTrayIcon();

signals:
    void visibleChanged();
    void notificationsEnabledChanged();
    void toolTipChanged();

    /// The user activated the tray icon (single/double click) — toggle window.
    void activationRequested();
    /// The user right-clicked the tray — the shell should pop the Material menu.
    void contextMenuRequested();
    /// The user clicked a shown notification balloon.
    void notificationClicked();
    void availableEditorsChanged();
    void selectedEditorChanged();
    void editorLaunchFinished(bool success, const QString &message);

private:
    friend class Application;

    // Application owns the one desktop bridge. A private constructor forces
    // QML singleton registration through create(), avoiding a duplicate tray
    // icon and duplicate notification state.
    explicit DesktopIntegration(QObject *parent = nullptr);

    void createTrayIcon();
    [[nodiscard]] QIcon resolveTrayIcon() const;

    QSystemTrayIcon *m_trayIcon = nullptr;
    QString m_toolTip;
    bool m_notificationsEnabled = true;
    QVariantList m_availableEditors;
    QString m_selectedEditor;
    QString m_customEditorPath;
};
