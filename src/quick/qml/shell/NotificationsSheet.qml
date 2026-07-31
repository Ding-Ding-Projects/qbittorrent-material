/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/* Persistent notification centre for all informational, warning and error cards. */
Item {
    id: root
    property bool open: false
    signal closeRequested()
    signal openHistoryRequested()
    readonly property int matchingNotifications: NotificationCenter.matchingCount(
        searchField.text, searchField.regexEnabled, searchField.regexFlags,
        scopeBox.currentValue || "all")

    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: Math.min(440, parent ? parent.width : 440)
    x: open ? 0 : width
    visible: open || x < width
    z: 160

    function matches(title, body, severity, read) {
        var scope = scopeBox.currentValue
        if (scope === "unread" && read)
            return false
        if (scope === "warning" && severity !== "warning")
            return false
        if (scope === "error" && severity !== "error")
            return false
        var query = searchField.text.trim()
        if (!query.length)
            return true
        var haystack = title + " " + body
        if (searchField.regexEnabled) {
            var evaluated = WorkspaceManager.evaluateRegularExpression(query,
                searchField.regexFlags, haystack)
            return evaluated.valid && evaluated.count > 0
        }
        return haystack.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
    }

    Behavior on x {
        NumberAnimation {
            duration: ThemeManager.reducedMotion ? 0 : 180
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outlineVariant")

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Spacing.md
                spacing: Spacing.sm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: qsTr("Notifications")
                        font: Typography.titleLarge
                        color: Theme.color("onSurface")
                    }
                    Label {
                        text: qsTr("%1 unread · %2 total")
                                  .arg(NotificationCenter.unreadCount)
                                  .arg(NotificationCenter.count)
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                    }
                }
                ToolButton {
                    text: qsTr("Close notifications")
                    display: AbstractButton.IconOnly
                    Accessible.name: text
                    contentItem: MDIcon { name: "close"; size: 20; color: Theme.color("onSurface") }
                    onClicked: root.closeRequested()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.md
                Layout.rightMargin: Spacing.md
                Layout.bottomMargin: Spacing.sm
                spacing: Spacing.sm

                FilterTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholder: qsTr("Search notifications")
                    Accessible.name: qsTr("Search notification title and message")
                    builderTitle: qsTr("Notification Regex Builder")
                    builderSampleText: qsTr("Error: connection timed out\nCompleted: torrent exported\nWarning: invalid path")
                }
                ComboBox {
                    id: scopeBox
                    textRole: "text"
                    valueRole: "value"
                    model: [
                        {"text": qsTr("All"), "value": "all"},
                        {"text": qsTr("Unread"), "value": "unread"},
                        {"text": qsTr("Warnings"), "value": "warning"},
                        {"text": qsTr("Errors"), "value": "error"}
                    ]
                    Accessible.name: qsTr("Notification filter")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.md
                Layout.rightMargin: Spacing.md
                Layout.bottomMargin: Spacing.sm
                Button {
                    text: qsTr("Mark all read")
                    flat: true
                    enabled: NotificationCenter.unreadCount > 0
                    onClicked: NotificationCenter.markAllRead()
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Clear history")
                    flat: true
                    enabled: NotificationCenter.count > 0
                    onClicked: NotificationCenter.clearAll()
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }

            ListView {
                id: feedView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Spacing.sm
                clip: true
                spacing: Spacing.sm
                model: NotificationCenter
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: card
                    required property string notificationId
                    required property string title
                    required property string body
                    required property string severity
                    required property string timeText
                    required property bool isRead
                    required property string actionLabel
                    required property string actionId

                    readonly property bool included: root.matches(title, body, severity, isRead)
                    readonly property color accent: severity === "error" ? Theme.color("error")
                                                    : severity === "warning" ? Theme.color("warning")
                                                    : severity === "success" ? Theme.color("success")
                                                    : Theme.color("primary")
                    width: feedView.width
                    height: included ? content.implicitHeight + Spacing.md * 2 : 0
                    visible: included
                    radius: Spacing.radiusCard
                    color: isRead ? Theme.color("surfaceVariant") : Theme.color("surfaceContainerHigh")
                    border.width: isRead ? 1 : 2
                    border.color: accent
                    Accessible.role: Accessible.ListItem
                    Accessible.name: title + ". " + body + ". " + timeText

                    RowLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Spacing.md
                        spacing: Spacing.sm

                        MDIcon {
                            Layout.alignment: Qt.AlignTop
                            name: card.severity === "error" ? "error" : card.severity === "warning" ? "warning" : card.severity === "success" ? "check_circle" : "info"
                            size: 20
                            color: card.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: card.title; font: Typography.titleSmall; color: Theme.color("onSurface"); wrapMode: Text.WordWrap }
                                Label { text: card.timeText; font: Typography.labelSmall; color: Theme.color("onSurfaceVariant") }
                            }
                            Label { Layout.fillWidth: true; text: card.body; font: Typography.bodyMedium; color: Theme.color("onSurfaceVariant"); wrapMode: Text.WordWrap }
                            Button {
                                visible: card.actionLabel.length > 0
                                text: card.actionLabel
                                flat: true
                                onClicked: NotificationCenter.activateAction(card.notificationId)
                            }
                        }
                    }

                    TapHandler { onTapped: NotificationCenter.markRead(card.notificationId) }
                }

                Label {
                    anchors.centerIn: parent
                    visible: root.matchingNotifications === 0
                    text: NotificationCenter.count === 0 ? qsTr("No notifications yet")
                        : qsTr("No notifications match this search or filter")
                    color: Theme.color("onSurfaceVariant")
                    font: Typography.bodyMedium
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }
            Button {
                Layout.fillWidth: true
                Layout.margins: Spacing.sm
                text: qsTr("Open Git-backed action history")
                flat: true
                onClicked: root.openHistoryRequested()
            }
        }
    }
}
