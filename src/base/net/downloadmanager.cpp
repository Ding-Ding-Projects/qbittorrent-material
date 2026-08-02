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
 * Derived in behavior from the original qBittorrent (GPLv2+) engine:
 * Copyright (C) 2024 Jonathan Ketchker
 * Copyright (C) 2015-2024 Vladimir Golovnev <glassez@yandex.ru>
 * Copyright (C) 2006 Christophe Dumez <chris@qbittorrent.org>
 */

#include "downloadmanager.h"

#include <algorithm>
#include <chrono>

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QNetworkAccessManager>
#include <QNetworkCookie>
#include <QNetworkCookieJar>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslError>
#include <QStringList>
#include <QTimer>
#include <QUrl>

#include "base/logging.h"
#include "base/preferences.h"
#include "base/utils/fs/path.h"
#include "downloadhandlerimpl.h"
#include "proxyconfigurationmanager.h"

using namespace std::chrono_literals;

namespace
{
    /// Build a browser-like User-Agent so that servers which block non-browser
    /// clients still serve the resource. The Firefox major version is derived
    /// from the elapsed months since a known release, cached after first use.
    QByteArray getBrowserUserAgent()
    {
        // Firefox release calendar
        // https://whattrainisitnow.com/calendar/
        // https://wiki.mozilla.org/index.php?title=Release_Management/Calendar&redirect=no

        static QByteArray ret;
        if (ret.isEmpty())
        {
            const std::chrono::time_point baseDate = std::chrono::sys_days(2024y / 04 / 16);
            const int baseVersion = 125;

            const std::chrono::time_point nowDate = std::chrono::system_clock::now();
            const int nowVersion = baseVersion + std::chrono::duration_cast<std::chrono::months>(nowDate - baseDate).count();

            QByteArray userAgentTemplate = QByteArrayLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:%1.0) Gecko/20100101 Firefox/%1.0");
            ret = userAgentTemplate.replace("%1", QByteArray::number(nowVersion));

            qCDebug(lcNet) << "Generated browser User-Agent:" << ret;
        }
        return ret;
    }
}

/// A cookie jar that persists cookies through `Preferences` and transparently
/// drops session/expired cookies on load, save and every read/write.
class Net::DownloadManager::NetworkCookieJar final : public QNetworkCookieJar
{
public:
    explicit NetworkCookieJar(QObject *parent = nullptr)
        : QNetworkCookieJar(parent)
    {
        const QDateTime now = QDateTime::currentDateTime();
        QList<QNetworkCookie> cookies = Preferences::instance()->getNetworkCookies();
        const qsizetype loadedCount = cookies.size();
        cookies.removeIf([&now](const QNetworkCookie &cookie)
        {
            return cookie.isSessionCookie() || (cookie.expirationDate() <= now);
        });

        qCDebug(lcNet) << "NetworkCookieJar loaded" << cookies.size() << "persistent cookie(s)"
                       << '(' << (loadedCount - cookies.size()) << "session/expired dropped)";

        setAllCookies(cookies);
    }

    ~NetworkCookieJar() override
    {
        const QDateTime now = QDateTime::currentDateTime();
        QList<QNetworkCookie> cookies = allCookies();
        cookies.removeIf([&now](const QNetworkCookie &cookie)
        {
            return cookie.isSessionCookie() || (cookie.expirationDate() <= now);
        });

        qCDebug(lcNet) << "NetworkCookieJar persisting" << cookies.size() << "cookie(s) to storage";
        Preferences::instance()->setNetworkCookies(cookies);
    }

    using QNetworkCookieJar::allCookies;
    using QNetworkCookieJar::setAllCookies;

    QList<QNetworkCookie> cookiesForUrl(const QUrl &url) const override
    {
        const QDateTime now = QDateTime::currentDateTime();
        QList<QNetworkCookie> cookies = QNetworkCookieJar::cookiesForUrl(url);
        cookies.removeIf([&now](const QNetworkCookie &cookie)
        {
            return !cookie.isSessionCookie() && (cookie.expirationDate() <= now);
        });

        return cookies;
    }

    bool setCookiesFromUrl(const QList<QNetworkCookie> &cookieList, const QUrl &url) override
    {
        const QDateTime now = QDateTime::currentDateTime();
        QList<QNetworkCookie> cookies = cookieList;
        cookies.removeIf([&now](const QNetworkCookie &cookie)
        {
            return !cookie.isSessionCookie() && (cookie.expirationDate() <= now);
        });

        return QNetworkCookieJar::setCookiesFromUrl(cookies, url);
    }
};

Net::DownloadManager *Net::DownloadManager::m_instance = nullptr;

Net::DownloadManager::DownloadManager(QObject *parent)
    : QObject(parent)
    , m_networkCookieJar {new NetworkCookieJar(this)}
    , m_networkManager {new QNetworkAccessManager(this)}
{
    qCDebug(lcNet) << "Constructing DownloadManager";

    m_networkManager->setCookieJar(m_networkCookieJar);
    connect(m_networkManager, &QNetworkAccessManager::sslErrors, this
            , [](QNetworkReply *reply, const QList<QSslError> &errors)
    {
        QStringList errorList;
        errorList.reserve(errors.size());
        for (const QSslError &error : errors)
            errorList += error.errorString();

        const QString url = reply->url().toString();
        const QString joinedErrors = errorList.join(u". ");

        if (!Preferences::instance()->isIgnoreSSLErrors())
        {
            // User-visible diagnostic — routed to the in-app Execution Log via the
            // dual-sink handler. Wrapped in tr() per the i18n contract.
            qCWarning(lcNet).noquote() << tr("SSL error, URL: \"%1\", errors: \"%2\"")
                    .arg(url, joinedErrors);
        }
        else
        {
            // Ignore all SSL errors
            reply->ignoreSslErrors();
            qCWarning(lcNet).noquote() << tr("Ignoring SSL error, URL: \"%1\", errors: \"%2\"")
                    .arg(url, joinedErrors);
        }
    });

    connect(ProxyConfigurationManager::instance(), &ProxyConfigurationManager::proxyConfigurationChanged
            , this, &DownloadManager::applyProxySettings);
    connect(Preferences::instance(), &Preferences::changed, this, &DownloadManager::applyProxySettings);
    applyProxySettings();

    qCInfo(lcNet) << "DownloadManager initialized";
}

void Net::DownloadManager::initInstance()
{
    if (!m_instance)
    {
        m_instance = new DownloadManager;
        qCInfo(lcNet) << "DownloadManager instance created";
    }
}

void Net::DownloadManager::freeInstance()
{
    qCInfo(lcNet) << "Destroying DownloadManager instance";
    delete m_instance;
    m_instance = nullptr;
}

Net::DownloadManager *Net::DownloadManager::instance()
{
    return m_instance;
}

Net::DownloadHandler *Net::DownloadManager::download(const DownloadRequest &downloadRequest, const bool useProxy)
{
    // Process download request
    const auto serviceID = ServiceID::fromURL(downloadRequest.url());
    const bool isSequentialService = m_sequentialServices.contains(serviceID);

    qCDebug(lcNet) << "Download requested" << downloadRequest.url()
                   << "useProxy=" << useProxy
                   << "sequentialService=" << isSequentialService;

    auto *downloadHandler = new DownloadHandlerImpl(this, downloadRequest, useProxy);
    connect(downloadHandler, &DownloadHandler::finished, this, [this, serviceID, downloadHandler]
    {
        if (!downloadHandler->assignedNetworkReply())
        {
            // DownloadHandler was finished (canceled) before QNetworkReply was assigned,
            // so it's still in the queue. Just remove it from there.
            qCDebug(lcNet) << "Removing unstarted download handler from waiting queue for host"
                           << serviceID.hostName;
            m_waitingJobs[serviceID].removeOne(downloadHandler);
        }

        downloadHandler->deleteLater();
    });

    if (isSequentialService && m_busyServices.contains(serviceID))
    {
        qCDebug(lcNet) << "Service busy, enqueuing download" << downloadRequest.url()
                       << "(queue length now" << (m_waitingJobs[serviceID].size() + 1) << ')';
        m_waitingJobs[serviceID].enqueue(downloadHandler);
    }
    else
    {
        qCInfo(lcNet) << "Downloading" << downloadRequest.url();
        if (isSequentialService)
            m_busyServices.insert(serviceID);
        processRequest(downloadHandler);
    }

    return downloadHandler;
}

void Net::DownloadManager::registerSequentialService(const Net::ServiceID &serviceID, const std::chrono::seconds delay)
{
    qCDebug(lcNet) << "Registering sequential service" << serviceID.hostName << ':' << serviceID.port
                   << "delay=" << static_cast<qint64>(delay.count()) << "s";
    m_sequentialServices.insert(serviceID, delay);
}

QList<QNetworkCookie> Net::DownloadManager::cookiesForUrl(const QUrl &url) const
{
    return m_networkCookieJar->cookiesForUrl(url);
}

bool Net::DownloadManager::setCookiesFromUrl(const QList<QNetworkCookie> &cookieList, const QUrl &url)
{
    qCDebug(lcNet) << "Setting" << cookieList.size() << "cookie(s) for URL" << url.toString();
    return m_networkCookieJar->setCookiesFromUrl(cookieList, url);
}

QList<QNetworkCookie> Net::DownloadManager::allCookies() const
{
    return m_networkCookieJar->allCookies();
}

void Net::DownloadManager::setAllCookies(const QList<QNetworkCookie> &cookieList)
{
    qCDebug(lcNet) << "Replacing cookie jar with" << cookieList.size() << "cookie(s)";
    m_networkCookieJar->setAllCookies(cookieList);
}

bool Net::DownloadManager::deleteCookie(const QNetworkCookie &cookie)
{
    const bool deleted = m_networkCookieJar->deleteCookie(cookie);
    qCDebug(lcNet) << "deleteCookie" << cookie.name() << "->" << deleted;
    return deleted;
}

bool Net::DownloadManager::hasSupportedScheme(const QString &url)
{
    static const QStringList schemes = QNetworkAccessManager().supportedSchemes();
    return std::ranges::any_of(schemes, [&url](const QString &scheme)
    {
        return url.startsWith((scheme + u':'), Qt::CaseInsensitive);
    });
}

void Net::DownloadManager::applyProxySettings()
{
    const auto *proxyManager = ProxyConfigurationManager::instance();
    const ProxyConfiguration proxyConfig = proxyManager->proxyConfiguration();

    switch (proxyConfig.type)
    {
    case Net::ProxyType::None:
    case Net::ProxyType::SOCKS4:
        // SOCKS4 is only usable by the BitTorrent session, not by QNetworkAccessManager.
        m_proxy = QNetworkProxy(QNetworkProxy::NoProxy);
        qCDebug(lcNet) << "Applied proxy settings: no proxy for general-purpose downloads";
        break;

    case Net::ProxyType::HTTP:
        m_proxy = QNetworkProxy(
            QNetworkProxy::HttpProxy
            , proxyConfig.ip
            , proxyConfig.port
            , (proxyConfig.authEnabled ? proxyConfig.username : QString())
            , (proxyConfig.authEnabled ? proxyConfig.password : QString()));
        m_proxy.setCapabilities(proxyConfig.hostnameLookupEnabled
            ? (m_proxy.capabilities() | QNetworkProxy::HostNameLookupCapability)
            : (m_proxy.capabilities() & ~QNetworkProxy::HostNameLookupCapability));
        qCInfo(lcNet) << "Applied HTTP proxy" << proxyConfig.ip << ':' << proxyConfig.port
                      << "auth=" << proxyConfig.authEnabled;
        break;

    case Net::ProxyType::SOCKS5:
        m_proxy = QNetworkProxy(
            QNetworkProxy::Socks5Proxy
            , proxyConfig.ip
            , proxyConfig.port
            , (proxyConfig.authEnabled ? proxyConfig.username : QString())
            , (proxyConfig.authEnabled ? proxyConfig.password : QString()));
        m_proxy.setCapabilities(proxyConfig.hostnameLookupEnabled
            ? (m_proxy.capabilities() | QNetworkProxy::HostNameLookupCapability)
            : (m_proxy.capabilities() & ~QNetworkProxy::HostNameLookupCapability));
        qCInfo(lcNet) << "Applied SOCKS5 proxy" << proxyConfig.ip << ':' << proxyConfig.port
                      << "auth=" << proxyConfig.authEnabled;
        break;
    };
}

void Net::DownloadManager::processWaitingJobs(const ServiceID &serviceID)
{
    const auto waitingJobsIter = m_waitingJobs.find(serviceID);
    if ((waitingJobsIter == m_waitingJobs.end()) || waitingJobsIter.value().isEmpty())
    {
        // No more waiting jobs for given ServiceID
        qCDebug(lcNet) << "No more waiting jobs for host" << serviceID.hostName << "- marking service idle";
        m_busyServices.remove(serviceID);
        return;
    }

    auto *handler = waitingJobsIter.value().dequeue();
    qCInfo(lcNet) << "Dequeued and downloading" << handler->url()
                  << '(' << waitingJobsIter.value().size() << "still waiting)";
    processRequest(handler);
}

void Net::DownloadManager::processRequest(DownloadHandlerImpl *downloadHandler)
{
    m_networkManager->setProxy((downloadHandler->useProxy() == true) ? m_proxy : QNetworkProxy(QNetworkProxy::NoProxy));

    const DownloadRequest downloadRequest = downloadHandler->downloadRequest();
    QNetworkRequest request {downloadRequest.url()};
    request.setHeader(QNetworkRequest::UserAgentHeader, (downloadRequest.userAgent().isEmpty()
        ? getBrowserUserAgent() : downloadRequest.userAgent().toUtf8()));

    // Spoof HTTP Referer to allow adding torrent link from Torcache/KickAssTorrents
    request.setRawHeader("Referer", request.url().toEncoded());
#ifdef QT_NO_COMPRESS
    // The macro "QT_NO_COMPRESS" defined in QT will disable the zlib related features
    // and reply data auto-decompression in QT will also be disabled. But we can support
    // gzip encoding and manually decompress the reply data.
    request.setRawHeader("Accept-Encoding", "gzip");
#endif
    // Qt doesn't support Magnet protocol so we need to handle redirections manually
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);

    request.setTransferTimeout();

    qCDebug(lcNet) << "Issuing GET" << downloadRequest.url()
                   << "proxy=" << (downloadHandler->useProxy() ? m_proxy.hostName() : QStringLiteral("none"))
                   << "userAgent=" << request.header(QNetworkRequest::UserAgentHeader).toString();

    QNetworkReply *reply = m_networkManager->get(request);
    // This handler runs *before* the DownloadHandlerImpl's own finished slot (connected
    // later in assignNetworkReply below), so it only inspects — never consumes — the reply.
    connect(reply, &QNetworkReply::finished, this, [this, reply, serviceID = ServiceID::fromURL(downloadHandler->url())]
    {
        // Log the response outcome (status/error) so requests and responses are both traceable.
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString redirectTarget = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl().toString();
        if (reply->error() != QNetworkReply::NoError)
        {
            qCWarning(lcNet) << "Response for host" << serviceID.hostName
                             << "finished with error" << reply->error()
                             << reply->errorString() << "(httpStatus=" << httpStatus << ')';
        }
        else if (!redirectTarget.isEmpty())
        {
            qCDebug(lcNet) << "Response for host" << serviceID.hostName
                           << "httpStatus=" << httpStatus << "redirect ->" << redirectTarget;
        }
        else
        {
            qCDebug(lcNet) << "Response for host" << serviceID.hostName
                           << "finished OK httpStatus=" << httpStatus
                           << "bytesAvailable=" << reply->bytesAvailable();
        }

        const std::chrono::seconds delay = m_sequentialServices.value(serviceID, 0s);
        qCDebug(lcNet) << "Reply finished for host" << serviceID.hostName
                       << "- scheduling next waiting job in" << static_cast<qint64>(delay.count()) << "s";
        QTimer::singleShot(delay, this, [this, serviceID] { processWaitingJobs(serviceID); });
    });
    downloadHandler->assignNetworkReply(reply);
}

Net::DownloadRequest::DownloadRequest(const QString &url)
    : m_url {url}
{
}

QString Net::DownloadRequest::url() const
{
    return m_url;
}

Net::DownloadRequest &Net::DownloadRequest::url(const QString &value)
{
    m_url = value;
    return *this;
}

QString Net::DownloadRequest::userAgent() const
{
    return m_userAgent;
}

Net::DownloadRequest &Net::DownloadRequest::userAgent(const QString &value)
{
    m_userAgent = value;
    return *this;
}

qint64 Net::DownloadRequest::limit() const
{
    return m_limit;
}

Net::DownloadRequest &Net::DownloadRequest::limit(const qint64 value)
{
    m_limit = value;
    return *this;
}

bool Net::DownloadRequest::saveToFile() const
{
    return m_saveToFile;
}

Net::DownloadRequest &Net::DownloadRequest::saveToFile(const bool value)
{
    m_saveToFile = value;
    return *this;
}

Path Net::DownloadRequest::destFileName() const
{
    return m_destFileName;
}

Net::DownloadRequest &Net::DownloadRequest::destFileName(const Path &value)
{
    m_destFileName = value;
    return *this;
}

Net::ServiceID Net::ServiceID::fromURL(const QUrl &url)
{
    const QString scheme = url.scheme();
    const int defaultPort = (scheme.compare(u"https", Qt::CaseInsensitive) == 0)
        ? 443
        : ((scheme.compare(u"http", Qt::CaseInsensitive) == 0) ? 80 : -1);
    return {url.host().toLower(), url.port(defaultPort)};
}

std::size_t Net::qHash(const ServiceID &serviceID, const std::size_t seed)
{
    return qHashMulti(seed, serviceID.hostName, serviceID.port);
}

bool Net::operator==(const ServiceID &lhs, const ServiceID &rhs)
{
    return ((lhs.hostName == rhs.hostName) && (lhs.port == rhs.port));
}
