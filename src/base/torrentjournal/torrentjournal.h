/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <memory>

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVariant>

#include "base/bittorrent/infohash.h"
#include "torrentjournalop.h"

namespace BitTorrent
{
    class Torrent;
    enum class TorrentRemoveOption;
}

namespace Git
{
    class GitRepositoryStore;
}

/**
 * Journals every torrent mutation (and every settings change) into local,
 * in-process Git repositories under the profile data directory:
 *
 *   torrent-journal/   — the "action log": one commit per torrent mutation.
 *       torrents/<TorrentID>.json   canonical config-only state per torrent
 *       blobs/<TorrentID>.torrent   bencoded metadata for delete-undo re-adds
 *       session.json                categories (with options) + tags
 *   settings-journal/  — the "settings repo": one commit per preference change.
 *       settings.json               accumulated key → value map
 *
 * History is append-only: undo and restore apply inverse mutations through
 * the normal engine and land as new annotated commits (Origin/Undoes
 * trailers), never as history rewrites.
 *
 * NOTE: this fork does not persist torrents across restarts (resume-data
 * storage is still a stub), so journal entries for torrents absent from the
 * session are EXPECTED after a restart — they are surfaced via
 * journaledOnlyTorrentIds() rather than treated as deletions.
 */
class TorrentJournal final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TorrentJournal)

public:
    enum class Repo
    {
        Actions,
        Settings
    };

    static void initInstance();
    static void freeInstance();
    static TorrentJournal *instance();

    [[nodiscard]] bool isAvailable() const;
    [[nodiscard]] QString repositoryPath(Repo repo) const;
    [[nodiscard]] QString headCommitId(Repo repo) const;
    [[nodiscard]] Git::GitRepositoryStore *store(Repo repo) const;

    // Newest-first decoded history. maxCount <= 0 means unlimited.
    [[nodiscard]] QList<TorrentJournalNS::JournalEntry> history(Repo repo, int maxCount) const;

    // Reads back stored state from a given commit (Actions repo).
    [[nodiscard]] bool torrentDocAtCommit(const QString &commitId, const QString &torrentId,
        QJsonObject *doc) const;
    [[nodiscard]] bool torrentBlobAtCommit(const QString &commitId, const QString &torrentId,
        QByteArray *blob) const;
    [[nodiscard]] QStringList torrentIdsAtCommit(const QString &commitId) const;
    [[nodiscard]] QJsonObject sessionDocAtCommit(const QString &commitId) const;
    [[nodiscard]] QJsonObject settingsDocAtCommit(const QString &commitId) const;

    // Torrents present in the journal working tree but absent from the live
    // session (the restart persistence gap).
    [[nodiscard]] QStringList journaledOnlyTorrentIds() const;
    [[nodiscard]] QJsonObject journaledTorrentDoc(const QString &torrentId) const;
    [[nodiscard]] QByteArray journaledTorrentBlob(const QString &torrentId) const;

    // While a scope is active every recorded op is flushed as ONE annotated
    // commit when the scope ends. Used by the undo manager.
    void beginAnnotatedScope(TorrentJournalNS::JournalOrigin origin, const QString &summary,
        const QString &undoesCommitId = {}, const QString &restoreTargetCommitId = {});
    void endAnnotatedScope();
    [[nodiscard]] bool isAnnotatedScopeActive() const;

    // Marks the NEXT ops for a torrent (e.g. the async torrentAdded of an
    // undo re-add) with the given annotation. Expires after ~30 seconds.
    void expectAnnotatedOps(const QString &torrentId, TorrentJournalNS::JournalOrigin origin,
        const QString &undoesCommitId);

    // Design: History panel auto-commit toggle (settings repo only; torrent
    // actions are always journaled) and retention preference.
    [[nodiscard]] bool isSettingsAutoCommitEnabled() const;
    void setSettingsAutoCommitEnabled(bool enabled);
    [[nodiscard]] QString retention() const;
    void setRetention(const QString &retention);

    // Flushes all pending work synchronously (called on shutdown while the
    // session and its torrents are still alive).
    void shutdownFlush();

signals:
    void entryCommitted(TorrentJournal::Repo repo, const TorrentJournalNS::JournalEntry &entry);
    void historyChanged(TorrentJournal::Repo repo);
    void statusChanged();

private:
    TorrentJournal();
    ~TorrentJournal() override;

    struct Annotation
    {
        TorrentJournalNS::JournalOrigin origin = TorrentJournalNS::JournalOrigin::User;
        QString undoesCommitId;
        QString restoreTargetCommitId;
        QString summary;
    };

    struct Expectation
    {
        TorrentJournalNS::JournalOrigin origin = TorrentJournalNS::JournalOrigin::Undo;
        QString undoesCommitId;
        QDateTime expiry;
    };

    void connectSession();
    void initializeRepositories();
    void onSessionRestored();

    void recordTorrentOp(TorrentJournalNS::JournalOpRecord op, const BitTorrent::Torrent *torrent,
        bool flushImmediately = false);
    void onTorrentAdded(BitTorrent::Torrent *torrent);
    void onTorrentAboutToBeRemoved(BitTorrent::Torrent *torrent,
        BitTorrent::TorrentRemoveOption removeOption);
    void onSettingsValueChanged(const QString &key, const QVariant &oldValue,
        const QVariant &newValue);

    void markSessionDirty(TorrentJournalNS::JournalOpRecord op);

    [[nodiscard]] bool writeTorrentFiles(const BitTorrent::Torrent *torrent, bool *changed);
    [[nodiscard]] bool writeSessionFile();
    void writeStaticFiles();

    void scheduleTorrentFlush();
    void flushTorrentJournal();
    [[nodiscard]] bool flushTorrentJournalImpl();
    void requeueActionBatch(QList<TorrentJournalNS::JournalOpRecord> ops,
        QSet<BitTorrent::TorrentID> dirtyTorrents, bool sessionDirty,
        bool preserveOps = false);
    void scheduleSettingsFlush();
    void flushSettingsJournal();
    [[nodiscard]] QString buildSummary(const QList<TorrentJournalNS::JournalOpRecord> &ops) const;
    [[nodiscard]] bool commitActions(const QString &summary,
        const QList<TorrentJournalNS::JournalOpRecord> &ops,
        const Annotation &annotation);

    [[nodiscard]] Annotation currentAnnotationFor(
        const QList<TorrentJournalNS::JournalOpRecord> &ops);

    static TorrentJournal *m_instance;

    std::unique_ptr<Git::GitRepositoryStore> m_actionStore;
    std::unique_ptr<Git::GitRepositoryStore> m_settingsStore;
    bool m_available = false;

    QList<TorrentJournalNS::JournalOpRecord> m_pendingOps;
    QSet<BitTorrent::TorrentID> m_dirtyTorrents;
    bool m_sessionDirty = false;
    bool m_preservePendingOps = false;
    QTimer m_torrentFlushTimer;

    struct SettingsChange
    {
        QVariant oldValue;
        QVariant newValue;
    };
    QHash<QString, SettingsChange> m_pendingSettings;
    QTimer m_settingsFlushTimer;

    bool m_scopeActive = false;
    Annotation m_scopeAnnotation;
    QHash<QString, Expectation> m_expectations; // torrentId → annotation
};
