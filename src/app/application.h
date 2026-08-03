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

#include <QApplication>
#include <QPointer>
#include <QString>

class QLocalServer;
class QQmlApplicationEngine;
class QTranslator;

class AppController;
class DesktopIntegration;

/**
 * @brief The one application object: engine bootstrap + QML host + lifetime owner.
 *
 * ::Application derives from @c QApplication (not @c QGuiApplication) because the
 * app needs a @c QSystemTrayIcon and the native OS file pickers — even though
 * every visible surface is Qt Quick / Material. It:
 *   - initializes the engine singletons (Preferences, BitTorrent::Session, …);
 *   - installs the runtime i18n translator (English / Cantonese / Bilingual)
 *     *before* the QML engine loads @c Main.qml (see CONTRACTS §2.3);
 *   - owns the app-scoped QML singletons that need a shared instance
 *     (::AppController, ::DesktopIntegration) and hands them out via their
 *     @c create() factories;
 *   - loads the @c qBittorrent QML module's @c Main entry point;
 *   - provides a single-instance guard.
 *
 * A process-wide accessor ::Application::instance() lets the QML singleton
 * factories reach the app-owned instances.
 */
class Application final : public QApplication
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(Application)

public:
    Application(int &argc, char **argv);
    ~Application() override;

    /// The running ::Application (nullptr before construction / after teardown).
    static Application *instance();

    /// Register QML singletons, init the engine, load Main.qml, run the event
    /// loop. Returns the loop's exit code. Call exactly once from main().
    [[nodiscard]] int run();

    /// True when this process acquired the single-instance lock (the primary).
    [[nodiscard]] bool isPrimaryInstance() const;

    /// Forward this process' request (command-line/activation) to the primary
    /// instance, then this process is expected to exit.
    [[nodiscard]] bool notifyPrimaryInstance();

    /// Shared, app-owned QML singleton instances.
    [[nodiscard]] AppController *appController() const;
    [[nodiscard]] DesktopIntegration *desktopIntegration() const;

    /// The underlying QML engine (valid only after run() has begun).
    [[nodiscard]] QQmlApplicationEngine *qmlEngine() const;

    /// The one process-wide runtime translator installed before QML loads.
    /// I18n adopts this instance instead of installing a competing translator.
    [[nodiscard]] QTranslator *runtimeTranslator() const;

    /// Wall-clock launch time (seconds since epoch), for uptime/statistics.
    [[nodiscard]] qint64 launchTimeSecsSinceEpoch() const;

signals:
    /// Emitted once, right before the engine is torn down, so bridge objects can
    /// flush state. Fired from cleanup().
    void aboutToShutDown();

private:
    void setupTranslation();
    void initEngine();
    void registerContext();
    void loadMainQml();
    void setupSingleInstance();
    void cleanup();

    QQmlApplicationEngine *m_engine = nullptr;
    QTranslator *m_translator = nullptr;  ///< The sole process-wide translator.

    QPointer<AppController> m_appController;
    QPointer<DesktopIntegration> m_desktopIntegration;

    QLocalServer *m_instanceServer = nullptr;
    QString m_instanceId;
    bool m_isPrimaryInstance = false;
    bool m_cleanupDone = false;

    qint64 m_launchTimeSecsSinceEpoch = -1;
};
