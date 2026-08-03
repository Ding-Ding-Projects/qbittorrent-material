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

#include <QQuickStyle>
#include <QString>

#include "base/logging.h"
#include "app/application.h"

using namespace Qt::StringLiterals;

int main(int argc, char *argv[])
{
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

        // --- 3. Single-instance guard. ---------------------------------------
        // If another primary instance already owns the lock, forward our
        // command-line (e.g. a magnet passed by the OS) to it and bail out.
        if (!app.isPrimaryInstance())
        {
            qCInfo(lcApp) << "Another instance is already running; forwarding request and exiting";
            return app.notifyPrimaryInstance() ? 0 : 1;
        }

        // --- 4. Boot the UI + event loop. ------------------------------------
        exitCode = app.run();
        qCInfo(lcApp) << "Event loop returned; exit code =" << exitCode;
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
