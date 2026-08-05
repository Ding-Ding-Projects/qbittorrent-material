/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2026  Vladimir Golovnev <glassez@yandex.ru>
 * Copyright (C) 2018-2025  Mike Tzou (Chocobo1)
 * Copyright (C) 2006  Christophe Dumez <chris@qbittorrent.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#include "foreignapps.h"

#if defined(Q_OS_WIN)
#include <algorithm>
#include <windows.h>
#endif

#include <QCoreApplication>
#include <QProcess>
#include <QRegularExpression>
#include <QStringList>

#if defined(Q_OS_WIN)
#include <QDir>
#include <QScopeGuard>
#endif

#include "base/logger.h"
#include "base/preferences.h"
#include "base/utils/bytearray.h"

#if defined(Q_OS_WIN)
#include "base/utils/compare.h"
#include "base/utils/reg.h"
#endif

using namespace Utils::ForeignApps;

namespace
{
    struct PythonDetectionCache
    {
        Path preferredPythonPath;
        PythonInfo configuredInfo;
        PythonInfo automaticInfo;
        bool initialized = false;
        bool automaticProbeComplete = false;
    };

    PythonDetectionCache &pythonDetectionCache()
    {
        static PythonDetectionCache cache;
        return cache;
    }

    bool testPythonInstallation(const Path &exePath, PythonInfo &info)
    {
        info = {};

        QProcess proc;
#ifdef Q_OS_UNIX
        proc.setUnixProcessParameters(QProcess::UnixProcessFlag::CloseFileDescriptors);
#endif
        proc.start(exePath.data(), {u"--version"_s}, QIODevice::ReadOnly);
        if (proc.waitForFinished(3000) && (proc.exitStatus() == QProcess::NormalExit))
        {
            QByteArray procOutput = proc.readAllStandardOutput();
            if (procOutput.isEmpty())
                procOutput = proc.readAllStandardError();
            procOutput = procOutput.simplified();

            // Software 'Anaconda' installs its own python interpreter
            // and `python --version` returns a string like this:
            // "Python 3.4.3 :: Anaconda 2.3.0 (64-bit)"
            const QList<QByteArrayView> outputSplit = Utils::ByteArray::splitToViews(procOutput, " ");
            if (outputSplit.size() <= 1)
                return false;

            // User reports: `python --version` -> "Python 3.6.6+"
            // So trim off unrelated characters
            const auto versionStr = QString::fromLocal8Bit(outputSplit[1]);
            const qsizetype idx = versionStr.indexOf(QRegularExpression(u"[^\\.\\d]"_s));
            const auto version = PythonInfo::Version::fromString(versionStr.left(idx));
            if (!version.isValid())
                return false;

            info = {.executablePath = exePath, .version = version};
            LogMsg(QCoreApplication::translate("Utils::ForeignApps", "Found Python executable. Name: \"%1\". Version: \"%2\"")
                .arg(info.executablePath.toString(), info.version.toString()), Log::INFO);
            return true;
        }

        if (proc.state() != QProcess::NotRunning)
            proc.kill();
        return false;
    }

#if defined(Q_OS_WIN)
    enum REG_SEARCH_TYPE
    {
        USER,
        SYSTEM_32BIT,
        SYSTEM_64BIT
    };

    PathList pythonSearchReg(const REG_SEARCH_TYPE type)
    {
        const HKEY hkRoot = (type == USER) ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
        const REGSAM samDesired = KEY_READ
            | ((type == SYSTEM_64BIT) ? KEY_WOW64_64KEY : KEY_WOW64_32KEY);
        PathList ret;

        HKEY hkPythonCore {0};
        if (::RegOpenKeyExW(hkRoot, L"SOFTWARE\\Python\\PythonCore", 0, samDesired, &hkPythonCore) == ERROR_SUCCESS)
        {
            [[maybe_unused]] const auto hkPythonCoreGuard = qScopeGuard([&hkPythonCore] { ::RegCloseKey(hkPythonCore); });

            // start with the largest version
            QStringList versions = Utils::Reg::getSubkeys(hkPythonCore);
            // ordinary sort won't suffice, it needs to sort ["3.9", "3.10"] correctly
            const Utils::Compare::NaturalCompare<Qt::CaseInsensitive> comparator;
            std::ranges::sort(versions, [&comparator](const QString &left, const QString &right)
            {
                return comparator(left, right);
            });

            ret.reserve(versions.size() * 2);

            while (!versions.empty())
            {
                const std::wstring version = (Path(versions.takeLast()) / Path(u"InstallPath"_s)).toString().toStdWString();

                HKEY hkInstallPath {0};
                if (::RegOpenKeyExW(hkPythonCore, version.c_str(), 0, samDesired, &hkInstallPath) == ERROR_SUCCESS)
                {
                    [[maybe_unused]] const auto hkInstallPathGuard = qScopeGuard([&hkInstallPath] { ::RegCloseKey(hkInstallPath); });

                    const Path basePath {Utils::Reg::getStringValue(hkInstallPath)};
                    if (basePath.isEmpty())
                        continue;

                    if (const Path path = (basePath / Path(u"python3.exe"_s)); path.exists())
                        ret.append(path);
                    if (const Path path = (basePath / Path(u"python.exe"_s)); path.exists())
                        ret.append(path);
                }
            }
        }

        return ret;
    }

    PathList searchPythonPaths()
    {
        // From registry
        PathList ret = pythonSearchReg(USER)
            + pythonSearchReg(SYSTEM_64BIT)
            + pythonSearchReg(SYSTEM_32BIT);

        // Fallback: Detect python from default locations
        const QFileInfoList dirs = QDir(u"C:/"_s).entryInfoList({u"Python*"_s}, QDir::Dirs, (QDir::Name | QDir::Reversed));
        for (const QFileInfo &info : dirs)
        {
            const Path absPath {info.absoluteFilePath()};

            if (const Path path = (absPath / Path(u"python3.exe"_s)); path.exists())
                ret.append(path);
            if (const Path path = (absPath / Path(u"python.exe"_s)); path.exists())
                ret.append(path);
        }

        return ret;
    }
#endif // Q_OS_WIN
}

bool Utils::ForeignApps::PythonInfo::isValid() const
{
    return (executablePath.isValid() && version.isValid());
}

bool Utils::ForeignApps::PythonInfo::isSupportedVersion() const
{
    return (version >= MINIMUM_SUPPORTED_VERSION);
}

PythonInfo Utils::ForeignApps::pythonInfo()
{
    PythonDetectionCache &cache = pythonDetectionCache();

    const Path preferredPythonPath = Preferences::instance()->getPythonExecutablePath();
    if (!cache.initialized || (cache.preferredPythonPath != preferredPythonPath))
    {
        // Treat a preference change as an explicit request to re-evaluate the
        // interpreter. In particular, moving from a configured path back to
        // automatic detection must not reuse the old configured executable.
        cache = {};
        cache.initialized = true;
        cache.preferredPythonPath = preferredPythonPath;
    }

    const QString invalidVersionMessage = QCoreApplication::translate("Utils::ForeignApps"
        , "Python failed to meet minimum version requirement. Path: \"%1\". Found version: \"%2\". Minimum supported version: \"%3\".");

    if (!preferredPythonPath.isEmpty())
    {
        PythonInfo &pyInfo = cache.configuredInfo;
        if (pyInfo.isValid() && (preferredPythonPath == pyInfo.executablePath) && pyInfo.executablePath.exists())
            return pyInfo;

        if (testPythonInstallation(preferredPythonPath, pyInfo))
        {
            if (pyInfo.isSupportedVersion())
                return pyInfo;

            LogMsg(invalidVersionMessage.arg(pyInfo.executablePath.toString()
                , pyInfo.version.toString(), PythonInfo::MINIMUM_SUPPORTED_VERSION.toString()), Log::WARNING);
        }
        else
        {
            LogMsg(QCoreApplication::translate("Utils::ForeignApps", "Failed to find Python executable. Path: \"%1\".")
                .arg(preferredPythonPath.toString()), Log::WARNING);
        }
    }
    else
    {
        // Probe PATH and the registry at most once for one automatic
        // configuration. Both a usable interpreter and an unavailable or
        // unsupported environment are useful results: re-running the latter
        // on every UI path can synchronously wait on multiple dead aliases.
        if (cache.automaticProbeComplete)
        {
            // Keep a PATH alias cached: checking Path("python") against the
            // filesystem would fail even while QProcess can still resolve it.
            // A cached concrete path, however, may be removed between searches;
            // discard that stale result and allow one bounded re-probe.
            const Path &cachedAutomaticPath = cache.automaticInfo.executablePath;
            if (!cache.automaticInfo.isValid() || !cachedAutomaticPath.isAbsolute()
                    || cachedAutomaticPath.exists())
            {
                return cache.automaticInfo;
            }

            cache.automaticInfo = {};
            cache.automaticProbeComplete = false;
        }

        PythonInfo &pyInfo = cache.automaticInfo;
        if (!pyInfo.isValid())
        {
            // search in `PATH` environment variable
            const QString exeNames[] = {u"python3"_s, u"python"_s};
            for (const QString &exeName : exeNames)
            {
                if (testPythonInstallation(Path(exeName), pyInfo))
                {
                    if (pyInfo.isSupportedVersion())
                        return pyInfo;

                    LogMsg(invalidVersionMessage.arg(pyInfo.executablePath.toString()
                        , pyInfo.version.toString(), PythonInfo::MINIMUM_SUPPORTED_VERSION.toString()), Log::INFO);
                }
                else
                {
                    LogMsg(QCoreApplication::translate("Utils::ForeignApps", "Failed to find `%1` executable in PATH environment variable. PATH: \"%2\"")
                        .arg(exeName, qEnvironmentVariable("PATH")), Log::INFO);
                }
            }

#if defined(Q_OS_WIN)
            for (const Path &path : asConst(searchPythonPaths()))
            {
                if (testPythonInstallation(path, pyInfo))
                {
                    if (pyInfo.isSupportedVersion())
                        return pyInfo;

                    LogMsg(invalidVersionMessage.arg(pyInfo.executablePath.toString()
                        , pyInfo.version.toString(), PythonInfo::MINIMUM_SUPPORTED_VERSION.toString()), Log::INFO);
                }
            }
#endif

            LogMsg(QCoreApplication::translate("Utils::ForeignApps", "Failed to find Python executable"), Log::WARNING);
        }

        cache.automaticProbeComplete = true;
    }

    return preferredPythonPath.isEmpty() ? cache.automaticInfo : cache.configuredInfo;
}

void Utils::ForeignApps::resetAutomaticPythonDetection()
{
    PythonDetectionCache &cache = pythonDetectionCache();
    // A configured interpreter is an explicit user choice and has its own
    // validation lifecycle. Only invalidate automatic discovery, which can
    // legitimately change after Python is installed while the app is open.
    if (Preferences::instance()->getPythonExecutablePath().isEmpty())
    {
        cache.automaticInfo = {};
        cache.automaticProbeComplete = false;
    }
}
