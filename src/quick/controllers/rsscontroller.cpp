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

#include "rsscontroller.h"

#include <QClipboard>
#include <QDateTime>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QTextDocument>
#include <QUrl>

#include "base/bittorrent/session.h"
#include "base/bittorrent/torrentdescriptor.h"
#include "base/logging.h"
#include "base/rss/rss_article.h"
#include "base/rss/rss_autodownloader.h"
#include "base/rss/rss_feed.h"
#include "base/rss/rss_folder.h"
#include "base/rss/rss_item.h"
#include "base/rss/rss_session.h"
#include "quick/controllers/guiaddtorrentmanager.h"

using namespace Qt::StringLiterals;

RSSController *RSSController::s_instance = nullptr;

RSSController *RSSController::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(scriptEngine)

    if (!s_instance)
        s_instance = new RSSController;
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    qCDebug(lcRss) << "RSSController QML singleton created";
    return s_instance;
}

RSSController::RSSController(QObject *parent)
    : QObject(parent)
{
    connectSession();
    qCInfo(lcRss) << "RSSController initialized (processing="
                  << processingEnabled() << ", autoDownload=" << autoDownloadEnabled() << ')';
}

RSSController::~RSSController()
{
    qCDebug(lcRss) << "RSSController destroyed";
    if (s_instance == this)
        s_instance = nullptr;
}

void RSSController::connectSession()
{
    auto *session = RSS::Session::instance();
    auto *autoDl = RSS::AutoDownloader::instance();

    connect(session, &RSS::Session::processingStateChanged, this, [this](const bool enabled) {
        qCInfo(lcRss) << "RSS processing state changed ->" << enabled;
        emit processingEnabledChanged();
    });
    if (autoDl)
    {
        connect(autoDl, &RSS::AutoDownloader::processingStateChanged, this, [this](const bool enabled) {
            qCInfo(lcRss) << "RSS auto-download state changed ->" << enabled;
            emit autoDownloadEnabledChanged();
        });
    }

    if (RSS::Folder *root = session->rootFolder())
    {
        connect(root, &RSS::Item::unreadCountChanged, this, [this] {
            emit unreadCountChanged();
        });
    }
}

bool RSSController::processingEnabled() const
{
    return RSS::Session::instance()->isProcessingEnabled();
}

void RSSController::setProcessingEnabled(const bool enabled)
{
    if (enabled == processingEnabled())
        return;
    qCInfo(lcRss) << "Setting RSS processing enabled ->" << enabled;
    RSS::Session::instance()->setProcessingEnabled(enabled);
}

bool RSSController::autoDownloadEnabled() const
{
    auto *autoDl = RSS::AutoDownloader::instance();
    return autoDl && autoDl->isProcessingEnabled();
}

void RSSController::setAutoDownloadEnabled(const bool enabled)
{
    auto *autoDl = RSS::AutoDownloader::instance();
    if (!autoDl || (enabled == autoDl->isProcessingEnabled()))
        return;
    qCInfo(lcRss) << "Setting RSS auto-download enabled ->" << enabled;
    autoDl->setProcessingEnabled(enabled);
}

int RSSController::unreadCount() const
{
    RSS::Folder *root = RSS::Session::instance()->rootFolder();
    return root ? root->unreadCount() : 0;
}

QString RSSController::addFeed(const QString &url, const QString &destFolderPath)
{
    const QString feedPath = RSS::Item::joinPath(destFolderPath, url);
    qCInfo(lcRss) << "Adding feed" << url << "at path" << feedPath;
    const auto result = RSS::Session::instance()->addFeed(url, feedPath);
    if (!result)
    {
        qCWarning(lcRss) << "Add feed failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

QString RSSController::addFolder(const QString &name, const QString &destFolderPath)
{
    const QString path = RSS::Item::joinPath(destFolderPath, name);
    qCInfo(lcRss) << "Adding folder" << path;
    const auto result = RSS::Session::instance()->addFolder(path);
    if (!result)
    {
        qCWarning(lcRss) << "Add folder failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

QString RSSController::removeItem(const QString &path)
{
    if (path.isEmpty())
        return {}; // sticky node — nothing to remove
    qCInfo(lcRss) << "Removing RSS item" << path;
    const auto result = RSS::Session::instance()->removeItem(path);
    if (!result)
    {
        qCWarning(lcRss) << "Remove item failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

QString RSSController::renameItem(const QString &path, const QString &newName)
{
    const QString destPath = RSS::Item::joinPath(RSS::Item::parentPath(path), newName);
    qCInfo(lcRss) << "Renaming RSS item" << path << "->" << destPath;
    const auto result = RSS::Session::instance()->moveItem(path, destPath);
    if (!result)
    {
        qCWarning(lcRss) << "Rename failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

QString RSSController::moveItem(const QString &path, const QString &destFolderPath)
{
    const QString destPath = RSS::Item::joinPath(destFolderPath, RSS::Item::relativeName(path));
    qCInfo(lcRss) << "Moving RSS item" << path << "->" << destPath;
    const auto result = RSS::Session::instance()->moveItem(path, destPath);
    if (!result)
    {
        qCWarning(lcRss) << "Move failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

QString RSSController::setFeedURL(const QString &path, const QString &url, const int refreshIntervalSeconds)
{
    auto *item = RSS::Session::instance()->itemByPath(path);
    auto *feed = qobject_cast<RSS::Feed *>(item);
    if (!feed)
        return tr("Item is not a feed.");

    qCInfo(lcRss) << "Updating feed" << path << "url=" << url << "interval=" << refreshIntervalSeconds;
    feed->setRefreshInterval(std::chrono::seconds(refreshIntervalSeconds));
    const auto result = RSS::Session::instance()->setFeedURL(feed, url);
    if (!result)
    {
        qCWarning(lcRss) << "Set feed URL failed:" << result.error();
        emit errorOccurred(result.error());
        return result.error();
    }
    return {};
}

void RSSController::refreshItem(const QString &path)
{
    if (path.isEmpty())
    {
        refreshAll();
        return;
    }
    if (auto *item = RSS::Session::instance()->itemByPath(path))
    {
        qCDebug(lcRss) << "Refreshing RSS item" << path;
        item->refresh();
    }
}

void RSSController::refreshAll()
{
    qCInfo(lcRss) << "Refreshing all RSS feeds";
    if (RSS::Folder *root = RSS::Session::instance()->rootFolder())
        root->refresh();
}

void RSSController::markItemRead(const QString &path)
{
    RSS::Item *item = path.isEmpty()
        ? static_cast<RSS::Item *>(RSS::Session::instance()->rootFolder())
        : RSS::Session::instance()->itemByPath(path);
    if (item)
    {
        qCInfo(lcRss) << "Marking item read:" << (path.isEmpty() ? QStringLiteral("<all>") : path);
        item->markAsRead();
    }
}

QString RSSController::itemName(const QString &path) const
{
    auto *item = RSS::Session::instance()->itemByPath(path);
    return item ? item->name() : QString();
}

bool RSSController::isFeed(const QString &path) const
{
    return qobject_cast<RSS::Feed *>(RSS::Session::instance()->itemByPath(path)) != nullptr;
}

bool RSSController::isFolder(const QString &path) const
{
    return qobject_cast<RSS::Folder *>(RSS::Session::instance()->itemByPath(path)) != nullptr;
}

QString RSSController::feedURL(const QString &path) const
{
    auto *feed = qobject_cast<RSS::Feed *>(RSS::Session::instance()->itemByPath(path));
    return feed ? feed->url() : QString();
}

int RSSController::feedRefreshInterval(const QString &path) const
{
    auto *feed = qobject_cast<RSS::Feed *>(RSS::Session::instance()->itemByPath(path));
    return feed ? static_cast<int>(feed->refreshInterval().count()) : 0;
}

QStringList RSSController::feedURLsUnder(const QString &path) const
{
    QStringList urls;
    auto *item = RSS::Session::instance()->itemByPath(path);
    if (auto *feed = qobject_cast<RSS::Feed *>(item))
    {
        urls << feed->url();
    }
    else if (qobject_cast<RSS::Folder *>(item))
    {
        for (RSS::Feed *feed : RSS::Session::instance()->feeds())
        {
            if (feed->path().startsWith(path))
                urls << feed->url();
        }
    }
    return urls;
}

QString RSSController::newSubscriptionDestination(const QString &selectedPath) const
{
    // If a feed is selected, use its parent folder; if a folder, use it;
    // otherwise (sticky/nothing) use the root folder ("").
    auto *item = RSS::Session::instance()->itemByPath(selectedPath);
    if (qobject_cast<RSS::Feed *>(item))
        return RSS::Item::parentPath(selectedPath);
    if (qobject_cast<RSS::Folder *>(item))
        return selectedPath;
    return {};
}

QString RSSController::clipboardURL() const
{
    const QString text = QGuiApplication::clipboard()->text().trimmed();
    const QUrl url(text);
    static const QStringList supported {u"http"_s, u"https"_s, u"magnet"_s, u"ftp"_s};
    if (url.isValid() && supported.contains(url.scheme()))
        return text;
    return u"https://"_s;
}

void RSSController::copyToClipboard(const QString &text) const
{
    qCDebug(lcRss) << "Copying to clipboard:" << text;
    QGuiApplication::clipboard()->setText(text);
}

void RSSController::downloadTorrent(const QString &torrentUrl)
{
    if (torrentUrl.isEmpty())
        return;

    qCInfo(lcRss) << "Downloading torrent from article:" << torrentUrl;
    const auto descr = BitTorrent::TorrentDescriptor::parse(torrentUrl);
    if (descr)
    {
        BitTorrent::Session::instance()->addTorrent(descr.value());
    }
    else
    {
        // Torrent URLs need the shared manager: it owns the asynchronous fetch,
        // size limits, duplicate/tracker handling, and the user's add dialog.
        // Direct descriptor parsing above remains the fast path for magnets and
        // inline info-hash descriptors.
        if (GuiAddTorrentManager::instance()->addTorrent(torrentUrl))
            return;

        qCWarning(lcRss) << "Could not start torrent add request:" << torrentUrl
                          << descr.error();
        emit errorOccurred(descr.error());
    }
}

bool RSSController::openArticleLink(const QString &link)
{
    if (link.isEmpty())
        return false;

    const QUrl url(link);
    if (url.isLocalFile() || (url.scheme().compare(u"file"_s, Qt::CaseInsensitive) == 0))
    {
        qCWarning(lcRss) << "Blocked opening RSS article URL that resolves to a local file:" << link;
        emit articleUrlBlocked(link);
        return false;
    }

    qCInfo(lcRss) << "Opening article news URL:" << link;
    QDesktopServices::openUrl(url);
    return true;
}

QString RSSController::renderArticleHtml(const QVariantMap &article, const bool showFeed) const
{
    const QString title = article.value(u"title"_s).toString();
    const QString dateText = article.value(u"dateText"_s).toString();
    const QString feedName = article.value(u"feedName"_s).toString();
    const QString author = article.value(u"author"_s).toString();
    const QString link = article.value(u"link"_s).toString();
    QString description = article.value(u"description"_s).toString();

    QString html = u"<html><body>"_s;

    // ---- Header block (bordered) -----------------------------------------
    html += u"<div style='border:1px solid #cf222e; padding:6px; margin-bottom:8px;'>"_s;
    html += u"<div style='font-weight:bold;'>"_s + title.toHtmlEscaped() + u"</div>"_s;
    if (!dateText.isEmpty())
        html += u"<div>"_s + tr("Date: ") + dateText.toHtmlEscaped() + u"</div>"_s;
    if (showFeed && !feedName.isEmpty())
        html += u"<div>"_s + tr("Feed: ") + feedName.toHtmlEscaped() + u"</div>"_s;
    if (!author.isEmpty())
        html += u"<div>"_s + tr("Author: ") + author.toHtmlEscaped() + u"</div>"_s;
    if (!link.isEmpty())
        html += u"<div><a href='"_s + link.toHtmlEscaped() + u"'>"_s + tr("Open link") + u"</a></div>"_s;
    html += u"</div>"_s;

    // ---- Body ------------------------------------------------------------
    if (Qt::mightBeRichText(description))
    {
        html += description;
    }
    else
    {
        // Minimal BBCode -> HTML, then wrap in <pre> (mirrors HtmlBrowser).
        description = description.toHtmlEscaped();
        description.replace(QRegularExpression(u"\\[img\\](.+?)\\[/img\\]"_s), u"<img src=\"\\1\">"_s);
        description.replace(QRegularExpression(u"\\[url=(.+?)\\](.+?)\\[/url\\]"_s), u"<a href=\"\\1\">\\2</a>"_s);
        description.replace(QRegularExpression(u"\\[b\\](.+?)\\[/b\\]"_s), u"<b>\\1</b>"_s);
        description.replace(QRegularExpression(u"\\[i\\](.+?)\\[/i\\]"_s), u"<i>\\1</i>"_s);
        description.replace(QRegularExpression(u"\\[u\\](.+?)\\[/u\\]"_s), u"<u>\\1</u>"_s);
        description.replace(QRegularExpression(u"\\[s\\](.+?)\\[/s\\]"_s), u"<s>\\1</s>"_s);
        description.replace(QRegularExpression(u"\\[color=(.+?)\\](.+?)\\[/color\\]"_s), u"<span style=\"color:\\1\">\\2</span>"_s);
        description.replace(QRegularExpression(u"\\[size=(.+?)\\](.+?)\\[/size\\]"_s), u"<span style=\"font-size:\\1px\">\\2</span>"_s);
        html += u"<pre style='white-space:pre-wrap;'>"_s + description + u"</pre>"_s;
    }

    html += u"</body></html>"_s;
    return html;
}
