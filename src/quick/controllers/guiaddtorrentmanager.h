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
#include <optional>

#include <QHash>
#include <QJSEngine>
#include <QMetaMethod>
#include <QObject>
#include <QQueue>
#include <QQmlEngine>
#include <QScopedValueRollback>
#include <QString>
#include <QTimer>
#include <QUrl>

#include "base/bittorrent/addtorrentparams.h"
#include "base/bittorrent/addtorrenterror.h"
#include "base/bittorrent/infohash.h"
#include "base/bittorrent/session.h"
#include "base/bittorrent/torrent.h"
#include "base/bittorrent/torrentdescriptor.h"
#include "base/logging.h"
#include "base/net/downloadmanager.h"
#include "base/path.h"
#include "base/preferences.h"
#include "base/torrentfileguard.h"

#include "addtorrentcontroller.h"

using namespace Qt::StringLiterals;

class QJSEngine;
/**
 * @file guiaddtorrentmanager.h
 * @brief The @c GuiAddTorrentManager QML singleton — front door for adding
 *        torrents from the GUI.
 *
 * Given a @c source (a `.torrent` path, magnet URI or http(s) URL) it:
 *  - downloads the file first if @c source is a supported URL;
 *  - parses it into a @c BitTorrent::TorrentDescriptor;
 *  - detects duplicates already in the session and merges trackers
 *    (asking for confirmation via @ref mergeTrackersRequested when the user
 *    enabled that preference); and
 *  - either adds it straight to the session (when the Add-torrent dialog is
 *    disabled / explicitly skipped) or hands it to @c AddTorrentController to
 *    present the Material dialog, finalizing on accept.
 *
 * QML uses it directly, e.g. from the toolbar / paste-magnet action:
 * @code
 *   GuiAddTorrentManager.addTorrent(urlField.text)
 * @endcode
 */
class GuiAddTorrentManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    /// How the dialog decision is made for a given add request.
    enum class Option
    {
        Default,    ///< Honour the "show Add-torrent dialog" preference.
        ShowDialog, ///< Always show the dialog.
        SkipDialog  ///< Never show the dialog; add immediately with @c params.
    };
    Q_ENUM(Option)

    static GuiAddTorrentManager *create(QQmlEngine *, QJSEngine *)
    {
        GuiAddTorrentManager *manager = instance();
        QJSEngine::setObjectOwnership(manager, QJSEngine::CppOwnership);
        return manager;
    }

    static GuiAddTorrentManager *instance()
    {
        static GuiAddTorrentManager s_instance;
        return &s_instance;
    }

private:
    explicit GuiAddTorrentManager(QObject *parent = nullptr)
        : QObject(parent)
        , m_session {BitTorrent::Session::instance()}
    {
        if (m_session)
        {
            connect(m_session, &BitTorrent::Session::metadataDownloaded,
                    this, &GuiAddTorrentManager::onMetadataDownloaded);
            connect(m_session, &BitTorrent::Session::torrentAdded,
                    this, &GuiAddTorrentManager::onSessionTorrentAdded);
            connect(m_session, &BitTorrent::Session::addTorrentFailed,
                    this, &GuiAddTorrentManager::onSessionAddTorrentFailed);
        }

        auto *controller = AddTorrentController::instance();
        connect(controller, &AddTorrentController::torrentAccepted,
                this, &GuiAddTorrentManager::onDialogAccepted);
        connect(controller, &AddTorrentController::torrentRejected,
                this, &GuiAddTorrentManager::onDialogRejected);

        qCDebug(lcUi) << "GuiAddTorrentManager constructed";
    }

public:
    /// Main entry point. Returns @c true if the request was started/handled.
    Q_INVOKABLE bool addTorrent(const QString &source
            , const BitTorrent::AddTorrentParams &params = {}
            , const Option option = Option::Default)
    {
        if (source.isEmpty())
        {
            qCWarning(lcUi) << "GuiAddTorrentManager: empty source ignored";
            return false;
        }

        qCInfo(lcUi) << "GuiAddTorrentManager: addTorrent source=" << source
                     << "option=" << static_cast<int>(option);

        const auto *pref = Preferences::instance();
        const bool dialogEnabled = pref->isAddNewTorrentDialogEnabled();

        // Fast path: skip the dialog and add straight to the session.
        if ((option == Option::SkipDialog)
                || ((option == Option::Default) && !dialogEnabled))
        {
            return addSourceToSession(source, params);
        }

        // AddTorrentController intentionally owns one dialog context. Serialize
        // requests that require that dialog so a multi-file picker (or several
        // activation requests) cannot overwrite the context that is currently
        // on screen.
        if (m_dialogPipelineBusy)
        {
            m_pendingDialogRequests.enqueue(PendingDialogRequest {source, params});
            qCInfo(lcUi) << "GuiAddTorrentManager: queued dialog request for" << source
                         << "pending=" << m_pendingDialogRequests.size();
            return true;
        }

        m_dialogPipelineBusy = true;
        const bool started = startDialogRequest(source, params);
        if (!started)
            scheduleNextDialogRequest();
        return started;
    }

    /// QML response to @ref mergeTrackersRequested.
    Q_INVOKABLE void respondMergeTrackers(const QString &source, const bool accepted)
    {
        auto pendingIt = m_pendingMerges.find(source);
        if ((pendingIt == m_pendingMerges.end()) || pendingIt->isEmpty())
        {
            qCWarning(lcUi) << "GuiAddTorrentManager: no pending tracker merge for" << source;
            return;
        }

        const BitTorrent::TorrentDescriptor descr = pendingIt->dequeue();
        if (pendingIt->isEmpty())
            m_pendingMerges.erase(pendingIt);

        if (!accepted)
        {
            qCDebug(lcUi) << "GuiAddTorrentManager: tracker merge declined for" << source;
            m_guards.remove(source);
            scheduleNextDialogRequest();
            return;
        }

        if (!m_session || !m_session->isMergeTrackersEnabled())
        {
            qCInfo(lcUi) << "GuiAddTorrentManager: tracker merging was disabled"
                         << "while confirmation was open";
        }
        else if (BitTorrent::Torrent *torrent = m_session->findTorrent(descr.infoHash()))
        {
            const bool descriptorPrivate = descr.info() && descr.info()->isPrivate();
            if (torrent->isPrivate() || descriptorPrivate)
            {
                qCInfo(lcUi) << "GuiAddTorrentManager: tracker merge blocked for private torrent"
                             << torrent->name();
            }
            else
            {
                torrent->addTrackers(descr.trackers());
                torrent->addUrlSeeds(descr.urlSeeds());
                qCInfo(lcUi) << "GuiAddTorrentManager: merged trackers into" << torrent->name();
            }
        }
        m_guards.remove(source);
        scheduleNextDialogRequest();
    }

signals:
    /// A torrent was successfully added to the session.
    void torrentAdded(const QString &source);
    /// Adding failed; @p reason is a human-readable, translated message.
    void addTorrentFailed(const QString &source, const QString &reason);
    /// The source duplicates an existing torrent; QML should notify the user.
    void duplicateTorrent(const QString &source, const QString &name);
    /// Ask the user whether to merge trackers; the receiver must call
    /// @ref respondMergeTrackers to release the serialized dialog pipeline.
    void mergeTrackersRequested(const QString &source, const QString &name, bool isPrivate);

private:
    // ---- pipeline steps ----------------------------------------------------

    struct PendingDialogRequest
    {
        QString source;
        BitTorrent::AddTorrentParams params;
    };

    struct PendingDownload
    {
        BitTorrent::AddTorrentParams params;
        bool showDialog = false;
    };

    struct PendingSessionAdd
    {
        QString source;
        std::shared_ptr<TorrentFileGuard> guard;
    };

    bool startDialogRequest(const QString &source
            , const BitTorrent::AddTorrentParams &params)
    {
        const auto *pref = Preferences::instance();

        // Remote source: keep ownership of the serialized dialog slot while
        // the .torrent is downloaded.
        if (Net::DownloadManager::hasSupportedScheme(source))
        {
            qCInfo(lcNet) << "GuiAddTorrentManager: downloading torrent from" << source;
            Net::DownloadManager::instance()->download(
                    Net::DownloadRequest(source).limit(pref->getTorrentFileSizeLimit())
                    , pref->useProxyForGeneralPurposes()
                    , this, [this, request = PendingDownload {params, true}]
                    (const Net::DownloadResult &result)
                    {
                        onDownloadFinished(result, request);
                    });
            return true;
        }

        // Magnet URI / info-hash string.
        if (const auto parseResult = BitTorrent::TorrentDescriptor::parse(source))
            return processTorrent(source, parseResult.value(), params);
        else if (source.startsWith(u"magnet:", Qt::CaseInsensitive))
        {
            emit addTorrentFailed(source, parseResult.error());
            return false;
        }

        // Local .torrent file.
        const Path decodedPath {source.startsWith(u"file://", Qt::CaseInsensitive)
                ? QUrl::fromEncoded(source.toLocal8Bit()).toLocalFile() : source};
        auto guard = std::make_shared<TorrentFileGuard>(decodedPath);
        if (const auto loadResult = BitTorrent::TorrentDescriptor::loadFromFile(decodedPath))
        {
            // Store the guard before emitting either dialog signal so even a
            // synchronous QML response can release it correctly.
            m_guards.insert(source, guard);
            const bool interactionPending = processTorrent(source, loadResult.value(), params);
            if (!interactionPending)
                m_guards.remove(source);
            return interactionPending;
        }
        else
        {
            emit addTorrentFailed(decodedPath.toString(), loadResult.error());
            return false;
        }
    }

    void scheduleNextDialogRequest()
    {
        if (m_dialogAdvanceScheduled)
            return;

        // AddTorrentController emits accepted/rejected before clearing its old
        // context. Advance on the next event-loop turn so presenting the next
        // request cannot be undone by that cleanup.
        m_dialogAdvanceScheduled = true;
        QTimer::singleShot(0, this, [this]
        {
            m_dialogAdvanceScheduled = false;
            if (m_pendingDialogRequests.isEmpty())
            {
                m_dialogPipelineBusy = false;
                return;
            }

            const PendingDialogRequest request = m_pendingDialogRequests.dequeue();
            qCInfo(lcUi) << "GuiAddTorrentManager: presenting next queued request for"
                         << request.source << "remaining=" << m_pendingDialogRequests.size();
            if (!startDialogRequest(request.source, request.params))
                scheduleNextDialogRequest();
        });
    }

    void onDownloadFinished(const Net::DownloadResult &result, const PendingDownload &request)
    {
        const QString source = result.url;
        bool interactionPending = false;

        switch (result.status)
        {
        case Net::DownloadStatus::Success:
            if (const auto loadResult = BitTorrent::TorrentDescriptor::load(result.data))
            {
                if (request.showDialog)
                    interactionPending = processTorrent(source, loadResult.value(), request.params);
                else
                    addToSession(source, loadResult.value(), request.params);
            }
            else
                emit addTorrentFailed(source, loadResult.error());
            break;
        case Net::DownloadStatus::RedirectedToMagnet:
            if (const auto parseResult = BitTorrent::TorrentDescriptor::parse(result.magnetURI))
            {
                if (request.showDialog)
                    interactionPending = processTorrent(source, parseResult.value(), request.params);
                else
                    addToSession(source, parseResult.value(), request.params);
            }
            else
                emit addTorrentFailed(source, parseResult.error());
            break;
        default:
            emit addTorrentFailed(source, result.errorString);
            break;
        }

        if (request.showDialog && !interactionPending)
            scheduleNextDialogRequest();
    }

    void onMetadataDownloaded(const BitTorrent::TorrentInfo &metadata)
    {
        // Forward to the dialog controller in case a magnet is being shown.
        AddTorrentController::instance()->updateMetadata(metadata);
    }

    void onSessionTorrentAdded(BitTorrent::Torrent *torrent)
    {
        if (!torrent)
            return;

        auto pendingIt = m_pendingSessionAdds.find(torrent->id());
        if ((pendingIt == m_pendingSessionAdds.end()) && torrent->infoHash().isHybrid())
            pendingIt = m_pendingSessionAdds.find(
                    BitTorrent::TorrentID::fromSHA1Hash(torrent->infoHash().v1()));
        if (pendingIt == m_pendingSessionAdds.end())
            return;

        PendingSessionAdd pending = pendingIt.value();
        m_pendingSessionAdds.erase(pendingIt);
        if (pending.guard)
            pending.guard->markAsAddedToSession();

        qCInfo(lcUi) << "GuiAddTorrentManager: session confirmed torrent from"
                     << pending.source;
        emit torrentAdded(pending.source);
    }

    void onSessionAddTorrentFailed(const BitTorrent::InfoHash &infoHash
            , const BitTorrent::AddTorrentError &reason)
    {
        // Duplicate failures are emitted synchronously by SessionImpl's
        // preflight. Only consume one while this manager's matching call is on
        // the stack; another Session caller can reject the same hash while our
        // genuine async add is still pending.
        if ((reason.kind == BitTorrent::AddTorrentError::DuplicateTorrent)
                && (!m_activeSessionAddID
                    || (*m_activeSessionAddID != infoHash.toTorrentID())))
        {
            return;
        }

        auto pendingIt = m_pendingSessionAdds.find(infoHash.toTorrentID());
        if ((pendingIt == m_pendingSessionAdds.end()) && infoHash.isHybrid())
            pendingIt = m_pendingSessionAdds.find(
                    BitTorrent::TorrentID::fromSHA1Hash(infoHash.v1()));
        if (pendingIt == m_pendingSessionAdds.end())
            return;

        const PendingSessionAdd pending = pendingIt.value();
        m_pendingSessionAdds.erase(pendingIt);
        qCWarning(lcUi) << "GuiAddTorrentManager: session rejected torrent from"
                        << pending.source << reason.message;

        if (reason.kind == BitTorrent::AddTorrentError::DuplicateTorrent)
        {
            const QString name = m_session && m_session->findTorrent(infoHash)
                    ? m_session->findTorrent(infoHash)->name() : QString();
            emit duplicateTorrent(pending.source, name);
        }
        else
        {
            emit addTorrentFailed(pending.source, reason.message.isEmpty()
                    ? tr("Failed to add torrent to the session.") : reason.message);
        }
    }

    // Returns true while the serialized pipeline is awaiting either the add
    // dialog or a tracker-merge confirmation.
    bool processTorrent(const QString &source
            , const BitTorrent::TorrentDescriptor &torrentDescr
            , const BitTorrent::AddTorrentParams &params)
    {
        const bool hasMetadata = torrentDescr.info().has_value();
        const BitTorrent::InfoHash infoHash = torrentDescr.infoHash();

        // Duplicate detection.
        if (BitTorrent::Torrent *torrent = m_session
                ? m_session->findTorrent(infoHash) : nullptr)
        {
            if (hasMetadata)
                torrent->setMetadata(*torrentDescr.info());

            const bool isPrivate = torrent->isPrivate()
                    || (hasMetadata && torrentDescr.info()->isPrivate());
            const bool mergingEnabled = m_session->isMergeTrackersEnabled();
            const bool confirmationEnabled = Preferences::instance()->confirmMergeTrackers();
            const bool confirmationAvailable = isSignalConnected(
                    QMetaMethod::fromSignal(
                            &GuiAddTorrentManager::mergeTrackersRequested));

            if (mergingEnabled && confirmationEnabled && !isPrivate && confirmationAvailable)
            {
                // Keep the add-dialog pipeline occupied until QML responds.
                // This prevents the next add dialog or merge prompt from
                // opening over the confirmation currently on screen.
                m_pendingMerges[source].enqueue(torrentDescr);
                emit mergeTrackersRequested(source, torrent->name(), false);
                return true;
            }

            if (mergingEnabled && confirmationEnabled && !isPrivate && !confirmationAvailable)
            {
                // The current shell has no merge-confirmation connection. Do
                // not retain an unanswerable request or merge without consent.
                qCWarning(lcUi) << "GuiAddTorrentManager: tracker merge confirmation"
                                << "has no responder; declining merge";
            }

            qCInfo(lcUi) << "GuiAddTorrentManager: duplicate torrent" << torrent->name();
            if (mergingEnabled && !confirmationEnabled && !isPrivate)
            {
                torrent->addTrackers(torrentDescr.trackers());
                torrent->addUrlSeeds(torrentDescr.urlSeeds());
            }
            emit duplicateTorrent(source, torrent->name());

            return false;
        }

        // Start fetching metadata for magnet links in the background.
        if (!hasMetadata && m_session)
            m_session->downloadMetadata(torrentDescr);

        // Present the Material Add-torrent dialog.
        const bool doNotDeleteVisible =
                (TorrentFileGuard::autoDeleteMode() != TorrentFileGuard::Never);
        AddTorrentController::instance()->present(source, torrentDescr, params, doNotDeleteVisible);
        return true;
    }

    void onDialogAccepted(const QString &source)
    {
        auto *controller = AddTorrentController::instance();

        // Honour "do not delete torrent file".
        if (controller->lastDoNotDeleteChecked())
        {
            if (auto it = m_guards.find(source); it != m_guards.end())
                (*it)->setAutoRemove(false);
        }

        const BitTorrent::TorrentDescriptor descr = controller->currentDescriptor();
        addToSession(source, descr, controller->builtParams());
        scheduleNextDialogRequest();
    }

    void onDialogRejected(const QString &source)
    {
        qCDebug(lcUi) << "GuiAddTorrentManager: dialog rejected for" << source;
        m_guards.remove(source);
        scheduleNextDialogRequest();
    }

    // ---- session hand-off --------------------------------------------------

    bool addSourceToSession(const QString &source, const BitTorrent::AddTorrentParams &params)
    {
        if (Net::DownloadManager::hasSupportedScheme(source))
        {
            // Defer: download then add without a dialog.
            Net::DownloadManager::instance()->download(
                    Net::DownloadRequest(source).limit(
                            Preferences::instance()->getTorrentFileSizeLimit())
                    , Preferences::instance()->useProxyForGeneralPurposes()
                    , this, [this, request = PendingDownload {params, false}]
                    (const Net::DownloadResult &result)
                    {
                        onDownloadFinished(result, request);
                    });
            return true;
        }

        if (const auto parseResult = BitTorrent::TorrentDescriptor::parse(source))
            return addToSession(source, parseResult.value(), params);

        const Path decodedPath {source.startsWith(u"file://", Qt::CaseInsensitive)
                ? QUrl::fromEncoded(source.toLocal8Bit()).toLocalFile() : source};
        if (const auto loadResult = BitTorrent::TorrentDescriptor::loadFromFile(decodedPath))
        {
            m_guards.insert(source, std::make_shared<TorrentFileGuard>(decodedPath));
            return addToSession(source, loadResult.value(), params);
        }
        else
            emit addTorrentFailed(decodedPath.toString(), loadResult.error());
        return false;
    }

    bool addToSession(const QString &source, const BitTorrent::TorrentDescriptor &torrentDescr
            , const BitTorrent::AddTorrentParams &params)
    {
        if (!m_session)
        {
            emit addTorrentFailed(source, tr("BitTorrent session is unavailable."));
            m_guards.remove(source);
            return false;
        }

        const BitTorrent::InfoHash infoHash = torrentDescr.infoHash();
        if (!infoHash.isValid())
        {
            emit addTorrentFailed(source, tr("Invalid torrent info hash."));
            m_guards.remove(source);
            return false;
        }

        const BitTorrent::TorrentID id = infoHash.toTorrentID();
        if (m_pendingSessionAdds.contains(id))
        {
            emit addTorrentFailed(source, tr("This torrent is already being added."));
            m_guards.remove(source);
            return false;
        }

        PendingSessionAdd pending {source, m_guards.take(source)};
        m_pendingSessionAdds.insert(id, pending);

        const QScopedValueRollback activeAddScope {m_activeSessionAddID,
                std::optional<BitTorrent::TorrentID> {id}};
        const bool queued = m_session->addTorrent(torrentDescr, params);
        if (!queued && m_pendingSessionAdds.contains(id))
        {
            // Some immediate failures (for example, an unavailable restoring
            // session) cannot emit a detailed engine signal.
            m_pendingSessionAdds.remove(id);
            emit addTorrentFailed(source, tr("Failed to add torrent to the session."));
        }
        else if (queued)
        {
            qCInfo(lcUi) << "GuiAddTorrentManager: queued torrent add from" << source;
        }
        return queued;
    }

    BitTorrent::Session *m_session = nullptr;
    QHash<QString, std::shared_ptr<TorrentFileGuard>> m_guards;
    QHash<QString, QQueue<BitTorrent::TorrentDescriptor>> m_pendingMerges;
    QHash<BitTorrent::TorrentID, PendingSessionAdd> m_pendingSessionAdds;
    std::optional<BitTorrent::TorrentID> m_activeSessionAddID;
    QQueue<PendingDialogRequest> m_pendingDialogRequests;
    bool m_dialogPipelineBusy = false;
    bool m_dialogAdvanceScheduled = false;
};
