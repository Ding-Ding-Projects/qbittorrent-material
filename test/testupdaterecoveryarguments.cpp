/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

#include "app/updaterecovery.h"

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);

    QTemporaryDir temporaryRoot;
    if (!temporaryRoot.isValid())
    {
        qCritical() << "Could not create the update-recovery argument test directory";
        return 1;
    }

    const QString originalWorkingDirectory = QDir::currentPath();
    const QString launchDirectory =
            temporaryRoot.filePath(QStringLiteral("launch directory with spaces"));
    if (!QDir().mkpath(launchDirectory) || !QDir::setCurrent(launchDirectory))
    {
        qCritical().noquote() << "Could not select test launch directory" << launchDirectory;
        return 1;
    }

    int failures = 0;
    const auto expect = [&failures](const bool condition, const QString &message)
    {
        if (!condition)
        {
            ++failures;
            qCritical().noquote() << "FAIL:" << message;
        }
    };

    const QString separatedRelativeRoot = QStringLiteral("profiles/../profiles/Separate Profile");
    const QString inlineRelativeRoot = QStringLiteral("profiles/Inline Profile");
    const QString expectedSeparatedRoot =
            QDir::cleanPath(QDir(launchDirectory).absoluteFilePath(separatedRelativeRoot));
    const QString expectedInlineRoot =
            QDir::cleanPath(QDir(launchDirectory).absoluteFilePath(inlineRelativeRoot));
    const QStringList originalArguments{QStringLiteral("qbittorrent.exe"),
            QStringLiteral("--profile-root"), separatedRelativeRoot,
            QStringLiteral("--configuration"), QStringLiteral("custom-config"),
            QStringLiteral("--profile-root=") + inlineRelativeRoot,
            QStringLiteral("--configuration=inline-config"), QStringLiteral("--unrelated-option"),
            QStringLiteral("ignored")};
    const QStringList expectedArguments{QStringLiteral("--profile-root"), expectedSeparatedRoot,
            QStringLiteral("--configuration"), QStringLiteral("custom-config"),
            QStringLiteral("--profile-root=") + expectedInlineRoot,
            QStringLiteral("--configuration=inline-config")};

    const QStringList preserved = UpdateRecovery::preservedLaunchArguments(originalArguments);
    expect(preserved == expectedArguments,
            QStringLiteral("separate and inline relative profile roots must become absolute "
                           "without changing configuration arguments"));
    expect(UpdateRecovery::preservedLaunchArguments(
                   QStringList{QStringLiteral("qbittorrent.exe")} + preserved) == preserved,
            QStringLiteral("the canonical restart arguments must remain stable when persisted for "
                           "rollback"));

    const QString squirrelRoot = temporaryRoot.filePath(QStringLiteral("Squirrel root"));
    const QString recoveryDirectory =
            QDir(squirrelRoot).filePath(QStringLiteral("qbt-update-recovery"));
    const QString targetDirectory = QDir(squirrelRoot).filePath(QStringLiteral("app-1.2.4"));
    const QString targetExecutable = QDir(targetDirectory).filePath(QStringLiteral("qbittorrent.exe"));
    if (!QDir().mkpath(recoveryDirectory) || !QDir().mkpath(targetDirectory))
    {
        qCritical() << "Could not create the update-recovery transaction layout";
        QDir::setCurrent(originalWorkingDirectory);
        return 1;
    }

    QFile targetFile(targetExecutable);
    QFile baselineFile(QDir(recoveryDirectory).filePath(QStringLiteral("baseline.json")));
    QJsonObject baseline;
    baseline.insert(QStringLiteral("version"), QStringLiteral("1.2.3"));
    const bool targetWritten = targetFile.open(QIODevice::WriteOnly)
            && (targetFile.write("stub") == 4);
    targetFile.close();
    const bool baselineWritten = baselineFile.open(QIODevice::WriteOnly)
            && (baselineFile.write(QJsonDocument(baseline).toJson(QJsonDocument::Compact)) > 0);
    baselineFile.close();
    if (!targetWritten || !baselineWritten)
    {
        qCritical() << "Could not prepare the update-recovery transaction baseline";
        QDir::setCurrent(originalWorkingDirectory);
        return 1;
    }

    QString token;
    QString transactionError;
    expect(UpdateRecovery::createRestartTransaction(squirrelRoot, QStringLiteral("1.2.3"),
                   QStringLiteral("1.2.4"), QStringLiteral("qbittorrent.exe"), preserved, &token,
                   &transactionError),
            QStringLiteral("the rollback transaction must accept the canonical restart arguments: %1")
                    .arg(transactionError));

    QFile transactionFile(QDir(recoveryDirectory).filePath(QStringLiteral("transaction.json")));
    if (!transactionFile.open(QIODevice::ReadOnly))
    {
        qCritical() << "Could not read the update-recovery transaction";
        QDir::setCurrent(originalWorkingDirectory);
        return 1;
    }
    const QJsonDocument transaction = QJsonDocument::fromJson(transactionFile.readAll());
    QStringList rollbackArguments;
    for (const QJsonValue &value : transaction.object().value(QStringLiteral("arguments")).toArray())
        rollbackArguments << value.toString();
    expect(rollbackArguments == preserved,
            QStringLiteral("the rollback transaction must retain the same canonical profile roots "
                           "as the target restart"));

    QDir::setCurrent(originalWorkingDirectory);
    if (failures == 0)
        qInfo() << "Update recovery relative profile-root regression passed";
    return (failures == 0) ? 0 : 1;
}
