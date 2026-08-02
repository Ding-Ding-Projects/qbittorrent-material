/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "experiencecontroller.h"

#include <QClipboard>
#include <QDate>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>

#include "base/logging.h"

#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

using namespace Qt::Literals::StringLiterals;

namespace
{
    const QString kFirstRunCompleteKey = u"Experience/FirstRunCompleted"_s;
    const QString kRegexSafetyPrefix = u"(*LIMIT_MATCH=100000)(*LIMIT_DEPTH=1000)(?:"_s;
    const QString kCommitBaseUrl = u"https://github.com/Ding-Ding-Projects/qbittorrent-material/commit/"_s;

    QDate parseUserDate(const QString &text)
    {
        const QString value = text.trimmed();
        if (value.isEmpty())
            return {};
        QDate date = QDate::fromString(value, Qt::ISODate);
        if (!date.isValid())
            date = QLocale().toDate(value, QLocale::ShortFormat);
        return date;
    }

    QRegularExpression::PatternOptions patternOptions(const QString &flags)
    {
        QRegularExpression::PatternOptions options = QRegularExpression::NoPatternOption;
        if (flags.contains(u'i')) options |= QRegularExpression::CaseInsensitiveOption;
        if (flags.contains(u'm')) options |= QRegularExpression::MultilineOption;
        if (flags.contains(u's')) options |= QRegularExpression::DotMatchesEverythingOption;
        if (flags.contains(u'u')) options |= QRegularExpression::UseUnicodePropertiesOption;
        return options;
    }
}

ExperienceController *ExperienceController::s_instance = nullptr;

ExperienceController *ExperienceController::create(QQmlEngine *, QJSEngine *)
{
    return instance();
}

ExperienceController *ExperienceController::instance()
{
    if (!s_instance)
        s_instance = new ExperienceController;
    return s_instance;
}

ExperienceController::ExperienceController(QObject *parent)
    : QObject(parent)
    , m_dishes(loadArrayResource(u":/experience/dim-sum.json"_s))
    , m_changelog(loadArrayResource(u":/experience/changelog.json"_s))
    , m_cantoneseCatalog(loadObjectResource(u":/i18n/cantonese.json"_s))
{
}

bool ExperienceController::startupDishVisible() const
{
    return m_startupDishVisible;
}

QVariantMap ExperienceController::startupDish() const
{
    return m_startupDish;
}

QVariantList ExperienceController::changelog() const
{
    return m_changelog;
}

void ExperienceController::considerStartupSurprise(const bool captureMode,
    const bool blockingFlow, const bool force)
{
    if (m_startupEvaluated && !force)
        return;
    m_startupEvaluated = true;

#ifdef QBT_HAS_PREFERENCES
    const bool firstRunComplete = Preferences::instance()->value(kFirstRunCompleteKey, false).toBool();
    if (!firstRunComplete && !force)
    {
        Preferences::instance()->setValue(kFirstRunCompleteKey, true);
        Preferences::instance()->apply();
        qCInfo(lcUi) << "Dim-sum surprise skipped during first run";
        return;
    }
#endif
    if (blockingFlow || m_dishes.isEmpty())
        return;
    if (captureMode && !force)
        return;
    if (!force && (QRandomGenerator::system()->bounded(10) != 0))
        return;

    const int index = QRandomGenerator::system()->bounded(static_cast<int>(m_dishes.size()));
    m_startupDish = m_dishes.at(index).toMap();
    m_startupDishVisible = !m_startupDish.isEmpty();
    emit startupDishChanged();
    qCInfo(lcUi) << "Dim-sum startup surprise selected" << m_startupDish.value(u"id"_s).toString();
}

void ExperienceController::dismissStartupDish()
{
    if (!m_startupDishVisible)
        return;
    m_startupDishVisible = false;
    emit startupDishChanged();
}

QVariantMap ExperienceController::filterChangelog(const QString &query, const bool regex,
    const QString &flags, const QString &fromDate, const QString &toDate) const
{
    QVariantMap result {{u"valid"_s, true}, {u"error"_s, QString()}};
    if (query.size() > 4096)
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("Patterns are limited to 4,096 characters.");
        result[u"entries"_s] = QVariantList {};
        return result;
    }
    const QString boundedQuery = query;
    const QDate from = parseUserDate(fromDate);
    const QDate to = parseUserDate(toDate);
    if ((!fromDate.trimmed().isEmpty() && !from.isValid())
        || (!toDate.trimmed().isEmpty() && !to.isValid()))
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("Enter a locale-formatted date or ISO date (YYYY-MM-DD).");
        result[u"entries"_s] = QVariantList {};
        return result;
    }
    if (from.isValid() && to.isValid() && from > to)
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("The start date must not be after the end date.");
        result[u"entries"_s] = QVariantList {};
        return result;
    }

    QRegularExpression expression;
    if (regex && !boundedQuery.isEmpty())
    {
        const QString normalizedFlags = flags.toLower();
        for (const QChar flag : normalizedFlags)
        {
            if (!u"gimsu"_s.contains(flag))
            {
                result[u"valid"_s] = false;
                result[u"error"_s] = tr("Unsupported regular-expression flag: %1").arg(flag);
                result[u"entries"_s] = QVariantList {};
                return result;
            }
        }
        expression.setPattern(kRegexSafetyPrefix + boundedQuery + u')');
        expression.setPatternOptions(patternOptions(flags));
        if (!expression.isValid())
        {
            result[u"valid"_s] = false;
            result[u"error"_s] = tr("Invalid regular expression at %1: %2")
                .arg(qMax<qsizetype>(0, expression.patternErrorOffset()
                    - kRegexSafetyPrefix.size())).arg(expression.errorString());
            result[u"entries"_s] = QVariantList {};
            return result;
        }
    }

    QVariantList filtered;
    for (const QVariant &value : m_changelog)
    {
        const QVariantMap entry = value.toMap();
        const QDate date = QDate::fromString(entry.value(u"date"_s).toString(), Qt::ISODate);
        if (from.isValid() && date.isValid() && date < from)
            continue;
        if (to.isValid() && date.isValid() && date > to)
            continue;
        const QString title = entry.value(u"title"_s).toString();
        const QString commit = entry.value(u"commit"_s).toString();
        const QStringList changes = entry.value(u"changes"_s).toStringList();
        QStringList localizedChanges;
        for (const QString &change : changes)
            localizedChanges.append(m_cantoneseCatalog.value(change).toString());
        const QString searchable = entry.value(u"version"_s).toString() + u'\n'
            + title + u'\n' + commit + u'\n' + changes.join(u'\n') + u'\n'
            + m_cantoneseCatalog.value(title).toString() + u'\n'
            + localizedChanges.join(u'\n');
        if (!boundedQuery.isEmpty())
        {
            const bool match = regex
                ? expression.match(searchable).hasMatch()
                : searchable.contains(boundedQuery, flags.contains(u'i')
                    ? Qt::CaseInsensitive : Qt::CaseSensitive);
            if (!match)
                continue;
        }
        filtered.append(entry);
    }
    result[u"entries"_s] = filtered;
    return result;
}

void ExperienceController::copyChangelog(const QVariantList &entries)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(markdownFor(entries));
    emit operationFinished(true, tr("The filtered changelog was copied to the clipboard."));
}

bool ExperienceController::exportChangelog(const QUrl &destination, const QVariantList &entries)
{
    const QString path = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (path.trimmed().isEmpty())
    {
        emit operationFinished(false, tr("Choose a local Markdown file for the changelog export."));
        return false;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        emit operationFinished(false, tr("Could not open the changelog export file: %1").arg(file.errorString()));
        return false;
    }
    const QByteArray bytes = markdownFor(entries).toUtf8();
    if ((file.write(bytes) != bytes.size()) || !file.commit())
    {
        emit operationFinished(false, tr("Could not save the changelog export: %1").arg(file.errorString()));
        return false;
    }
    emit operationFinished(true, tr("Exported %1 changelog entries to %2.").arg(entries.size()).arg(path));
    return true;
}

QVariantList ExperienceController::loadArrayResource(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        qCWarning(lcUi) << "Could not open bundled experience data" << path << file.errorString();
        return {};
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (!document.isArray())
    {
        qCWarning(lcUi) << "Invalid bundled experience data" << path << error.errorString();
        return {};
    }
    return document.array().toVariantList();
}

QVariantMap ExperienceController::loadObjectResource(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap {};
}

QString ExperienceController::markdownFor(const QVariantList &entries)
{
    QString output = u"# qBittorrent Material changelog\n\n"_s;
    QDate earliest;
    QDate latest;
    for (const QVariant &value : entries)
    {
        const QDate date = QDate::fromString(value.toMap().value(u"date"_s).toString(), Qt::ISODate);
        if (!date.isValid()) continue;
        if (!earliest.isValid() || date < earliest) earliest = date;
        if (!latest.isValid() || date > latest) latest = date;
    }
    output += entries.isEmpty()
        ? u"> Exported filtered range: no matching releases.\n\n"_s
        : u"> Exported filtered range: %1 through %2 (%3 entries).\n\n"_s
            .arg(earliest.toString(Qt::ISODate), latest.toString(Qt::ISODate))
            .arg(entries.size());
    for (const QVariant &value : entries)
    {
        const QVariantMap entry = value.toMap();
        output += u"## %1 — %2\n\n"_s.arg(entry.value(u"version"_s).toString(),
            entry.value(u"date"_s).toString());
        const QString commit = entry.value(u"commit"_s).toString();
        if (!commit.isEmpty())
            output += u"Commit: [%1](%2%1)\n\n"_s.arg(commit, kCommitBaseUrl);
        const QString title = entry.value(u"title"_s).toString();
        if (!title.isEmpty()) output += title + u"\n\n"_s;
        const QStringList changes = entry.value(u"changes"_s).toStringList();
        for (const QString &change : changes) output += u"- "_s + change + u'\n';
        output += u'\n';
    }
    return output;
}
