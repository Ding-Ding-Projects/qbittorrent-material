/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <optional>

#include <QByteArray>
#include <QString>
#include <QStringList>

#include "squirrelreleasevalidator.h"

namespace UpdateRecovery
{
struct Baseline
{
    QString squirrelRoot;
    QString currentVersion;
    QString relativeExecutable;
    QString currentPackagePath;
    QByteArray currentManifest;
    SquirrelReleaseValidator::ReleaseEntry currentRelease;
};

/** Cache the exact previous full package before Squirrel replaces local RELEASES. */
[[nodiscard]] bool prepareBaseline(const Baseline &baseline, QString *error);

/** Persist a launch-health transaction and its already-filtered restart arguments. */
[[nodiscard]] bool createRestartTransaction(const QString &squirrelRoot,
        const QString &fromVersion, const QString &targetVersion,
        const QString &relativeExecutable, const QStringList &restartArguments,
        QString *token, QString *error);

/** Tell a detached watchdog to stop when Update.exe itself could not be launched. */
void cancelRestartTransaction(const QString &squirrelRoot, const QString &token);

/** Preserve profile-selection arguments across a restart, making profile roots absolute. */
[[nodiscard]] QStringList preservedLaunchArguments(const QStringList &arguments);

/** Run the old-binary watchdog before QApplication is constructed. */
[[nodiscard]] std::optional<int> runWatchdogIfRequested(
        const QStringList &arguments, const QString &executablePath);

[[nodiscard]] QString healthToken(const QStringList &arguments);

/** First acknowledgement: the target binary owns the primary-instance lock. */
[[nodiscard]] bool acknowledgeStarted(const QStringList &arguments, QString *error);

/** Final acknowledgement: Main.qml exists and the event loop completed a turn. */
[[nodiscard]] bool acknowledgeReady(const QStringList &arguments, QString *error);

/** Consume one recovery outcome so the restored build can explain what happened. */
[[nodiscard]] bool takeRecoveryNotice(const QString &squirrelRoot,
        QString *failedVersion, QString *message, QString *error);
}
