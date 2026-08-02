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

#include "addtorrentcontroller.h"

#include <algorithm>

#include <QLocale>
#include <QJSEngine>
#include <QStringList>

#include "base/bittorrent/downloadpriority.h"
#include "base/bittorrent/infohash.h"
#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/torrentinfo.h"
#include "base/logging.h"
#include "base/preferences.h"
#include "base/torrentfileguard.h"
#include "base/utils/fs.h"
#include "base/utils/misc.h"

using namespace Qt::StringLiterals;

namespace
{
    const QString KEY_SAVE_PATH_HISTORY = u"AddNewTorrentDialog/SavePathHistory"_s;
    const QString KEY_DOWNLOAD_PATH_HISTORY = u"AddNewTorrentDialog/DownloadPathHistory"_s;
    const QString KEY_DEFAULT_CATEGORY = u"AddNewTorrentDialog/DefaultCategory"_s;
    const QString KEY_REMEMBER_LAST_SAVE_PATH = u"AddNewTorrentDialog/RememberLastSavePath"_s;

    constexpr int DEFAULT_HISTORY_LENGTH = 20;

    /// Free space on @p path, walking up to the first existing ancestor.
    qint64 queryFreeDiskSpace(const Path &path)
    {
        if (path.isEmpty())
            return -1;

        const Path root = path.rootItem();
        Path current = path;
        qint64 freeSpace = Utils::Fs::freeDiskSpaceOnPath(current);
        while ((freeSpace < 0) && (current != root))
        {
            current = current.parentPath();
            freeSpace = Utils::Fs::freeDiskSpaceOnPath(current);
        }
        return freeSpace;
    }
}

// ===========================================================================
// AddTorrentFileModel
// ===========================================================================

AddTorrentFileModel::AddTorrentFileModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AddTorrentFileModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_paths.size();
}

QVariant AddTorrentFileModel::data(const QModelIndex &index, const int role) const
{
    const int row = index.row();
    if ((row < 0) || (row >= m_paths.size()))
        return {};

    switch (role)
    {
    case FileNameRole:
        {
            const QString path = m_paths.at(row);
            const int slash = path.lastIndexOf(u'/');
            return (slash >= 0) ? path.mid(slash + 1) : path;
        }
    case FilePathRole:
        return m_paths.at(row);
    case SizeTextRole:
        return Utils::Misc::friendlyUnit(m_sizes.at(row));
    case RawSizeRole:
        return static_cast<qlonglong>(m_sizes.at(row));
    case PriorityRole:
        return m_priorities.at(row);
    case WantedRole:
        return (m_priorities.at(row) != static_cast<int>(BitTorrent::DownloadPriority::Ignored));
    default:
        return {};
    }
}

QHash<int, QByteArray> AddTorrentFileModel::roleNames() const
{
    return {
        {FileNameRole, "fileName"},
        {FilePathRole, "filePath"},
        {SizeTextRole, "sizeText"},
        {RawSizeRole, "rawSize"},
        {PriorityRole, "priority"},
        {WantedRole, "wanted"}
    };
}

void AddTorrentFileModel::reset(const QStringList &paths, const QList<qlonglong> &sizes
        , const QList<int> &priorities)
{
    beginResetModel();
    m_paths = paths;
    m_sizes = sizes;
    m_priorities = priorities;
    m_priorities.resize(m_paths.size(),
            static_cast<int>(BitTorrent::DownloadPriority::Normal));
    endResetModel();
    qCDebug(lcModel) << "AddTorrentFileModel reset:" << m_paths.size() << "file(s)";
    emit wantedSizeChanged();
}

void AddTorrentFileModel::setPriorities(const QList<int> &priorities)
{
    if (priorities.size() != m_priorities.size())
    {
        qCWarning(lcModel) << "AddTorrentFileModel::setPriorities size mismatch"
                           << priorities.size() << "vs" << m_priorities.size();
        return;
    }

    m_priorities = priorities;
    if (!m_paths.isEmpty())
    {
        emit dataChanged(index(0), index(m_paths.size() - 1),
                {PriorityRole, WantedRole});
    }
    emit wantedSizeChanged();
}

qlonglong AddTorrentFileModel::wantedSize() const
{
    qlonglong total = 0;
    for (int i = 0; i < m_priorities.size(); ++i)
    {
        if (m_priorities.at(i) != static_cast<int>(BitTorrent::DownloadPriority::Ignored))
            total += m_sizes.at(i);
    }
    return total;
}

void AddTorrentFileModel::setWanted(const int row, const bool wanted)
{
    if ((row < 0) || (row >= m_priorities.size()))
        return;

    m_priorities[row] = static_cast<int>(wanted
            ? BitTorrent::DownloadPriority::Normal
            : BitTorrent::DownloadPriority::Ignored);
    emit dataChanged(index(row), index(row), {PriorityRole, WantedRole});
    emit wantedSizeChanged();
    qCDebug(lcModel) << "AddTorrentFileModel row" << row << "wanted=" << wanted;
}

void AddTorrentFileModel::setPriority(const int row, const int priority)
{
    if ((row < 0) || (row >= m_priorities.size()))
        return;

    m_priorities[row] = priority;
    emit dataChanged(index(row), index(row), {PriorityRole, WantedRole});
    emit wantedSizeChanged();
    qCDebug(lcModel) << "AddTorrentFileModel row" << row << "priority=" << priority;
}

void AddTorrentFileModel::checkAll()
{
    for (int &p : m_priorities)
    {
        if (p == static_cast<int>(BitTorrent::DownloadPriority::Ignored))
            p = static_cast<int>(BitTorrent::DownloadPriority::Normal);
    }
    if (!m_paths.isEmpty())
        emit dataChanged(index(0), index(m_paths.size() - 1), {PriorityRole, WantedRole});
    emit wantedSizeChanged();
    qCDebug(lcModel) << "AddTorrentFileModel: check all";
}

void AddTorrentFileModel::checkNone()
{
    for (int &p : m_priorities)
        p = static_cast<int>(BitTorrent::DownloadPriority::Ignored);
    if (!m_paths.isEmpty())
        emit dataChanged(index(0), index(m_paths.size() - 1), {PriorityRole, WantedRole});
    emit wantedSizeChanged();
    qCDebug(lcModel) << "AddTorrentFileModel: check none";
}

// ===========================================================================
// AddTorrentController::Context / TorrentContentAdaptor
// ===========================================================================

struct AddTorrentController::Context
{
    QString source;
    BitTorrent::TorrentDescriptor torrentDescr;
    BitTorrent::AddTorrentParams params;
};

/// In-memory content handler used while a torrent is not yet in the session.
///
/// It owns no storage of its own — it operates on the file-path / priority
/// lists held inside the active @c Context's @c AddTorrentParams, exactly like
/// the legacy dialog's adaptor, so content-layout switches and per-file renames
/// are reflected straight into the params that get committed on accept.
class AddTorrentController::TorrentContentAdaptor final
{
public:
    TorrentContentAdaptor(const BitTorrent::TorrentInfo &torrentInfo
            , PathList &filePaths, QList<BitTorrent::DownloadPriority> &filePriorities)
        : m_torrentInfo {torrentInfo}
        , m_filePaths {filePaths}
        , m_filePriorities {filePriorities}
    {
        m_originalRootFolder = Path::findRootFolder(m_torrentInfo.filePaths());
        m_currentContentLayout = (m_originalRootFolder.isEmpty()
                ? BitTorrent::TorrentContentLayout::NoSubfolder
                : BitTorrent::TorrentContentLayout::Subfolder);
    }

    int filesCount() const { return m_torrentInfo.filesCount(); }
    qlonglong fileSize(const int index) const { return m_torrentInfo.fileSize(index); }

    Path filePath(const int index) const
    {
        return m_filePaths.isEmpty() ? m_torrentInfo.filePath(index) : m_filePaths.at(index);
    }

    PathList filePaths() const
    {
        return m_filePaths.isEmpty() ? m_torrentInfo.filePaths() : m_filePaths;
    }

    QList<BitTorrent::DownloadPriority> filePriorities() const { return m_filePriorities; }

    void renameFile(const int index, const Path &newFilePath)
    {
        if ((index < 0) || (index >= filesCount()))
            return;
        if (m_filePaths.isEmpty())
            m_filePaths = m_torrentInfo.filePaths();
        m_filePaths[index] = newFilePath;
    }

    /// Re-derive @c m_filePaths for the requested layout (mirrors legacy logic).
    void applyContentLayout(const BitTorrent::TorrentContentLayout contentLayout)
    {
        if (m_filePaths.isEmpty())
            m_filePaths = m_torrentInfo.filePaths();

        const auto originalLayout = (m_originalRootFolder.isEmpty()
                ? BitTorrent::TorrentContentLayout::NoSubfolder
                : BitTorrent::TorrentContentLayout::Subfolder);
        const auto newLayout = ((contentLayout == BitTorrent::TorrentContentLayout::Original)
                ? originalLayout : contentLayout);
        if (newLayout == m_currentContentLayout)
            return;

        if (newLayout == BitTorrent::TorrentContentLayout::NoSubfolder)
        {
            Path::stripRootFolder(m_filePaths);
        }
        else
        {
            const Path rootFolder = ((originalLayout == BitTorrent::TorrentContentLayout::Subfolder)
                    ? m_originalRootFolder : m_filePaths.at(0).removedExtension());
            Path::addRootFolder(m_filePaths, rootFolder);
        }
        m_currentContentLayout = newLayout;
    }

private:
    const BitTorrent::TorrentInfo &m_torrentInfo;
    PathList &m_filePaths;
    QList<BitTorrent::DownloadPriority> &m_filePriorities;
    Path m_originalRootFolder;
    BitTorrent::TorrentContentLayout m_currentContentLayout;
};

// ===========================================================================
// AddTorrentController
// ===========================================================================

AddTorrentController *AddTorrentController::s_instance = nullptr;

AddTorrentController *AddTorrentController::create(QQmlEngine *, QJSEngine *)
{
    AddTorrentController *controller = instance();
    QJSEngine::setObjectOwnership(controller, QJSEngine::CppOwnership);
    return controller;
}

AddTorrentController *AddTorrentController::instance()
{
    if (!s_instance)
        s_instance = new AddTorrentController;
    return s_instance;
}

AddTorrentController::AddTorrentController(QObject *parent)
    : QObject(parent)
    , m_session {BitTorrent::Session::instance()}
    , m_fileModel {new AddTorrentFileModel(this)}
{
    connect(m_fileModel, &AddTorrentFileModel::wantedSizeChanged, this, [this]
    {
        // Refresh the size label against the currently-selected save path.
        updateSizeText(m_initialValues.value(u"savePath"_s).toString());
    });
    qCDebug(lcUi) << "AddTorrentController constructed";
}

AddTorrentController::~AddTorrentController() = default;

bool AddTorrentController::hasMetadata() const
{
    return m_context && m_context->torrentDescr.info().has_value();
}

QString AddTorrentController::source() const
{
    return m_context ? m_context->source : QString();
}

QString AddTorrentController::torrentName() const
{
    if (!m_context)
        return {};
    const QString name = m_context->torrentDescr.name();
    return name.isEmpty() ? tr("Magnet link") : name;
}

QString AddTorrentController::comment() const
{
    if (!hasMetadata())
        return tr("Not Available", "This comment is unavailable");
    return m_context->torrentDescr.comment();
}

QString AddTorrentController::creationDate() const
{
    if (!hasMetadata())
        return tr("Not Available", "This date is unavailable");
    const QDateTime date = m_context->torrentDescr.creationDate();
    return date.isNull() ? tr("Not available")
            : QLocale().toString(date, QLocale::ShortFormat);
}

QString AddTorrentController::infoHashV1() const
{
    if (!m_context)
        return {};
    const auto v1 = m_context->torrentDescr.infoHash().v1();
    return v1.isValid() ? v1.toString() : tr("N/A");
}

QString AddTorrentController::infoHashV2() const
{
    if (!m_context)
        return {};
    const auto v2 = m_context->torrentDescr.infoHash().v2();
    return v2.isValid() ? v2.toString() : tr("N/A");
}

bool AddTorrentController::canSaveTorrentFile() const
{
    // v2 torrents cannot be exported until their data is fully downloaded.
    return hasMetadata() && !m_context->torrentDescr.infoHash().v2().isValid();
}

QStringList AddTorrentController::categories() const
{
    if (!m_session)
        return {};
    QStringList result = m_session->categories();
    std::sort(result.begin(), result.end());
    result.prepend(QString()); // uncategorized
    return result;
}

QStringList AddTorrentController::savePathHistory() const
{
    QStringList history = Preferences::instance()
            ->value(KEY_SAVE_PATH_HISTORY, {}).toStringList();
    if (history.isEmpty() && m_session)
        history.append(m_session->savePath().toString());
    return history;
}

QStringList AddTorrentController::downloadPathHistory() const
{
    QStringList history = Preferences::instance()
            ->value(KEY_DOWNLOAD_PATH_HISTORY, {}).toStringList();
    if (history.isEmpty() && m_session)
        history.append(m_session->downloadPath().toString());
    return history;
}

const BitTorrent::TorrentDescriptor &AddTorrentController::currentDescriptor() const
{
    static const BitTorrent::TorrentDescriptor empty;
    return m_context ? m_context->torrentDescr : empty;
}

void AddTorrentController::present(const QString &source
        , const BitTorrent::TorrentDescriptor &torrentDescr
        , const BitTorrent::AddTorrentParams &inParams, const bool doNotDeleteVisible)
{
    qCInfo(lcUi) << "AddTorrentController: presenting dialog for" << source;

    m_context = std::make_shared<Context>(Context {source, torrentDescr, inParams});
    m_doNotDeleteVisible = doNotDeleteVisible;
    m_contentAdaptor.reset();

    resolveInitialValues();
    rebuildContentModel();

    if (hasMetadata())
    {
        setMetadataStatus(false, {});
    }
    else
    {
        setMetadataStatus(true, tr("Retrieving metadata..."));
    }

    emit contextChanged();
    emit dialogRequested();
}

void AddTorrentController::resolveInitialValues()
{
    Q_ASSERT(m_context);
    const BitTorrent::AddTorrentParams &p = m_context->params;
    const auto *session = m_session;

    QVariantMap v;
    v.insert(u"useAutoTMM"_s,
            p.useAutoTMM.value_or(session && !session->isAutoTMMDisabledByDefault()));
    v.insert(u"savePath"_s, p.savePath.isEmpty()
            ? (session ? session->savePath().toString() : QString())
            : p.savePath.toString());
    v.insert(u"useDownloadPath"_s,
            p.useDownloadPath.value_or(session && session->isDownloadPathEnabled()));
    v.insert(u"downloadPath"_s, p.downloadPath.isEmpty()
            ? (session ? session->downloadPath().toString() : QString())
            : p.downloadPath.toString());
    v.insert(u"category"_s, p.category.isEmpty()
            ? Preferences::instance()->value(KEY_DEFAULT_CATEGORY, {}).toString()
            : p.category);

    QStringList tags;
    for (const auto &tag : p.tags)
        tags.append(tag.toString());
    v.insert(u"tags"_s, tags);

    v.insert(u"startTorrent"_s,
            !p.addStopped.value_or(session && session->isAddTorrentStopped()));
    v.insert(u"addToQueueTop"_s,
            p.addToQueueTop.value_or(session && session->isAddTorrentToQueueTop()));
    v.insert(u"skipChecking"_s, p.skipChecking);
    v.insert(u"sequential"_s, p.sequential);
    v.insert(u"firstLastPiece"_s, p.firstLastPiecePriority);
    v.insert(u"contentLayout"_s, static_cast<int>(p.contentLayout.value_or(
            session ? session->torrentContentLayout()
                    : BitTorrent::TorrentContentLayout::Original)));
    v.insert(u"stopCondition"_s, static_cast<int>(p.stopCondition.value_or(
            session ? session->torrentStopCondition()
                    : BitTorrent::Torrent::StopCondition::None)));
    v.insert(u"rememberSavePath"_s,
            Preferences::instance()->value(KEY_REMEMBER_LAST_SAVE_PATH, false).toBool());

    m_initialValues = v;
}

void AddTorrentController::rebuildContentModel()
{
    Q_ASSERT(m_context);
    if (!hasMetadata())
    {
        m_fileModel->reset({}, {}, {});
        return;
    }

    const auto &torrentInfo = *m_context->torrentDescr.info();
    BitTorrent::AddTorrentParams &params = m_context->params;

    if (params.filePaths.isEmpty())
        params.filePaths = torrentInfo.filePaths();
    if (params.filePriorities.isEmpty())
    {
        params.filePriorities = QList<BitTorrent::DownloadPriority>(
                torrentInfo.filesCount(), BitTorrent::DownloadPriority::Normal);
    }

    m_contentAdaptor = std::make_unique<TorrentContentAdaptor>(
            torrentInfo, params.filePaths, params.filePriorities);

    // Apply the selected content layout before populating the tree.
    const auto layout = static_cast<BitTorrent::TorrentContentLayout>(
            m_initialValues.value(u"contentLayout"_s).toInt());
    m_contentAdaptor->applyContentLayout(layout);

    // Honour the session filename blacklist for manually-added torrents.
    if (m_session && m_session->isExcludedFileNamesEnabled())
    {
        QList<BitTorrent::DownloadPriority> priorities = m_contentAdaptor->filePriorities();
        m_session->applyFilenameFilter(m_contentAdaptor->filePaths(), priorities);
        params.filePriorities = priorities;
    }

    QStringList paths;
    QList<qlonglong> sizes;
    QList<int> priorities;
    const int count = m_contentAdaptor->filesCount();
    paths.reserve(count);
    sizes.reserve(count);
    priorities.reserve(count);
    for (int i = 0; i < count; ++i)
    {
        paths.append(m_contentAdaptor->filePath(i).toString());
        sizes.append(m_contentAdaptor->fileSize(i));
        priorities.append(static_cast<int>(params.filePriorities.value(
                i, BitTorrent::DownloadPriority::Normal)));
    }
    m_fileModel->reset(paths, sizes, priorities);
}

void AddTorrentController::updateMetadata(const BitTorrent::TorrentInfo &metadata)
{
    if (!m_context || !metadata.isValid())
        return;
    if (!metadata.matchesInfoHash(m_context->torrentDescr.infoHash()))
        return;

    qCInfo(lcUi) << "AddTorrentController: metadata received for" << m_context->source;
    setMetadataStatus(true, tr("Parsing metadata..."));
    m_context->torrentDescr.setTorrentInfo(metadata);
    rebuildContentModel();
    setMetadataStatus(false, tr("Metadata retrieval complete"));
    emit contextChanged();
}

void AddTorrentController::applyContentLayout(const int contentLayout)
{
    if (!m_contentAdaptor)
        return;

    qCDebug(lcUi) << "AddTorrentController: content layout ->" << contentLayout;
    m_contentAdaptor->applyContentLayout(
            static_cast<BitTorrent::TorrentContentLayout>(contentLayout));
    m_initialValues.insert(u"contentLayout"_s, contentLayout);

    const int count = m_contentAdaptor->filesCount();
    QStringList paths;
    QList<qlonglong> sizes;
    QList<int> priorities;
    for (int i = 0; i < count; ++i)
    {
        paths.append(m_contentAdaptor->filePath(i).toString());
        sizes.append(m_contentAdaptor->fileSize(i));
        priorities.append(m_fileModel->priorities().value(i,
                static_cast<int>(BitTorrent::DownloadPriority::Normal)));
    }
    m_fileModel->reset(paths, sizes, priorities);
}

void AddTorrentController::updateSizeText(const QString &savePath)
{
    const qlonglong wanted = m_fileModel->wantedSize();
    const QString wantedStr = (wanted > 0)
            ? Utils::Misc::friendlyUnit(wanted)
            : tr("Not available", "This size is unavailable.");
    const QString freeStr = Utils::Misc::friendlyUnit(queryFreeDiskSpace(Path(savePath)));
    setSizeText(tr("%1 (Free space on disk: %2)").arg(wantedStr, freeStr));
}

QVariantMap AddTorrentController::categoryPaths(const QString &category) const
{
    QVariantMap result;
    if (!m_session)
        return result;

    const Path savePath = m_session->categorySavePath(category);
    const Path downloadPath = m_session->categoryDownloadPath(category);
    result.insert(u"savePath"_s, savePath.toString());
    result.insert(u"downloadPath"_s, downloadPath.toString());
    result.insert(u"useDownloadPath"_s, !downloadPath.isEmpty());
    return result;
}

void AddTorrentController::renameFile(const int row, const QString &newPath)
{
    if (!m_contentAdaptor)
        return;

    m_contentAdaptor->renameFile(row, Path(newPath));
    m_fileModel->reset(
            [this] {
                QStringList paths;
                for (int i = 0; i < m_contentAdaptor->filesCount(); ++i)
                    paths.append(m_contentAdaptor->filePath(i).toString());
                return paths;
            }(),
            [this] {
                QList<qlonglong> sizes;
                for (int i = 0; i < m_contentAdaptor->filesCount(); ++i)
                    sizes.append(m_contentAdaptor->fileSize(i));
                return sizes;
            }(),
            m_fileModel->priorities());
    qCDebug(lcUi) << "AddTorrentController: renamed file" << row << "->" << newPath;
}

bool AddTorrentController::saveTorrentFile(const QString &filePath)
{
    if (!hasMetadata() || filePath.isEmpty())
        return false;

    Path path {filePath};
    if (!path.hasExtension(u".torrent"_s))
        path += u".torrent"_s;

    const auto result = m_context->torrentDescr.saveToFile(path);
    if (!result)
    {
        qCWarning(lcUi) << "AddTorrentController: failed to export torrent file"
                       << path.toString() << ':' << result.error();
        return false;
    }
    qCInfo(lcUi) << "AddTorrentController: exported torrent file" << path.toString();
    return true;
}

void AddTorrentController::accept(const QVariantMap &values)
{
    if (!m_context)
        return;

    qCInfo(lcUi) << "AddTorrentController: accepted" << m_context->source;

    BitTorrent::AddTorrentParams &params = m_context->params;

    const bool useAutoTMM = values.value(u"useAutoTMM"_s).toBool();
    params.useAutoTMM = useAutoTMM;

    if (!useAutoTMM)
    {
        const QString savePath = values.value(u"savePath"_s).toString();
        params.savePath = Path(savePath);
        pushSavePathHistory(KEY_SAVE_PATH_HISTORY, savePath);

        const bool useDownloadPath = values.value(u"useDownloadPath"_s).toBool();
        params.useDownloadPath = useDownloadPath;
        if (useDownloadPath)
        {
            const QString downloadPath = values.value(u"downloadPath"_s).toString();
            params.downloadPath = Path(downloadPath);
            pushSavePathHistory(KEY_DOWNLOAD_PATH_HISTORY, downloadPath);
        }
        else
        {
            params.downloadPath = Path();
        }
    }
    else
    {
        params.savePath = Path();
        params.downloadPath = Path();
        params.useDownloadPath = std::nullopt;
    }

    params.category = values.value(u"category"_s).toString();
    if (values.value(u"setDefaultCategory"_s).toBool())
        Preferences::instance()->setValue(KEY_DEFAULT_CATEGORY, params.category);

    TagSet tags;
    const QStringList tagList = values.value(u"tags"_s).toStringList();
    for (const QString &tag : tagList)
    {
        const QString trimmed = tag.trimmed();
        if (!trimmed.isEmpty())
            tags.insert(Tag(trimmed));
    }
    params.tags = tags;

    params.addStopped = !values.value(u"startTorrent"_s).toBool();
    params.addToQueueTop = values.value(u"addToQueueTop"_s).toBool();
    params.skipChecking = values.value(u"skipChecking"_s).toBool();
    params.sequential = values.value(u"sequential"_s).toBool();
    params.firstLastPiecePriority = values.value(u"firstLastPiece"_s).toBool();
    params.contentLayout = static_cast<BitTorrent::TorrentContentLayout>(
            values.value(u"contentLayout"_s).toInt());
    params.stopCondition = static_cast<BitTorrent::Torrent::StopCondition>(
            values.value(u"stopCondition"_s).toInt());

    // Commit the possibly-edited per-file priorities from the content tree.
    if (hasMetadata())
    {
        const QList<int> pris = m_fileModel->priorities();
        QList<BitTorrent::DownloadPriority> filePriorities;
        filePriorities.reserve(pris.size());
        for (const int p : pris)
            filePriorities.append(static_cast<BitTorrent::DownloadPriority>(p));
        params.filePriorities = filePriorities;
    }

    Preferences::instance()->setValue(KEY_REMEMBER_LAST_SAVE_PATH,
            values.value(u"rememberSavePath"_s, false).toBool());

    // "Never show the dialog again" preference.
    if (values.contains(u"neverShowAgain"_s))
    {
        Preferences::instance()->setValue(u"AddNewTorrentDialog/Enabled"_s,
                !values.value(u"neverShowAgain"_s).toBool());
    }

    m_lastDoNotDelete = values.value(u"doNotDelete"_s, false).toBool();
    m_builtParams = params;

    const QString source = m_context->source;
    emit torrentAccepted(source);

    m_context.reset();
    m_contentAdaptor.reset();
    emit contextChanged();
}

void AddTorrentController::reject()
{
    if (!m_context)
        return;

    qCInfo(lcUi) << "AddTorrentController: rejected" << m_context->source;
    const QString source = m_context->source;

    // The preview handle remains temporary even after metadata arrives. Always
    // cancel it when the dialog is rejected so it cannot leak into the native
    // session or block a later add of the same magnet.
    if (m_session)
    {
        m_session->cancelDownloadMetadata(
                m_context->torrentDescr.infoHash().toTorrentID());
    }

    emit torrentRejected(source);

    m_context.reset();
    m_contentAdaptor.reset();
    emit contextChanged();
}

void AddTorrentController::setMetadataStatus(const bool inProgress, const QString &text)
{
    if ((m_metadataInProgress == inProgress) && (m_metadataStatusText == text))
        return;
    m_metadataInProgress = inProgress;
    m_metadataStatusText = text;
    emit metadataStatusChanged();
}

void AddTorrentController::setSizeText(const QString &text)
{
    if (m_sizeText == text)
        return;
    m_sizeText = text;
    emit sizeTextChanged();
}

void AddTorrentController::pushSavePathHistory(const QString &key, const QString &path)
{
    if (path.isEmpty())
        return;

    auto *pref = Preferences::instance();
    QStringList history = pref->value(key, {}).toStringList();
    const int existing = history.indexOf(path);
    if (existing > -1)
        history.move(existing, 0);
    else
        history.prepend(path);

    const int maxLength = pref->value(
            u"AddNewTorrentDialog/SavePathHistoryLength"_s, DEFAULT_HISTORY_LENGTH).toInt();
    if (history.size() > maxLength)
        history = history.mid(0, maxLength);

    pref->setValue(key, history);
    qCDebug(lcUi) << "AddTorrentController: save-path history updated (" << key << ")";
}
