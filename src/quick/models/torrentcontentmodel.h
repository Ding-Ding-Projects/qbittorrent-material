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

#include <QAbstractItemModel>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QRegularExpression>
#include <QSet>
#include <QSortFilterProxyModel>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include "base/bittorrent/downloadpriority.h"
#include "base/utils/fs/path.h"

namespace BitTorrent
{
    class TorrentContentHandler;
}

/// Internal tree node (file or folder). Defined in the .cpp; the model only
/// stores pointers to it, so a forward declaration is enough here.
class ContentNode;

/**
 * @brief Bridge tree model over a torrent's files/folders.
 *
 * A @c QAbstractItemModel exposing the torrent content as a folder tree with,
 * per node, name / size / progress / priority / remaining / availability and a
 * tri-state check + priority propagation (checking a folder checks every child;
 * a folder whose children disagree is @c Mixed / partially-checked).
 *
 * The model is driven by a @c BitTorrent::TorrentContentHandler (a live
 * @c Torrent for the Content tab, or the in-memory add-torrent adaptor for the
 * Add dialog). It subscribes to the handler's @c metadataReceived / @c
 * fileRenamed / @c folderRenamed / @c folderRenamingFailed signals and never
 * polls; progress / priority / availability are recomputed on demand through
 * @c refresh() (called from the properties controller on @c torrentsUpdated).
 *
 * Because a QML @c TreeView renders one tree column and lays out the other
 * columns inside the row delegate, this model is single-column (@c columnCount
 * == 1) and publishes every field as a **named role** (CONTRACTS §7.1) read as
 * @c model.<role> in the delegate. Mutations go through the @c Q_INVOKABLE
 * verbs (setItemPriority / setChecked / renameItem / checkAll / …) rather than
 * @c setData, so QML never has to build @c EditRole payloads.
 */
class TorrentContentModel : public QAbstractItemModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_DISABLE_COPY_MOVE(TorrentContentModel)

    /// The content handler, accepted as a plain @c QObject* so QML can assign a
    /// @c Torrent or the add-torrent adaptor directly (both derive from
    /// @c BitTorrent::TorrentContentHandler which is a @c QObject).
    Q_PROPERTY(QObject *contentHandler READ contentHandlerObject WRITE setContentHandlerObject NOTIFY contentHandlerChanged)
    /// True once metadata is available and the tree is populated.
    Q_PROPERTY(bool metadataReady READ metadataReady NOTIFY metadataReadyChanged)
    /// Number of leaf files in the tree.
    Q_PROPERTY(int fileCount READ fileCount NOTIFY metadataReadyChanged)

public:
    /// Named data roles (single logical column; read as @c model.<name>).
    enum Roles
    {
        NameRole = Qt::UserRole + 1,   ///< "name"              display name
        SizeRole,                      ///< "size"              friendly size string
        SizeValueRole,                 ///< "sizeValue"         raw bytes (sort key)
        ProgressRole,                  ///< "progress"          qreal 0..1
        ProgressTextRole,              ///< "progressText"      e.g. "42.3%"
        PriorityRole,                  ///< "priority"          DownloadPriority int
        PriorityTextRole,              ///< "priorityText"      localized label
        RemainingRole,                 ///< "remaining"         friendly remaining string
        RemainingValueRole,            ///< "remainingValue"    raw bytes (sort key)
        AvailabilityRole,             ///< "availability"      "N/A" / "53.2%"
        AvailabilityValueRole,         ///< "availabilityValue" qreal (sort key)
        CheckStateRole,                ///< "checkState"        Qt::CheckState int
        IsFolderRole,                  ///< "isFolder"          bool
        FileIndexRole                  ///< "fileIndex"         int (-1 for folders)
    };
    Q_ENUM(Roles)

    explicit TorrentContentModel(QObject *parent = nullptr);
    ~TorrentContentModel() override;

    // ---- QAbstractItemModel ------------------------------------------------
    int columnCount(const QModelIndex &parent = {}) const override;
    int rowCount(const QModelIndex &parent = {}) const override;
    QModelIndex index(int row, int column, const QModelIndex &parent = {}) const override;
    QModelIndex parent(const QModelIndex &index) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;
    QHash<int, QByteArray> roleNames() const override;

    // ---- Property accessors ------------------------------------------------
    QObject *contentHandlerObject() const;
    void setContentHandlerObject(QObject *handler);
    bool metadataReady() const;
    int fileCount() const;

    /// Bind (or unbind, with @c nullptr) the content handler and (re)build the tree.
    void setContentHandler(BitTorrent::TorrentContentHandler *contentHandler);
    BitTorrent::TorrentContentHandler *contentHandler() const;

    // ---- QML-invocable actions (operate on this model's own indexes) -------

    /// Recompute progress / priority / availability and notify the view.
    Q_INVOKABLE void refresh();

    /// Set the download priority of a single node (folder propagates to children).
    Q_INVOKABLE bool setItemPriority(const QModelIndex &index, int priority);

    /// Check / uncheck a node (checked → Normal, unchecked → Ignored, propagated).
    Q_INVOKABLE bool setChecked(const QModelIndex &index, bool checked);

    /// Rename the file/folder at @p index; returns false and emits @c renameFailed on error.
    Q_INVOKABLE bool renameItem(const QModelIndex &index, const QString &newName);

    /// Check / uncheck every top-level node (recursively via propagation).
    Q_INVOKABLE void checkAll();
    Q_INVOKABLE void checkNone();

    /// Apply @p priority to each of @p indexes (a JS array of this model's indexes).
    Q_INVOKABLE void applyPriorities(const QVariantList &indexes, int priority);

    /// Split @p indexes into three equal groups → Maximum / High / Normal.
    Q_INVOKABLE void applyPrioritiesByOrder(const QVariantList &indexes);

    // ---- Node introspection (used by the context menu / batch rename) ------
    Q_INVOKABLE bool isFolder(const QModelIndex &index) const;
    Q_INVOKABLE int fileIndexOf(const QModelIndex &index) const;
    Q_INVOKABLE bool hasStorageLocation() const;
    Q_INVOKABLE QString itemRelativePath(const QModelIndex &index) const;
    Q_INVOKABLE QString itemFullPath(const QModelIndex &index) const;

    /// Unique leaf file indexes represented by the supplied files/folders.
    Q_INVOKABLE QVariantList fileIndexesForItems(const QVariantList &indexes) const;

    /// [{ index, path, name }] for every leaf file — feeds the batch-rename preview.
    Q_INVOKABLE QVariantList fileEntries() const;

    /// Rename a leaf file by its torrent file index to a new relative path.
    Q_INVOKABLE bool renameFileByIndex(int fileIndex, const QString &newRelativePath);

signals:
    void contentHandlerChanged();
    void metadataReadyChanged();
    /// A rename could not be applied; @p errorMessage is user-facing (already tr'd).
    void renameFailed(const QString &errorMessage);

private:
    ContentNode *nodeForIndex(const QModelIndex &index) const;
    QModelIndex indexForNode(const ContentNode *node) const;
    QModelIndex indexForPath(const Path &path) const;
    Path pathForIndex(const QModelIndex &index) const;
    void appendFileIndexes(const ContentNode *node, QSet<int> &indexes) const;

    void populate();
    ContentNode *populateFolder(const Path &folderPath, bool suppressNotify);
    void removeEmptyBranch(const Path &folderPath);

    void updateFilesProgress();
    void updateFilesPriorities();
    void updateFilesAvailability();

    QList<BitTorrent::DownloadPriority> collectFilePriorities() const;
    void emitSubtreeChanged(const QModelIndex &index);

    // Handler signal reactions.
    void onMetadataReceived();
    void onFileRenamed(int fileIndex, const Path &oldFilePath);
    void onFolderRenamed(const Path &newFolderPath, const Path &oldFolderPath
            , const QHash<int, Path> &renamedFiles);
    void onFolderRenamingFailed(const Path &newFolderPath, const Path &oldFolderPath
            , const QHash<int, Path> &renamedFiles, const QList<int> &failedFileIndexes);

    QPointer<BitTorrent::TorrentContentHandler> m_contentHandler;
    ContentNode *m_rootNode = nullptr;
    QList<ContentNode *> m_filesIndex;
    QHash<Path, ContentNode *> m_nodeByPath;
    bool m_metadataReady = false;
};

/**
 * @brief Sort/filter proxy over @c TorrentContentModel.
 *
 * Provides the "Filter files…" text filter (plain-substring or regex) and
 * header-click sorting for the content tree. Filtering is recursive: a folder
 * is kept when it (or any descendant) matches, and children of a matched folder
 * are kept, so matches always render with their surrounding structure.
 *
 * QML action helpers on the tree operate on @b source indexes, so this proxy
 * exposes @c sourceIndex() to translate a proxy index back to the source model.
 */
class TorrentContentFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString filterPattern READ filterPattern WRITE setFilterPattern NOTIFY filterOptionsChanged)
    Q_PROPERTY(bool useRegex READ useRegex WRITE setUseRegex NOTIFY filterOptionsChanged)

public:
    explicit TorrentContentFilterModel(QObject *parent = nullptr);

    QString filterPattern() const;
    void setFilterPattern(const QString &pattern);
    bool useRegex() const;
    void setUseRegex(bool useRegex);

    /// Map a proxy index to the underlying @c TorrentContentModel index.
    Q_INVOKABLE QModelIndex sourceIndex(const QModelIndex &proxyIndex) const;

    /// Sort the tree by a role name ("name","size","progress","priority",
    /// "remaining","availability"); @p order is Qt.AscendingOrder/DescendingOrder.
    Q_INVOKABLE void sortByRole(const QString &roleName, int order);

signals:
    void filterOptionsChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    bool subtreeMatches(const QModelIndex &sourceIndex) const;
    bool ancestorMatches(const QModelIndex &sourceParent) const;
    bool nameMatches(const QModelIndex &sourceIndex) const;
    void rebuildRegex();

    QString m_pattern;
    bool m_useRegex = false;
    QRegularExpression m_regex;
    int m_sortValueRole = TorrentContentModel::NameRole;
};
