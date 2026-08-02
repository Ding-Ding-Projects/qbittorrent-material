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

#include "torrentinfo.h"

#include <memory>
#include <span>

#include <libtorrent/create_torrent.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/torrent_info.hpp>

#include <QByteArray>
#include <QDateTime>
#include <QString>
#include <QUrl>

#include "base/global.h"
#include "base/logging.h"
#include "base/utils/fs/path.h"
#include "infohash.h"
#include "trackerentry.h"

using namespace BitTorrent;

TorrentInfo::TorrentInfo(const lt::torrent_info &nativeInfo)
    : m_nativeInfo {std::make_shared<const lt::torrent_info>(nativeInfo)}
{
    const lt::file_storage &fileStorage = m_nativeInfo->orig_files();
    m_nativeIndexes.reserve(fileStorage.num_files());
    for (const lt::file_index_t nativeIndex : fileStorage.file_range())
    {
        // Skip the padding files inserted by libtorrent so our public indexes are
        // stable and cover payload files only.
        if (fileStorage.pad_file_at(nativeIndex))
            continue;
        m_nativeIndexes.append(nativeIndex);
    }
}

TorrentInfo &TorrentInfo::operator=(const TorrentInfo &other) = default;

bool TorrentInfo::isValid() const
{
    return (m_nativeInfo != nullptr) && m_nativeInfo->is_valid() && (m_nativeInfo->num_files() > 0);
}

InfoHash TorrentInfo::infoHash() const
{
    if (!isValid())
        return {};

    return m_nativeInfo->info_hashes();
}

QString TorrentInfo::name() const
{
    if (!isValid())
        return {};

    return QString::fromStdString(m_nativeInfo->name());
}

bool TorrentInfo::isPrivate() const
{
    return isValid() && m_nativeInfo->priv();
}

qlonglong TorrentInfo::totalSize() const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->total_size();
}

int TorrentInfo::filesCount() const
{
    if (!isValid())
        return -1;

    return m_nativeIndexes.size();
}

int TorrentInfo::pieceLength() const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->piece_length();
}

int TorrentInfo::pieceLength(const int index) const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->piece_size(lt::piece_index_t {index});
}

int TorrentInfo::piecesCount() const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->num_pieces();
}

Path TorrentInfo::filePath(const int index) const
{
    if (!isValid())
        return {};

    return Path(m_nativeInfo->orig_files().file_path(m_nativeIndexes[index]));
}

PathList TorrentInfo::filePaths() const
{
    PathList list;
    list.reserve(filesCount());
    for (int i = 0; i < filesCount(); ++i)
        list << filePath(i);

    return list;
}

qlonglong TorrentInfo::fileSize(const int index) const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->orig_files().file_size(m_nativeIndexes[index]);
}

qlonglong TorrentInfo::fileOffset(const int index) const
{
    if (!isValid())
        return -1;

    return m_nativeInfo->orig_files().file_offset(m_nativeIndexes[index]);
}

QList<QByteArray> TorrentInfo::pieceHashes() const
{
    if (!isValid())
        return {};

    QList<QByteArray> hashes;
    hashes.reserve(piecesCount());
    for (const auto pieceIndex : m_nativeInfo->piece_range())
    {
        const lt::sha1_hash &hash = m_nativeInfo->hash_for_piece(pieceIndex);
        hashes.append(QByteArray::fromRawData(hash.data(), lt::sha1_hash::size()).toHex());
    }

    return hashes;
}

TorrentInfo::PieceRange TorrentInfo::filePieces(const Path &filePath) const
{
    if (!isValid())
        return {};

    const int index = fileIndex(filePath);
    if (index == -1)
    {
        qCDebug(lcEngine) << "Filename" << filePath.data() << "was not found in torrent" << name();
        return {};
    }

    return filePieces(index);
}

TorrentInfo::PieceRange TorrentInfo::filePieces(const int fileIndex) const
{
    if (!isValid())
        return {};

    if ((fileIndex < 0) || (fileIndex >= filesCount()))
    {
        qCDebug(lcEngine) << "Invalid file index" << fileIndex << "in torrent" << name();
        return {};
    }

    const lt::file_storage &files = m_nativeInfo->orig_files();
    const auto nativeIndex = m_nativeIndexes[fileIndex];
    const auto fileSize = files.file_size(nativeIndex);
    const auto fileOffset = files.file_offset(nativeIndex);

    const int pieceLength = m_nativeInfo->piece_length();
    const int firstPiece = static_cast<int>(fileOffset / pieceLength);
    const int lastPiece = static_cast<int>((fileOffset + fileSize - (fileSize > 0 ? 1 : 0)) / pieceLength);
    return makeInterval(firstPiece, lastPiece);
}

PathList TorrentInfo::filesForPiece(const int pieceIndex) const
{
    const QList<int> fileIndices = fileIndicesForPiece(pieceIndex);

    PathList res;
    res.reserve(fileIndices.size());
    for (const int index : fileIndices)
        res.append(filePath(index));

    return res;
}

QList<int> TorrentInfo::fileIndicesForPiece(const int pieceIndex) const
{
    if (!isValid() || (pieceIndex < 0) || (pieceIndex >= piecesCount()))
        return {};

    const std::vector<lt::file_slice> files = m_nativeInfo->map_block(
            lt::piece_index_t {pieceIndex}, 0, m_nativeInfo->piece_size(lt::piece_index_t {pieceIndex}));

    QList<int> res;
    res.reserve(static_cast<decltype(res)::size_type>(files.size()));
    for (const lt::file_slice &fileSlice : files)
    {
        const int index = m_nativeIndexes.indexOf(fileSlice.file_index);
        if (index >= 0)
            res.append(index);
    }

    return res;
}

QByteArray TorrentInfo::rawData() const
{
    if (!isValid())
        return {};

    const std::span<const char> infoSection = m_nativeInfo->info_section();
    return {infoSection.data(), static_cast<qsizetype>(infoSection.size())};
}

bool TorrentInfo::matchesInfoHash(const InfoHash &otherInfoHash) const
{
    if (!isValid() || !otherInfoHash.isValid())
        return false;

    // A magnet can advertise only one side of a hybrid torrent. Match any
    // common, valid hash generation so metadata that expands btih/v1 or
    // btmh/v2 into the complete hybrid identity is still accepted.
    const InfoHash ownInfoHash = infoHash();
    const SHA1Hash ownV1 = ownInfoHash.v1();
    const SHA1Hash otherV1 = otherInfoHash.v1();
    if (ownV1.isValid() && otherV1.isValid() && (ownV1 == otherV1))
        return true;

    const SHA256Hash ownV2 = ownInfoHash.v2();
    const SHA256Hash otherV2 = otherInfoHash.v2();
    return ownV2.isValid() && otherV2.isValid() && (ownV2 == otherV2);
}

std::shared_ptr<lt::torrent_info> TorrentInfo::nativeInfo() const
{
    if (!m_nativeInfo)
        return {};

    return std::make_shared<lt::torrent_info>(*m_nativeInfo);
}

QList<lt::file_index_t> TorrentInfo::nativeIndexes() const
{
    return m_nativeIndexes;
}

int TorrentInfo::fileIndex(const Path &filePath) const
{
    for (int i = 0; i < filesCount(); ++i)
    {
        if (filePath == this->filePath(i))
            return i;
    }

    return -1;
}
