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
    dismissed. The viewport restores undismissed persisted cards and scrolls
    internally when their combined height cannot fit. Exactly one instance is
    the primary visual host; non-primary instances retain the lightweight show()
    API but only publish into the persistent centre, preventing duplicate card
    stacks in nested pages.
*/
Item {
    id: root
    anchors.fill: parent
    // This host belongs to Overlay.overlay, but must remain beneath modal
    // dialogs and their dimmer rather than intercepting a required decision.
    z: -1
    visible: primaryHost && activeModel.count > 0

    property bool primaryHost: false

    function show(text, actionText, actionId, severity) {
        return NotificationCenter.notify(String(text),
                                         severity === undefined ? "info" : String(severity),
                                         "", actionText === undefined ? "" : String(actionText),
                                         actionId === undefined ? "" : String(actionId))
    }

    function removeById(id) {
        for (var i = 0; i < activeModel.count; ++i) {
            if (activeModel.get(i).notificationId === id) {
                activeModel.remove(i)
                return
            }
        }
    }

    function appendNotification(id, title, body, severity, actionLabel, actionId) {
        for (var i = 0; i < activeModel.count; ++i) {
            if (activeModel.get(i).notificationId === id)
                return false
        }
        activeModel.append({
            "notificationId": id,
            "notificationTitle": title,
            "notificationBody": body,
            "notificationSeverity": severity,
            "notificationActionLabel": actionLabel,
            "notificationActionId": actionId
        })
        return true
    }

    function scrollToNewest() {
        Qt.callLater(function() {
            notificationScrollBar.position = Math.max(0, 1 - notificationScrollBar.size)
        })
    }

    function hydrateActiveNotifications() {
        if (!root.primaryHost)
            return

        // A notification can be raised while the component tree is completing.
        // Rebuild from the controller's authoritative snapshot, then deduplicate
        // all later signals by id so startup cannot paint the same card twice.
        activeModel.clear()
        var entries = NotificationCenter.activeEntries()
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i]
            appendNotification(entry.notificationId,
                               entry.notificationTitle,
                               entry.notificationBody,
                               entry.notificationSeverity,
                               entry.notificationActionLabel,
                               entry.notificationActionId)
        }
        scrollToNewest()
    }

    ListModel { id: activeModel }

    Connections {
        target: root.primaryHost ? NotificationCenter : null
        function onNotificationRaised(id, title, body, severity, actionLabel, actionId) {
            if (root.appendNotification(id, title, body, severity, actionLabel, actionId))
                root.scrollToNewest()
        }
        function onAllDismissed() {
            activeModel.clear()
        }
        function onNotificationDismissed(id) {
            root.removeById(id)
        }
    }

    Component.onCompleted: hydrateActiveNotifications()

    Item {
        id: snackbarViewport
        readonly property real horizontalMargin: Math.min(Spacing.lg,
                                                           Math.max(0, root.width / 16))
        readonly property real verticalMargin: Math.min(Spacing.lg,
                                                         Math.max(0, root.height / 16))
        readonly property real maximumHeight: Math.max(0,
                                                        root.height - verticalMargin * 2)
        readonly property real desiredHeight: dismissAllRow.implicitHeight
                                                  + Spacing.sm
                                                  + cardsColumn.implicitHeight
        // A focused global action is still keyboard interaction with this
        // notification surface, so transient cards must not disappear under it.
        readonly property bool keyboardInteractionActive: dismissAllButton.activeFocus

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: horizontalMargin
        anchors.bottomMargin: verticalMargin
        width: Math.max(0, Math.min(480, root.width - horizontalMargin * 2))
        height: Math.max(0, Math.min(maximumHeight, desiredHeight))
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: Spacing.sm

            Item {
                id: dismissAllRow
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                implicitHeight: dismissAllButton.implicitHeight

                Button {
                    id: dismissAllButton
                    anchors.right: parent.right
                    width: Math.max(0, Math.min(implicitWidth, parent.width))
                    focusPolicy: Qt.StrongFocus
                    // The action is global: it also dismisses persistent
                    // warning/error records restored before this live host was
                    // created. Report the same scope the click actually affects.
                    text: qsTr("Dismiss all (%1)").arg(NotificationCenter.activeCount)
                    Accessible.name: qsTr("Dismiss all %1 active notifications")
                        .arg(NotificationCenter.activeCount)
                    Accessible.description: qsTr("Dismisses every active notification card and keeps notification history")
                    onClicked: NotificationCenter.dismissAll()
                }
            }

            ScrollView {
                id: notificationScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                padding: 0
                clip: true
                contentWidth: availableWidth
                contentHeight: cardsColumn.implicitHeight
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: ScrollBar {
                    id: notificationScrollBar
                    policy: ScrollBar.AsNeeded
                }
                Accessible.role: Accessible.List
                Accessible.name: qsTr("Notifications")

                Column {
                    id: cardsColumn
                    width: Math.max(0, notificationScroll.availableWidth)
                    spacing: Spacing.sm

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

                            readonly property bool persistent: notificationSeverity === "warning"
                                                               || notificationSeverity === "error"
                            readonly property bool keyboardInteractionActive:
                                notificationAction.activeFocus || notificationDismiss.activeFocus
                            readonly property color accent: notificationSeverity === "error" ? Theme.color("error")
                                                            : notificationSeverity === "warning" ? Theme.color("warning")
                                                            : notificationSeverity === "success" ? Theme.color("success")
                                                            : Theme.color("primary")

                            width: cardsColumn.width
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
                                        id: notificationAction
                                        visible: card.notificationActionLabel.length > 0
                                        text: card.notificationActionLabel
                                        flat: true
                                        focusPolicy: Qt.StrongFocus
                                        Accessible.name: text
                                        onClicked: {
                                            var id = card.notificationId
                                            if (card.notificationActionId.length > 0)
                                                NotificationCenter.activateAction(id)
                                            NotificationCenter.dismiss(id)
                                        }
                                    }
                                }

                                IconButton {
                                    id: notificationDismiss
                                    Layout.alignment: Qt.AlignTop
                                    symbol: Icons.close
                                    size: Spacing.iconSizeSmall
                                    tooltip: qsTr("Dismiss")
                                    focusPolicy: Qt.StrongFocus
                                    Accessible.name: qsTr("Dismiss %1 notification").arg(card.notificationTitle)
                                    onClicked: {
                                        var id = card.notificationId
                                        NotificationCenter.dismiss(id)
                                    }
                                }
                            }

                            Timer {
                                interval: card.notificationSeverity === "success" ? 4000
                                        : card.notificationSeverity === "progress" ? 6500 : 5000
                                // A keyboard user needs time to invoke the
                                // focused action before a transient card goes.
                                running: !card.persistent
                                         && !snackbarViewport.keyboardInteractionActive
                                         && !card.keyboardInteractionActive
                                onTriggered: {
                                    var id = card.notificationId
                                    NotificationCenter.dismiss(id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
