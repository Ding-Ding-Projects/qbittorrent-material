/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype Snackbar
    \brief Corner-anchored, stacking notification host backed by NotificationCenter.

    Every message is retained by the persistent NotificationCenter model. Info,
    success and progress cards auto-dismiss; warnings and errors remain until
    dismissed. The legacy show(text, action, callback) entry point remains so
    existing call sites gain history without a disruptive migration.
*/
Item {
    id: root
    anchors.fill: parent
    z: 9000
    visible: activeModel.count > 0

    property int maximumVisible: 5
    property var _callbacks: ({})

    function show(text, actionText, callback, severity) {
        var id = NotificationCenter.notify(String(text),
                                           severity === undefined ? "info" : String(severity),
                                           "", actionText === undefined ? "" : String(actionText),
                                           actionText === undefined || actionText.length === 0 ? "" : "qml-callback")
        if (id.length > 0 && callback !== undefined && callback !== null)
            _callbacks[id] = callback
        return id
    }

    function removeById(id) {
        for (var i = 0; i < activeModel.count; ++i) {
            if (activeModel.get(i).notificationId === id) {
                activeModel.remove(i)
                return
            }
        }
    }

    ListModel { id: activeModel }

    Connections {
        target: NotificationCenter
        function onNotificationRaised(id, title, body, severity, actionLabel, actionId) {
            activeModel.append({
                "notificationId": id,
                "notificationTitle": title,
                "notificationBody": body,
                "notificationSeverity": severity,
                "notificationActionLabel": actionLabel,
                "notificationActionId": actionId
            })
        }
    }

    Column {
        id: stack
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Spacing.lg
        anchors.bottomMargin: Spacing.lg
        spacing: Spacing.sm
        width: Math.min(480, Math.max(280, parent.width - Spacing.xl * 2))

        Repeater {
            model: activeModel

            delegate: Pane {
                id: card
                required property string notificationId
                required property string notificationTitle
                required property string notificationBody
                required property string notificationSeverity
                required property string notificationActionLabel
                required property string notificationActionId
                required property int index

                readonly property bool persistent: notificationSeverity === "warning"
                                                   || notificationSeverity === "error"
                // Keep overflow queued in the local model. The oldest card
                // becomes visible again when a newer card is dismissed, so a
                // warning/error is never silently thrown away.
                visible: index >= Math.max(0, activeModel.count - root.maximumVisible)
                readonly property color accent: notificationSeverity === "error" ? Theme.color("error")
                                                : notificationSeverity === "warning" ? Theme.color("warning")
                                                : notificationSeverity === "success" ? Theme.color("success")
                                                : Theme.color("primary")

                width: stack.width
                padding: Spacing.md
                Material.elevation: 6
                Accessible.role: Accessible.AlertMessage
                Accessible.name: notificationTitle + ". " + notificationBody

                background: Rectangle {
                    radius: Spacing.radiusCard
                    color: Theme.color("surfaceContainerHigh")
                    border.width: 1
                    border.color: card.accent
                }

                contentItem: RowLayout {
                    spacing: Spacing.sm

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignTop
                        radius: 12
                        color: Qt.alpha(card.accent, Theme.isDark ? 0.24 : 0.14)
                        MDIcon {
                            anchors.centerIn: parent
                            name: card.notificationSeverity === "error" ? "error"
                                : card.notificationSeverity === "warning" ? "warning"
                                : card.notificationSeverity === "success" ? "check_circle"
                                : card.notificationSeverity === "progress" ? "progress_activity" : "info"
                            size: 20
                            color: card.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            Layout.fillWidth: true
                            text: card.notificationTitle
                            font: Typography.titleSmall
                            color: Theme.color("onSurface")
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            text: card.notificationBody
                            font: Typography.bodyMedium
                            color: Theme.color("onSurfaceVariant")
                            wrapMode: Text.WordWrap
                            maximumLineCount: 5
                            elide: Text.ElideRight
                        }
                        Button {
                            visible: card.notificationActionLabel.length > 0
                            text: card.notificationActionLabel
                            flat: true
                            Accessible.name: text
                            onClicked: {
                                var callback = root._callbacks[card.notificationId]
                                if (callback)
                                    callback()
                                else if (card.notificationActionId.length > 0)
                                    NotificationCenter.activateAction(card.notificationId)
                                delete root._callbacks[card.notificationId]
                                NotificationCenter.dismiss(card.notificationId)
                                root.removeById(card.notificationId)
                            }
                        }
                    }

                    ToolButton {
                        Layout.alignment: Qt.AlignTop
                        icon.name: "close"
                        text: qsTr("Dismiss")
                        display: AbstractButton.IconOnly
                        Accessible.name: qsTr("Dismiss %1 notification").arg(card.notificationTitle)
                        ToolTip.visible: hovered
                        ToolTip.text: text
                        onClicked: {
                            delete root._callbacks[card.notificationId]
                            NotificationCenter.dismiss(card.notificationId)
                            root.removeById(card.notificationId)
                        }
                    }
                }

                Timer {
                    interval: card.notificationSeverity === "success" ? 4000
                            : card.notificationSeverity === "progress" ? 6500 : 5000
                    running: !card.persistent
                    onTriggered: {
                        delete root._callbacks[card.notificationId]
                        NotificationCenter.dismiss(card.notificationId)
                        root.removeById(card.notificationId)
                    }
                }

            }
        }
    }
}
