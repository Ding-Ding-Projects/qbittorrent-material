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

#include <QObject>
#include <QString>

class QProcess;

class SearchPluginManager;

/// Handle for downloading a search result's `.torrent` via the owning plugin
/// (the plugin may transform the result URL into a real torrent URL or magnet).
/// Created only by `SearchPluginManager::downloadTorrent()`; emits `downloadFinished`
/// with the local file path (or an error message) once the child process completes.
class SearchDownloadHandler final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SearchDownloadHandler)

    friend class SearchPluginManager;

    SearchDownloadHandler(const QString &pluginName, const QString &url, SearchPluginManager *manager);

signals:
    void downloadFinished(const QString &path, const QString &errorMessage);

private:
    void finishDownload(const QString &path, const QString &errorMessage);
    void downloadProcessFinished(int exitcode);

    QString m_pluginName;
    QString m_url;
    SearchPluginManager *m_manager = nullptr;
    QProcess *m_downloadProcess = nullptr;
    bool m_finished = false;
};
