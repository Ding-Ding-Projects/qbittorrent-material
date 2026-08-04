/*
 * qBittorrent (Material rewrite) — Squirrel.Windows lifecycle integration
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "squirrellifecycle.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QProcess>
#include <QString>
#include <QStringList>

#include <vector>

#include "base/logging.h"

#ifdef Q_OS_WIN
#include <windows.h>
#include <ShlObj.h>
#endif

using namespace Qt::StringLiterals;

namespace
{
#ifdef Q_OS_WIN
    constexpr auto BackupRoot = L"Software\\qBittorrentMaterial\\AssociationBackup";
    constexpr auto ClassesRoot = L"Software\\Classes\\";

    struct RegistryString
    {
        bool present = false;
        QString value;
        DWORD type = REG_SZ;
    };

    QString nativePath(const QString &path)
    {
        return QDir::toNativeSeparators(QFileInfo(path).absoluteFilePath());
    }

    std::wstring wide(const QString &value)
    {
        return value.toStdWString();
    }

    RegistryString readString(HKEY root, const QString &subKey, const QString &valueName = {})
    {
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegOpenKeyExW(root, keyName.c_str(), 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS)
            return {};

        const std::wstring name = wide(valueName);
        const wchar_t *namePointer = valueName.isEmpty() ? nullptr : name.c_str();
        DWORD type = 0;
        DWORD byteCount = 0;
        const LSTATUS sizeStatus = RegQueryValueExW(
            key, namePointer, nullptr, &type, nullptr, &byteCount);
        if (sizeStatus != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ))
        {
            RegCloseKey(key);
            return {};
        }

        std::vector<wchar_t> buffer((byteCount / sizeof(wchar_t)) + 1, L'\0');
        const LSTATUS readStatus = RegQueryValueExW(
            key, namePointer, nullptr, &type,
            reinterpret_cast<LPBYTE>(buffer.data()), &byteCount);
        RegCloseKey(key);
        if (readStatus != ERROR_SUCCESS)
            return {};

        return {true, QString::fromWCharArray(buffer.data()), type};
    }

    bool writeString(
        HKEY root, const QString &subKey, const QString &valueName,
        const QString &value, DWORD type = REG_SZ)
    {
        if (type != REG_SZ && type != REG_EXPAND_SZ)
            return false;
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegCreateKeyExW(root, keyName.c_str(), 0, nullptr, 0, KEY_SET_VALUE,
                nullptr, &key, nullptr) != ERROR_SUCCESS)
            return false;

        const std::wstring name = wide(valueName);
        const wchar_t *namePointer = valueName.isEmpty() ? nullptr : name.c_str();
        const std::wstring data = wide(value);
        const LSTATUS status = RegSetValueExW(key, namePointer, 0, type,
            reinterpret_cast<const BYTE *>(data.c_str()),
            static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(key);
        return status == ERROR_SUCCESS;
    }

    bool writeDword(const QString &subKey, const QString &valueName, DWORD value)
    {
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegCreateKeyExW(HKEY_CURRENT_USER, keyName.c_str(), 0, nullptr, 0,
                KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS)
            return false;
        const std::wstring name = wide(valueName);
        const LSTATUS status = RegSetValueExW(key, name.c_str(), 0, REG_DWORD,
            reinterpret_cast<const BYTE *>(&value), sizeof(value));
        RegCloseKey(key);
        return status == ERROR_SUCCESS;
    }

    std::optional<DWORD> readDword(const QString &subKey, const QString &valueName)
    {
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegOpenKeyExW(HKEY_CURRENT_USER, keyName.c_str(), 0,
                KEY_QUERY_VALUE, &key) != ERROR_SUCCESS)
            return std::nullopt;
        DWORD type = 0;
        DWORD value = 0;
        DWORD byteCount = sizeof(value);
        const std::wstring name = wide(valueName);
        const LSTATUS status = RegQueryValueExW(key, name.c_str(), nullptr, &type,
            reinterpret_cast<LPBYTE>(&value), &byteCount);
        RegCloseKey(key);
        if (status != ERROR_SUCCESS || type != REG_DWORD || byteCount != sizeof(value))
            return std::nullopt;
        return value;
    }

    void deleteValue(HKEY root, const QString &subKey, const QString &valueName = {})
    {
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegOpenKeyExW(root, keyName.c_str(), 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS)
            return;
        const std::wstring name = wide(valueName);
        RegDeleteValueW(key, valueName.isEmpty() ? nullptr : name.c_str());
        RegCloseKey(key);
    }

    void deleteKeyIfEmpty(HKEY root, const QString &subKey)
    {
        const std::wstring keyName = wide(subKey);
        HKEY key = nullptr;
        if (RegOpenKeyExW(root, keyName.c_str(), 0,
                KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS, &key) != ERROR_SUCCESS)
        {
            return;
        }
        DWORD subKeyCount = 0;
        DWORD valueCount = 0;
        const LSTATUS status = RegQueryInfoKeyW(key, nullptr, nullptr, nullptr,
            &subKeyCount, nullptr, nullptr, &valueCount,
            nullptr, nullptr, nullptr, nullptr);
        RegCloseKey(key);
        if (status == ERROR_SUCCESS && subKeyCount == 0 && valueCount == 0)
            RegDeleteKeyW(root, keyName.c_str());
    }

    bool keyExists(HKEY root, const QString &subKey)
    {
        HKEY key = nullptr;
        const std::wstring keyName = wide(subKey);
        if (RegOpenKeyExW(
                root, keyName.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS)
            return false;
        RegCloseKey(key);
        return true;
    }

    void restoreKeyPresence(
        const QString &backupKey,
        const QString &presenceName,
        HKEY destinationRoot,
        const QString &destinationKey)
    {
        // Older pre-release backups did not record key presence. Preserve the
        // key in that ambiguous case rather than deleting something we cannot
        // prove the installer created.
        const bool wasPresent =
            readDword(backupKey, presenceName).value_or(1) == 1;
        if (wasPresent)
        {
            HKEY key = nullptr;
            const std::wstring keyName = wide(destinationKey);
            if (RegCreateKeyExW(destinationRoot, keyName.c_str(), 0, nullptr, 0,
                    KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS)
            {
                RegCloseKey(key);
            }
            return;
        }
        deleteKeyIfEmpty(destinationRoot, destinationKey);
    }

    bool captureValue(
        const QString &backupKey,
        const QString &presenceName,
        const QString &backupName,
        HKEY sourceRoot,
        const QString &sourceKey,
        const QString &sourceName = {})
    {
        const RegistryString current = readString(sourceRoot, sourceKey, sourceName);
        return writeDword(backupKey, presenceName, current.present ? 1 : 0)
            && (!current.present
                || (writeString(HKEY_CURRENT_USER, backupKey, backupName, current.value)
                    && writeDword(backupKey, backupName + u"Type"_s, current.type)));
    }

    bool captureAssociations()
    {
        const QString classes = QString::fromWCharArray(ClassesRoot);
        const QString torrentBackup = QString::fromWCharArray(BackupRoot) + u"\\torrent"_s;
        const QString magnetBackup = QString::fromWCharArray(BackupRoot) + u"\\magnet"_s;
        bool ok = true;
        if (readDword(torrentBackup, u"Saved"_s).value_or(0) != 1)
        {
            ok = writeDword(torrentBackup, u"ExtensionKeyPresent"_s,
                    keyExists(HKEY_CURRENT_USER, classes + u".torrent"_s) ? 1 : 0)
                && captureValue(torrentBackup, u"ExtensionDefaultPresent"_s,
                    u"ExtensionDefaultValue"_s, HKEY_CURRENT_USER,
                    classes + u".torrent"_s)
                && captureValue(torrentBackup, u"ExtensionContentTypePresent"_s,
                    u"ExtensionContentTypeValue"_s, HKEY_CURRENT_USER,
                    classes + u".torrent"_s, u"Content Type"_s)
                && captureValue(torrentBackup, u"ProgIdDescriptionPresent"_s,
                    u"ProgIdDescriptionValue"_s, HKEY_CURRENT_USER,
                    classes + u"qBittorrentMaterial.torrent"_s)
                && captureValue(torrentBackup, u"ProgIdIconPresent"_s,
                    u"ProgIdIconValue"_s, HKEY_CURRENT_USER,
                    classes + u"qBittorrentMaterial.torrent\\DefaultIcon"_s)
                && captureValue(torrentBackup, u"ProgIdCommandPresent"_s,
                    u"ProgIdCommandValue"_s, HKEY_CURRENT_USER,
                    classes + u"qBittorrentMaterial.torrent\\shell\\open\\command"_s)
                && writeDword(torrentBackup, u"Saved"_s, 1);
        }
        if (readDword(magnetBackup, u"Saved"_s).value_or(0) != 1)
        {
            ok = writeDword(magnetBackup, u"RootKeyPresent"_s,
                    keyExists(HKEY_CURRENT_USER, classes + u"magnet"_s) ? 1 : 0)
                && captureValue(magnetBackup, u"DescriptionPresent"_s,
                    u"DescriptionValue"_s, HKEY_CURRENT_USER,
                    classes + u"magnet"_s)
                && captureValue(magnetBackup, u"ProtocolPresent"_s,
                    u"ProtocolValue"_s, HKEY_CURRENT_USER,
                    classes + u"magnet"_s, u"URL Protocol"_s)
                && captureValue(magnetBackup, u"IconPresent"_s,
                    u"IconValue"_s, HKEY_CURRENT_USER,
                    classes + u"magnet\\DefaultIcon"_s)
                && captureValue(magnetBackup, u"CommandPresent"_s,
                    u"CommandValue"_s, HKEY_CURRENT_USER,
                    classes + u"magnet\\shell\\open\\command"_s)
                && writeDword(magnetBackup, u"Saved"_s, 1)
                && ok;
        }
        return ok;
    }

    bool registerAssociations(const QString &stubPath)
    {
        if (!captureAssociations())
            return false;
        const QString classes = QString::fromWCharArray(ClassesRoot);
        const QString command = u'"' + nativePath(stubPath) + u"\" \"%1\""_s;
        const QString icon = nativePath(stubPath) + u",0"_s;
        const bool ok =
            writeString(HKEY_CURRENT_USER, classes + u".torrent"_s, {},
                u"qBittorrentMaterial.torrent"_s)
            && writeString(HKEY_CURRENT_USER, classes + u".torrent"_s,
                u"Content Type"_s, u"application/x-bittorrent"_s)
            && writeString(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent"_s, {}, u"BitTorrent Torrent"_s)
            && writeString(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent\\DefaultIcon"_s, {}, icon)
            && writeString(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent\\shell\\open\\command"_s,
                {}, command)
            && writeString(HKEY_CURRENT_USER, classes + u"magnet"_s, {},
                u"URL:Magnet Link"_s)
            && writeString(HKEY_CURRENT_USER, classes + u"magnet"_s,
                u"URL Protocol"_s, {})
            && writeString(HKEY_CURRENT_USER,
                classes + u"magnet\\DefaultIcon"_s, {}, icon)
            && writeString(HKEY_CURRENT_USER,
                classes + u"magnet\\shell\\open\\command"_s, {}, command);
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
        return ok;
    }

    void restoreValue(
        const QString &backupKey,
        const QString &presenceName,
        const QString &backupName,
        const QString &destinationKey,
        const QString &destinationName = {})
    {
        const bool wasPresent = readDword(backupKey, presenceName).value_or(0) == 1;
        if (wasPresent)
        {
            const RegistryString value = readString(
                HKEY_CURRENT_USER, backupKey, backupName);
            if (value.present)
            {
                const DWORD type = readDword(
                    backupKey, backupName + u"Type"_s).value_or(REG_SZ);
                writeString(HKEY_CURRENT_USER, destinationKey,
                    destinationName, value.value, type);
            }
            else
                deleteValue(HKEY_CURRENT_USER, destinationKey, destinationName);
        }
        else
        {
            deleteValue(HKEY_CURRENT_USER, destinationKey, destinationName);
        }
    }

    bool commandBelongsTo(const QString &key, const QString &expectedCommand)
    {
        const RegistryString current = readString(HKEY_CURRENT_USER, key);
        return current.present && (current.value == expectedCommand);
    }

    void deleteBackupTree(const QString &subKey)
    {
        const std::wstring keyName = wide(subKey);
        RegDeleteTreeW(HKEY_CURRENT_USER, keyName.c_str());
    }

    void restoreAssociations(const QString &stubPath)
    {
        const QString classes = QString::fromWCharArray(ClassesRoot);
        const QString torrentBackup = QString::fromWCharArray(BackupRoot) + u"\\torrent"_s;
        const QString magnetBackup = QString::fromWCharArray(BackupRoot) + u"\\magnet"_s;
        const QString expectedCommand = u'"' + nativePath(stubPath) + u"\" \"%1\""_s;
        const QString torrentCommand =
            classes + u"qBittorrentMaterial.torrent\\shell\\open\\command"_s;
        if (commandBelongsTo(torrentCommand, expectedCommand))
        {
            restoreValue(torrentBackup, u"ExtensionDefaultPresent"_s,
                u"ExtensionDefaultValue"_s, classes + u".torrent"_s);
            restoreValue(torrentBackup, u"ExtensionContentTypePresent"_s,
                u"ExtensionContentTypeValue"_s, classes + u".torrent"_s,
                u"Content Type"_s);
            restoreKeyPresence(torrentBackup, u"ExtensionKeyPresent"_s,
                HKEY_CURRENT_USER, classes + u".torrent"_s);
            restoreValue(torrentBackup, u"ProgIdDescriptionPresent"_s,
                u"ProgIdDescriptionValue"_s,
                classes + u"qBittorrentMaterial.torrent"_s);
            restoreValue(torrentBackup, u"ProgIdIconPresent"_s,
                u"ProgIdIconValue"_s,
                classes + u"qBittorrentMaterial.torrent\\DefaultIcon"_s);
            restoreValue(torrentBackup, u"ProgIdCommandPresent"_s,
                u"ProgIdCommandValue"_s, torrentCommand);
            deleteKeyIfEmpty(HKEY_CURRENT_USER, torrentCommand);
            deleteKeyIfEmpty(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent\\shell\\open"_s);
            deleteKeyIfEmpty(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent\\shell"_s);
            deleteKeyIfEmpty(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent\\DefaultIcon"_s);
            deleteKeyIfEmpty(HKEY_CURRENT_USER,
                classes + u"qBittorrentMaterial.torrent"_s);
            deleteBackupTree(torrentBackup);
        }

        const QString magnetCommand = classes + u"magnet\\shell\\open\\command"_s;
        if (commandBelongsTo(magnetCommand, expectedCommand))
        {
            restoreValue(magnetBackup, u"DescriptionPresent"_s,
                u"DescriptionValue"_s, classes + u"magnet"_s);
            restoreValue(magnetBackup, u"ProtocolPresent"_s,
                u"ProtocolValue"_s, classes + u"magnet"_s,
                u"URL Protocol"_s);
            restoreValue(magnetBackup, u"IconPresent"_s,
                u"IconValue"_s, classes + u"magnet\\DefaultIcon"_s);
            restoreValue(magnetBackup, u"CommandPresent"_s,
                u"CommandValue"_s, magnetCommand);
            deleteKeyIfEmpty(HKEY_CURRENT_USER, magnetCommand);
            deleteKeyIfEmpty(HKEY_CURRENT_USER, classes + u"magnet\\shell\\open"_s);
            deleteKeyIfEmpty(HKEY_CURRENT_USER, classes + u"magnet\\shell"_s);
            deleteKeyIfEmpty(HKEY_CURRENT_USER, classes + u"magnet\\DefaultIcon"_s);
            restoreKeyPresence(magnetBackup, u"RootKeyPresent"_s,
                HKEY_CURRENT_USER, classes + u"magnet"_s);
            deleteBackupTree(magnetBackup);
        }
        deleteKeyIfEmpty(HKEY_CURRENT_USER, QString::fromWCharArray(BackupRoot));
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    }

    bool runUpdater(const QString &updaterPath, const QStringList &arguments)
    {
        QProcess updater;
        updater.setProgram(updaterPath);
        updater.setArguments(arguments);
        updater.setProcessChannelMode(QProcess::MergedChannels);
        updater.start();
        if (!updater.waitForStarted(5000) || !updater.waitForFinished(15000))
        {
            qCWarning(lcApp) << "Squirrel shortcut command did not complete:"
                             << updater.errorString();
            updater.kill();
            updater.waitForFinished();
            return false;
        }
        if ((updater.exitStatus() != QProcess::NormalExit) || (updater.exitCode() != 0))
        {
            qCWarning(lcApp) << "Squirrel shortcut command failed:"
                             << updater.exitCode() << updater.readAll();
            return false;
        }
        return true;
    }
#endif
}

std::optional<int> SquirrelLifecycle::handle(const QStringList &arguments)
{
#ifndef Q_OS_WIN
    Q_UNUSED(arguments)
    return std::nullopt;
#else
    QString event;
    for (const QString &argument : arguments)
    {
        if (argument == u"--squirrel-install"_s
            || argument == u"--squirrel-updated"_s
            || argument == u"--squirrel-uninstall"_s
            || argument == u"--squirrel-obsolete"_s)
        {
            event = argument;
            break;
        }
    }
    if (event.isEmpty())
        return std::nullopt;

    const QFileInfo executable(QCoreApplication::applicationFilePath());
    const QDir appDirectory = executable.absoluteDir();
    if (!appDirectory.dirName().startsWith(u"app-"_s))
    {
        qCWarning(lcApp) << "Refusing a Squirrel lifecycle event outside app-<version>:"
                         << appDirectory.absolutePath();
        return 1;
    }
    QDir installRoot(appDirectory.absoluteFilePath(u".."_s));
    const QString updaterPath = installRoot.absoluteFilePath(u"Update.exe"_s);
    const QString stubPath = installRoot.absoluteFilePath(u"qbittorrent.exe"_s);
    if (!QFileInfo::exists(updaterPath))
    {
        qCWarning(lcApp) << "Squirrel Update.exe is missing:" << updaterPath;
        return 1;
    }

    if (event == u"--squirrel-install"_s || event == u"--squirrel-updated"_s)
    {
        const bool associationsReady = registerAssociations(stubPath);
        const bool shortcutsReady = runUpdater(updaterPath, {
            u"--createShortcut=qbittorrent.exe"_s,
            u"--shortcut-locations=Desktop,StartMenu"_s,
            u"--silent"_s
        });
        qCInfo(lcApp) << "Handled Squirrel install/update lifecycle:"
                      << "associations=" << associationsReady
                      << "shortcuts=" << shortcutsReady;
        return (associationsReady && shortcutsReady) ? 0 : 1;
    }

    if (event == u"--squirrel-uninstall"_s)
    {
        const bool shortcutsRemoved = runUpdater(updaterPath, {
            u"--removeShortcut=qbittorrent.exe"_s,
            u"--shortcut-locations=Desktop,StartMenu"_s,
            u"--silent"_s
        });
        restoreAssociations(stubPath);
        qCInfo(lcApp) << "Handled Squirrel uninstall lifecycle: shortcuts="
                      << shortcutsRemoved;
        return shortcutsRemoved ? 0 : 1;
    }

    qCInfo(lcApp) << "Handled Squirrel obsolete lifecycle.";
    return 0;
#endif
}
