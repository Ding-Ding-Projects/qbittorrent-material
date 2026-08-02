/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs as Dialogs
import qBittorrent

Item {
    id: root
    objectName: "workspaceView"
    Accessible.name: qsTr("Custom workspace")
    property string revealedTabId: ""

    function createTab() {
        WorkspaceManager.createTab(qsTr("New tab"))
    }

    function closeCurrentTab() {
        if (WorkspaceManager.activeIndex >= 0)
            WorkspaceManager.closeTab(WorkspaceManager.activeIndex)
    }

    function customizeCurrentTab() {
        if (WorkspaceManager.activeIndex >= 0)
            tabSettings.openForIndex(WorkspaceManager.activeIndex)
    }

    function renameApplication() {
        renameAppDialog.text = WorkspaceManager.appDisplayName
        renameAppDialog.open()
    }

    function importWorkspace() { root.showImportWarning("json") }
    function exportWorkspace() { exportJsonDialog.open() }
    function importGitRepository() { root.showImportWarning("repository") }
    function exportGitRepository() { exportRepositoryDialog.open() }
    function openGitRepository() { WorkspaceManager.openRepository() }
    function syncWorkspace() { WorkspaceManager.syncNow() }

    function showImportWarning(kind) {
        importWarning.kind = kind
        importWarning.open()
    }

    Connections {
        target: WorkspaceManager
        function onActiveIndexChanged() {
            if (WorkspaceManager.activeIndex >= 0)
                tabList.positionViewAtIndex(WorkspaceManager.activeIndex, ListView.Contain)
        }
        function onOperationFinished(success, message, location) {
            workspaceSnackbar.show(message,
                success && location && location.toString().length > 0 ? qsTr("Open") : "",
                success && location && location.toString().length > 0
                    ? function() { Qt.openUrlExternally(location) } : null)
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Spacing.xs

            Label {
                Layout.fillWidth: true
                text: qsTr("Workspace")
                font: Typography.pageTitle
                color: Theme.color("onSurface")
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Keep persistent local pages with individual typography and versioned Git history.")
                font: Typography.metadata
                color: Theme.color("muted")
                wrapMode: Text.WordWrap
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
                spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: workspaceHeader.implicitHeight + Spacing.lg * 2
            color: Theme.color("surface")
            border.width: 0

            RowLayout {
                id: workspaceHeader
                anchors.fill: parent
                anchors.leftMargin: Spacing.space20
                anchors.rightMargin: Spacing.lg
                anchors.topMargin: Spacing.lg
                anchors.bottomMargin: Spacing.lg
                spacing: Spacing.md

                Image {
                    source: "qrc:/branding/logo-mark.png"
                    sourceSize.width: 34
                    sourceSize.height: 34
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: WorkspaceManager.appDisplayName
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font: Typography.sectionTitle
                        color: Theme.color("onSurface")
                        Layout.fillWidth: true
                    }
                    Label {
                        objectName: "workspaceSyncStatus"
                        text: WorkspaceManager.repositoryStatus
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        font: Typography.metadata
                        color: !WorkspaceManager.writable
                            ? Theme.color("error")
                            : (WorkspaceManager.dirty
                                ? Theme.color("primary") : Theme.color("onSurfaceVariant"))
                        Layout.fillWidth: true
                    }
                }

                Button {
                    id: renameButton
                    objectName: "workspaceRenameAppButton"
                    visible: root.width >= 720
                    enabled: WorkspaceManager.writable
                    flat: true
                    Layout.preferredHeight: Spacing.controlHeight
                    text: qsTr("Rename app")
                    icon.source: ""
                    onClicked: root.renameApplication()
                }

                IconButton {
                    objectName: "workspaceSyncButton"
                    enabled: WorkspaceManager.writable
                    symbol: Icons.refresh
                    tooltip: qsTr("Commit pending changes to local Git")
                    onClicked: WorkspaceManager.syncNow()
                }

                IconButton {
                    objectName: "workspaceOpenRepositoryButton"
                    symbol: Icons.folder
                    tooltip: qsTr("Open local Git repository")
                    onClicked: WorkspaceManager.openRepository()
                }

                IconButton {
                    objectName: "workspacePortabilityButton"
                    symbol: Icons.more_vert
                    tooltip: qsTr("Import and export")
                    onClicked: portabilityMenu.popup()
                }
            }
        }

        WorkspaceTabStrip {
            id: modernTabStrip
            Layout.fillWidth: true
            revealedTabId: root.revealedTabId
            onContextRequested: function(index, anchorItem) {
                tabContextMenu.targetIndex = index
                tabContextMenu.popup()
            }
            onAppearanceRequested: function(index, anchorItem) {
                tabSettings.openForIndex(index, anchorItem)
            }
            onGroupAppearanceRequested: function(groupId, anchorItem) {
                tabSettings.openForGroup(groupId, anchorItem)
            }
            onGroupContextRequested: function(groupId, anchorItem) {
                groupContextMenu.targetGroupId = groupId
                groupContextMenu.popup()
            }
            onSearchRequested: function(anchorItem, groupId) {
                workspaceSearch.openFrom(anchorItem, groupId)
            }
            onOverflowRequested: function(anchorItem) {
                overflowPopup.returnFocusItem = anchorItem
                overflowPopup.open()
                overflowSearch.forceActiveFocus()
            }
        }

        Rectangle {
            visible: false
            enabled: false
            Layout.preferredHeight: 0
            Layout.fillWidth: true
            implicitHeight: Spacing.controlHeight + Spacing.sm
            color: Theme.color("surfaceWarm")
            border.width: 0

            RowLayout {
                anchors.fill: parent
                anchors.margins: Spacing.xs
                spacing: 0

                ListView {
                    id: tabList
                    objectName: "workspaceTabBar"
                    Accessible.name: qsTr("Workspace tabs")
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    spacing: 2
                    model: WorkspaceManager
                    currentIndex: WorkspaceManager.activeIndex

                    delegate: TabButton {
                        id: tabButton
                        required property int index
                        required property string tabId
                        required property string name
                        width: Math.max(132, Math.min(230, implicitWidth))
                        height: ListView.view.height
                        leftPadding: Spacing.sm
                        rightPadding: Spacing.xs
                        checked: index === WorkspaceManager.activeIndex
                        objectName: "workspaceTab_" + tabId
                        Accessible.name: qsTr("Workspace tab %1").arg(name)
                        onClicked: WorkspaceManager.activeIndex = index

                        background: Rectangle {
                            radius: Spacing.radiusControl
                            color: tabButton.checked
                                ? Theme.color("primaryContainer")
                                : (tabButton.hovered ? Theme.color("surface") : "transparent")

                            Behavior on color {
                                ColorAnimation { duration: Spacing.motionFast }
                            }
                        }

                        contentItem: RowLayout {
                            spacing: Spacing.xs
                            MDIcon {
                                icon: Icons.article
                                size: 16
                                color: tabButton.checked
                                    ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                            }
                            Label {
                                text: tabButton.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font: Typography.titleSmall
                                color: tabButton.checked
                                    ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                                Layout.fillWidth: true
                            }
                            IconButton {
                                objectName: "workspaceTabClose_" + tabButton.tabId
                                Accessible.name: qsTr("Close %1").arg(tabButton.name)
                                symbol: Icons.close
                                size: 14
                                tooltip: qsTr("Close tab")
                                enabled: WorkspaceManager.writable
                                onClicked: WorkspaceManager.closeTab(tabButton.index)
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                WorkspaceManager.activeIndex = tabButton.index
                                tabContextMenu.targetIndex = tabButton.index
                                tabContextMenu.popup()
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            enabled: WorkspaceManager.writable
                            onTapped: WorkspaceManager.closeTab(tabButton.index)
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            enabled: WorkspaceManager.writable
                            onDoubleTapped: tabSettings.openForIndex(tabButton.index)
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: Spacing.outlineWidth
                    Layout.fillHeight: true
                    color: Theme.color("outlineVariant")
                }

                IconButton {
                    id: addTabButton
                    objectName: "workspaceAddTabButton"
                    Accessible.name: qsTr("New workspace tab")
                    Layout.preferredWidth: Spacing.controlHeight
                    Layout.fillHeight: true
                    symbol: Icons.add
                    tooltip: qsTr("New tab (Ctrl+T)")
                    enabled: WorkspaceManager.writable
                    onClicked: root.createTab()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Spacing.outlineWidth
            color: Theme.color("outlineVariant")
        }

        StackLayout {
            id: pageStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: WorkspaceManager.activeIndex
            visible: WorkspaceManager.count > 0

            Repeater {
                model: WorkspaceManager
                delegate: Item {
                    required property int index
                    required property string tabId
                    required property string name
                    required property string content
                    required property string fontFamily
                    required property string fontStyle
                    required property real fontPointSize
                    required property bool bold
                    required property bool italic
                    required property string fontColor
                    required property string groupId
                    required property var appearance
                    required property string updatedAt

                    WorkspacePage {
                        anchors.fill: parent
                        tabId: parent.tabId
                        tabName: parent.name
                        tabContent: parent.content
                        fontFamily: parent.fontFamily
                        fontStyle: parent.fontStyle
                        fontPointSize: parent.fontPointSize
                        bold: parent.bold
                        italic: parent.italic
                        fontColor: parent.fontColor
                        groupId: parent.groupId
                        appearance: parent.appearance
                        updatedAt: parent.updatedAt
                    }
                }
            }
        }

        Pane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: WorkspaceManager.count === 0
            background: Rectangle { color: Theme.color("surface") }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(460, parent.width * 0.86)
                spacing: Spacing.md
                MDIcon {
                    Layout.alignment: Qt.AlignHCenter
                    icon: Icons.article
                    size: 56
                    color: Theme.color("primary")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Open your first page")
                    horizontalAlignment: Text.AlignHCenter
                    font: Typography.sectionTitle
                    color: Theme.color("onSurface")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Each tab is a persistent page with its own typography and unlimited color. Every change is versioned in a private local Git repository.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: Spacing.controlHeight
                    text: qsTr("Create tab")
                    highlighted: true
                    enabled: WorkspaceManager.writable
                    onClicked: root.createTab()
                }
            }
        }
            }
        }
    }

    Menu {
        id: tabContextMenu
        objectName: "workspaceTabContextMenu"
        property int targetIndex: -1
        readonly property var targetTab: WorkspaceManager.tabAt(targetIndex)
        Material.elevation: Spacing.elevationMenu
        background: Rectangle {
            implicitWidth: 260
            radius: Spacing.radiusCard
            color: Theme.color("surface")
            border.width: Spacing.outlineWidth
            border.color: Theme.color("outlineVariant")
        }

        MenuItem {
            id: customizeTabAction
            objectName: "workspaceCustomizeTabAction"
            text: qsTr("Edit tab appearance…")
            enabled: WorkspaceManager.writable
            onTriggered: tabSettings.openForIndex(tabContextMenu.targetIndex)
        }
        MenuItem {
            text: tabContextMenu.targetTab.pinned ? qsTr("Unpin tab") : qsTr("Pin tab")
            enabled: WorkspaceManager.writable
            onTriggered: WorkspaceManager.setTabPinned(tabContextMenu.targetIndex,
                !tabContextMenu.targetTab.pinned)
        }
        MenuItem {
            text: qsTr("Duplicate tab")
            enabled: WorkspaceManager.writable
            onTriggered: WorkspaceManager.duplicateTab(tabContextMenu.targetIndex)
        }
        Menu {
            title: qsTr("Move to group")
            MenuItem {
                text: qsTr("Ungrouped")
                checkable: true
                checked: !tabContextMenu.targetTab.groupId
                onTriggered: WorkspaceManager.assignTabToGroup(
                    tabContextMenu.targetIndex, "")
            }
            MenuSeparator {}
            Repeater {
                model: WorkspaceManager.groups
                delegate: MenuItem {
                    required property var modelData
                    text: modelData.name
                    checkable: true
                    checked: tabContextMenu.targetTab.groupId === modelData.groupId
                    onTriggered: WorkspaceManager.assignTabToGroup(
                        tabContextMenu.targetIndex, modelData.groupId)
                }
            }
        }
        MenuItem {
            text: qsTr("Move left")
            enabled: WorkspaceManager.writable && tabContextMenu.targetIndex > 0
            onTriggered: WorkspaceManager.moveTab(tabContextMenu.targetIndex,
                tabContextMenu.targetIndex - 1)
        }
        MenuItem {
            text: qsTr("Move right")
            enabled: WorkspaceManager.writable
                && tabContextMenu.targetIndex < WorkspaceManager.count - 1
            onTriggered: WorkspaceManager.moveTab(tabContextMenu.targetIndex,
                tabContextMenu.targetIndex + 1)
        }
        MenuItem {
            text: qsTr("Close other ordinary tabs (keep pinned)")
            enabled: WorkspaceManager.writable && WorkspaceManager.count > 1
            onTriggered: WorkspaceManager.closeOtherTabs(tabContextMenu.targetIndex)
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Close tab")
            enabled: WorkspaceManager.writable
            onTriggered: WorkspaceManager.closeTab(tabContextMenu.targetIndex)
        }
    }

    Menu {
        id: groupContextMenu
        property string targetGroupId: ""
        readonly property var targetGroup: WorkspaceManager.groupById(targetGroupId)
        readonly property int targetGroupIndex: WorkspaceManager.groups.findIndex(function(group) {
            return group.groupId === targetGroupId
        })
        Material.elevation: Spacing.elevationMenu

        MenuItem {
            text: qsTr("Search inside group…")
            onTriggered: workspaceSearch.openFrom(modernTabStrip,
                groupContextMenu.targetGroupId)
        }
        MenuItem {
            text: qsTr("Edit group appearance…")
            enabled: WorkspaceManager.writable
            onTriggered: tabSettings.openForGroup(groupContextMenu.targetGroupId)
        }
        MenuItem {
            text: groupContextMenu.targetGroup.collapsed
                ? qsTr("Expand group") : qsTr("Collapse group")
            enabled: WorkspaceManager.writable
            onTriggered: WorkspaceManager.setGroupCollapsed(
                groupContextMenu.targetGroupId,
                !groupContextMenu.targetGroup.collapsed)
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Move group left")
            enabled: WorkspaceManager.writable && groupContextMenu.targetGroupIndex > 0
            onTriggered: WorkspaceManager.moveGroup(groupContextMenu.targetGroupIndex,
                groupContextMenu.targetGroupIndex - 1)
        }
        MenuItem {
            text: qsTr("Move group right")
            enabled: WorkspaceManager.writable && groupContextMenu.targetGroupIndex >= 0
                && groupContextMenu.targetGroupIndex < WorkspaceManager.groups.length - 1
            onTriggered: WorkspaceManager.moveGroup(groupContextMenu.targetGroupIndex,
                groupContextMenu.targetGroupIndex + 1)
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Remove group (keep tabs)")
            enabled: WorkspaceManager.writable
            onTriggered: WorkspaceManager.removeGroup(groupContextMenu.targetGroupId)
        }
    }

    Popup {
        id: overflowPopup
        property Item returnFocusItem: null
        parent: root
        x: Math.max(Spacing.lg, root.width - width - Spacing.lg)
        y: Math.min(root.height - height - Spacing.lg, 150)
        width: Math.min(520, root.width - Spacing.xl * 2)
        height: Math.min(540, root.height - Spacing.xl * 2)
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: Spacing.md
        Material.elevation: 12
        onClosed: if (returnFocusItem) returnFocusItem.forceActiveFocus()

        readonly property var result: WorkspaceManager.searchTabs(
            overflowSearch.text, overflowSearch.regexEnabled,
            overflowSearch.regexFlags, "")

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
            border.width: 1
            border.color: Theme.color("outlineVariant")
        }
        contentItem: ColumnLayout {
            spacing: Spacing.sm
            Accessible.name: qsTr("Searchable workspace tab overflow")
            Accessible.role: Accessible.Dialog
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: qsTr("All workspace tabs")
                    font: Typography.titleLarge
                }
                IconButton {
                    symbol: Icons.close
                    tooltip: qsTr("Close overflow and return to tab strip")
                    onClicked: overflowPopup.close()
                }
            }
            FilterTextField {
                id: overflowSearch
                Layout.fillWidth: true
                placeholder: qsTr("Search overflowed and visible tabs")
                builderTitle: qsTr("Overflow tab-list Regex Builder")
                builderSampleText: WorkspaceManager.tabItems.map(function(tab) {
                    return tab.name
                }).join("\n")
            }
            Label {
                text: qsTr("%1 result(s) · pinned tabs stay protected and visible")
                    .arg(overflowPopup.result.count)
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Spacing.xs
                model: overflowPopup.result.items || []
                Accessible.name: qsTr("All workspace tab results")
                Accessible.role: Accessible.List
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: qsTr("%1 · %2%3%4")
                        .arg(modelData.name)
                        .arg(modelData.location)
                        .arg(modelData.pinned ? qsTr(" · Pinned") : "")
                        .arg(modelData.groupCollapsed ? qsTr(" · Collapsed group") : "")
                    onClicked: {
                        WorkspaceManager.activeIndex = modelData.index
                        root.revealedTabId = modelData.tabId
                        revealTimer.restart()
                        overflowSearch.forceActiveFocus()
                    }
                }
            }
        }
    }

    WorkspaceSearchPanel {
        id: workspaceSearch
        parent: root
        x: Math.max(Spacing.lg, root.width - width - Spacing.lg)
        y: Math.max(Spacing.lg, (root.height - height) / 2)
        onRevealTab: function(tabId) {
            root.revealedTabId = tabId
            revealTimer.restart()
        }
        onEditGroupAppearance: function(groupId, anchorItem) {
            tabSettings.openForGroup(groupId, anchorItem)
        }
    }

    Timer {
        id: revealTimer
        interval: 8000
        repeat: false
        onTriggered: root.revealedTabId = ""
    }

    Menu {
        id: portabilityMenu
        Material.elevation: Spacing.elevationMenu
        background: Rectangle {
            implicitWidth: 360
            radius: Spacing.radiusCard
            color: Theme.color("surface")
            border.width: Spacing.outlineWidth
            border.color: Theme.color("outlineVariant")
        }
        MenuItem {
            objectName: "workspaceImportAction"
            text: qsTr("Import workspace JSON…")
            enabled: WorkspaceManager.writable
            onTriggered: root.showImportWarning("json")
        }
        MenuItem {
            objectName: "workspaceExportAction"
            text: qsTr("Export workspace JSON…")
            onTriggered: exportJsonDialog.open()
        }
        MenuSeparator {}
        MenuItem {
            objectName: "workspaceImportRepoAction"
            text: qsTr("Import complete Git repository…")
            enabled: WorkspaceManager.writable
            onTriggered: root.showImportWarning("repository")
        }
        MenuItem {
            objectName: "workspaceExportRepoAction"
            text: qsTr("Export complete Git repository…")
            enabled: WorkspaceManager.writable
            onTriggered: exportRepositoryDialog.open()
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Rename application…")
            enabled: WorkspaceManager.writable
            onTriggered: root.renameApplication()
        }
        MenuItem {
            text: qsTr("Edit workspace appearance…")
            enabled: WorkspaceManager.writable
            onTriggered: tabSettings.openForGlobal()
        }
        MenuItem {
            text: qsTr("Open managed repository")
            onTriggered: WorkspaceManager.openRepository()
        }
    }

    TextInputDialog {
        id: renameAppDialog
        objectName: "workspaceRenameAppDialog"
        inputObjectName: "workspaceRenameAppField"
        title: qsTr("Rename application")
        label: qsTr("Display name")
        placeholder: qsTr("qBittorrent Material")
        onAccepted: (value) => WorkspaceManager.appDisplayName = value
    }

    WorkspaceTabSettingsDialog { id: tabSettings }

    Popup {
        id: importWarning
        property string kind: "json"
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, parent.width * 0.9)
        padding: Spacing.xl
        Material.elevation: 24
        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
        }
        contentItem: ColumnLayout {
            spacing: Spacing.md
            Label {
                text: qsTr("Replace current workspace?")
                font: Typography.headlineSmall
                color: Theme.color("onSurface")
            }
            Label {
                Layout.fillWidth: true
                text: importWarning.kind === "repository"
                    ? qsTr("Importing a repository replaces the current tabs and local history. The current workspace is committed first.")
                    : qsTr("Importing JSON replaces the current tabs and appearance settings. The current workspace remains in local Git history.")
                wrapMode: Text.WordWrap
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
            }
            DialogButtonBox {
                Layout.fillWidth: true
                background: null
                Button {
                    text: qsTr("Cancel")
                    flat: true
                    DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                    onClicked: importWarning.close()
                }
                Button {
                    text: qsTr("Continue")
                    highlighted: true
                    DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                    onClicked: {
                        var kind = importWarning.kind
                        importWarning.close()
                        if (kind === "repository")
                            importRepositoryDialog.open()
                        else
                            importJsonDialog.open()
                    }
                }
            }
        }
    }

    Dialogs.FileDialog {
        id: importJsonDialog
        title: qsTr("Import workspace JSON")
        fileMode: Dialogs.FileDialog.OpenFile
        nameFilters: [qsTr("Workspace JSON (*.json)"), qsTr("All files (*)")]
        onAccepted: WorkspaceManager.importWorkspace(selectedFile)
    }

    Dialogs.FileDialog {
        id: exportJsonDialog
        title: qsTr("Export workspace JSON")
        fileMode: Dialogs.FileDialog.SaveFile
        defaultSuffix: "json"
        selectedFile: WorkspaceManager.suggestedExportUrl("qbt-material-workspace.json")
        nameFilters: [qsTr("Workspace JSON (*.json)"), qsTr("All files (*)")]
        onAccepted: WorkspaceManager.exportWorkspace(selectedFile)
    }

    Dialogs.FolderDialog {
        id: exportRepositoryDialog
        title: qsTr("Choose where to export the complete Git repository")
        onAccepted: WorkspaceManager.exportRepository(selectedFolder)
    }

    Dialogs.FolderDialog {
        id: importRepositoryDialog
        title: qsTr("Choose an exported workspace Git repository")
        onAccepted: WorkspaceManager.importRepository(selectedFolder)
    }

    Snackbar { id: workspaceSnackbar }
}
