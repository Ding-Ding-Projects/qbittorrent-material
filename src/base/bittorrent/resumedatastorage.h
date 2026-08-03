/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <memory>

#include <QList>
#include <QString>

#include "base/path.h"
#include "infohash.h"

namespace Git
{
    class GitRepositoryStore;
}

namespace BitTorrent
{
    struct LoadTorrentParams;

    /**
     * @file resumedatastorage.h
     * @brief Persists the live torrent list across restarts through a local Git
     *        repository, using the same @c Git::GitRepositoryStore engine as the
     *        settings/workspace journal (bundled libgit2, no external Git or
     *        remote service).
     *
     * One torrent = three blobs under `torrents/`: `<id>.meta.json` (the
     * qBittorrent-level fields of @c LoadTorrentParams — name, category, tags,
     * save path, operating mode, share limits, …), `<id>.resume.dat` (the
     * bencoded @c lt::add_torrent_params from the latest
     * `save_resume_data_alert` with the info dict stripped — piece-verified
     * state included, so a reload does not re-check files from scratch), and
     * `<id>.metadata.dat` (the immutable info dict, written once when first
     * available so routine checkpoint commits stay small).
     *
     * Deliberately separate from @c TorrentJournal: the journal is an
     * append-history/undo log meant to be browsed and reverted; this store is a
     * plain current-state cache that gets overwritten and pruned freely as
     * torrents change and get removed, with no undo semantics of its own.
     */
    class ResumeDataStorage
    {
    public:
        explicit ResumeDataStorage(const Path &dataFolderPath);
        ~ResumeDataStorage();

        ResumeDataStorage(const ResumeDataStorage &) = delete;
        ResumeDataStorage &operator=(const ResumeDataStorage &) = delete;

        [[nodiscard]] bool isAvailable() const { return m_available; }

        // Writes (or overwrites) one torrent's full resume state and commits.
        // A no-op commit (identical content) is not an error.
        bool store(const TorrentID &id, const LoadTorrentParams &params);

        // Deletes one torrent's resume state and commits. Missing entries are
        // not an error.
        bool remove(const TorrentID &id);

        // Every currently-stored torrent id, oldest-added first.
        [[nodiscard]] QList<TorrentID> torrentIds() const;

        // Persists the queue from top to bottom independently of the
        // lexicographic torrent-file enumeration used by torrentIds().
        bool storeQueue(const QList<TorrentID> &ids);
        [[nodiscard]] QList<TorrentID> loadQueue() const;
        bool removeQueue();

        // Reconstructs one torrent's full resume state. False if missing/corrupt.
        [[nodiscard]] bool load(const TorrentID &id, LoadTorrentParams *params) const;

    private:
        Path m_rootPath;
        std::unique_ptr<Git::GitRepositoryStore> m_store;
        bool m_available = false;
    };
}
