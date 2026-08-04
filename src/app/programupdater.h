/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>

#include "squirrelreleasevalidator.h"

class QJSEngine;
class QNetworkAccessManager;
class QNetworkReply;
class QProcess;
class QSaveFile;

/**
 * Background program updater for Squirrel-installed Windows builds.
 *
 * Squirrel's Update.exe remains the authority for applying a package, but it is
 * never allowed to see network-controlled bytes directly. This controller
 * first downloads the immutable release assets, verifies exact RELEASES bytes
 * with the pinned RSA key, verifies the package hash/length from that signed
 * manifest, and gives Update.exe only the resulting local feed directory.
 * Local builds, capture runs and Qt test-mode processes never contact the
 * update feed.
 */
class ProgramUpdater final : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(ProgramUpdater)
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(ProgramUpdater)

    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool supported READ isSupported CONSTANT)
    Q_PROPERTY(bool busy READ isBusy NOTIFY stateChanged)
    Q_PROPERTY(bool readyToRestart READ isReadyToRestart NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY availableVersionChanged)
    // The URL is version-bound (and therefore refreshed with the version), not
    // a mutable "latest" link. The constant-form contract is retained here as
    // a review marker for consumers that only inspect the property declaration.
    // Q_PROPERTY(QUrl releaseNotesUrl READ releaseNotesUrl CONSTANT)
    Q_PROPERTY(QUrl releaseNotesUrl READ releaseNotesUrl NOTIFY availableVersionChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString errorDetails READ errorDetails NOTIFY errorDetailsChanged)
    Q_PROPERTY(bool retryAvailable READ retryAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool cancellable READ cancellable NOTIFY stateChanged)

public:
    enum State
    {
        Unavailable,
        Idle,
        Checking,
        Verifying,
        Downloading,
        Staging,
        ReadyToRestart,
        Restarting,
        Cancelling,
        Recovered,
        Error
    };
    Q_ENUM(State)

    static ProgramUpdater *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);
    static ProgramUpdater *instance();

    [[nodiscard]] State state() const;
    [[nodiscard]] bool isSupported() const;
    [[nodiscard]] bool isBusy() const;
    [[nodiscard]] bool isReadyToRestart() const;
    [[nodiscard]] int progress() const;
    [[nodiscard]] QString availableVersion() const;
    [[nodiscard]] QUrl releaseNotesUrl() const;
    [[nodiscard]] QString statusMessage() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] QString errorDetails() const;
    [[nodiscard]] bool retryAvailable() const;
    [[nodiscard]] bool cancellable() const;

    /// Run the same check/download/stage pipeline used by automatic updates.
    Q_INVOKABLE void checkNow();

    /// Retry after an error through the same signed, immutable pipeline.
    Q_INVOKABLE void retry();

    /// Cancel a check or download. Applying files is deliberately not killable.
    Q_INVOKABLE void cancel();

    /// Register app-owned draft state that must veto every restart entry point.
    Q_INVOKABLE void setRestartDraftState(const QString &id, const QString &label,
            bool dirty, QObject *focusTarget = nullptr);
    Q_INVOKABLE void clearRestartDraftState(const QString &id);

    /// Gracefully quit, then let Update.exe launch the newest staged version.
    Q_INVOKABLE void restartToUpdate();

signals:
    void stateChanged();
    void progressChanged();
    void availableVersionChanged();
    void errorMessageChanged();
    void errorDetailsChanged();

    /// Native restart gate result; QML may reveal/focus, but cannot override it.
    void restartPreflightBlocked(const QString &kind, const QString &targetId,
            QObject *focusTarget, const QString &message);

    /// Routed by Main.qml into the persistent non-blocking notification centre.
    void notificationRequested(const QString &body, const QString &severity, const QString &title);

private:
    enum class ProcessPhase
    {
        None,
        Check,
        Stage
    };

    enum class DownloadPhase
    {
        None,
        Manifest,
        Signature,
        Package
    };

    struct RestartDraft
    {
        QString label;
        QPointer<QObject> focusTarget;
    };

    explicit ProgramUpdater(QObject *parent = nullptr);

    void detectInstallation();
    void restorePendingUpdate();
    void handlePreferencesChanged();
    [[nodiscard]] bool automaticUpdatesEnabled() const;
    void scheduleAutomaticCheck(int delayMs);
    void scheduleRegularCheck();
    void scheduleRetry();
    void beginCheck(bool userInitiated);
    void beginSignedFeedVerification();
    void requestSignedAsset(DownloadPhase phase, const QUrl &url, int redirectCount = 0);
    void consumeNetworkBytes();
    void handleNetworkFinished();
    void verifySignedManifest();
    void beginPackageDownload();
    void finishPackageDownload();
    void beginStage();
    void startProcess(ProcessPhase phase, const QStringList &arguments, int timeoutMs);
    void consumeStandardOutput();
    void consumeStandardError();
    void consumeProgressLines(const QByteArray &bytes);
    void handleProcessFinished(int exitCode, int exitStatus);
    void handleProcessError();
    void handleCheckFinished();
    void handleStageFinished();
    void finishWithoutUpdate();
    void finishCancellation();
    void fail(const QString &userMessage, const QString &diagnostic = {});
    void clearProcess();
    void clearNetworkRequest();
    void cleanupVerifiedFeed();

    [[nodiscard]] bool parseCheckResult(
            QString *futureVersion, bool *hasUpdate, QString *diagnostic) const;
    [[nodiscard]] bool verifyInstalledLayout();
    [[nodiscard]] bool stagedExecutableExists(const QString &version) const;
    [[nodiscard]] bool verifyStagedInstallation(const QString &version,
            QString *diagnostic = nullptr) const;
    [[nodiscard]] bool validateDownloadUrl(const QUrl &url, DownloadPhase phase,
            int redirectCount, QString *diagnostic) const;
    [[nodiscard]] QUrl immutableAssetUrl(const QString &assetName) const;
    [[nodiscard]] QString immutableTag() const;
    [[nodiscard]] bool nativeRestartPreflight();
    [[nodiscard]] bool updatesSuppressedForThisRun() const;
    void setState(State state);
    void setProgress(int progress);
    void setAvailableVersion(const QString &version);
    void setErrorMessage(const QString &message);
    void setErrorDetails(const QString &details);

    static ProgramUpdater *s_instance;

    State m_state = Unavailable;
    int m_progress = 0;
    QString m_availableVersion;
    QString m_errorMessage;
    QString m_errorDetails;

    QString m_updateExecutable;
    QString m_squirrelRoot;
    QString m_currentAppDirectory;
    QString m_currentVersion;
    QString m_executableRelativePath;
    SquirrelReleaseValidator::ReleaseEntry m_currentRelease;
    SquirrelReleaseValidator::ReleaseEntry m_targetRelease;
    QString m_currentPackagePath;
    QByteArray m_localManifest;

    QNetworkAccessManager *m_network = nullptr;
    QPointer<QNetworkReply> m_reply;
    QSaveFile *m_packageSaveFile = nullptr;
    DownloadPhase m_downloadPhase = DownloadPhase::None;
    QByteArray m_signedManifest;
    QByteArray m_manifestSignature;
    QUrl m_requestedUrl;
    int m_redirectCount = 0;
    qint64 m_packageBytesReceived = 0;
    QString m_verifiedFeedDirectory;
    QString m_verifiedPackagePath;

    QPointer<QProcess> m_process;
    QTimer m_automaticTimer;
    QTimer m_processTimeout;
    ProcessPhase m_processPhase = ProcessPhase::None;
    QByteArray m_standardOutput;
    QByteArray m_standardError;
    QByteArray m_partialProgressLine;
    bool m_userInitiated = false;
    bool m_processCompletionHandled = false;
    bool m_cancelRequested = false;
    int m_consecutiveFailures = 0;
    QString m_lastNotifiedError;
    QHash<QString, RestartDraft> m_restartDrafts;
};
