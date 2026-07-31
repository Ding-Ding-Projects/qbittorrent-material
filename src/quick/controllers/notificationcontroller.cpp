/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "notificationcontroller.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QRegularExpression>
#include <QUuid>

#include "base/logging.h"

#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

using namespace Qt::Literals::StringLiterals;

namespace
{
    constexpr int kMaximumEntries = 200;
    constexpr int kMaximumTitleLength = 160;
    constexpr int kMaximumBodyLength = 4096;
    const QString kHistoryKey = u"GUI/Notifications/HistoryV1"_s;
    const QString kRegexSafetyPrefix = u"(*LIMIT_MATCH=100000)(*LIMIT_DEPTH=1000)(?:"_s;
}

NotificationController *NotificationController::s_instance = nullptr;

NotificationController *NotificationController::create(QQmlEngine *, QJSEngine *)
{
    return instance();
}

NotificationController *NotificationController::instance()
{
    if (!s_instance)
        s_instance = new NotificationController;
    return s_instance;
}

NotificationController::NotificationController()
{
    load();
}

int NotificationController::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_entries.size();
}

int NotificationController::count() const
{
    return m_entries.size();
}

QVariant NotificationController::data(const QModelIndex &index, const int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};

    const Entry &entry = m_entries.at(index.row());
    switch (role)
    {
    case IdRole: return entry.id;
    case TitleRole: return entry.title;
    case BodyRole: return entry.body;
    case SeverityRole: return entry.severity;
    case TimestampRole: return entry.timestamp;
    case TimeTextRole: return QLocale().toString(entry.timestamp.toLocalTime(), QLocale::ShortFormat);
    case ReadRole: return entry.read;
    case DismissedRole: return entry.dismissed;
    case ActionLabelRole: return entry.actionLabel;
    case ActionIdRole: return entry.actionId;
    default: return {};
    }
}

QHash<int, QByteArray> NotificationController::roleNames() const
{
    return {
        {IdRole, "notificationId"}, {TitleRole, "title"}, {BodyRole, "body"},
        {SeverityRole, "severity"}, {TimestampRole, "timestamp"}, {TimeTextRole, "timeText"},
        {ReadRole, "isRead"}, {DismissedRole, "dismissed"},
        {ActionLabelRole, "actionLabel"}, {ActionIdRole, "actionId"}
    };
}

int NotificationController::unreadCount() const
{
    return m_unreadCount;
}

QString NotificationController::notify(const QString &body, const QString &severity,
    const QString &title, const QString &actionLabel, const QString &actionId)
{
    const QString safeBody = body.trimmed().left(kMaximumBodyLength);
    if (safeBody.isEmpty())
        return {};

    Entry entry;
    entry.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    entry.severity = normalizedSeverity(severity);
    entry.title = title.trimmed().left(kMaximumTitleLength);
    if (entry.title.isEmpty())
        entry.title = defaultTitle(entry.severity);
    entry.body = safeBody;
    entry.timestamp = QDateTime::currentDateTimeUtc();
    entry.actionLabel = actionLabel.trimmed().left(kMaximumTitleLength);
    entry.actionId = actionId.trimmed().left(kMaximumTitleLength);

    beginInsertRows({}, 0, 0);
    m_entries.prepend(entry);
    endInsertRows();
    if (m_entries.size() > kMaximumEntries)
    {
        beginRemoveRows({}, kMaximumEntries, m_entries.size() - 1);
        m_entries.resize(kMaximumEntries);
        endRemoveRows();
    }

    updateUnreadCount();
    persist();
    emit countChanged();
    emit notificationRaised(entry.id, entry.title, entry.body, entry.severity,
        entry.actionLabel, entry.actionId);
    qCInfo(lcUi) << "Notification recorded" << entry.severity << entry.title;
    return entry.id;
}

void NotificationController::markRead(const QString &id)
{
    const int row = indexOf(id);
    if (row < 0 || m_entries[row].read)
        return;
    m_entries[row].read = true;
    emit dataChanged(index(row), index(row), {ReadRole});
    updateUnreadCount();
    persist();
}

void NotificationController::markAllRead()
{
    if (m_entries.isEmpty() || m_unreadCount == 0)
        return;
    for (Entry &entry : m_entries)
        entry.read = true;
    emit dataChanged(index(0), index(m_entries.size() - 1), {ReadRole});
    updateUnreadCount();
    persist();
}

void NotificationController::dismiss(const QString &id)
{
    const int row = indexOf(id);
    if (row < 0)
        return;
    Entry &entry = m_entries[row];
    entry.dismissed = true;
    entry.read = true;
    emit dataChanged(index(row), index(row), {ReadRole, DismissedRole});
    updateUnreadCount();
    persist();
}

void NotificationController::clearAll()
{
    if (m_entries.isEmpty())
        return;
    beginResetModel();
    m_entries.clear();
    endResetModel();
    updateUnreadCount();
    persist();
    emit countChanged();
}

void NotificationController::activateAction(const QString &id)
{
    const int row = indexOf(id);
    if (row < 0 || m_entries.at(row).actionId.isEmpty())
        return;
    emit actionRequested(m_entries.at(row).actionId, id);
    markRead(id);
}

int NotificationController::matchingCount(const QString &query, const bool regex,
    const QString &flags, const QString &scope) const
{
    if (query.size() > 4096)
        return 0;
    const QString normalizedFlags = flags.toLower();
    for (const QChar flag : normalizedFlags)
    {
        if (!u"gimsu"_s.contains(flag))
            return 0;
    }
    QRegularExpression expression;
    if (regex && !query.isEmpty())
    {
        QRegularExpression::PatternOptions options;
        if (normalizedFlags.contains(u'i')) options |= QRegularExpression::CaseInsensitiveOption;
        if (normalizedFlags.contains(u'm')) options |= QRegularExpression::MultilineOption;
        if (normalizedFlags.contains(u's')) options |= QRegularExpression::DotMatchesEverythingOption;
        if (normalizedFlags.contains(u'u')) options |= QRegularExpression::UseUnicodePropertiesOption;
        expression = QRegularExpression(kRegexSafetyPrefix + query + u')', options);
        if (!expression.isValid())
            return 0;
    }

    const Qt::CaseSensitivity sensitivity = normalizedFlags.contains(u'i')
        ? Qt::CaseInsensitive : Qt::CaseSensitive;
    int count = 0;
    for (const Entry &entry : m_entries)
    {
        if ((scope == u"unread"_s) && entry.read) continue;
        if ((scope == u"warning"_s) && (entry.severity != u"warning"_s)) continue;
        if ((scope == u"error"_s) && (entry.severity != u"error"_s)) continue;
        const QString haystack = entry.title + u' ' + entry.body;
        if (query.isEmpty() || (regex ? expression.match(haystack).hasMatch()
                                      : haystack.contains(query, sensitivity)))
            ++count;
    }
    return count;
}

int NotificationController::indexOf(const QString &id) const
{
    for (int i = 0; i < m_entries.size(); ++i)
    {
        if (m_entries.at(i).id == id)
            return i;
    }
    return -1;
}

QString NotificationController::normalizedSeverity(const QString &severity)
{
    const QString normalized = severity.trimmed().toLower();
    if ((normalized == u"success"_s) || (normalized == u"warning"_s)
        || (normalized == u"error"_s) || (normalized == u"progress"_s))
        return normalized;
    return u"info"_s;
}

QString NotificationController::defaultTitle(const QString &severity) const
{
    if (severity == u"error"_s) return tr("Error");
    if (severity == u"warning"_s) return tr("Warning");
    if (severity == u"success"_s) return tr("Completed");
    if (severity == u"progress"_s) return tr("In progress");
    return tr("Notice");
}

void NotificationController::load()
{
#ifdef QBT_HAS_PREFERENCES
    const QByteArray bytes = Preferences::instance()->value(kHistoryKey).toString().toUtf8();
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    if (!document.isArray())
        return;
    const QJsonArray array = document.array();
    m_entries.reserve(qMin(array.size(), kMaximumEntries));
    for (const QJsonValue &value : array)
    {
        if (!value.isObject() || m_entries.size() >= kMaximumEntries)
            break;
        const QJsonObject object = value.toObject();
        Entry entry;
        entry.id = object.value(u"id"_s).toString();
        entry.title = object.value(u"title"_s).toString();
        entry.body = object.value(u"body"_s).toString();
        entry.severity = normalizedSeverity(object.value(u"severity"_s).toString());
        entry.timestamp = QDateTime::fromString(object.value(u"time"_s).toString(), Qt::ISODate);
        entry.read = object.value(u"read"_s).toBool();
        entry.dismissed = object.value(u"dismissed"_s).toBool();
        entry.actionLabel = object.value(u"actionLabel"_s).toString();
        entry.actionId = object.value(u"actionId"_s).toString();
        if (entry.id.isEmpty() || entry.body.isEmpty() || !entry.timestamp.isValid())
            continue;
        m_entries.append(entry);
    }
#endif
    updateUnreadCount();
}

void NotificationController::persist() const
{
#ifdef QBT_HAS_PREFERENCES
    QJsonArray array;
    for (const Entry &entry : m_entries)
    {
        array.append(QJsonObject {
            {u"id"_s, entry.id}, {u"title"_s, entry.title}, {u"body"_s, entry.body},
            {u"severity"_s, entry.severity}, {u"time"_s, entry.timestamp.toString(Qt::ISODate)},
            {u"read"_s, entry.read}, {u"dismissed"_s, entry.dismissed},
            {u"actionLabel"_s, entry.actionLabel}, {u"actionId"_s, entry.actionId}
        });
    }
    Preferences::instance()->setValue(kHistoryKey,
        QString::fromUtf8(QJsonDocument(array).toJson(QJsonDocument::Compact)));
#endif
}

void NotificationController::updateUnreadCount()
{
    int unread = 0;
    for (const Entry &entry : m_entries)
        unread += entry.read ? 0 : 1;
    if (m_unreadCount == unread)
        return;
    m_unreadCount = unread;
    emit unreadCountChanged();
}
