/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2018-2024  Vladimir Golovnev <glassez@yandex.ru>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#include "searchdownloadhandler.h"

#include <QFileInfo>
#include <QMetaObject>
#include <QProcess>
#include <QTimer>
#include <QtLogging>

#include "base/global.h"
#include "base/logging.h"
#include "base/logger.h"
#include "base/path.h"
#include "base/utils/foreignapps.h"
#include "base/utils/fs.h"
#include "searchpluginmanager.h"

namespace
{
    // nova2dl.py should return one short path record. Bound both pipes before
    // the terminal parse so a malformed third-party plugin cannot retain an
    // arbitrary amount of process output in the client.
    constexpr qsizetype MAX_DOWNLOAD_STDOUT_BYTES = 64 * 1024;
    constexpr qsizetype MAX_DOWNLOAD_STDERR_BYTES = 64 * 1024;
    constexpr qint64 DOWNLOAD_READ_CHUNK_BYTES = 16 * 1024;
}

SearchDownloadHandler::SearchDownloadHandler(const QString &pluginName, const QString &url, SearchPluginManager *manager)
    : QObject(manager)
    , m_pluginName {pluginName}
    , m_url {url}
    , m_manager {manager}
    , m_downloadProcess {new QProcess(this)}
{
    m_downloadProcess->setProcessEnvironment(m_manager->proxyEnvironment());
#ifdef Q_OS_UNIX
    m_downloadProcess->setUnixProcessParameters(QProcess::UnixProcessFlag::CloseFileDescriptors);
#endif
    connect(m_downloadProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished)
            , this, &SearchDownloadHandler::downloadProcessFinished);
    connect(m_downloadProcess, &QProcess::readyReadStandardOutput,
            this, [this] { readDownloadOutput(); });
    connect(m_downloadProcess, &QProcess::readyReadStandardError,
            this, [this] { readDownloadError(); });
    connect(m_downloadProcess, &QProcess::errorOccurred, this,
        [this](const QProcess::ProcessError error)
    {
        if (error != QProcess::FailedToStart)
            return;
        finishDownload({}, tr("The search downloader could not start: %1.").arg(m_downloadProcess->errorString()));
    });
    const QStringList params
    {
        Utils::ForeignApps::PYTHON_ISOLATE_MODE_FLAG,
        Utils::ForeignApps::PYTHON_UTF8_MODE_FLAG,
        (SearchPluginManager::engineLocation() / Path(u"nova2dl.py"_s)).toString(),
        pluginName,
        url
    };
    // Launch search
    m_downloadProcess->start(Utils::ForeignApps::pythonInfo().executablePath.data(), params, QIODevice::ReadOnly);

    QTimer::singleShot(30000, this, [this]
    {
        if (m_finished || !m_downloadProcess
            || (m_downloadProcess->state() == QProcess::NotRunning))
        {
            return;
        }
        qCWarning(lcSearch) << "Search torrent download timed out" << m_pluginName << m_url;
        m_downloadProcess->kill();
        finishDownload({}, tr("The search downloader timed out after 30 seconds."));
    });
}

void SearchDownloadHandler::finishDownload(const QString &path, const QString &errorMessage)
{
    if (m_finished)
        return;
    m_finished = true;
    emit downloadFinished(path, errorMessage);
}

void SearchDownloadHandler::failDownload(const QString &errorMessage)
{
    if (m_finished || !m_terminalError.isEmpty())
        return;

    m_terminalError = errorMessage.isEmpty()
        ? tr("The search downloader failed.")
        : errorMessage;
    qCWarning(lcSearch).noquote() << tr("Search torrent download failed. Engine: \"%1\". URL: \"%2\". Error: \"%3\".")
        .arg(m_pluginName, m_url, m_terminalError);

    if (m_downloadProcess->state() != QProcess::NotRunning)
        m_downloadProcess->kill();
    finishDownload({}, m_terminalError);
}

void SearchDownloadHandler::scheduleDownloadOutputRead()
{
    if (m_finished || !m_terminalError.isEmpty() || m_downloadOutputReadScheduled)
        return;

    m_downloadOutputReadScheduled = true;
    QMetaObject::invokeMethod(this, [this]
    {
        m_downloadOutputReadScheduled = false;
        readDownloadOutput();
    }, Qt::QueuedConnection);
}

void SearchDownloadHandler::scheduleDownloadErrorRead()
{
    if (m_finished || !m_terminalError.isEmpty() || m_downloadErrorReadScheduled)
        return;

    m_downloadErrorReadScheduled = true;
    QMetaObject::invokeMethod(this, [this]
    {
        m_downloadErrorReadScheduled = false;
        readDownloadError();
    }, Qt::QueuedConnection);
}

void SearchDownloadHandler::readDownloadOutput(const bool drainAll)
{
    if (m_finished || !m_terminalError.isEmpty())
        return;

    do
    {
        m_downloadProcess->setReadChannel(QProcess::StandardOutput);
        const QByteArray chunk = m_downloadProcess->read(DOWNLOAD_READ_CHUNK_BYTES);
        if (chunk.isEmpty())
            break;

        const qsizetype remaining = MAX_DOWNLOAD_STDOUT_BYTES - m_downloadStdOut.size();
        if (chunk.size() > remaining)
        {
            if (remaining > 0)
                m_downloadStdOut.append(chunk.constData(), remaining);
            failDownload(tr("The search downloader produced more than %1 KiB of output.")
                .arg(MAX_DOWNLOAD_STDOUT_BYTES / 1024));
            return;
        }
        m_downloadStdOut.append(chunk);
    }
    while (drainAll && (m_downloadProcess->bytesAvailable() > 0));

    if (!drainAll && (m_downloadProcess->bytesAvailable() > 0))
        scheduleDownloadOutputRead();
}

void SearchDownloadHandler::readDownloadError(const bool drainAll)
{
    if (m_finished || !m_terminalError.isEmpty())
        return;

    do
    {
        m_downloadProcess->setReadChannel(QProcess::StandardError);
        const QByteArray chunk = m_downloadProcess->read(DOWNLOAD_READ_CHUNK_BYTES);
        if (chunk.isEmpty())
            break;

        const qsizetype remaining = MAX_DOWNLOAD_STDERR_BYTES - m_downloadStdErr.size();
        if (chunk.size() > remaining)
        {
            if (remaining > 0)
                m_downloadStdErr.append(chunk.constData(), remaining);
            failDownload(tr("The search downloader produced more than %1 KiB of diagnostic output.")
                .arg(MAX_DOWNLOAD_STDERR_BYTES / 1024));
            return;
        }
        m_downloadStdErr.append(chunk);
    }
    while (drainAll && (m_downloadProcess->bytesAvailable() > 0));

    if (!drainAll && (m_downloadProcess->bytesAvailable() > 0))
        scheduleDownloadErrorRead();
}

void SearchDownloadHandler::downloadProcessFinished(const int exitcode)
{
    if (m_finished)
        return;

    readDownloadOutput(true);
    readDownloadError(true);

    if (!m_terminalError.isEmpty())
    {
        finishDownload({}, m_terminalError);
        return;
    }

    const QString errMsg = QString::fromUtf8(m_downloadStdErr).trimmed();
    if (!errMsg.isEmpty())
    {
        qWarning("%s", qUtf8Printable(errMsg));
        LogMsg(tr("Error occurred when downloading torrent via search engine. Engine: \"%1\". URL: \"%2\". Error: \"%3\".")
            .arg(m_pluginName, m_url, errMsg), Log::WARNING);
    }

    QString path;
    if ((exitcode == 0) && (m_downloadProcess->exitStatus() == QProcess::NormalExit))
    {
        const QString line = QString::fromUtf8(m_downloadStdOut).trimmed();
        // Legacy nova2dl.py writes "<temporary path> <source URL>". The path
        // is allowed to contain spaces, so the final delimiter is the only
        // protocol separator we can safely use.
        const qsizetype delimiter = line.lastIndexOf(u' ');
        if ((delimiter > 0) && (delimiter < (line.size() - 1)))
        {
            const QStringView pathPart = QStringView(line).left(delimiter);
            const QStringView metadataPart = QStringView(line).mid(delimiter + 1);
            if (!pathPart.trimmed().isEmpty() && !metadataPart.trimmed().isEmpty())
                path = pathPart.trimmed().toString();
        }
    }

    m_downloadStdOut.clear();
    m_downloadStdErr.clear();

    QString finalError = errMsg;
    if ((exitcode != 0) || (m_downloadProcess->exitStatus() != QProcess::NormalExit))
    {
        if (finalError.isEmpty())
            finalError = tr("The search downloader exited before returning a torrent file.");
        path.clear();
    }
    else if (path.isEmpty() || !QFileInfo(path).isFile())
    {
        finalError = tr("The search downloader did not return a readable torrent file.");
        path.clear();
    }

    finishDownload(path, finalError);
}
