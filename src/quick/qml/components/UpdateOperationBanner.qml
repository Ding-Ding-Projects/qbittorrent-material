/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*
 * Persistent, non-modal progress and recovery surface for ProgramUpdater.
 *
 * The staged-update restart prompt belongs to UpdateReadyBanner. This banner
 * covers the states before and after that handoff: visible progress, a Cancel
 * action only while the backend has declared the operation cancellable, an
 * explicit safe-apply explanation during staging, and a Retry action after a
 * failed or recovered operation. It never blocks the rest of the application.
 */
Pane {
    id: root

    signal cancelRequested()
    signal retryRequested()

    readonly property bool busy: ProgramUpdater.busy
    readonly property bool retryAvailable: ProgramUpdater.retryAvailable
    readonly property bool expanded: busy || retryAvailable
    readonly property bool cancellable: ProgramUpdater.cancellable
    readonly property bool staging: ProgramUpdater.state === ProgramUpdater.Staging
    readonly property bool cancelling: ProgramUpdater.state === ProgramUpdater.Cancelling
    readonly property bool failed: retryAvailable && !busy
    readonly property int percent: Math.max(0, Math.min(100, ProgramUpdater.progress))
    readonly property bool showPercent: busy && percent > 0
    readonly property string statusText: ProgramUpdater.statusMessage
    readonly property string heading: failed
        ? qsTr("Update needs attention")
        : staging
            ? qsTr("Applying update")
            : cancelling
                ? qsTr("Cancelling update")
                : qsTr("Updating qBittorrent")
    readonly property string stagingExplanation: qsTr(
        "The verified package is being applied locally. This step cannot be cancelled safely; qBittorrent will report when it finishes.")
    readonly property string announcement: failed
        ? qsTr("%1. Retry is available.").arg(statusText)
        : staging
            ? statusText + " " + stagingExplanation
            : showPercent
                ? qsTr("%1. %2% complete.").arg(statusText).arg(percent)
                : statusText

    width: parent ? parent.width : 0
    implicitHeight: Math.max(64, content.implicitHeight + topPadding + bottomPadding)
    height: expanded ? implicitHeight : 0
    opacity: expanded ? 1 : 0
    visible: expanded || height > 0.5
    clip: true
    padding: Spacing.md
    leftPadding: Math.min(Spacing.lg, Math.max(0, width / 16))
    rightPadding: Math.min(Spacing.lg, Math.max(0, width / 16))
    z: 2
    Material.elevation: 1

    Accessible.ignored: !expanded
    Accessible.role: Accessible.AlertMessage
    Accessible.name: announcement

    Behavior on height {
        NumberAnimation {
            duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        NumberAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
    }

    background: Rectangle {
        color: root.failed ? Theme.color("errorContainer") : Theme.color("primaryContainer")
        border.width: 1
        border.color: root.failed ? Theme.color("error") : Theme.color("primary")
    }

    contentItem: ColumnLayout {
        id: content
        spacing: Spacing.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.md

            MDIcon {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignTop
                name: root.failed ? "error" : "system_update_alt"
                size: 26
                color: root.failed ? Theme.color("onErrorContainer")
                                   : Theme.color("onPrimaryContainer")
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: root.heading
                    font: Typography.titleSmall
                    color: root.failed ? Theme.color("onErrorContainer")
                                       : Theme.color("onPrimaryContainer")
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: root.statusText
                    font: Typography.bodyMedium
                    color: root.failed ? Theme.color("onErrorContainer")
                                       : Theme.color("onPrimaryContainer")
                    wrapMode: Text.WordWrap
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.staging
            text: root.stagingExplanation
            font: Typography.bodySmall
            color: Theme.color("onPrimaryContainer")
            wrapMode: Text.WordWrap
            Accessible.name: visible ? text : ""
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.busy
            spacing: Spacing.sm

            ProgressBar {
                id: progressBar
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.percent
                indeterminate: !root.showPercent
                Accessible.name: qsTr("Update progress")
                Accessible.description: root.showPercent
                    ? qsTr("%1% complete").arg(root.percent)
                    : root.statusText
            }

            Label {
                visible: root.showPercent
                text: qsTr("%1%").arg(root.percent)
                font: Typography.mono
                color: Theme.color("onPrimaryContainer")
                Accessible.name: visible ? qsTr("%1 percent complete").arg(root.percent) : ""
            }
        }

        GridLayout {
            id: actionLayout
            Layout.fillWidth: true
            columnSpacing: Spacing.sm
            rowSpacing: Spacing.xs
            readonly property real requiredInlineWidth: cancelButton.implicitWidth
                                                        + retryButton.implicitWidth
                                                        + columnSpacing
            readonly property bool stackActions: I18n.language === I18n.Bilingual
                                                  || width < requiredInlineWidth
            columns: stackActions ? 1 : 3

            Item {
                visible: !actionLayout.stackActions
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 1
            }

            Button {
                id: cancelButton
                visible: root.cancellable
                text: qsTr("Cancel update")
                flat: true
                Layout.fillWidth: actionLayout.stackActions
                Layout.minimumWidth: 0
                Layout.maximumWidth: actionLayout.width
                Layout.alignment: Qt.AlignRight
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                Accessible.name: text
                Accessible.description: qsTr(
                    "Cancel the current update check or download. No update will be installed.")
                onClicked: {
                    if (ProgramUpdater.cancellable)
                        root.cancelRequested()
                }

                contentItem: Label {
                    text: cancelButton.text
                    font: cancelButton.font
                    color: Theme.color("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    Accessible.ignored: true
                }
            }

            Button {
                id: retryButton
                visible: root.retryAvailable
                text: qsTr("Retry update")
                Layout.fillWidth: actionLayout.stackActions
                Layout.minimumWidth: 0
                Layout.maximumWidth: actionLayout.width
                Layout.alignment: Qt.AlignRight
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                Accessible.name: text
                Accessible.description: qsTr(
                    "Retry the signed update check and verify any downloaded package before staging it.")
                onClicked: {
                    if (ProgramUpdater.retryAvailable)
                        root.retryRequested()
                }

                contentItem: Label {
                    text: retryButton.text
                    font: retryButton.font
                    color: root.failed ? Theme.color("error") : Theme.color("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    Accessible.ignored: true
                }
            }
        }
    }
}
