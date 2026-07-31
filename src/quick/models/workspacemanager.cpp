/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "workspacemanager.h"

#include <algorithm>
#include <functional>
#include <utility>

#include <QColor>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QUuid>

#include <git2.h>

#include "base/logging.h"

namespace
{
    constexpr int SchemaVersion = 2;
    constexpr int MinimumSchemaVersion = 1;
    constexpr int MaximumTabs = 100;
    constexpr int MaximumGroups = 32;
    constexpr qsizetype MaximumPatternCharacters = 4096;
    constexpr qsizetype MaximumSampleCharacters = 64 * 1024;
    constexpr int MaximumRegexMatches = 200;
    const QString RegexSafetyPrefix = QStringLiteral(
        "(*LIMIT_MATCH=100000)(*LIMIT_DEPTH=1000)(?:");
    constexpr qsizetype MaximumContentCharacters = 4 * 1024 * 1024;
    constexpr qint64 MaximumWorkspaceBytes = 32LL * 1024 * 1024;
    constexpr qint64 MaximumRepositoryBytes = 256LL * 1024 * 1024;
    constexpr auto ProductDisplayName = "qBittorrent Material";

    QString gitErrorText(const QString &fallback)
    {
        if (const git_error *error = git_error_last(); error && error->message)
            return QString::fromUtf8(error->message);
        return fallback;
    }

    QString isoDate(const QDateTime &dateTime)
    {
        return dateTime.toUTC().toString(Qt::ISODateWithMs);
    }

    bool hasSymlinkIdentity(const QFileInfo &info)
    {
        return info.isSymLink() || info.isJunction() || !info.symLinkTarget().isEmpty();
    }
}

WorkspaceManager::WorkspaceManager(QObject *parent)
    : QAbstractListModel(parent)
{
    git_libgit2_init();

    const QString overrideRoot = qEnvironmentVariable("QBT_WORKSPACE_ROOT").trimmed();
    const QString dataRoot = overrideRoot.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)
        : overrideRoot;
    m_repositoryPath = overrideRoot.isEmpty()
        ? QDir(dataRoot).filePath(QStringLiteral("workspace-tabs"))
        : QDir::cleanPath(dataRoot);

    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(650);
    connect(&m_saveTimer, &QTimer::timeout, this, [this]
    {
        QString error;
        const QString message = m_pendingCommitMessage.isEmpty()
            ? QStringLiteral("workspace: autosave") : m_pendingCommitMessage;
        m_pendingCommitMessage.clear();
        if (!saveNow(message, &error))
            qCWarning(lcUi) << "Workspace autosave failed:" << error;
    });

    loadWorkspace();
    QGuiApplication::setApplicationDisplayName(m_appDisplayName);

    if (m_initializationBlocked)
        return;

    QString error;
    if (!saveNow(QStringLiteral("workspace: initialize"), &error))
    {
        m_repositoryStatus = tr("Saved files; local Git needs attention");
        qCWarning(lcUi) << "Workspace repository initialization failed:" << error;
    }
    else if (!m_recoveryPath.isEmpty())
    {
        m_repositoryStatus = tr("Recovered safely; previous files kept in %1")
            .arg(QDir::toNativeSeparators(m_recoveryPath));
        emit repositoryStatusChanged();
    }
}

WorkspaceManager::~WorkspaceManager()
{
    m_saveTimer.stop();
    if (m_dirty)
    {
        QString error;
        if (!saveNow(QStringLiteral("workspace: shutdown save"), &error))
            qCWarning(lcUi) << "Workspace shutdown save failed:" << error;
    }
    git_libgit2_shutdown();
}

int WorkspaceManager::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_tabs.size();
}

QVariant WorkspaceManager::data(const QModelIndex &index, const int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tabs.size())
        return {};
    const Tab &tab = m_tabs.at(index.row());
    switch (role)
    {
    case TabIdRole: return tab.id;
    case NameRole: return tab.name;
    case ContentRole: return tab.content;
    case FontFamilyRole: return tab.fontFamily;
    case FontStyleRole: return tab.fontStyle;
    case FontPointSizeRole: return tab.fontPointSize;
    case BoldRole: return tab.bold;
    case ItalicRole: return tab.italic;
    case FontColorRole: return tab.fontColor;
    case PinnedRole: return tab.pinned;
    case GroupIdRole: return tab.groupId;
    case GroupNameRole: return groupName(tab.groupId);
    case GroupColorRole: return groupColor(tab.groupId);
    case GroupCollapsedRole: return groupCollapsed(tab.groupId);
    case AppearanceRole: return tab.appearance;
    case CreatedAtRole: return isoDate(tab.createdAt);
    case UpdatedAtRole: return isoDate(tab.updatedAt);
    default: return {};
    }
}

QHash<int, QByteArray> WorkspaceManager::roleNames() const
{
    return {
        {TabIdRole, "tabId"},
        {NameRole, "name"},
        {ContentRole, "content"},
        {FontFamilyRole, "fontFamily"},
        {FontStyleRole, "fontStyle"},
        {FontPointSizeRole, "fontPointSize"},
        {BoldRole, "bold"},
        {ItalicRole, "italic"},
        {FontColorRole, "fontColor"},
        {PinnedRole, "pinned"},
        {GroupIdRole, "groupId"},
        {GroupNameRole, "groupName"},
        {GroupColorRole, "groupColor"},
        {GroupCollapsedRole, "groupCollapsed"},
        {AppearanceRole, "appearance"},
        {CreatedAtRole, "createdAt"},
        {UpdatedAtRole, "updatedAt"}
    };
}

QString WorkspaceManager::appDisplayName() const
{
    return m_appDisplayName;
}

void WorkspaceManager::setAppDisplayName(const QString &name)
{
    if (!requireWritable())
        return;
    const QString normalized = normalizedName(name, 80, QString::fromLatin1(ProductDisplayName));
    if (m_appDisplayName == normalized)
        return;
    m_appDisplayName = normalized;
    QGuiApplication::setApplicationDisplayName(m_appDisplayName);
    emit appDisplayNameChanged();
    scheduleSave(QStringLiteral("workspace: rename application display"));
}

int WorkspaceManager::count() const
{
    return m_tabs.size();
}

int WorkspaceManager::pinnedCount() const
{
    return static_cast<int>(std::count_if(m_tabs.cbegin(), m_tabs.cend(),
        [](const Tab &tab) { return tab.pinned; }));
}

int WorkspaceManager::activeIndex() const
{
    return m_activeIndex;
}

void WorkspaceManager::setActiveIndex(const int index)
{
    const int normalized = (index >= 0 && index < m_tabs.size()) ? index : -1;
    if (m_activeIndex == normalized)
        return;
    m_activeIndex = normalized;
    emit activeIndexChanged();
    if (!m_loading && writable())
        scheduleSave(QStringLiteral("workspace: select tab"));
}

QString WorkspaceManager::activeTabId() const
{
    return (m_activeIndex >= 0 && m_activeIndex < m_tabs.size())
        ? m_tabs.at(m_activeIndex).id : QString();
}

QString WorkspaceManager::repositoryPath() const
{
    return m_repositoryPath;
}

QUrl WorkspaceManager::repositoryUrl() const
{
    return QUrl::fromLocalFile(m_repositoryPath);
}

QString WorkspaceManager::repositoryStatus() const
{
    return m_repositoryStatus;
}

QString WorkspaceManager::lastCommitId() const
{
    return m_lastCommitId;
}

bool WorkspaceManager::dirty() const
{
    return m_dirty;
}

bool WorkspaceManager::writable() const
{
    return !m_initializationBlocked;
}

QVariantList WorkspaceManager::tabItems() const
{
    QVariantList result;
    result.reserve(m_tabs.size());
    for (int i = 0; i < m_tabs.size(); ++i)
    {
        QVariantMap item = tabMap(m_tabs.at(i));
        item.insert(QStringLiteral("index"), i);
        result.push_back(item);
    }
    return result;
}

QVariantList WorkspaceManager::groups() const
{
    QVariantList result;
    result.reserve(m_groups.size());
    for (const Group &group : m_groups)
        result.push_back(groupMap(group));
    return result;
}

QVariantMap WorkspaceManager::globalAppearance() const
{
    return m_globalAppearance;
}

QVariantList WorkspaceManager::appearancePresets() const
{
    return m_appearancePresets;
}

bool WorkspaceManager::requireWritable()
{
    if (writable())
        return true;
    emit operationFinished(false,
        tr("The workspace is read-only because automatic recovery needs attention. "
           "Open the managed repository folder before closing the application."),
        QUrl::fromLocalFile(QFileInfo(m_repositoryPath).absolutePath()));
    return false;
}

QVariantMap WorkspaceManager::tabAt(const int index) const
{
    return (index >= 0 && index < m_tabs.size()) ? tabMap(m_tabs.at(index)) : QVariantMap();
}

QVariantMap WorkspaceManager::tabById(const QString &tabId) const
{
    const int index = indexOfTab(tabId);
    return (index >= 0) ? tabMap(m_tabs.at(index)) : QVariantMap();
}

QString WorkspaceManager::createTab(const QString &name)
{
    if (!requireWritable())
        return {};
    if (m_tabs.size() >= MaximumTabs)
    {
        emit operationFinished(false, tr("A workspace can contain at most %1 tabs.").arg(MaximumTabs), {});
        return {};
    }

    Tab tab;
    tab.id = newTabId();
    tab.name = normalizedName(name, 120, tr("New tab"));
    tab.fontFamily = QFontDatabase::systemFont(QFontDatabase::GeneralFont).family();
    const QStringList styles = QFontDatabase::styles(tab.fontFamily);
    tab.fontStyle = styles.contains(QStringLiteral("Regular"))
        ? QStringLiteral("Regular") : styles.value(0, QStringLiteral("Regular"));
    tab.createdAt = tab.updatedAt = QDateTime::currentDateTimeUtc();

    const int row = m_tabs.size();
    beginInsertRows({}, row, row);
    m_tabs.push_back(tab);
    endInsertRows();
    emit countChanged();
    emit tabsChanged();
    setActiveIndex(row);
    scheduleSave(QStringLiteral("workspace: create tab"));
    return tab.id;
}

int WorkspaceManager::duplicateTab(const int index)
{
    if (!requireWritable())
        return -1;
    if (index < 0 || index >= m_tabs.size() || m_tabs.size() >= MaximumTabs)
        return -1;
    Tab copy = m_tabs.at(index);
    copy.id = newTabId();
    copy.name = normalizedName(tr("%1 copy").arg(copy.name), 120, tr("Tab copy"));
    copy.createdAt = copy.updatedAt = QDateTime::currentDateTimeUtc();
    const int destination = index + 1;
    beginInsertRows({}, destination, destination);
    m_tabs.insert(destination, copy);
    endInsertRows();
    emit countChanged();
    emit tabsChanged();
    setActiveIndex(destination);
    scheduleSave(QStringLiteral("workspace: duplicate tab"));
    return destination;
}

bool WorkspaceManager::closeTab(const int index)
{
    if (!requireWritable())
        return false;
    if (index < 0 || index >= m_tabs.size())
        return false;
    if (m_dirty)
    {
        QString error;
        if (!saveNow(QStringLiteral("workspace: checkpoint before close"), &error))
        {
            emit operationFinished(false,
                tr("The tab was not closed because its latest edits could not be checkpointed: %1")
                    .arg(error), {});
            return false;
        }
    }
    const QSet<QString> previouslyNonEmpty = nonEmptyGroupIds();
    beginRemoveRows({}, index, index);
    m_tabs.removeAt(index);
    endRemoveRows();
    pruneNewlyEmptyGroups(previouslyNonEmpty);
    emit countChanged();

    int next = m_activeIndex;
    if (m_tabs.isEmpty())
        next = -1;
    else if (index < m_activeIndex)
        next = m_activeIndex - 1;
    else if (index == m_activeIndex)
        next = qMin(index, m_tabs.size() - 1);
    m_activeIndex = next;
    emit activeIndexChanged();
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: close tab"));
    return true;
}

bool WorkspaceManager::closeOtherTabs(const int index)
{
    if (!requireWritable())
        return false;
    if (index < 0 || index >= m_tabs.size())
        return false;
    if (m_dirty)
    {
        QString error;
        if (!saveNow(QStringLiteral("workspace: checkpoint before close others"), &error))
        {
            emit operationFinished(false,
                tr("Other tabs were not closed because current edits could not be checkpointed: %1")
                    .arg(error), {});
            return false;
        }
    }
    const QSet<QString> previouslyNonEmpty = nonEmptyGroupIds();
    const QString retainedId = m_tabs.at(index).id;
    QVector<Tab> retained;
    retained.reserve(pinnedCount() + 1);
    for (const Tab &tab : std::as_const(m_tabs))
    {
        if (tab.pinned || tab.id == retainedId)
            retained.push_back(tab);
    }
    beginResetModel();
    m_tabs = std::move(retained);
    normalizePinnedOrder();
    m_activeIndex = indexOfTab(retainedId);
    endResetModel();
    pruneNewlyEmptyGroups(previouslyNonEmpty);
    emit countChanged();
    emit activeIndexChanged();
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: close other tabs"));
    return true;
}

bool WorkspaceManager::moveTab(const int from, const int to)
{
    if (!requireWritable())
        return false;
    if (from < 0 || from >= m_tabs.size() || to < 0 || to >= m_tabs.size() || from == to)
        return false;
    // Pinning defines a protected, stable region. Reordering cannot silently
    // pin or unpin a tab; callers use setTabPinned() for that explicit action.
    if (m_tabs.at(from).pinned != m_tabs.at(to).pinned)
        return false;
    const int destinationChild = (to > from) ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, destinationChild))
        return false;
    m_tabs.move(from, to);
    endMoveRows();
    if (m_activeIndex == from)
        m_activeIndex = to;
    else if (from < m_activeIndex && to >= m_activeIndex)
        --m_activeIndex;
    else if (from > m_activeIndex && to <= m_activeIndex)
        ++m_activeIndex;
    emit activeIndexChanged();
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: reorder tabs"));
    return true;
}

bool WorkspaceManager::setTabPinned(const int index, const bool pinned)
{
    if (!requireWritable() || index < 0 || index >= m_tabs.size())
        return false;
    if (m_tabs.at(index).pinned == pinned)
        return true;

    const QString activeId = activeTabId();
    beginResetModel();
    Tab tab = m_tabs.takeAt(index);
    tab.pinned = pinned;
    tab.updatedAt = QDateTime::currentDateTimeUtc();
    const int destination = pinned ? pinnedCount() : pinnedCount();
    m_tabs.insert(qBound(0, destination, m_tabs.size()), std::move(tab));
    normalizePinnedOrder();
    m_activeIndex = indexOfTab(activeId);
    endResetModel();
    emit activeIndexChanged();
    emit tabsChanged();
    scheduleSave(pinned ? QStringLiteral("workspace: pin tab")
                        : QStringLiteral("workspace: unpin tab"));
    return true;
}

bool WorkspaceManager::assignTabToGroup(const int index, const QString &groupId)
{
    if (!requireWritable() || index < 0 || index >= m_tabs.size())
        return false;
    const QString normalizedId = groupId.trimmed();
    if (!normalizedId.isEmpty() && indexOfGroup(normalizedId) < 0)
        return false;
    Tab &tab = m_tabs[index];
    if (tab.groupId == normalizedId)
        return true;
    tab.groupId = normalizedId;
    tab.updatedAt = QDateTime::currentDateTimeUtc();
    emit dataChanged(this->index(index), this->index(index),
        {GroupIdRole, GroupNameRole, GroupColorRole, GroupCollapsedRole, UpdatedAtRole});
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: move tab to group"));
    return true;
}

QString WorkspaceManager::createGroup(const QString &name, const QString &color)
{
    if (!requireWritable() || m_groups.size() >= MaximumGroups)
        return {};
    const QColor parsedColor(color.isEmpty() ? QStringLiteral("#6750A4") : color);
    if (!parsedColor.isValid())
        return {};
    Group group;
    group.id = newTabId();
    group.name = normalizedName(name, 80, tr("New group"));
    group.color = parsedColor.name(QColor::HexArgb).toUpper();
    m_groups.push_back(group);
    emit groupsChanged();
    scheduleSave(QStringLiteral("workspace: create tab group"));
    return group.id;
}

bool WorkspaceManager::updateGroup(const QString &groupId, const QString &name,
    const QString &color)
{
    if (!requireWritable())
        return false;
    const int row = indexOfGroup(groupId);
    const QColor parsedColor(color);
    if (row < 0 || !parsedColor.isValid())
        return false;
    Group &group = m_groups[row];
    group.name = normalizedName(name, 80, tr("Untitled group"));
    group.color = parsedColor.name(QColor::HexArgb).toUpper();
    emit groupsChanged();
    if (!m_tabs.isEmpty())
        emit dataChanged(index(0), index(m_tabs.size() - 1),
            {GroupNameRole, GroupColorRole});
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: update tab group"));
    return true;
}

bool WorkspaceManager::setGroupCollapsed(const QString &groupId, const bool collapsed)
{
    if (!requireWritable())
        return false;
    const int row = indexOfGroup(groupId);
    if (row < 0)
        return false;
    if (m_groups[row].collapsed == collapsed)
        return true;
    m_groups[row].collapsed = collapsed;
    emit groupsChanged();
    if (!m_tabs.isEmpty())
        emit dataChanged(index(0), index(m_tabs.size() - 1), {GroupCollapsedRole});
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: toggle tab group"));
    return true;
}

bool WorkspaceManager::moveGroup(const int from, const int to)
{
    if (!requireWritable() || from < 0 || from >= m_groups.size()
        || to < 0 || to >= m_groups.size() || from == to)
        return false;
    m_groups.move(from, to);
    emit groupsChanged();
    scheduleSave(QStringLiteral("workspace: reorder tab groups"));
    return true;
}

bool WorkspaceManager::removeGroup(const QString &groupId)
{
    if (!requireWritable())
        return false;
    const int row = indexOfGroup(groupId);
    if (row < 0)
        return false;
    m_groups.removeAt(row);
    for (Tab &tab : m_tabs)
    {
        if (tab.groupId == groupId)
            tab.groupId.clear();
    }
    emit groupsChanged();
    if (!m_tabs.isEmpty())
        emit dataChanged(index(0), index(m_tabs.size() - 1),
            {GroupIdRole, GroupNameRole, GroupColorRole, GroupCollapsedRole});
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: remove tab group"));
    return true;
}

QVariantMap WorkspaceManager::groupById(const QString &groupId) const
{
    const int row = indexOfGroup(groupId);
    return row >= 0 ? groupMap(m_groups.at(row)) : QVariantMap();
}

bool WorkspaceManager::setTabContent(const QString &tabId, const QString &content)
{
    if (!requireWritable())
        return false;
    const int row = indexOfTab(tabId);
    if (row < 0)
        return false;
    if (content.size() > MaximumContentCharacters)
    {
        emit operationFinished(false, tr("A tab can contain at most 4 million characters."), {});
        return false;
    }
    Tab &tab = m_tabs[row];
    if (tab.content == content)
        return true;
    tab.content = content;
    tab.updatedAt = QDateTime::currentDateTimeUtc();
    emit dataChanged(index(row), index(row), {ContentRole, UpdatedAtRole});
    scheduleSave(QStringLiteral("workspace: edit tab"));
    return true;
}

bool WorkspaceManager::updateTab(const QString &tabId, const QString &name,
    const QString &fontFamily, const QString &fontStyle, const double fontPointSize,
    const bool bold, const bool italic, const QString &fontColor)
{
    if (!requireWritable())
        return false;
    const int row = indexOfTab(tabId);
    const QColor parsedColor(fontColor);
    if (row < 0 || fontPointSize < 6.0 || fontPointSize > 144.0 || !parsedColor.isValid())
        return false;

    Tab &tab = m_tabs[row];
    tab.name = normalizedName(name, 120, tr("Untitled tab"));
    tab.fontFamily = normalizedName(fontFamily, 128,
        QFontDatabase::systemFont(QFontDatabase::GeneralFont).family());
    tab.fontStyle = normalizedName(fontStyle, 64, QStringLiteral("Regular"));
    tab.fontPointSize = fontPointSize;
    tab.bold = bold;
    tab.italic = italic;
    tab.fontColor = parsedColor.name(QColor::HexArgb).toUpper();
    tab.updatedAt = QDateTime::currentDateTimeUtc();
    emit dataChanged(index(row), index(row), {
        NameRole, FontFamilyRole, FontStyleRole, FontPointSizeRole,
        BoldRole, ItalicRole, FontColorRole, UpdatedAtRole
    });
    emit tabsChanged();
    scheduleSave(QStringLiteral("workspace: customize tab"));
    return true;
}

bool WorkspaceManager::updateTabAppearance(const QString &tabId,
    const QVariantMap &appearance)
{
    if (!requireWritable())
        return false;
    const int row = indexOfTab(tabId);
    if (row < 0)
        return false;
    Tab &tab = m_tabs[row];
    tab.appearance = normalizedAppearance(appearance);
    tab.updatedAt = QDateTime::currentDateTimeUtc();
    emit dataChanged(index(row), index(row), {
        FontFamilyRole, FontStyleRole, FontPointSizeRole, BoldRole, ItalicRole,
        FontColorRole, AppearanceRole, UpdatedAtRole
    });
    emit tabsChanged();
    emit appearanceChanged();
    scheduleSave(QStringLiteral("workspace: edit tab appearance"));
    return true;
}

bool WorkspaceManager::updateGroupAppearance(const QString &groupId,
    const QVariantMap &appearance)
{
    if (!requireWritable())
        return false;
    const int row = indexOfGroup(groupId);
    if (row < 0)
        return false;
    m_groups[row].appearance = normalizedAppearance(appearance);
    emit groupsChanged();
    emit appearanceChanged();
    scheduleSave(QStringLiteral("workspace: edit group appearance"));
    return true;
}

bool WorkspaceManager::updateGlobalAppearance(const QVariantMap &appearance)
{
    if (!requireWritable())
        return false;
    m_globalAppearance = normalizedAppearance(appearance);
    emit appearanceChanged();
    scheduleSave(QStringLiteral("workspace: edit global appearance"));
    return true;
}

bool WorkspaceManager::resetTabAppearance(const QString &tabId,
    const QString &propertyName)
{
    const int row = indexOfTab(tabId);
    if (!requireWritable() || row < 0)
        return false;
    QVariantMap appearance = m_tabs.at(row).appearance;
    if (propertyName.trimmed().isEmpty())
        appearance.clear();
    else
        appearance.remove(propertyName.trimmed());
    return updateTabAppearance(tabId, appearance);
}

bool WorkspaceManager::resetGroupAppearance(const QString &groupId,
    const QString &propertyName)
{
    const int row = indexOfGroup(groupId);
    if (!requireWritable() || row < 0)
        return false;
    QVariantMap appearance = m_groups.at(row).appearance;
    if (propertyName.trimmed().isEmpty())
        appearance.clear();
    else
        appearance.remove(propertyName.trimmed());
    return updateGroupAppearance(groupId, appearance);
}

bool WorkspaceManager::resetGlobalAppearance(const QString &propertyName)
{
    if (!requireWritable())
        return false;
    QVariantMap appearance = m_globalAppearance;
    if (propertyName.trimmed().isEmpty())
        appearance.clear();
    else
        appearance.remove(propertyName.trimmed());
    return updateGlobalAppearance(appearance);
}

bool WorkspaceManager::saveAppearancePreset(const QString &name,
    const QVariantMap &appearance)
{
    if (!requireWritable())
        return false;
    const QString normalized = normalizedName(name, 80, tr("Appearance preset"));
    const QVariantMap values = normalizedAppearance(appearance);
    for (qsizetype i = 0; i < m_appearancePresets.size(); ++i)
    {
        QVariantMap preset = m_appearancePresets.at(i).toMap();
        if (preset.value(QStringLiteral("name")).toString().compare(normalized,
            Qt::CaseInsensitive) == 0)
        {
            preset.insert(QStringLiteral("name"), normalized);
            preset.insert(QStringLiteral("appearance"), values);
            m_appearancePresets[i] = preset;
            emit appearanceChanged();
            scheduleSave(QStringLiteral("workspace: update appearance preset"));
            return true;
        }
    }
    if (m_appearancePresets.size() >= 32)
        return false;
    m_appearancePresets.push_back(QVariantMap {
        {QStringLiteral("name"), normalized},
        {QStringLiteral("appearance"), values}
    });
    emit appearanceChanged();
    scheduleSave(QStringLiteral("workspace: save appearance preset"));
    return true;
}

bool WorkspaceManager::removeAppearancePreset(const QString &name)
{
    if (!requireWritable())
        return false;
    for (qsizetype i = 0; i < m_appearancePresets.size(); ++i)
    {
        if (m_appearancePresets.at(i).toMap().value(QStringLiteral("name")).toString()
            .compare(name.trimmed(), Qt::CaseInsensitive) == 0)
        {
            m_appearancePresets.removeAt(i);
            emit appearanceChanged();
            scheduleSave(QStringLiteral("workspace: remove appearance preset"));
            return true;
        }
    }
    return false;
}

bool WorkspaceManager::exportAppearancePreset(const QString &name,
    const QUrl &destination)
{
    QVariantMap selected;
    for (const QVariant &value : std::as_const(m_appearancePresets))
    {
        const QVariantMap preset = value.toMap();
        if (preset.value(QStringLiteral("name")).toString().compare(name,
            Qt::CaseInsensitive) == 0)
        {
            selected = preset;
            break;
        }
    }
    const QString path = localPath(destination);
    if (selected.isEmpty() || path.isEmpty())
        return false;
    QJsonObject object = QJsonObject::fromVariantMap(selected);
    object.insert(QStringLiteral("type"), QStringLiteral("qbt-material-appearance-preset"));
    object.insert(QStringLiteral("schemaVersion"), 1);
    QString error;
    const bool success = writeFileAtomically(path,
        QJsonDocument(object).toJson(QJsonDocument::Indented), &error);
    emit operationFinished(success, success ? tr("Appearance preset exported.")
        : tr("Could not export the appearance preset: %1").arg(error),
        success ? QUrl::fromLocalFile(path) : QUrl());
    return success;
}

bool WorkspaceManager::importAppearancePreset(const QUrl &source)
{
    if (!requireWritable())
        return false;
    const QString path = localPath(source);
    QFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::ReadOnly) || file.size() > 128 * 1024)
        return false;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (!document.isObject())
        return false;
    const QJsonObject object = document.object();
    if (object.value(QStringLiteral("type")).toString()
        != QStringLiteral("qbt-material-appearance-preset")
        || object.value(QStringLiteral("schemaVersion")).toInt() != 1
        || !object.value(QStringLiteral("appearance")).isObject())
        return false;
    return saveAppearancePreset(object.value(QStringLiteral("name")).toString(),
        object.value(QStringLiteral("appearance")).toObject().toVariantMap());
}

QVariantMap WorkspaceManager::validatePattern(const QString &pattern,
    const QString &flags) const
{
    QString error;
    const QRegularExpression expression = regularExpression(pattern, flags, &error);
    return {
        {QStringLiteral("valid"), expression.isValid()},
        {QStringLiteral("error"), error},
        {QStringLiteral("errorOffset"), expression.isValid() ? -1
            : qMax<qsizetype>(0, expression.patternErrorOffset()
                - RegexSafetyPrefix.size())},
        {QStringLiteral("dialect"), QStringLiteral("Qt QRegularExpression (PCRE2)")},
        {QStringLiteral("flags"), flags.toLower()}
    };
}

QVariantMap WorkspaceManager::evaluateRegularExpression(const QString &pattern,
    const QString &flags, const QString &sampleText) const
{
    if (sampleText.size() > MaximumSampleCharacters)
    {
        return {
            {QStringLiteral("valid"), false},
            {QStringLiteral("error"), tr("Sample text is limited to 64 KiB.")},
            {QStringLiteral("dialect"), QStringLiteral("Qt QRegularExpression (PCRE2)")}
        };
    }
    QString error;
    const QRegularExpression expression = regularExpression(pattern, flags, &error);
    QVariantList matches;
    bool truncated = false;
    if (expression.isValid() && !pattern.isEmpty())
    {
        QRegularExpressionMatchIterator iterator = expression.globalMatch(sampleText);
        while (iterator.hasNext())
        {
            if (matches.size() >= MaximumRegexMatches)
            {
                truncated = true;
                break;
            }
            const QRegularExpressionMatch match = iterator.next();
            QVariantList captures;
            const QStringList capturedTexts = match.capturedTexts();
            for (qsizetype capture = 0; capture < capturedTexts.size(); ++capture)
            {
                captures.push_back(QVariantMap {
                    {QStringLiteral("index"), capture},
                    {QStringLiteral("name"), expression.captureCount() >= capture
                        ? expression.namedCaptureGroups().value(capture) : QString()},
                    {QStringLiteral("text"), capturedTexts.at(capture).left(4096)},
                    {QStringLiteral("start"), match.capturedStart(capture)},
                    {QStringLiteral("length"), match.capturedLength(capture)}
                });
            }
            matches.push_back(QVariantMap {
                {QStringLiteral("start"), match.capturedStart()},
                {QStringLiteral("length"), match.capturedLength()},
                {QStringLiteral("text"), match.captured().left(4096)},
                {QStringLiteral("captures"), captures}
            });
            if (!flags.contains(QLatin1Char('g'), Qt::CaseInsensitive))
                break;
        }
    }
    return {
        {QStringLiteral("valid"), expression.isValid()},
        {QStringLiteral("error"), error},
        {QStringLiteral("errorOffset"), expression.isValid() ? -1
            : qMax<qsizetype>(0, expression.patternErrorOffset()
                - RegexSafetyPrefix.size())},
        {QStringLiteral("dialect"), QStringLiteral("Qt QRegularExpression (PCRE2)")},
        {QStringLiteral("matches"), matches},
        {QStringLiteral("count"), matches.size()},
        {QStringLiteral("truncated"), truncated}
    };
}

QVariantMap WorkspaceManager::searchTabs(const QString &query, const bool regex,
    const QString &flags, const QString &groupId) const
{
    return queryTabs(query, regex, flags, groupId, false, true, false);
}

QVariantMap WorkspaceManager::searchGroups(const QString &query, const bool regex,
    const QString &flags) const
{
    QString error;
    const QRegularExpression expression = regex
        ? regularExpression(query, flags, &error) : QRegularExpression();
    QVariantList items;
    const bool valid = !regex || expression.isValid();
    const Qt::CaseSensitivity sensitivity = flags.contains(QLatin1Char('i'),
        Qt::CaseInsensitive) ? Qt::CaseInsensitive : Qt::CaseSensitive;
    if (valid)
    {
        for (int i = 0; i < m_groups.size(); ++i)
        {
            const Group &group = m_groups.at(i);
            const bool match = query.isEmpty()
                || (regex ? expression.match(group.name).hasMatch()
                          : group.name.contains(query, sensitivity));
            if (!match)
                continue;
            QVariantMap item = groupMap(group);
            item.insert(QStringLiteral("index"), i);
            item.insert(QStringLiteral("tabCount"), static_cast<int>(std::count_if(
                m_tabs.cbegin(), m_tabs.cend(), [&group](const Tab &tab)
                { return tab.groupId == group.id; })));
            items.push_back(item);
        }
    }
    return {
        {QStringLiteral("valid"), valid},
        {QStringLiteral("error"), error},
        {QStringLiteral("items"), items},
        {QStringLiteral("count"), items.size()},
        {QStringLiteral("dialect"), QStringLiteral("Qt QRegularExpression (PCRE2)")}
    };
}

QVariantMap WorkspaceManager::previewCloseTabs(const QString &query,
    const bool regex, const QString &flags, const bool inverse,
    const bool includePinned, const QString &groupId) const
{
    return queryTabs(query, regex, flags, groupId, inverse, includePinned, true);
}

bool WorkspaceManager::closeTabsByText(const QString &query, const bool regex,
    const QString &flags, const bool inverse, const bool includePinned,
    const QString &groupId)
{
    if (!requireWritable())
        return false;
    const QVariantMap preview = previewCloseTabs(query, regex, flags, inverse,
        includePinned, groupId);
    if (!preview.value(QStringLiteral("valid")).toBool()
        || preview.value(QStringLiteral("count")).toInt() <= 0)
        return false;

    if (m_dirty)
    {
        QString error;
        if (!saveNow(QStringLiteral("workspace: checkpoint before bulk close"), &error))
        {
            emit operationFinished(false,
                tr("Tabs were not closed because current edits could not be checkpointed: %1")
                    .arg(error), {});
            return false;
        }
    }

    const QSet<QString> previouslyNonEmpty = nonEmptyGroupIds();
    QSet<QString> ids;
    const QVariantList items = preview.value(QStringLiteral("items")).toList();
    for (const QVariant &value : items)
        ids.insert(value.toMap().value(QStringLiteral("tabId")).toString());
    const QString activeId = activeTabId();
    beginResetModel();
    m_tabs.erase(std::remove_if(m_tabs.begin(), m_tabs.end(), [&ids](const Tab &tab)
        { return ids.contains(tab.id); }), m_tabs.end());
    m_activeIndex = indexOfTab(activeId);
    if (m_activeIndex < 0 && !m_tabs.isEmpty())
        m_activeIndex = 0;
    endResetModel();
    pruneNewlyEmptyGroups(previouslyNonEmpty);
    emit countChanged();
    emit activeIndexChanged();
    emit tabsChanged();
    scheduleSave(inverse ? QStringLiteral("workspace: close tabs not containing text")
                         : QStringLiteral("workspace: close tabs containing text"));
    emit operationFinished(true,
        tr("Closed %1 workspace tab(s). Pinned tabs were %2.")
            .arg(ids.size()).arg(includePinned ? tr("included") : tr("protected")), {});
    return true;
}

QStringList WorkspaceManager::fontFamilies() const
{
    QStringList families = QFontDatabase::families();
    families.sort(Qt::CaseInsensitive);
    return families;
}

QStringList WorkspaceManager::fontStyles(const QString &family) const
{
    QStringList styles = QFontDatabase::styles(family);
    if (styles.isEmpty())
        styles << QStringLiteral("Regular");
    return styles;
}

QFont WorkspaceManager::resolvedFont(const QString &family, const QString &style,
    const double pointSize, const bool bold, const bool italic) const
{
    const double normalizedSize = qBound(6.0, pointSize, 144.0);
    QFont font = QFontDatabase::font(family, style, qRound(normalizedSize));
    // Preserve the selected face's weight/stretch/slant as ordinary QFont
    // attributes, then clear styleName so explicit Bold and Italic additions
    // are not ignored by Qt's named-style matching.
    font.setStyleName(QString());
    font.setPointSizeF(normalizedSize);
    if (bold)
        font.setBold(true);
    if (italic)
        font.setItalic(true);
    return font;
}

QUrl WorkspaceManager::suggestedExportUrl(const QString &fileName) const
{
    const QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return QUrl::fromLocalFile(QDir(documents).filePath(QFileInfo(fileName).fileName()));
}

bool WorkspaceManager::openRepository() const
{
    return QDesktopServices::openUrl(repositoryUrl());
}

bool WorkspaceManager::syncNow()
{
    if (!requireWritable())
        return false;
    m_saveTimer.stop();
    QString error;
    const bool ok = saveNow(QStringLiteral("workspace: manual sync"), &error);
    emit operationFinished(ok, ok ? tr("Workspace committed to local Git.") : error, repositoryUrl());
    return ok;
}

bool WorkspaceManager::exportWorkspace(const QUrl &destination)
{
    const QString path = localPath(destination);
    if (path.isEmpty())
    {
        emit operationFinished(false, tr("Choose a local JSON destination."), {});
        return false;
    }
    const QFileInfo destinationInfo(path);
    const QFileInfo destinationParent(destinationInfo.absolutePath());
    if (isInsidePath(path, m_repositoryPath)
        || !destinationParent.isDir() || hasSymlinkIdentity(destinationParent)
        || (destinationInfo.exists() && (!destinationInfo.isFile() || hasSymlinkIdentity(destinationInfo))))
    {
        emit operationFinished(false,
            tr("Choose a safe JSON file outside the managed Git repository."), {});
        return false;
    }
    qint64 contentBytes = 0;
    for (const Tab &tab : std::as_const(m_tabs))
    {
        contentBytes += tab.content.toUtf8().size();
        if (contentBytes > MaximumWorkspaceBytes)
        {
            emit operationFinished(false,
                tr("This workspace is larger than the 32 MB JSON export limit. Export its complete Git repository instead."), {});
            return false;
        }
    }
    QJsonObject object = workspaceObject(true);
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (payload.size() > MaximumWorkspaceBytes)
    {
        emit operationFinished(false,
            tr("This workspace is larger than the 32 MB JSON export limit. Export its complete Git repository instead."), {});
        return false;
    }
    QString error;
    const bool ok = writeFileAtomically(path, payload, &error);
    emit operationFinished(ok,
        ok ? tr("Workspace snapshot exported.") : error, QUrl::fromLocalFile(path));
    return ok;
}

bool WorkspaceManager::importWorkspace(const QUrl &source)
{
    if (!requireWritable())
        return false;
    const QString path = localPath(source);
    const QFileInfo info(path);
    if (path.isEmpty() || !info.isFile() || info.size() > MaximumWorkspaceBytes || hasSymlinkIdentity(info))
    {
        emit operationFinished(false, tr("The selected workspace JSON is not a safe local file."), {});
        return false;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        emit operationFinished(false, file.errorString(), QUrl::fromLocalFile(path));
        return false;
    }
    Snapshot snapshot;
    QString error;
    if (!parseWorkspace(file.readAll(), &snapshot, &error, true))
    {
        emit operationFinished(false, error, QUrl::fromLocalFile(path));
        return false;
    }

    Snapshot previous {m_appDisplayName, activeTabId(), m_tabs, m_groups,
        m_globalAppearance, m_appearancePresets};
    if (!saveNow(QStringLiteral("workspace: backup before JSON import"), &error))
    {
        emit operationFinished(false, error, repositoryUrl());
        return false;
    }
    const QSet<QString> previousManagedTabFiles = m_managedTabFiles;
    QHash<QString, QByteArray> rollbackCandidateContents;
    for (const Tab &tab : std::as_const(snapshot.tabs))
    {
        const QString fileName = tab.id + QStringLiteral(".md");
        const QString path = QDir(m_repositoryPath).filePath(
            QStringLiteral("tabs/%1").arg(fileName));
        const QByteArray incomingBytes = tab.content.toUtf8();
        if (!QFileInfo::exists(path))
        {
            rollbackCandidateContents.insert(fileName, incomingBytes);
            continue;
        }
        if (previousManagedTabFiles.contains(fileName))
            continue;

        QFile collision(path);
        if (!collision.open(QIODevice::ReadOnly) || collision.readAll() != incomingBytes)
        {
            emit operationFinished(false,
                tr("Import was cancelled because an untracked recovery page already uses tab identifier %1. "
                   "The existing file was left untouched.").arg(tab.id),
                QUrl::fromLocalFile(path));
            return false;
        }
    }
    applySnapshot(std::move(snapshot));
    if (!saveNow(QStringLiteral("workspace: import JSON snapshot"), &error))
    {
        // writeManagedFiles can fail after writing only part of the imported
        // bodies. Delete only candidate files whose bytes prove this import
        // wrote them; preserve every preexisting unmanaged recovery file.
        QSet<QString> rollbackManagedFiles = previousManagedTabFiles;
        for (auto it = rollbackCandidateContents.cbegin(); it != rollbackCandidateContents.cend(); ++it)
        {
            QFile candidate(QDir(m_repositoryPath).filePath(
                QStringLiteral("tabs/%1").arg(it.key())));
            if (candidate.open(QIODevice::ReadOnly) && candidate.readAll() == it.value())
                rollbackManagedFiles.insert(it.key());
        }
        m_managedTabFiles = std::move(rollbackManagedFiles);
        applySnapshot(std::move(previous));
        QString rollbackError;
        const bool restored = saveNow(QStringLiteral("workspace: restore after failed JSON import"), &rollbackError);
        if (!restored)
            setDirty(true);
        emit operationFinished(false,
            restored ? tr("Import failed and the previous workspace was restored: %1").arg(error)
                     : tr("Import failed; automatic restoration also needs attention: %1 / %2")
                           .arg(error, rollbackError),
            QUrl::fromLocalFile(path));
        return false;
    }
    emit operationFinished(true, tr("Workspace snapshot imported and committed."), repositoryUrl());
    return true;
}

bool WorkspaceManager::exportRepository(const QUrl &destinationFolder)
{
    const QString destinationRoot = localPath(destinationFolder);
    QFileInfo destinationInfo(destinationRoot);
    if (destinationRoot.isEmpty() || !destinationInfo.isDir() || hasSymlinkIdentity(destinationInfo))
    {
        emit operationFinished(false, tr("Choose a safe local folder for the Git repository."), {});
        return false;
    }
    QString error;
    if (!saveNow(QStringLiteral("workspace: prepare repository export"), &error))
    {
        emit operationFinished(false, error, repositoryUrl());
        return false;
    }

    const QString folderName = QStringLiteral("%1-workspace-repo-%2-%3")
        .arg(fileSafeName(m_appDisplayName),
            QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-HHmmss-zzz")),
            QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
    const QString destination = QDir(destinationRoot).filePath(folderName);
    if (isInsidePath(destination, m_repositoryPath) || isInsidePath(m_repositoryPath, destination))
    {
        emit operationFinished(false, tr("The export folder cannot be inside the managed repository."), {});
        return false;
    }
    if (!QDir(destinationRoot).mkdir(folderName))
    {
        emit operationFinished(false, tr("Could not create a unique repository export folder."), {});
        return false;
    }
    qint64 copied = 0;
    const bool ok = copyTree(m_repositoryPath, destination, &copied, &error)
        && validateRepositoryRoot(destination, &error);
    if (!ok)
    {
        QString removeError;
        (void)removeTree(destination, &removeError);
    }
    emit operationFinished(ok,
        ok ? tr("Complete Git repository exported with its history.") : error,
        ok ? QUrl::fromLocalFile(destination) : QUrl());
    return ok;
}

bool WorkspaceManager::importRepository(const QUrl &sourceFolder)
{
    if (!requireWritable())
        return false;
    const QString source = localPath(sourceFolder);
    QString error;
    if (source.isEmpty() || isInsidePath(source, m_repositoryPath)
        || isInsidePath(m_repositoryPath, source)
        || !validateRepositoryRoot(source, &error))
    {
        emit operationFinished(false,
            error.isEmpty() ? tr("Choose an exported workspace Git repository.") : error, {});
        return false;
    }

    Snapshot previous {m_appDisplayName, activeTabId(), m_tabs, m_groups,
        m_globalAppearance, m_appearancePresets};
    const QSet<QString> previousManagedTabFiles = m_managedTabFiles;
    if (!saveNow(QStringLiteral("workspace: backup before repository import"), &error))
    {
        emit operationFinished(false, error, repositoryUrl());
        return false;
    }

    const QString parent = QFileInfo(m_repositoryPath).absolutePath();
    const QString nonce = QStringLiteral("%1-%2")
        .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-HHmmss-zzz")),
            QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
    const QString staging = QDir(parent).filePath(QStringLiteral(".workspace-import-%1").arg(nonce));
    const QString backup = QDir(parent).filePath(QStringLiteral(".workspace-backup-%1").arg(nonce));
    qint64 copied = 0;
    Snapshot importedSnapshot;
    QSet<QString> importedTrackedExtras;
    if (!copyTree(source, staging, &copied, &error)
        || !validateRepositoryRoot(staging, &error)
        || !loadSnapshotFromRoot(staging, &importedSnapshot, &error, &importedTrackedExtras))
    {
        QString removeError;
        (void)removeTree(staging, &removeError);
        emit operationFinished(false, error, QUrl::fromLocalFile(source));
        return false;
    }
    QSet<QString> importedManagedTabFiles;
    for (const Tab &tab : std::as_const(importedSnapshot.tabs))
        importedManagedTabFiles.insert(tab.id + QStringLiteral(".md"));
    importedManagedTabFiles.unite(importedTrackedExtras);

    QDir parentDir(parent);
    const QString currentName = QFileInfo(m_repositoryPath).fileName();
    if (!parentDir.rename(currentName, QFileInfo(backup).fileName()))
    {
        (void)removeTree(staging, nullptr);
        emit operationFinished(false, tr("Could not create a safety backup of the current repository."), {});
        return false;
    }
    if (!parentDir.rename(QFileInfo(staging).fileName(), currentName))
    {
        const bool restored = parentDir.rename(QFileInfo(backup).fileName(), currentName);
        if (restored)
            (void)removeTree(staging, nullptr);
        else
        {
            m_initializationBlocked = true;
            emit writableChanged();
            m_repositoryStatus = tr("Repository import was interrupted; recovery copies were preserved");
            emit repositoryStatusChanged();
        }
        emit operationFinished(false,
            restored ? tr("Could not activate the imported repository; the previous repository was restored.")
                     : tr("Could not activate or restore the repository automatically. Recovery copies were preserved in %1.")
                           .arg(QDir::toNativeSeparators(parent)),
            restored ? repositoryUrl() : QUrl::fromLocalFile(parent));
        return false;
    }

    applySnapshot(std::move(importedSnapshot));
    m_managedTabFiles = std::move(importedManagedTabFiles);
    QString activationError;
    if (!saveNow(QStringLiteral("workspace: activate imported repository"), &activationError))
    {
        const QString failedName = QStringLiteral(".workspace-failed-import-%1").arg(nonce);
        const bool movedFailedImport = parentDir.rename(currentName, failedName);
        const bool restored = movedFailedImport
            && parentDir.rename(QFileInfo(backup).fileName(), currentName);
        if (restored)
        {
            applySnapshot(std::move(previous));
            m_managedTabFiles = previousManagedTabFiles;
            updateRepositoryStatus();
            setDirty(false);
        }
        else
        {
            if (movedFailedImport)
                parentDir.rename(failedName, currentName);
            m_initializationBlocked = true;
            emit writableChanged();
            setDirty(true);
            m_repositoryStatus = tr("Imported repository needs manual recovery; all copies were preserved");
            emit repositoryStatusChanged();
        }
        emit operationFinished(false,
            restored ? tr("Imported repository validation failed and the previous repository was restored: %1")
                           .arg(activationError)
                     : tr("Imported repository validation failed and automatic restoration needs attention: %1")
                           .arg(activationError),
            QUrl::fromLocalFile(parent));
        return false;
    }

    m_recoveryPath = backup;
    emit operationFinished(true,
        tr("Git repository and complete tab history imported. The previous repository is kept at %1.")
            .arg(QDir::toNativeSeparators(backup)),
        repositoryUrl());
    return true;
}

QString WorkspaceManager::localPath(const QUrl &url)
{
    if (url.isLocalFile())
        return QDir::cleanPath(url.toLocalFile());
    const QString text = url.toString();
    if (url.scheme().isEmpty() && QFileInfo(text).isAbsolute())
        return QDir::cleanPath(text);
    return {};
}

QString WorkspaceManager::normalizedName(const QString &value, const int maximum,
    const QString &fallback)
{
    QString result = value.trimmed();
    result.remove(QChar::Null);
    if (result.isEmpty())
        result = fallback;
    return result.left(maximum);
}

QString WorkspaceManager::normalizedColor(const QString &value)
{
    const QColor color(value);
    return color.isValid() ? color.name(QColor::HexArgb).toUpper()
                           : QStringLiteral("#FF6750A4");
}

QString WorkspaceManager::newTabId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QString WorkspaceManager::fileSafeName(const QString &value)
{
    QString result = value.toLower();
    result.replace(QRegularExpression(QStringLiteral("[^a-z0-9._-]+")), QStringLiteral("-"));
    result.remove(QRegularExpression(QStringLiteral("^-+|-+$")));
    return result.isEmpty() ? QStringLiteral("workspace") : result.left(64);
}

bool WorkspaceManager::isInsidePath(const QString &candidate, const QString &root)
{
    const auto resolvedPath = [](const QString &value)
    {
        QString probe = QDir::cleanPath(QFileInfo(value).absoluteFilePath());
        QStringList missingParts;
        QFileInfo info(probe);
        while (!info.exists())
        {
            const QString fileName = info.fileName();
            const QString parent = info.absolutePath();
            if (fileName.isEmpty() || parent == probe)
                break;
            missingParts.prepend(fileName);
            probe = parent;
            info.setFile(probe);
        }
        QString result = info.canonicalFilePath();
        if (result.isEmpty())
            result = info.absoluteFilePath();
        for (const QString &part : std::as_const(missingParts))
            result = QDir(result).filePath(part);
        return QDir::fromNativeSeparators(QDir::cleanPath(result));
    };

    const QString cleanCandidate = resolvedPath(candidate);
    const QString cleanRoot = resolvedPath(root);
#ifdef Q_OS_WIN
    constexpr auto pathCaseSensitivity = Qt::CaseInsensitive;
#else
    constexpr auto pathCaseSensitivity = Qt::CaseSensitive;
#endif
    if (cleanCandidate.compare(cleanRoot, pathCaseSensitivity) == 0)
        return true;
    return cleanCandidate.startsWith(cleanRoot + QStringLiteral("/"), pathCaseSensitivity);
}

bool WorkspaceManager::containsReparsePoint(const QString &path, const QString &root)
{
    if (!isInsidePath(path, root))
        return true;
    QString current = QDir::cleanPath(root);
    const QString relative = QDir(root).relativeFilePath(path);
    const QStringList parts = relative.split(QRegularExpression(QStringLiteral("[/\\\\]+")), Qt::SkipEmptyParts);
    for (const QString &part : parts)
    {
        current = QDir(current).filePath(part);
        const QFileInfo info(current);
        if (info.exists() && hasSymlinkIdentity(info))
            return true;
    }
    return false;
}

QVariantMap WorkspaceManager::tabMap(const Tab &tab) const
{
    return {
        {QStringLiteral("tabId"), tab.id},
        {QStringLiteral("name"), tab.name},
        {QStringLiteral("content"), tab.content},
        {QStringLiteral("fontFamily"), tab.fontFamily},
        {QStringLiteral("fontStyle"), tab.fontStyle},
        {QStringLiteral("fontPointSize"), tab.fontPointSize},
        {QStringLiteral("bold"), tab.bold},
        {QStringLiteral("italic"), tab.italic},
        {QStringLiteral("fontColor"), tab.fontColor},
        {QStringLiteral("pinned"), tab.pinned},
        {QStringLiteral("groupId"), tab.groupId},
        {QStringLiteral("groupName"), groupName(tab.groupId)},
        {QStringLiteral("groupColor"), groupColor(tab.groupId)},
        {QStringLiteral("groupCollapsed"), groupCollapsed(tab.groupId)},
        {QStringLiteral("appearance"), tab.appearance},
        {QStringLiteral("createdAt"), isoDate(tab.createdAt)},
        {QStringLiteral("updatedAt"), isoDate(tab.updatedAt)}
    };
}

QVariantMap WorkspaceManager::groupMap(const Group &group) const
{
    return {
        {QStringLiteral("groupId"), group.id},
        {QStringLiteral("name"), group.name},
        {QStringLiteral("color"), group.color},
        {QStringLiteral("collapsed"), group.collapsed},
        {QStringLiteral("appearance"), group.appearance}
    };
}

int WorkspaceManager::indexOfTab(const QString &tabId) const
{
    for (int i = 0; i < m_tabs.size(); ++i)
    {
        if (m_tabs.at(i).id == tabId)
            return i;
    }
    return -1;
}

int WorkspaceManager::indexOfGroup(const QString &groupId) const
{
    for (int i = 0; i < m_groups.size(); ++i)
    {
        if (m_groups.at(i).id == groupId)
            return i;
    }
    return -1;
}

QString WorkspaceManager::groupName(const QString &groupId) const
{
    const int row = indexOfGroup(groupId);
    return row >= 0 ? m_groups.at(row).name : QString();
}

QString WorkspaceManager::groupColor(const QString &groupId) const
{
    const int row = indexOfGroup(groupId);
    return row >= 0 ? m_groups.at(row).color : QStringLiteral("#00000000");
}

bool WorkspaceManager::groupCollapsed(const QString &groupId) const
{
    const int row = indexOfGroup(groupId);
    return row >= 0 && m_groups.at(row).collapsed;
}

QVariantMap WorkspaceManager::normalizedAppearance(const QVariantMap &appearance)
{
    // Sparse overrides are intentionally data-only. Restrict keys and sizes so
    // imported themes cannot grow the workspace manifest without bound.
    static const QSet<QString> allowed {
        QStringLiteral("fontFamily"), QStringLiteral("fontStyle"),
        QStringLiteral("fontPointSize"), QStringLiteral("fontWeight"),
        QStringLiteral("bold"), QStringLiteral("italic"),
        QStringLiteral("underline"), QStringLiteral("underlineStyle"),
        QStringLiteral("underlineColor"), QStringLiteral("strikeout"),
        QStringLiteral("doubleStrike"), QStringLiteral("overline"),
        QStringLiteral("capitalization"), QStringLiteral("smallCaps"),
        QStringLiteral("superscript"), QStringLiteral("subscript"),
        QStringLiteral("textColor"), QStringLiteral("highlightColor"),
        QStringLiteral("outlineColor"), QStringLiteral("shadowColor"),
        QStringLiteral("glowColor"), QStringLiteral("letterSpacing"),
        QStringLiteral("wordSpacing"), QStringLiteral("lineHeight"),
        QStringLiteral("baselineOffset"), QStringLiteral("direction"),
        QStringLiteral("alignment"), QStringLiteral("backgroundColor"),
        QStringLiteral("borderColor"), QStringLiteral("borderWidth"),
        QStringLiteral("radius"), QStringLiteral("padding"),
        QStringLiteral("spacing"), QStringLiteral("opacity"),
        QStringLiteral("icon"), QStringLiteral("badge"),
        QStringLiteral("separatorColor"), QStringLiteral("hoverColor"),
        QStringLiteral("focusColor"), QStringLiteral("checkedColor"),
        QStringLiteral("disabledColor")
    };
    QVariantMap result;
    for (auto it = appearance.cbegin(); it != appearance.cend() && result.size() < 64; ++it)
    {
        if (!allowed.contains(it.key()))
            continue;
        QVariant value = it.value();
        if (value.metaType().id() == QMetaType::QString)
            value = value.toString().left(256);
        if (it.key() == QStringLiteral("fontPointSize"))
            value = qBound(6.0, value.toDouble(), 144.0);
        else if (it.key() == QStringLiteral("fontWeight"))
            value = qBound(1, value.toInt(), 1000);
        else if (it.key() == QStringLiteral("letterSpacing")
            || it.key() == QStringLiteral("wordSpacing"))
            value = qBound(-50.0, value.toDouble(), 200.0);
        else if (it.key() == QStringLiteral("lineHeight"))
            value = qBound(0.5, value.toDouble(), 5.0);
        else if (it.key() == QStringLiteral("baselineOffset"))
            value = qBound(-100.0, value.toDouble(), 100.0);
        else if (it.key() == QStringLiteral("borderWidth"))
            value = qBound(0.0, value.toDouble(), 20.0);
        else if (it.key() == QStringLiteral("radius"))
            value = qBound(0.0, value.toDouble(), 200.0);
        else if (it.key() == QStringLiteral("padding")
            || it.key() == QStringLiteral("spacing"))
            value = qBound(0.0, value.toDouble(), 200.0);
        else if (it.key() == QStringLiteral("opacity"))
            value = qBound(0.0, value.toDouble(), 1.0);
        if (it.key().endsWith(QStringLiteral("Color")))
        {
            const QColor color(value.toString());
            if (!color.isValid())
                continue;
            value = color.name(QColor::HexArgb).toUpper();
        }
        result.insert(it.key(), value);
    }
    return result;
}

QRegularExpression WorkspaceManager::regularExpression(const QString &pattern,
    const QString &flags, QString *error)
{
    if (pattern.size() > MaximumPatternCharacters)
    {
        if (error) *error = QObject::tr("Patterns are limited to 4,096 characters.");
        return QRegularExpression(QStringLiteral("("));
    }
    const QString normalizedFlags = flags.toLower();
    for (const QChar flag : normalizedFlags)
    {
        if (!QStringLiteral("gimsu").contains(flag))
        {
            if (error) *error = QObject::tr("Unsupported regular-expression flag: %1").arg(flag);
            return QRegularExpression(QStringLiteral("("));
        }
    }
    QRegularExpression::PatternOptions options = QRegularExpression::NoPatternOption;
    if (normalizedFlags.contains(QLatin1Char('i')))
        options |= QRegularExpression::CaseInsensitiveOption;
    if (normalizedFlags.contains(QLatin1Char('m')))
        options |= QRegularExpression::MultilineOption;
    if (normalizedFlags.contains(QLatin1Char('s')))
        options |= QRegularExpression::DotMatchesEverythingOption;
    if (normalizedFlags.contains(QLatin1Char('u')))
        options |= QRegularExpression::UseUnicodePropertiesOption;
    // PCRE2 start verbs cap backtracking work and recursion depth for every
    // consumer. The non-capturing wrapper preserves capture numbering.
    QRegularExpression expression(RegexSafetyPrefix + pattern + QLatin1Char(')'), options);
    if (!expression.isValid() && error)
        *error = expression.errorString();
    else if (error)
        error->clear();
    return expression;
}

QVariantMap WorkspaceManager::queryTabs(const QString &query, const bool regex,
    const QString &flags, const QString &groupId, const bool inverse,
    const bool includePinned, const bool closingPreview) const
{
    QString error;
    if (closingPreview && query.trimmed().isEmpty())
    {
        return {
            {QStringLiteral("valid"), false},
            {QStringLiteral("error"), tr("Enter text or a regular expression before closing tabs.")},
            {QStringLiteral("items"), QVariantList()},
            {QStringLiteral("count"), 0}
        };
    }
    const QRegularExpression expression = regex
        ? regularExpression(query, flags, &error) : QRegularExpression();
    const bool valid = !regex || expression.isValid();
    const Qt::CaseSensitivity sensitivity = flags.contains(QLatin1Char('i'),
        Qt::CaseInsensitive) ? Qt::CaseInsensitive : Qt::CaseSensitive;
    QVariantList items;
    int excludedPinned = 0;
    if (valid)
    {
        for (int i = 0; i < m_tabs.size(); ++i)
        {
            const Tab &tab = m_tabs.at(i);
            if (!groupId.isEmpty() && tab.groupId != groupId)
                continue;
            bool match = query.isEmpty()
                || (regex ? expression.match(tab.name).hasMatch()
                          : tab.name.contains(query, sensitivity));
            if (inverse)
                match = !match;
            if (!match)
                continue;
            if (closingPreview && tab.pinned && !includePinned)
            {
                ++excludedPinned;
                continue;
            }
            QVariantMap item = tabMap(tab);
            item.insert(QStringLiteral("index"), i);
            item.insert(QStringLiteral("window"), tr("Workspace window"));
            item.insert(QStringLiteral("strip"), tr("Workspace tab strip"));
            item.insert(QStringLiteral("location"), tab.groupId.isEmpty()
                ? tr("Ungrouped") : tr("Group: %1").arg(groupName(tab.groupId)));
            items.push_back(item);
        }
    }
    return {
        {QStringLiteral("valid"), valid},
        {QStringLiteral("error"), error},
        {QStringLiteral("items"), items},
        {QStringLiteral("count"), items.size()},
        {QStringLiteral("excludedPinned"), excludedPinned},
        {QStringLiteral("willCheckpoint"), closingPreview && m_dirty},
        {QStringLiteral("mode"), regex ? QStringLiteral("regex") : QStringLiteral("plain")},
        {QStringLiteral("flags"), flags.toLower()},
        {QStringLiteral("dialect"), QStringLiteral("Qt QRegularExpression (PCRE2)")}
    };
}

void WorkspaceManager::normalizePinnedOrder()
{
    std::stable_partition(m_tabs.begin(), m_tabs.end(),
        [](const Tab &tab) { return tab.pinned; });
}

QSet<QString> WorkspaceManager::nonEmptyGroupIds() const
{
    QSet<QString> result;
    for (const Tab &tab : m_tabs)
    {
        if (!tab.groupId.isEmpty())
            result.insert(tab.groupId);
    }
    return result;
}

void WorkspaceManager::pruneNewlyEmptyGroups(const QSet<QString> &previouslyNonEmpty)
{
    const QSet<QString> remaining = nonEmptyGroupIds();
    const qsizetype previousSize = m_groups.size();
    m_groups.erase(std::remove_if(m_groups.begin(), m_groups.end(),
        [&previouslyNonEmpty, &remaining](const Group &group)
        {
            return previouslyNonEmpty.contains(group.id) && !remaining.contains(group.id);
        }), m_groups.end());
    if (m_groups.size() != previousSize)
        emit groupsChanged();
}

QJsonObject WorkspaceManager::tabObject(const Tab &tab, const bool includeContent) const
{
    QJsonObject object {
        {QStringLiteral("id"), tab.id},
        {QStringLiteral("name"), tab.name},
        {QStringLiteral("fontFamily"), tab.fontFamily},
        {QStringLiteral("fontStyle"), tab.fontStyle},
        {QStringLiteral("fontPointSize"), tab.fontPointSize},
        {QStringLiteral("bold"), tab.bold},
        {QStringLiteral("italic"), tab.italic},
        {QStringLiteral("fontColor"), tab.fontColor},
        {QStringLiteral("pinned"), tab.pinned},
        {QStringLiteral("groupId"), tab.groupId},
        {QStringLiteral("appearance"), QJsonObject::fromVariantMap(tab.appearance)},
        {QStringLiteral("createdAt"), isoDate(tab.createdAt)},
        {QStringLiteral("updatedAt"), isoDate(tab.updatedAt)}
    };
    if (includeContent)
        object.insert(QStringLiteral("content"), tab.content);
    return object;
}

QJsonObject WorkspaceManager::workspaceObject(const bool exportMetadata) const
{
    QJsonArray tabs;
    for (const Tab &tab : m_tabs)
        tabs.append(tabObject(tab, exportMetadata));
    QJsonArray groups;
    for (const Group &group : m_groups)
    {
        groups.append(QJsonObject {
            {QStringLiteral("id"), group.id},
            {QStringLiteral("name"), group.name},
            {QStringLiteral("color"), group.color},
            {QStringLiteral("collapsed"), group.collapsed},
            {QStringLiteral("appearance"), QJsonObject::fromVariantMap(group.appearance)}
        });
    }
    QJsonObject object {
        {QStringLiteral("type"), QStringLiteral("qbt-material-workspace")},
        {QStringLiteral("schemaVersion"), SchemaVersion},
        {QStringLiteral("appDisplayName"), m_appDisplayName},
        {QStringLiteral("activeTabId"), activeTabId()},
        {QStringLiteral("groups"), groups},
        {QStringLiteral("globalAppearance"), QJsonObject::fromVariantMap(m_globalAppearance)},
        {QStringLiteral("appearancePresets"), QJsonArray::fromVariantList(m_appearancePresets)},
        {QStringLiteral("tabs"), tabs}
    };
    if (exportMetadata)
        object.insert(QStringLiteral("exportedAt"), isoDate(QDateTime::currentDateTimeUtc()));
    return object;
}

bool WorkspaceManager::parseWorkspace(const QByteArray &bytes, Snapshot *snapshot,
    QString *error, const bool requireContent) const
{
    if (!snapshot || bytes.size() > MaximumWorkspaceBytes)
    {
        if (error) *error = tr("Workspace data exceeds the 32 MB limit.");
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
    if (!document.isObject())
    {
        if (error) *error = tr("Workspace JSON is invalid: %1").arg(parseError.errorString());
        return false;
    }
    const QJsonObject root = document.object();
    const int schemaVersion = root.value(QStringLiteral("schemaVersion")).toInt(-1);
    if (root.value(QStringLiteral("type")).toString() != QStringLiteral("qbt-material-workspace")
        || schemaVersion < MinimumSchemaVersion || schemaVersion > SchemaVersion)
    {
        if (error) *error = tr("This is not a supported qBittorrent Material workspace.");
        return false;
    }
    if (!root.contains(QStringLiteral("tabs"))
        || !root.value(QStringLiteral("tabs")).isArray())
    {
        if (error) *error = tr("Workspace JSON is missing its tab list.");
        return false;
    }
    const QJsonArray entries = root.value(QStringLiteral("tabs")).toArray();
    if (entries.size() > MaximumTabs)
    {
        if (error) *error = tr("Workspace contains too many tabs.");
        return false;
    }

    Snapshot candidate;
    candidate.appDisplayName = normalizedName(root.value(QStringLiteral("appDisplayName")).toString(),
        80, QString::fromLatin1(ProductDisplayName));
    candidate.activeTabId = root.value(QStringLiteral("activeTabId")).toString();
    QSet<QString> groupIds;
    if (schemaVersion >= 2)
    {
        const QJsonValue groupsValue = root.value(QStringLiteral("groups"));
        if (!groupsValue.isUndefined() && !groupsValue.isArray())
        {
            if (error) *error = tr("Workspace contains a malformed group list.");
            return false;
        }
        const QJsonArray groupEntries = groupsValue.toArray();
        if (groupEntries.size() > MaximumGroups)
        {
            if (error) *error = tr("Workspace contains too many tab groups.");
            return false;
        }
        for (const QJsonValue &groupValue : groupEntries)
        {
            if (!groupValue.isObject())
            {
                if (error) *error = tr("Workspace contains a malformed tab group.");
                return false;
            }
            const QJsonObject object = groupValue.toObject();
            const QUuid parsedId(object.value(QStringLiteral("id")).toString());
            const QColor color(object.value(QStringLiteral("color")).toString());
            if (parsedId.isNull() || !color.isValid())
            {
                if (error) *error = tr("Workspace contains an invalid tab group.");
                return false;
            }
            Group group;
            group.id = parsedId.toString(QUuid::WithoutBraces);
            if (groupIds.contains(group.id))
            {
                if (error) *error = tr("Workspace contains duplicate tab groups.");
                return false;
            }
            groupIds.insert(group.id);
            group.name = normalizedName(object.value(QStringLiteral("name")).toString(),
                80, tr("Untitled group"));
            group.color = color.name(QColor::HexArgb).toUpper();
            group.collapsed = object.value(QStringLiteral("collapsed")).toBool();
            if (object.value(QStringLiteral("appearance")).isObject())
                group.appearance = normalizedAppearance(object.value(
                    QStringLiteral("appearance")).toObject().toVariantMap());
            candidate.groups.push_back(std::move(group));
        }
        if (root.value(QStringLiteral("globalAppearance")).isObject())
            candidate.globalAppearance = normalizedAppearance(root.value(
                QStringLiteral("globalAppearance")).toObject().toVariantMap());
        if (root.value(QStringLiteral("appearancePresets")).isArray())
        {
            const QJsonArray presets = root.value(QStringLiteral("appearancePresets")).toArray();
            for (qsizetype i = 0; i < presets.size() && i < 32; ++i)
            {
                const QJsonObject preset = presets.at(i).toObject();
                if (!preset.value(QStringLiteral("appearance")).isObject())
                    continue;
                candidate.appearancePresets.push_back(QVariantMap {
                    {QStringLiteral("name"), normalizedName(preset.value(
                        QStringLiteral("name")).toString(), 80, tr("Appearance preset"))},
                    {QStringLiteral("appearance"), normalizedAppearance(preset.value(
                        QStringLiteral("appearance")).toObject().toVariantMap())}
                });
            }
        }
    }
    QSet<QString> ids;
    for (const QJsonValue &value : entries)
    {
        if (!value.isObject())
        {
            if (error) *error = tr("Workspace contains a malformed tab record.");
            return false;
        }
        const QJsonObject object = value.toObject();
        const QUuid parsedId(object.value(QStringLiteral("id")).toString());
        if (parsedId.isNull())
        {
            if (error) *error = tr("Workspace contains an invalid tab identifier.");
            return false;
        }
        Tab tab;
        tab.id = parsedId.toString(QUuid::WithoutBraces);
        if (ids.contains(tab.id))
        {
            if (error) *error = tr("Workspace contains duplicate tab identifiers.");
            return false;
        }
        ids.insert(tab.id);
        tab.name = normalizedName(object.value(QStringLiteral("name")).toString(), 120, tr("Untitled tab"));
        if (requireContent && (!object.contains(QStringLiteral("content"))
            || !object.value(QStringLiteral("content")).isString()))
        {
            if (error) *error = tr("This file contains repository metadata, not a portable workspace snapshot.");
            return false;
        }
        tab.content = object.value(QStringLiteral("content")).toString();
        if (tab.content.size() > MaximumContentCharacters)
        {
            if (error) *error = tr("A tab exceeds the 4 MB content limit.");
            return false;
        }
        tab.fontFamily = normalizedName(object.value(QStringLiteral("fontFamily")).toString(), 128,
            QFontDatabase::systemFont(QFontDatabase::GeneralFont).family());
        tab.fontStyle = normalizedName(object.value(QStringLiteral("fontStyle")).toString(), 64,
            QStringLiteral("Regular"));
        tab.fontPointSize = object.value(QStringLiteral("fontPointSize")).toDouble(16.0);
        if (tab.fontPointSize < 6.0 || tab.fontPointSize > 144.0)
        {
            if (error) *error = tr("A tab has an invalid font size.");
            return false;
        }
        const QColor color(object.value(QStringLiteral("fontColor")).toString());
        if (!color.isValid())
        {
            if (error) *error = tr("A tab has an invalid font color.");
            return false;
        }
        tab.fontColor = color.name(QColor::HexArgb).toUpper();
        tab.bold = object.value(QStringLiteral("bold")).toBool();
        tab.italic = object.value(QStringLiteral("italic")).toBool();
        tab.pinned = object.value(QStringLiteral("pinned")).toBool();
        tab.groupId = object.value(QStringLiteral("groupId")).toString();
        if (!tab.groupId.isEmpty() && !groupIds.contains(tab.groupId))
            tab.groupId.clear();
        if (object.value(QStringLiteral("appearance")).isObject())
            tab.appearance = normalizedAppearance(object.value(
                QStringLiteral("appearance")).toObject().toVariantMap());
        tab.createdAt = QDateTime::fromString(object.value(QStringLiteral("createdAt")).toString(), Qt::ISODate);
        tab.updatedAt = QDateTime::fromString(object.value(QStringLiteral("updatedAt")).toString(), Qt::ISODate);
        if (!tab.createdAt.isValid()) tab.createdAt = QDateTime::currentDateTimeUtc();
        if (!tab.updatedAt.isValid()) tab.updatedAt = tab.createdAt;
        candidate.tabs.push_back(std::move(tab));
    }
    std::stable_partition(candidate.tabs.begin(), candidate.tabs.end(),
        [](const Tab &tab) { return tab.pinned; });
    if (!candidate.tabs.isEmpty() && !ids.contains(candidate.activeTabId))
        candidate.activeTabId = candidate.tabs.constFirst().id;
    if (candidate.tabs.isEmpty())
        candidate.activeTabId.clear();
    *snapshot = std::move(candidate);
    return true;
}

bool WorkspaceManager::loadSnapshotFromRoot(const QString &root, Snapshot *snapshot,
    QString *error, QSet<QString> *trackedExtras) const
{
    const QString workspacePath = QDir(root).filePath(QStringLiteral("workspace.json"));
    const QFileInfo workspaceInfo(workspacePath);
    if (!workspaceInfo.isFile() || workspaceInfo.size() > MaximumWorkspaceBytes
        || containsReparsePoint(workspacePath, root))
    {
        if (error) *error = tr("Repository workspace.json is missing or unsafe.");
        return false;
    }
    QFile workspaceFile(workspacePath);
    if (!workspaceFile.open(QIODevice::ReadOnly))
    {
        if (error) *error = workspaceFile.errorString();
        return false;
    }
    if (!parseWorkspace(workspaceFile.readAll(), snapshot, error))
        return false;

    for (Tab &tab : snapshot->tabs)
    {
        const QString contentPath = QDir(root).filePath(QStringLiteral("tabs/%1.md").arg(tab.id));
        const QFileInfo contentInfo(contentPath);
        if (!contentInfo.isFile() || contentInfo.size() > MaximumContentCharacters * 4LL
            || containsReparsePoint(contentPath, root))
        {
            if (error) *error = tr("Repository tab content is missing or unsafe.");
            return false;
        }
        QFile contentFile(contentPath);
        if (!contentFile.open(QIODevice::ReadOnly))
        {
            if (error) *error = contentFile.errorString();
            return false;
        }
        tab.content = QString::fromUtf8(contentFile.readAll());
        if (tab.content.size() > MaximumContentCharacters)
        {
            if (error) *error = tr("Repository tab content exceeds the 4 MB limit.");
            return false;
        }
    }

    QSet<QString> trackedFiles;
    if (QFileInfo::exists(QDir(root).filePath(QStringLiteral(".git"))))
    {
        git_repository *repository = nullptr;
        git_index *indexHandle = nullptr;
        const QByteArray encodedRoot = QDir::fromNativeSeparators(root).toUtf8();
        if (git_repository_open_ext(&repository, encodedRoot.constData(),
                GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr) != 0
            || git_repository_index(&indexHandle, repository) != 0)
        {
            if (error) *error = tr("Could not inspect the workspace Git index during recovery.");
            git_index_free(indexHandle);
            git_repository_free(repository);
            return false;
        }
        const size_t entryCount = git_index_entrycount(indexHandle);
        for (size_t i = 0; i < entryCount; ++i)
        {
            const git_index_entry *entry = git_index_get_byindex(indexHandle, i);
            if (!entry || !entry->path)
                continue;
            const QString relativePath = QString::fromUtf8(entry->path);
            if (relativePath.startsWith(QStringLiteral("tabs/")))
                trackedFiles.insert(QFileInfo(relativePath).fileName());
        }
        git_index_free(indexHandle);
        git_repository_free(repository);
    }

    // A process can stop after a new page body is atomically replaced but
    // before workspace.json is replaced. Adopt those valid UUID-named bodies
    // as recovered tabs. An extra body already tracked by Git represents the
    // opposite crash window: workspace.json recorded an intentional close but
    // the body was not removed yet. Keep that file in the managed cleanup set
    // without resurrecting the closed tab.
    QSet<QString> manifestIds;
    for (const Tab &tab : std::as_const(snapshot->tabs))
        manifestIds.insert(tab.id);
    const QFileInfoList tabEntries = QDir(QDir(root).filePath(QStringLiteral("tabs"))).entryInfoList(
        QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden | QDir::System,
        QDir::Name);
    for (const QFileInfo &entry : tabEntries)
    {
        const QUuid parsedId(entry.completeBaseName());
        const QString canonicalId = parsedId.toString(QUuid::WithoutBraces);
        if (!entry.isFile() || hasSymlinkIdentity(entry)
            || entry.suffix() != QStringLiteral("md") || parsedId.isNull()
            || entry.completeBaseName() != canonicalId
            || entry.size() > MaximumContentCharacters * 4LL)
        {
            if (error) *error = tr("Repository tabs contain an unexpected or unsafe path.");
            return false;
        }
        if (manifestIds.contains(canonicalId))
            continue;
        if (trackedFiles.contains(entry.fileName()))
        {
            if (trackedExtras)
                trackedExtras->insert(entry.fileName());
            continue;
        }
        if (snapshot->tabs.size() >= MaximumTabs)
        {
            if (error) *error = tr("Workspace contains too many tabs after crash recovery.");
            return false;
        }

        QFile recoveredFile(entry.absoluteFilePath());
        if (!recoveredFile.open(QIODevice::ReadOnly))
        {
            if (error) *error = recoveredFile.errorString();
            return false;
        }
        Tab recovered;
        recovered.id = canonicalId;
        recovered.name = tr("Recovered tab %1").arg(canonicalId.left(8));
        recovered.content = QString::fromUtf8(recoveredFile.readAll());
        if (recovered.content.size() > MaximumContentCharacters)
        {
            if (error) *error = tr("A recovered tab exceeds the 4 MB content limit.");
            return false;
        }
        recovered.fontFamily = QFontDatabase::systemFont(QFontDatabase::GeneralFont).family();
        const QStringList styles = QFontDatabase::styles(recovered.fontFamily);
        recovered.fontStyle = styles.contains(QStringLiteral("Regular"))
            ? QStringLiteral("Regular") : styles.value(0, QStringLiteral("Regular"));
        recovered.createdAt = recovered.updatedAt = entry.lastModified().toUTC();
        if (!recovered.createdAt.isValid())
            recovered.createdAt = recovered.updatedAt = QDateTime::currentDateTimeUtc();
        snapshot->tabs.push_back(std::move(recovered));
        manifestIds.insert(canonicalId);
    }
    if (snapshot->activeTabId.isEmpty() && !snapshot->tabs.isEmpty())
        snapshot->activeTabId = snapshot->tabs.constFirst().id;
    return true;
}

void WorkspaceManager::applySnapshot(Snapshot snapshot)
{
    m_loading = true;
    beginResetModel();
    m_tabs = std::move(snapshot.tabs);
    m_groups = std::move(snapshot.groups);
    m_globalAppearance = std::move(snapshot.globalAppearance);
    m_appearancePresets = std::move(snapshot.appearancePresets);
    normalizePinnedOrder();
    m_appDisplayName = normalizedName(snapshot.appDisplayName, 80,
        QString::fromLatin1(ProductDisplayName));
    m_activeIndex = indexOfTab(snapshot.activeTabId);
    if (m_activeIndex < 0 && !m_tabs.isEmpty())
        m_activeIndex = 0;
    endResetModel();
    QGuiApplication::setApplicationDisplayName(m_appDisplayName);
    emit countChanged();
    emit activeIndexChanged();
    emit appDisplayNameChanged();
    emit tabsChanged();
    emit groupsChanged();
    emit appearanceChanged();
    m_loading = false;
}

void WorkspaceManager::loadWorkspace()
{
    const QFileInfo configuredRoot(m_repositoryPath);
    const QString parentPath = configuredRoot.absolutePath();
    QDir parentDirectory(parentPath);

    // If the process stopped after moving the current repository aside during
    // an import, restore the newest verified backup before reading any state.
    if (!configuredRoot.exists() && parentDirectory.exists())
    {
        const QStringList backups = parentDirectory.entryList(
            {QStringLiteral(".workspace-backup-*")}, QDir::Dirs | QDir::Hidden, QDir::Time);
        for (const QString &backupName : backups)
        {
            QString recoveryError;
            const QString backupPath = parentDirectory.filePath(backupName);
            if (validateRepositoryRoot(backupPath, &recoveryError)
                && parentDirectory.rename(backupName, configuredRoot.fileName()))
            {
                qCWarning(lcUi) << "Restored workspace after interrupted repository import from"
                                << backupPath;
                break;
            }
        }
    }

    Snapshot snapshot;
    QString error;
    const QString workspacePath = QDir(m_repositoryPath).filePath(QStringLiteral("workspace.json"));
    const QString gitPath = QDir(m_repositoryPath).filePath(QStringLiteral(".git"));
    if (QFileInfo::exists(workspacePath))
    {
        bool validExistingState = validateManagedWorkingTree(m_repositoryPath, &error, false);
        if (validExistingState && QFileInfo::exists(gitPath))
            validExistingState = validateRepositoryRoot(m_repositoryPath, &error, true);
        QSet<QString> trackedExtras;
        if (validExistingState
            && loadSnapshotFromRoot(m_repositoryPath, &snapshot, &error, &trackedExtras))
        {
            applySnapshot(std::move(snapshot));
            m_managedTabFiles.clear();
            for (const Tab &tab : std::as_const(m_tabs))
                m_managedTabFiles.insert(tab.id + QStringLiteral(".md"));
            m_managedTabFiles.unite(trackedExtras);
            return;
        }
    }
    if (!error.isEmpty())
        qCWarning(lcUi) << "Ignoring invalid workspace state:" << error;

    // Existing but invalid data must never be overwritten by the Welcome tab.
    // Move the complete directory aside first so every file and Git object is
    // recoverable. If that cannot be done, keep the invalid data untouched and
    // expose an in-memory Welcome page only.
    const QFileInfo currentRoot(m_repositoryPath);
    const bool hasExistingData = currentRoot.isFile()
        || (currentRoot.isDir() && !QDir(m_repositoryPath).entryList(
            QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden | QDir::System).isEmpty());
    if (hasExistingData)
    {
        const QString recoveryName = QStringLiteral(".workspace-recovery-%1-%2")
            .arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-HHmmss-zzz")),
                QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
        if (parentDirectory.rename(currentRoot.fileName(), recoveryName))
        {
            m_recoveryPath = parentDirectory.filePath(recoveryName);
            qCWarning(lcUi) << "Preserved invalid workspace at" << m_recoveryPath;
        }
        else
        {
            m_initializationBlocked = true;
            emit writableChanged();
            m_repositoryStatus = tr("Existing workspace needs recovery; its files were left untouched");
            qCWarning(lcUi) << "Could not preserve invalid workspace; automatic initialization blocked";
        }
    }

    // An explicit workspace root is an isolated/portable workspace. Do not
    // import the normal user's QSettings display-name override into it (capture
    // profiles and portable workspaces must start from canonical product state).
    const bool isolatedWorkspace = !qEnvironmentVariable("QBT_WORKSPACE_ROOT").trimmed().isEmpty();
    QSettings settings;
    snapshot.appDisplayName = isolatedWorkspace
        ? QString::fromLatin1(ProductDisplayName)
        : normalizedName(
            settings.value(QStringLiteral("Workspace/AppDisplayName"), QString::fromLatin1(ProductDisplayName)).toString(),
            80, QString::fromLatin1(ProductDisplayName));
    Tab welcome;
    welcome.id = newTabId();
    welcome.name = tr("Welcome");
    welcome.content = tr("Your persistent workspace is ready.\n\n"
        "Create tabs like a browser, write on each page, and right-click a tab to customize its name, font, style, and color.");
    welcome.fontFamily = QFontDatabase::systemFont(QFontDatabase::GeneralFont).family();
    const QStringList styles = QFontDatabase::styles(welcome.fontFamily);
    welcome.fontStyle = styles.contains(QStringLiteral("Regular"))
        ? QStringLiteral("Regular") : styles.value(0, QStringLiteral("Regular"));
    welcome.createdAt = welcome.updatedAt = QDateTime::currentDateTimeUtc();
    snapshot.tabs.push_back(welcome);
    snapshot.activeTabId = welcome.id;
    applySnapshot(std::move(snapshot));
    m_managedTabFiles.clear();
}

void WorkspaceManager::scheduleSave(const QString &commitMessage)
{
    if (m_loading || !writable())
        return;
    m_pendingCommitMessage = commitMessage;
    setDirty(true);
    m_repositoryStatus = tr("Changes pending…");
    emit repositoryStatusChanged();
    m_saveTimer.start();
}

bool WorkspaceManager::saveNow(const QString &commitMessage, QString *error)
{
    m_saveTimer.stop();
    if (m_initializationBlocked)
    {
        if (error) *error = tr("The existing workspace could not be recovered automatically; its files remain untouched.");
        return false;
    }
    if (!writeManagedFiles(error))
        return false;
    setDirty(true);
    if (!ensureRepository(error))
    {
        m_repositoryStatus = tr("Files saved; local Git unavailable");
        emit repositoryStatusChanged();
        return false;
    }
    if (!commitRepository(commitMessage, error))
    {
        m_repositoryStatus = tr("Files saved; Git commit failed");
        emit repositoryStatusChanged();
        return false;
    }
    setDirty(false);
    updateRepositoryStatus();

    // Portable/explicit roots carry this metadata in workspace.json and must
    // not rewrite the normal user's global QSettings profile.
    if (qEnvironmentVariable("QBT_WORKSPACE_ROOT").trimmed().isEmpty())
    {
        QSettings settings;
        settings.setValue(QStringLiteral("Workspace/AppDisplayName"), m_appDisplayName);
        settings.setValue(QStringLiteral("Workspace/ActiveTabId"), activeTabId());
        settings.sync();
    }
    return true;
}

bool WorkspaceManager::writeManagedFiles(QString *error)
{
    const QFileInfo rootInfo(m_repositoryPath);
    if (rootInfo.exists() && (!rootInfo.isDir() || hasSymlinkIdentity(rootInfo)))
    {
        if (error) *error = tr("The managed workspace path is not a safe local directory.");
        return false;
    }
    QDir root(m_repositoryPath);
    if (!root.mkpath(QStringLiteral("tabs")))
    {
        if (error) *error = tr("Could not create the managed workspace folder.");
        return false;
    }
    const QFileInfo tabsInfo(root.filePath(QStringLiteral("tabs")));
    if (!tabsInfo.isDir() || hasSymlinkIdentity(tabsInfo))
    {
        if (error) *error = tr("The managed tabs path is not a safe local directory.");
        return false;
    }

    QSet<QString> expectedFiles;
    for (const Tab &tab : m_tabs)
    {
        const QString fileName = tab.id + QStringLiteral(".md");
        expectedFiles.insert(fileName);
        const QString contentPath = root.filePath(QStringLiteral("tabs/%1").arg(fileName));
        const QByteArray contentBytes = tab.content.toUtf8();
        const QFileInfo existingInfo(contentPath);
        if (existingInfo.exists() && !m_managedTabFiles.contains(fileName))
        {
            QFile existingFile(contentPath);
            if (!existingFile.open(QIODevice::ReadOnly) || existingFile.readAll() != contentBytes)
            {
                if (error) *error = tr("An untracked page already uses tab identifier %1; its file was left untouched.")
                    .arg(tab.id);
                return false;
            }
        }
        if (!writeFileAtomically(contentPath, contentBytes, error))
            return false;
    }
    if (!writeFileAtomically(root.filePath(QStringLiteral("workspace.json")),
        QJsonDocument(workspaceObject(false)).toJson(QJsonDocument::Indented), error))
        return false;

    const QByteArray readme = QStringLiteral(
        "# %1 workspace\n\n"
        "This is a complete local Git repository managed by qBittorrent Material.\n\n"
        "- `workspace.json` stores the app display name, pinned and ordinary tab order, groups, and sparse appearance overrides.\n"
        "- `tabs/*.md` stores one plain-text page per browser-style tab.\n"
        "- `.git` stores the automatic local history.\n\n"
        "Use the app's Workspace menu to export/import JSON snapshots or the entire repository.\n")
        .arg(m_appDisplayName).toUtf8();
    if (!writeFileAtomically(root.filePath(QStringLiteral("README.md")), readme, error))
        return false;

    QDir tabsDirectory(root.filePath(QStringLiteral("tabs")));
    const QSet<QString> intentionallyRemovedFiles = m_managedTabFiles - expectedFiles;
    for (const QString &fileName : intentionallyRemovedFiles)
    {
        const QString path = tabsDirectory.filePath(fileName);
        const QFileInfo info(path);
        if (!info.exists())
            continue;
        if (!info.isFile() || containsReparsePoint(path, m_repositoryPath) || !QFile::remove(path))
        {
            if (error) *error = tr("Could not remove a closed tab from the repository.");
            return false;
        }
    }
    m_managedTabFiles = expectedFiles;
    return true;
}

bool WorkspaceManager::ensureRepository(QString *error)
{
    git_repository *repository = nullptr;
    const QByteArray path = QDir::fromNativeSeparators(m_repositoryPath).toUtf8();
    const QFileInfo gitDirectory(QDir(m_repositoryPath).filePath(QStringLiteral(".git")));
    int result = git_repository_open_ext(&repository, path.constData(),
        GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr);
    if (result == 0 && repository)
    {
        git_repository_free(repository);
        return validateRepositoryRoot(m_repositoryPath, error, true);
    }
    if (result != 0)
    {
        if (gitDirectory.exists())
        {
            if (error) *error = tr("The existing local Git repository is invalid: %1")
                .arg(gitErrorText(tr("unknown libgit2 error")));
            git_repository_free(repository);
            return false;
        }
        git_repository_init_options options = GIT_REPOSITORY_INIT_OPTIONS_INIT;
        options.flags = GIT_REPOSITORY_INIT_MKPATH;
        options.initial_head = "main";
        result = git_repository_init_ext(&repository, path.constData(), &options);
    }
    if (result != 0 || !repository)
    {
        if (error) *error = tr("Could not initialize local Git: %1")
            .arg(gitErrorText(tr("unknown libgit2 error")));
        git_repository_free(repository);
        return false;
    }
    git_repository_free(repository);
    return true;
}

bool WorkspaceManager::commitRepository(const QString &message, QString *error)
{
    git_repository *repository = nullptr;
    git_index *indexHandle = nullptr;
    git_tree *tree = nullptr;
    git_commit *parentCommit = nullptr;
    git_tree *parentTree = nullptr;
    git_signature *signature = nullptr;
    const QByteArray path = QDir::fromNativeSeparators(m_repositoryPath).toUtf8();

    auto fail = [&](const QString &prefix)
    {
        if (error) *error = prefix + QStringLiteral(": ") + gitErrorText(tr("unknown libgit2 error"));
    };

    if (git_repository_open_ext(&repository, path.constData(),
            GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr) != 0
        || git_repository_index(&indexHandle, repository) != 0)
    {
        fail(tr("Could not open the workspace Git index"));
        git_index_free(indexHandle);
        git_repository_free(repository);
        return false;
    }

    char tabsPath[] = "tabs/*";
    char *pathStrings[] = {tabsPath};
    git_strarray pathspec {pathStrings, 1};
    bool staged = git_index_update_all(indexHandle, &pathspec, nullptr, nullptr) == 0
        && git_index_add_bypath(indexHandle, "workspace.json") == 0
        && git_index_add_bypath(indexHandle, "README.md") == 0;
    for (const Tab &tab : std::as_const(m_tabs))
    {
        const QByteArray tabPath = QStringLiteral("tabs/%1.md").arg(tab.id).toUtf8();
        if (git_index_add_bypath(indexHandle, tabPath.constData()) != 0)
        {
            staged = false;
            break;
        }
    }
    if (!staged || git_index_write(indexHandle) != 0)
    {
        fail(tr("Could not stage workspace files"));
        git_index_free(indexHandle);
        git_repository_free(repository);
        return false;
    }

    git_oid treeId;
    if (git_index_write_tree(&treeId, indexHandle) != 0
        || git_tree_lookup(&tree, repository, &treeId) != 0)
    {
        fail(tr("Could not create the workspace Git tree"));
        git_index_free(indexHandle);
        git_repository_free(repository);
        return false;
    }

    git_oid parentId;
    bool hasParent = false;
    if (git_reference_name_to_id(&parentId, repository, "HEAD") == 0
        && git_commit_lookup(&parentCommit, repository, &parentId) == 0)
    {
        hasParent = true;
        if (git_commit_tree(&parentTree, parentCommit) == 0
            && git_oid_equal(git_tree_id(parentTree), &treeId))
        {
            git_tree_free(parentTree);
            git_commit_free(parentCommit);
            git_tree_free(tree);
            git_index_free(indexHandle);
            git_repository_free(repository);
            return true;
        }
    }

    if (git_signature_now(&signature, "qBittorrent Material Workspace", "workspace@local.invalid") != 0)
    {
        fail(tr("Could not create the workspace Git signature"));
        git_tree_free(parentTree);
        git_commit_free(parentCommit);
        git_tree_free(tree);
        git_index_free(indexHandle);
        git_repository_free(repository);
        return false;
    }

    git_oid commitId;
    const QByteArray commitMessage = message.toUtf8();
    const git_commit *parents[] = {parentCommit};
    const int result = git_commit_create(&commitId, repository, "HEAD", signature, signature,
        "UTF-8", commitMessage.constData(), tree, hasParent ? 1 : 0, hasParent ? parents : nullptr);
    if (result != 0)
        fail(tr("Could not commit the workspace"));

    git_signature_free(signature);
    git_tree_free(parentTree);
    git_commit_free(parentCommit);
    git_tree_free(tree);
    git_index_free(indexHandle);
    git_repository_free(repository);
    return result == 0;
}

void WorkspaceManager::updateRepositoryStatus()
{
    git_repository *repository = nullptr;
    git_reference *head = nullptr;
    const QByteArray path = QDir::fromNativeSeparators(m_repositoryPath).toUtf8();
    if (git_repository_open_ext(&repository, path.constData(),
            GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr) == 0
        && git_repository_head(&head, repository) == 0)
    {
        if (const git_oid *target = git_reference_target(head))
        {
            char id[GIT_OID_HEXSZ + 1] {};
            git_oid_tostr(id, sizeof(id), target);
            m_lastCommitId = QString::fromLatin1(id).left(8);
            m_repositoryStatus = tr("Synced to local Git • %1").arg(m_lastCommitId);
        }
    }
    if (m_repositoryStatus.isEmpty())
        m_repositoryStatus = tr("Local Git repository ready");
    git_reference_free(head);
    git_repository_free(repository);
    emit repositoryStatusChanged();
}

void WorkspaceManager::setDirty(const bool dirty)
{
    if (m_dirty == dirty)
        return;
    m_dirty = dirty;
    emit dirtyChanged();
}

bool WorkspaceManager::writeFileAtomically(const QString &path, const QByteArray &bytes,
    QString *error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
    {
        if (error) *error = file.errorString();
        return false;
    }
    if (file.write(bytes) != bytes.size() || !file.commit())
    {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

bool WorkspaceManager::copyTree(const QString &source, const QString &destination,
    qint64 *bytesCopied, QString *error)
{
    int entryCount = 0;
    std::function<bool(const QString &, const QString &, int)> copyEntry;
    copyEntry = [&](const QString &entrySource, const QString &entryDestination, const int depth)
    {
        if (depth > 64 || ++entryCount > 20000)
        {
            if (error) *error = QObject::tr("Repository has too many files or nested folders.");
            return false;
        }
        const QFileInfo sourceInfo(entrySource);
        if (!sourceInfo.exists() || hasSymlinkIdentity(sourceInfo))
        {
            if (error) *error = QObject::tr("Repository contains a symlink, junction, or missing path.");
            return false;
        }
        if (sourceInfo.isFile())
        {
            if (bytesCopied)
            {
                *bytesCopied += sourceInfo.size();
                if (*bytesCopied > MaximumRepositoryBytes)
                {
                    if (error) *error = QObject::tr("Repository exceeds the 256 MB safety limit.");
                    return false;
                }
            }
            if (!QDir().mkpath(QFileInfo(entryDestination).absolutePath())
                || !QFile::copy(entrySource, entryDestination))
            {
                if (error) *error = QObject::tr("Could not copy repository file: %1")
                    .arg(sourceInfo.fileName());
                return false;
            }
            return true;
        }
        if (!sourceInfo.isDir() || !QDir().mkpath(entryDestination))
        {
            if (error) *error = QObject::tr("Could not create repository export folder.");
            return false;
        }
        const QFileInfoList entries = QDir(entrySource).entryInfoList(
            QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden | QDir::System);
        for (const QFileInfo &entry : entries)
        {
            if (!copyEntry(entry.absoluteFilePath(),
                QDir(entryDestination).filePath(entry.fileName()), depth + 1))
                return false;
        }
        return true;
    };
    return copyEntry(source, destination, 0);
}

bool WorkspaceManager::removeTree(const QString &path, QString *error)
{
    if (!QFileInfo::exists(path))
        return true;
    QDir directory(path);
    if (!directory.removeRecursively())
    {
        if (error) *error = QObject::tr("Could not remove temporary workspace folder.");
        return false;
    }
    return true;
}

bool WorkspaceManager::validateManagedWorkingTree(const QString &path, QString *error,
    const bool requireRepositoryFiles)
{
    const QFileInfo root(path);
    const QFileInfo gitDirectory(QDir(path).filePath(QStringLiteral(".git")));
    const QFileInfo workspaceFile(QDir(path).filePath(QStringLiteral("workspace.json")));
    const QFileInfo readmeFile(QDir(path).filePath(QStringLiteral("README.md")));
    const QFileInfo tabsDirectory(QDir(path).filePath(QStringLiteral("tabs")));
    if (!root.isDir() || hasSymlinkIdentity(root)
        || !workspaceFile.isFile() || hasSymlinkIdentity(workspaceFile)
        || !tabsDirectory.isDir() || hasSymlinkIdentity(tabsDirectory)
        || (readmeFile.exists() && (!readmeFile.isFile() || hasSymlinkIdentity(readmeFile)))
        || (gitDirectory.exists() && (!gitDirectory.isDir() || hasSymlinkIdentity(gitDirectory)))
        || (requireRepositoryFiles && (!readmeFile.isFile() || !gitDirectory.isDir())))
    {
        if (error) *error = QObject::tr("Selected folder is not a safe workspace working tree.");
        return false;
    }

    const QSet<QString> allowedTopLevel {
        QStringLiteral(".git"), QStringLiteral("README.md"),
        QStringLiteral("tabs"), QStringLiteral("workspace.json")
    };
    const QFileInfoList topLevelEntries = QDir(path).entryInfoList(
        QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden | QDir::System);
    for (const QFileInfo &entry : topLevelEntries)
    {
        if (!allowedTopLevel.contains(entry.fileName()) || hasSymlinkIdentity(entry))
        {
            if (error) *error = QObject::tr("Repository contains an unexpected or redirected working-tree path.");
            return false;
        }
    }

    const QFileInfoList tabEntries = QDir(tabsDirectory.absoluteFilePath()).entryInfoList(
        QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden | QDir::System);
    for (const QFileInfo &entry : tabEntries)
    {
        const QUuid id(entry.completeBaseName());
        const QString canonicalId = id.toString(QUuid::WithoutBraces);
        if (!entry.isFile() || hasSymlinkIdentity(entry)
            || entry.suffix() != QStringLiteral("md") || id.isNull()
            || entry.completeBaseName() != canonicalId
            || entry.size() > MaximumContentCharacters * 4LL)
        {
            if (error) *error = QObject::tr("Repository tabs contain an unexpected or unsafe path.");
            return false;
        }
    }
    return true;
}

bool WorkspaceManager::validateRepositoryRoot(const QString &path, QString *error,
    const bool allowUnbornMain)
{
    const QFileInfo gitDirectory(QDir(path).filePath(QStringLiteral(".git")));
    if (!validateManagedWorkingTree(path, error, true))
        return false;
    if (QFileInfo::exists(QDir(gitDirectory.absoluteFilePath()).filePath(QStringLiteral("commondir")))
        || QFileInfo::exists(QDir(gitDirectory.absoluteFilePath()).filePath(
            QStringLiteral("objects/info/alternates"))))
    {
        if (error) *error = QObject::tr("Linked worktrees and external Git object stores are not supported.");
        return false;
    }

    git_repository *repository = nullptr;
    git_reference *head = nullptr;
    git_commit *headCommit = nullptr;
    const QByteArray encoded = QDir::fromNativeSeparators(path).toUtf8();
    bool valid = git_repository_open_ext(&repository, encoded.constData(),
            GIT_REPOSITORY_OPEN_NO_SEARCH, nullptr) == 0
        && !git_repository_is_bare(repository);
    bool validHead = false;
    if (valid && !git_repository_head_detached(repository)
        && git_repository_head(&head, repository) == 0
        && QString::fromUtf8(git_reference_name(head)) == QStringLiteral("refs/heads/main"))
    {
        const git_oid *target = git_reference_target(head);
        validHead = target && git_commit_lookup(&headCommit, repository, target) == 0;
    }
    else if (valid && allowUnbornMain && git_repository_head_unborn(repository) == 1)
    {
        git_reference *symbolicHead = nullptr;
        validHead = git_reference_lookup(&symbolicHead, repository, "HEAD") == 0
            && git_reference_type(symbolicHead) == GIT_REFERENCE_SYMBOLIC
            && QString::fromUtf8(git_reference_symbolic_target(symbolicHead))
                == QStringLiteral("refs/heads/main");
        git_reference_free(symbolicHead);
    }
    valid = valid && validHead;
    if (valid)
    {
        const QString expectedWorkdir = QFileInfo(path).canonicalFilePath();
        const QString actualWorkdir = QFileInfo(
            QString::fromUtf8(git_repository_workdir(repository))).canonicalFilePath();
        const QString expectedGitdir = gitDirectory.canonicalFilePath();
        const QString actualGitdir = QFileInfo(
            QString::fromUtf8(git_repository_path(repository))).canonicalFilePath();
#ifdef Q_OS_WIN
        constexpr auto pathCaseSensitivity = Qt::CaseInsensitive;
#else
        constexpr auto pathCaseSensitivity = Qt::CaseSensitive;
#endif
        valid = !expectedWorkdir.isEmpty() && !actualWorkdir.isEmpty()
            && !expectedGitdir.isEmpty() && !actualGitdir.isEmpty()
            && expectedWorkdir.compare(actualWorkdir, pathCaseSensitivity) == 0
            && expectedGitdir.compare(actualGitdir, pathCaseSensitivity) == 0;
    }
    if (!valid && error)
        *error = QObject::tr("Selected repository is not a self-contained checked-out main-branch workspace.");
    git_commit_free(headCommit);
    git_reference_free(head);
    git_repository_free(repository);
    return valid;
}
