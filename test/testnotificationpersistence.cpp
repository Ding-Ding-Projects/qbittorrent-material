/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QVector>

#include "base/path.h"
#include "base/preferences.h"
#include "base/profile.h"
#include "base/settingsstorage.h"
#include "quick/controllers/notificationcontroller.h"

namespace
{
    constexpr auto kHistoryKey = "GUI/Notifications/HistoryV1";

    [[nodiscard]] int rowForId(const NotificationController *controller, const QString &id)
    {
        for (int row = 0; row < controller->rowCount(); ++row)
        {
            if (controller->data(controller->index(row), NotificationController::IdRole).toString() == id)
                return row;
        }
        return -1;
    }

    [[nodiscard]] bool snapshotContains(const QVariantList &entries, const QString &id)
    {
        for (const QVariant &entry : entries)
        {
            if (entry.toMap().value(QStringLiteral("notificationId")).toString() == id)
                return true;
        }
        return false;
    }

    [[nodiscard]] QJsonObject persistedEntry(const QJsonArray &entries, const QString &id)
    {
        for (const QJsonValue &value : entries)
        {
            const QJsonObject entry = value.toObject();
            if (entry.value(QStringLiteral("id")).toString() == id)
                return entry;
        }
        return {};
    }
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("testnotificationpersistence"));

    QTemporaryDir temporaryRoot;
    if (!temporaryRoot.isValid())
    {
        qCritical() << "Could not create the notification-persistence test directory";
        return 1;
    }

    const Path profileRoot(temporaryRoot.path());
    const QString configurationName = QStringLiteral("notification-persistence");
    const auto initializeProfile = [&profileRoot, &configurationName]()
    {
        Profile::initInstance(profileRoot, configurationName, false);
        SettingsStorage::initInstance();
        Preferences::initInstance();
    };
    const auto freeProfile = []()
    {
        Preferences::freeInstance();
        SettingsStorage::freeInstance();
        Profile::freeInstance();
    };

    int failures = 0;
    const auto expect = [&failures](const bool condition, const QString &message)
    {
        if (condition)
            return;
        ++failures;
        qCritical().noquote() << "FAIL:" << message;
    };

    const QString transientId = QStringLiteral("transient-undo");
    const QString warningId = QStringLiteral("persistent-warning");
    const QString timestamp = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    initializeProfile();
    const QJsonArray seededHistory {
        QJsonObject {
            {QStringLiteral("id"), transientId},
            {QStringLiteral("title"), QStringLiteral("Restart regression")},
            {QStringLiteral("body"), QStringLiteral("Transient undo action")},
            {QStringLiteral("severity"), QStringLiteral("info")},
            {QStringLiteral("time"), timestamp},
            {QStringLiteral("read"), false},
            {QStringLiteral("dismissed"), false},
            {QStringLiteral("actionLabel"), QStringLiteral("Undo")},
            {QStringLiteral("actionId"), QStringLiteral("journal-undo:stale")}
        },
        QJsonObject {
            {QStringLiteral("id"), warningId},
            {QStringLiteral("title"), QStringLiteral("Restart regression")},
            {QStringLiteral("body"), QStringLiteral("Persistent warning")},
            {QStringLiteral("severity"), QStringLiteral("warning")},
            {QStringLiteral("time"), timestamp},
            {QStringLiteral("read"), false},
            {QStringLiteral("dismissed"), false},
            {QStringLiteral("actionLabel"), QString()},
            {QStringLiteral("actionId"), QString()}
        }
    };
    Preferences::instance()->setValue(QString::fromLatin1(kHistoryKey),
        QString::fromUtf8(QJsonDocument(seededHistory).toJson(QJsonDocument::Compact)));
    Preferences::instance()->apply();

    // Recreate the normal profile/settings chain before the singleton
    // controller is first constructed, mirroring a fresh application launch.
    freeProfile();
    initializeProfile();

    NotificationController *controller = NotificationController::instance();
    QVector<QString> requestedActions;
    QObject::connect(controller, &NotificationController::actionRequested,
        &application, [&requestedActions](const QString &actionId, const QString &)
        {
            requestedActions.append(actionId);
        });

    expect(controller->count() == 2, QStringLiteral("restart load must retain both history rows"));
    const int transientRow = rowForId(controller, transientId);
    const int warningRow = rowForId(controller, warningId);
    expect(transientRow >= 0 && warningRow >= 0,
        QStringLiteral("restart load must retain identifiable history rows"));
    if (transientRow >= 0)
    {
        const QModelIndex index = controller->index(transientRow);
        expect(controller->data(index, NotificationController::ReadRole).toBool(),
            QStringLiteral("restart must mark transient history read"));
        expect(controller->data(index, NotificationController::DismissedRole).toBool(),
            QStringLiteral("restart must end transient presentation"));
        expect(controller->data(index, NotificationController::ActionLabelRole).toString().isEmpty()
                && controller->data(index, NotificationController::ActionIdRole).toString().isEmpty(),
            QStringLiteral("restart must strip a stale journal undo affordance"));
    }
    if (warningRow >= 0)
    {
        const QModelIndex index = controller->index(warningRow);
        expect(!controller->data(index, NotificationController::DismissedRole).toBool(),
            QStringLiteral("restart must preserve persistent warning presentation"));
    }

    const QVariantList recoveryEntries = controller->activeEntries();
    expect(!snapshotContains(recoveryEntries, transientId),
        QStringLiteral("transient undo must not rehydrate into the corner host"));
    expect(snapshotContains(recoveryEntries, warningId),
        QStringLiteral("persistent warning must remain in the corner-host snapshot"));

    controller->activateAction(transientId);
    expect(requestedActions.isEmpty(),
        QStringLiteral("a restart-sanitized transient undo must not emit an action"));

    const QJsonDocument rewritten = QJsonDocument::fromJson(
        Preferences::instance()->value(QString::fromLatin1(kHistoryKey)).toString().toUtf8());
    expect(rewritten.isArray(), QStringLiteral("sanitized history must remain valid JSON"));
    const QJsonObject rewrittenTransient = persistedEntry(rewritten.array(), transientId);
    expect(rewrittenTransient.value(QStringLiteral("read")).toBool()
            && rewrittenTransient.value(QStringLiteral("dismissed")).toBool()
            && rewrittenTransient.value(QStringLiteral("actionLabel")).toString().isEmpty()
            && rewrittenTransient.value(QStringLiteral("actionId")).toString().isEmpty(),
        QStringLiteral("restart sanitization must be persisted for the next launch"));

    freeProfile();
    if (failures == 0)
        qInfo() << "Notification persistence restart regression passed";
    return (failures == 0) ? 0 : 1;
}
