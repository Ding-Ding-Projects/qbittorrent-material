/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

Rectangle {
    id: root

    property string revealedTabId: ""
    readonly property var pinnedTabs: WorkspaceManager.tabItems.filter(function(tab) {
        return tab.pinned
    })
    readonly property var ordinaryItems: {
        var tabs = WorkspaceManager.tabItems.filter(function(tab) { return !tab.pinned })
        var result = [{ kind: "ungrouped" }]
        tabs.filter(function(tab) { return !tab.groupId }).forEach(function(tab) {
            result.push({ kind: "tab", tab: tab })
        })
        WorkspaceManager.groups.forEach(function(group, groupIndex) {
            result.push({ kind: "group", group: group, groupIndex: groupIndex })
            tabs.filter(function(tab) { return tab.groupId === group.groupId }).forEach(function(tab) {
                if (!group.collapsed || tab.tabId === root.revealedTabId)
                    result.push({ kind: "tab", tab: tab })
            })
        })
        return result
    }

    signal contextRequested(int index, Item anchorItem)
    signal appearanceRequested(int index, Item anchorItem)
    signal groupAppearanceRequested(string groupId, Item anchorItem)
    signal groupContextRequested(string groupId, Item anchorItem)
    signal searchRequested(Item anchorItem, string groupId)
    signal overflowRequested(Item anchorItem)

    implicitHeight: Spacing.controlHeight + Spacing.sm
    color: Theme.color("surfaceWarm")
    border.width: 0

    function focusTabByIndex(index) {
        WorkspaceManager.activeIndex = index
        var item = pinnedList.itemAtIndex(pinnedTabs.findIndex(function(tab) {
            return tab.index === index
        }))
        if (item) {
            item.forceActiveFocus()
            return
        }
        for (var i = 0; i < ordinaryItems.length; ++i) {
            if (ordinaryItems[i].kind === "tab" && ordinaryItems[i].tab.index === index) {
                ordinaryList.positionViewAtIndex(i, ListView.Contain)
                var ordinaryItem = ordinaryList.itemAtIndex(i)
                if (ordinaryItem && ordinaryItem.tabControl)
                    ordinaryItem.tabControl.forceActiveFocus()
                return
            }
        }
    }

    component WorkspaceTabButton: TabButton {
        id: control
        required property var tabData
        property bool compact: false
        property alias dragActive: dragHandler.active

        width: compact ? 54 : Math.max(132, Math.min(230, implicitWidth))
        height: ListView.view ? ListView.view.height : Spacing.controlHeight
        leftPadding: Spacing.sm
        rightPadding: Spacing.xs
        checked: tabData.index === WorkspaceManager.activeIndex
        activeFocusOnTab: true
        objectName: "workspaceTab_" + tabData.tabId
        Accessible.name: qsTr("%1 workspace tab, %2%3")
            .arg(tabData.name)
            .arg(tabData.pinned ? qsTr("pinned") : qsTr("not pinned"))
            .arg(tabData.groupName ? qsTr(", group %1").arg(tabData.groupName) : "")
        Accessible.description: qsTr("Use Left and Right to change tabs; Ctrl+Shift+Left or Right reorders within the pinned or ordinary region.")
        Accessible.role: Accessible.PageTab
        Accessible.selected: checked
        Accessible.focusable: true
        ToolTip.visible: hovered && compact
        ToolTip.text: tabData.name

        onClicked: WorkspaceManager.activeIndex = tabData.index

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left && (event.modifiers & Qt.ControlModifier)
                    && (event.modifiers & Qt.ShiftModifier)) {
                WorkspaceManager.moveTab(tabData.index, Math.max(0, tabData.index - 1))
                event.accepted = true
            } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.ControlModifier)
                    && (event.modifiers & Qt.ShiftModifier)) {
                WorkspaceManager.moveTab(tabData.index,
                    Math.min(WorkspaceManager.count - 1, tabData.index + 1))
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                root.focusTabByIndex(Math.max(0, tabData.index - 1))
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                root.focusTabByIndex(Math.min(WorkspaceManager.count - 1, tabData.index + 1))
                event.accepted = true
            } else if (event.key === Qt.Key_Home) {
                root.focusTabByIndex(0)
                event.accepted = true
            } else if (event.key === Qt.Key_End) {
                root.focusTabByIndex(WorkspaceManager.count - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Space) {
                WorkspaceManager.activeIndex = tabData.index
                event.accepted = true
            } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)
                    && (event.modifiers & Qt.ShiftModifier)) {
                root.appearanceRequested(tabData.index, control)
                event.accepted = true
            }
        }

        background: Rectangle {
            radius: tabData.appearance.radius !== undefined
                ? tabData.appearance.radius : Spacing.radiusControl
            color: control.checked
                ? (tabData.appearance.checkedColor || Theme.color("primaryContainer"))
                : (control.hovered
                    ? (tabData.appearance.hoverColor || Theme.color("surface"))
                    : (tabData.appearance.backgroundColor || "transparent"))
            border.width: tabData.appearance.borderWidth || 0
            border.color: tabData.appearance.borderColor || Theme.color("outlineVariant")
            Behavior on color { ColorAnimation { duration: Spacing.motionFast } }
        }

        contentItem: RowLayout {
            spacing: Spacing.xs
            MDIcon {
                icon: control.tabData.pinned ? Icons.lock : Icons.article
                size: 16
                color: control.checked
                    ? Theme.color("primary") : Theme.color("onSurfaceVariant")
            }
            Label {
                visible: !control.compact
                text: control.tabData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: control.tabData.appearance.fontFamily || Typography.family
                font.pixelSize: control.tabData.appearance.fontPointSize
                    ? control.tabData.appearance.fontPointSize * 1.333 : Typography.titleSmall.pixelSize
                font.weight: control.tabData.appearance.fontWeight || Typography.titleSmall.weight
                font.bold: !!control.tabData.appearance.bold
                font.italic: !!control.tabData.appearance.italic
                font.underline: !!control.tabData.appearance.underline
                font.strikeout: !!control.tabData.appearance.strikeout
                font.letterSpacing: control.tabData.appearance.letterSpacing || 0
                font.wordSpacing: control.tabData.appearance.wordSpacing || 0
                color: control.tabData.appearance.textColor || (control.checked
                    ? Theme.color("primary") : Theme.color("onSurfaceVariant"))
                Layout.fillWidth: true
            }
            IconButton {
                visible: !control.compact && (!control.tabData.pinned || control.hovered)
                objectName: "workspaceTabClose_" + control.tabData.tabId
                Accessible.name: qsTr("Close %1").arg(control.tabData.name)
                symbol: Icons.close
                size: 14
                tooltip: control.tabData.pinned
                    ? qsTr("Close pinned tab") : qsTr("Close tab")
                enabled: WorkspaceManager.writable
                onClicked: WorkspaceManager.closeTab(control.tabData.index)
            }
        }

        Drag.active: dragHandler.active
        Drag.source: control
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        DragHandler {
            id: dragHandler
            target: null
            enabled: WorkspaceManager.writable
            acceptedButtons: Qt.LeftButton
        }

        DropArea {
            anchors.fill: parent
            onEntered: function(drag) {
                if (!drag.source || !drag.source.tabData)
                    return
                var source = drag.source.tabData
                if (source.pinned !== control.tabData.pinned)
                    return
                if (!source.pinned && source.groupId !== control.tabData.groupId)
                    WorkspaceManager.assignTabToGroup(source.index, control.tabData.groupId)
                WorkspaceManager.moveTab(source.index, control.tabData.index)
            }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: function(eventPoint) {
                WorkspaceManager.activeIndex = control.tabData.index
                if (eventPoint.modifiers & Qt.ShiftModifier)
                    root.appearanceRequested(control.tabData.index, control)
                else
                    root.contextRequested(control.tabData.index, control)
            }
        }
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            enabled: WorkspaceManager.writable
            onTapped: WorkspaceManager.closeTab(control.tabData.index)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Spacing.xs
        spacing: Spacing.xs

        Rectangle {
            visible: root.pinnedTabs.length > 0
            Layout.preferredWidth: visible
                ? Math.min(pinnedList.contentWidth + Spacing.xs, root.width * 0.36) : 0
            Layout.fillHeight: true
            radius: Spacing.radiusControl
            color: Theme.color("surfaceContainerHigh")
            border.width: 1
            border.color: Theme.color("outlineVariant")

            ListView {
                id: pinnedList
                anchors.fill: parent
                orientation: ListView.Horizontal
                clip: true
                spacing: 2
                model: root.pinnedTabs
                boundsBehavior: Flickable.StopAtBounds
                Accessible.name: qsTr("Pinned workspace tabs")
                Accessible.role: Accessible.PageTabList
                delegate: WorkspaceTabButton {
                    required property var modelData
                    tabData: modelData
                    compact: root.pinnedTabs.length > 4
                }
            }
        }

        Rectangle {
            visible: root.pinnedTabs.length > 0
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Theme.color("outlineVariant")
        }

        ListView {
            id: ordinaryList
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            clip: true
            spacing: 2
            model: root.ordinaryItems
            boundsBehavior: Flickable.StopAtBounds
            Accessible.name: qsTr("Ordinary workspace tabs and groups")
            Accessible.role: Accessible.PageTabList

            delegate: Item {
                id: visualItem
                required property var modelData
                property alias tabControl: tabLoader.item
                width: modelData.kind === "group" ? groupHeader.width
                    : (modelData.kind === "ungrouped" ? ungroupedHeader.width
                    : (tabLoader.item ? tabLoader.item.width : 0))
                height: ListView.view.height

                Loader {
                    id: tabLoader
                    active: visualItem.modelData.kind === "tab"
                    sourceComponent: WorkspaceTabButton {
                        tabData: visualItem.modelData.tab
                    }
                }

                Rectangle {
                    id: ungroupedHeader
                    visible: visualItem.modelData.kind === "ungrouped"
                    width: visible ? 42 : 0
                    height: parent.height
                    radius: Spacing.radiusControl
                    color: ungroupedDrop.containsDrag
                        ? Theme.color("primaryContainer") : "transparent"
                    border.width: 1
                    border.color: Theme.color("outlineVariant")
                    Accessible.name: qsTr("Ungrouped tabs drop target")
                    Accessible.role: Accessible.Grouping
                    MDIcon {
                        anchors.centerIn: parent
                        icon: Icons.article
                        size: 16
                        color: Theme.color("onSurfaceVariant")
                    }
                    ToolTip.visible: ungroupedHover.hovered
                    ToolTip.text: qsTr("Ungrouped tabs · drop an ordinary tab here")
                    HoverHandler { id: ungroupedHover }
                    DropArea {
                        id: ungroupedDrop
                        anchors.fill: parent
                        onEntered: function(drag) {
                            if (drag.source && drag.source.tabData
                                    && !drag.source.tabData.pinned)
                                WorkspaceManager.assignTabToGroup(
                                    drag.source.tabData.index, "")
                        }
                    }
                }

                Rectangle {
                    id: groupHeader
                    visible: visualItem.modelData.kind === "group"
                    width: visible ? Math.max(96, groupRow.implicitWidth + Spacing.sm * 2) : 0
                    height: parent.height
                    radius: visualItem.modelData.kind === "group"
                        && visualItem.modelData.group.appearance.radius !== undefined
                        ? visualItem.modelData.group.appearance.radius : Spacing.radiusControl
                    color: visualItem.modelData.kind === "group"
                        ? (visualItem.modelData.group.appearance.backgroundColor
                            || Theme.color("surfaceVariant")) : "transparent"
                    border.width: 1
                    border.color: visualItem.modelData.kind === "group"
                        ? (visualItem.modelData.group.appearance.borderColor
                            || visualItem.modelData.group.color) : "transparent"
                    activeFocusOnTab: visible
                    Accessible.name: visible ? qsTr("Tab group %1, %2")
                        .arg(visualItem.modelData.group.name)
                        .arg(visualItem.modelData.group.collapsed ? qsTr("collapsed") : qsTr("expanded")) : ""
                    Accessible.role: Accessible.Grouping
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Space || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Return) {
                            WorkspaceManager.setGroupCollapsed(visualItem.modelData.group.groupId,
                                !visualItem.modelData.group.collapsed)
                            event.accepted = true
                        } else if ((event.modifiers & Qt.ControlModifier)
                                && (event.modifiers & Qt.ShiftModifier)
                                && event.key === Qt.Key_Left) {
                            WorkspaceManager.moveGroup(visualItem.modelData.groupIndex,
                                Math.max(0, visualItem.modelData.groupIndex - 1))
                            event.accepted = true
                        } else if ((event.modifiers & Qt.ControlModifier)
                                && (event.modifiers & Qt.ShiftModifier)
                                && event.key === Qt.Key_Right) {
                            WorkspaceManager.moveGroup(visualItem.modelData.groupIndex,
                                Math.min(WorkspaceManager.groups.length - 1,
                                    visualItem.modelData.groupIndex + 1))
                            event.accepted = true
                        } else if ((event.modifiers & Qt.ControlModifier)
                                && (event.modifiers & Qt.ShiftModifier)
                                && event.key === Qt.Key_A) {
                            root.groupAppearanceRequested(
                                visualItem.modelData.group.groupId, groupHeader)
                            event.accepted = true
                        }
                    }

                    RowLayout {
                        id: groupRow
                        anchors.fill: parent
                        anchors.leftMargin: Spacing.xs
                        anchors.rightMargin: Spacing.xs
                        spacing: 0
                        IconButton {
                            symbol: visualItem.modelData.kind === "group"
                                && visualItem.modelData.group.collapsed
                                ? Icons.chevron_right : Icons.expand_more
                            size: 14
                            tooltip: visualItem.modelData.kind === "group"
                                && visualItem.modelData.group.collapsed
                                ? qsTr("Expand group") : qsTr("Collapse group")
                            onClicked: WorkspaceManager.setGroupCollapsed(
                                visualItem.modelData.group.groupId,
                                !visualItem.modelData.group.collapsed)
                        }
                        Label {
                            text: visualItem.modelData.kind === "group"
                                ? visualItem.modelData.group.name : ""
                            color: visualItem.modelData.kind === "group"
                                ? (visualItem.modelData.group.appearance.textColor
                                    || visualItem.modelData.group.color) : Theme.color("onSurface")
                            font.family: visualItem.modelData.kind === "group"
                                ? (visualItem.modelData.group.appearance.fontFamily
                                    || Typography.family) : Typography.family
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: 130
                        }
                        IconButton {
                            symbol: Icons.search
                            size: 14
                            tooltip: qsTr("Search inside this group")
                            onClicked: root.searchRequested(groupHeader,
                                visualItem.modelData.group.groupId)
                        }
                    }

                    Drag.active: groupDrag.active
                    Drag.source: groupHeader
                    property int groupIndex: visualItem.modelData.kind === "group"
                        ? visualItem.modelData.groupIndex : -1
                    DragHandler { id: groupDrag; target: null; acceptedButtons: Qt.LeftButton }
                    DropArea {
                        anchors.fill: parent
                        onEntered: function(drag) {
                            if (drag.source && drag.source.tabData
                                    && !drag.source.tabData.pinned) {
                                WorkspaceManager.assignTabToGroup(
                                    drag.source.tabData.index,
                                    visualItem.modelData.group.groupId)
                            } else if (drag.source && drag.source.groupIndex >= 0) {
                                WorkspaceManager.moveGroup(drag.source.groupIndex,
                                    groupHeader.groupIndex)
                            }
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: function(eventPoint) {
                            if (eventPoint.modifiers & Qt.ShiftModifier)
                                root.groupAppearanceRequested(
                                    visualItem.modelData.group.groupId, groupHeader)
                            else
                                root.groupContextRequested(
                                    visualItem.modelData.group.groupId, groupHeader)
                        }
                    }
                }
            }
        }

        IconButton {
            id: overflowButton
            visible: ordinaryList.contentWidth > ordinaryList.width || root.pinnedTabs.length > 0
            Layout.preferredWidth: Spacing.controlHeight
            Layout.fillHeight: true
            symbol: Icons.more_vert
            tooltip: qsTr("All workspace tabs and overflow")
            onClicked: root.overflowRequested(overflowButton)
        }

        IconButton {
            id: searchButton
            Layout.preferredWidth: Spacing.controlHeight
            Layout.fillHeight: true
            symbol: Icons.search
            tooltip: qsTr("Search current strip, groups, or all tabs")
            onClicked: root.searchRequested(searchButton, "")
        }

        IconButton {
            id: addButton
            objectName: "workspaceAddTabButton"
            Accessible.name: qsTr("New workspace tab")
            Layout.preferredWidth: Spacing.controlHeight
            Layout.fillHeight: true
            symbol: Icons.add
            tooltip: qsTr("New tab (Ctrl+T)")
            enabled: WorkspaceManager.writable
            onClicked: WorkspaceManager.createTab(qsTr("New tab"))
        }
    }
}
