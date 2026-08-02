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
import qBittorrent

/*!
    \qmltype SearchTab
    \brief The top-level "Search" central tab: query bar, category / plugin-scope
           combos, a Search/Stop button, a per-query TabBar of results tabs, and
           the "Search plugins…" launcher.

    The empty state (no plugins installed) swaps the whole content area for
    \l SearchNoPluginsPage. All engine interaction goes through the
    \c SearchController singleton.
*/
Item {
    id: root

    // The tab id whose results are currently shown (-1 = none).
    property int currentTabId: -1
    // The query string that produced the current tab (to detect edits).
    property string currentTabPattern: ""
    // Currently selected plugin-scope token.
    property string currentScope: "enabled"

    readonly property bool currentOngoing:
        currentTabId >= 0 && SearchController.tabStatus(currentTabId) === SearchController.Ongoing
    // Show "Stop" only while the current tab runs AND the query is unchanged.
    readonly property bool showStop:
        currentOngoing && (searchField.text.trim() === currentTabPattern)

    function _refillCategories() {
        var items = SearchController.categoriesForScope(root.currentScope)
        categoryCombo.model = items
        categoryCombo.currentIndex = 0
    }

    function _doSearch() {
        var pattern = searchField.text.trim()
        if (pattern.length === 0) {
            Log.warning("search", "Search clicked with empty pattern")
            NotificationCenter.notify(qsTr("Please type a search pattern first"), "warning")
            return
        }
        Log.info("search", "Search clicked: '" + pattern + "' scope=" + root.currentScope +
                 " category=" + categoryCombo.currentValue)
        var id = SearchController.startSearch(pattern, categoryCombo.currentValue, root.currentScope)
        if (id >= 0) {
            root.currentTabId = id
            root.currentTabPattern = pattern
        }
    }

    function openPluginsDialog() {
        Log.info("search", "Search plugins dialog opened from application menu")
        pluginsDialog.open()
    }

    Component.onCompleted: {
        Log.debug("search", "SearchTab opened")
        _refillCategories()
    }

    Connections {
        target: SearchController
        function onTabsChanged() {
            // If the current tab was closed, fall back to the last tab.
            var tabs = SearchController.tabs
            var stillThere = false
            for (var i = 0; i < tabs.length; ++i)
                if (tabs[i].id === root.currentTabId) { stillThere = true; break }
            if (!stillThere)
                root.currentTabId = tabs.length > 0 ? tabs[tabs.length - 1].id : -1
        }
        function onPluginsChanged() {
            Log.debug("search", "Plugins changed; refilling scope/category combos")
            root._refillCategories()
        }
        function onSearchFinished(tabId, failed) {
            Log.info("search", "Search finished tab=" + tabId + " failed=" + failed)
        }
        function onPluginSelectionRequested() {
            pluginsDialog.open()
        }
        function onNotify(message) {
            NotificationCenter.notify(message, "info")
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color("background")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.pagePadding
        spacing: Spacing.lg

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.lg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.xs

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Search")
                    font: Typography.pageTitle
                    color: Theme.color("onSurface")
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Find releases through installed search plugins.")
                    font: Typography.metadata
                    color: Theme.color("muted")
                    wrapMode: Text.WordWrap
                }
            }

            Button {
                Layout.preferredHeight: Spacing.controlHeight
                flat: true
                text: qsTr("Search plugins…")
                contentItem: RowLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.extension; size: 18; color: Theme.color("primary") }
                    Label { text: qsTr("Search plugins…"); font: Typography.labelLarge; color: Theme.color("primary") }
                }
                onClicked: {
                    Log.info("search", "Search plugins dialog opened")
                    pluginsDialog.open()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Spacing.radiusPanel
            color: Theme.color("surface")
            border.width: Spacing.outlineWidth
            border.color: Theme.color("outline")
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Spacing.space20
                spacing: Spacing.md

        // ---- Query bar ----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.sm

            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: Spacing.controlHeight
                enabled: SearchController.pluginsInstalled && SearchController.pythonAvailable
                placeholderText: qsTr("Search…")
                selectByMouse: true
                ToolTip.text: qsTr("A file name to search for. Multiple words act as AND; wrap an exact phrase in double quotes.")
                ToolTip.visible: hovered && text.length === 0
                ToolTip.delay: 800
                onAccepted: root._doSearch()
                onTextEdited: Log.trace("search", "Query edited")

                IconButton {
                    symbol: Icons.arrow_drop_down
                    size: 18
                    visible: SearchController.history.length > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    tooltip: qsTr("Search history")
                    onClicked: historyMenu.open()
                }

                Menu {
                    id: historyMenu
                    y: searchField.height
                    Material.elevation: Spacing.elevationMenu
                    Repeater {
                        model: SearchController.history
                        delegate: MenuItem {
                            required property string modelData
                            text: modelData
                            onTriggered: {
                                Log.debug("search", "History picked: " + modelData)
                                searchField.text = modelData
                            }
                        }
                    }
                    MenuSeparator { visible: SearchController.history.length > 0 }
                    MenuItem {
                        text: qsTr("Clear history")
                        enabled: SearchController.history.length > 0
                        onTriggered: {
                            Log.info("search", "Clear history")
                            SearchController.clearHistory()
                        }
                    }
                }
            }

            ComboBox {
                id: categoryCombo
                Layout.preferredWidth: root.width >= 1120 ? 220 : 160
                Layout.preferredHeight: Spacing.controlHeight
                enabled: searchField.enabled
                textRole: "label"
                valueRole: "value"
                onActivated: Log.debug("search", "Category -> " + currentValue)
            }

            ComboBox {
                id: scopeCombo
                Layout.preferredWidth: root.width >= 1120 ? 220 : 160
                Layout.preferredHeight: Spacing.controlHeight
                enabled: searchField.enabled
                textRole: "label"
                valueRole: "value"
                model: SearchController.pluginScopes
                Component.onCompleted: currentIndex = 0
                onActivated: {
                    var value = currentValue
                    Log.debug("search", "Plugin scope -> " + value)
                    if (value === "multi") {
                        // "Select…" opens the plugins dialog and reverts the box.
                        currentIndex = 0
                        pluginsDialog.open()
                        return
                    }
                    root.currentScope = value
                    root._refillCategories()
                }
            }

            Button {
                id: searchButton
                Layout.preferredHeight: Spacing.controlHeight
                visible: !root.showStop
                enabled: searchField.enabled
                highlighted: true
                text: qsTr("Search")
                icon.source: ""
                contentItem: RowLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.search; size: 18; color: Theme.color("onPrimary") }
                    Label { text: searchButton.text; font: Typography.labelLarge; color: Theme.color("onPrimary") }
                }
                onClicked: root._doSearch()
            }

            Button {
                id: stopButton
                Layout.preferredHeight: Spacing.controlHeight
                visible: root.showStop
                text: qsTr("Stop")
                Material.accent: Theme.color("error")
                highlighted: true
                onClicked: {
                    Log.info("search", "Stop clicked for tab " + root.currentTabId)
                    SearchController.stopSearch(root.currentTabId)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Spacing.outlineWidth
            color: Theme.color("outlineVariant")
        }

        // ---- Content: empty page OR results tabs --------------------------
        Loader {
            id: contentLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // A blocked runtime wins over installed plugins: they cannot run.
            sourceComponent: (SearchController.pluginsInstalled
                    && (SearchController.unavailableReason.length === 0))
                ? resultsComponent : emptyComponent
        }

            }
        }
    }

    // ---- Empty page --------------------------------------------------------
    Component {
        id: emptyComponent
        SearchNoPluginsPage {
            onInstallRequested: pluginsDialog.open()
        }
    }

    // ---- Results tabs ------------------------------------------------------
    Component {
        id: resultsComponent
        ColumnLayout {
            spacing: 0

            TabBar {
                id: resultsBar
                Layout.fillWidth: true
                Layout.preferredHeight: Spacing.controlHeight
                visible: SearchController.tabs.length > 0
                Material.elevation: 0
                background: Rectangle {
                    radius: Spacing.radiusControl
                    color: Theme.color("surfaceWarm")
                }
                currentIndex: {
                    var tabs = SearchController.tabs
                    for (var i = 0; i < tabs.length; ++i)
                        if (tabs[i].id === root.currentTabId) return i
                    return 0
                }

                Repeater {
                    model: SearchController.tabs
                    delegate: TabButton {
                        id: resultTabButton
                        required property var modelData
                        required property int index
                        width: Math.min(220, implicitWidth)
                        implicitHeight: Spacing.controlHeight
                        onClicked: {
                            root.currentTabId = modelData.id
                            root.currentTabPattern = SearchController.tabPattern(modelData.id)
                            Log.debug("search", "Tab selected: " + modelData.id)
                        }

                        ToolTip.text: SearchController.statusText(modelData.status)
                        ToolTip.visible: hovered
                        ToolTip.delay: 600

                        background: Rectangle {
                            radius: Spacing.radiusControl
                            color: resultTabButton.checked
                                ? Theme.color("primaryContainer")
                                : (resultTabButton.hovered ? Theme.color("surface") : "transparent")

                            Behavior on color {
                                ColorAnimation { duration: Spacing.motionFast }
                            }
                        }

                        contentItem: RowLayout {
                            spacing: Spacing.xs
                            MDIcon {
                                icon: Icons.forId(SearchController.statusIcon(modelData.status))
                                size: 16
                                color: modelData.status === SearchController.Error
                                       ? Theme.color("error") : Theme.color("onSurfaceVariant")
                            }
                            Label {
                                text: modelData.pattern
                                font: Typography.titleSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            IconButton {
                                symbol: Icons.close
                                size: 14
                                tooltip: qsTr("Close tab")
                                onClicked: SearchController.closeTab(modelData.id)
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                tabMenu.tabId = modelData.id
                                tabMenu.ongoing = modelData.status === SearchController.Ongoing
                                tabMenu.popup()
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: SearchController.closeTab(modelData.id)
                        }
                        // Double-click copies the pattern back into the input.
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onDoubleTapped: {
                                searchField.text = modelData.pattern
                                Log.debug("search", "Tab double-clicked; pattern copied to input")
                            }
                        }
                    }
                }
            }

            StackLayout {
                id: resultsStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: resultsBar.currentIndex

                Repeater {
                    model: SearchController.tabs
                    delegate: SearchResultsTab {
                        required property var modelData
                        tabId: modelData.id
                        proxyModel: SearchController.resultsModel(modelData.id)
                    }
                }
            }
        }
    }

    SearchTabContextMenu {
        id: tabMenu
    }

    SearchPluginsDialog {
        id: pluginsDialog
    }
}
