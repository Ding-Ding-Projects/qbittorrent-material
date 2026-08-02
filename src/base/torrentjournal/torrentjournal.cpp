/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "torrentjournal.h"

#include <utility>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonValue>

#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/git/gitrepositorystore.h"
#include "base/logging.h"
#include "base/profile.h"
#include "base/settingsstorage.h"
#include "base/tag.h"
#include "torrentjournalserializer.h"
#include "torrentundomanager.h"

using namespace Qt::Literals::StringLiterals;
using namespace TorrentJournalNS;

namespace
{
    constexpr int FlushDelayMs = 650;
    constexpr qint64 MaximumBlobBytes = 32LL * 1024 * 1024;
    constexpr int ExpectationLifetimeSecs = 30;

    const QString KeyAutoCommitSettings = u"TorrentJournal/AutoCommitSettings"_s;
    const QString KeyRetention = u"TorrentJournal/Retention"_s;

    QString torrentFileRelPath(const QString &torrentId)
    {
        return u"torrents/"_s + torrentId + u".json"_s;
    }

    QString blobFileRelPath(const QString &torrentId)
    {
        return u"blobs/"_s + torrentId + u".torrent"_s;
    }

    QJsonValue jsonValueForVariant(const QVariant &value)
    {
        if (!value.isValid())
            return QJsonValue();
        const QJsonValue converted = QJsonValue::fromVariant(value);
        if (converted.isNull() || converted.isUndefined())
            return QJsonValue(value.toString());
        return converted;
    }

    QString displayValue(const QVariant &value)
    {
        if (!value.isValid())
            return u"(unset)"_s;
        const QString text = value.toString();
        if (text.isEmpty() && value.canConvert<QStringList>())
            return value.toStringList().join(u", "_s);
        return text.isEmpty() ? u"(complex value)"_s : text;
    }
}

TorrentJournal *TorrentJournal::m_instance = nullptr;

void TorrentJournal::initInstance()
{
    if (!m_instance)
        m_instance = new TorrentJournal;
}

void TorrentJournal::freeInstance()
{
    delete m_instance;
    m_instance = nullptr;
}

TorrentJournal *TorrentJournal::instance()
{
    return m_instance;
}

TorrentJournal::TorrentJournal()
{
    const Path dataRoot = specialFolderLocation(SpecialFolder::Data);
    m_actionStore = std::make_unique<Git::GitRepositoryStore>(
        (dataRoot / Path(u"torrent-journal"_s)).data(),
        u"qBittorrent Material Journal"_s, u"journal@local.invalid"_s);
    m_settingsStore = std::make_unique<Git::GitRepositoryStore>(
        (dataRoot / Path(u"settings-journal"_s)).data(),
        u"qBittorrent Material Journal"_s, u"journal@local.invalid"_s);

    m_torrentFlushTimer.setSingleShot(true);
    m_torrentFlushTimer.setInterval(FlushDelayMs);
    connect(&m_torrentFlushTimer, &QTimer::timeout, this, &TorrentJournal::flushTorrentJournal);

    m_settingsFlushTimer.setSingleShot(true);
    m_settingsFlushTimer.setInterval(FlushDelayMs);
    connect(&m_settingsFlushTimer, &QTimer::timeout, this, &TorrentJournal::flushSettingsJournal);

    initializeRepositories();
    connectSession();

    // Version history is a safety feature, not a lossy preference. Profiles
    // created by earlier builds may have paused settings capture; re-enable it
    // before listening for new writes and snapshot any drift that occurred.
    if (!isSettingsAutoCommitEnabled())
        setSettingsAutoCommitEnabled(true);

    connect(SettingsStorage::instance(), &SettingsStorage::valueChanged,
        this, &TorrentJournal::onSettingsValueChanged);
}

TorrentJournal::~TorrentJournal()
{
    shutdownFlush();
}

void TorrentJournal::initializeRepositories()
{
    QString error;
    bool ok = m_actionStore->ensureRepository(&error);
    if (!ok)
    {
        qCWarning(lcApp) << "Torrent journal repository unavailable:" << error;
    }
    else if (!m_actionStore->recoveryPath().isEmpty())
    {
        qCWarning(lcApp) << "Torrent journal recovered; previous files kept in"
            << m_actionStore->recoveryPath();
    }

    QString settingsError;
    const bool settingsOk = m_settingsStore->ensureRepository(&settingsError);
    if (!settingsOk)
        qCWarning(lcApp) << "Settings journal repository unavailable:" << settingsError;

    m_available = ok && settingsOk;
    if (m_available)
    {
        writeStaticFiles();

        // First run: capture the complete preference state as the settings
        // repo's root commit (the design's "init: preferences snapshot").
        if (m_settingsStore->headCommitId().isEmpty())
        {
            QJsonObject snapshot;
            const QStringList keys = SettingsStorage::instance()->allKeys();
            for (const QString &key : keys)
            {
                snapshot[key] = jsonValueForVariant(
                    SettingsStorage::instance()->loadValue<QVariant>(key));
            }
            QString error;
            if (!Git::GitRepositoryStore::writeFileAtomically(
                    QDir(m_settingsStore->rootPath()).filePath(u"settings.json"_s),
                    QJsonDocument(snapshot).toJson(QJsonDocument::Indented), &error))
            {
                qCWarning(lcApp) << "Settings journal initial snapshot write failed:" << error;
            }
            else
            {
                bool committed = false;
                const QString message = encodeCommitMessage(
                    u"init: preferences snapshot (%1 keys)"_s.arg(keys.size()),
                    {}, JournalOrigin::Snapshot);
                if (!m_settingsStore->commitAll(message, nullptr, &committed, &error))
                    qCWarning(lcApp) << "Settings journal initial snapshot failed:" << error;
            }
        }
    }
}

void TorrentJournal::writeStaticFiles()
{
    const QDir actionRoot {m_actionStore->rootPath()};
    const QByteArray manifest = QJsonDocument(QJsonObject {
        {u"schemaVersion"_s, TorrentDocSchemaVersion},
        {u"kind"_s, u"torrent-journal"_s}
    }).toJson(QJsonDocument::Indented);
    QString error;
    if (!Git::GitRepositoryStore::writeFileAtomically(
            actionRoot.filePath(u"manifest.json"_s), manifest, &error))
        qCWarning(lcApp) << "Torrent journal manifest write failed:" << error;

    const QByteArray actionReadme = QByteArrayLiteral(
        "# qBittorrent Material torrent journal\n\n"
        "A complete local Git repository managed by qBittorrent Material.\n"
        "Every torrent mutation (add, delete, edit) is one commit.\n\n"
        "- `torrents/<id>.json` stores each torrent's configuration.\n"
        "- `blobs/<id>.torrent` stores the torrent metadata for delete-undo.\n"
        "- `session.json` stores categories and tags.\n\n"
        "Use the in-app History panel to undo entries or restore a point in time.\n");
    if (!Git::GitRepositoryStore::writeFileAtomically(
            actionRoot.filePath(u"README.md"_s), actionReadme, &error))
        qCWarning(lcApp) << "Torrent journal README write failed:" << error;

    const QDir settingsRoot {m_settingsStore->rootPath()};
    const QByteArray settingsReadme = QByteArrayLiteral(
        "# qBittorrent Material settings journal\n\n"
        "A complete local Git repository managed by qBittorrent Material.\n"
        "Every preference change is one commit over `settings.json`.\n");
    if (!Git::GitRepositoryStore::writeFileAtomically(
            settingsRoot.filePath(u"README.md"_s), settingsReadme, &error))
        qCWarning(lcApp) << "Settings journal README write failed:" << error;
}

void TorrentJournal::connectSession()
{
    using BitTorrent::Session;
    using BitTorrent::Torrent;
    Session *session = Session::instance();
    if (!session)
    {
        qCWarning(lcApp) << "Torrent journal: no BitTorrent session to observe";
        return;
    }

    connect(session, &Session::torrentAdded, this, &TorrentJournal::onTorrentAdded);
    connect(session, &Session::torrentAboutToBeRemoved,
        this, &TorrentJournal::onTorrentAboutToBeRemoved);

    connect(session, &Session::torrentNameChanged, this, [this](Torrent *torrent, const QString &oldName)
    {
        recordTorrentOp({JournalOpKind::Name, torrent->id().toString(), torrent->name(),
            oldName, torrent->name()}, torrent);
    });
    connect(session, &Session::torrentCategoryChanged, this,
        [this](Torrent *torrent, const QString &oldCategory)
    {
        recordTorrentOp({JournalOpKind::Category, torrent->id().toString(), torrent->name(),
            oldCategory, torrent->category()}, torrent);
    });
    connect(session, &Session::torrentTagAdded, this, [this](Torrent *torrent, const Tag &tag)
    {
        recordTorrentOp({JournalOpKind::TagAdd, torrent->id().toString(), torrent->name(),
            {}, tag.toString()}, torrent);
    });
    connect(session, &Session::torrentTagRemoved, this, [this](Torrent *torrent, const Tag &tag)
    {
        recordTorrentOp({JournalOpKind::TagRemove, torrent->id().toString(), torrent->name(),
            tag.toString(), {}}, torrent);
    });
    connect(session, &Session::torrentSavePathChanged, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::SavePath, torrent->id().toString(), torrent->name(),
            {}, torrent->savePath().data()}, torrent);
    });
    connect(session, &Session::torrentSavingModeChanged, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::SavingMode, torrent->id().toString(), torrent->name(),
            {}, torrent->isAutoTMMEnabled() ? u"automatic"_s : u"manual"_s}, torrent);
    });
    connect(session, &Session::torrentStarted, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::Start, torrent->id().toString(), torrent->name(),
            u"stopped"_s, u"running"_s}, torrent);
    });
    connect(session, &Session::torrentStopped, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::Stop, torrent->id().toString(), torrent->name(),
            u"running"_s, u"stopped"_s}, torrent);
    });
    connect(session, &Session::torrentMetadataReceived, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::Metadata, torrent->id().toString(), torrent->name(),
            {}, u"metadata received"_s}, torrent);
    });
    connect(session, &Session::torrentConfigChanged, this, [this](Torrent *torrent)
    {
        recordTorrentOp({JournalOpKind::Config, torrent->id().toString(), torrent->name(),
            {}, {}}, torrent);
    });
    connect(session, &Session::trackersAdded, this,
        [this](Torrent *torrent, const QList<BitTorrent::TrackerEntry> &trackers)
    {
        recordTorrentOp({JournalOpKind::TrackersAdd, torrent->id().toString(), torrent->name(),
            {}, QString::number(trackers.size()) + u" trackers"_s}, torrent);
    });
    connect(session, &Session::trackersRemoved, this,
        [this](Torrent *torrent, const QStringList &trackers)
    {
        recordTorrentOp({JournalOpKind::TrackersRemove, torrent->id().toString(), torrent->name(),
            QString::number(trackers.size()) + u" trackers"_s, {}}, torrent);
    });
    connect(session, &Session::trackersReset, this, [this](Torrent *torrent,
        const QList<BitTorrent::TrackerEntryStatus> &, const QList<BitTorrent::TrackerEntry> &)
    {
        recordTorrentOp({JournalOpKind::TrackersReset, torrent->id().toString(), torrent->name(),
            {}, {}}, torrent);
    });
    connect(session, &Session::torrentContentFileRenamed, this,
        [this](Torrent *torrent, const int index, const Path &oldFilePath)
    {
        Q_UNUSED(index);
        recordTorrentOp({JournalOpKind::FileRename, torrent->id().toString(), torrent->name(),
            oldFilePath.data(), {}}, torrent);
    });
    connect(session, &Session::torrentContentFolderRenamed, this, [this](Torrent *torrent,
        const Path &newFolderPath, const Path &oldFolderPath, const QHash<int, Path> &)
    {
        recordTorrentOp({JournalOpKind::FolderRename, torrent->id().toString(), torrent->name(),
            oldFolderPath.data(), newFolderPath.data()}, torrent);
    });

    // Session-level state (categories/tags) lands in session.json.
    connect(session, &Session::categoryAdded, this, [this](const QString &name)
    {
        markSessionDirty({JournalOpKind::SessionCategory, {}, {}, {}, name});
    });
    connect(session, &Session::categoryRemoved, this, [this](const QString &name)
    {
        markSessionDirty({JournalOpKind::SessionCategory, {}, {}, name, {}});
    });
    connect(session, &Session::categoryOptionsChanged, this, [this](const QString &name)
    {
        markSessionDirty({JournalOpKind::SessionCategory, {}, {}, name, name});
    });
    connect(session, &Session::tagAdded, this, [this](const Tag &tag)
    {
        markSessionDirty({JournalOpKind::SessionTag, {}, {}, {}, tag.toString()});
    });
    connect(session, &Session::tagRemoved, this, [this](const Tag &tag)
    {
        markSessionDirty({JournalOpKind::SessionTag, {}, {}, tag.toString(), {}});
    });

    if (session->isRestored())
        onSessionRestored();
    else
        connect(session, &Session::restored, this, &TorrentJournal::onSessionRestored);
}

void TorrentJournal::onSessionRestored()
{
    if (!m_available)
        return;

    // Capture the full live state; the no-op commit check suppresses the
    // commit when nothing drifted while the app was closed.
    bool anyChanged = false;
    const QList<BitTorrent::Torrent *> torrents = BitTorrent::Session::instance()->torrents();
    for (const BitTorrent::Torrent *torrent : torrents)
    {
        bool changed = false;
        if (writeTorrentFiles(torrent, &changed))
            anyChanged = anyChanged || changed;
    }
    if (!writeSessionFile())
        qCWarning(lcApp) << "Torrent journal: session.json write failed at startup";

    QString commitId;
    bool committed = false;
    QString error;
    const QString message = encodeCommitMessage(u"snapshot: startup"_s,
        {{JournalOpKind::Snapshot, {}, {}, {}, QString::number(torrents.size()) + u" torrents"_s}},
        JournalOrigin::Snapshot);
    if (!m_actionStore->commitAll(message, &commitId, &committed, &error))
        qCWarning(lcApp) << "Torrent journal startup snapshot failed:" << error;
    else if (committed)
    {
        qCInfo(lcApp) << "Torrent journal: startup snapshot committed" << commitId.left(8);
        emit historyChanged(Repo::Actions);
    }

    const QStringList orphans = journaledOnlyTorrentIds();
    if (!orphans.isEmpty())
    {
        qCInfo(lcApp) << "Torrent journal:" << orphans.size()
            << "journaled torrents are not in the session (restorable via History)";

        // Opt-in: with no real resume-data storage in this fork, the journal
        // can double as the persistence layer and re-add everything it knows
        // about on startup. Deferred so the session finishes settling first.
        if (SettingsStorage::instance()->loadValue(u"TorrentJournal/AutoRestoreOnStartup"_s, false))
        {
            QTimer::singleShot(0, this, []
            {
                if (TorrentUndoManager *undoManager = TorrentUndoManager::instance())
                {
                    qCInfo(lcApp) << "Torrent journal: auto-restoring journaled torrents on startup";
                    undoManager->restoreMissingTorrents();
                }
            });
        }
    }
    emit statusChanged();
    Q_UNUSED(anyChanged);
}

bool TorrentJournal::isAvailable() const
{
    return m_available;
}

QString TorrentJournal::repositoryPath(const Repo repo) const
{
    return (repo == Repo::Actions) ? m_actionStore->rootPath() : m_settingsStore->rootPath();
}

QString TorrentJournal::headCommitId(const Repo repo) const
{
    return store(repo)->headCommitId();
}

Git::GitRepositoryStore *TorrentJournal::store(const Repo repo) const
{
    return (repo == Repo::Actions) ? m_actionStore.get() : m_settingsStore.get();
}

QList<JournalEntry> TorrentJournal::history(const Repo repo, const int maxCount) const
{
    QList<JournalEntry> entries;
    if (!m_available)
        return entries;
    const QList<Git::CommitInfo> commits = store(repo)->log(maxCount);
    entries.reserve(commits.size());
    for (const Git::CommitInfo &commit : commits)
    {
        JournalEntry entry = decodeCommitMessage(commit.message);
        entry.commitId = commit.id;
        entry.shortId = commit.shortId;
        entry.timestamp = commit.timestamp;
        entries.append(entry);
    }
    return entries;
}

bool TorrentJournal::torrentDocAtCommit(const QString &commitId, const QString &torrentId,
    QJsonObject *doc) const
{
    QByteArray content;
    bool found = false;
    if (!m_actionStore->readFileAtCommit(commitId, torrentFileRelPath(torrentId), &content, &found)
        || !found)
        return false;
    if (doc)
        *doc = QJsonDocument::fromJson(content).object();
    return true;
}

bool TorrentJournal::torrentBlobAtCommit(const QString &commitId, const QString &torrentId,
    QByteArray *blob) const
{
    bool found = false;
    if (!m_actionStore->readFileAtCommit(commitId, blobFileRelPath(torrentId), blob, &found)
        || !found)
        return false;
    return true;
}

QStringList TorrentJournal::torrentIdsAtCommit(const QString &commitId) const
{
    QStringList files;
    if (!m_actionStore->listTreeFiles(commitId, u"torrents"_s, &files))
        return {};
    QStringList ids;
    ids.reserve(files.size());
    for (const QString &file : std::as_const(files))
    {
        if (file.endsWith(u".json"_s))
            ids.append(file.chopped(5));
    }
    return ids;
}

QJsonObject TorrentJournal::sessionDocAtCommit(const QString &commitId) const
{
    QByteArray content;
    bool found = false;
    if (!m_actionStore->readFileAtCommit(commitId, u"session.json"_s, &content, &found) || !found)
        return {};
    return QJsonDocument::fromJson(content).object();
}

QJsonObject TorrentJournal::settingsDocAtCommit(const QString &commitId) const
{
    QByteArray content;
    bool found = false;
    if (!m_settingsStore->readFileAtCommit(commitId, u"settings.json"_s, &content, &found) || !found)
        return {};
    return QJsonDocument::fromJson(content).object();
}

QStringList TorrentJournal::journaledOnlyTorrentIds() const
{
    if (!m_available)
        return {};
    const QDir torrentsDir {QDir(m_actionStore->rootPath()).filePath(u"torrents"_s)};
    const QStringList files = torrentsDir.entryList({u"*.json"_s}, QDir::Files);

    QSet<QString> liveIds;
    if (const BitTorrent::Session *session = BitTorrent::Session::instance())
    {
        const QList<BitTorrent::Torrent *> torrents = session->torrents();
        for (const BitTorrent::Torrent *torrent : torrents)
            liveIds.insert(torrent->id().toString());
    }

    QStringList orphans;
    for (const QString &file : files)
    {
        const QString id = file.chopped(5);
        if (!liveIds.contains(id))
            orphans.append(id);
    }
    return orphans;
}

QJsonObject TorrentJournal::journaledTorrentDoc(const QString &torrentId) const
{
    QFile file {QDir(m_actionStore->rootPath()).filePath(torrentFileRelPath(torrentId))};
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

QByteArray TorrentJournal::journaledTorrentBlob(const QString &torrentId) const
{
    QFile file {QDir(m_actionStore->rootPath()).filePath(blobFileRelPath(torrentId))};
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

void TorrentJournal::beginAnnotatedScope(const JournalOrigin origin, const QString &summary,
    const QString &undoesCommitId, const QString &restoreTargetCommitId)
{
    // Anything already pending belongs to the previous (user) context.
    flushTorrentJournal();

    m_scopeActive = true;
    m_scopeAnnotation = {origin, undoesCommitId, restoreTargetCommitId, summary};
}

void TorrentJournal::endAnnotatedScope()
{
    if (!m_scopeActive)
        return;
    flushTorrentJournal();
    m_scopeActive = false;
    m_scopeAnnotation = {};
}

bool TorrentJournal::isAnnotatedScopeActive() const
{
    return m_scopeActive;
}

void TorrentJournal::expectAnnotatedOps(const QString &torrentId, const JournalOrigin origin,
    const QString &undoesCommitId)
{
    m_expectations.insert(torrentId,
        {origin, undoesCommitId, QDateTime::currentDateTimeUtc().addSecs(ExpectationLifetimeSecs)});
}

bool TorrentJournal::isSettingsAutoCommitEnabled() const
{
    return SettingsStorage::instance()->loadValue(KeyAutoCommitSettings, true);
}

void TorrentJournal::setSettingsAutoCommitEnabled(const bool enabled)
{
    if (!enabled)
    {
        qCWarning(lcApp) << "Ignoring request to disable mandatory local settings history";
        return;
    }
    const bool wasEnabled = isSettingsAutoCommitEnabled();
    SettingsStorage::instance()->storeValue(KeyAutoCommitSettings, enabled);
    if (!wasEnabled && enabled)
    {
        // Re-enabling captures whatever drifted while paused as one snapshot.
        m_pendingSettings.clear();
        QJsonObject snapshot;
        const QStringList keys = SettingsStorage::instance()->allKeys();
        for (const QString &key : keys)
        {
            snapshot[key] = jsonValueForVariant(
                SettingsStorage::instance()->loadValue<QVariant>(key));
        }
        QString error;
        if (!Git::GitRepositoryStore::writeFileAtomically(
                QDir(m_settingsStore->rootPath()).filePath(u"settings.json"_s),
                QJsonDocument(snapshot).toJson(QJsonDocument::Indented), &error))
        {
            qCWarning(lcApp) << "Settings journal snapshot write failed:" << error;
            return;
        }
        bool committed = false;
        if (m_settingsStore->commitAll(encodeCommitMessage(
                u"settings: snapshot (auto-commit re-enabled)"_s, {}, JournalOrigin::Snapshot),
                nullptr, &committed, &error)
            && committed)
        {
            emit historyChanged(Repo::Settings);
        }
    }
    emit statusChanged();
}

QString TorrentJournal::retention() const
{
    return SettingsStorage::instance()->loadValue(KeyRetention, u"Forever"_s);
}

void TorrentJournal::setRetention(const QString &retention)
{
    SettingsStorage::instance()->storeValue(KeyRetention, retention);
    emit statusChanged();
}

void TorrentJournal::shutdownFlush()
{
    m_torrentFlushTimer.stop();
    m_settingsFlushTimer.stop();
    if (!m_available)
        return;
    flushTorrentJournal();
    flushSettingsJournal();
}

void TorrentJournal::recordTorrentOp(JournalOpRecord op, const BitTorrent::Torrent *torrent,
    const bool flushImmediately)
{
    if (!m_available || !torrent)
        return;

    const QString torrentId = op.torrentId;

    if (op.kind == JournalOpKind::Config)
    {
        // The catch-all fires alongside every specific mutator; keep only the
        // most specific record for this torrent in the pending batch.
        for (const JournalOpRecord &pending : std::as_const(m_pendingOps))
        {
            if ((pending.torrentId == torrentId) && (pending.kind != JournalOpKind::Config))
                return;
        }
        // Ignore config noise for torrents that are still mid-add: the Add
        // op serializes the complete final state anyway.
        const QString filePath =
            QDir(m_actionStore->rootPath()).filePath(torrentFileRelPath(torrentId));
        if (!QFile::exists(filePath))
            return;
        for (const JournalOpRecord &pending : std::as_const(m_pendingOps))
        {
            if ((pending.torrentId == torrentId) && (pending.kind == JournalOpKind::Config))
            {
                m_dirtyTorrents.insert(torrent->id());
                scheduleTorrentFlush();
                return; // already recorded for this batch
            }
        }
    }
    else
    {
        // A specific op supersedes any pending catch-all record for the torrent.
        m_pendingOps.removeIf([&torrentId](const JournalOpRecord &pending)
        {
            return (pending.torrentId == torrentId) && (pending.kind == JournalOpKind::Config);
        });
    }

    m_pendingOps.append(std::move(op));
    m_dirtyTorrents.insert(torrent->id());

    if (flushImmediately)
        flushTorrentJournal();
    else
        scheduleTorrentFlush();
}

void TorrentJournal::onTorrentAdded(BitTorrent::Torrent *torrent)
{
    if (!m_available)
        return;
    // Keep unrelated pending edits out of the add commit.
    flushTorrentJournal();
    recordTorrentOp({JournalOpKind::Add, torrent->id().toString(), torrent->name(),
        {}, torrent->name()}, torrent, /*flushImmediately=*/true);
}

void TorrentJournal::onTorrentAboutToBeRemoved(BitTorrent::Torrent *torrent,
    const BitTorrent::TorrentRemoveOption removeOption)
{
    if (!m_available)
        return;

    // 1) Land every pending edit (and the torrent's final state) in its own
    //    commit so the delete commit's PARENT holds the complete last state.
    m_dirtyTorrents.insert(torrent->id());
    const bool previousBatchCommitted = flushTorrentJournalImpl();

    // 2) Remove the torrent's files from the working tree and commit that as
    //    the delete entry.
    const QString torrentId = torrent->id().toString();
    const QDir root {m_actionStore->rootPath()};
    QFile::remove(root.filePath(torrentFileRelPath(torrentId)));
    QFile::remove(root.filePath(blobFileRelPath(torrentId)));

    const bool keepContent = (removeOption == BitTorrent::TorrentRemoveOption::KeepContent);
    const JournalOpRecord op {JournalOpKind::Delete, torrentId, torrent->name(),
        torrent->name(), keepContent ? u"kept files"_s : u"deleted files"_s};
    const QString summary = u"delete: "_s + torrent->name()
        + (keepContent ? u" (kept files)"_s : u" (with files)"_s);

    // Never let commitAll() sweep a failed preceding batch into a commit that
    // is labelled only as a deletion. The failed batch has already been put
    // back at the front of m_pendingOps, so append the later delete operation
    // and let the retry preserve their chronological order.
    if (!previousBatchCommitted)
    {
        m_pendingOps.append(op);
        m_torrentFlushTimer.start();
        return;
    }

    if (!commitActions(summary, {op}, currentAnnotationFor({op})))
        requeueActionBatch({op}, {}, false);
}

void TorrentJournal::onSettingsValueChanged(const QString &key, const QVariant &oldValue,
    const QVariant &newValue)
{
    if (!m_available)
        return;
    // The journal's own bookkeeping keys would self-loop.
    if (key.startsWith(u"TorrentJournal/"_s))
        return;
    // Notification history is ephemeral UI history, not configuration. Its
    // JSON blob is rewritten on read/dismiss and must not create a large Git
    // settings commit for every toast.
    if (key == u"GUI/Notifications/HistoryV1"_s)
        return;
    if (!isSettingsAutoCommitEnabled())
        return;

    auto it = m_pendingSettings.find(key);
    if (it == m_pendingSettings.end())
        m_pendingSettings.insert(key, {oldValue, newValue});
    else
        it->newValue = newValue; // keep the earliest old value in the batch
    scheduleSettingsFlush();
}

void TorrentJournal::markSessionDirty(JournalOpRecord op)
{
    if (!m_available)
        return;
    m_sessionDirty = true;
    m_pendingOps.append(std::move(op));
    scheduleTorrentFlush();
}

bool TorrentJournal::writeTorrentFiles(const BitTorrent::Torrent *torrent, bool *changed)
{
    if (changed)
        *changed = false;
    const QString torrentId = torrent->id().toString();
    const QDir root {m_actionStore->rootPath()};
    const QString filePath = root.filePath(torrentFileRelPath(torrentId));

    const QByteArray bytes =
        QJsonDocument(TorrentJournalNS::serializeTorrent(torrent)).toJson(QJsonDocument::Indented);

    QByteArray existing;
    if (QFile existingFile {filePath}; existingFile.open(QIODevice::ReadOnly))
        existing = existingFile.readAll();

    if (existing != bytes)
    {
        QString error;
        if (!Git::GitRepositoryStore::writeFileAtomically(filePath, bytes, &error))
        {
            qCWarning(lcApp) << "Torrent journal write failed for" << torrentId << ":" << error;
            return false;
        }
        if (changed)
            *changed = true;
    }

    // The metadata blob is written once, as soon as it is exportable.
    const QString blobPath = root.filePath(blobFileRelPath(torrentId));
    if (torrent->hasMetadata() && !QFile::exists(blobPath))
    {
        if (const auto result = torrent->exportToBuffer(); result)
        {
            if (result.value().size() <= MaximumBlobBytes)
            {
                QString error;
                if (!Git::GitRepositoryStore::writeFileAtomically(blobPath, result.value(), &error))
                {
                    qCWarning(lcApp) << "Torrent blob write failed for" << torrentId << ":" << error;
                    return false;
                }
                else if (changed)
                    *changed = true;
            }
            else
            {
                qCInfo(lcApp) << "Torrent blob for" << torrentId
                    << "exceeds the size cap; relying on the magnet fallback";
            }
        }
    }
    return true;
}

bool TorrentJournal::writeSessionFile()
{
    const QByteArray bytes = QJsonDocument(
        TorrentJournalNS::serializeSession(BitTorrent::Session::instance()))
        .toJson(QJsonDocument::Indented);
    QString error;
    if (!Git::GitRepositoryStore::writeFileAtomically(
            QDir(m_actionStore->rootPath()).filePath(u"session.json"_s), bytes, &error))
    {
        qCWarning(lcApp) << "Torrent journal session.json write failed:" << error;
        return false;
    }
    return true;
}

void TorrentJournal::scheduleTorrentFlush()
{
    if (!m_scopeActive)
        m_torrentFlushTimer.start();
}

void TorrentJournal::flushTorrentJournal()
{
    (void)flushTorrentJournalImpl();
}

void TorrentJournal::requeueActionBatch(QList<JournalOpRecord> ops,
    QSet<BitTorrent::TorrentID> dirtyTorrents, const bool sessionDirty,
    const bool preserveOps)
{
    // A flush is synchronous today, but prepend the failed snapshot to any
    // work that may have arrived re-entrantly so history remains chronological.
    const bool hasOps = !ops.isEmpty();
    if (hasOps)
    {
        ops.append(m_pendingOps);
        m_pendingOps = std::move(ops);
    }
    m_dirtyTorrents.unite(dirtyTorrents);
    m_sessionDirty = m_sessionDirty || sessionDirty;
    m_preservePendingOps = m_preservePendingOps || (preserveOps && hasOps);

    // This is a retry, not a new user edit. Restart the debounce timer even if
    // the failed flush came from an annotated scope; the event loop normally
    // dispatches it after that synchronous scope has ended.
    m_torrentFlushTimer.start();
}

bool TorrentJournal::flushTorrentJournalImpl()
{
    if (!m_available)
        return false;
    m_torrentFlushTimer.stop();
    if (m_pendingOps.isEmpty() && m_dirtyTorrents.isEmpty() && !m_sessionDirty)
        return true;

    BitTorrent::Session *session = BitTorrent::Session::instance();
    QSet<BitTorrent::TorrentID> dirty = std::exchange(m_dirtyTorrents, {});
    QList<JournalOpRecord> ops = std::exchange(m_pendingOps, {});
    const bool sessionDirty = std::exchange(m_sessionDirty, false);
    const bool preserveOps = std::exchange(m_preservePendingOps, false);

    bool writeSucceeded = true;
    QSet<QString> unchangedIds;
    for (const BitTorrent::TorrentID &id : dirty)
    {
        const BitTorrent::Torrent *torrent = session ? session->getTorrent(id) : nullptr;
        if (!torrent)
            continue; // being removed — the delete handler owns its files
        bool changed = false;
        if (!writeTorrentFiles(torrent, &changed))
            writeSucceeded = false;
        else if (!changed)
            unchangedIds.insert(id.toString());
    }

    if (sessionDirty && !writeSessionFile())
        writeSucceeded = false;

    // Do not create a partial/mislabelled commit when even one required state
    // file failed to reach the worktree. Successful writes are harmless to
    // repeat atomically on the retry.
    if (!writeSucceeded)
    {
        requeueActionBatch(std::move(ops), std::move(dirty), sessionDirty, true);
        return false;
    }

    // Keep the semantic snapshot intact for a retry. Filtering below is only a
    // presentation/noise decision for this commit attempt; it must not destroy
    // records when commitAll() itself fails.
    QList<JournalOpRecord> retryOps = ops;

    // Catch-all records whose serialized state turned out identical are noise
    // only on a first attempt. After any failed write/commit, part or all of the
    // desired state may already be in the worktree; filtering on the retry
    // would incorrectly erase the semantic operation that explains it.
    if (!preserveOps)
    {
        ops.removeIf([&unchangedIds](const JournalOpRecord &op)
        {
            return (op.kind == JournalOpKind::Config) && unchangedIds.contains(op.torrentId);
        });
    }
    if (ops.isEmpty())
    {
        // Still commit silently if files changed without a describable op
        // (should not happen in practice; the no-op check makes this free).
        bool committed = false;
        QString error;
        if (!m_actionStore->commitAll(encodeCommitMessage(u"edit: state sync"_s, {},
                JournalOrigin::User), nullptr, &committed, &error))
        {
            qCWarning(lcApp) << "Torrent journal commit failed:" << error;
            requeueActionBatch(std::move(retryOps), std::move(dirty), sessionDirty, true);
            return false;
        }
        if (committed)
            emit historyChanged(Repo::Actions);
        return true;
    }

    if (!commitActions(buildSummary(ops), ops, currentAnnotationFor(ops)))
    {
        requeueActionBatch(std::move(retryOps), std::move(dirty), sessionDirty, true);
        return false;
    }
    return true;
}

TorrentJournal::Annotation TorrentJournal::currentAnnotationFor(
    const QList<JournalOpRecord> &ops)
{
    if (m_scopeActive)
        return m_scopeAnnotation;

    // Async stragglers of an undo (e.g. the re-add confirmation) inherit the
    // undo annotation via the expectation map.
    const QDateTime now = QDateTime::currentDateTimeUtc();
    for (auto it = m_expectations.begin(); it != m_expectations.end();)
    {
        if (it->expiry < now)
            it = m_expectations.erase(it);
        else
            ++it;
    }
    if (!ops.isEmpty() && !m_expectations.isEmpty())
    {
        const bool allExpected = std::all_of(ops.cbegin(), ops.cend(),
            [this](const JournalOpRecord &op)
        {
            return m_expectations.contains(op.torrentId);
        });
        if (allExpected)
        {
            const Expectation expectation = m_expectations.value(ops.first().torrentId);
            return {expectation.origin, expectation.undoesCommitId, {}, {}};
        }
    }
    return {};
}

QString TorrentJournal::buildSummary(const QList<JournalOpRecord> &ops) const
{
    Q_ASSERT(!ops.isEmpty());
    const JournalOpRecord &first = ops.first();

    QSet<QString> torrentIds;
    bool sameKind = true;
    for (const JournalOpRecord &op : ops)
    {
        if (!op.torrentId.isEmpty())
            torrentIds.insert(op.torrentId);
        sameKind = sameKind && (op.kind == first.kind);
    }
    const int torrentCount = qMax(1, static_cast<int>(torrentIds.size()));
    const QString scopeText = (torrentCount == 1)
        ? first.torrentName
        : u"%1 torrents"_s.arg(torrentCount);

    if (!sameKind)
        return u"edit: %1 changes (%2)"_s.arg(QString::number(ops.size()), scopeText);

    switch (first.kind)
    {
    case JournalOpKind::Add:
        return u"add: "_s + scopeText;
    case JournalOpKind::Delete:
        return u"delete: "_s + scopeText;
    case JournalOpKind::Name:
        return u"edit: renamed '%1' → '%2'"_s.arg(first.oldValue, first.newValue);
    case JournalOpKind::Category:
    {
        const QString target = first.newValue.isEmpty() ? u"(none)"_s : first.newValue;
        return u"edit: category → '%1' (%2)"_s.arg(target, scopeText);
    }
    case JournalOpKind::TagAdd:
        return u"edit: +tag '%1' (%2)"_s.arg(first.newValue, scopeText);
    case JournalOpKind::TagRemove:
        return u"edit: −tag '%1' (%2)"_s.arg(first.oldValue, scopeText);
    case JournalOpKind::SavePath:
        return u"edit: moved %1 → %2"_s.arg(scopeText, first.newValue);
    case JournalOpKind::SavingMode:
        return u"edit: AutoTMM %1 (%2)"_s.arg(first.newValue, scopeText);
    case JournalOpKind::Start:
        return u"start: "_s + scopeText;
    case JournalOpKind::Stop:
        return u"stop: "_s + scopeText;
    case JournalOpKind::Metadata:
        return u"metadata: "_s + scopeText;
    case JournalOpKind::TrackersAdd:
        return u"edit: added %1 (%2)"_s.arg(first.newValue, scopeText);
    case JournalOpKind::TrackersRemove:
        return u"edit: removed %1 (%2)"_s.arg(first.oldValue, scopeText);
    case JournalOpKind::TrackersReset:
        return u"edit: trackers replaced (%1)"_s.arg(scopeText);
    case JournalOpKind::FileRename:
        return u"edit: renamed a file (%1)"_s.arg(scopeText);
    case JournalOpKind::FolderRename:
        return u"edit: renamed a folder (%1)"_s.arg(scopeText);
    case JournalOpKind::SessionCategory:
        if (first.oldValue.isEmpty())
            return u"session: category '%1' added"_s.arg(first.newValue);
        if (first.newValue.isEmpty())
            return u"session: category '%1' removed"_s.arg(first.oldValue);
        return u"session: category '%1' options changed"_s.arg(first.newValue);
    case JournalOpKind::SessionTag:
        if (first.oldValue.isEmpty())
            return u"session: tag '%1' added"_s.arg(first.newValue);
        return u"session: tag '%1' removed"_s.arg(first.oldValue);
    case JournalOpKind::Config:
        return u"edit: options changed (%1)"_s.arg(scopeText);
    default:
        return u"edit: %1 changes (%2)"_s.arg(QString::number(ops.size()), scopeText);
    }
}

bool TorrentJournal::commitActions(const QString &summary, const QList<JournalOpRecord> &ops,
    const Annotation &annotation)
{
    const QString message = encodeCommitMessage(summary, ops, annotation.origin,
        annotation.undoesCommitId, annotation.restoreTargetCommitId);

    QString commitId;
    bool committed = false;
    QString error;
    if (!m_actionStore->commitAll(message, &commitId, &committed, &error))
    {
        qCWarning(lcApp) << "Torrent journal commit failed:" << error;
        return false;
    }

    // Async undo expectations are consumed only after Git accepted the batch.
    // Leaving them intact across a failed commit lets the retry retain the
    // original undo annotation instead of being recorded as a user edit.
    if (!m_scopeActive && (annotation.origin != JournalOrigin::User))
    {
        for (const JournalOpRecord &op : ops)
        {
            const auto it = m_expectations.find(op.torrentId);
            if ((it != m_expectations.end())
                    && (it->origin == annotation.origin)
                    && (it->undoesCommitId == annotation.undoesCommitId))
            {
                m_expectations.erase(it);
            }
        }
    }

    if (!committed)
        return true;

    JournalEntry entry = decodeCommitMessage(message);
    entry.commitId = commitId;
    entry.shortId = commitId.left(8);
    entry.timestamp = QDateTime::currentDateTimeUtc();

    qCInfo(lcApp) << "Torrent journal:" << entry.shortId << summary;
    emit entryCommitted(Repo::Actions, entry);
    emit historyChanged(Repo::Actions);
    emit statusChanged();
    return true;
}

void TorrentJournal::scheduleSettingsFlush()
{
    m_settingsFlushTimer.start();
}

void TorrentJournal::flushSettingsJournal()
{
    if (!m_available || m_pendingSettings.isEmpty())
        return;
    m_settingsFlushTimer.stop();

    const QHash<QString, SettingsChange> changes = std::exchange(m_pendingSettings, {});

    const auto requeueChanges = [this, &changes]
    {
        // The failed snapshot predates anything that arrived re-entrantly.
        // Preserve its earliest old value, while retaining the newer pending
        // value as the eventual state for a key changed again during the flush.
        for (auto it = changes.cbegin(); it != changes.cend(); ++it)
        {
            auto pending = m_pendingSettings.find(it.key());
            if (pending == m_pendingSettings.end())
                m_pendingSettings.insert(it.key(), it.value());
            else
                pending->oldValue = it->oldValue;
        }
        m_settingsFlushTimer.start();
    };

    // Merge the changed keys into the accumulated settings.json.
    const QString filePath = QDir(m_settingsStore->rootPath()).filePath(u"settings.json"_s);
    QJsonObject doc;
    if (QFile file {filePath}; file.open(QIODevice::ReadOnly))
        doc = QJsonDocument::fromJson(file.readAll()).object();
    for (auto it = changes.cbegin(); it != changes.cend(); ++it)
    {
        if (it->newValue.isValid())
            doc[it.key()] = jsonValueForVariant(it->newValue);
        else
            doc.remove(it.key());
    }
    QString error;
    if (!Git::GitRepositoryStore::writeFileAtomically(filePath,
            QJsonDocument(doc).toJson(QJsonDocument::Indented), &error))
    {
        qCWarning(lcApp) << "Settings journal write failed:" << error;
        requeueChanges();
        return;
    }

    QList<JournalOpRecord> ops;
    ops.reserve(changes.size());
    for (auto it = changes.cbegin(); it != changes.cend(); ++it)
    {
        ops.append({JournalOpKind::Config, {}, it.key(),
            displayValue(it->oldValue), displayValue(it->newValue)});
    }
    const QString summary = (changes.size() == 1)
        ? u"%1: %2 → %3"_s.arg(changes.cbegin().key(),
            displayValue(changes.cbegin()->oldValue), displayValue(changes.cbegin()->newValue))
        : u"settings: %1 changes"_s.arg(changes.size());

    const QString message = encodeCommitMessage(summary, ops, JournalOrigin::User);
    QString commitId;
    bool committed = false;
    if (!m_settingsStore->commitAll(message, &commitId, &committed, &error))
    {
        qCWarning(lcApp) << "Settings journal commit failed:" << error;
        requeueChanges();
        return;
    }
    if (!committed)
        return;

    JournalEntry entry = decodeCommitMessage(message);
    entry.commitId = commitId;
    entry.shortId = commitId.left(8);
    entry.timestamp = QDateTime::currentDateTimeUtc();

    qCInfo(lcApp) << "Settings journal:" << entry.shortId << summary;
    emit entryCommitted(Repo::Settings, entry);
    emit historyChanged(Repo::Settings);
    emit statusChanged();
}
