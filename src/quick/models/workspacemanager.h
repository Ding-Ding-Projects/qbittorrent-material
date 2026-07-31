/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFont>
#include <QHash>
#include <QJsonObject>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QVector>

class WorkspaceManager : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString appDisplayName READ appDisplayName WRITE setAppDisplayName
        NOTIFY appDisplayNameChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int pinnedCount READ pinnedCount NOTIFY tabsChanged)
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(QString activeTabId READ activeTabId NOTIFY activeIndexChanged)
    Q_PROPERTY(QVariantList tabItems READ tabItems NOTIFY tabsChanged)
    Q_PROPERTY(QVariantList groups READ groups NOTIFY groupsChanged)
    Q_PROPERTY(QVariantMap globalAppearance READ globalAppearance NOTIFY appearanceChanged)
    Q_PROPERTY(QVariantList appearancePresets READ appearancePresets NOTIFY appearanceChanged)
    Q_PROPERTY(QString repositoryPath READ repositoryPath CONSTANT)
    Q_PROPERTY(QUrl repositoryUrl READ repositoryUrl CONSTANT)
    Q_PROPERTY(QString repositoryStatus READ repositoryStatus NOTIFY repositoryStatusChanged)
    Q_PROPERTY(QString lastCommitId READ lastCommitId NOTIFY repositoryStatusChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged)
    Q_PROPERTY(bool writable READ writable NOTIFY writableChanged)

public:
    enum Roles
    {
        TabIdRole = Qt::UserRole + 1,
        NameRole,
        ContentRole,
        FontFamilyRole,
        FontStyleRole,
        FontPointSizeRole,
        BoldRole,
        ItalicRole,
        FontColorRole,
        PinnedRole,
        GroupIdRole,
        GroupNameRole,
        GroupColorRole,
        GroupCollapsedRole,
        AppearanceRole,
        CreatedAtRole,
        UpdatedAtRole
    };

    static WorkspaceManager *create(QQmlEngine *, QJSEngine *)
    {
        return new WorkspaceManager;
    }

    explicit WorkspaceManager(QObject *parent = nullptr);
    ~WorkspaceManager() override;

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QString appDisplayName() const;
    void setAppDisplayName(const QString &name);
    [[nodiscard]] int count() const;
    [[nodiscard]] int pinnedCount() const;
    [[nodiscard]] int activeIndex() const;
    void setActiveIndex(int index);
    [[nodiscard]] QString activeTabId() const;
    [[nodiscard]] QString repositoryPath() const;
    [[nodiscard]] QUrl repositoryUrl() const;
    [[nodiscard]] QString repositoryStatus() const;
    [[nodiscard]] QString lastCommitId() const;
    [[nodiscard]] bool dirty() const;
    [[nodiscard]] bool writable() const;
    [[nodiscard]] QVariantList tabItems() const;
    [[nodiscard]] QVariantList groups() const;
    [[nodiscard]] QVariantMap globalAppearance() const;
    [[nodiscard]] QVariantList appearancePresets() const;

    Q_INVOKABLE QVariantMap tabAt(int index) const;
    Q_INVOKABLE QVariantMap tabById(const QString &tabId) const;
    Q_INVOKABLE QString createTab(const QString &name);
    Q_INVOKABLE int duplicateTab(int index);
    Q_INVOKABLE bool closeTab(int index);
    Q_INVOKABLE bool closeOtherTabs(int index);
    Q_INVOKABLE bool moveTab(int from, int to);
    Q_INVOKABLE bool setTabPinned(int index, bool pinned);
    Q_INVOKABLE bool assignTabToGroup(int index, const QString &groupId);
    Q_INVOKABLE QString createGroup(const QString &name, const QString &color = {});
    Q_INVOKABLE bool updateGroup(const QString &groupId, const QString &name,
        const QString &color);
    Q_INVOKABLE bool setGroupCollapsed(const QString &groupId, bool collapsed);
    Q_INVOKABLE bool moveGroup(int from, int to);
    Q_INVOKABLE bool removeGroup(const QString &groupId);
    Q_INVOKABLE QVariantMap groupById(const QString &groupId) const;
    Q_INVOKABLE bool setTabContent(const QString &tabId, const QString &content);
    Q_INVOKABLE bool updateTab(const QString &tabId, const QString &name,
        const QString &fontFamily, const QString &fontStyle, double fontPointSize,
        bool bold, bool italic, const QString &fontColor);
    Q_INVOKABLE bool updateTabAppearance(const QString &tabId,
        const QVariantMap &appearance);
    Q_INVOKABLE bool updateGroupAppearance(const QString &groupId,
        const QVariantMap &appearance);
    Q_INVOKABLE bool updateGlobalAppearance(const QVariantMap &appearance);
    Q_INVOKABLE bool resetTabAppearance(const QString &tabId,
        const QString &propertyName = {});
    Q_INVOKABLE bool resetGroupAppearance(const QString &groupId,
        const QString &propertyName = {});
    Q_INVOKABLE bool resetGlobalAppearance(const QString &propertyName = {});
    Q_INVOKABLE bool saveAppearancePreset(const QString &name,
        const QVariantMap &appearance);
    Q_INVOKABLE bool removeAppearancePreset(const QString &name);
    Q_INVOKABLE bool exportAppearancePreset(const QString &name, const QUrl &destination);
    Q_INVOKABLE bool importAppearancePreset(const QUrl &source);

    Q_INVOKABLE QVariantMap validatePattern(const QString &pattern,
        const QString &flags = {}) const;
    Q_INVOKABLE QVariantMap evaluateRegularExpression(const QString &pattern,
        const QString &flags, const QString &sampleText) const;
    Q_INVOKABLE QVariantMap searchTabs(const QString &query, bool regex,
        const QString &flags = {}, const QString &groupId = {}) const;
    Q_INVOKABLE QVariantMap searchGroups(const QString &query, bool regex,
        const QString &flags = {}) const;
    Q_INVOKABLE QVariantMap previewCloseTabs(const QString &query, bool regex,
        const QString &flags, bool inverse, bool includePinned,
        const QString &groupId = {}) const;
    Q_INVOKABLE bool closeTabsByText(const QString &query, bool regex,
        const QString &flags, bool inverse, bool includePinned,
        const QString &groupId = {});

    Q_INVOKABLE QStringList fontFamilies() const;
    Q_INVOKABLE QStringList fontStyles(const QString &family) const;
    Q_INVOKABLE QFont resolvedFont(const QString &family, const QString &style,
        double pointSize, bool bold, bool italic) const;
    Q_INVOKABLE QUrl suggestedExportUrl(const QString &fileName) const;
    Q_INVOKABLE bool openRepository() const;
    Q_INVOKABLE bool syncNow();
    Q_INVOKABLE bool exportWorkspace(const QUrl &destination);
    Q_INVOKABLE bool importWorkspace(const QUrl &source);
    Q_INVOKABLE bool exportRepository(const QUrl &destinationFolder);
    Q_INVOKABLE bool importRepository(const QUrl &sourceFolder);

signals:
    void appDisplayNameChanged();
    void countChanged();
    void activeIndexChanged();
    void repositoryStatusChanged();
    void dirtyChanged();
    void writableChanged();
    void tabsChanged();
    void groupsChanged();
    void appearanceChanged();
    void operationFinished(bool success, const QString &message, const QUrl &location);

private:
    struct Tab
    {
        QString id;
        QString name;
        QString content;
        QString fontFamily;
        QString fontStyle;
        double fontPointSize = 16.0;
        bool bold = false;
        bool italic = false;
        QString fontColor = QStringLiteral("#FF6750A4");
        bool pinned = false;
        QString groupId;
        QVariantMap appearance;
        QDateTime createdAt;
        QDateTime updatedAt;
    };

    struct Group
    {
        QString id;
        QString name;
        QString color = QStringLiteral("#FF6750A4");
        bool collapsed = false;
        QVariantMap appearance;
    };

    struct Snapshot
    {
        QString appDisplayName;
        QString activeTabId;
        QVector<Tab> tabs;
        QVector<Group> groups;
        QVariantMap globalAppearance;
        QVariantList appearancePresets;
    };

    [[nodiscard]] static QString localPath(const QUrl &url);
    [[nodiscard]] static QString normalizedName(const QString &value, int maximum,
        const QString &fallback);
    [[nodiscard]] static QString normalizedColor(const QString &value);
    [[nodiscard]] static QString newTabId();
    [[nodiscard]] static QString fileSafeName(const QString &value);
    [[nodiscard]] static bool isInsidePath(const QString &candidate, const QString &root);
    [[nodiscard]] static bool containsReparsePoint(const QString &path, const QString &root);

    [[nodiscard]] QVariantMap tabMap(const Tab &tab) const;
    [[nodiscard]] QVariantMap groupMap(const Group &group) const;
    [[nodiscard]] int indexOfTab(const QString &tabId) const;
    [[nodiscard]] int indexOfGroup(const QString &groupId) const;
    [[nodiscard]] QString groupName(const QString &groupId) const;
    [[nodiscard]] QString groupColor(const QString &groupId) const;
    [[nodiscard]] bool groupCollapsed(const QString &groupId) const;
    [[nodiscard]] static QVariantMap normalizedAppearance(const QVariantMap &appearance);
    [[nodiscard]] static QRegularExpression regularExpression(const QString &pattern,
        const QString &flags, QString *error = nullptr);
    [[nodiscard]] QVariantMap queryTabs(const QString &query, bool regex,
        const QString &flags, const QString &groupId, bool inverse,
        bool includePinned, bool closingPreview) const;
    void normalizePinnedOrder();
    [[nodiscard]] QSet<QString> nonEmptyGroupIds() const;
    void pruneNewlyEmptyGroups(const QSet<QString> &previouslyNonEmpty);
    [[nodiscard]] QJsonObject tabObject(const Tab &tab, bool includeContent) const;
    [[nodiscard]] QJsonObject workspaceObject(bool exportMetadata) const;
    [[nodiscard]] bool parseWorkspace(const QByteArray &bytes, Snapshot *snapshot,
        QString *error, bool requireContent = false) const;
    [[nodiscard]] bool loadSnapshotFromRoot(const QString &root, Snapshot *snapshot,
        QString *error, QSet<QString> *trackedExtras = nullptr) const;
    void applySnapshot(Snapshot snapshot);
    void loadWorkspace();

    void scheduleSave(const QString &commitMessage);
    [[nodiscard]] bool requireWritable();
    [[nodiscard]] bool saveNow(const QString &commitMessage, QString *error = nullptr);
    [[nodiscard]] bool writeManagedFiles(QString *error);
    [[nodiscard]] bool ensureRepository(QString *error);
    [[nodiscard]] bool commitRepository(const QString &message, QString *error);
    void updateRepositoryStatus();
    void setDirty(bool dirty);

    [[nodiscard]] static bool writeFileAtomically(const QString &path,
        const QByteArray &bytes, QString *error);
    [[nodiscard]] static bool copyTree(const QString &source, const QString &destination,
        qint64 *bytesCopied, QString *error);
    [[nodiscard]] static bool removeTree(const QString &path, QString *error);
    [[nodiscard]] static bool validateManagedWorkingTree(const QString &path,
        QString *error, bool requireRepositoryFiles);
    [[nodiscard]] static bool validateRepositoryRoot(const QString &path, QString *error,
        bool allowUnbornMain = false);

    QVector<Tab> m_tabs;
    QVector<Group> m_groups;
    QVariantMap m_globalAppearance;
    QVariantList m_appearancePresets;
    QString m_appDisplayName;
    QString m_repositoryPath;
    QString m_repositoryStatus;
    QString m_lastCommitId;
    QString m_pendingCommitMessage;
    QString m_recoveryPath;
    QSet<QString> m_managedTabFiles;
    int m_activeIndex = -1;
    bool m_dirty = false;
    bool m_loading = false;
    bool m_initializationBlocked = false;
    QTimer m_saveTimer;
};
