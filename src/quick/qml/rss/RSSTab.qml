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

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore
import qBittorrent

/*!
    \qmltype RSSTab
    \brief The RSS reader tab: a warning banner, toolbar and a three-pane split
           (Feeds tree | Articles list | Article preview).

    Owns the RSS bridge models (\c RSSFeedTreeModel and \c RSSArticleModel) and
    coordinates the panes: selecting a feed repopulates the article list;
    navigating between articles marks the previous one read (mirroring the
    Widgets client) and renders the current one in the preview.
*/
Item {
    id: root

    RSSFeedTreeModel { id: feedModel }
    RSSArticleModel { id: articleModel }

    // Whether the current feed selection is a sticky "Unread" node.
    readonly property bool unreadView: feedsTree.currentStickyKind === 2
    // Whether the current selection is a sticky (All/Unread) node.
    readonly property bool stickyView: feedsTree.currentStickyKind !== 0

    Component.onCompleted: Log.debug("rss", "RSSTab opened")

    function _selectFeed(path, stickyKind) {
        Log.info("rss", "Feed selected: '" + path + "' stickyKind=" + stickyKind)
        articleModel.setFeed(path, stickyKind === 2)
        articlePreview.article = ({})
        articlesList.currentRow = -1
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color("background")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.pagePadding
        spacing: Spacing.lg

        // ---- Page heading -------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Spacing.xs

            Label {
                Layout.fillWidth: true
                text: qsTr("RSS reader")
                font: Typography.pageTitle
                color: Theme.color("onBackground")
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Monitor feeds and route matching releases through download rules.")
                font: Typography.metadata
                color: Theme.color("muted")
                wrapMode: Text.WordWrap
            }
        }

        // ---- Warning banner (fetching disabled) ---------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: !RSSController.processingEnabled
            implicitHeight: visible ? warnLabel.implicitHeight + (Spacing.md * 2) : 0
            color: Qt.alpha(Theme.color("warning"), Theme.isDark ? 0.20 : 0.12)
            border.width: Spacing.outlineWidth
            border.color: Qt.alpha(Theme.color("warning"), 0.55)
            radius: Spacing.radiusControl

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Spacing.motionBase
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Spacing.easeStandard
                }
            }

            Label {
                id: warnLabel
                anchors.fill: parent
                anchors.margins: Spacing.md
                text: qsTr("Fetching of RSS feeds is disabled now! You can enable it in application settings.")
                color: Theme.color("warning")
                font: Qt.font({
                    family: Typography.bodyMedium.family,
                    pixelSize: Typography.bodyMedium.pixelSize,
                    weight: Typography.bodyMedium.weight,
                    letterSpacing: Typography.bodyMedium.letterSpacing,
                    italic: true
                })
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ---- Dominant RSS workspace surface -------------------------------
        Rectangle {
            id: rssPanel
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.color("surface")
            border.width: Spacing.outlineWidth
            border.color: Theme.color("outline")
            radius: Spacing.radiusPanel
            clip: true

            Behavior on color {
                ColorAnimation {
                    duration: Spacing.motionFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Spacing.easeStandard
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Spacing.outlineWidth
                spacing: 0

                // ---- Toolbar ----------------------------------------------
                RSSToolbar {
                    id: toolbar
                    Layout.fillWidth: true
                    Layout.preferredHeight: Spacing.controlHeight
                    Layout.minimumHeight: Spacing.controlHeight
                    Layout.maximumHeight: Spacing.controlHeight
                    selectedPath: feedsTree.currentPath
                    background: Rectangle {
                        color: Theme.color("surfaceWarm")
                    }
                    onNewSubscription: feedDialog.openForAdd(RSSController.newSubscriptionDestination(feedsTree.currentPath))
                    onMarkItemsRead: RSSController.markItemRead(feedsTree.currentPath)
                    onUpdateAll: RSSController.refreshAll()
                    onOpenDownloader: rulesDialog.open()
                    onFilterChanged: (text) => articleModel.setFilter(text)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Spacing.outlineWidth
                    color: Theme.color("outlineVariant")
                }

                // ---- Three-pane split -------------------------------------
                SplitView {
                    id: sideSplit
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Spacing.lg
                    orientation: Qt.Horizontal

                    Settings {
                        id: sidePersist
                        category: "RSSWidget/SideSplit"
                        property alias feedsWidth: feedsPane.implicitWidth
                    }

                    // Feeds tree pane.
                    Item {
                        id: feedsPane
                        SplitView.preferredWidth: 220
                        SplitView.minimumWidth: 150

                        FeedsTree {
                            id: feedsTree
                            anchors.fill: parent
                            model: feedModel
                            onSelectionChanged: root._selectFeed(currentPath, currentStickyKind)
                            onActivated: (path) => {
                                // Double-click a feed → rename (legacy behavior).
                                if (RSSController.isFeed(path))
                                    renameDialog.openFor(path)
                            }
                            onContextRequested: (pos) => {
                                feedsMenu.updateState()
                                feedsMenu.popup(feedsTree, pos)
                            }
                        }
                    }

                    // Articles + preview pane.
                    ColumnLayout {
                        SplitView.fillWidth: true
                        spacing: Spacing.sm

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: Spacing.sm
                            Layout.rightMargin: Spacing.sm
                            text: qsTr("Torrents: (double-click to download)")
                            font: Typography.labelMedium
                            color: Theme.color("onSurfaceVariant")
                        }

                        SplitView {
                            id: mainSplit
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            orientation: Qt.Horizontal

                            Settings {
                                category: "RSSWidget/MainSplit"
                                property alias articlesWidth: articlesPane.implicitWidth
                            }

                            Item {
                                id: articlesPane
                                SplitView.preferredWidth: 290
                                SplitView.minimumWidth: 180

                                ArticlesList {
                                    id: articlesList
                                    anchors.fill: parent
                                    model: articleModel
                                    stickyView: root.stickyView
                                    onCurrentArticleChanged: (row) => {
                                        articlePreview.showFeed = root.stickyView
                                        articlePreview.article = row >= 0 ? articleModel.get(row) : ({})
                                    }
                                    onArticleActivated: (row) => {
                                        const a = articleModel.get(row)
                                        articleModel.markRead(row)
                                        RSSController.downloadTorrent(a.torrentUrl)
                                    }
                                    onContextRequested: (pos) => {
                                        const a = articleModel.get(articlesList.currentRow)
                                        articlesMenu.hasTorrent = a.torrentUrl && a.torrentUrl.length > 0
                                        articlesMenu.hasLink = a.link && a.link.length > 0
                                        if (articlesMenu.hasTorrent || articlesMenu.hasLink)
                                            articlesMenu.popup(articlesList, pos)
                                    }
                                }
                            }

                            ArticlePreview {
                                id: articlePreview
                                SplitView.fillWidth: true
                                SplitView.minimumWidth: 180
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Context menus ----------------------------------------------------

    FeedsContextMenu {
        id: feedsMenu

        function updateState() {
            const path = feedsTree.currentPath
            currentPath = path
            isSticky = feedsTree.currentStickyKind !== 0
            isFeed = !isSticky && RSSController.isFeed(path)
            isFolder = !isSticky && RSSController.isFolder(path)
            hasSelection = feedsTree.currentStickyKind !== 0 || path.length > 0 || RSSController.isFolder(path)
        }

        onRequestUpdate: RSSController.refreshItem(feedsTree.currentPath)
        onRequestMarkRead: RSSController.markItemRead(feedsTree.currentPath)
        onRequestRename: renameDialog.openFor(feedsTree.currentPath)
        onRequestEditFeed: feedDialog.openForEdit(feedsTree.currentPath)
        onRequestDelete: deleteFeedConfirm.open()
        onRequestNewFolder: newFolderDialog.open()
        onRequestNewSubscription: feedDialog.openForAdd(RSSController.newSubscriptionDestination(feedsTree.currentPath))
        onRequestCopyUrl: RSSController.copyToClipboard(RSSController.feedURLsUnder(feedsTree.currentPath).join("\n"))
        onRequestUpdateAll: RSSController.refreshAll()
    }

    ArticlesContextMenu {
        id: articlesMenu
        onRequestDownload: {
            const a = articleModel.get(articlesList.currentRow)
            articleModel.markRead(articlesList.currentRow)
            RSSController.downloadTorrent(a.torrentUrl)
        }
        onRequestOpenUrl: {
            const a = articleModel.get(articlesList.currentRow)
            articleModel.markRead(articlesList.currentRow)
            RSSController.openArticleLink(a.link)
        }
    }

    // ---- Dialogs ----------------------------------------------------------

    RSSFeedDialog {
        id: feedDialog
        onSubmitted: (url, intervalSeconds, editMode, path) => {
            let err = editMode
                ? RSSController.setFeedURL(path, url, intervalSeconds)
                : RSSController.addFeed(url, feedDialog.destFolder)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    TextInputDialog {
        id: renameDialog
        property string path: ""
        title: qsTr("Rename")
        label: qsTr("New feed name:")
        function openFor(p) {
            path = p
            text = RSSController.itemName(p)
            open()
        }
        onAccepted: (newName) => {
            const err = RSSController.renameItem(path, newName)
            if (err && err.length > 0)
                NotificationCenter.notify(qsTr("Rename failed") + ": " + err, "error")
        }
    }

    TextInputDialog {
        id: newFolderDialog
        title: qsTr("New folder")
        label: qsTr("Folder name:")
        text: qsTr("New folder")
        onAccepted: (name) => {
            const dest = RSSController.newSubscriptionDestination(feedsTree.currentPath)
            const err = RSSController.addFolder(name, dest)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    ConfirmDialog {
        id: deleteFeedConfirm
        title: qsTr("Deletion confirmation")
        text: qsTr("Are you sure you want to delete the selected RSS feeds?")
        destructive: true
        onAccepted: {
            const err = RSSController.removeItem(feedsTree.currentPath)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    // ---- Automated Download Rules dialog ----------------------------------

    AutomatedDownloadRulesDialog {
        id: rulesDialog
    }

    Connections {
        target: RSSController
        function onErrorOccurred(message) { NotificationCenter.notify(message, "error") }
        function onArticleUrlBlocked(link) {
            NotificationCenter.notify(qsTr("Blocked opening a local-file article URL."), "warning")
        }
    }
}
