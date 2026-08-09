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

/**
 * @file main.cpp
 * @brief Process entry point.
 *
 * Responsibilities, in order:
 *   1. Force the Qt Quick Controls **Material** style (the whole UI is Material).
 *   2. Install the dual-sink categorized logging message handler.
 *   3. Construct the single ::Application (a QApplication so the tray + native
 *      OS file pickers work), which owns engine init + the QML module.
 *   4. Honor the single-instance guard, then hand off to the event loop.
 *
 * Everything is logged aggressively so a startup failure is diagnosable from
 * the very first line of the rotating log file.
 */

#include <QCoreApplication>
#include <QFileInfo>
#include <QQuickStyle>
#include <QString>
#include <QStringList>

#include <optional>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#endif

#include "base/logging.h"
#include "app/application.h"
#include "app/squirrellifecycle.h"
#include "app/updaterecovery.h"

using namespace Qt::StringLiterals;

namespace
{
QStringList startupArguments(const int argc, char *argv[])
{
#ifdef Q_OS_WIN
    // `main` receives the ANSI CRT argv on Windows. The watchdog needs the
    // canonical executable path before QApplication exists, so obtain the
    // original UTF-16 command line rather than corrupting a non-ASCII install
    // or profile path through the active code page.
    Q_UNUSED(argc)
    Q_UNUSED(argv)
    int wideArgumentCount = 0;
    wchar_t **const wideArguments = CommandLineToArgvW(GetCommandLineW(), &wideArgumentCount);
    if (wideArguments)
    {
        QStringList arguments;
        arguments.reserve(wideArgumentCount);
        for (int index = 0; index < wideArgumentCount; ++index)
            arguments << QString::fromWCharArray(wideArguments[index]);
        LocalFree(wideArguments);
        return arguments;
    }
#endif

    QStringList arguments;
    arguments.reserve(argc);
    for (int index = 0; index < argc; ++index)
        arguments << QString::fromLocal8Bit(argv[index]);
    return arguments;
}
}

int main(int argc, char *argv[])
{
    // The detached rollback watchdog is the old app binary, not a normal app
    // launch. It must run before QApplication creates a single-instance socket
    // or initializes any UI state. Collect startup arguments through the
    // platform's wide-aware pre-QCoreApplication path.
    const QStringList earlyArguments = startupArguments(argc, argv);
    const QString earlyExecutable = earlyArguments.isEmpty()
            ? QString() : QFileInfo(earlyArguments.constFirst()).absoluteFilePath();
    if (const std::optional<int> recoveryExit =
                UpdateRecovery::runWatchdogIfRequested(earlyArguments, earlyExecutable))
    {
        return *recoveryExit;
    }

    // --- 0. Style MUST be chosen before any QML/Quick object is created. ------
    // Do it even before the QApplication so the Material style is locked in.
    QQuickStyle::setStyle(u"Material"_qs);

    // --- 1. Bring up logging as early as possible. ----------------------------
    Logging::installMessageHandler();
    qCInfo(lcApp) << "qBittorrent (Material) starting up; Qt Quick style = Material";
    qCDebug(lcApp) << "Command line argc =" << argc;

    int exitCode = 0;
    try
    {
        // --- 2. Construct the application (engine init happens inside). --------
        Application app(argc, argv);

        // Squirrel lifecycle hooks must finish quickly, before engine/QML boot.
        // The normal --squirrel-firstrun path intentionally continues below.
        if (const std::optional<int> lifecycleExit =
                SquirrelLifecycle::handle(QCoreApplication::arguments()))
        {
            qCInfo(lcApp) << "Squirrel lifecycle complete; exit code ="
                          << *lifecycleExit;
            return *lifecycleExit;
        }

        // --- 3. Single-instance guard. ---------------------------------------
        // If another primary instance already owns the lock, forward our
        // command-line (e.g. a magnet passed by the OS) to it and bail out.
        if (!app.isPrimaryInstance())
        {
            qCInfo(lcApp) << "Another instance is already running; forwarding request and exiting";
            return app.notifyPrimaryInstance() ? 0 : 1;
        }

        // A restarted target confirms ownership only after it holds the
        // single-instance lock. The old watchdog can then distinguish a real
        // target start from a failed Update.exe handoff.
        QString recoveryError;
        if (!UpdateRecovery::acknowledgeStarted(QCoreApplication::arguments(), &recoveryError))
        {
            qCCritical(lcApp).noquote()
                    << "Update recovery start acknowledgement failed:" << recoveryError;
            return 1;
        }
    }
    catch (const std::exception &err)
    {
        qCCritical(lcApp) << "Fatal unhandled exception during startup:" << err.what();
        exitCode = 1;
    }
    catch (...)
    {
        qCCritical(lcApp) << "Fatal unhandled non-standard exception during startup";
        exitCode = 1;
    }

    qCInfo(lcApp) << "Shutdown complete; flushing logs. Goodbye.";
    Logging::removeMessageHandler();
    return exitCode;
}
