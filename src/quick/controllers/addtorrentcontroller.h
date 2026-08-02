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

#include <memory>

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include "base/bittorrent/addtorrentparams.h"
#include "base/bittorrent/torrentcontenthandler.h"
#include "base/bittorrent/torrentcontentlayout.h"
#include "base/bittorrent/torrentdescriptor.h"
#include "base/path.h"

class QQmlEngine;
class QJSEngine;

namespace BitTorrent
{
    class Session;
    class TorrentInfo;
    enum class DownloadPriority : int;
}

/**
 * @file addtorrentcontroller.h
 * @brief Bridge backing the Material "Add New Torrent" dialog.
 *
 * @c AddTorrentController is the QML-facing hub for a single in-flight
 * add-torrent request. @c GUIAddTorrentManager (C++) hands it a
 * @c BitTorrent::TorrentDescriptor plus caller-supplied @c AddTorrentParams via
 * @ref present(); the controller resolves every tri-state default against
 * @c Session / @c Preferences, exposes them as notifiable properties, owns an
 * in-memory content adaptor + file model for the content tree, and — when the
 * user accepts — rebuilds a concrete @c AddTorrentParams and emits
 * @ref torrentAccepted() (keyed by the QString @c source so QML never has to
 * touch engine types).
 */

/// Flat, in-memory content model for the Add-torrent dialog's file tree.
///
/// Mirrors the file list of a not-yet-added torrent. It is fed by the
/// controller's @c TorrentContentAdaptor and re-emits @ref wantedSizeChanged so
/// the dialog can recompute the "selected size / free space" label live.
class AddTorrentFileModel final : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles
    {
        FileNameRole = Qt::UserRole + 1, ///< "fileName"  — leaf name shown in the tree
        FilePathRole,                    ///< "filePath"  — full relative path
        SizeTextRole,                    ///< "sizeText"  — friendly size, e.g. "1.2 MiB"
        RawSizeRole,                     ///< "rawSize"   — bytes (for sorting)
        PriorityRole,                    ///< "priority"  — DownloadPriority int
        WantedRole                       ///< "wanted"    — bool (priority != Ignored)
    };

    explicit AddTorrentFileModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    /// Replace the whole file list (paths + sizes + priorities). Resets the model.
    void reset(const QStringList &paths, const QList<qlonglong> &sizes
            , const QList<int> &priorities);
    /// Update just the priorities (e.g. after a content-layout change). No reset.
    void setPriorities(const QList<int> &priorities);

    QList<int> priorities() const { return m_priorities; }

    /// Sum of the sizes of all wanted (priority != Ignored) files.
    qlonglong wantedSize() const;

    /// QML-callable per-row edits (used by the tree delegates).
    Q_INVOKABLE void setWanted(int row, bool wanted);
    Q_INVOKABLE void setPriority(int row, int priority);
    Q_INVOKABLE void checkAll();
    Q_INVOKABLE void checkNone();

signals:
    /// Emitted whenever the wanted set / priorities change (drives size label).
    void wantedSizeChanged();

private:
    QStringList m_paths;
    QList<qlonglong> m_sizes;
    QList<int> m_priorities;
};

class AddTorrentController : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AddTorrentController)
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool active READ isActive NOTIFY contextChanged)
    Q_PROPERTY(bool hasMetadata READ hasMetadata NOTIFY contextChanged)
    Q_PROPERTY(QString source READ source NOTIFY contextChanged)
    Q_PROPERTY(QString torrentName READ torrentName NOTIFY contextChanged)
    Q_PROPERTY(QString comment READ comment NOTIFY contextChanged)
    Q_PROPERTY(QString creationDate READ creationDate NOTIFY contextChanged)
    Q_PROPERTY(QString infoHashV1 READ infoHashV1 NOTIFY contextChanged)
    Q_PROPERTY(QString infoHashV2 READ infoHashV2 NOTIFY contextChanged)
    Q_PROPERTY(bool canSaveTorrentFile READ canSaveTorrentFile NOTIFY contextChanged)
    Q_PROPERTY(bool doNotDeleteVisible READ doNotDeleteVisible NOTIFY contextChanged)

    Q_PROPERTY(bool metadataInProgress READ metadataInProgress NOTIFY metadataStatusChanged)
    Q_PROPERTY(QString metadataStatusText READ metadataStatusText NOTIFY metadataStatusChanged)

    Q_PROPERTY(QString sizeText READ sizeText NOTIFY sizeTextChanged)

    Q_PROPERTY(QStringList categories READ categories NOTIFY contextChanged)
    Q_PROPERTY(QStringList savePathHistory READ savePathHistory NOTIFY contextChanged)
    Q_PROPERTY(QStringList downloadPathHistory READ downloadPathHistory NOTIFY contextChanged)

    /// Resolved initial field values (defaults folded in) the dialog binds once.
    Q_PROPERTY(QVariantMap initialValues READ initialValues NOTIFY contextChanged)

    Q_PROPERTY(AddTorrentFileModel *contentModel READ contentModel CONSTANT)

public:
    /// QML singleton factory — returns the one app-owned instance.
    static AddTorrentController *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    static AddTorrentController *instance();

    ~AddTorrentController() override;

    // ---- property getters -------------------------------------------------
    bool isActive() const { return static_cast<bool>(m_context); }
    bool hasMetadata() const;
    QString source() const;
    QString torrentName() const;
    QString comment() const;
    QString creationDate() const;
    QString infoHashV1() const;
    QString infoHashV2() const;
    bool canSaveTorrentFile() const;
    bool doNotDeleteVisible() const { return m_doNotDeleteVisible; }
    bool metadataInProgress() const { return m_metadataInProgress; }
    QString metadataStatusText() const { return m_metadataStatusText; }
    QString sizeText() const { return m_sizeText; }
    QStringList categories() const;
    QStringList savePathHistory() const;
    QStringList downloadPathHistory() const;
    QVariantMap initialValues() const { return m_initialValues; }
    AddTorrentFileModel *contentModel() const { return m_fileModel; }

    // ---- C++ entry points (called by GUIAddTorrentManager) ----------------

    /// Begin presenting the dialog for @p source. Stores the context, resolves
    /// defaults, (re)builds the content model and asks QML to open the dialog.
    void present(const QString &source, const BitTorrent::TorrentDescriptor &torrentDescr
            , const BitTorrent::AddTorrentParams &inParams, bool doNotDeleteVisible);

    /// Feed freshly-downloaded metadata for a magnet that is currently shown.
    void updateMetadata(const BitTorrent::TorrentInfo &metadata);

    /// The params built by the last accepted dialog (read by the manager).
    const BitTorrent::AddTorrentParams &builtParams() const { return m_builtParams; }
    const BitTorrent::TorrentDescriptor &currentDescriptor() const;
    /// Whether the user asked to keep the source .torrent file on accept.
    bool lastDoNotDeleteChecked() const { return m_lastDoNotDelete; }

    // ---- QML actions ------------------------------------------------------

    /// Re-apply the content layout (Original/Subfolder/NoSubfolder) to the tree.
    Q_INVOKABLE void applyContentLayout(int contentLayout);
    /// Recompute the "selected size (free space)" label for @p savePath.
    Q_INVOKABLE void updateSizeText(const QString &savePath);
    /// Resolve the automatic save/download paths for @p category (AutoTMM).
    Q_INVOKABLE QVariantMap categoryPaths(const QString &category) const;
    /// Rename a file inside the content tree.
    Q_INVOKABLE void renameFile(int row, const QString &newPath);
    /// Export the (metadata-complete) torrent to @p filePath.
    Q_INVOKABLE bool saveTorrentFile(const QString &filePath);

    /// Build @c AddTorrentParams from the dialog's field values and accept.
    Q_INVOKABLE void accept(const QVariantMap &values);
    /// Dismiss the dialog without adding (cancels metadata download).
    Q_INVOKABLE void reject();

signals:
    /// Ask the QML layer to open the Add-torrent dialog for the current context.
    void dialogRequested();
    /// The context (torrent / resolved defaults) changed — rebind everything.
    void contextChanged();
    void metadataStatusChanged();
    void sizeTextChanged();

    /// Emitted after @ref accept(): the manager adds the torrent to the session.
    void torrentAccepted(const QString &source);
    /// Emitted after @ref reject(): the manager releases guards / cancels download.
    void torrentRejected(const QString &source);

private:
    explicit AddTorrentController(QObject *parent = nullptr);

    class TorrentContentAdaptor;
    struct Context;

    void resolveInitialValues();
    void rebuildContentModel();
    void setMetadataStatus(bool inProgress, const QString &text);
    void setSizeText(const QString &text);
    void pushSavePathHistory(const QString &key, const QString &path);

    BitTorrent::Session *m_session = nullptr;
    AddTorrentFileModel *m_fileModel = nullptr;

    std::shared_ptr<Context> m_context;
    std::unique_ptr<TorrentContentAdaptor> m_contentAdaptor;

    BitTorrent::AddTorrentParams m_builtParams;

    QVariantMap m_initialValues;
    QString m_metadataStatusText;
    QString m_sizeText;
    bool m_metadataInProgress = false;
    bool m_doNotDeleteVisible = false;
    bool m_lastDoNotDelete = false;

    static AddTorrentController *s_instance;
};
