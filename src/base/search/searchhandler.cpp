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
 *
 * Derived from the original qBittorrent (GPLv2+) search subsystem; the class
 * and method names, the `nova2.py` process protocol, and the parsed result
 * layout are preserved verbatim so the Python search plugins continue to work
 * and the QML bridge (SearchController / SearchResultsModel) can code against a
 * stable contract (see docs/CONTRACTS.md §6, docs/ARCHITECTURE.md).
 */

#include "searchhandler.h"

#include <chrono>

#include <QList>
#include <QMetaObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>

#include "base/global.h"
#include "base/logging.h"
#include "base/path.h"
#include "base/utils/bytearray.h"
#include "base/utils/foreignapps.h"
#include "searchpluginmanager.h"

using namespace std::chrono_literals;

namespace
{
    // Search plugins are third-party Python code. Bound every stream and the
    // result bridge so one noisy or malformed plugin cannot retain arbitrary
    // process output or rows in the desktop process.
    constexpr qsizetype MAX_SEARCH_STDOUT_BYTES = 8 * 1024 * 1024;
    constexpr qsizetype MAX_SEARCH_STDERR_BYTES = 512 * 1024;
    constexpr qsizetype MAX_SEARCH_RESULT_LINE_BYTES = 64 * 1024;
    constexpr qsizetype MAX_SEARCH_RESULTS = 10000;
    constexpr qint64 SEARCH_READ_CHUNK_BYTES = 64 * 1024;

    /// Column layout of a `nova2.py` result line (pipe-separated).
    enum SearchResultColumn
    {
        PL_DL_LINK,
        PL_NAME,
        PL_SIZE,
        PL_SEEDS,
        PL_LEECHS,
        PL_ENGINE_URL,
        PL_DESC_LINK,
        PL_PUB_DATE,
        NB_PLUGIN_COLUMNS
    };

    /// Human-readable, translatable text for a `QProcess` failure.
    QString toString(const QProcess::ProcessError error)
    {
        switch (error)
        {
        case QProcess::FailedToStart:
            return SearchHandler::tr("Process failed to start");
        case QProcess::Crashed:
            return SearchHandler::tr("Process crashed");
        case QProcess::Timedout:
            return SearchHandler::tr("Process timed out");
        case QProcess::WriteError:
            return SearchHandler::tr("Process write error");
        case QProcess::ReadError:
            return SearchHandler::tr("Process read error");
        case QProcess::UnknownError:
            return SearchHandler::tr("Process unknown error");
        }
        return {};
    }
}

SearchHandler::SearchHandler(const QString &pattern, const QString &category
        , const QStringList &usedPlugins, SearchPluginManager *manager)
    : QObject(manager)
    , m_pattern {pattern}
    , m_category {category}
    , m_usedPlugins {usedPlugins}
    , m_manager {manager}
    , m_searchProcess {new QProcess(this)}
    , m_searchTimeout {new QTimer(this)}
{
    qCInfo(lcSearch).noquote() << QStringLiteral("Starting search. Query: \"%1\". Category: \"%2\". Engines: \"%3\".")
        .arg(m_pattern, m_category, m_usedPlugins.join(u", "_s));

    // Load environment variables (proxy) so the Python plugins pick up the proxy config.
    m_searchProcess->setProcessEnvironment(m_manager->proxyEnvironment());
    m_searchProcess->setProgram(Utils::ForeignApps::pythonInfo().executablePath.data());
#ifdef Q_OS_UNIX
    m_searchProcess->setUnixProcessParameters(QProcess::UnixProcessFlag::CloseFileDescriptors);
#endif

    const QStringList params
    {
        Utils::ForeignApps::PYTHON_ISOLATE_MODE_FLAG,
        Utils::ForeignApps::PYTHON_UTF8_MODE_FLAG,
        (SearchPluginManager::engineLocation() / Path(u"nova2.py"_s)).toString(),
        m_usedPlugins.join(u','),
        m_category
    };
    m_searchProcess->setArguments(params + m_pattern.split(u' '));
    qCDebug(lcSearch).noquote() << QStringLiteral("Search process command line:")
        << m_searchProcess->program() << m_searchProcess->arguments().join(u' ');

    connect(m_searchProcess, &QProcess::errorOccurred, this, [this](const QProcess::ProcessError error)
    {
        if (m_searchCancelled || !m_terminalError.isEmpty())
        {
            qCDebug(lcSearch) << "Ignoring search process error after terminal state" << error;
            return;
        }

        failSearch(toString(error));
    });
    connect(m_searchProcess, &QProcess::readyReadStandardOutput, this, [this] { readSearchOutput(); });
    connect(m_searchProcess, &QProcess::readyReadStandardError, this, [this] { readSearchError(); });
    connect(m_searchProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished)
            , this, &SearchHandler::processFinished);

    m_searchTimeout->setSingleShot(true);
    connect(m_searchTimeout, &QTimer::timeout, this, [this]
    {
        failSearch(tr("Search timed out after 3 minutes."));
    });
    m_searchTimeout->start(3min);

    // Launch search.
    // Deferred start allows clients to connect to starting-related signals first.
    QMetaObject::invokeMethod(this, [this]
    {
        qCDebug(lcSearch) << "Spawning search process for query" << m_pattern;
        m_searchProcess->start(QIODevice::ReadOnly);
    }, Qt::QueuedConnection);
}

bool SearchHandler::isActive() const
{
    return (m_searchProcess->state() != QProcess::NotRunning);
}

void SearchHandler::cancelSearch()
{
    if ((m_searchProcess->state() == QProcess::NotRunning) || m_searchCancelled)
    {
        qCDebug(lcSearch) << "cancelSearch() ignored; process not running or already cancelled. Query:" << m_pattern;
        return;
    }

    qCInfo(lcSearch).noquote() << QStringLiteral("Cancelling search. Query: \"%1\".").arg(m_pattern);

    // Set state before signalling the process so a synchronous platform error
    // cannot turn an intentional cancel into a spurious failure.
    m_searchCancelled = true;
    m_searchTimeout->stop();

#ifdef Q_OS_WIN
    m_searchProcess->kill();
#else
    m_searchProcess->terminate();
#endif
}

// Slot called when QProcess is finished.
// QProcess can be finished for 3 reasons:
// Error | Stopped by user | Finished normally
void SearchHandler::processFinished(const int exitcode)
{
    m_searchTimeout->stop();

    // QProcess can emit finished while it still has buffered bytes. Drain the
    // bounded streams first so a normal final batch is not lost.
    if (!m_searchCancelled && m_terminalError.isEmpty())
    {
        readSearchOutput(true);
        readSearchError(true);
    }

    if (!m_terminalError.isEmpty())
    {
        m_searchResultLineTruncated.clear();
        m_searchStdErr.clear();
        emitSearchFailureOnce();
        return;
    }

    // nova2 normally terminates every result with a newline, but third-party
    // engines are not allowed to silently lose a valid final row when they
    // omit that delimiter. It has already passed the same bounded-line check
    // in readSearchOutput(); parse it once now that EOF makes it complete.
    if (!m_searchCancelled && !m_searchResultLineTruncated.isEmpty())
    {
        const QByteArray trailingLine = m_searchResultLineTruncated;
        m_searchResultLineTruncated.clear();
        if (SearchResult finalSearchResult; parseSearchResult(trailingLine, finalSearchResult))
        {
            if (m_resultCount >= MAX_SEARCH_RESULTS)
            {
                failSearch(tr("Search stopped after collecting %1 results.").arg(MAX_SEARCH_RESULTS));
            }
            else
            {
                ++m_resultCount;
                emit newSearchResults({std::move(finalSearchResult)});
            }
        }
    }

    if (!m_terminalError.isEmpty())
    {
        m_searchStdErr.clear();
        emitSearchFailureOnce();
        return;
    }

    const QString errMsg = QString::fromUtf8(m_searchStdErr).trimmed();
    m_searchResultLineTruncated.clear();
    m_searchStdErr.clear();
    if (!errMsg.isEmpty())
    {
        qCWarning(lcSearch).noquote() << tr("Error occurred in search engine. Search query: \"%1\". Category: \"%2\". Engines: \"%3\". Error: \"%4\".")
            .arg(m_pattern, m_category, m_usedPlugins.join(u", "_s), errMsg);
    }

    if (m_searchCancelled)
    {
        qCInfo(lcSearch).noquote() << QStringLiteral("Search cancelled. Query: \"%1\". Total results: %2.")
            .arg(m_pattern, QString::number(m_resultCount));
        emit searchFinished(true);
    }
    else if ((m_searchProcess->exitStatus() == QProcess::NormalExit) && (exitcode == 0))
    {
        qCInfo(lcSearch).noquote() << QStringLiteral("Search finished. Query: \"%1\". Total results: %2.")
            .arg(m_pattern, QString::number(m_resultCount));
        emit searchFinished(false);
    }
    else
    {
        const QString failure = errMsg.isEmpty()
            ? tr("The search process exited with code %1.").arg(exitcode)
            : errMsg;
        qCWarning(lcSearch).noquote() << QStringLiteral("Search failed. Query: \"%1\". Exit code: %2. Exit status: %3.")
            .arg(m_pattern, QString::number(exitcode), QString::number(m_searchProcess->exitStatus()));
        failSearch(failure);
    }
}

void SearchHandler::scheduleSearchOutputRead()
{
    if (m_searchOutputReadScheduled || m_searchCancelled || !m_terminalError.isEmpty())
        return;

    m_searchOutputReadScheduled = true;
    QMetaObject::invokeMethod(this, [this]
    {
        m_searchOutputReadScheduled = false;
        readSearchOutput();
    }, Qt::QueuedConnection);
}

void SearchHandler::scheduleSearchErrorRead()
{
    if (m_searchErrorReadScheduled || m_searchCancelled || !m_terminalError.isEmpty())
        return;

    m_searchErrorReadScheduled = true;
    QMetaObject::invokeMethod(this, [this]
    {
        m_searchErrorReadScheduled = false;
        readSearchError();
    }, Qt::QueuedConnection);
}

void SearchHandler::failSearch(const QString &errorMessage)
{
    if (m_searchCancelled || !m_terminalError.isEmpty() || m_searchFailureEmitted)
        return;

    m_terminalError = errorMessage.isEmpty() ? tr("The search process failed.") : errorMessage;
    m_searchTimeout->stop();
    qCWarning(lcSearch).noquote() << tr("Search process failed. Search query: \"%1\". Category: \"%2\". Engines: \"%3\". Error: \"%4\".")
        .arg(m_pattern, m_category, m_usedPlugins.join(u", "_s), m_terminalError);

    if ((m_searchProcess->state() == QProcess::NotRunning)
        || (m_searchProcess->error() == QProcess::FailedToStart))
    {
        emitSearchFailureOnce();
        return;
    }

    m_searchProcess->kill();
}

void SearchHandler::emitSearchFailureOnce()
{
    if (m_searchFailureEmitted)
        return;

    m_searchFailureEmitted = true;
    emit searchFailed(m_terminalError.isEmpty() ? tr("The search process failed.") : m_terminalError);
}

// The search QProcess returns output as soon as it has new data. Read in small
// chunks so Qt's process buffer and this parser have natural pipe backpressure.
// Keep one trailing partial line only; every complete row streams straight to the
// owning SearchResultsModel rather than being retained a second time here.
void SearchHandler::readSearchOutput(const bool drainAll)
{
    if (m_searchCancelled || !m_terminalError.isEmpty())
        return;

    do
    {
        m_searchProcess->setReadChannel(QProcess::StandardOutput);
        const QByteArray chunk = m_searchProcess->read(SEARCH_READ_CHUNK_BYTES);
        if (chunk.isEmpty())
            break;

        m_searchStdOutBytesRead += chunk.size();
        if (m_searchStdOutBytesRead > MAX_SEARCH_STDOUT_BYTES)
        {
            m_searchResultLineTruncated.clear();
            failSearch(tr("Search output exceeded the %1 MiB safety limit.")
                .arg(MAX_SEARCH_STDOUT_BYTES / (1024 * 1024)));
            return;
        }

        QByteArray output = m_searchResultLineTruncated;
        output.append(chunk);
        QList<QByteArrayView> lines = Utils::ByteArray::splitToViews(output, "\n", Qt::KeepEmptyParts);

        // The last item is either empty or an incomplete line for the next
        // chunk. Check its untrimmed length before storing it.
        const QByteArrayView trailingLine = lines.takeLast();
        if (trailingLine.size() > MAX_SEARCH_RESULT_LINE_BYTES)
        {
            m_searchResultLineTruncated.clear();
            failSearch(tr("Search output contains a line longer than %1 KiB.")
                .arg(MAX_SEARCH_RESULT_LINE_BYTES / 1024));
            return;
        }
        m_searchResultLineTruncated = trailingLine.trimmed().toByteArray();

        QList<SearchResult> searchResultList;
        searchResultList.reserve(lines.size());

        for (const QByteArrayView &line : asConst(lines))
        {
            if (line.size() > MAX_SEARCH_RESULT_LINE_BYTES)
            {
                failSearch(tr("Search output contains a line longer than %1 KiB.")
                    .arg(MAX_SEARCH_RESULT_LINE_BYTES / 1024));
                return;
            }

            if (SearchResult searchResult; parseSearchResult(line, searchResult))
            {
                searchResultList.append(std::move(searchResult));
                if ((m_resultCount + searchResultList.size()) > MAX_SEARCH_RESULTS)
                {
                    // A read chunk can contain many rows after the final free
                    // slot. Trim that batch before emitting so the advertised
                    // cap is an actual maximum rather than an off-by-a-chunk
                    // best effort.
                    const qsizetype remainingResultSlots = MAX_SEARCH_RESULTS - m_resultCount;
                    if (searchResultList.size() > remainingResultSlots)
                        searchResultList.resize(remainingResultSlots);
                    if (!searchResultList.isEmpty())
                    {
                        m_resultCount += searchResultList.size();
                        emit newSearchResults(searchResultList);
                    }
                    failSearch(tr("Search stopped after collecting %1 results.").arg(MAX_SEARCH_RESULTS));
                    return;
                }
            }
        }

        if (!searchResultList.isEmpty())
        {
            m_resultCount += searchResultList.size();
            qCDebug(lcSearch) << "Parsed" << searchResultList.size() << "new result(s) for query" << m_pattern
                << "(total" << m_resultCount << ')';
            emit newSearchResults(searchResultList);
        }
    }
    while (drainAll && (m_searchProcess->bytesAvailable() > 0));

    if (!drainAll && (m_searchProcess->bytesAvailable() > 0))
        scheduleSearchOutputRead();
}

void SearchHandler::readSearchError(const bool drainAll)
{
    if (m_searchCancelled || !m_terminalError.isEmpty())
        return;

    do
    {
        m_searchProcess->setReadChannel(QProcess::StandardError);
        const QByteArray chunk = m_searchProcess->read(SEARCH_READ_CHUNK_BYTES);
        if (chunk.isEmpty())
            break;

        const qsizetype remaining = MAX_SEARCH_STDERR_BYTES - m_searchStdErr.size();
        if (chunk.size() > remaining)
        {
            if (remaining > 0)
                m_searchStdErr.append(chunk.constData(), remaining);
            failSearch(tr("Search diagnostic output exceeded the %1 KiB safety limit.")
                .arg(MAX_SEARCH_STDERR_BYTES / 1024));
            return;
        }
        m_searchStdErr.append(chunk);
    }
    while (drainAll && (m_searchProcess->bytesAvailable() > 0));

    if (!drainAll && (m_searchProcess->bytesAvailable() > 0))
        scheduleSearchErrorRead();
}

// Parse one line of the search results list.
// The line has the following pipe-separated form:
// file url | file name | file size | nb seeds | nb leechers | engine site url | [desc link] | [pub date]
bool SearchHandler::parseSearchResult(const QByteArrayView line, SearchResult &searchResult)
{
    const QList<QByteArrayView> parts = Utils::ByteArray::splitToViews(line, "|");
    const qsizetype nbFields = parts.size();

    if (nbFields <= PL_ENGINE_URL)
        return false; // Anything after ENGINE_URL is optional; before it is mandatory.

    searchResult = SearchResult();
    searchResult.fileUrl = QString::fromUtf8(parts.at(PL_DL_LINK).trimmed()); // download URL
    searchResult.fileName = QString::fromUtf8(parts.at(PL_NAME).trimmed()); // name
    searchResult.fileSize = parts.at(PL_SIZE).trimmed().toLongLong(); // size

    bool ok = false;

    searchResult.nbSeeders = parts.at(PL_SEEDS).trimmed().toLongLong(&ok); // seeders
    if (!ok || (searchResult.nbSeeders < 0))
        searchResult.nbSeeders = -1;

    searchResult.nbLeechers = parts.at(PL_LEECHS).trimmed().toLongLong(&ok); // leechers
    if (!ok || (searchResult.nbLeechers < 0))
        searchResult.nbLeechers = -1;

    searchResult.siteUrl = QString::fromUtf8(parts.at(PL_ENGINE_URL).trimmed()); // engine site URL
    searchResult.engineName = m_manager->pluginNameBySiteURL(searchResult.siteUrl); // engine name

    if (nbFields > PL_DESC_LINK)
        searchResult.descrLink = QString::fromUtf8(parts.at(PL_DESC_LINK).trimmed()); // description link

    if (nbFields > PL_PUB_DATE)
    {
        const qint64 secs = parts.at(PL_PUB_DATE).trimmed().toLongLong(&ok);
        if (ok && (secs > 0))
            searchResult.pubDate = QDateTime::fromSecsSinceEpoch(secs); // publication date
    }

    return true;
}

SearchPluginManager *SearchHandler::manager() const
{
    return m_manager;
}

QString SearchHandler::pattern() const
{
    return m_pattern;
}
