/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once

#include <QByteArray>
#include <QString>

namespace UpdateCheck
{
    struct Release
    {
        QString tagName;
        QString pageUrl;
        quint64 buildNumber = 0;
        QString commitPrefix;

        [[nodiscard]] bool isValid() const;
    };

    /// Parse the small object returned by GitHub's latest-release endpoint.
    /// Drafts, prereleases, and tags outside this repository's immutable
    /// build-<run>-<sha> convention are deliberately rejected.
    [[nodiscard]] Release parseLatestRelease(const QByteArray &payload, QString *errorMessage = nullptr);

    /// Development builds without a release identity are considered older
    /// than a valid published release.
    [[nodiscard]] bool isNewer(const Release &latest, const QString &currentBuildId);
}
