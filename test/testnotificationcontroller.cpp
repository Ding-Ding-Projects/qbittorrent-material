/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QDebug>
#include <QPair>
#include <QString>
#include <QVariantMap>
#include <QVector>

#include "base/logging.h"
#include "quick/controllers/notificationcontroller.h"

// The focused regression compiles only the controller instead of dragging the
// entire engine into an opt-in non-GUI target. Supply the one category that the
// controller records to; production builds keep the central definition.
Q_LOGGING_CATEGORY(lcUi, "qbt.ui.notificationtest")

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("testnotificationcontroller"));

    NotificationController *controller = NotificationController::instance();
    controller->clearAll();

    QVector<QString> dismissedIds;
    QVector<QPair<QString, QString>> requestedActions;
    QVector<QPair<int, int>> removedRanges;
    int allDismissedCount = 0;
    int failures = 0;

    const auto expect = [&failures](const bool condition, const QString &message)
    {
        if (condition)
            return;
        ++failures;
        qCritical().noquote() << "FAIL:" << message;
    };

    QObject::connect(controller, &NotificationController::notificationDismissed,
        &application, [&dismissedIds](const QString &id) { dismissedIds.append(id); });
    QObject::connect(controller, &NotificationController::actionRequested,
        &application, [&requestedActions](const QString &actionId, const QString &notificationId)
        {
            requestedActions.append({actionId, notificationId});
        });
    QObject::connect(controller, &NotificationController::allDismissed,
        &application, [&allDismissedCount]() { ++allDismissedCount; });
    QObject::connect(controller, &QAbstractItemModel::rowsRemoved,
        &application, [&removedRanges](const QModelIndex &, const int first, const int last)
        {
            removedRanges.append({first, last});
        });

    QVector<QString> ids;
    ids.reserve(201);
    for (int number = 1; number <= 201; ++number)
    {
        const bool actionEntry = (number == 201);
        ids.append(controller->notify(
            QStringLiteral("Persistent notification %1").arg(number),
            (number % 2) ? QStringLiteral("warning") : QStringLiteral("error"),
            QStringLiteral("Regression %1").arg(number),
            actionEntry ? QStringLiteral("Undo") : QString(),
            actionEntry ? QStringLiteral("journal-undo:regression") : QString()));
    }

    expect(controller->count() == 200, QStringLiteral("history must retain exactly 200 rows"));
    expect(controller->rowCount() == 200, QStringLiteral("model row count must match history count"));
    expect(controller->activeCount() == 200, QStringLiteral("all retained warnings/errors must remain active"));
    expect(controller->unreadCount() == 200, QStringLiteral("all retained warnings/errors must remain unread"));
    expect(controller->activeEntries().size() == 200,
        QStringLiteral("active snapshot must contain every retained notification"));

    expect(removedRanges.size() == 1 && removedRanges.constFirst() == QPair<int, int>(200, 200),
        QStringLiteral("the 201st insert must evict only model row 200"));
    expect(dismissedIds.size() == 1 && dismissedIds.constFirst() == ids.constFirst(),
        QStringLiteral("active eviction must remove the stale corner-card id"));

    expect(controller->data(controller->index(0), NotificationController::IdRole).toString()
            == ids.constLast(),
        QStringLiteral("newest notification must remain model row 0"));
    expect(controller->data(controller->index(199), NotificationController::IdRole).toString()
            == ids.at(1),
        QStringLiteral("oldest retained notification must be notification 2"));

    const QVariantList active = controller->activeEntries();
    expect(active.constFirst().toMap().value(QStringLiteral("notificationId")).toString()
            == ids.at(1),
        QStringLiteral("active snapshot must be oldest-first"));
    expect(active.constLast().toMap().value(QStringLiteral("notificationId")).toString()
            == ids.constLast(),
        QStringLiteral("active snapshot must end with the newest entry"));

    const QString actionNotificationId = ids.constLast();
    controller->activateAction(actionNotificationId);
    expect(requestedActions.size() == 1
            && requestedActions.constFirst().first == QStringLiteral("journal-undo:regression")
            && requestedActions.constFirst().second == actionNotificationId,
        QStringLiteral("the retained notification action must route exactly once"));
    expect(controller->unreadCount() == 199,
        QStringLiteral("activating the action must mark only that notification read"));
    expect(controller->activeCount() == 200,
        QStringLiteral("activating an action must not dismiss its notification"));
    expect(controller->data(controller->index(0), NotificationController::ActionIdRole)
               .toString().isEmpty()
            && controller->data(controller->index(0), NotificationController::ActionLabelRole)
               .toString().isEmpty(),
        QStringLiteral("journal undo must be consumed before its handler runs"));

    controller->activateAction(actionNotificationId);
    expect(requestedActions.size() == 1,
        QStringLiteral("a consumed journal undo must reject repeated activation"));

    controller->dismiss(actionNotificationId);
    expect(dismissedIds.size() == 2 && dismissedIds.constLast() == actionNotificationId,
        QStringLiteral("individual dismissal must identify the retained card"));
    expect(controller->activeCount() == 199,
        QStringLiteral("individual dismissal must reduce the active count once"));
    expect(controller->unreadCount() == 199,
        QStringLiteral("dismissing the already-read action card must preserve unread count"));

    controller->dismiss(actionNotificationId);
    expect(dismissedIds.size() == 2,
        QStringLiteral("repeated individual dismissal must be a no-op"));

    controller->dismissAll();
    expect(allDismissedCount == 1, QStringLiteral("dismiss all must emit exactly once"));
    expect(controller->activeCount() == 0, QStringLiteral("dismiss all must clear active count"));
    expect(controller->unreadCount() == 0, QStringLiteral("dismiss all must mark retained history read"));
    expect(controller->activeEntries().isEmpty(),
        QStringLiteral("dismiss all must leave no active snapshot entries"));
    expect(controller->count() == 200 && controller->rowCount() == 200,
        QStringLiteral("dismiss all must retain the bounded history"));

    for (int row = 0; row < controller->rowCount(); ++row)
    {
        const QModelIndex modelIndex = controller->index(row);
        expect(controller->data(modelIndex, NotificationController::ReadRole).toBool(),
            QStringLiteral("retained row %1 must be read").arg(row));
        expect(controller->data(modelIndex, NotificationController::DismissedRole).toBool(),
            QStringLiteral("retained row %1 must be dismissed").arg(row));
    }

    // The corner host receives fresh transient notifications from its signal,
    // not from the persisted recovery snapshot. That keeps an Undo action from
    // gaining a new full timeout if the application is restarted.
    controller->clearAll();
    requestedActions.clear();
    const QString transientUndoId = controller->notify(
        QStringLiteral("Transient undo"), QStringLiteral("info"),
        QStringLiteral("Restart regression"), QStringLiteral("Undo"),
        QStringLiteral("journal-undo:transient"));
    const QString persistentWarningId = controller->notify(
        QStringLiteral("Persistent warning"), QStringLiteral("warning"),
        QStringLiteral("Restart regression"));
    const QString persistentErrorId = controller->notify(
        QStringLiteral("Persistent error"), QStringLiteral("error"),
        QStringLiteral("Restart regression"));

    const QVariantList recoveryEntries = controller->activeEntries();
    QVector<QString> recoveryIds;
    recoveryIds.reserve(recoveryEntries.size());
    for (const QVariant &entry : recoveryEntries)
        recoveryIds.append(entry.toMap().value(QStringLiteral("notificationId")).toString());
    expect(!recoveryIds.contains(transientUndoId),
        QStringLiteral("transient undo must not enter the persisted recovery snapshot"));
    expect(recoveryIds.contains(persistentWarningId) && recoveryIds.contains(persistentErrorId),
        QStringLiteral("persistent warning and error cards must remain restorable"));
    expect(controller->count() == 3 && controller->activeCount() == 3,
        QStringLiteral("excluding a transient recovery card must retain its live history row"));

    controller->activateAction(transientUndoId);
    expect(requestedActions.size() == 1
            && requestedActions.constFirst().first == QStringLiteral("journal-undo:transient"),
        QStringLiteral("a fresh transient undo remains actionable before restart sanitization"));

    if (failures == 0)
        qInfo() << "Notification controller 201-entry regression passed";
    return (failures == 0) ? 0 : 1;
}
