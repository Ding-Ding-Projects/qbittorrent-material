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

#include "settingsstorage.h"

#include <chrono>
#include <memory>

#include <QFile>
#include <QHash>
#include <QMetaObject>
#include <QOverload>
#include <QSettings>

#include "base/global.h"
#include "base/logging.h"
#include "base/profile.h"
#include "base/utils/fs.h"
#include "base/utils/fs/path.h"

using namespace std::chrono_literals;

namespace
{
    // QFile::rename() cannot replace an existing file on Windows. Move the
    // old settings aside first, then restore it if the replacement fails; the
    // previous implementation deleted the only good copy before attempting
    // the second rename.
    bool replaceSettingsFile(const Path &source, const Path &destination)
    {
        if (!destination.exists())
            return Utils::Fs::renameFile(source, destination);

        const Path backup {destination.toString() + u".qbt-previous"_s};
        Utils::Fs::removeFile(backup);
        if (!Utils::Fs::renameFile(destination, backup))
            return false;

        if (Utils::Fs::renameFile(source, destination))
        {
            Utils::Fs::removeFile(backup);
            return true;
        }

        if (!Utils::Fs::renameFile(backup, destination))
            qCCritical(lcApp) << "Could not restore the previous settings file after replacement failed";
        return false;
    }
}

SettingsStorage *SettingsStorage::m_instance = nullptr;

/**
 * The storage keeps the whole configuration in memory (@c m_data) and lazily
 * flushes it to the native QSettings backend. Writes are debounced through a
 * 5-second single-shot timer so a burst of `storeValue()` calls results in a
 * single transactional save. The save itself is transactional: everything is
 * written to a `qBittorrent_new.{ini,conf}` sibling first, then atomically
 * renamed over the real file so a power loss can never corrupt the config.
 */
SettingsStorage::SettingsStorage()
    : m_nativeSettingsName {u"qBittorrent"_s}
{
    qCDebug(lcApp) << "SettingsStorage: constructing; reading native settings";
    readNativeSettings();

    m_timer.setSingleShot(true);
    m_timer.setInterval(5s);
    connect(&m_timer, &QTimer::timeout, this, &SettingsStorage::save);

    qCInfo(lcApp) << "SettingsStorage: initialized with" << m_data.size() << "keys";
}

SettingsStorage::~SettingsStorage()
{
    qCDebug(lcApp) << "SettingsStorage: destroying; performing final save";
    save();
}

void SettingsStorage::initInstance()
{
    if (!m_instance)
    {
        qCDebug(lcApp) << "SettingsStorage: creating singleton instance";
        m_instance = new SettingsStorage;
    }
}

void SettingsStorage::freeInstance()
{
    qCDebug(lcApp) << "SettingsStorage: freeing singleton instance";
    delete m_instance;
    m_instance = nullptr;
}

SettingsStorage *SettingsStorage::instance()
{
    return m_instance;
}

bool SettingsStorage::save()
{
    // return `true` only when settings is different AND is saved successfully

    const QWriteLocker locker(&m_lock);  // guard for `m_dirty` too
    if (!m_dirty)
    {
        qCDebug(lcApp) << "SettingsStorage: save skipped, nothing changed";
        return false;
    }

    qCDebug(lcApp) << "SettingsStorage: flushing" << m_data.size() << "keys to disk";
    if (!writeNativeSettings())
    {
        qCWarning(lcApp) << "SettingsStorage: save failed; scheduling retry";
        QMetaObject::invokeMethod(&m_timer, qOverload<>(&QTimer::start));
        return false;
    }

    m_dirty = false;
    qCInfo(lcApp) << "SettingsStorage: settings saved successfully";
    return true;
}

QVariant SettingsStorage::loadValueImpl(const QString &key, const QVariant &defaultValue) const
{
    const QReadLocker locker(&m_lock);
    return m_data.value(key, defaultValue);
}

void SettingsStorage::storeValueImpl(const QString &key, const QVariant &value)
{
    QVariant oldValue;
    bool changed = false;
    {
        const QWriteLocker locker(&m_lock);
        QVariant &currentValue = m_data[key];
        if (currentValue != value)
        {
            oldValue = currentValue;
            m_dirty = true;
            currentValue = value;
            changed = true;
            qCDebug(lcApp).nospace() << "SettingsStorage: key changed [" << key << "], flush scheduled";
            QMetaObject::invokeMethod(&m_timer, qOverload<>(&QTimer::start));
        }
    }
    // Emitted outside the lock so a directly-connected slot can read settings.
    if (changed)
        emit valueChanged(key, oldValue, value);
}

void SettingsStorage::readNativeSettings()
{
    // We return actual file names used by QSettings because
    // there is no other way to get that name except actually create a QSettings object.
    // If serialization operation was not successful we return empty string.
    const auto deserialize = [](QVariantHash &data, const QString &nativeSettingsName) -> Path
    {
        std::unique_ptr<QSettings> nativeSettings = Profile::instance()->applicationSettings(nativeSettingsName);
        if (nativeSettings->allKeys().isEmpty())
            return {};

        // Copy everything into memory. This means even keys inserted in the file manually
        // or that we don't touch directly in this code (eg disabled by ifdef). This ensures
        // that they will be copied over when save our settings to disk.
        for (const QString &key : asConst(nativeSettings->allKeys()))
        {
            const QVariant value = nativeSettings->value(key);
            if (value.isValid())
                data[key] = value;
        }

        return Path(nativeSettings->fileName());
    };

    const Path newPath = deserialize(m_data, (m_nativeSettingsName + u"_new"));
    if (!newPath.isEmpty())
    {
        // "_new" file is NOT empty
        // This means that the PC closed either due to power outage
        // or because the disk was full. In any case the settings weren't transferred
        // in their final position. So assume that qbittorrent_new.ini/qbittorrent_new.conf
        // contains the most recent settings.
        qCWarning(lcApp).noquote() << tr("Detected unclean program exit. Using fallback file to restore settings: %1")
                .arg(newPath.toString());

        QString finalPathStr = newPath.data();
        const qsizetype index = finalPathStr.lastIndexOf(u"_new", -1, Qt::CaseInsensitive);
        finalPathStr.remove(index, 4);

        const Path finalPath {finalPathStr};
        if (!replaceSettingsFile(newPath, finalPath))
            qCCritical(lcApp) << "Could not promote fallback settings file to" << finalPath.toString();
    }
    else
    {
        deserialize(m_data, m_nativeSettingsName);
    }

    qCDebug(lcApp) << "SettingsStorage: read" << m_data.size() << "keys from native storage";
}

bool SettingsStorage::writeNativeSettings() const
{
    const auto *profile = Profile::instance();

    // No-op when it has no write permission
    if (const auto confPath = Path(profile->applicationSettings(m_nativeSettingsName)->fileName());
        confPath.exists() && !Utils::Fs::isWritable(confPath))
    {
        qCWarning(lcApp).noquote() << tr("The configuration file is not writable: %1").arg(confPath.toString());
        return false;
    }

    std::unique_ptr<QSettings> nativeSettings = profile->applicationSettings(m_nativeSettingsName + u"_new");

    // QSettings deletes the file before writing it out. This can result in problems
    // if the disk is full or a power outage occurs. Those events might occur
    // between deleting the file and recreating it. This is a safety measure.
    // Write everything to qBittorrent_new.ini/qBittorrent_new.conf and if it succeeds
    // replace qBittorrent.ini/qBittorrent.conf with it.
    for (auto i = m_data.cbegin(); i != m_data.cend(); ++i)
        nativeSettings->setValue(i.key(), i.value());

    nativeSettings->sync(); // Important to get error status
    const QSettings::Status status = nativeSettings->status();
    const Path newPath {nativeSettings->fileName()};

    nativeSettings.reset();  // close QSettings

    switch (status)
    {
    case QSettings::NoError:
        break;
    case QSettings::AccessError:
        qCCritical(lcApp).noquote() << tr("An access error occurred while trying to write the configuration file.");
        break;
    case QSettings::FormatError:
        qCCritical(lcApp).noquote() << tr("A format error occurred while trying to write the configuration file.");
        break;
    default:
        qCCritical(lcApp).noquote() << tr("An unknown error occurred while trying to write the configuration file.");
        break;
    }

    if (status != QSettings::NoError)
    {
        Utils::Fs::removeFile(newPath);
        return false;
    }

    QString finalPathStr = newPath.data();
    const qsizetype index = finalPathStr.lastIndexOf(u"_new", -1, Qt::CaseInsensitive);
    finalPathStr.remove(index, 4);

    const Path finalPath {finalPathStr};
    return replaceSettingsFile(newPath, finalPath);
}

void SettingsStorage::removeValue(const QString &key)
{
    QVariant oldValue;
    bool removed = false;
    {
        const QWriteLocker locker(&m_lock);
        if (const auto it = m_data.constFind(key); it != m_data.cend())
        {
            oldValue = it.value();
            m_data.erase(it);
            m_dirty = true;
            removed = true;
            qCDebug(lcApp).nospace() << "SettingsStorage: key removed [" << key << "], flush scheduled";
            QMetaObject::invokeMethod(&m_timer, qOverload<>(&QTimer::start));
        }
    }
    if (removed)
        emit valueChanged(key, oldValue, QVariant());
}

QStringList SettingsStorage::allKeys() const
{
    const QReadLocker locker {&m_lock};
    return m_data.keys();
}

bool SettingsStorage::hasKey(const QString &key) const
{
    const QReadLocker locker {&m_lock};
    return m_data.contains(key);
}

bool SettingsStorage::isEmpty() const
{
    const QReadLocker locker {&m_lock};
    return m_data.isEmpty();
}
