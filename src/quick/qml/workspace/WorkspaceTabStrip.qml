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
    // NOT "surfaceWarm": that token is aliased to primaryContainer, which is
    // exactly the selected tab's fill, so the active tab used to be invisible
    // against its own strip. The strip is the recessed tray; tabs sit on it.
    color: Theme.color("surfaceVariant")
    border.width: 0

    function mergeAppearance(result, values) {
        if (!values)
            return result
        var keys = Object.keys(values)
        for (var i = 0; i < keys.length; ++i)
            result[keys[i]] = values[keys[i]]
        return result
    }

    function resolveGroupAppearance(group) {
        var result = mergeAppearance({}, WorkspaceManager.globalAppearance || ({}))
        return mergeAppearance(result, group && group.appearance ? group.appearance : ({}))
    }

    function resolveTabAppearance(tab) {
        // Read the groups property directly so this binding also refreshes when
        // a group-level sparse override changes. The editor previews the same
        // global → group → tab order; the strip must render that order too.
        var groups = WorkspaceManager.groups || []
        var result = mergeAppearance({}, WorkspaceManager.globalAppearance || ({}))
        if (tab && tab.groupId) {
            for (var i = 0; i < groups.length; ++i) {
                if (groups[i].groupId === tab.groupId) {
                    mergeAppearance(result, groups[i].appearance || ({}))
                    break
                }
            }
        }
        return mergeAppearance(result, tab && tab.appearance ? tab.appearance : ({}))
    }

    function appearanceValue(appearance, key, fallback) {
        if (!appearance || appearance[key] === undefined || appearance[key] === null)
            return fallback
        return appearance[key]
    }

    function appearanceNumber(appearance, key, fallback) {
        var value = appearanceValue(appearance, key, fallback)
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : fallback
    }

    function appearanceBool(appearance, key, fallback) {
        var value = appearanceValue(appearance, key, fallback)
        return value === true || value === "true" || value === 1
    }

    function capitalization(value) {
        if (value === "AllUppercase" || value === "Uppercase") return Font.AllUppercase
        if (value === "AllLowercase" || value === "Lowercase") return Font.AllLowercase
        if (value === "SmallCaps") return Font.SmallCaps
        if (value === "Capitalize") return Font.Capitalize
        return Font.MixedCase
    }

    /*! Scrolls the tab with workspace index \a index into view without stealing
        focus. Pinned tabs are always on screen, so only the ordinary list moves. */
    function positionTabInView(index) {
        for (var i = 0; i < ordinaryItems.length; ++i) {
            if (ordinaryItems[i].kind === "tab" && ordinaryItems[i].tab.index === index) {
                ordinaryList.positionViewAtIndex(i, ListView.Contain)
                return
            }
        }
    }

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
        readonly property var resolvedAppearance: root.resolveTabAppearance(tabData)

        width: compact ? 54 : Math.max(132, Math.min(230, implicitWidth))
        height: ListView.view ? ListView.view.height : Spacing.controlHeight
        leftPadding: root.appearanceNumber(resolvedAppearance, "padding", Spacing.sm)
        rightPadding: root.appearanceNumber(resolvedAppearance, "padding", Spacing.xs)
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
            radius: root.appearanceNumber(control.resolvedAppearance, "radius",
                Spacing.radiusControl)
            // Every state needs its own fill or the tabs read as one flat band.
            // Unselected tabs were "transparent", which on a same-coloured strip
            // meant browser-style tab shapes were never drawn at all.
            color: control.checked
                ? root.appearanceValue(control.resolvedAppearance, "checkedColor",
                    Theme.color("primaryContainer"))
                : (control.hovered
                    ? root.appearanceValue(control.resolvedAppearance, "hoverColor",
                        Theme.color("surfaceContainerHigh"))
                    : root.appearanceValue(control.resolvedAppearance, "backgroundColor",
                        Theme.color("surface")))
            // Zero is a real saved border width, not a request to fall back to
            // the state default.
            border.width: root.appearanceNumber(control.resolvedAppearance, "borderWidth",
                control.checked ? 0 : Spacing.outlineWidth)
            border.color: root.appearanceValue(control.resolvedAppearance, "borderColor",
                Theme.color("outlineVariant"))
            Behavior on color { ColorAnimation { duration: Spacing.motionFast } }
        }

        contentItem: RowLayout {
            spacing: Spacing.xs
            MDIcon {
                icon: control.tabData.pinned ? Icons.lock : Icons.article
                size: 16
                color: root.appearanceValue(control.resolvedAppearance, "textColor",
                    control.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant"))
            }
            Label {
                visible: !control.compact
                text: control.tabData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: root.appearanceValue(control.resolvedAppearance, "fontFamily",
                    Typography.family)
                font.styleName: root.appearanceValue(control.resolvedAppearance, "fontStyle", "")
                font.pixelSize: root.appearanceNumber(control.resolvedAppearance,
                    "fontPointSize", Typography.titleSmall.pixelSize / 1.333) * 1.333
                font.weight: root.appearanceNumber(control.resolvedAppearance, "fontWeight",
                    Typography.titleSmall.weight)
                font.bold: root.appearanceBool(control.resolvedAppearance, "bold", false)
                font.italic: root.appearanceBool(control.resolvedAppearance, "italic", false)
                font.underline: root.appearanceBool(control.resolvedAppearance, "underline", false)
                font.strikeout: root.appearanceBool(control.resolvedAppearance, "strikeout", false)
                    || root.appearanceBool(control.resolvedAppearance, "doubleStrike", false)
                font.overline: root.appearanceBool(control.resolvedAppearance, "overline", false)
                font.capitalization: root.capitalization(root.appearanceValue(
                    control.resolvedAppearance, "capitalization", "MixedCase"))
                font.letterSpacing: root.appearanceNumber(control.resolvedAppearance,
                    "letterSpacing", 0)
                font.wordSpacing: root.appearanceNumber(control.resolvedAppearance,
                    "wordSpacing", 0)
                LayoutMirroring.enabled: root.appearanceValue(control.resolvedAppearance,
                    "direction", "Auto") === "RightToLeft"
                color: root.appearanceValue(control.resolvedAppearance, "textColor",
                    control.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant"))
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
                    readonly property var resolvedAppearance: root.resolveGroupAppearance(
                        visible ? visualItem.modelData.group : null)
                    width: visible ? Math.max(96, groupRow.implicitWidth + Spacing.sm * 2) : 0
                    height: parent.height
                    radius: root.appearanceNumber(resolvedAppearance, "radius",
                        Spacing.radiusControl)
                    color: visualItem.modelData.kind === "group"
                        ? root.appearanceValue(resolvedAppearance, "backgroundColor",
                            Theme.color("surfaceVariant")) : "transparent"
                    border.width: visible ? root.appearanceNumber(resolvedAppearance,
                        "borderWidth", 1) : 0
                    border.color: visualItem.modelData.kind === "group"
                        ? root.appearanceValue(resolvedAppearance, "borderColor",
                            visualItem.modelData.group.color) : "transparent"
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
                                ? root.appearanceValue(groupHeader.resolvedAppearance,
                                    "textColor", visualItem.modelData.group.color)
                                : Theme.color("onSurface")
                            font.family: visualItem.modelData.kind === "group"
                                ? root.appearanceValue(groupHeader.resolvedAppearance,
                                    "fontFamily", Typography.family) : Typography.family
                            font.styleName: root.appearanceValue(groupHeader.resolvedAppearance,
                                "fontStyle", "")
                            font.pixelSize: root.appearanceNumber(groupHeader.resolvedAppearance,
                                "fontPointSize", Typography.labelLarge.pixelSize / 1.333) * 1.333
                            font.weight: root.appearanceNumber(groupHeader.resolvedAppearance,
                                "fontWeight", Typography.labelLarge.weight)
                            font.bold: root.appearanceBool(groupHeader.resolvedAppearance,
                                "bold", true)
                            font.italic: root.appearanceBool(groupHeader.resolvedAppearance,
                                "italic", false)
                            font.underline: root.appearanceBool(groupHeader.resolvedAppearance,
                                "underline", false)
                            font.strikeout: root.appearanceBool(groupHeader.resolvedAppearance,
                                "strikeout", false) || root.appearanceBool(
                                groupHeader.resolvedAppearance, "doubleStrike", false)
                            font.overline: root.appearanceBool(groupHeader.resolvedAppearance,
                                "overline", false)
                            font.capitalization: root.capitalization(root.appearanceValue(
                                groupHeader.resolvedAppearance, "capitalization", "MixedCase"))
                            font.letterSpacing: root.appearanceNumber(groupHeader.resolvedAppearance,
                                "letterSpacing", 0)
                            font.wordSpacing: root.appearanceNumber(groupHeader.resolvedAppearance,
                                "wordSpacing", 0)
                            LayoutMirroring.enabled: root.appearanceValue(
                                groupHeader.resolvedAppearance, "direction", "Auto") === "RightToLeft"
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
