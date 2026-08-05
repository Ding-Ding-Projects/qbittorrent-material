/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QObject>
#include <QString>
#include <QtContainerFwd>

class QProcess;
class QTimer;

/// A single row returned by a search plugin.
struct SearchResult
{
    QString fileName;
    QString fileUrl;
    qlonglong fileSize = 0;
    qlonglong nbSeeders = 0;
    qlonglong nbLeechers = 0;
    QString engineName;
    QString siteUrl;
    QString descrLink;
    QDateTime pubDate;
};

class SearchPluginManager;

/// Handle for one in-flight search. Wraps the `nova2.py` child process, parses its
/// line-oriented output into `SearchResult`s, and streams them via `newSearchResults`.
/// Created only by `SearchPluginManager::startSearch()`. Subscribe to the signals;
/// never poll. Log start/results/finish/cancel via `lcSearch`.
class SearchHandler final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SearchHandler)

    friend class SearchPluginManager;

    SearchHandler(const QString &pattern, const QString &category
                  , const QStringList &usedPlugins, SearchPluginManager *manager);

public:
    bool isActive() const;
    QString pattern() const;
    SearchPluginManager *manager() const;

    /// Aborts the search; `searchFinished(true)` follows.
    void cancelSearch();

signals:
    void searchFinished(bool cancelled = false);
    void searchFailed(const QString &errorMessage);
    void newSearchResults(const QList<SearchResult> &results);

private:
    void readSearchOutput(bool drainAll = false);
    void readSearchError(bool drainAll = false);
    void scheduleSearchOutputRead();
    void scheduleSearchErrorRead();
    void failSearch(const QString &errorMessage);
    void emitSearchFailureOnce();
    void processFinished(int exitcode);
    bool parseSearchResult(QByteArrayView line, SearchResult &searchResult);

    const QString m_pattern;
    const QString m_category;
    const QStringList m_usedPlugins;
    SearchPluginManager *m_manager = nullptr;
    QProcess *m_searchProcess = nullptr;
    QTimer *m_searchTimeout = nullptr;
    QByteArray m_searchResultLineTruncated;
    QByteArray m_searchStdErr;
    qsizetype m_searchStdOutBytesRead = 0;
    qsizetype m_resultCount = 0;
    bool m_searchCancelled = false;
    bool m_searchOutputReadScheduled = false;
    bool m_searchErrorReadScheduled = false;
    bool m_searchFailureEmitted = false;
    QString m_terminalError;
};
