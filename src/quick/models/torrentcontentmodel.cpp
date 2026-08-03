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

#include "torrentcontentmodel.h"

#include <algorithm>
#include <exception>

#include <QFuture>
#include <QModelIndex>
#include <QSet>
#include <QVariant>

#include "base/bittorrent/torrentcontenthandler.h"
#include "base/logging.h"
#include "base/utils/misc.h"
#include "base/utils/string.h"

using namespace Qt::StringLiterals;
using BitTorrent::DownloadPriority;

// ===========================================================================
//  ContentNode — the internal file/folder tree node
// ===========================================================================

/**
 * @brief One node of the content tree (a file or a folder).
 *
 * Folders aggregate the size/progress/remaining/availability of their children
 * and propagate priority changes both up (recompute parent → possibly Mixed)
 * and down (a non-Mixed folder pushes its priority to every child). This mirrors
 * the tri-state checkbox semantics of the legacy Qt-Widgets model.
 */
class ContentNode final
{
    Q_DISABLE_COPY_MOVE(ContentNode)

public:
    explicit ContentNode(const bool folder)
        : m_isFolder {folder}
    {
    }

    ~ContentNode()
    {
        qDeleteAll(m_children);
    }

    bool isFolder() const { return m_isFolder; }
    bool isRoot() const { return (m_parent == nullptr); }

    ContentNode *parent() const { return m_parent; }
    const QList<ContentNode *> &children() const { return m_children; }
    ContentNode *child(const int row) const { return m_children.value(row, nullptr); }
    int childCount() const { return static_cast<int>(m_children.size()); }

    int row() const
    {
        return m_parent ? static_cast<int>(m_parent->m_children.indexOf(const_cast<ContentNode *>(this))) : 0;
    }

    void appendChild(ContentNode *node)
    {
        m_children.append(node);
        node->m_parent = this;
        if (!node->m_isFolder)
            increaseSize(node->m_size);
    }

    void removeChild(ContentNode *node)
    {
        if (m_children.removeOne(node))
        {
            if (!node->m_isFolder)
                decreaseSize(node->m_size);
            node->m_parent = nullptr;
        }
    }

    QString name() const { return m_name; }
    void setName(const QString &name) { m_name = name; }

    quint64 size() const { return m_size; }
    void setSize(const quint64 size) { m_size = size; }
    int fileIndex() const { return m_fileIndex; }
    void setFileIndex(const int index) { m_fileIndex = index; }

    qreal progress() const { return (m_size > 0) ? m_progress : 1.0; }
    quint64 remaining() const { return (m_priority == DownloadPriority::Ignored) ? 0 : m_remaining; }
    qreal availability() const { return (m_size > 0) ? m_availability : 0; }

    void setProgress(const qreal progress)
    {
        m_progress = progress;
        m_remaining = static_cast<quint64>(m_size * (1.0 - m_progress));
    }

    void setAvailability(const qreal availability) { m_availability = availability; }

    DownloadPriority priority() const { return m_priority; }

    void setPriority(const DownloadPriority newPriority, const bool updateParent = true)
    {
        if (m_priority == newPriority)
            return;

        m_priority = newPriority;

        // Recompute the parent chain (root's updatePriority() is a no-op).
        if (updateParent && m_parent)
            m_parent->updatePriority();

        // A folder with a definite priority forces it onto every child.
        if (m_isFolder && (m_priority != DownloadPriority::Mixed))
        {
            for (ContentNode *child : std::as_const(m_children))
                child->setPriority(m_priority, false);
        }
    }

    void updatePriority()
    {
        if (isRoot() || m_children.isEmpty())
            return;

        const DownloadPriority prio = m_children.constFirst()->priority();
        for (qsizetype i = 1; i < m_children.size(); ++i)
        {
            if (m_children.at(i)->priority() != prio)
            {
                setPriority(DownloadPriority::Mixed);
                return;
            }
        }
        setPriority(prio);
    }

    void recalculateProgress()
    {
        if (!m_isFolder)
            return;

        qreal totalProgress = 0;
        quint64 totalSize = 0;
        quint64 totalRemaining = 0;
        for (ContentNode *child : std::as_const(m_children))
        {
            if (child->priority() == DownloadPriority::Ignored)
                continue;

            if (child->m_isFolder)
                child->recalculateProgress();

            totalProgress += child->progress() * child->size();
            totalSize += child->size();
            totalRemaining += child->remaining();
        }

        if (!isRoot())
        {
            if (totalSize > 0)
            {
                m_progress = totalProgress / totalSize;
                m_remaining = totalRemaining;
            }
            else
            {
                m_progress = 1.0;
                m_remaining = 0;
            }
        }
    }

    void recalculateAvailability()
    {
        if (!m_isFolder)
            return;

        qreal totalAvailability = 0;
        quint64 totalSize = 0;
        bool foundAnyData = false;
        for (ContentNode *child : std::as_const(m_children))
        {
            if (child->priority() == DownloadPriority::Ignored)
                continue;

            if (child->m_isFolder)
                child->recalculateAvailability();

            const qreal childAvailability = child->availability();
            if (childAvailability >= 0) // -1 means "no data"
            {
                totalAvailability += childAvailability * child->size();
                foundAnyData = true;
            }
            totalSize += child->size();
        }

        if (!isRoot() && (totalSize > 0) && foundAnyData)
            m_availability = totalAvailability / totalSize;
        else
            m_availability = -1;
    }

    /// Qt::CheckState derived from priority (tri-state for Mixed folders).
    Qt::CheckState checkState() const
    {
        if (m_priority == DownloadPriority::Ignored)
            return Qt::Unchecked;

        if (m_priority == DownloadPriority::Mixed)
        {
            const bool hasIgnored = std::ranges::any_of(m_children, [](const ContentNode *child)
            {
                const DownloadPriority prio = child->priority();
                return (prio == DownloadPriority::Ignored) || (prio == DownloadPriority::Mixed);
            });
            return hasIgnored ? Qt::PartiallyChecked : Qt::Checked;
        }

        return Qt::Checked;
    }

private:
    void increaseSize(const quint64 delta)
    {
        if (isRoot())
            return;
        m_size += delta;
        if (m_parent)
            m_parent->increaseSize(delta);
    }

    void decreaseSize(const quint64 delta)
    {
        if (isRoot())
            return;
        m_size -= delta;
        if (m_parent)
            m_parent->decreaseSize(delta);
    }

    bool m_isFolder = false;
    ContentNode *m_parent = nullptr;
    QList<ContentNode *> m_children;
    QString m_name;
    quint64 m_size = 0;
    quint64 m_remaining = 0;
    int m_fileIndex = -1;
    DownloadPriority m_priority = DownloadPriority::Normal;
    qreal m_progress = 0;
    qreal m_availability = -1;
};

namespace
{
    /// Minimal single-node name validation (no path separators, non-empty).
    /// The engine performs the authoritative filesystem validation on rename.
    bool isValidNodeName(const QString &name)
    {
        return !name.isEmpty() && !name.contains(u'/') && !name.contains(u'\\');
    }

    QString priorityLabel(const DownloadPriority priority)
    {
        switch (priority)
        {
        case DownloadPriority::Mixed:
            return TorrentContentModel::tr("Mixed", "Mixed (priorities)");
        case DownloadPriority::Ignored:
            return TorrentContentModel::tr("Do not download", "Do not download (priority)");
        case DownloadPriority::High:
            return TorrentContentModel::tr("High", "High (priority)");
        case DownloadPriority::Maximum:
            return TorrentContentModel::tr("Maximum", "Maximum (priority)");
        default:
            return TorrentContentModel::tr("Normal", "Normal (priority)");
        }
    }
}

// ===========================================================================
//  TorrentContentModel
// ===========================================================================

TorrentContentModel::TorrentContentModel(QObject *parent)
    : QAbstractItemModel(parent)
    , m_rootNode {new ContentNode(true)}
{
    m_nodeByPath.insert(Path(), m_rootNode);
    qCDebug(lcModel) << "TorrentContentModel constructed";
}

TorrentContentModel::~TorrentContentModel()
{
    delete m_rootNode;
    qCDebug(lcModel) << "TorrentContentModel destroyed";
}

int TorrentContentModel::columnCount([[maybe_unused]] const QModelIndex &parent) const
{
    // Single logical column: QML lays out the "columns" inside the row delegate.
    return 1;
}

int TorrentContentModel::rowCount(const QModelIndex &parent) const
{
    const ContentNode *parentNode = parent.isValid() ? nodeForIndex(parent) : m_rootNode;
    return (parentNode && parentNode->isFolder()) ? parentNode->childCount() : 0;
}

QModelIndex TorrentContentModel::index(const int row, const int column, const QModelIndex &parent) const
{
    if ((column != 0) || (row < 0))
        return {};

    const ContentNode *parentNode = parent.isValid() ? nodeForIndex(parent) : m_rootNode;
    if (!parentNode || (row >= parentNode->childCount()))
        return {};

    ContentNode *childNode = parentNode->child(row);
    return childNode ? createIndex(row, column, childNode) : QModelIndex {};
}

QModelIndex TorrentContentModel::parent(const QModelIndex &index) const
{
    if (!index.isValid())
        return {};

    const ContentNode *node = nodeForIndex(index);
    if (!node)
        return {};

    ContentNode *parentNode = node->parent();
    if (!parentNode || (parentNode == m_rootNode))
        return {};

    return createIndex(parentNode->row(), 0, parentNode);
}

QVariant TorrentContentModel::data(const QModelIndex &index, const int role) const
{
    const ContentNode *node = nodeForIndex(index);
    if (!node)
        return {};

    switch (role)
    {
    case Qt::DisplayRole:
    case NameRole:
        return node->name();
    case SizeRole:
        return Utils::Misc::friendlyUnit(static_cast<qint64>(node->size()));
    case SizeValueRole:
        return static_cast<qulonglong>(node->size());
    case ProgressRole:
        return node->progress();
    case ProgressTextRole:
        return (node->progress() >= 1)
                ? u"100%"_s
                : (Utils::String::fromDouble((node->progress() * 100), 1) + u'%');
    case PriorityRole:
        return static_cast<int>(node->priority());
    case PriorityTextRole:
        return priorityLabel(node->priority());
    case RemainingRole:
        return Utils::Misc::friendlyUnit(static_cast<qint64>(node->remaining()));
    case RemainingValueRole:
        return static_cast<qulonglong>(node->remaining());
    case AvailabilityRole:
        {
            const qreal avail = node->availability();
            if (avail < 0)
                return tr("N/A");
            const QString value = (avail >= 1) ? u"100"_s : Utils::String::fromDouble((avail * 100), 1);
            return QString(value + u'%');
        }
    case AvailabilityValueRole:
        return node->availability();
    case CheckStateRole:
        return static_cast<int>(node->checkState());
    case IsFolderRole:
        return node->isFolder();
    case FileIndexRole:
        return node->fileIndex();
    default:
        return {};
    }
}

Qt::ItemFlags TorrentContentModel::flags(const QModelIndex &index) const
{
    if (!index.isValid())
        return Qt::NoItemFlags;
    return {Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsUserCheckable};
}

QHash<int, QByteArray> TorrentContentModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {SizeRole, "size"},
        {SizeValueRole, "sizeValue"},
        {ProgressRole, "progress"},
        {ProgressTextRole, "progressText"},
        {PriorityRole, "priority"},
        {PriorityTextRole, "priorityText"},
        {RemainingRole, "remaining"},
        {RemainingValueRole, "remainingValue"},
        {AvailabilityRole, "availability"},
        {AvailabilityValueRole, "availabilityValue"},
        {CheckStateRole, "checkState"},
        {IsFolderRole, "isFolder"},
        {FileIndexRole, "fileIndex"}
    };
}

// ---- Property accessors ----------------------------------------------------

QObject *TorrentContentModel::contentHandlerObject() const
{
    return m_contentHandler.data();
}

void TorrentContentModel::setContentHandlerObject(QObject *handler)
{
    auto *contentHandler = qobject_cast<BitTorrent::TorrentContentHandler *>(handler);
    if ((handler != nullptr) && (contentHandler == nullptr))
        qCWarning(lcModel) << "TorrentContentModel: assigned object is not a TorrentContentHandler";
    setContentHandler(contentHandler);
}

bool TorrentContentModel::metadataReady() const
{
    return m_metadataReady;
}

int TorrentContentModel::fileCount() const
{
    return static_cast<int>(m_filesIndex.size());
}

BitTorrent::TorrentContentHandler *TorrentContentModel::contentHandler() const
{
    return m_contentHandler.data();
}

void TorrentContentModel::setContentHandler(BitTorrent::TorrentContentHandler *contentHandler)
{
    if (m_contentHandler == contentHandler)
        return;

    qCInfo(lcModel) << "TorrentContentModel: binding content handler" << static_cast<void *>(contentHandler);

    beginResetModel();

    if (m_contentHandler)
        m_contentHandler->disconnect(this);

    // Tear down the previous tree.
    delete m_rootNode;
    m_rootNode = new ContentNode(true);
    m_filesIndex.clear();
    m_nodeByPath.clear();
    m_nodeByPath.insert(Path(), m_rootNode);
    m_metadataReady = false;

    m_contentHandler = contentHandler;

    if (m_contentHandler)
    {
        if (m_contentHandler->hasMetadata())
            populate();
        else
            connect(m_contentHandler, &BitTorrent::TorrentContentHandler::metadataReceived
                    , this, &TorrentContentModel::onMetadataReceived);

        connect(m_contentHandler, &BitTorrent::TorrentContentHandler::fileRenamed
                , this, &TorrentContentModel::onFileRenamed);
        connect(m_contentHandler, &BitTorrent::TorrentContentHandler::folderRenamed
                , this, &TorrentContentModel::onFolderRenamed);
        connect(m_contentHandler, &BitTorrent::TorrentContentHandler::folderRenamingFailed
                , this, &TorrentContentModel::onFolderRenamingFailed);
        connect(m_contentHandler, &QObject::destroyed, this, [this]
        {
            qCDebug(lcModel) << "TorrentContentModel: content handler destroyed, clearing";
            setContentHandler(nullptr);
        });
    }

    endResetModel();

    emit contentHandlerChanged();
    emit metadataReadyChanged();
}

// ---- Tree population -------------------------------------------------------

void TorrentContentModel::populate()
{
    if (!m_contentHandler || !m_contentHandler->hasMetadata())
        return;

    const int filesCount = m_contentHandler->filesCount();
    qCDebug(lcModel) << "TorrentContentModel: populating" << filesCount << "files";
    m_filesIndex.reserve(filesCount);

    ContentNode *lastParentFolder = m_rootNode;
    for (int i = 0; i < filesCount; ++i)
    {
        const Path filePath = m_contentHandler->filePath(i);
        const Path parentFolderPath = filePath.parentPath();
        auto *parentFolder = m_nodeByPath.value(parentFolderPath);
        if (lastParentFolder != parentFolder)
        {
            if (!parentFolder)
                parentFolder = populateFolder(parentFolderPath, true);
            lastParentFolder = parentFolder;
        }

        auto *fileNode = new ContentNode(false);
        fileNode->setName(filePath.filename());
        fileNode->setSize(static_cast<quint64>(std::max<qlonglong>(0, m_contentHandler->fileSize(i))));
        fileNode->setFileIndex(i);
        lastParentFolder->appendChild(fileNode);
        m_filesIndex.push_back(fileNode);
        m_nodeByPath.insert(filePath, fileNode);
    }

    updateFilesProgress();
    updateFilesPriorities();
    updateFilesAvailability();

    m_metadataReady = true;
}

ContentNode *TorrentContentModel::populateFolder(const Path &folderPath, const bool suppressNotify)
{
    ContentNode *currentFolder = m_rootNode;
    for (const Path &subPath : folderPath)
    {
        auto *folderNode = m_nodeByPath.value(subPath);
        if (!folderNode)
        {
            folderNode = new ContentNode(true);
            folderNode->setName(subPath.filename());

            if (!suppressNotify)
            {
                const int row = currentFolder->childCount();
                beginInsertRows(indexForNode(currentFolder), row, row);
            }

            currentFolder->appendChild(folderNode);
            m_nodeByPath.insert(subPath, folderNode);

            if (!suppressNotify)
                endInsertRows();
        }

        currentFolder = folderNode;
    }

    return currentFolder;
}

void TorrentContentModel::removeEmptyBranch(const Path &folderPath)
{
    Path currentPath = folderPath;
    auto *folderNode = m_nodeByPath.value(currentPath);
    if (!folderNode)
        return;

    while ((folderNode != m_rootNode) && (folderNode->childCount() == 0))
    {
        ContentNode *parentFolder = folderNode->parent();
        const int row = folderNode->row();

        beginRemoveRows(indexForNode(parentFolder), row, row);
        parentFolder->removeChild(folderNode);
        m_nodeByPath.remove(currentPath);
        delete folderNode;
        endRemoveRows();

        currentPath = currentPath.parentPath();
        folderNode = parentFolder;
    }
}

// ---- Live updates ----------------------------------------------------------

void TorrentContentModel::updateFilesProgress()
{
    if (!m_contentHandler)
        return;

    const QList<qreal> filesProgress = m_contentHandler->filesProgress();
    if (m_filesIndex.size() != filesProgress.size())
        return;

    for (qsizetype i = 0; i < filesProgress.size(); ++i)
        m_filesIndex[i]->setProgress(filesProgress[i]);

    m_rootNode->recalculateProgress();
    m_rootNode->recalculateAvailability();
}

void TorrentContentModel::updateFilesPriorities()
{
    if (!m_contentHandler)
        return;

    const QList<DownloadPriority> priorities = m_contentHandler->filePriorities();
    if (m_filesIndex.size() != priorities.size())
        return;

    for (qsizetype i = 0; i < priorities.size(); ++i)
        m_filesIndex[i]->setPriority(priorities[i]);
}

void TorrentContentModel::updateFilesAvailability()
{
    if (!m_contentHandler)
        return;

    m_contentHandler->fetchAvailableFileFractions().then(this
            , [this, handler = QPointer(m_contentHandler.data())](const QList<qreal> &availableFileFractions)
    {
        if (!m_contentHandler || (m_contentHandler != handler))
            return;

        for (qsizetype i = 0; i < m_filesIndex.size(); ++i)
            m_filesIndex[i]->setAvailability(availableFileFractions.value(i, 0));
        m_rootNode->recalculateProgress();
        m_rootNode->recalculateAvailability();

        const int topLevel = rowCount();
        for (int i = 0; i < topLevel; ++i)
            emitSubtreeChanged(index(i, 0, {}));
    });
}

void TorrentContentModel::refresh()
{
    if (m_filesIndex.isEmpty() || !m_contentHandler || !m_contentHandler->hasMetadata())
        return;

    qCDebug(lcModel) << "TorrentContentModel: refresh";
    updateFilesProgress();
    updateFilesPriorities();
    updateFilesAvailability();

    const int topLevel = rowCount();
    for (int i = 0; i < topLevel; ++i)
        emitSubtreeChanged(index(i, 0, {}));
}

// ---- Actions ---------------------------------------------------------------

bool TorrentContentModel::setItemPriority(const QModelIndex &index, const int priorityInt)
{
    ContentNode *node = nodeForIndex(index);
    if (!node || !m_contentHandler)
        return false;

    const auto priority = static_cast<DownloadPriority>(priorityInt);
    if (node->priority() == priority)
        return false;

    qCDebug(lcModel) << "TorrentContentModel: set priority" << priorityInt << "on" << node->name();
    node->setPriority(priority);
    m_contentHandler->prioritizeFiles(collectFilePriorities());

    m_rootNode->recalculateProgress();
    m_rootNode->recalculateAvailability();
    emitSubtreeChanged(index);
    return true;
}

bool TorrentContentModel::setChecked(const QModelIndex &index, const bool checked)
{
    const auto priority = checked ? DownloadPriority::Normal : DownloadPriority::Ignored;
    return setItemPriority(index, static_cast<int>(priority));
}

bool TorrentContentModel::renameItem(const QModelIndex &index, const QString &newName)
{
    ContentNode *node = nodeForIndex(index);
    if (!node || !m_contentHandler)
        return false;

    const QString trimmed = newName.trimmed();
    if (trimmed == node->name())
        return false;

    if (!isValidNodeName(trimmed))
    {
        emit renameFailed(tr("The name is invalid: \"%1\"").arg(trimmed));
        return false;
    }

    const Path parentPath = pathForIndex(parent(index));
    const Path oldPath = parentPath / Path(node->name());
    const Path newPath = parentPath / Path(trimmed);

    qCInfo(lcModel) << "TorrentContentModel: rename" << oldPath.data() << "->" << newPath.data();
    try
    {
        if (node->isFolder())
            m_contentHandler->renameFolder(oldPath, newPath);
        else
            m_contentHandler->renameFile(oldPath, newPath);
    }
    catch (const std::exception &err)
    {
        emit renameFailed(tr("Could not rename: %1").arg(QString::fromLocal8Bit(err.what())));
        return false;
    }

    return true;
}

void TorrentContentModel::checkAll()
{
    qCDebug(lcModel) << "TorrentContentModel: check all";
    const int n = rowCount();
    for (int i = 0; i < n; ++i)
        setChecked(index(i, 0, {}), true);
}

void TorrentContentModel::checkNone()
{
    qCDebug(lcModel) << "TorrentContentModel: check none";
    const int n = rowCount();
    for (int i = 0; i < n; ++i)
        setChecked(index(i, 0, {}), false);
}

void TorrentContentModel::applyPriorities(const QVariantList &indexes, const int priority)
{
    qCDebug(lcModel) << "TorrentContentModel: apply priority" << priority << "to" << indexes.size() << "items";
    for (const QVariant &value : indexes)
    {
        const auto index = qvariant_cast<QModelIndex>(value);
        if (index.isValid())
            setItemPriority(index, priority);
    }
}

void TorrentContentModel::applyPrioritiesByOrder(const QVariantList &indexes)
{
    // Distribute the selected items into three equal groups and assign
    // Maximum / High / Normal respectively (matching the legacy behavior).
    QList<QModelIndex> valid;
    valid.reserve(indexes.size());
    for (const QVariant &value : indexes)
    {
        const auto index = qvariant_cast<QModelIndex>(value);
        if (index.isValid())
            valid.append(index);
    }

    qCDebug(lcModel) << "TorrentContentModel: apply priorities by order to" << valid.size() << "items";

    const qsizetype priorityGroups = 3;
    const auto groupSize = std::max<qsizetype>((valid.size() / priorityGroups), 1);
    for (qsizetype i = 0; i < valid.size(); ++i)
    {
        DownloadPriority priority = DownloadPriority::Normal;
        switch (i / groupSize)
        {
        case 0:
            priority = DownloadPriority::Maximum;
            break;
        case 1:
            priority = DownloadPriority::High;
            break;
        default:
            priority = DownloadPriority::Normal;
            break;
        }
        setItemPriority(valid.at(i), static_cast<int>(priority));
    }
}

// ---- Node introspection ----------------------------------------------------

bool TorrentContentModel::isFolder(const QModelIndex &index) const
{
    const ContentNode *node = nodeForIndex(index);
    return node && node->isFolder();
}

int TorrentContentModel::fileIndexOf(const QModelIndex &index) const
{
    const ContentNode *node = nodeForIndex(index);
    return node ? node->fileIndex() : -1;
}

bool TorrentContentModel::hasStorageLocation() const
{
    return m_contentHandler && !m_contentHandler->actualStorageLocation().isEmpty();
}

QString TorrentContentModel::itemRelativePath(const QModelIndex &index) const
{
    return pathForIndex(index).data();
}

QString TorrentContentModel::itemFullPath(const QModelIndex &index) const
{
    const ContentNode *node = nodeForIndex(index);
    if (!node || !m_contentHandler)
        return {};

    const Path storage = m_contentHandler->actualStorageLocation();
    if (!node->isFolder() && (node->fileIndex() >= 0))
        return (storage / m_contentHandler->actualFilePath(node->fileIndex())).data();
    return (storage / pathForIndex(index)).data();
}

void TorrentContentModel::appendFileIndexes(const ContentNode *node, QSet<int> &indexes) const
{
    if (!node)
        return;
    if (!node->isFolder())
    {
        if (node->fileIndex() >= 0)
            indexes.insert(node->fileIndex());
        return;
    }
    for (const ContentNode *child : node->children())
        appendFileIndexes(child, indexes);
}

QVariantList TorrentContentModel::fileIndexesForItems(const QVariantList &indexes) const
{
    QSet<int> uniqueIndexes;
    for (const QVariant &value : indexes)
        appendFileIndexes(nodeForIndex(qvariant_cast<QModelIndex>(value)), uniqueIndexes);

    QList<int> sortedIndexes(uniqueIndexes.begin(), uniqueIndexes.end());
    std::sort(sortedIndexes.begin(), sortedIndexes.end());
    QVariantList result;
    result.reserve(sortedIndexes.size());
    for (const int fileIndex : sortedIndexes)
        result.append(fileIndex);
    return result;
}

QVariantList TorrentContentModel::fileEntries() const
{
    QVariantList entries;
    entries.reserve(m_filesIndex.size());
    for (const ContentNode *fileNode : m_filesIndex)
    {
        if (!m_contentHandler)
            break;
        const Path filePath = m_contentHandler->filePath(fileNode->fileIndex());
        entries.append(QVariantMap {
            {u"index"_s, fileNode->fileIndex()},
            {u"path"_s, filePath.data()},
            {u"name"_s, filePath.filename()}
        });
    }
    return entries;
}

bool TorrentContentModel::renameFileByIndex(const int fileIndex, const QString &newRelativePath)
{
    if (!m_contentHandler || (fileIndex < 0) || (fileIndex >= m_filesIndex.size()))
        return false;

    const QString trimmed = newRelativePath.trimmed();
    const Path targetPath(trimmed);
    const QString normalized = QString(trimmed).replace(u'\\', u'/');
    const bool hasTraversal = normalized.split(u'/', Qt::KeepEmptyParts).contains(u".."_s);
    if (trimmed.isEmpty() || !targetPath.isValid() || !targetPath.isRelative() || hasTraversal)
    {
        emit renameFailed(tr("The relative path is invalid: \"%1\"").arg(newRelativePath));
        return false;
    }

    qCInfo(lcModel) << "TorrentContentModel: batch rename file" << fileIndex << "->" << trimmed;
    try
    {
        m_contentHandler->renameFile(fileIndex, targetPath);
    }
    catch (const std::exception &err)
    {
        emit renameFailed(tr("Could not rename: %1").arg(QString::fromLocal8Bit(err.what())));
        return false;
    }
    return true;
}

// ---- Handler signal reactions ----------------------------------------------

void TorrentContentModel::onMetadataReceived()
{
    qCInfo(lcModel) << "TorrentContentModel: metadata received, repopulating";
    beginResetModel();

    delete m_rootNode;
    m_rootNode = new ContentNode(true);
    m_filesIndex.clear();
    m_nodeByPath.clear();
    m_nodeByPath.insert(Path(), m_rootNode);

    populate();

    endResetModel();
    emit metadataReadyChanged();
}

void TorrentContentModel::onFileRenamed(const int fileIndex, const Path &oldFilePath)
{
    if (!m_contentHandler || (fileIndex < 0) || (fileIndex >= m_filesIndex.size()))
        return;

    const Path newFilePath = m_contentHandler->filePath(fileIndex);
    ContentNode *fileNode = m_filesIndex.at(fileIndex);
    fileNode->setName(newFilePath.filename());

    if (newFilePath.parentPath() == oldFilePath.parentPath())
    {
        m_nodeByPath.insert(newFilePath, m_nodeByPath.take(oldFilePath));
        const QModelIndex itemIndex = indexForNode(fileNode);
        emit dataChanged(itemIndex, itemIndex);
        return;
    }

    const Path oldParentPath = oldFilePath.parentPath();
    auto *oldParentFolder = m_nodeByPath.value(oldParentPath);
    const int row = fileNode->row();
    beginRemoveRows(indexForNode(oldParentFolder), row, row);
    oldParentFolder->removeChild(fileNode);
    m_nodeByPath.remove(oldFilePath);
    endRemoveRows();

    removeEmptyBranch(oldParentPath);

    const Path newParentPath = newFilePath.parentPath();
    auto *newParentFolder = m_nodeByPath.value(newParentPath);
    if (!newParentFolder)
        newParentFolder = populateFolder(newParentPath, false);

    const int newRow = newParentFolder->childCount();
    beginInsertRows(indexForNode(newParentFolder), newRow, newRow);
    newParentFolder->appendChild(fileNode);
    m_nodeByPath.insert(newFilePath, fileNode);
    endInsertRows();
}

void TorrentContentModel::onFolderRenamed(const Path &newFolderPath, const Path &oldFolderPath
        , const QHash<int, Path> &renamedFiles)
{
    Q_UNUSED(newFolderPath)
    Q_UNUSED(oldFolderPath)
    Q_UNUSED(renamedFiles)

    if (!m_contentHandler || !m_contentHandler->hasMetadata())
        return;

    // The handler has already applied every native file rename. Rebuild from
    // its paths so nested descendants and cross-parent moves cannot retain
    // stale keys in m_nodeByPath. The mapping remains available on the signal
    // for failure recovery and journal consumers.
    beginResetModel();
    delete m_rootNode;
    m_rootNode = new ContentNode(true);
    m_filesIndex.clear();
    m_nodeByPath.clear();
    m_nodeByPath.insert(Path(), m_rootNode);
    m_metadataReady = false;
    populate();
    endResetModel();
    emit metadataReadyChanged();
}

void TorrentContentModel::onFolderRenamingFailed(const Path &newFolderPath, const Path &oldFolderPath
        , const QHash<int, Path> &renamedFiles, const QList<int> &failedFileIndexes)
{
    for (const auto &[fileIndex, oldFilePath] : renamedFiles.asKeyValueRange())
        onFileRenamed(fileIndex, oldFilePath);

    emit renameFailed(tr("Failed to rename folder '%1' to '%2'. %n file(s) are still in the old folder.", ""
            , static_cast<int>(failedFileIndexes.size()))
            .arg(oldFolderPath.toString(), newFolderPath.toString()));
}

// ---- Helpers ---------------------------------------------------------------

ContentNode *TorrentContentModel::nodeForIndex(const QModelIndex &index) const
{
    if (!index.isValid())
        return nullptr;
    return static_cast<ContentNode *>(index.internalPointer());
}

QModelIndex TorrentContentModel::indexForNode(const ContentNode *node) const
{
    if (!node || (node == m_rootNode))
        return {};
    return createIndex(node->row(), 0, const_cast<ContentNode *>(node));
}

QModelIndex TorrentContentModel::indexForPath(const Path &path) const
{
    const ContentNode *node = m_nodeByPath.value(path);
    return indexForNode(node);
}

Path TorrentContentModel::pathForIndex(const QModelIndex &index) const
{
    QStringList parts;
    for (const ContentNode *node = nodeForIndex(index); node && !node->isRoot(); node = node->parent())
        parts.prepend(node->name());

    Path result;
    for (const QString &part : std::as_const(parts))
        result = result / Path(part);
    return result;
}

QList<DownloadPriority> TorrentContentModel::collectFilePriorities() const
{
    QList<DownloadPriority> priorities;
    priorities.reserve(m_filesIndex.size());
    for (const ContentNode *fileNode : m_filesIndex)
        priorities.push_back(fileNode->priority());
    return priorities;
}

void TorrentContentModel::emitSubtreeChanged(const QModelIndex &index)
{
    if (!index.isValid())
        return;

    emit dataChanged(index, index);

    // Propagate up the tree (folder aggregates change too).
    for (QModelIndex p = parent(index); p.isValid(); p = parent(p))
        emit dataChanged(p, p);

    // Propagate down to every descendant.
    QList<QModelIndex> stack;
    if (hasChildren(index))
        stack.push_back(index);
    while (!stack.isEmpty())
    {
        const QModelIndex parentIndex = stack.takeLast();
        const int childCount = rowCount(parentIndex);
        if (childCount > 0)
            emit dataChanged(this->index(0, 0, parentIndex), this->index(childCount - 1, 0, parentIndex));
        for (int i = 0; i < childCount; ++i)
        {
            const QModelIndex child = this->index(i, 0, parentIndex);
            if (hasChildren(child))
                stack.push_back(child);
        }
    }
}

// ===========================================================================
//  TorrentContentFilterModel
// ===========================================================================

TorrentContentFilterModel::TorrentContentFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    setSortRole(TorrentContentModel::NameRole);
    setRecursiveFilteringEnabled(false); // custom recursive logic below
    qCDebug(lcModel) << "TorrentContentFilterModel constructed";
}

QString TorrentContentFilterModel::filterPattern() const
{
    return m_pattern;
}

void TorrentContentFilterModel::setFilterPattern(const QString &pattern)
{
    if (m_pattern == pattern)
        return;

    m_pattern = pattern;
    rebuildRegex();
    qCDebug(lcModel) << "TorrentContentFilterModel: filter ->" << pattern;
    invalidateFilter();
    emit filterOptionsChanged();
}

bool TorrentContentFilterModel::useRegex() const
{
    return m_useRegex;
}

void TorrentContentFilterModel::setUseRegex(const bool useRegex)
{
    if (m_useRegex == useRegex)
        return;

    m_useRegex = useRegex;
    rebuildRegex();
    invalidateFilter();
    emit filterOptionsChanged();
}

QModelIndex TorrentContentFilterModel::sourceIndex(const QModelIndex &proxyIndex) const
{
    return mapToSource(proxyIndex);
}

void TorrentContentFilterModel::sortByRole(const QString &roleName, const int order)
{
    static const QHash<QString, int> roleMap {
        {u"name"_s, TorrentContentModel::NameRole},
        {u"size"_s, TorrentContentModel::SizeValueRole},
        {u"progress"_s, TorrentContentModel::ProgressRole},
        {u"priority"_s, TorrentContentModel::PriorityRole},
        {u"remaining"_s, TorrentContentModel::RemainingValueRole},
        {u"availability"_s, TorrentContentModel::AvailabilityValueRole}
    };

    m_sortValueRole = roleMap.value(roleName, TorrentContentModel::NameRole);
    setSortRole(m_sortValueRole);
    qCDebug(lcModel) << "TorrentContentFilterModel: sort by" << roleName << "order" << order;
    sort(0, static_cast<Qt::SortOrder>(order));
}

void TorrentContentFilterModel::rebuildRegex()
{
    if (m_useRegex)
    {
        m_regex = QRegularExpression(m_pattern, QRegularExpression::CaseInsensitiveOption);
    }
    else
    {
        m_regex = QRegularExpression(QRegularExpression::escape(m_pattern)
                , QRegularExpression::CaseInsensitiveOption);
    }
}

bool TorrentContentFilterModel::nameMatches(const QModelIndex &sourceIndex) const
{
    const QString name = sourceModel()->data(sourceIndex, TorrentContentModel::NameRole).toString();
    if (m_pattern.isEmpty())
        return true;
    if (!m_regex.isValid())
        return name.contains(m_pattern, Qt::CaseInsensitive);
    return m_regex.match(name).hasMatch();
}

bool TorrentContentFilterModel::subtreeMatches(const QModelIndex &sourceIndex) const
{
    if (nameMatches(sourceIndex))
        return true;

    const int childCount = sourceModel()->rowCount(sourceIndex);
    for (int i = 0; i < childCount; ++i)
    {
        if (subtreeMatches(sourceModel()->index(i, 0, sourceIndex)))
            return true;
    }
    return false;
}

bool TorrentContentFilterModel::ancestorMatches(const QModelIndex &sourceParent) const
{
    for (QModelIndex ancestor = sourceParent; ancestor.isValid(); ancestor = ancestor.parent())
    {
        if (nameMatches(ancestor))
            return true;
    }
    return false;
}

bool TorrentContentFilterModel::filterAcceptsRow(const int sourceRow, const QModelIndex &sourceParent) const
{
    if (m_pattern.isEmpty())
        return true;

    const QModelIndex sourceIndex = sourceModel()->index(sourceRow, 0, sourceParent);
    // Keep a node when it (or a descendant) matches, or when one of its
    // ancestors matched (so a matched folder shows all its contents).
    return subtreeMatches(sourceIndex) || ancestorMatches(sourceParent);
}

bool TorrentContentFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    const QVariant leftData = sourceModel()->data(left, m_sortValueRole);
    const QVariant rightData = sourceModel()->data(right, m_sortValueRole);

    if ((leftData.typeId() == QMetaType::QString) || (rightData.typeId() == QMetaType::QString))
        return QString::localeAwareCompare(leftData.toString(), rightData.toString()) < 0;

    return leftData.toDouble() < rightData.toDouble();
}
