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

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QQmlEngine>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include "base/search/searchpluginmanager.h"
#include "base/logging.h"

/**
 * @file searchpluginsmodel.h
 * @brief Canonical list model of every search plugin known to the palette,
 *        backing the Search Plugins dialog table.
 *
 * The QML owner binds @c inventory to @c SearchController::plugins, so the
 * dialog and command palette consume the same validated union: registered,
 * waiting-runtime, quarantined, removed, and failed/unregistered rows all keep
 * one stable id. The complete row map is retained so newly added trust/runtime
 * fields survive even before a dedicated display role is added.
 *
 * QML-creatable: the dialog does `SearchPluginsModel { id: pluginsModel }`.
 */
class SearchPluginsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QVariantList inventory READ inventory WRITE setInventory NOTIFY inventoryChanged)
    Q_PROPERTY(QString highlightedPluginId READ highlightedPluginId NOTIFY highlightedPluginIdChanged)

public:
    enum Roles
    {
        PluginIdRole = Qt::UserRole + 1, ///< "pluginId"  — short id / key
        FullNameRole,                    ///< "fullName"  — human display name
        VersionRole,                     ///< "version"   — e.g. "2.11"
        UrlRole,                         ///< "url"              — engine site URL
        CatalogSourceUrlRole,            ///< "catalogSourceUrl" — verified source
        EnabledRole,                     ///< "enabled"          — bool
        RegisteredRole,                  ///< "registered"       — runtime registered
        InstalledOnDiskRole,             ///< "installedOnDisk"  — active/quarantined file
        RuntimeWaitingRole,              ///< "runtimeWaiting"   — blocked on runtime
        RuntimeStateRole,                ///< "runtimeState"     — canonical state token
        IntegrityStateRole,              ///< "integrityState"   — verification state token
        CatalogOwnedRole,                ///< "catalogOwned"     — catalog lifecycle owned
        TrustedRole,                     ///< "trusted"          — explicitly trusted
        CanTrustRole,                    ///< "canTrust"         — trust action available
        CanRetryRole,                    ///< "canRetry"         — retry action available
        CanManageRole,                   ///< "canManage"        — management available
        UserRemovedRole,                 ///< "userRemoved"      — deliberate removal
        DiagnosticRole,                  ///< "diagnostic"       — concrete failure reason
        IconPathRole,                    ///< "iconPath"         — local favicon (file URL)
        HighlightedRole                  ///< "highlighted"      — transient deep-link cue
    };
    Q_ENUM(Roles)

    explicit SearchPluginsModel(QObject *parent = nullptr)
        : QAbstractListModel(parent)
    {
        qCDebug(lcSearch) << "SearchPluginsModel constructed; waiting for canonical inventory";
    }

    int rowCount(const QModelIndex &parent = {}) const override
    {
        return parent.isValid() ? 0 : static_cast<int>(m_rows.size());
    }

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override
    {
        const int row = index.row();
        if ((row < 0) || (row >= m_rows.size()))
            return {};

        const QVariantMap &plugin = m_rows.at(row);
        const QString id = plugin.value(QStringLiteral("id")).toString();

        switch (role)
        {
        case Qt::DisplayRole:
        case FullNameRole: return plugin.value(QStringLiteral("label"));
        case PluginIdRole: return id;
        case VersionRole: return plugin.value(QStringLiteral("version"));
        case UrlRole: return plugin.value(QStringLiteral("url"));
        case CatalogSourceUrlRole: return plugin.value(QStringLiteral("catalogSourceUrl"));
        case EnabledRole: return plugin.value(QStringLiteral("enabled"));
        case RegisteredRole: return plugin.value(QStringLiteral("registered"));
        case InstalledOnDiskRole: return plugin.value(QStringLiteral("installedOnDisk"));
        case RuntimeWaitingRole: return plugin.value(QStringLiteral("runtimeWaiting"));
        case RuntimeStateRole: return plugin.value(QStringLiteral("runtimeState"));
        case IntegrityStateRole: return plugin.value(QStringLiteral("integrityState"));
        case CatalogOwnedRole: return plugin.value(QStringLiteral("catalogOwned"));
        case TrustedRole: return plugin.value(QStringLiteral("trusted"));
        case CanTrustRole: return plugin.value(QStringLiteral("canTrust"));
        case CanRetryRole: return plugin.value(QStringLiteral("canRetry"));
        case CanManageRole: return plugin.value(QStringLiteral("canManage"));
        case UserRemovedRole: return plugin.value(QStringLiteral("userRemoved"));
        case DiagnosticRole: return plugin.value(QStringLiteral("diagnostic"));
        case IconPathRole:
        {
            const auto *mgr = SearchPluginManager::instance();
            const SearchPluginInfo *info = mgr ? mgr->pluginInfo(id) : nullptr;
            return (!info || info->iconPath.isEmpty())
                ? QString() : QUrl::fromLocalFile(info->iconPath.data()).toString();
        }
        case HighlightedRole: return id == m_highlightedPluginId;
        default: return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return {
            {PluginIdRole, "pluginId"},
            {FullNameRole, "fullName"},
            {VersionRole, "version"},
            {UrlRole, "url"},
            {CatalogSourceUrlRole, "catalogSourceUrl"},
            {EnabledRole, "enabled"},
            {RegisteredRole, "registered"},
            {InstalledOnDiskRole, "installedOnDisk"},
            {RuntimeWaitingRole, "runtimeWaiting"},
            {RuntimeStateRole, "runtimeState"},
            {IntegrityStateRole, "integrityState"},
            {CatalogOwnedRole, "catalogOwned"},
            {TrustedRole, "trusted"},
            {CanTrustRole, "canTrust"},
            {CanRetryRole, "canRetry"},
            {CanManageRole, "canManage"},
            {UserRemovedRole, "userRemoved"},
            {DiagnosticRole, "diagnostic"},
            {IconPathRole, "iconPath"},
            {HighlightedRole, "highlighted"}
        };
    }

    [[nodiscard]] QVariantList inventory() const { return m_inventory; }
    [[nodiscard]] QString highlightedPluginId() const { return m_highlightedPluginId; }

    void setInventory(const QVariantList &inventory)
    {
        if ((!m_hasPendingInventory && (m_inventory == inventory))
            || (m_hasPendingInventory && (m_pendingInventory == inventory)))
        {
            return;
        }

        m_pendingInventory = inventory;
        m_hasPendingInventory = true;
        if (m_inventoryApplyQueued)
            return;

        m_inventoryApplyQueued = true;
        QTimer::singleShot(0, this, [this] { flushPendingInventory(); });
    }

    /// Plugin id for a row (used by context menus / selection).
    Q_INVOKABLE QString pluginId(int row) const
    {
        return ((row >= 0) && (row < m_rows.size()))
            ? m_rows.at(row).value(QStringLiteral("id")).toString() : QString();
    }

    /// Row for a stable plugin id, used by command-palette teleportation.
    Q_INVOKABLE int indexOfPlugin(const QString &id) const
    {
        return m_rowById.value(id, -1);
    }

    /// The complete canonical record, including fields unknown to this model's
    /// current role list. This keeps future trust/runtime metadata lossless.
    Q_INVOKABLE QVariantMap pluginRecord(int row) const
    {
        return ((row >= 0) && (row < m_rows.size())) ? m_rows.at(row) : QVariantMap {};
    }

    Q_INVOKABLE bool isEnabled(int row) const
    {
        return pluginRecord(row).value(QStringLiteral("enabled")).toBool();
    }

    Q_INVOKABLE bool isRegistered(int row) const
    {
        return pluginRecord(row).value(QStringLiteral("registered")).toBool();
    }

    Q_INVOKABLE bool isHighlighted(int row) const
    {
        return !m_highlightedPluginId.isEmpty() && (pluginId(row) == m_highlightedPluginId);
    }

    Q_INVOKABLE bool highlightPlugin(const QString &id)
    {
        flushPendingInventory();
        const int newRow = indexOfPlugin(id);
        if (newRow < 0)
            return false;

        const int oldRow = indexOfPlugin(m_highlightedPluginId);
        if (m_highlightedPluginId == id)
            return true;
        m_highlightedPluginId = id;
        emit highlightedPluginIdChanged();
        if (oldRow >= 0)
            emit dataChanged(index(oldRow, 0), index(oldRow, 0), {HighlightedRole});
        emit dataChanged(index(newRow, 0), index(newRow, 0), {HighlightedRole});
        return true;
    }

    Q_INVOKABLE void clearHighlight()
    {
        const int row = indexOfPlugin(m_highlightedPluginId);
        if (m_highlightedPluginId.isEmpty())
            return;
        m_highlightedPluginId.clear();
        emit highlightedPluginIdChanged();
        if (row >= 0)
            emit dataChanged(index(row, 0), index(row, 0), {HighlightedRole});
    }

    /// Favicon file URL for a row (empty string when none).
    Q_INVOKABLE QString iconPathAt(int row) const
    {
        auto *mgr = SearchPluginManager::instance();
        if (!mgr || (row < 0) || (row >= m_rows.size()))
            return {};
        const SearchPluginInfo *info = mgr->pluginInfo(pluginId(row));
        if (!info || info->iconPath.isEmpty())
            return {};
        return QUrl::fromLocalFile(info->iconPath.data()).toString();
    }

    /// Apply the newest controller snapshot immediately before a deep link.
    Q_INVOKABLE void flushPendingInventory()
    {
        m_inventoryApplyQueued = false;
        if (!m_hasPendingInventory)
            return;

        const QVariantList nextInventory = m_pendingInventory;
        m_pendingInventory.clear();
        m_hasPendingInventory = false;

        beginResetModel();
        m_inventory = nextInventory;
        m_rows.clear();
        m_rowById.clear();
        QSet<QString> seen;
        for (const QVariant &entry : m_inventory)
        {
            QVariantMap row = entry.toMap();
            const QString id = row.value(QStringLiteral("id")).toString();
            if (id.isEmpty() || seen.contains(id))
                continue;
            seen.insert(id);
            if (row.value(QStringLiteral("label")).toString().isEmpty())
                row.insert(QStringLiteral("label"), id);
            if (row.value(QStringLiteral("catalogSourceUrl")).toString().isEmpty())
                row.insert(QStringLiteral("catalogSourceUrl"), row.value(QStringLiteral("url")));
            m_rowById.insert(id, static_cast<int>(m_rows.size()));
            m_rows.append(row);
        }
        const bool highlightRemoved = !m_highlightedPluginId.isEmpty()
            && !m_rowById.contains(m_highlightedPluginId);
        if (highlightRemoved)
            m_highlightedPluginId.clear();
        endResetModel();
        if (highlightRemoved)
            emit highlightedPluginIdChanged();
        emit countChanged();
        emit inventoryChanged();
        qCDebug(lcSearch) << "SearchPluginsModel applied canonical inventory:" << m_rows.size() << "plugins";
    }

signals:
    void countChanged();
    void inventoryChanged();
    void highlightedPluginIdChanged();

private:
    QVariantList m_inventory;
    QVariantList m_pendingInventory;
    QList<QVariantMap> m_rows;
    QHash<QString, int> m_rowById;
    QString m_highlightedPluginId;
    bool m_hasPendingInventory = false;
    bool m_inventoryApplyQueued = false;
};
