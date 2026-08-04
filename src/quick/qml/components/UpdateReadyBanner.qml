/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*
 * Persistent, non-modal update notice. It intentionally has no checking or
 * downloading state: the banner enters the visual tree only after Update.exe
 * has completed staging and ProgramUpdater has verified the new executable.
 */
Pane {
    id: root

    signal restartRequested(var returnFocusItem)
    signal laterRequested(var returnFocusItem)

    property string postponedVersion: ""
    property var returnFocusItem: null
    readonly property string versionText: ProgramUpdater.availableVersion
    readonly property bool expanded: ProgramUpdater.readyToRestart
        && versionText.length > 0 && postponedVersion !== versionText
    readonly property string announcement: qsTr(
        "Version %1 has been downloaded and is ready. Restart qBittorrent to finish updating.")
        .arg(versionText)

    function captureReturnFocus() {
        var owningWindow = root.Window.window
        if (owningWindow && owningWindow.activeFocusItem)
            root.returnFocusItem = owningWindow.activeFocusItem
    }

    function postpone() {
        root.postponedVersion = root.versionText
        root.laterRequested(root.returnFocusItem)
    }

    onExpandedChanged: {
        if (expanded)
            captureReturnFocus()
    }

    width: parent ? parent.width : 0
    implicitHeight: Math.max(64, content.implicitHeight + topPadding + bottomPadding)
    height: expanded ? implicitHeight : 0
    opacity: expanded ? 1 : 0
    visible: expanded || height > 0.5
    clip: true
    padding: Spacing.md
    // Preserve usable content width when the logical viewport narrows at high
    // display scales. The action layout below handles the remaining width by
    // stacking instead of allowing a translated label to leave the window.
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
        color: Theme.color("primaryContainer")
        border.width: 1
        border.color: Theme.color("primary")
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
                name: "system_update_alt"
                size: 26
                color: Theme.color("onPrimaryContainer")
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Update ready · Version %1").arg(root.versionText)
                    font: Typography.titleSmall
                    color: Theme.color("onPrimaryContainer")
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: root.announcement
                    font: Typography.bodyMedium
                    color: Theme.color("onPrimaryContainer")
                    wrapMode: Text.WordWrap
                }
            }
        }

        GridLayout {
            id: actionLayout
            Layout.fillWidth: true
            columnSpacing: Spacing.sm
            rowSpacing: Spacing.xs
            readonly property real requiredInlineWidth: releaseNotesButton.implicitWidth
                                                        + laterButton.implicitWidth
                                                        + restartButton.implicitWidth
                                                        + columnSpacing * 2
            readonly property bool stackActions: I18n.language === I18n.Bilingual
                                                  || width < requiredInlineWidth
            columns: stackActions ? 1 : 4

            Item {
                visible: !actionLayout.stackActions
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 1
            }

            Button {
                id: releaseNotesButton
                text: qsTr("Release notes")
                flat: true
                Layout.fillWidth: actionLayout.stackActions
                Layout.minimumWidth: 0
                Layout.maximumWidth: actionLayout.width
                Layout.alignment: Qt.AlignRight
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                KeyNavigation.tab: laterButton
                Accessible.name: qsTr("Release notes for version %1").arg(root.versionText)
                Accessible.description: qsTr("Open the release notes in the default browser")
                onClicked: Qt.openUrlExternally(ProgramUpdater.releaseNotesUrl)

                contentItem: Label {
                    text: releaseNotesButton.text
                    font: releaseNotesButton.font
                    color: Theme.color("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    Accessible.ignored: true
                }
            }

            Button {
                id: laterButton
                text: qsTr("Later")
                flat: true
                Layout.fillWidth: actionLayout.stackActions
                Layout.minimumWidth: 0
                Layout.maximumWidth: actionLayout.width
                Layout.alignment: Qt.AlignRight
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                KeyNavigation.tab: restartButton
                Accessible.name: text
                Accessible.description: qsTr("Hide this banner until the next app launch")
                onClicked: root.postpone()

                contentItem: Label {
                    text: laterButton.text
                    font: laterButton.font
                    color: Theme.color("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    Accessible.ignored: true
                }
            }

            Button {
                id: restartButton
                text: qsTr("Restart to install update")
                Layout.fillWidth: actionLayout.stackActions
                Layout.minimumWidth: 0
                Layout.maximumWidth: actionLayout.width
                Layout.alignment: Qt.AlignRight
                focusPolicy: Qt.StrongFocus
                activeFocusOnTab: true
                Accessible.name: text
                Accessible.description: root.announcement
                onClicked: root.restartRequested(root.returnFocusItem)

                contentItem: Label {
                    text: restartButton.text
                    font: restartButton.font
                    color: Theme.color("primary")
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
