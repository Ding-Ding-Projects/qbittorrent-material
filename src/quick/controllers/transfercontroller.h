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

#include <QList>
#include <QObject>
#include <QVariantList>
#include <QString>
#include <QStringList>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;

namespace BitTorrent
{
    class Torrent;
    class TorrentID;
}

/**
 * @file transfercontroller.h
 * @brief @c TransferController — the QML singleton exposing every row/context
 *        action of the transfer list as a `Q_INVOKABLE` verb.
 *
 * The controller operates on a *selection*: QML sets @ref selectedIds (TorrentID
 * hex strings) as rows are (de)selected, then invokes verbs such as
 * `start()`, `stop()`, `deleteSelected(bool)`, `setCategory(...)`, `addTags(...)`,
 * queue moves, etc. State the controller resolves per action from the current
 * selection; it never rediscovers selection implicitly. Every action logs through
 * `lcUi`/`lcModel`.
 */
class TransferController final : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(TransferController)

    Q_PROPERTY(QStringList selectedIds READ selectedIds WRITE setSelectedIds NOTIFY selectionChanged)
    Q_PROPERTY(int selectionCount READ selectionCount NOTIFY selectionChanged)

public:
    /// QML singleton factory — returns the shared app-owned instance.
    static TransferController *create(QQmlEngine *engine, QJSEngine *jsEngine);
    static TransferController *instance();

    [[nodiscard]] QStringList selectedIds() const;
    void setSelectedIds(const QStringList &ids);
    [[nodiscard]] int selectionCount() const;

    // --- run state ---
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void forceStart();
    Q_INVOKABLE void pauseSession();
    Q_INVOKABLE void resumeSession();

    // --- removal ---
    Q_INVOKABLE void deleteSelected(bool deleteFiles);

    // --- location / naming ---
    Q_INVOKABLE void setLocation(const QString &path);
    Q_INVOKABLE void rename(const QString &newName);            ///< single-selection rename

    // --- category / tags ---
    Q_INVOKABLE void setCategory(const QString &category);
    Q_INVOKABLE void addTags(const QStringList &tags);
    Q_INVOKABLE void removeTags(const QStringList &tags);
    Q_INVOKABLE void removeAllTags();

    // --- trackers / torrent files ---
    /// Trackers common to the selection, formatted for TrackerEntriesDialog.
    Q_INVOKABLE QString trackersText() const;
    /// Replace every selected torrent's trackers with the dialog's tiered text.
    Q_INVOKABLE void setTrackers(const QString &text);
    /// Remove every tracker served by @p host from every torrent in the session.
    /// Returns the number of torrents actually changed.
    Q_INVOKABLE int removeTrackerFromAll(const QString &host);

    // --- export --------------------------------------------------------------

    /// Every format the transfer list can be exported to, as
    /// `{ token, name, extension, lossNote }` maps for a format picker.
    [[nodiscard]] Q_INVOKABLE QVariantList exportFormats() const;

    /// Writes the transfer list to @p filePath in the format named by
    /// @p formatToken ("json", "csv", …). Exports the current selection when
    /// @p selectedOnly, otherwise every torrent in the session. Returns an
    /// empty string on success, or a translated failure message.
    Q_INVOKABLE QString exportTransfers(const QString &formatToken,
        const QString &filePath, bool selectedOnly) const;
    /// Export every selected torrent to @p directory. Returns false on any failure.
    Q_INVOKABLE bool exportTorrent(const QString &directory);

    // --- queue ---
    Q_INVOKABLE void queueTop();
    Q_INVOKABLE void queueUp();
    Q_INVOKABLE void queueDown();
    Q_INVOKABLE void queueBottom();

    // --- maintenance ---
    Q_INVOKABLE void forceRecheck();
    Q_INVOKABLE void forceReannounce();

    // --- per-torrent toggles (tri-state input: 0 = off, 1 = on) ---
    Q_INVOKABLE void setSuperSeeding(bool enabled);
    Q_INVOKABLE void setSequential(bool enabled);
    Q_INVOKABLE void setFirstLastPiece(bool enabled);
    Q_INVOKABLE void setAutoTMM(bool enabled);

    // --- limits / share limits ---
    Q_INVOKABLE void setDownloadLimit(int limitBytesPerSec);
    Q_INVOKABLE void setUploadLimit(int limitBytesPerSec);
    Q_INVOKABLE void setShareLimits(double ratioLimit, int seedingTimeMinutes, int inactiveSeedingTimeMinutes);

    // --- clipboard ---
    Q_INVOKABLE void copyName();
    Q_INVOKABLE void copyHash();      ///< info hash v1 (falls back to v2)
    Q_INVOKABLE void copyMagnet();

    // --- shell / dialogs (delegated) ---
    Q_INVOKABLE void openDestination();
    Q_INVOKABLE void preview();       ///< emits @ref previewRequested for the preview dialog layer

    // --- drag & drop add ---
    /// Classify dropped URLs/paths (.torrent / magnet / other) and request an add.
    Q_INVOKABLE void dropUrls(const QStringList &urls);

signals:
    void selectionChanged();
    /// Emitted when a preview is requested for the given TorrentID (dialog layer handles it).
    void previewRequested(const QStringList &ids);
    /// Emitted for drag-dropped `.torrent`/magnet sources so the add-torrent layer can process them.
    void addTorrentsRequested(const QStringList &sources);
    /// Emitted for a non-torrent dropped file so the Torrent Creator can open on it.
    void createTorrentRequested(const QString &path);

private:
    explicit TransferController(QObject *parent = nullptr);

    /// Resolve the current selection to live torrent pointers (skips stale ids).
    [[nodiscard]] QList<BitTorrent::Torrent *> selectedTorrents() const;
    /// Resolve a single TorrentID string to a torrent (nullptr if unknown).
    [[nodiscard]] BitTorrent::Torrent *torrentFromId(const QString &id) const;
    /// Resolve the selection to a list of TorrentIDs (for queue operations).
    [[nodiscard]] QList<BitTorrent::TorrentID> selectedTorrentIDs() const;

    QStringList m_selectedIds;

    static TransferController *m_instance;
};
