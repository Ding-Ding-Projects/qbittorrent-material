/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "updaterecovery.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QThread>
#include <QUuid>

#if defined(Q_OS_WIN)
#include <windows.h>
#endif

using namespace Qt::StringLiterals;

namespace
{
constexpr qsizetype kMaximumTransactionBytes = 64 * 1024;
constexpr int kChildStartDeadlineMs = 30 * 1000;
constexpr int kPollIntervalMs = 200;
const QString kRecoveryDirectoryName = u"qbt-update-recovery"_s;

QString recoveryDirectory(const QString &root)
{
    return QDir(root).absoluteFilePath(kRecoveryDirectoryName);
}

QString transactionPath(const QString &root)
{
    return QDir(recoveryDirectory(root)).absoluteFilePath(u"transaction.json"_s);
}

QString markerPath(const QString &root, const QString &kind, const QString &token)
{
    return QDir(recoveryDirectory(root)).absoluteFilePath(kind + u'-' + token + u".json"_s);
}

bool writeAtomically(const QString &path, const QByteArray &bytes, QString *error)
{
    QSaveFile file(path);
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
    {
        if (error)
            *error = u"Could not atomically write "_s + path + u": " + file.errorString();
        return false;
    }
    return true;
}

bool copyAtomically(const QString &source, const QString &destination, QString *error)
{
    QFile input(source);
    QSaveFile output(destination);
    output.setDirectWriteFallback(false);
    if (!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly))
    {
        if (error)
            *error = u"Could not open update recovery package files"_s;
        return false;
    }

    QByteArray buffer;
    buffer.resize(1024 * 1024);
    while (!input.atEnd())
    {
        const qint64 count = input.read(buffer.data(), buffer.size());
        if (count <= 0 || output.write(buffer.constData(), count) != count)
        {
            if (error)
                *error = u"Could not copy the complete recovery package"_s;
            output.cancelWriting();
            return false;
        }
    }
    if (!output.commit())
    {
        if (error)
            *error = u"Could not commit the recovery package: "_s + output.errorString();
        return false;
    }
    return true;
}

bool readJsonObject(const QString &path, QJsonObject *object, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0
            || file.size() > kMaximumTransactionBytes)
    {
        if (error)
            *error = u"Recovery metadata is missing or exceeds its size limit"_s;
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
    {
        if (error)
            *error = u"Recovery metadata is not valid JSON"_s;
        return false;
    }
    *object = document.object();
    return true;
}

QString canonicalExisting(const QString &path)
{
    return QFileInfo(path).canonicalFilePath();
}

bool samePath(const QString &left, const QString &right)
{
#if defined(Q_OS_WIN)
    return QDir::cleanPath(left).compare(QDir::cleanPath(right), Qt::CaseInsensitive) == 0;
#else
    return QDir::cleanPath(left) == QDir::cleanPath(right);
#endif
}

bool immediateAppChild(const QString &root, const QString &path, const QString &version)
{
    const QString expected = QDir(root).absoluteFilePath(u"app-"_s + version);
    return !canonicalExisting(expected).isEmpty()
            && samePath(canonicalExisting(expected), canonicalExisting(path));
}

QString argumentValue(const QStringList &arguments, const QString &name)
{
    const QString prefix = name + u'=';
    for (const QString &argument : arguments)
    {
        if (argument.startsWith(prefix))
            return argument.sliced(prefix.size());
    }
    return {};
}

QStringList preservedArguments(const QStringList &arguments)
{
    QStringList result;
    for (qsizetype index = 1; index < arguments.size(); ++index)
    {
        const QString &argument = arguments.at(index);
        const bool separated = (argument == u"--profile-root"_s)
                || (argument == u"--configuration"_s);
        if (separated && (index + 1 < arguments.size()))
        {
            result << argument << arguments.at(++index);
            continue;
        }
        if (argument.startsWith(u"--profile-root="_s)
                || argument.startsWith(u"--configuration="_s))
        {
            result << argument;
        }
    }
    return result;
}

QString rootFromExecutable(const QString &executablePath)
{
    QDir appDirectory(QFileInfo(executablePath).absolutePath());
    if (!appDirectory.dirName().startsWith(u"app-"_s) || !appDirectory.cdUp())
        return {};
    return appDirectory.canonicalPath();
}

#if defined(Q_OS_WIN)
bool processAliveAndPath(const qint64 pid, QString *imagePath)
{
    HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
            FALSE, DWORD(pid));
    if (!process)
        return false;
    const DWORD wait = WaitForSingleObject(process, 0);
    if (wait != WAIT_TIMEOUT)
    {
        CloseHandle(process);
        return false;
    }

    if (imagePath)
    {
        std::wstring buffer(32768, L'\0');
        DWORD size = DWORD(buffer.size());
        if (QueryFullProcessImageNameW(process, 0, buffer.data(), &size))
            *imagePath = QDir::fromNativeSeparators(QString::fromWCharArray(buffer.data(), size));
        else
            imagePath->clear();
    }
    CloseHandle(process);
    return true;
}
#else
bool processAliveAndPath(const qint64, QString *)
{
    return false;
}
#endif

bool markerMatches(const QString &path, const QString &token, const QString &targetVersion,
        QJsonObject *marker = nullptr)
{
    QJsonObject object;
    if (!readJsonObject(path, &object, nullptr)
            || object.value(u"token"_s).toString() != token
            || object.value(u"targetVersion"_s).toString() != targetVersion)
    {
        return false;
    }
    if (marker)
        *marker = object;
    return true;
}

bool cleanupSuccessfulTransaction(const QString &root, const QString &token)
{
    const QDir directory(recoveryDirectory(root));
    bool ok = true;
    const QStringList names = {
        u"transaction.json"_s,
        u"baseline.json"_s,
        u"previous.RELEASES"_s,
        u"previous.nupkg"_s,
        u"started-"_s + token + u".json"_s,
        u"ready-"_s + token + u".json"_s,
        u"cancel-"_s + token + u".json"_s
    };
    for (const QString &name : names)
    {
        const QString path = directory.absoluteFilePath(name);
        if (QFileInfo::exists(path) && !QFile::remove(path))
            ok = false;
    }
    return ok;
}

bool rollback(const QString &root, const QJsonObject &transaction, QString *error)
{
    QJsonObject baseline;
    if (!readJsonObject(QDir(recoveryDirectory(root)).absoluteFilePath(u"baseline.json"_s),
                &baseline, error))
    {
        return false;
    }

    const QString fromVersion = transaction.value(u"fromVersion"_s).toString();
    const QString targetVersion = transaction.value(u"targetVersion"_s).toString();
    const QString token = transaction.value(u"token"_s).toString();
    const QString packageName = baseline.value(u"packageName"_s).toString();
    SquirrelReleaseValidator::ReleaseEntry release;
    release.fileName = packageName;
    release.sha1Hex = baseline.value(u"sha1"_s).toString().toLatin1();
    release.size = baseline.value(u"size"_s).toString().toLongLong();

    const QDir recovery(recoveryDirectory(root));
    const QString backupPackage = recovery.absoluteFilePath(u"previous.nupkg"_s);
    QString verificationError;
    if (!SquirrelReleaseValidator::isStrictVersion(fromVersion)
            || !SquirrelReleaseValidator::isStrictVersion(targetVersion)
            || !SquirrelReleaseValidator::verifyPackageFile(
                    backupPackage, release, &verificationError))
    {
        if (error)
            *error = u"The recovery package is invalid: "_s + verificationError;
        return false;
    }

    const QDir packages(QDir(root).absoluteFilePath(u"packages"_s));
    const QString targetPackageName = u"qBittorrentMaterial-"_s + targetVersion
            + u"-full.nupkg"_s;
    const QString targetPackage = packages.absoluteFilePath(targetPackageName);
    if (QFileInfo::exists(targetPackage))
    {
        QDir().mkpath(recovery.absoluteFilePath(u"quarantine"_s));
        const QString quarantine = recovery.absoluteFilePath(
                u"quarantine/"_s + targetVersion + u'-' + token + u".nupkg"_s);
        if (!QFile::rename(targetPackage, quarantine))
        {
            if (error)
                *error = u"Could not quarantine the failed candidate package"_s;
            return false;
        }
    }

    if (!copyAtomically(backupPackage, packages.absoluteFilePath(packageName), error))
        return false;

    QFile previousManifest(recovery.absoluteFilePath(u"previous.RELEASES"_s));
    if (!previousManifest.open(QIODevice::ReadOnly)
            || !writeAtomically(packages.absoluteFilePath(u"RELEASES"_s),
                    previousManifest.readAll(), error))
    {
        return false;
    }

    const QString oldExecutable = transaction.value(u"oldExecutable"_s).toString();
    if (canonicalExisting(oldExecutable).isEmpty()
            || !immediateAppChild(root, QFileInfo(oldExecutable).absolutePath(), fromVersion))
    {
        if (error)
            *error = u"The previous executable no longer has the recorded canonical identity"_s;
        return false;
    }

    QJsonObject notice;
    notice.insert(u"schemaVersion"_s, 1);
    notice.insert(u"failedVersion"_s, targetVersion);
    notice.insert(u"restoredVersion"_s, fromVersion);
    notice.insert(u"recordedAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    notice.insert(u"message"_s,
            u"The downloaded update did not reach a healthy launch. The previous program version was restored; user data was not changed."_s);
    if (!writeAtomically(recovery.absoluteFilePath(u"last-recovery.json"_s),
                QJsonDocument(notice).toJson(QJsonDocument::Compact), error))
    {
        return false;
    }

    QStringList launchArguments;
    const QJsonArray savedArguments = transaction.value(u"arguments"_s).toArray();
    for (const QJsonValue &value : savedArguments)
        launchArguments << value.toString();
    qint64 oldPid = 0;
    if (!QProcess::startDetached(oldExecutable, launchArguments,
                QFileInfo(oldExecutable).absolutePath(), &oldPid))
    {
        if (error)
            *error = u"The package was restored, but the previous executable could not be launched"_s;
        return false;
    }

    QFile::remove(transactionPath(root));
    QFile::remove(markerPath(root, u"started"_s, token));
    QFile::remove(markerPath(root, u"ready"_s, token));
    QFile::remove(markerPath(root, u"cancel"_s, token));
    return true;
}
}

namespace UpdateRecovery
{
QStringList preservedLaunchArguments(const QStringList &arguments)
{
    return preservedArguments(arguments);
}

bool prepareBaseline(const Baseline &baseline, QString *error)
{
    if (!SquirrelReleaseValidator::isStrictVersion(baseline.currentVersion)
            || baseline.currentRelease.rawLine.isEmpty())
    {
        if (error)
            *error = u"The current Squirrel release identity is incomplete"_s;
        return false;
    }
    QString verifyError;
    if (!SquirrelReleaseValidator::verifyPackageFile(
                baseline.currentPackagePath, baseline.currentRelease, &verifyError))
    {
        if (error)
            *error = u"The current package cannot be used for recovery: "_s + verifyError;
        return false;
    }

    const QString directory = recoveryDirectory(baseline.squirrelRoot);
    if (!QDir().mkpath(directory))
    {
        if (error)
            *error = u"Could not create the update recovery directory"_s;
        return false;
    }
    const QDir recovery(directory);
    if (!copyAtomically(baseline.currentPackagePath,
                recovery.absoluteFilePath(u"previous.nupkg"_s), error))
    {
        return false;
    }
    if (!writeAtomically(recovery.absoluteFilePath(u"previous.RELEASES"_s),
                baseline.currentRelease.rawLine + '\n', error))
    {
        return false;
    }

    QJsonObject object;
    object.insert(u"schemaVersion"_s, 1);
    object.insert(u"profileFormat"_s, 1);
    object.insert(u"version"_s, baseline.currentVersion);
    object.insert(u"relativeExecutable"_s, baseline.relativeExecutable);
    object.insert(u"packageName"_s, baseline.currentRelease.fileName);
    object.insert(u"sha1"_s, QString::fromLatin1(baseline.currentRelease.sha1Hex));
    object.insert(u"size"_s, QString::number(baseline.currentRelease.size));
    return writeAtomically(recovery.absoluteFilePath(u"baseline.json"_s),
            QJsonDocument(object).toJson(QJsonDocument::Compact), error);
}

bool createRestartTransaction(const QString &squirrelRoot, const QString &fromVersion,
        const QString &targetVersion, const QString &relativeExecutable,
        const QStringList &originalArguments, QString *token, QString *error)
{
    QJsonObject baseline;
    const QString directory = recoveryDirectory(squirrelRoot);
    if (!readJsonObject(QDir(directory).absoluteFilePath(u"baseline.json"_s),
                &baseline, error)
            || baseline.value(u"version"_s).toString() != fromVersion
            || !SquirrelReleaseValidator::isStrictVersion(targetVersion))
    {
        if (error && error->isEmpty())
            *error = u"The update recovery baseline does not match the running version"_s;
        return false;
    }

    const QString attempt = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString oldExecutable = canonicalExisting(QCoreApplication::applicationFilePath());
    const QString targetExecutable = QDir(squirrelRoot).absoluteFilePath(
            u"app-"_s + targetVersion + u'/' + relativeExecutable);
    if (oldExecutable.isEmpty() || canonicalExisting(targetExecutable).isEmpty())
    {
        if (error)
            *error = u"The old or target executable failed canonical restart validation"_s;
        return false;
    }

    QJsonArray arguments;
    for (const QString &argument : preservedLaunchArguments(originalArguments))
        arguments.append(argument);

    QJsonObject object;
    object.insert(u"schemaVersion"_s, 1);
    object.insert(u"profileFormat"_s, 1);
    object.insert(u"token"_s, attempt);
    object.insert(u"fromVersion"_s, fromVersion);
    object.insert(u"targetVersion"_s, targetVersion);
    object.insert(u"oldExecutable"_s, oldExecutable);
    object.insert(u"targetExecutable"_s, canonicalExisting(targetExecutable));
    object.insert(u"relativeExecutable"_s, relativeExecutable);
    object.insert(u"parentPid"_s, QString::number(QCoreApplication::applicationPid()));
    object.insert(u"arguments"_s, arguments);
    object.insert(u"createdAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    if (!writeAtomically(transactionPath(squirrelRoot),
                QJsonDocument(object).toJson(QJsonDocument::Compact), error))
    {
        return false;
    }
    if (token)
        *token = attempt;
    return true;
}

void cancelRestartTransaction(const QString &squirrelRoot, const QString &token)
{
    QJsonObject object;
    object.insert(u"token"_s, token);
    object.insert(u"cancelledAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    writeAtomically(markerPath(squirrelRoot, u"cancel"_s, token),
            QJsonDocument(object).toJson(QJsonDocument::Compact), nullptr);
}

std::optional<int> runWatchdogIfRequested(
        const QStringList &arguments, const QString &executablePath)
{
    const QString token = argumentValue(arguments, u"--update-recovery-watchdog"_s);
    if (token.isEmpty())
        return std::nullopt;

#if !defined(Q_OS_WIN)
    Q_UNUSED(executablePath)
    return 2;
#else
    const QString executable = canonicalExisting(executablePath);
    const QString root = rootFromExecutable(executable);
    QJsonObject transaction;
    QString error;
    if (root.isEmpty() || !readJsonObject(transactionPath(root), &transaction, &error)
            || transaction.value(u"token"_s).toString() != token
            || !samePath(transaction.value(u"oldExecutable"_s).toString(), executable))
    {
        return 2;
    }

    const qint64 parentPid = transaction.value(u"parentPid"_s).toString().toLongLong();
    while (processAliveAndPath(parentPid, nullptr))
    {
        if (QFileInfo::exists(markerPath(root, u"cancel"_s, token)))
        {
            QFile::remove(transactionPath(root));
            return 0;
        }
        QThread::msleep(kPollIntervalMs);
    }

    const QString targetVersion = transaction.value(u"targetVersion"_s).toString();
    const QString expectedTarget = transaction.value(u"targetExecutable"_s).toString();
    QElapsedTimer startDeadline;
    startDeadline.start();
    QJsonObject started;
    while (startDeadline.elapsed() < kChildStartDeadlineMs)
    {
        if (markerMatches(markerPath(root, u"started"_s, token), token,
                    targetVersion, &started))
        {
            break;
        }
        QThread::msleep(kPollIntervalMs);
    }

    if (!started.isEmpty())
    {
        const qint64 childPid = started.value(u"pid"_s).toString().toLongLong();
        while (true)
        {
            if (markerMatches(markerPath(root, u"ready"_s, token), token, targetVersion))
            {
                cleanupSuccessfulTransaction(root, token);
                return 0;
            }

            QString liveImage;
            if (!processAliveAndPath(childPid, &liveImage))
                break;
            if (liveImage.isEmpty() || !samePath(canonicalExisting(liveImage), expectedTarget))
                break;
            // Never terminate a live, unacknowledged app: it may hold user work.
            // The watchdog remains headless and waits for either readiness or a
            // natural exit before restoring the old binary.
            QThread::msleep(kPollIntervalMs);
        }
    }

    if (!rollback(root, transaction, &error))
    {
        QJsonObject notice;
        notice.insert(u"schemaVersion"_s, 1);
        notice.insert(u"failedVersion"_s, targetVersion);
        const QString recoveryMessage = u"Update recovery could not restore the previous binary: "_s + error;
        notice.insert(u"message"_s, recoveryMessage);
        notice.insert(u"recordedAt"_s,
                QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
        writeAtomically(QDir(recoveryDirectory(root)).absoluteFilePath(u"last-recovery.json"_s),
                QJsonDocument(notice).toJson(QJsonDocument::Compact), nullptr);
        return 3;
    }
    return 0;
#endif
}

QString healthToken(const QStringList &arguments)
{
    return argumentValue(arguments, u"--update-health-token"_s);
}

bool acknowledgeStarted(const QStringList &arguments, QString *error)
{
    const QString token = healthToken(arguments);
    if (token.isEmpty())
        return true;
    const QString executable = canonicalExisting(QCoreApplication::applicationFilePath());
    const QString root = rootFromExecutable(executable);
    QJsonObject transaction;
    if (root.isEmpty() || !readJsonObject(transactionPath(root), &transaction, error)
            || transaction.value(u"token"_s).toString() != token
            || !samePath(transaction.value(u"targetExecutable"_s).toString(), executable))
    {
        if (error && error->isEmpty())
            *error = u"The launch-health token does not match this executable"_s;
        return false;
    }

    QJsonObject object;
    object.insert(u"token"_s, token);
    object.insert(u"targetVersion"_s, transaction.value(u"targetVersion"_s).toString());
    object.insert(u"pid"_s, QString::number(QCoreApplication::applicationPid()));
    object.insert(u"executable"_s, executable);
    object.insert(u"startedAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    return writeAtomically(markerPath(root, u"started"_s, token),
            QJsonDocument(object).toJson(QJsonDocument::Compact), error);
}

bool acknowledgeReady(const QStringList &arguments, QString *error)
{
    const QString token = healthToken(arguments);
    if (token.isEmpty())
        return true;
    const QString executable = canonicalExisting(QCoreApplication::applicationFilePath());
    const QString root = rootFromExecutable(executable);
    QJsonObject transaction;
    if (root.isEmpty() || !readJsonObject(transactionPath(root), &transaction, error)
            || transaction.value(u"token"_s).toString() != token
            || !samePath(transaction.value(u"targetExecutable"_s).toString(), executable)
            || !markerMatches(markerPath(root, u"started"_s, token), token,
                    transaction.value(u"targetVersion"_s).toString()))
    {
        if (error && error->isEmpty())
            *error = u"The ready acknowledgement does not match the active update transaction"_s;
        return false;
    }

    QJsonObject object;
    object.insert(u"token"_s, token);
    object.insert(u"targetVersion"_s, transaction.value(u"targetVersion"_s).toString());
    object.insert(u"pid"_s, QString::number(QCoreApplication::applicationPid()));
    object.insert(u"readyAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    return writeAtomically(markerPath(root, u"ready"_s, token),
            QJsonDocument(object).toJson(QJsonDocument::Compact), error);
}

bool takeRecoveryNotice(const QString &squirrelRoot, QString *failedVersion,
        QString *message, QString *error)
{
    const QString path = QDir(recoveryDirectory(squirrelRoot)).absoluteFilePath(
            u"last-recovery.json"_s);
    if (!QFileInfo::exists(path))
        return false;
    QJsonObject object;
    if (!readJsonObject(path, &object, error))
        return false;
    if (failedVersion)
        *failedVersion = object.value(u"failedVersion"_s).toString();
    if (message)
        *message = object.value(u"message"_s).toString();
    if (!QFile::remove(path) && error)
        *error = u"Recovery notice was read but could not be marked consumed"_s;
    return true;
}
}
