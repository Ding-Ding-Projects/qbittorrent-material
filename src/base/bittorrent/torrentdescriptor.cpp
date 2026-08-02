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

#include "torrentdescriptor.h"

#include <libtorrent/error_code.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <QByteArray>
#include <QCoreApplication>
#include <QDateTime>
#include <QString>
#include <QUrl>

#include "base/global.h"
#include "base/logging.h"
#include "base/utils/io.h"
#include "infohash.h"
#include "trackerentry.h"

using namespace BitTorrent;
using namespace Qt::Literals::StringLiterals;

namespace
{
    // Amount of bytes libtorrent is allowed to decode from a .torrent file.
    constexpr int TORRENT_LOAD_LIMIT_BYTES = 100 * 1024 * 1024; // 100 MiB
}

TorrentDescriptor::TorrentDescriptor(lt::add_torrent_params ltAddTorrentParams)
    : m_ltAddTorrentParams {std::move(ltAddTorrentParams)}
{
    if (m_ltAddTorrentParams.ti)
    {
        m_info.emplace(*m_ltAddTorrentParams.ti);

        m_creationDate = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.ti->creation_date());
        m_creator = QString::fromStdString(m_ltAddTorrentParams.ti->creator());
        m_comment = QString::fromStdString(m_ltAddTorrentParams.ti->comment());
    }
}

InfoHash TorrentDescriptor::infoHash() const
{
    return m_ltAddTorrentParams.info_hashes;
}

QString TorrentDescriptor::name() const
{
    if (m_info)
    {
        const QString name = m_info->name();
        if (!name.isEmpty())
            return name;
    }

    return QString::fromStdString(m_ltAddTorrentParams.name);
}

QDateTime TorrentDescriptor::creationDate() const
{
    return m_creationDate;
}

QString TorrentDescriptor::creator() const
{
    return m_creator;
}

QString TorrentDescriptor::comment() const
{
    return m_comment;
}

QList<TrackerEntry> TorrentDescriptor::trackers() const
{
    QList<TrackerEntry> ret;
    ret.reserve(static_cast<decltype(ret)::size_type>(m_ltAddTorrentParams.trackers.size()));

    std::size_t i = 0;
    for (const std::string &tracker : m_ltAddTorrentParams.trackers)
    {
        const int tier = (i < m_ltAddTorrentParams.tracker_tiers.size())
                ? m_ltAddTorrentParams.tracker_tiers[i] : 0;
        ret.append({QString::fromStdString(tracker), tier});
        ++i;
    }

    return ret;
}

QList<QUrl> TorrentDescriptor::urlSeeds() const
{
    QList<QUrl> ret;
    ret.reserve(static_cast<decltype(ret)::size_type>(m_ltAddTorrentParams.url_seeds.size()));

    for (const std::string &urlSeed : m_ltAddTorrentParams.url_seeds)
        ret.append(QString::fromStdString(urlSeed));

    return ret;
}

const std::optional<TorrentInfo> &TorrentDescriptor::info() const
{
    return m_info;
}

void TorrentDescriptor::setTorrentInfo(TorrentInfo torrentInfo)
{
    m_info = std::move(torrentInfo);
    m_ltAddTorrentParams.info_hashes =
            static_cast<InfoHash::WrappedType>(m_info->infoHash());
    m_ltAddTorrentParams.ti = m_info->nativeInfo();
    if (m_ltAddTorrentParams.ti)
    {
        m_creationDate = QDateTime::fromSecsSinceEpoch(m_ltAddTorrentParams.ti->creation_date());
        m_creator = QString::fromStdString(m_ltAddTorrentParams.ti->creator());
        m_comment = QString::fromStdString(m_ltAddTorrentParams.ti->comment());
    }
}

nonstd::expected<TorrentDescriptor, QString> TorrentDescriptor::load(const QByteArray &data) noexcept
{
    if (data.isEmpty())
        return nonstd::make_unexpected(QCoreApplication::translate("BitTorrent::TorrentDescriptor", "Torrent data is empty."));

    lt::load_torrent_limits limits;
    limits.max_buffer_size = TORRENT_LOAD_LIMIT_BYTES;

    try
    {
        const lt::add_torrent_params ltParams = lt::load_torrent_buffer(
                lt::span<const char>(data.constData(), data.size()), limits);
        qCDebug(lcEngine) << "Loaded torrent from buffer, size:" << data.size();
        return TorrentDescriptor(ltParams);
    }
    catch (const lt::system_error &err)
    {
        const QString message = QString::fromLocal8Bit(err.what());
        qCWarning(lcEngine) << "Failed to decode torrent buffer:" << message;
        return nonstd::make_unexpected(message);
    }
}

nonstd::expected<TorrentDescriptor, QString> TorrentDescriptor::loadFromFile(const Path &path) noexcept
{
    const auto readResult = Utils::IO::readFile(path, TORRENT_LOAD_LIMIT_BYTES);
    if (!readResult)
        return nonstd::make_unexpected(readResult.error().message);

    return load(readResult.value());
}

nonstd::expected<TorrentDescriptor, QString> TorrentDescriptor::parse(const QString &str) noexcept
{
    lt::error_code ec;
    lt::add_torrent_params ltParams = lt::parse_magnet_uri(str.toStdString(), ec);
    if (ec)
    {
        qCWarning(lcEngine) << "Failed to parse magnet URI:" << QString::fromStdString(ec.message());
        return nonstd::make_unexpected(QString::fromStdString(ec.message()));
    }

    qCDebug(lcEngine) << "Parsed magnet URI:" << str;
    return TorrentDescriptor(std::move(ltParams));
}

nonstd::expected<void, QString> TorrentDescriptor::saveToFile(const Path &path) const
{
    const auto result = saveToBuffer();
    if (!result)
        return nonstd::make_unexpected(result.error());

    const auto writeResult = Utils::IO::saveToFile(path, result.value());
    if (!writeResult)
        return nonstd::make_unexpected(writeResult.error());

    return {};
}

nonstd::expected<QByteArray, QString> TorrentDescriptor::saveToBuffer() const
{
    if (!m_info || !m_info->isValid())
        return nonstd::make_unexpected(QCoreApplication::translate("BitTorrent::TorrentDescriptor", "Invalid metadata."));

    try
    {
        const std::shared_ptr<lt::torrent_info> nativeInfo = m_info->nativeInfo();
        lt::entry torrentEntry = lt::write_torrent_file(m_ltAddTorrentParams);

        QByteArray buffer;
        lt::bencode(std::back_inserter(buffer), torrentEntry);
        return buffer;
    }
    catch (const std::exception &err)
    {
        return nonstd::make_unexpected(QString::fromLocal8Bit(err.what()));
    }
}

const lt::add_torrent_params &TorrentDescriptor::ltAddTorrentParams() const
{
    return m_ltAddTorrentParams;
}
