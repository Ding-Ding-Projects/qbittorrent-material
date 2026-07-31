/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QString>
#include <QVector>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;

/**
 * Persistent, severity-aware notification history shared by every QML surface.
 *
 * Informational messages are still rendered by the non-blocking Snackbar host,
 * while this model keeps them reviewable after dismissal. Warning and error
 * presentation remains visible until the user dismisses it in QML.
 */
class NotificationController final : public QAbstractListModel
{
    Q_OBJECT
    QML_NAMED_ELEMENT(NotificationCenter)
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(NotificationController)

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)

public:
    enum Roles
    {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        BodyRole,
        SeverityRole,
        TimestampRole,
        TimeTextRole,
        ReadRole,
        DismissedRole,
        ActionLabelRole,
        ActionIdRole
    };

    static NotificationController *create(QQmlEngine *, QJSEngine *);
    static NotificationController *instance();

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] int count() const;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;
    [[nodiscard]] int unreadCount() const;

    Q_INVOKABLE QString notify(const QString &body, const QString &severity = QStringLiteral("info"),
        const QString &title = {}, const QString &actionLabel = {}, const QString &actionId = {});
    Q_INVOKABLE void markRead(const QString &id);
    Q_INVOKABLE void markAllRead();
    Q_INVOKABLE void dismiss(const QString &id);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE void activateAction(const QString &id);
    Q_INVOKABLE int matchingCount(const QString &query, bool regex,
        const QString &flags, const QString &scope) const;

signals:
    void countChanged();
    void unreadCountChanged();
    void notificationRaised(const QString &id, const QString &title, const QString &body,
        const QString &severity, const QString &actionLabel, const QString &actionId);
    void actionRequested(const QString &actionId, const QString &notificationId);

private:
    struct Entry
    {
        QString id;
        QString title;
        QString body;
        QString severity;
        QDateTime timestamp;
        bool read = false;
        bool dismissed = false;
        QString actionLabel;
        QString actionId;
    };

    NotificationController();
    [[nodiscard]] int indexOf(const QString &id) const;
    [[nodiscard]] static QString normalizedSeverity(const QString &severity);
    [[nodiscard]] QString defaultTitle(const QString &severity) const;
    void load();
    void persist() const;
    void updateUnreadCount();

    static NotificationController *s_instance;
    QVector<Entry> m_entries;
    int m_unreadCount = 0;
};
