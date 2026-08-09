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
Sheet {
    id: root
    sheetWidth: 440
    accessibleName: qsTr("Notifications")

    signal closeRequested()
    signal openHistoryRequested()

    // matchingCount() is an invokable rather than a Q_PROPERTY getter, so make
    // the model signals explicit binding dependencies. Without these reads the
    // empty state could remain stale after a notification arrived or was read.
    readonly property int matchingNotifications: {
        // These reads intentionally register all model-state notify signals as
        // dependencies even though matchingCount() owns the actual filtering.
        const modelState = [NotificationCenter.count,
            NotificationCenter.unreadCount, NotificationCenter.activeCount]
        return NotificationCenter.matchingCount(
            searchField.text, searchField.regexEnabled, searchField.regexFlags,
            scopeBox.currentValue || "all")
    }

    onOpenChanged: {
        if (open)
            Qt.callLater(function() { searchField.forceActiveFocus(Qt.TabFocusReason) })
    }

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

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.md
                Layout.rightMargin: Spacing.md
                Layout.bottomMargin: Spacing.sm
                columns: (I18n.language === I18n.Bilingual || width < 360) ? 1 : 2
                columnSpacing: Spacing.sm
                rowSpacing: Spacing.sm

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
                    Layout.fillWidth: true
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

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.md
                Layout.rightMargin: Spacing.md
                Layout.bottomMargin: Spacing.sm
                columns: (I18n.language === I18n.Bilingual || width < 400) ? 1 : 3
                columnSpacing: Spacing.sm
                rowSpacing: Spacing.xs
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Mark all read")
                    flat: true
                    enabled: NotificationCenter.unreadCount > 0
                    onClicked: NotificationCenter.markAllRead()
                }
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Dismiss all (%1)").arg(NotificationCenter.activeCount)
                    flat: true
                    enabled: NotificationCenter.activeCount > 0
                    Accessible.name: qsTr("Dismiss all %1 active notifications")
                        .arg(NotificationCenter.activeCount)
                    Accessible.description: qsTr("Dismisses active notification cards and keeps them in notification history")
                    onClicked: NotificationCenter.dismissAll()
                }
                Button {
                    Layout.fillWidth: true
                    text: qsTr("Clear history")
                    flat: true
                    enabled: false
                    Accessible.description: clearHistoryExplanation.text
                }

                Label {
                    id: clearHistoryExplanation
                    Layout.fillWidth: true
                    Layout.columnSpan: parent.columns
                    text: qsTr("Clear history is unavailable until notification records can be restored from append-only local history.")
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                    wrapMode: Text.WordWrap
                    Accessible.name: text
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
                    required property bool dismissed
                    required property string actionLabel
                    required property string actionId

                    readonly property bool included: root.matches(title, body, severity, isRead)
                    readonly property bool oneShotAction: actionId.startsWith("journal-undo:")
                    readonly property bool actionAvailable: actionLabel.length > 0
                        && !(oneShotAction && dismissed)
                    readonly property color accent: severity === "error" ? Theme.color("error")
                                                    : severity === "warning" ? Theme.color("warning")
                                                    : severity === "success" ? Theme.color("success")
                                                    : Theme.color("primary")
                    readonly property string severityLabel: severity === "error" ? qsTr("Error")
                        : severity === "warning" ? qsTr("Warning")
                        : severity === "success" ? qsTr("Completed")
                        : severity === "progress" ? qsTr("In progress") : qsTr("Notice")
                    readonly property string readLabel: isRead ? qsTr("Read") : qsTr("Unread")
                    readonly property string presentationLabel: dismissed
                        ? qsTr("Dismissed") : qsTr("Active notification")
                    width: feedView.width
                    height: included ? content.implicitHeight + Spacing.md * 2 : 0
                    visible: included
                    activeFocusOnTab: included
                    radius: Spacing.radiusCard
                    color: isRead ? Theme.color("surfaceVariant") : Theme.color("surfaceContainerHigh")
                    border.width: activeFocus ? 3 : (isRead ? 1 : 2)
                    border.color: activeFocus ? Theme.color("focusRing") : accent
                    Accessible.role: Accessible.ListItem
                    Accessible.name: severityLabel + ". " + title + ". " + body
                        + ". " + timeText
                    Accessible.description: readLabel + ". " + presentationLabel

                    Keys.onSpacePressed: NotificationCenter.markRead(card.notificationId)
                    Keys.onReturnPressed: NotificationCenter.markRead(card.notificationId)
                    Keys.onDeletePressed: {
                        if (!card.dismissed)
                            NotificationCenter.dismiss(card.notificationId)
                    }

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
                                visible: card.actionAvailable
                                text: card.actionLabel
                                flat: true
                                onClicked: NotificationCenter.activateAction(card.notificationId)
                            }
                        }

                        ToolButton {
                            visible: !card.dismissed
                            Layout.alignment: Qt.AlignTop
                            text: qsTr("Dismiss")
                            display: AbstractButton.IconOnly
                            Accessible.name: qsTr("Dismiss %1 notification").arg(card.title)
                            contentItem: MDIcon {
                                name: "close"
                                size: 20
                                color: Theme.color("onSurface")
                            }
                            onClicked: NotificationCenter.dismiss(card.notificationId)
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
