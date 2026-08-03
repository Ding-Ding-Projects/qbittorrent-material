/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "journalhistorymodel.h"

#include <algorithm>

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QMap>
#include <QRegularExpression>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

#include "base/logging.h"
#include "base/torrentjournal/torrentjournal.h"
#include "base/torrentjournal/torrentundomanager.h"

using namespace Qt::StringLiterals;
using namespace TorrentJournalNS;

namespace
{
    QString relativeTimeText(const QDateTime &timestamp)
    {
        const qint64 secs = timestamp.secsTo(QDateTime::currentDateTimeUtc());
        if (secs < 60)
            return QObject::tr("just now");
        if (secs < 3600)
            return QObject::tr("%1m ago").arg(secs / 60);
        if (secs < (24 * 3600))
            return QObject::tr("%1h ago").arg(secs / 3600);
        return QObject::tr("%1d ago").arg(secs / (24 * 3600));
    }

    QString describeOp(const JournalOpRecord &op)
    {
        QString from = op.oldValue;
        QString to = op.newValue;
        const QString subject = op.torrentName.isEmpty() ? op.torrentId : op.torrentName;
        const QString kindText = journalOpKindToString(op.kind);
        if (from.isEmpty())
            from = u"(none)"_s;
        if (to.isEmpty())
            to = u"(none)"_s;
        return kindText + u' ' + subject + u": "_s + from + u" → "_s + to;
    }

    QString actionLabel(const QString &id)
    {
        if (id == u"created"_s)
            return QObject::tr("Created");
        if (id == u"updated"_s)
            return QObject::tr("Updated");
        if (id == u"deleted"_s)
            return QObject::tr("Deleted");
        if (id == u"restored"_s)
            return QObject::tr("Restored");
        if (id == u"undone"_s)
            return QObject::tr("Undone");
        if (id == u"imported"_s)
            return QObject::tr("Imported");
        if (id == u"settings-changed"_s)
            return QObject::tr("Settings changed");
        if (id == u"snapshot"_s)
            return QObject::tr("Snapshot");
        return id;
    }

    QStringList entryActionIds(const JournalEntry &entry, const QString &repo)
    {
        QSet<QString> ids;
        bool hasOtherMutation = false;

        if (entry.origin == JournalOrigin::Undo)
            ids.insert(u"undone"_s);
        else if (entry.origin == JournalOrigin::Restore)
            ids.insert(u"restored"_s);
        else if (entry.origin == JournalOrigin::Snapshot)
            ids.insert(u"snapshot"_s);

        if (entry.summary.contains(u"import"_s, Qt::CaseInsensitive))
            ids.insert(u"imported"_s);

        for (const JournalOpRecord &op : entry.ops)
        {
            switch (op.kind)
            {
            case JournalOpKind::Add:
                ids.insert(u"created"_s);
                break;
            case JournalOpKind::Delete:
                ids.insert(u"deleted"_s);
                break;
            case JournalOpKind::Restore:
                ids.insert(u"restored"_s);
                break;
            case JournalOpKind::Snapshot:
                ids.insert(u"snapshot"_s);
                break;
            case JournalOpKind::Config:
                ids.insert(u"settings-changed"_s);
                break;
            case JournalOpKind::Unknown:
                break;
            default:
                hasOtherMutation = true;
                break;
            }
        }

        if ((repo == u"settings"_s) && !ids.contains(u"snapshot"_s))
            ids.insert(u"settings-changed"_s);
        if (hasOtherMutation)
            ids.insert(u"updated"_s);
        if (ids.isEmpty())
            ids.insert(u"updated"_s);

        QStringList result = ids.values();
        std::sort(result.begin(), result.end());
        return result;
    }

    QRegularExpression::PatternOptions regexOptions(const QString &flags)
    {
        QRegularExpression::PatternOptions options;
        if (flags.contains(u"i"_s))
            options |= QRegularExpression::CaseInsensitiveOption;
        if (flags.contains(u"m"_s))
            options |= QRegularExpression::MultilineOption;
        if (flags.contains(u"s"_s))
            options |= QRegularExpression::DotMatchesEverythingOption;
        if (flags.contains(u"u"_s))
            options |= QRegularExpression::UseUnicodePropertiesOption;
        return options;
    }

    bool parseDate(const QString &text, QDate *date)
    {
        const QString value = text.trimmed();
        if (value.isEmpty())
        {
            *date = {};
            return true;
        }

        QDate parsed = QDate::fromString(value, Qt::ISODate);
        if (!parsed.isValid())
            parsed = QLocale().toDate(value, QLocale::ShortFormat);
        if (!parsed.isValid())
            return false;

        *date = parsed;
        return true;
    }
}

JournalHistoryModel::JournalHistoryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    if (TorrentJournal *journal = TorrentJournal::instance())
    {
        connect(journal, &TorrentJournal::historyChanged, this,
            [this](const TorrentJournal::Repo repo)
        {
            const bool matches = ((repo == TorrentJournal::Repo::Actions) && (m_repo == u"actions"_s))
                || ((repo == TorrentJournal::Repo::Settings) && (m_repo == u"settings"_s));
            if (matches)
                reload();
        });
    }
    reload();
}

int JournalHistoryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_entries.size());
}

QVariant JournalHistoryModel::data(const QModelIndex &index, const int role) const
{
    if (!index.isValid() || (index.row() < 0) || (index.row() >= m_entries.size()))
        return {};
    const JournalEntry &entry = m_entries.at(index.row());

    switch (role)
    {
    case CommitIdRole: return entry.commitId;
    case ShaRole: return entry.shortId.left(7);
    case MessageRole: return entry.summary;
    case TimeTextRole: return relativeTimeText(entry.timestamp);
    case DateKeyRole:
    {
        const qint64 secs = entry.timestamp.secsTo(QDateTime::currentDateTimeUtc());
        return (secs < (24 * 3600)) ? tr("Today") : tr("Earlier");
    }
    case DiffLinesRole:
    {
        QVariantList lines;
        for (const JournalOpRecord &op : entry.ops)
        {
            QVariantMap line;
            const QString subject = op.torrentName.isEmpty() ? op.torrentId : op.torrentName;
            line[u"from"_s] = QString(journalOpKindToString(op.kind) + u' ' + subject + u": "_s
                + (op.oldValue.isEmpty() ? u"(none)"_s : op.oldValue));
            line[u"to"_s] = QString(journalOpKindToString(op.kind) + u' ' + subject + u": "_s
                + (op.newValue.isEmpty() ? u"(none)"_s : op.newValue));
            lines.append(line);
            if (lines.size() >= 12)
                break;
        }
        return lines;
    }
    case UndoableRole:
        return (m_repo == u"actions"_s)
            ? TorrentUndoManager::isEntryUndoable(entry)
            : (!entry.ops.isEmpty() && (entry.origin == JournalOrigin::User));
    case CanRestoreRole:
        return (m_repo == u"actions"_s)
            ? (entry.origin != JournalOrigin::Snapshot)
            : !entry.ops.isEmpty();
    case OriginRole: return journalOriginToString(entry.origin);
    case OpCountRole: return static_cast<int>(entry.ops.size()) + entry.truncatedOpCount;
    default: return {};
    }
}

QHash<int, QByteArray> JournalHistoryModel::roleNames() const
{
    return {
        {CommitIdRole, QByteArrayLiteral("commitId")},
        {ShaRole, QByteArrayLiteral("sha")},
        {MessageRole, QByteArrayLiteral("message")},
        {TimeTextRole, QByteArrayLiteral("timeText")},
        {DateKeyRole, QByteArrayLiteral("dateKey")},
        {DiffLinesRole, QByteArrayLiteral("diffLines")},
        {UndoableRole, QByteArrayLiteral("undoable")},
        {CanRestoreRole, QByteArrayLiteral("canRestore")},
        {OriginRole, QByteArrayLiteral("origin")},
        {OpCountRole, QByteArrayLiteral("opCount")}
    };
}

QString JournalHistoryModel::repo() const
{
    return m_repo;
}

void JournalHistoryModel::setRepo(const QString &repo)
{
    const QString normalized = (repo == u"settings"_s) ? u"settings"_s : u"actions"_s;
    if (m_repo == normalized)
        return;
    m_repo = normalized;
    emit repoChanged();
    reload();
}

QString JournalHistoryModel::filterText() const
{
    return m_filterText;
}

void JournalHistoryModel::setFilterText(const QString &text)
{
    if (m_filterText == text)
        return;
    m_filterText = text;
    emit filterChanged();
    reload();
}

bool JournalHistoryModel::filterRegex() const
{
    return m_filterRegex;
}

void JournalHistoryModel::setFilterRegex(const bool regex)
{
    if (m_filterRegex == regex)
        return;
    m_filterRegex = regex;
    emit filterChanged();
    reload();
}

QString JournalHistoryModel::filterRegexFlags() const
{
    return m_filterRegexFlags;
}

void JournalHistoryModel::setFilterRegexFlags(const QString &flags)
{
    if (m_filterRegexFlags == flags)
        return;
    m_filterRegexFlags = flags;
    emit filterChanged();
    reload();
}

QString JournalHistoryModel::fromDate() const
{
    return m_fromDateText;
}

void JournalHistoryModel::setFromDate(const QString &date)
{
    if (m_fromDateText == date)
        return;
    m_fromDateText = date;
    reload();
    emit filterChanged();
}

QString JournalHistoryModel::toDate() const
{
    return m_toDateText;
}

void JournalHistoryModel::setToDate(const QString &date)
{
    if (m_toDateText == date)
        return;
    m_toDateText = date;
    reload();
    emit filterChanged();
}

QStringList JournalHistoryModel::actionFilter() const
{
    return m_actionFilter;
}

void JournalHistoryModel::setActionFilter(const QStringList &actions)
{
    QStringList normalized;
    for (const QString &action : actions)
    {
        const QString value = action.trimmed();
        if (!value.isEmpty() && !normalized.contains(value))
            normalized.append(value);
    }
    std::sort(normalized.begin(), normalized.end());
    if (m_actionFilter == normalized)
        return;
    m_actionFilter = normalized;
    emit filterChanged();
    reload();
}

bool JournalHistoryModel::filterValid() const
{
    return m_filterValid;
}

QString JournalHistoryModel::filterError() const
{
    return m_filterError;
}

QVariantList JournalHistoryModel::actionFacets() const
{
    return m_actionFacets;
}

int JournalHistoryModel::count() const
{
    return static_cast<int>(m_entries.size());
}

void JournalHistoryModel::refresh()
{
    reload();
}

bool JournalHistoryModel::matchesTextFilter(const JournalEntry &entry) const
{
    if (m_filterText.isEmpty())
        return true;

    QString haystack = entry.summary + u' ' + entry.shortId;
    for (const JournalOpRecord &op : entry.ops)
        haystack += u' ' + describeOp(op);

    if (m_filterRegex)
    {
        const QRegularExpression expression {m_filterText, regexOptions(m_filterRegexFlags)};
        if (!expression.isValid())
            return false;
        return expression.match(haystack).hasMatch();
    }
    return haystack.contains(m_filterText, Qt::CaseInsensitive);
}

bool JournalHistoryModel::matchesDateFilter(const JournalEntry &entry) const
{
    if (m_fromDateValue.isValid() && (entry.timestamp.toLocalTime().date() < m_fromDateValue))
        return false;
    if (m_toDateValue.isValid() && (entry.timestamp.toLocalTime().date() > m_toDateValue))
        return false;
    return true;
}

QStringList JournalHistoryModel::actionIds(const JournalEntry &entry) const
{
    return entryActionIds(entry, m_repo);
}

bool JournalHistoryModel::matchesFilter(const JournalEntry &entry) const
{
    if (!m_filterValid || !matchesDateFilter(entry) || !matchesTextFilter(entry))
        return false;
    if (m_actionFilter.isEmpty())
        return true;

    const QStringList ids = actionIds(entry);
    for (const QString &action : m_actionFilter)
    {
        if (ids.contains(action))
            return true;
    }
    return false;
}

void JournalHistoryModel::updateDateFilterState()
{
    m_filterValid = true;
    m_filterError.clear();
    m_fromDateValue = {};
    m_toDateValue = {};

    if (!parseDate(m_fromDateText, &m_fromDateValue))
    {
        m_filterValid = false;
        m_filterError = tr("Invalid start date. Use your locale format or YYYY-MM-DD.");
        return;
    }
    if (!parseDate(m_toDateText, &m_toDateValue))
    {
        m_filterValid = false;
        m_filterError = tr("Invalid end date. Use your locale format or YYYY-MM-DD.");
        return;
    }
    if (m_fromDateValue.isValid() && m_toDateValue.isValid()
            && (m_fromDateValue > m_toDateValue))
    {
        m_filterValid = false;
        m_filterError = tr("The start date must not be later than the end date.");
        return;
    }

    if (m_filterRegex && !m_filterText.isEmpty())
    {
        const QRegularExpression expression {m_filterText, regexOptions(m_filterRegexFlags)};
        if (!expression.isValid())
        {
            m_filterValid = false;
            m_filterError = tr("Invalid regular expression at offset %1: %2")
                    .arg(expression.patternErrorOffset()).arg(expression.errorString());
        }
    }
}

void JournalHistoryModel::reload()
{
    updateDateFilterState();

    QList<JournalEntry> sourceEntries;
    if (const TorrentJournal *journal = TorrentJournal::instance(); journal && journal->isAvailable())
    {
        const TorrentJournal::Repo repo = (m_repo == u"settings"_s)
            ? TorrentJournal::Repo::Settings : TorrentJournal::Repo::Actions;
        sourceEntries = journal->history(repo, 500);
    }

    QMap<QString, int> facetCounts;
    if (m_filterValid)
    {
        for (const JournalEntry &entry : sourceEntries)
        {
            // Facets describe the result set after date/text filtering, before
            // the action selection itself, so multiple actions compose as OR.
            if (!matchesDateFilter(entry) || !matchesTextFilter(entry))
                continue;
            for (const QString &id : actionIds(entry))
                ++facetCounts[id];
        }
    }
    for (const QString &id : m_actionFilter)
        facetCounts.insert(id, facetCounts.value(id, 0));

    m_actionFacets.clear();
    for (auto it = facetCounts.cbegin(); it != facetCounts.cend(); ++it)
    {
        QVariantMap facet;
        facet[u"id"_s] = it.key();
        facet[u"label"_s] = actionLabel(it.key());
        facet[u"count"_s] = it.value();
        m_actionFacets.append(facet);
    }

    beginResetModel();
    m_entries.clear();
    for (const JournalEntry &entry : sourceEntries)
    {
        if (matchesFilter(entry))
            m_entries.append(entry);
    }
    endResetModel();
    emit facetsChanged();
    emit countChanged();
}
