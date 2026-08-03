/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    Main workspace host. The old top TabBar has been replaced by the supplied
    design system's persistent 248 px grouped navigation. Workspace loaders and
    their controller lifetimes stay exactly as before.
*/
Item {
    id: central

    required property var shell
    property int transfersCount: 0
    property bool searchEnabled: false
    property bool rssEnabled: false
    property bool logEnabled: false
    property int currentIndex: 0

    readonly property int rssUnread:
        (typeof RSSController !== "undefined" && RSSController.unreadCount) || 0

    onSearchEnabledChanged: normalizeCurrent()
    onRssEnabledChanged: normalizeCurrent()
    onLogEnabledChanged: normalizeCurrent()

    function normalizeCurrent() {
        if ((currentIndex === 1 && !searchEnabled)
                || (currentIndex === 2 && !rssEnabled)
                || (currentIndex === 3 && !logEnabled)) {
            currentIndex = 0
        }
    }

    function activateTab(index) {
        if (index < 0 || index > 4)
            return
        Log.debug("ui", "Workspace destination -> " + index)
        central.currentIndex = index
    }

    function requestDestination(index) {
        if (index >= 1 && index <= 3)
            central.shell.switchToTab(index)
        else
            central.activateTab(index)
    }

    // Header owns the transfers filter field now; expose a hook the shell drives.
    signal focusFilterRequested()
    function toggleFilterFocus() {
        if (currentIndex === 0)
            central.focusFilterRequested()
    }

    /*! Selects every transfer the active filter shows. */
    function selectAllTransfers() {
        if (currentIndex === 0)
            transfersPage.selectAllVisible()
    }

    /*! Selects exactly the visible transfers that are not selected. */
    function invertTransferSelection() {
        if (currentIndex === 0)
            transfersPage.invertSelection()
    }

    function workspaceItem() {
        central.currentIndex = 4
        return workspaceLoader.item
    }

    function openSearchPlugins() {
        // Enabling the loader and selecting the page are deliberately kept in
        // one synchronous path. This also makes the menu action work when
        // Search has not been enabled in Preferences yet.
        if (!searchEnabled)
            central.shell.setSearchTabEnabled(true)
        central.currentIndex = 1
        if (searchLoader.item && searchLoader.item.openPluginsDialog)
            searchLoader.item.openPluginsDialog()
    }

    function newWorkspaceTab() {
        var item = workspaceItem()
        if (item) item.createTab()
    }

    function closeWorkspaceTab() {
        var item = workspaceItem()
        if (item) item.closeCurrentTab()
    }

    function customizeWorkspaceTab() {
        var item = workspaceItem()
        if (item) item.customizeCurrentTab()
    }

    function renameWorkspaceApplication() {
        var item = workspaceItem()
        if (item) item.renameApplication()
    }

    function importWorkspace() {
        var item = workspaceItem()
        if (item) item.importWorkspace()
    }

    function exportWorkspace() {
        var item = workspaceItem()
        if (item) item.exportWorkspace()
    }

    function importWorkspaceRepository() {
        var item = workspaceItem()
        if (item) item.importGitRepository()
    }

    function exportWorkspaceRepository() {
        var item = workspaceItem()
        if (item) item.exportGitRepository()
    }

    function openWorkspaceRepository() {
        var item = workspaceItem()
        if (item) item.openGitRepository()
    }

    function syncWorkspace() {
        var item = workspaceItem()
        if (item) item.syncWorkspace()
    }

    // The shared filter proxy — created here so the header search pill, the
    // A/C status chips, and the B sidebar all drive the same model.
    TorrentFilterProxyModel {
        id: sharedProxy
        sourceModel: TransferListModel
    }
    readonly property var proxy: sharedProxy

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Tonal Rail (A) / Card Flow (C): a left navigation rail. Split Dock (B)
        // puts navigation in the header segments instead (design directions).
        NavRail {
            visible: !Theme.isSplitDock
            Layout.fillHeight: true
            navModel: central.navModel
            currentTab: central.currentIndex
            onNavRequested: (index) => central.requestDestination(index)
            onAddRequested: central.shell.addTorrentFile()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.color("background")

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: central.currentIndex

                // 0 — Transfers (redesigned, per UI style).
                TransfersPage {
                    id: transfersPage
                    shell: central.shell
                    filterProxy: sharedProxy
                    onDeleteRequested: central.shell.removeSelected()
                }

                Loader {
                    id: searchLoader
                    active: central.searchEnabled
                    sourceComponent: SearchTab {}
                    onLoaded: Log.debug("ui", "Search workspace instantiated")
                }

                Loader {
                    id: rssLoader
                    active: central.rssEnabled
                    sourceComponent: RSSTab {}
                    onLoaded: Log.debug("ui", "RSS workspace instantiated")
                }

                Loader {
                    id: logLoader
                    active: central.logEnabled
                    sourceComponent: ExecutionLogTab {}
                    onLoaded: Log.debug("ui", "Execution log workspace instantiated")
                }

                Loader {
                    id: workspaceLoader
                    active: true
                    sourceComponent: WorkspaceView {}
                    onLoaded: Log.debug("ui", "Personal workspace instantiated")
                }
            }
        }
    }

    // Navigation model shared by the rails (A/C) and the header segments (B).
    readonly property var navModel: [
        { label: qsTr("Transfers"), icon: "download", page: 0, badge: 0 },
        { label: qsTr("Search"), icon: "travel_explore", page: 1, badge: 0 },
        { label: qsTr("RSS"), icon: "rss_feed", page: 2, badge: central.rssUnread },
        { label: qsTr("Log"), icon: "article", page: 3, badge: 0 },
        { label: qsTr("Notes"), icon: "edit_note", page: 4, badge: 0 }
    ]

    Component.onCompleted: Log.debug("ui", "Design-system workspace shell ready")
}
