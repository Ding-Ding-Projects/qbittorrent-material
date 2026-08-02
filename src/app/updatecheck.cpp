/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "updatecheck.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QRegularExpression>

using namespace Qt::StringLiterals;

namespace
{
    struct BuildIdentity
    {
        quint64 number = 0;
        QString commitPrefix;
        bool valid = false;
    };

    BuildIdentity parseBuildIdentity(const QString &value)
    {
        // Release tags use dashes; CMake build IDs use dots.
        static const QRegularExpression pattern(
            u"^build(?:-|\\.)([1-9][0-9]*)(?:-|\\.)([0-9a-fA-F]{7,40})$"_s);
        const QRegularExpressionMatch match = pattern.match(value.trimmed());
        if (!match.hasMatch())
            return {};

        bool ok = false;
        const quint64 number = match.captured(1).toULongLong(&ok);
        return {number, match.captured(2).toLower(), ok};
    }
}

bool UpdateCheck::Release::isValid() const
{
    return (buildNumber > 0) && !tagName.isEmpty() && !pageUrl.isEmpty()
        && !commitPrefix.isEmpty();
}

UpdateCheck::Release UpdateCheck::parseLatestRelease(const QByteArray &payload, QString *errorMessage)
{
    const auto fail = [errorMessage](const QString &message)
    {
        if (errorMessage)
            *errorMessage = message;
        return Release {};
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return fail(u"The release service returned invalid JSON."_s);

    const QJsonObject object = document.object();
    if (object.value(u"draft"_s).toBool(true) || object.value(u"prerelease"_s).toBool(true))
        return fail(u"The release service did not return a stable release."_s);

    const QString tagName = object.value(u"tag_name"_s).toString();
    const QString pageUrl = object.value(u"html_url"_s).toString();
    const BuildIdentity identity = parseBuildIdentity(tagName);
    if (!identity.valid || pageUrl.isEmpty())
        return fail(u"The latest release has an unsupported identity."_s);

    if (errorMessage)
        errorMessage->clear();
    return {tagName, pageUrl, identity.number, identity.commitPrefix};
}

bool UpdateCheck::isNewer(const Release &latest, const QString &currentBuildId)
{
    if (!latest.isValid())
        return false;

    const BuildIdentity current = parseBuildIdentity(currentBuildId);
    if (!current.valid)
        return true;

    if (latest.buildNumber != current.number)
        return latest.buildNumber > current.number;

    // Run numbers are immutable. For an unexpected same-run/different-commit
    // identity, offer the published artifact instead of claiming equivalence.
    return !latest.commitPrefix.startsWith(current.commitPrefix)
        && !current.commitPrefix.startsWith(latest.commitPrefix);
}
