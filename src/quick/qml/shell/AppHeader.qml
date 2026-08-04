/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype AppHeader
    \brief The redesigned 64px header: transfers search pill (with regex
           toggle + Regex Builder hook), Split Dock nav segments, session
           speed pill, Alt-speed toggle, notification bell, History (git),
           theme toggle, Settings — plus a trailing overflow menu that keeps
           every legacy menu verb reachable.
*/
Rectangle {
    id: root

    required property var shell
    property var filterProxy: null
    property int currentTab: 0
    property int unreadNotifications: 0
    property string activePanel: ""

    // Split Dock puts five labelled destinations in the header.  At the
    // supported minimum window width those labels compete with the search
    // field and the always-available session controls, so the header must
    // collapse the destination strip before any control is squeezed off the
    // right edge.  The compact menu keeps every destination keyboard and
    // screen-reader reachable without changing the desktop-wide layout.
    readonly property bool compactSplitDock: Theme.isSplitDock && root.width < 1200

    signal navRequested(int index)
    signal panelRequested(string panel)
    signal regexBuilderRequested()

    height: 64
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 12

        // --- Split Dock (B): nav segments live in the header -----------------
        Rectangle {
            visible: Theme.isSplitDock && !root.compactSplitDock
            Layout.preferredHeight: 40
            Layout.preferredWidth: segmentsRow.implicitWidth + 8
            radius: 20
            color: Theme.color("surfaceVariant")

            Row {
                id: segmentsRow
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: root.navModel
                    delegate: AbstractButton {
                        id: segmentButton
                        required property var modelData
                        required property int index
                        readonly property bool active: root.currentTab === modelData.page

                        height: 32
                        width: segRow.implicitWidth + 28
                        padding: 0
                        hoverEnabled: true
                        activeFocusOnTab: true

                        Accessible.name: segmentButton.modelData.label
                        Accessible.description: segmentButton.active
                            ? qsTr("Current destination") : qsTr("Open destination")

                        background: Rectangle {
                            radius: 16
                            color: segmentButton.active ? Theme.color("primaryContainer")
                                                       : (segmentButton.hovered ? Theme.color("hoverStrong") : "transparent")
                            border.width: segmentButton.visualFocus ? 2 : 0
                            border.color: Theme.color("primary")
                        }

                        contentItem: Row {
                            id: segRow
                            anchors.centerIn: parent
                            spacing: 6

                            MDIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.icon
                                size: 17
                                fill: parent.parent.active
                                color: parent.parent.active ? Theme.color("onPrimaryContainer")
                                                            : Theme.color("onSurfaceVariant")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: Typography.family
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: parent.parent.active ? Theme.color("onSurface")
                                                            : Theme.color("onSurfaceVariant")
                            }
                            Rectangle {
                                visible: (modelData.badge || 0) > 0 && !parent.parent.active
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(16, segBadge.implicitWidth + 8)
                                height: 16
                                radius: 8
                                color: Theme.color("primary")
                                Text {
                                    id: segBadge
                                    anchors.centerIn: parent
                                    text: String(modelData.badge || 0)
                                    color: Theme.color("onPrimary")
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: root.navRequested(modelData.page)
                    }
                }
            }
        }

        HeaderIconButton {
            visible: root.compactSplitDock
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            iconName: "menu"
            tooltip: qsTr("Open destinations")
            onClicked: compactNavigationMenu.popup()
        }

        // --- Transfers filter pill (Transfers tab only) -----------------------
        Rectangle {
            id: searchPill
            visible: (root.currentTab === 0) && (root.filterProxy !== null)
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.preferredHeight: 44
            radius: 22
            color: Theme.color("surfaceVariant")
            border.width: 1
            border.color: rxInvalid ? Theme.color("error") : "transparent"

            readonly property bool useRegex: root.filterProxy && root.filterProxy.useRegex
            readonly property string textFilter: root.filterProxy ? root.filterProxy.textFilter : ""
            readonly property bool rxInvalid: useRegex
                && (textFilter.length > 0) && !root.regexValid(textFilter)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 6
                spacing: 8

                MDIcon { name: "search"; size: 20; color: Theme.color("onSurfaceVariant") }

                TextInput {
                    id: filterInput
                    objectName: "headerFilterInput"
                    Layout.fillWidth: true
                    text: searchPill.textFilter
                    Accessible.name: qsTr("Filter torrents")
                    Accessible.description: searchPill.useRegex
                        ? qsTr("Filter transfers with a regular expression")
                        : qsTr("Filter transfers by text")
                    onTextEdited: { if (root.filterProxy) root.filterProxy.textFilter = text }
                    font.family: Typography.family
                    font.pixelSize: 14
                    color: Theme.color("onSurface")
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        visible: filterInput.text.length === 0
                        text: searchPill.useRegex
                            ? (filterInput.width < 110 ? qsTr("Regex") : qsTr("Search with /regex/"))
                            : (filterInput.width < 110 ? qsTr("Search") : qsTr("Search torrents"))
                        elide: Text.ElideRight
                        font: filterInput.font
                        color: Theme.color("onSurfaceVariant")
                    }
                }

                AbstractButton {
                    id: regexToggle
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: rxLabel.implicitWidth + 20
                    padding: 0
                    hoverEnabled: true
                    activeFocusOnTab: true
                    checkable: true
                    checked: searchPill.useRegex
                    Accessible.name: searchPill.useRegex
                        ? qsTr("Disable regular-expression filtering")
                        : qsTr("Enable regular-expression filtering")
                    Accessible.description: qsTr("Toggle regular-expression filtering")

                    background: Rectangle {
                        radius: 14
                        color: searchPill.useRegex
                            ? (searchPill.rxInvalid ? Theme.color("errorContainer") : Theme.color("primaryContainer"))
                            : (regexToggle.hovered ? Theme.color("hoverStrong") : "transparent")
                        border.width: regexToggle.visualFocus ? 2 : 0
                        border.color: Theme.color("primary")
                    }
                    contentItem: Text {
                        id: rxLabel
                        anchors.centerIn: parent
                        text: ".*"
                        font.family: Typography.monoFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: searchPill.useRegex
                            ? (searchPill.rxInvalid ? Theme.color("error") : Theme.color("onPrimaryContainer"))
                            : Theme.color("onSurfaceVariant")
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: { if (root.filterProxy) root.filterProxy.useRegex = !root.filterProxy.useRegex }
                }

                HeaderIconButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    iconName: "data_object"
                    iconSize: 18
                    iconColor: Theme.color("onSurfaceVariant")
                    tooltip: qsTr("Open Regex Builder")
                    onClicked: root.regexBuilderRequested()
                }
            }
        }

        Item { Layout.fillWidth: true }

        // --- Session speeds pill ---------------------------------------------
        Rectangle {
            Layout.preferredHeight: 34
            Layout.preferredWidth: speedsRow.implicitWidth + 28
            radius: 17
            color: Theme.color("surfaceVariant")

            Row {
                id: speedsRow
                anchors.centerIn: parent
                spacing: 8

                MDIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_downward"; size: 18; color: Theme.color("success")
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatSpeed(Session.downloadRate || 0)
                    font.family: Typography.monoFamily
                    font.pixelSize: 13
                    color: Theme.color("onSurface")
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1; height: 14; color: Theme.color("outline")
                }
                MDIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_upward"; size: 18; color: Theme.color("primary")
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatSpeed(Session.uploadRate || 0)
                    font.family: Typography.monoFamily
                    font.pixelSize: 13
                    color: Theme.color("onSurface")
                }
            }
        }

        // --- Alternative speed limits toggle ----------------------------------
        AbstractButton {
            id: alternativeLimitsButton
            readonly property bool altOn: SpeedLimitController.alternativeLimitsEnabled || false
            Layout.preferredHeight: 34
            Layout.preferredWidth: altRow.implicitWidth + 28
            padding: 0
            hoverEnabled: true
            activeFocusOnTab: true
            checkable: true
            checked: altOn
            Accessible.name: qsTr("Alternative speed limits")
            Accessible.description: altOn
                ? qsTr("Disable alternative speed limits")
                : qsTr("Enable alternative speed limits")

            background: Rectangle {
                radius: 17
                color: alternativeLimitsButton.altOn
                    ? Theme.color("primaryContainer")
                    : (alternativeLimitsButton.hovered ? Theme.color("hoverStrong") : "transparent")
                border.width: alternativeLimitsButton.visualFocus ? 2 : 1
                border.color: alternativeLimitsButton.visualFocus
                    ? Theme.color("primary")
                    : (alternativeLimitsButton.altOn ? Theme.color("primaryContainer") : Theme.color("outline"))

                Behavior on color { ColorAnimation { duration: 250 } }
            }

            contentItem: Row {
                id: altRow
                anchors.centerIn: parent
                spacing: 6
                MDIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "speed"; size: 18
                    fill: parent.parent.altOn
                    color: parent.parent.altOn ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Alt")
                    font.family: Typography.family
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: parent.parent.altOn ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            onClicked: SpeedLimitController.toggleAlternativeLimits()
        }

        // --- Panel buttons -----------------------------------------------------
        HeaderIconButton {
            iconName: "search"
            tooltip: qsTr("Command palette")
            onClicked: root.shell.actionCommandPalette.trigger()
        }
        HeaderIconButton {
            iconName: "notifications"
            tooltip: qsTr("Notifications")
            active: root.activePanel === "notifications"
            badgeCount: root.unreadNotifications
            Accessible.name: qsTr("Notifications") + ". "
                + qsTr("%1 unread · %2 total")
                    .arg(root.unreadNotifications).arg(NotificationCenter.count)
            Accessible.description: active
                ? qsTr("Notification center open")
                : qsTr("Notification center closed")
            Accessible.checked: active
            onClicked: root.panelRequested("notifications")
        }
        HeaderIconButton {
            iconName: "history"
            tooltip: qsTr("History (git)")
            active: root.activePanel === "history"
            onClicked: root.panelRequested("history")
        }
        HeaderIconButton {
            iconName: Theme.isDark ? "light_mode" : "dark_mode"
            tooltip: qsTr("Toggle light / dark")
            onClicked: ThemeManager.colorScheme = Theme.isDark ? ThemeManager.Light : ThemeManager.Dark
        }
        HeaderIconButton {
            iconName: "settings"
            tooltip: qsTr("Settings")
            active: root.activePanel === "settings"
            onClicked: root.panelRequested("settings")
        }

        // --- Overflow: the full legacy menu tree stays reachable --------------
        AppMenuBar {
            shell: root.shell
        }
    }

    // The full five-destination strip is intentionally replaced, rather than
    // merely clipped, at compact widths.  SearchableMenu gives this navigation
    // surface the same local keyboard search as the other menus.
    SearchableMenu {
        id: compactNavigationMenu
        minimumMenuWidth: 260
        searchPlaceholder: qsTr("Search destinations")
        searchAccessibleName: qsTr("Search destinations")

        Repeater {
            model: root.navModel
            delegate: MenuItem {
                required property var modelData
                text: modelData.label
                visible: compactNavigationMenu.matches(text)
                height: visible ? implicitHeight : 0
                Accessible.name: text
                onTriggered: root.navRequested(modelData.page)
            }
        }
    }

    // Navigation model shared by the header segments (B) and the nav rails (A/C).
    property int rssUnread: 0
    readonly property var navModel: [
        { label: qsTr("Transfers"), icon: "download", page: 0, badge: 0 },
        { label: qsTr("Search"), icon: "travel_explore", page: 1, badge: 0 },
        { label: qsTr("RSS"), icon: "rss_feed", page: 2, badge: root.rssUnread },
        { label: qsTr("Log"), icon: "article", page: 3, badge: 0 },
        { label: qsTr("Notes"), icon: "edit_note", page: 4, badge: 0 }
    ]

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec >= 1024 * 1024)
            return (bytesPerSec / (1024 * 1024)).toFixed(1) + " MiB/s"
        if (bytesPerSec >= 1024)
            return Math.round(bytesPerSec / 1024) + " KiB/s"
        return bytesPerSec + " B/s"
    }

    function regexValid(pattern) {
        try { new RegExp(pattern); return true } catch (e) { return false }
    }

    function focusFilter() {
        filterInput.forceActiveFocus()
    }
}
