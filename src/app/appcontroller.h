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

class QQmlEngine;
class QJSEngine;

/**
 * @brief Top-level UI action controller (a shared QML singleton).
 *
 * Exposes the window-shell verbs that don't belong to any single feature:
 * quitting, locking/unlocking the UI, minimizing to tray, checking for program
 * updates, and pasting a magnet/URL from the clipboard. It is deliberately thin:
 * heavier flows (the actual add-torrent pipeline) are delegated to feature
 * controllers via signals so this class stays decoupled.
 *
 * Accessed from QML by name: `AppController.exit()`, `AppController.locked`, …
 */
class AppController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    /// Whether the UI is currently locked behind the unlock password.
    Q_PROPERTY(bool locked READ isLocked NOTIFY lockedChanged)
    /// Whether a UI-lock password has been configured at all.
    Q_PROPERTY(bool lockPasswordSet READ isLockPasswordSet NOTIFY lockedChanged)

public:
    ~AppController() override;

    /// QML singleton factory — returns the app-owned instance (never a new one).
    static AppController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    [[nodiscard]] bool isLocked() const;
    [[nodiscard]] bool isLockPasswordSet() const;

    // --- User actions (invoked from QML) -------------------------------------

    /// Quit the whole application (honors the "confirm on exit" preference by
    /// emitting confirmExitRequested() when appropriate; force==true skips it).
    Q_INVOKABLE void exit(bool force = false);

    /// Hide the main window to the system tray (if a tray is available).
    Q_INVOKABLE void minimizeToTray();

    /// Bring the main window back to the foreground.
    Q_INVOKABLE void showMainWindow();

    /// Toggle main-window visibility (used by the tray double-click).
    Q_INVOKABLE void toggleMainWindow();

    /// Lock the UI. Requires that a lock password has been configured.
    Q_INVOKABLE void lock();

    /// Attempt to unlock with @p password. Returns true on success.
    Q_INVOKABLE bool unlock(const QString &password);

    /// Set (or, with an empty string, clear) the UI-lock password.
    Q_INVOKABLE void setLockPassword(const QString &password);

    /// Kick off the asynchronous Squirrel check/download/stage pipeline.
    Q_INVOKABLE void checkForUpdates();

    /// Read the clipboard; if it contains a magnet/URL/info-hash, forward it to
    /// the add-torrent pipeline via addTorrentRequested().
    Q_INVOKABLE void pasteAdd();

    /// Forward an arbitrary add source (path/magnet/URL) to the add pipeline.
    Q_INVOKABLE void addTorrentFromSource(const QString &source);

    /// Save the rendered main Qt Quick window to a PNG. This is used by the
    /// repository's deterministic documentation-capture mode.
    Q_INVOKABLE bool captureMainWindow(const QString &filePath) const;

    /// Handle an activation payload forwarded by a secondary instance.
    void handleActivationRequest(const QString &payload);

signals:
    void lockedChanged();

    /// The shell should ask the user to confirm quitting.
    void confirmExitRequested();
    /// Request to show/hide/toggle the main window (handled by Main.qml).
    void showMainWindowRequested();
    void hideMainWindowRequested();
    void toggleMainWindowRequested();

    /// A torrent add was requested from clipboard / another instance / CLI.
    void addTorrentRequested(const QString &source);

    /// Non-blocking user feedback (shown via the Snackbar / tray).
    void notify(const QString &message);

private:
    friend class Application;

    // Application owns the single instance. Keeping construction private makes
    // qmltyperegistrar select create() instead of silently constructing a
    // second controller (and splitting shell state between two objects).
    explicit AppController(QObject *parent = nullptr);

    [[nodiscard]] static QString storedPasswordHash();

    bool m_locked = false;
};
