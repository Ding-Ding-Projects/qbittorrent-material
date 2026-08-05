/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "programupdater.h"

#include <algorithm>

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QVersionNumber>

#include "base/logging.h"
#include "base/preferences.h"
#include "quick/controllers/optionscontroller.h"
#include "quick/models/workspacemanager.h"
#include "updaterecovery.h"

using namespace Qt::StringLiterals;

#ifndef QBT_UPDATE_FEED_URL
#define QBT_UPDATE_FEED_URL                                                                        \
    "https://github.com/Ding-Ding-Projects/qbittorrent-material/releases/latest/download"
#endif

namespace
{
constexpr int kInitialCheckDelayMs = 20 * 1000;
constexpr int kRegularCheckIntervalMs = 4 * 60 * 60 * 1000;
constexpr int kRegularCheckJitterMs = 5 * 60 * 1000;
constexpr int kFirstRetryDelayMs = 15 * 60 * 1000;
constexpr int kCheckTimeoutMs = 90 * 1000;
constexpr int kStageTimeoutMs = 30 * 60 * 1000;
constexpr qsizetype kMaximumProcessOutput = 1024 * 1024;
constexpr qsizetype kMaximumDiagnosticOutput = 64 * 1024;
constexpr qsizetype kMaximumProgressBuffer = 4 * 1024;
constexpr qsizetype kMaximumManifestBytes = 1024 * 1024;
constexpr qsizetype kMaximumSignatureBytes = 1024;
constexpr qint64 kMaximumPackageBytes = 2LL * 1024 * 1024 * 1024;
constexpr int kMaximumRedirects = 5;

const QString kPendingVersionKey = u"ProgramUpdater/PendingVersion"_s;
const QString kFailedVersionKey = u"ProgramUpdater/FailedVersion"_s;
const QString kFeedUrl = QString::fromUtf8(QBT_UPDATE_FEED_URL);
const QString kReleaseBaseUrl =
        u"https://github.com/Ding-Ding-Projects/qbittorrent-material/releases"_s;
const QString kPackageId = u"qBittorrentMaterial"_s;
const QString kPublicKeyResource = u":/updates/squirrel-feed-public-key.json"_s;

void appendBounded(QByteArray &destination, const QByteArray &bytes, const qsizetype maximum)
{
    if (bytes.isEmpty() || destination.size() >= maximum)
        return;
    destination.append(bytes.left(maximum - destination.size()));
}

bool hasArgument(const QStringList &arguments, const QString &name)
{
    return std::ranges::any_of(arguments, [&name](const QString &argument)
            { return (argument == name) || argument.startsWith(name + u'='); });
}

bool hasSymlinkIdentity(const QFileInfo &info)
{
    return info.isSymLink() || info.isJunction() || !info.symLinkTarget().isEmpty();
}

bool samePath(const QString &left, const QString &right)
{
#if defined(Q_OS_WIN)
    return QDir::cleanPath(left).compare(QDir::cleanPath(right), Qt::CaseInsensitive) == 0;
#else
    return QDir::cleanPath(left) == QDir::cleanPath(right);
#endif
}

bool isImmediateChild(const QString &root, const QString &child)
{
    const QString canonicalRoot = QFileInfo(root).canonicalFilePath();
    const QString canonicalChild = QFileInfo(child).canonicalFilePath();
    return !canonicalRoot.isEmpty() && !canonicalChild.isEmpty()
            && samePath(QFileInfo(canonicalChild).absolutePath(), canonicalRoot);
}

QString quoteWindowsCommandLineArgument(const QString &argument)
{
    if (argument.isEmpty())
        return u"\"\""_s;

    const bool needsQuotes = std::ranges::any_of(argument,
            [](const QChar character) { return character.isSpace() || (character == u'\"'); });
    if (!needsQuotes)
        return argument;

    QString quoted;
    quoted.reserve(argument.size() + 2);
    quoted += u'\"';
    qsizetype consecutiveBackslashes = 0;
    for (const QChar character : argument)
    {
        if (character == u'\\')
        {
            ++consecutiveBackslashes;
            continue;
        }

        if (character == u'\"')
            quoted += QString((consecutiveBackslashes * 2) + 1, u'\\');
        else
            quoted += QString(consecutiveBackslashes, u'\\');
        quoted += character;
        consecutiveBackslashes = 0;
    }
    // Backslashes immediately before a closing quote must themselves be
    // escaped for CommandLineToArgvW-compatible parsing in Update.exe.
    quoted += QString(consecutiveBackslashes * 2, u'\\');
    quoted += u'\"';
    return quoted;
}

QString joinWindowsCommandLine(const QStringList &arguments)
{
    QStringList quotedArguments;
    quotedArguments.reserve(arguments.size());
    for (const QString &argument : arguments)
        quotedArguments << quoteWindowsCommandLineArgument(argument);
    return quotedArguments.join(u' ');
}
} // namespace

ProgramUpdater *ProgramUpdater::s_instance = nullptr;

ProgramUpdater *ProgramUpdater::create(QQmlEngine *, QJSEngine *)
{
    return instance();
}

ProgramUpdater *ProgramUpdater::instance()
{
    if (!s_instance)
    {
        s_instance = new ProgramUpdater(QCoreApplication::instance());
        QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    }
    return s_instance;
}

ProgramUpdater::ProgramUpdater(QObject *parent)
    : QObject(parent)
    , m_network(new QNetworkAccessManager(this))
{
    m_automaticTimer.setSingleShot(true);
    m_processTimeout.setSingleShot(true);

    connect(&m_automaticTimer, &QTimer::timeout, this,
            [this]
            {
                if (!automaticUpdatesEnabled())
                    return;
                beginCheck(false);
            });
    connect(&m_processTimeout, &QTimer::timeout, this,
            [this]
            {
                if (!m_process)
                    return;
                if (m_cancelRequested)
                {
                    m_process->kill();
                    return;
                }
                qCWarning(lcUi) << "Program update process timed out during phase"
                                << int(m_processPhase);
                m_processCompletionHandled = true;
                m_process->kill();
                fail(tr("The update service took too long to respond. Please try again later."),
                        u"Update.exe timed out"_s);
                clearProcess();
            });

    detectInstallation();
    if (!isSupported())
    {
        qCInfo(lcUi) << "Program updates disabled for this process layout";
        return;
    }

    m_state = Idle;

    QString failedVersion;
    QString recoveryMessage;
    QString recoveryError;
    if (UpdateRecovery::takeRecoveryNotice(
                m_squirrelRoot, &failedVersion, &recoveryMessage, &recoveryError))
    {
        if (Preferences *preferences = Preferences::instance())
        {
            preferences->setValue(kFailedVersionKey, failedVersion);
            preferences->apply();
        }
        setAvailableVersion(failedVersion);
        setErrorMessage(recoveryMessage);
        setErrorDetails(tr("The previous executable and package manifest were restored. User "
                           "settings, torrents, and Workspace data were not changed."));
        setState(Recovered);
        emit notificationRequested(recoveryMessage, u"warning"_s, tr("Update rolled back"));
    }
    else if (!recoveryError.isEmpty())
    {
        qCWarning(lcUi).noquote() << "Could not consume update recovery notice:"
                                  << recoveryError;
    }
    restorePendingUpdate();

    if (Preferences *preferences = Preferences::instance())
    {
        connect(preferences, &Preferences::changed, this,
                &ProgramUpdater::handlePreferencesChanged);
    }

    if ((m_state == Idle || m_state == Recovered) && automaticUpdatesEnabled())
        scheduleAutomaticCheck(kInitialCheckDelayMs);
}

ProgramUpdater::State ProgramUpdater::state() const
{
    return m_state;
}

bool ProgramUpdater::isSupported() const
{
    return !m_updateExecutable.isEmpty() && !m_squirrelRoot.isEmpty() &&
            !m_currentAppDirectory.isEmpty() && !m_executableRelativePath.isEmpty();
}

bool ProgramUpdater::isBusy() const
{
    return (m_state == Checking) || (m_state == Verifying) || (m_state == Downloading)
            || (m_state == Staging) || (m_state == Restarting) || (m_state == Cancelling);
}

bool ProgramUpdater::isReadyToRestart() const
{
    return m_state == ReadyToRestart;
}

int ProgramUpdater::progress() const
{
    return m_progress;
}

QString ProgramUpdater::availableVersion() const
{
    return m_availableVersion;
}

QUrl ProgramUpdater::releaseNotesUrl() const
{
    if (!SquirrelReleaseValidator::isStrictVersion(m_availableVersion))
        return {};
    return QUrl(kReleaseBaseUrl + u"/tag/"_s + immutableTag());
}

QString ProgramUpdater::statusMessage() const
{
    switch (m_state)
    {
    case Checking:
        return tr("Checking for updates…");
    case Verifying:
        return tr("Verifying signed update metadata…");
    case Downloading:
        return tr("Downloading and verifying version %1…").arg(m_availableVersion);
    case Staging:
        return tr("Applying version %1 locally…").arg(m_availableVersion);
    case ReadyToRestart:
        return tr("Version %1 is ready to install on restart.").arg(m_availableVersion);
    case Restarting:
        return tr("Starting the verified update…");
    case Cancelling:
        return tr("Cancelling the update operation…");
    case Recovered:
        return tr("The previous version was restored after an unhealthy update launch.");
    case Error:
        return m_errorMessage;
    case Unavailable:
        return tr("Automatic updates are unavailable in this build.");
    case Idle:
        return tr("Updates are checked, downloaded, and staged automatically.");
    }
    return {};
}

QString ProgramUpdater::errorMessage() const
{
    return m_errorMessage;
}

QString ProgramUpdater::errorDetails() const
{
    return m_errorDetails;
}

bool ProgramUpdater::retryAvailable() const
{
    return isSupported() && ((m_state == Error) || (m_state == Recovered));
}

bool ProgramUpdater::cancellable() const
{
    return (m_state == Checking) || (m_state == Verifying) || (m_state == Downloading);
}

void ProgramUpdater::detectInstallation()
{
#if !defined(Q_OS_WIN)
    return;
#else
    if (updatesSuppressedForThisRun())
        return;

    if (!verifyInstalledLayout())
        qCWarning(lcUi) << "Rejected incomplete or non-canonical Squirrel installation layout";
#endif
}

bool ProgramUpdater::verifyInstalledLayout()
{
#if !defined(Q_OS_WIN)
    return false;
#else
    const QFileInfo applicationFile(QCoreApplication::applicationFilePath());
    const QFileInfo applicationDirectory(applicationFile.absolutePath());
    const QRegularExpression appDirectoryExpression(
            uR"(^app-([0-9]+\.[0-9]+\.[0-9]+)$)"_s,
            QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch directoryMatch =
            appDirectoryExpression.match(applicationDirectory.fileName());
    if (!applicationFile.isFile()
            || applicationFile.fileName().compare(u"qbittorrent.exe"_s, Qt::CaseInsensitive) != 0
            || !directoryMatch.hasMatch() || hasSymlinkIdentity(applicationFile)
            || hasSymlinkIdentity(applicationDirectory))
    {
        return false;
    }

    QDir root(applicationDirectory.absolutePath());
    if (!root.cdUp())
        return false;
    const QFileInfo rootInfo(root.absolutePath());
    const QString canonicalRoot = root.canonicalPath();
    const QString canonicalAppDirectory = QFileInfo(applicationDirectory.absoluteFilePath())
                                                  .canonicalFilePath();
    if (canonicalRoot.isEmpty() || canonicalAppDirectory.isEmpty()
            || hasSymlinkIdentity(rootInfo) || !isImmediateChild(canonicalRoot, canonicalAppDirectory)
            || QFileInfo(root.absoluteFilePath(u".dead"_s)).exists())
    {
        return false;
    }

    const QFileInfo updateExecutable(root.absoluteFilePath(u"Update.exe"_s));
    const QFileInfo stableExecutable(root.absoluteFilePath(u"qbittorrent.exe"_s));
    const QFileInfo packagesDirectory(root.absoluteFilePath(u"packages"_s));
    const QFileInfo releasesFile(
            QDir(packagesDirectory.absoluteFilePath()).absoluteFilePath(u"RELEASES"_s));
    if (!updateExecutable.isFile() || !stableExecutable.isFile() || !packagesDirectory.isDir()
            || !releasesFile.isFile() || hasSymlinkIdentity(updateExecutable)
            || hasSymlinkIdentity(stableExecutable) || hasSymlinkIdentity(packagesDirectory)
            || hasSymlinkIdentity(releasesFile)
            || !isImmediateChild(canonicalRoot, updateExecutable.canonicalFilePath())
            || !isImmediateChild(canonicalRoot, stableExecutable.canonicalFilePath())
            || !isImmediateChild(canonicalRoot, packagesDirectory.canonicalFilePath()))
    {
        return false;
    }

    QFile manifestFile(releasesFile.absoluteFilePath());
    if (!manifestFile.open(QIODevice::ReadOnly) || manifestFile.size() <= 0
            || manifestFile.size() > kMaximumManifestBytes)
    {
        return false;
    }
    const QByteArray manifest = manifestFile.readAll();
    const QString version = directoryMatch.captured(1);
    SquirrelReleaseValidator::ReleaseEntry currentRelease;
    QString releaseError;
    if (!SquirrelReleaseValidator::findFullRelease(
                manifest, kPackageId, version, &currentRelease, &releaseError))
    {
        qCWarning(lcUi).noquote() << "Rejected local Squirrel RELEASES:" << releaseError;
        return false;
    }

    const QFileInfo packageFile(
            QDir(packagesDirectory.absoluteFilePath()).absoluteFilePath(currentRelease.fileName));
    if (!packageFile.isFile() || hasSymlinkIdentity(packageFile)
            || !samePath(QFileInfo(packageFile.canonicalFilePath()).absolutePath(),
                    packagesDirectory.canonicalFilePath())
            || !SquirrelReleaseValidator::verifyPackageFile(
                    packageFile.absoluteFilePath(), currentRelease, &releaseError))
    {
        qCWarning(lcUi).noquote() << "Rejected local Squirrel package:" << releaseError;
        return false;
    }

    m_squirrelRoot = canonicalRoot;
    m_currentAppDirectory = canonicalAppDirectory;
    m_currentVersion = version;
    m_updateExecutable = updateExecutable.canonicalFilePath();
    m_executableRelativePath = applicationFile.fileName();
    m_currentRelease = currentRelease;
    m_currentPackagePath = packageFile.canonicalFilePath();
    m_localManifest = manifest;
    qCInfo(lcUi) << "Validated Squirrel updater layout; current version" << m_currentVersion;
    return true;
#endif
}

bool ProgramUpdater::updatesSuppressedForThisRun() const
{
    if (QStandardPaths::isTestModeEnabled())
        return true;

    const QStringList arguments = QCoreApplication::arguments();
    if (hasArgument(arguments, u"--capture-ui"_s) || hasArgument(arguments, u"--test-mode"_s))
    {
        return true;
    }

    const QByteArray disabled = qgetenv("QBT_DISABLE_PROGRAM_UPDATES").trimmed().toLower();
    return (disabled == "1") || (disabled == "true") || (disabled == "yes");
}

void ProgramUpdater::restorePendingUpdate()
{
    Preferences *preferences = Preferences::instance();
    if (!preferences)
        return;

    const QString pendingVersion = preferences->value(kPendingVersionKey).toString().trimmed();
    if (pendingVersion.isEmpty())
        return;

    const QVersionNumber current = QVersionNumber::fromString(m_currentVersion);
    const QVersionNumber pending = QVersionNumber::fromString(pendingVersion);
    const bool alreadyRunningPending = !current.isNull() && !pending.isNull() &&
            (QVersionNumber::compare(current, pending) >= 0);
    if (alreadyRunningPending)
    {
        preferences->setValue(kPendingVersionKey, QString());
        preferences->apply();
        return;
    }

    QString stagedError;
    if (!SquirrelReleaseValidator::isStrictVersion(pendingVersion)
            || !verifyStagedInstallation(pendingVersion, &stagedError))
    {
        qCWarning(lcUi).noquote() << "Discarding stale pending update marker"
                                  << pendingVersion << stagedError;
        preferences->setValue(kPendingVersionKey, QString());
        preferences->apply();
        return;
    }

    setAvailableVersion(pendingVersion);
    setProgress(100);
    setState(ReadyToRestart);
    qCInfo(lcUi) << "Restored staged update marker for" << pendingVersion;
}

bool ProgramUpdater::automaticUpdatesEnabled() const
{
#if defined(Q_OS_WIN)
    if (Preferences *preferences = Preferences::instance())
        return preferences->isUpdateCheckEnabled();
#endif
    return false;
}

void ProgramUpdater::handlePreferencesChanged()
{
    if (!isSupported() || (m_state == ReadyToRestart) || isBusy())
        return;

    if (!automaticUpdatesEnabled())
    {
        m_automaticTimer.stop();
        return;
    }

    if (!m_automaticTimer.isActive())
        scheduleAutomaticCheck(1000);
}

void ProgramUpdater::scheduleAutomaticCheck(const int delayMs)
{
    if (!isSupported() || !automaticUpdatesEnabled() || (m_state == ReadyToRestart))
        return;
    m_automaticTimer.start(std::max(0, delayMs));
}

void ProgramUpdater::scheduleRegularCheck()
{
    m_consecutiveFailures = 0;
    const int jitter = QRandomGenerator::global()->bounded((kRegularCheckJitterMs * 2) + 1) -
            kRegularCheckJitterMs;
    scheduleAutomaticCheck(kRegularCheckIntervalMs + jitter);
}

void ProgramUpdater::scheduleRetry()
{
    ++m_consecutiveFailures;
    const int exponent = std::min(m_consecutiveFailures - 1, 4);
    const qint64 delay = std::min<qint64>(
            qint64(kFirstRetryDelayMs) * (qint64(1) << exponent), kRegularCheckIntervalMs);
    scheduleAutomaticCheck(int(delay));
}

void ProgramUpdater::checkNow()
{
    beginCheck(true);
}

void ProgramUpdater::retry()
{
    if (!retryAvailable())
        return;
    if (Preferences *preferences = Preferences::instance())
    {
        preferences->setValue(kFailedVersionKey, QString());
        preferences->apply();
    }
    beginCheck(true);
}

void ProgramUpdater::cancel()
{
    if (!cancellable())
    {
        if (m_state == Staging)
        {
            emit notificationRequested(
                    tr("The verified package is already being applied. Cancelling now could "
                       "damage the installed program, so this step will finish."),
                    u"warning"_s, tr("Update cannot be cancelled safely"));
        }
        return;
    }

    m_cancelRequested = true;
    setState(Cancelling);
    if (m_reply)
    {
        m_reply->abort();
        return;
    }
    if (m_process)
    {
        m_process->terminate();
        QPointer<QProcess> process = m_process;
        QTimer::singleShot(2000, this,
                [process]
                {
                    if (process && process->state() != QProcess::NotRunning)
                        process->kill();
                });
        return;
    }
    finishCancellation();
}

void ProgramUpdater::setRestartDraftState(const QString &id, const QString &label,
        const bool dirty, QObject *focusTarget)
{
    const QString safeId = id.trimmed().left(128);
    if (safeId.isEmpty())
        return;
    if (!dirty)
    {
        m_restartDrafts.remove(safeId);
        return;
    }
    RestartDraft draft;
    draft.label = label.trimmed().left(256);
    draft.focusTarget = focusTarget;
    m_restartDrafts.insert(safeId, draft);
}

void ProgramUpdater::clearRestartDraftState(const QString &id)
{
    m_restartDrafts.remove(id.trimmed().left(128));
}

void ProgramUpdater::beginCheck(const bool userInitiated)
{
    if (!isSupported())
    {
        const QString message = tr("Automatic updates are available only in the installed Windows "
                                   "version of qBittorrent.");
        setErrorMessage(message);
        emit notificationRequested(message, u"warning"_s, tr("Updates unavailable"));
        return;
    }

    if (m_state == ReadyToRestart)
    {
        emit notificationRequested(tr("Version %1 is already downloaded and ready to install.")
                                           .arg(m_availableVersion),
                u"info"_s, tr("Update ready"));
        return;
    }

    if (isBusy())
    {
        if (userInitiated)
        {
            emit notificationRequested(tr("An update check is already in progress."), u"info"_s,
                    tr("Checking for updates"));
        }
        return;
    }

    m_automaticTimer.stop();
    m_userInitiated = userInitiated;
    m_cancelRequested = false;
    cleanupVerifiedFeed();
    setAvailableVersion({});
    setErrorMessage({});
    setErrorDetails({});
    setProgress(0);
    setState(Checking);
    startProcess(ProcessPhase::Check, {u"--checkForUpdate="_s + kFeedUrl}, kCheckTimeoutMs);
}

QString ProgramUpdater::immutableTag() const
{
    return SquirrelReleaseValidator::isStrictVersion(m_availableVersion)
            ? u'v' + m_availableVersion : QString();
}

QUrl ProgramUpdater::immutableAssetUrl(const QString &assetName) const
{
    if (immutableTag().isEmpty() || assetName.isEmpty() || assetName.contains(u'/')
            || assetName.contains(u'\\') || assetName.contains(u".."_s))
    {
        return {};
    }
    return QUrl(kReleaseBaseUrl + u"/download/"_s + immutableTag() + u'/'
            + QString::fromLatin1(QUrl::toPercentEncoding(assetName)));
}

bool ProgramUpdater::validateDownloadUrl(const QUrl &url, const DownloadPhase phase,
        const int redirectCount, QString *diagnostic) const
{
    if (!url.isValid() || url.scheme().compare(u"https"_s, Qt::CaseInsensitive) != 0
            || !url.userInfo().isEmpty() || (url.port(-1) != -1 && url.port() != 443)
            || redirectCount < 0 || redirectCount > kMaximumRedirects)
    {
        if (diagnostic)
            *diagnostic = u"Rejected non-HTTPS, credentialed, or excessive update redirect"_s;
        return false;
    }

    const QString host = url.host().toLower();
    static const QSet<QString> allowedHosts{
        u"github.com"_s,
        u"release-assets.githubusercontent.com"_s,
        u"objects.githubusercontent.com"_s,
        u"github-releases.githubusercontent.com"_s
    };
    if (!allowedHosts.contains(host))
    {
        if (diagnostic)
            *diagnostic = u"Rejected update redirect host: "_s + host;
        return false;
    }

    if (redirectCount == 0)
    {
        QString asset;
        switch (phase)
        {
        case DownloadPhase::Manifest:
            asset = u"RELEASES"_s;
            break;
        case DownloadPhase::Signature:
            asset = u"RELEASES.sig"_s;
            break;
        case DownloadPhase::Package:
            asset = m_targetRelease.fileName;
            break;
        case DownloadPhase::None:
            return false;
        }
        if (host != u"github.com"_s || url != immutableAssetUrl(asset))
        {
            if (diagnostic)
                *diagnostic = u"The update asset URL does not match the immutable release tag"_s;
            return false;
        }
    }
    return true;
}

void ProgramUpdater::beginSignedFeedVerification()
{
    if (!SquirrelReleaseValidator::isStrictVersion(m_availableVersion))
    {
        fail(tr("The update service returned an invalid version."),
                u"futureVersion is not a strict three-component numeric version"_s);
        return;
    }
    setState(Verifying);
    setProgress(1);
    m_signedManifest.clear();
    m_manifestSignature.clear();
    m_targetRelease = {};
    requestSignedAsset(DownloadPhase::Manifest, immutableAssetUrl(u"RELEASES"_s));
}

void ProgramUpdater::requestSignedAsset(const DownloadPhase phase, const QUrl &url,
        const int redirectCount)
{
    QString diagnostic;
    if (!validateDownloadUrl(url, phase, redirectCount, &diagnostic))
    {
        fail(tr("The signed update location was rejected."), diagnostic);
        return;
    }

    m_downloadPhase = phase;
    m_requestedUrl = url;
    m_redirectCount = redirectCount;
    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
            QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
            QNetworkRequest::AlwaysNetwork);
    request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);
    request.setHeader(QNetworkRequest::UserAgentHeader,
            u"qBittorrent-Material signed updater"_s);

    QNetworkReply *reply = m_network->get(request);
    m_reply = reply;
    connect(reply, &QNetworkReply::readyRead, this, &ProgramUpdater::consumeNetworkBytes);
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, phase](const qint64 received, const qint64 total)
            {
                if (phase != DownloadPhase::Package || total <= 0)
                    return;
                const int value = 5 + int((std::clamp<qint64>(received, 0, total) * 60) / total);
                setProgress(value);
            });
    connect(reply, &QNetworkReply::finished, this, &ProgramUpdater::handleNetworkFinished);
}

void ProgramUpdater::consumeNetworkBytes()
{
    if (!m_reply)
        return;
    if (m_reply->attribute(QNetworkRequest::RedirectionTargetAttribute).isValid())
    {
        m_reply->readAll();
        return;
    }
    const QByteArray bytes = m_reply->readAll();
    if (m_downloadPhase == DownloadPhase::Manifest)
    {
        appendBounded(m_signedManifest, bytes, kMaximumManifestBytes + 1);
        if (m_signedManifest.size() > kMaximumManifestBytes)
            m_reply->abort();
    }
    else if (m_downloadPhase == DownloadPhase::Signature)
    {
        appendBounded(m_manifestSignature, bytes, kMaximumSignatureBytes + 1);
        if (m_manifestSignature.size() > kMaximumSignatureBytes)
            m_reply->abort();
    }
    else if (m_downloadPhase == DownloadPhase::Package)
    {
        m_packageBytesReceived += bytes.size();
        if (!m_packageSaveFile || m_packageBytesReceived > m_targetRelease.size
                || m_packageBytesReceived > kMaximumPackageBytes
                || m_packageSaveFile->write(bytes) != bytes.size())
        {
            m_reply->abort();
        }
    }
}

void ProgramUpdater::handleNetworkFinished()
{
    if (!m_reply)
        return;
    consumeNetworkBytes();

    QNetworkReply *finishedReply = m_reply;
    const DownloadPhase completedPhase = m_downloadPhase;
    const QUrl redirect = finishedReply->attribute(
            QNetworkRequest::RedirectionTargetAttribute).toUrl();
    const int status = finishedReply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError networkError = finishedReply->error();
    const QString networkErrorText = finishedReply->errorString().left(512);
    m_reply.clear();
    finishedReply->deleteLater();

    if (m_cancelRequested)
    {
        finishCancellation();
        return;
    }

    if (!redirect.isEmpty())
    {
        const QUrl resolved = m_requestedUrl.resolved(redirect);
        requestSignedAsset(completedPhase, resolved, m_redirectCount + 1);
        return;
    }

    if (networkError != QNetworkReply::NoError || status != 200)
    {
        fail(tr("Could not download the signed update assets. Please try again later."),
                tr("HTTPS request to %1%2 failed with status %3: %4")
                        .arg(m_requestedUrl.host(), m_requestedUrl.path())
                        .arg(status)
                        .arg(networkErrorText));
        return;
    }

    if (completedPhase == DownloadPhase::Manifest)
    {
        if (m_signedManifest.isEmpty() || m_signedManifest.size() > kMaximumManifestBytes)
        {
            fail(tr("The signed update manifest is missing or too large."),
                    u"RELEASES violated its 1 MiB bound"_s);
            return;
        }
        setProgress(3);
        requestSignedAsset(DownloadPhase::Signature,
                immutableAssetUrl(u"RELEASES.sig"_s));
    }
    else if (completedPhase == DownloadPhase::Signature)
    {
        verifySignedManifest();
    }
    else if (completedPhase == DownloadPhase::Package)
    {
        finishPackageDownload();
    }
}

void ProgramUpdater::verifySignedManifest()
{
    QFile keyFile(kPublicKeyResource);
    QString diagnostic;
    if (!keyFile.open(QIODevice::ReadOnly)
            || !SquirrelReleaseValidator::verifyManifestSignature(m_signedManifest,
                    m_manifestSignature, keyFile.readAll(), &diagnostic))
    {
        fail(tr("The update signature is missing or invalid. Nothing was installed."), diagnostic);
        return;
    }
    if (!SquirrelReleaseValidator::findFullRelease(m_signedManifest, kPackageId,
                m_availableVersion, &m_targetRelease, &diagnostic)
            || m_targetRelease.size <= 0 || m_targetRelease.size > kMaximumPackageBytes)
    {
        fail(tr("The signed update manifest does not describe the expected package."), diagnostic);
        return;
    }

    m_verifiedFeedDirectory = QDir(m_squirrelRoot).absoluteFilePath(
            u"qbt-verified-feed/"_s + m_availableVersion);
    if (!QDir().mkpath(m_verifiedFeedDirectory))
    {
        fail(tr("Could not prepare the verified update locally."),
                u"Could not create the private verified-feed directory"_s);
        return;
    }

    QSaveFile manifestFile(QDir(m_verifiedFeedDirectory).absoluteFilePath(u"RELEASES"_s));
    QSaveFile signatureFile(
            QDir(m_verifiedFeedDirectory).absoluteFilePath(u"RELEASES.sig"_s));
    manifestFile.setDirectWriteFallback(false);
    signatureFile.setDirectWriteFallback(false);
    if (!manifestFile.open(QIODevice::WriteOnly)
            || manifestFile.write(m_signedManifest) != m_signedManifest.size()
            || !manifestFile.commit() || !signatureFile.open(QIODevice::WriteOnly)
            || signatureFile.write(m_manifestSignature) != m_manifestSignature.size()
            || !signatureFile.commit())
    {
        fail(tr("Could not store the verified update metadata locally."),
                u"Atomic verified-feed metadata write failed"_s);
        return;
    }
    setProgress(5);
    beginPackageDownload();
}

void ProgramUpdater::beginPackageDownload()
{
    setState(Downloading);
    m_verifiedPackagePath = QDir(m_verifiedFeedDirectory).absoluteFilePath(
            m_targetRelease.fileName);
    delete m_packageSaveFile;
    m_packageSaveFile = new QSaveFile(m_verifiedPackagePath);
    m_packageSaveFile->setDirectWriteFallback(false);
    m_packageBytesReceived = 0;
    if (!m_packageSaveFile->open(QIODevice::WriteOnly))
    {
        fail(tr("Could not prepare the update package download."),
                m_packageSaveFile->errorString());
        return;
    }
    requestSignedAsset(DownloadPhase::Package,
            immutableAssetUrl(m_targetRelease.fileName));
}

void ProgramUpdater::finishPackageDownload()
{
    QString diagnostic;
    if (!m_packageSaveFile || m_packageBytesReceived != m_targetRelease.size
            || !m_packageSaveFile->commit())
    {
        if (m_packageSaveFile)
            diagnostic = m_packageSaveFile->errorString();
        fail(tr("The update package download was incomplete. Nothing was installed."), diagnostic);
        return;
    }
    delete m_packageSaveFile;
    m_packageSaveFile = nullptr;

    if (!SquirrelReleaseValidator::verifyPackageFile(
                m_verifiedPackagePath, m_targetRelease, &diagnostic))
    {
        fail(tr("The downloaded update package is corrupt. Nothing was installed."), diagnostic);
        return;
    }

    UpdateRecovery::Baseline baseline;
    baseline.squirrelRoot = m_squirrelRoot;
    baseline.currentVersion = m_currentVersion;
    baseline.relativeExecutable = m_executableRelativePath;
    baseline.currentPackagePath = m_currentPackagePath;
    baseline.currentManifest = m_localManifest;
    baseline.currentRelease = m_currentRelease;
    if (!UpdateRecovery::prepareBaseline(baseline, &diagnostic))
    {
        fail(tr("The update was verified, but a safe rollback copy could not be prepared. "
                "Nothing was installed."), diagnostic);
        return;
    }
    beginStage();
}

void ProgramUpdater::beginStage()
{
    setState(Staging);
    setProgress(66);
    startProcess(ProcessPhase::Stage,
            {u"--update="_s + QDir::toNativeSeparators(m_verifiedFeedDirectory)},
            kStageTimeoutMs);
}

void ProgramUpdater::startProcess(
        const ProcessPhase phase, const QStringList &arguments, const int timeoutMs)
{
    clearProcess();
    m_processPhase = phase;
    m_processCompletionHandled = false;
    m_standardOutput.clear();
    m_standardError.clear();
    m_partialProgressLine.clear();

    auto *process = new QProcess(this);
    m_process = process;
    process->setProgram(m_updateExecutable);
    process->setArguments(arguments);
    process->setWorkingDirectory(m_squirrelRoot);
    process->setProcessChannelMode(QProcess::SeparateChannels);

    connect(process, &QProcess::readyReadStandardOutput, this,
            &ProgramUpdater::consumeStandardOutput);
    connect(process, &QProcess::readyReadStandardError, this,
            &ProgramUpdater::consumeStandardError);
    connect(process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error)
            {
                if (error == QProcess::FailedToStart)
                    handleProcessError();
            });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this](const int exitCode, const QProcess::ExitStatus exitStatus)
            { handleProcessFinished(exitCode, int(exitStatus)); });

    qCInfo(lcUi) << "Starting Squirrel Update.exe phase" << int(phase);
    process->start();
    m_processTimeout.start(timeoutMs);
}

void ProgramUpdater::consumeStandardOutput()
{
    if (!m_process)
        return;
    const QByteArray bytes = m_process->readAllStandardOutput();
    appendBounded(m_standardOutput, bytes, kMaximumProcessOutput);
    if (m_processPhase == ProcessPhase::Stage)
        consumeProgressLines(bytes);
}

void ProgramUpdater::consumeStandardError()
{
    if (m_process)
        appendBounded(m_standardError, m_process->readAllStandardError(), kMaximumDiagnosticOutput);
}

void ProgramUpdater::consumeProgressLines(const QByteArray &bytes)
{
    appendBounded(m_partialProgressLine, bytes, kMaximumProgressBuffer);
    while (true)
    {
        const qsizetype lineEnd = m_partialProgressLine.indexOf('\n');
        if (lineEnd < 0)
            break;
        const QByteArray line = m_partialProgressLine.left(lineEnd).trimmed();
        m_partialProgressLine.remove(0, lineEnd + 1);
        bool ok = false;
        const int value = line.toInt(&ok);
        if (!ok || value < 0 || value > 100)
            continue;
        // Network download and cryptographic verification already completed.
        // Map Squirrel's local apply progress into the final third so progress
        // never jumps backwards when control passes to Update.exe.
        setProgress(66 + ((value * 33) / 100));
    }

    // A malformed updater must not grow a never-terminated progress line for
    // the lifetime of the app. Native Squirrel progress lines are at most
    // three bytes, so dropping an oversized remainder cannot hide valid state.
    if (m_partialProgressLine.size() >= kMaximumProgressBuffer)
        m_partialProgressLine.clear();
}

void ProgramUpdater::handleProcessError()
{
    if (m_processCompletionHandled)
        return;
    m_processCompletionHandled = true;
    consumeStandardError();
    if (m_cancelRequested)
    {
        clearProcess();
        finishCancellation();
        return;
    }
    fail(tr("Could not start the update service. Please try again later."),
            QString::fromUtf8(m_standardError));
    clearProcess();
}

void ProgramUpdater::handleProcessFinished(const int exitCode, const int exitStatus)
{
    if (m_processCompletionHandled)
        return;
    m_processCompletionHandled = true;
    m_processTimeout.stop();
    consumeStandardOutput();
    consumeStandardError();

    if (m_cancelRequested)
    {
        clearProcess();
        finishCancellation();
        return;
    }

    if ((exitStatus != int(QProcess::NormalExit)) || (exitCode != 0))
    {
        const QString diagnostic = tr("Update.exe exited with code %1. %2")
                                           .arg(exitCode)
                                           .arg(QString::fromUtf8(m_standardError).trimmed());
        fail(tr("Could not complete the update. Please try again later."), diagnostic);
        clearProcess();
        return;
    }

    const ProcessPhase completedPhase = m_processPhase;
    clearProcess();
    if (completedPhase == ProcessPhase::Check)
        handleCheckFinished();
    else if (completedPhase == ProcessPhase::Stage)
        handleStageFinished();
}

void ProgramUpdater::handleCheckFinished()
{
    QString futureVersion;
    QString diagnostic;
    bool hasUpdate = false;
    if (!parseCheckResult(&futureVersion, &hasUpdate, &diagnostic))
    {
        fail(tr("Could not understand the update service response."), diagnostic);
        return;
    }

    if (!hasUpdate)
    {
        finishWithoutUpdate();
        return;
    }

    setAvailableVersion(futureVersion);
    if (Preferences *preferences = Preferences::instance())
    {
        const QString failedVersion = preferences->value(kFailedVersionKey).toString();
        if (!m_userInitiated && failedVersion == futureVersion)
        {
            m_userInitiated = false;
            setProgress(0);
            setState(Recovered);
            scheduleRegularCheck();
            return;
        }
    }
    beginSignedFeedVerification();
}

void ProgramUpdater::handleStageFinished()
{
    QString diagnostic;
    if (m_availableVersion.isEmpty()
            || !verifyStagedInstallation(m_availableVersion, &diagnostic))
    {
        fail(tr("The update finished downloading but could not be verified for restart."),
                diagnostic);
        return;
    }

    if (Preferences *preferences = Preferences::instance())
    {
        preferences->setValue(kPendingVersionKey, m_availableVersion);
        preferences->apply();
    }

    m_consecutiveFailures = 0;
    m_lastNotifiedError.clear();
    setErrorMessage({});
    setProgress(100);
    setState(ReadyToRestart);
    cleanupVerifiedFeed();
    qCInfo(lcUi) << "Program update staged and ready to restart:" << m_availableVersion;
}

void ProgramUpdater::finishWithoutUpdate()
{
    const bool notify = m_userInitiated;
    m_userInitiated = false;
    // A successful check ends the current outage. Let a later, independent
    // failure with the same user-facing text notify again instead of being
    // mistaken for a duplicate from the recovered incident.
    m_lastNotifiedError.clear();
    setProgress(0);
    setErrorMessage({});
    setState(Idle);
    scheduleRegularCheck();
    if (notify)
    {
        emit notificationRequested(
                tr("qBittorrent is up to date."), u"success"_s, tr("No updates available"));
    }
}

void ProgramUpdater::finishCancellation()
{
    clearNetworkRequest();
    clearProcess();
    cleanupVerifiedFeed();
    m_cancelRequested = false;
    m_userInitiated = false;
    setAvailableVersion({});
    setProgress(0);
    setErrorMessage({});
    setErrorDetails({});
    setState(Idle);
    scheduleRegularCheck();
    emit notificationRequested(tr("The update operation was cancelled. No update was installed."),
            u"info"_s, tr("Update cancelled"));
}

void ProgramUpdater::fail(const QString &userMessage, const QString &diagnostic)
{
    if (!diagnostic.trimmed().isEmpty())
        qCWarning(lcUi).noquote() << "Program updater failure:" << diagnostic.trimmed();
    else
        qCWarning(lcUi).noquote() << "Program updater failure:" << userMessage;

    const bool shouldNotify = m_userInitiated || (m_lastNotifiedError != userMessage);
    m_userInitiated = false;
    m_cancelRequested = false;
    clearNetworkRequest();
    if (m_process)
    {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->kill();
    }
    clearProcess();
    cleanupVerifiedFeed();
    setErrorMessage(userMessage);
    setErrorDetails(diagnostic.trimmed().left(kMaximumDiagnosticOutput));
    setState(Error);
    scheduleRetry();
    if (shouldNotify)
    {
        m_lastNotifiedError = userMessage;
        emit notificationRequested(userMessage, u"error"_s, tr("Update failed"));
    }
}

void ProgramUpdater::clearProcess()
{
    m_processTimeout.stop();
    if (m_process)
    {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->deleteLater();
        m_process.clear();
    }
    m_processPhase = ProcessPhase::None;
}

void ProgramUpdater::clearNetworkRequest()
{
    if (m_reply)
    {
        disconnect(m_reply, nullptr, this, nullptr);
        m_reply->abort();
        m_reply->deleteLater();
        m_reply.clear();
    }
    if (m_packageSaveFile)
    {
        m_packageSaveFile->cancelWriting();
        delete m_packageSaveFile;
        m_packageSaveFile = nullptr;
    }
    m_downloadPhase = DownloadPhase::None;
    m_requestedUrl = {};
    m_redirectCount = 0;
    m_packageBytesReceived = 0;
}

void ProgramUpdater::cleanupVerifiedFeed()
{
    if (m_verifiedFeedDirectory.isEmpty())
        return;
    const QString expectedRoot = QDir(m_squirrelRoot).absoluteFilePath(u"qbt-verified-feed"_s);
    const QString cleanDirectory = QDir::cleanPath(m_verifiedFeedDirectory);
    const QString cleanRoot = QDir::cleanPath(expectedRoot);
    const QString prefix = cleanRoot + QDir::separator();
#if defined(Q_OS_WIN)
    const bool owned = cleanDirectory.startsWith(prefix, Qt::CaseInsensitive);
#else
    const bool owned = cleanDirectory.startsWith(prefix);
#endif
    if (!owned || !SquirrelReleaseValidator::isStrictVersion(QFileInfo(cleanDirectory).fileName()))
    {
        qCWarning(lcUi) << "Refusing to clean an unowned verified-feed path" << cleanDirectory;
        m_verifiedFeedDirectory.clear();
        m_verifiedPackagePath.clear();
        return;
    }

    const QDir directory(cleanDirectory);
    const QStringList files{u"RELEASES"_s, u"RELEASES.sig"_s,
            m_targetRelease.fileName};
    for (const QString &name : files)
    {
        if (!name.isEmpty() && !name.contains(u'/') && !name.contains(u'\\'))
            QFile::remove(directory.absoluteFilePath(name));
    }
    QDir().rmdir(cleanDirectory);
    QDir().rmdir(cleanRoot);
    m_verifiedFeedDirectory.clear();
    m_verifiedPackagePath.clear();
}

bool ProgramUpdater::parseCheckResult(
        QString *futureVersion, bool *hasUpdate, QString *diagnostic) const
{
    const QList<QByteArray> lines = m_standardOutput.split('\n');
    for (auto it = lines.crbegin(); it != lines.crend(); ++it)
    {
        const QByteArray candidate = it->trimmed();
        if (!candidate.startsWith('{'))
            continue;

        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(candidate, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject())
            continue;

        const QJsonObject object = document.object();
        const QJsonValue releasesValue = object.value(u"releasesToApply"_s);
        if (!releasesValue.isArray())
            continue;

        const QJsonArray releases = releasesValue.toArray();
        *hasUpdate = !releases.isEmpty();
        *futureVersion = object.value(u"futureVersion"_s).toString().trimmed().left(128);
        if (*hasUpdate && !SquirrelReleaseValidator::isStrictVersion(*futureVersion))
        {
            if (diagnostic)
                *diagnostic = u"Update response omitted a strict numeric futureVersion"_s;
            return false;
        }
        return true;
    }

    if (diagnostic)
        *diagnostic = u"No valid Squirrel update JSON object was found"_s;
    return false;
}

bool ProgramUpdater::verifyStagedInstallation(
        const QString &version, QString *diagnostic) const
{
    if (!SquirrelReleaseValidator::isStrictVersion(version))
    {
        if (diagnostic)
            *diagnostic = u"The staged version is not a strict numeric version"_s;
        return false;
    }

    const QFileInfo rootInfo(m_squirrelRoot);
    const QFileInfo stagedDirectory(
            QDir(m_squirrelRoot).absoluteFilePath(u"app-"_s + version));
    const QFileInfo stagedExecutable(
            QDir(stagedDirectory.absoluteFilePath()).absoluteFilePath(m_executableRelativePath));
    if (!rootInfo.isDir() || !stagedDirectory.isDir() || !stagedExecutable.isFile()
            || hasSymlinkIdentity(stagedDirectory) || hasSymlinkIdentity(stagedExecutable)
            || !isImmediateChild(m_squirrelRoot, stagedDirectory.canonicalFilePath())
            || !samePath(QFileInfo(stagedExecutable.canonicalFilePath()).absolutePath(),
                    stagedDirectory.canonicalFilePath()))
    {
        if (diagnostic)
            *diagnostic = u"The staged app directory or executable failed canonical path checks"_s;
        return false;
    }

    const QDir packages(QDir(m_squirrelRoot).absoluteFilePath(u"packages"_s));
    const QFileInfo releasesFile(packages.absoluteFilePath(u"RELEASES"_s));
    if (!releasesFile.isFile() || hasSymlinkIdentity(releasesFile)
            || releasesFile.size() <= 0 || releasesFile.size() > kMaximumManifestBytes)
    {
        if (diagnostic)
            *diagnostic = u"The local RELEASES file is missing or invalid after staging"_s;
        return false;
    }
    QFile manifestFile(releasesFile.absoluteFilePath());
    if (!manifestFile.open(QIODevice::ReadOnly))
    {
        if (diagnostic)
            *diagnostic = u"The local RELEASES file could not be read after staging"_s;
        return false;
    }

    SquirrelReleaseValidator::ReleaseEntry stagedRelease;
    if (!SquirrelReleaseValidator::findFullRelease(manifestFile.readAll(), kPackageId,
                version, &stagedRelease, diagnostic))
    {
        return false;
    }
    const QFileInfo stagedPackage(packages.absoluteFilePath(stagedRelease.fileName));
    if (!stagedPackage.isFile() || hasSymlinkIdentity(stagedPackage)
            || !samePath(QFileInfo(stagedPackage.canonicalFilePath()).absolutePath(),
                    packages.canonicalPath()))
    {
        if (diagnostic)
            *diagnostic = u"The staged full package failed canonical path checks"_s;
        return false;
    }
    return SquirrelReleaseValidator::verifyPackageFile(
            stagedPackage.absoluteFilePath(), stagedRelease, diagnostic);
}

bool ProgramUpdater::stagedExecutableExists(const QString &version) const
{
    if (!SquirrelReleaseValidator::isStrictVersion(version) || m_squirrelRoot.isEmpty()
            || m_executableRelativePath.isEmpty())
    {
        return false;
    }
    const QFileInfo stagedDirectory(
            QDir(m_squirrelRoot).absoluteFilePath(u"app-"_s + version));
    const QFileInfo stagedExecutable(
            QDir(stagedDirectory.absoluteFilePath()).absoluteFilePath(m_executableRelativePath));
    return stagedDirectory.isDir() && stagedExecutable.isFile()
            && !hasSymlinkIdentity(stagedDirectory) && !hasSymlinkIdentity(stagedExecutable)
            && isImmediateChild(m_squirrelRoot, stagedDirectory.canonicalFilePath())
            && samePath(QFileInfo(stagedExecutable.canonicalFilePath()).absolutePath(),
                    stagedDirectory.canonicalFilePath());
}

bool ProgramUpdater::nativeRestartPreflight()
{
    for (auto it = m_restartDrafts.cbegin(); it != m_restartDrafts.cend(); ++it)
    {
        const QString label = it->label.isEmpty() ? tr("an open editor") : it->label;
        const QString message = tr("Apply or cancel changes in %1 before restarting.").arg(label);
        emit restartPreflightBlocked(u"draft"_s, it.key(), it->focusTarget, message);
        return false;
    }

    OptionsController *options = OptionsController::existingInstance();
    if (!options)
    {
        const QString message = tr("The Options restart guard is unavailable. Restart was stopped "
                                   "to protect unsaved settings.");
        emit restartPreflightBlocked(u"guard"_s, u"options"_s, nullptr, message);
        return false;
    }
    if (options->isModified())
    {
        const QString message = tr("Apply or cancel the pending Options changes before restarting "
                                   "to install version %1.").arg(m_availableVersion);
        emit restartPreflightBlocked(u"options"_s, u"options"_s, options, message);
        return false;
    }

    WorkspaceManager *workspace = WorkspaceManager::existingInstance();
    if (!workspace)
    {
        const QString message = tr("The Workspace restart guard is unavailable. Restart was stopped "
                                   "to protect unsaved work.");
        emit restartPreflightBlocked(u"guard"_s, u"workspace"_s, nullptr, message);
        return false;
    }
    if (workspace->dirty() && !workspace->syncNow())
    {
        const QString message = tr("Workspace changes could not be checkpointed. The current "
                                   "session remains open and the update is still ready.");
        emit restartPreflightBlocked(u"workspace"_s, u"workspace"_s, workspace, message);
        return false;
    }
    return true;
}

void ProgramUpdater::restartToUpdate()
{
    if (m_state != ReadyToRestart)
        return;

    QString diagnostic;
    if (!stagedExecutableExists(m_availableVersion)
            || !QFileInfo(m_updateExecutable).isFile()
            || !verifyStagedInstallation(m_availableVersion, &diagnostic))
    {
        fail(tr("The staged update is no longer available. Check for updates again."),
                diagnostic.isEmpty()
                        ? u"Restart preflight could not validate Update.exe or the staged package"_s
                        : diagnostic);
        return;
    }
    if (!nativeRestartPreflight())
        return;

    QString healthToken;
    if (!UpdateRecovery::createRestartTransaction(m_squirrelRoot, m_currentVersion,
                m_availableVersion, m_executableRelativePath,
                QCoreApplication::arguments(), &healthToken, &diagnostic))
    {
        fail(tr("The update is ready, but restart recovery could not be prepared. Your current "
                "session is still running."), diagnostic);
        return;
    }

    qint64 watchdogPid = 0;
    const bool watchdogStarted = QProcess::startDetached(
            QCoreApplication::applicationFilePath(),
            {u"--update-recovery-watchdog="_s + healthToken},
            m_currentAppDirectory, &watchdogPid);
    if (!watchdogStarted)
    {
        UpdateRecovery::cancelRestartTransaction(m_squirrelRoot, healthToken);
        fail(tr("Could not start update recovery. Your current session is still running."),
                u"The old-binary recovery watchdog did not launch"_s);
        return;
    }

    // Update.exe accepts one Windows command-line string for the target. Carry
    // only the same allowlisted profile/configuration arguments captured for
    // rollback, so a custom-profile instance never restarts into the default
    // profile and arbitrary launch arguments cannot cross the updater boundary.
    QStringList targetArguments{u"--update-health-token="_s + healthToken};
    targetArguments << UpdateRecovery::preservedLaunchArguments(
            QCoreApplication::arguments());

    qint64 updaterPid = 0;
    const QStringList arguments{
        u"--processStartAndWait="_s + m_executableRelativePath,
        u"--process-start-args="_s + joinWindowsCommandLine(targetArguments)
    };
    const bool started =
            QProcess::startDetached(m_updateExecutable, arguments, m_squirrelRoot, &updaterPid);
    if (!started)
    {
        UpdateRecovery::cancelRestartTransaction(m_squirrelRoot, healthToken);
        fail(tr("Could not restart into the downloaded update. Your current session is still "
                "running."),
                u"Update.exe --processStartAndWait failed to launch"_s);
        return;
    }

    qCInfo(lcUi) << "Squirrel restart helper started with pid" << updaterPid
                 << "and recovery watchdog pid" << watchdogPid;
    setState(Restarting);
    // Squirrel resolves its parent PID before waiting for this process to
    // finish. Give the freshly-started helper the same short rendezvous window
    // used by its native RestartApp implementation, then close cleanly so the
    // application releases its single-instance state before the new build runs.
    QTimer::singleShot(500, QCoreApplication::instance(), &QCoreApplication::quit);
}

void ProgramUpdater::setState(const State state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

void ProgramUpdater::setProgress(const int progress)
{
    const int safeProgress = std::clamp(progress, 0, 100);
    if (m_progress == safeProgress)
        return;
    m_progress = safeProgress;
    emit progressChanged();
}

void ProgramUpdater::setAvailableVersion(const QString &version)
{
    if (m_availableVersion == version)
        return;
    m_availableVersion = version;
    emit availableVersionChanged();
}

void ProgramUpdater::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void ProgramUpdater::setErrorDetails(const QString &details)
{
    if (m_errorDetails == details)
        return;
    m_errorDetails = details;
    emit errorDetailsChanged();
}
