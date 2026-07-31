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
    \qmltype HistorySheet
    \brief The git History manager: Action log / Settings repo tabs, commit
           search (plain or regex), a day-grouped commit timeline with
           expandable diffs, per-entry Restore/Undo and Copy-sha — backed by
           JournalHistoryModel + JournalController.
*/
Sheet {
    id: root
    sheetWidth: 460

    property string repo: "actions"
    property string expandedCommit: ""

    JournalHistoryModel {
        id: historyModel
        repo: root.repo
        filterText: searchField.text
        filterRegex: histRegex
    }
    property bool histRegex: false

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.leftMargin: 20
            Layout.rightMargin: 16
            Layout.bottomMargin: 10
            spacing: 10

            Text {
                text: qsTr("History")
                font.family: Typography.family
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Theme.color("onSurface")
            }
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: branchRow.implicitWidth + 20
                radius: 12
                color: Theme.color("surfaceVariant")
                Row {
                    id: branchRow
                    anchors.centerIn: parent
                    spacing: 5
                    MDIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "account_tree"; size: 14; color: Theme.color("onSurfaceVariant")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "main"
                        font.family: Typography.monoFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.color("onSurfaceVariant")
                    }
                }
            }
            Item { Layout.fillWidth: true }
            HeaderIconButton {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                iconName: "save_alt"; iconSize: 19; iconColor: Theme.color("onSurfaceVariant")
                tooltip: qsTr("Export repo as JSON")
                onClicked: {
                    var n = JournalController.exportHistoryJson(root.repo)
                    root.shellNotify(qsTr("Copied %1 commits as JSON to the clipboard").arg(n))
                }
            }
            HeaderIconButton {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                iconName: "close"; iconSize: 19; iconColor: Theme.color("onSurfaceVariant")
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }

        // Repo tabs + auto-commit toggle.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 10
            spacing: 6

            Repeater {
                model: [
                    { key: "actions", label: qsTr("Action log"), icon: "bolt" },
                    { key: "settings", label: qsTr("Settings repo"), icon: "settings" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.repo === modelData.key
                    Layout.preferredHeight: 34
                    implicitWidth: tabRow.implicitWidth + 28
                    radius: 17
                    color: active ? Theme.color("primaryContainer") : "transparent"
                    border.width: 1
                    border.color: active ? Theme.color("primaryContainer") : Theme.color("outline")
                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 6
                        MDIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon; size: 16
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Typography.family
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.key === "actions"
                                ? String(JournalController.actionsCount) : String(JournalController.settingsCount)
                            font.family: Typography.monoFamily
                            font.pixelSize: 11
                            opacity: 0.7
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.repo = modelData.key; root.expandedCommit = "" }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: qsTr("auto-commit · always on")
                font.family: Typography.family
                font.pixelSize: 12
                color: Theme.color("onSurfaceVariant")
            }
            Rectangle {
                Layout.preferredWidth: 34; Layout.preferredHeight: 20
                radius: 10
                color: JournalController.autoCommit ? Theme.color("primary") : Theme.color("surfaceContainerHigh")
                Behavior on color { ColorAnimation { duration: 200 } }
                Rectangle {
                    width: 14; height: 14; radius: 7
                    y: 3
                    x: JournalController.autoCommit ? 17 : 3
                    color: JournalController.autoCommit ? Theme.color("onPrimary") : Theme.color("onSurfaceVariant")
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Spacing.easeStandard } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.ArrowCursor
                    Accessible.name: qsTr("Settings history is always recorded locally")
                }
            }
        }

        // Search.
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 10
            Layout.preferredHeight: 38
            radius: 19
            color: Theme.color("surfaceVariant")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 6
                spacing: 8
                MDIcon { name: "search"; size: 17; color: Theme.color("onSurfaceVariant") }
                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    font.family: Typography.family
                    font.pixelSize: 13
                    color: Theme.color("onSurface")
                    clip: true
                    selectByMouse: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text.length === 0
                        text: qsTr("Search commits (message, sha)")
                        font: searchField.font
                        color: Theme.color("onSurfaceVariant")
                    }
                }
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: 34
                    radius: 12
                    color: root.histRegex ? Theme.color("primaryContainer") : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: ".*"
                        font.family: Typography.monoFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.histRegex ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.histRegex = !root.histRegex }
                }
            }
        }

        // Commit timeline.
        ListView {
            id: timeline
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 16
            clip: true
            model: historyModel
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            section.property: "dateKey"
            section.delegate: Text {
                text: section.toUpperCase()
                font.family: Typography.family
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: Theme.color("onSurfaceVariant")
                topPadding: 10
                bottomPadding: 6
                leftPadding: 30
            }

            delegate: Item {
                id: commitItem
                required property int index
                required property string commitId
                required property string sha
                required property string message
                required property string timeText
                required property var diffLines
                required property bool undoable
                required property bool canRestore
                required property string origin

                readonly property bool expanded: root.expandedCommit === commitId

                width: timeline.width
                height: commitColumn.implicitHeight

                Row {
                    anchors.fill: parent
                    spacing: 12

                    // Timeline dot + line.
                    Column {
                        width: 18
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 10; height: 10; radius: 5
                            color: (commitItem.index === 0) ? Theme.color("primary") : Theme.color("outline")
                            border.width: 2
                            border.color: Theme.color("surface")
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 2
                            height: commitColumn.implicitHeight - 8
                            color: Theme.color("outlineVariant")
                        }
                    }

                    Column {
                        id: commitColumn
                        width: parent.width - 30
                        bottomPadding: 10

                        // Row header.
                        Rectangle {
                            width: parent.width
                            height: 34
                            radius: 12
                            color: headerMouse.containsMouse ? Theme.color("hover") : "transparent"
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: shaText.implicitWidth + 14
                                    height: 20
                                    radius: 8
                                    color: Theme.color("surfaceVariant")
                                    Text {
                                        id: shaText
                                        anchors.centerIn: parent
                                        text: commitItem.sha
                                        font.family: Typography.monoFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.color("primary")
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - shaText.implicitWidth - 130
                                    text: commitItem.message
                                    elide: Text.ElideRight
                                    font.family: Typography.family
                                    font.pixelSize: 13
                                    color: Theme.color("onSurface")
                                }
                                Item { width: 1; height: 1 }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: commitItem.timeText
                                    font.family: Typography.family
                                    font.pixelSize: 11
                                    color: Theme.color("onSurfaceVariant")
                                }
                                MDIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand_more"
                                    size: 17
                                    color: Theme.color("onSurfaceVariant")
                                    rotation: commitItem.expanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 200 } }
                                }
                            }
                            MouseArea {
                                id: headerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.expandedCommit = commitItem.expanded ? "" : commitItem.commitId
                            }
                        }

                        // Expanded diff + actions.
                        Rectangle {
                            visible: commitItem.expanded
                            width: parent.width - 6
                            x: 6
                            height: diffColumn.implicitHeight + 20
                            radius: 12
                            color: Theme.color("surfaceVariant")

                            Column {
                                id: diffColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                Repeater {
                                    model: commitItem.diffLines
                                    delegate: Column {
                                        required property var modelData
                                        width: parent.width
                                        spacing: 2
                                        Row {
                                            spacing: 8
                                            Text { text: "−"; color: Theme.color("error"); font.family: Typography.monoFamily; font.pixelSize: 12 }
                                            Text {
                                                width: diffColumn.width - 20
                                                text: modelData.from
                                                elide: Text.ElideRight
                                                color: Theme.color("error")
                                                font.family: Typography.monoFamily
                                                font.pixelSize: 12
                                            }
                                        }
                                        Row {
                                            spacing: 8
                                            Text { text: "+"; color: Theme.color("success"); font.family: Typography.monoFamily; font.pixelSize: 12 }
                                            Text {
                                                width: diffColumn.width - 20
                                                text: modelData.to
                                                elide: Text.ElideRight
                                                color: Theme.color("success")
                                                font.family: Typography.monoFamily
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                }

                                Row {
                                    spacing: 8
                                    topPadding: 6

                                    Rectangle {
                                        visible: commitItem.undoable
                                        height: 28
                                        width: undoRow.implicitWidth + 24
                                        radius: 14
                                        color: Theme.color("primaryContainer")
                                        enabled: !JournalController.busy
                                        opacity: JournalController.busy ? 0.6 : 1
                                        Row {
                                            id: undoRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "undo"; size: 15; color: Theme.color("onPrimaryContainer") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Undo")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onPrimaryContainer")
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.repo === "settings")
                                                    JournalController.undoSettingsEntry(commitItem.commitId)
                                                else
                                                    JournalController.undoEntry(commitItem.commitId)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: commitItem.canRestore && root.repo === "actions"
                                        height: 28
                                        width: restoreRow.implicitWidth + 24
                                        radius: 14
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.color("outline")
                                        enabled: !JournalController.busy
                                        opacity: JournalController.busy ? 0.6 : 1
                                        Row {
                                            id: restoreRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "settings_backup_restore"; size: 15; color: Theme.color("onSurfaceVariant") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Restore")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onSurfaceVariant")
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.restoreConfirm(commitItem.commitId, commitItem.index)
                                        }
                                    }

                                    Rectangle {
                                        height: 28
                                        width: copyRow.implicitWidth + 24
                                        radius: 14
                                        color: copyMouse.containsMouse ? Theme.color("hoverStrong") : "transparent"
                                        Row {
                                            id: copyRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "content_copy"; size: 15; color: Theme.color("onSurfaceVariant") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Copy sha")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onSurfaceVariant")
                                            }
                                        }
                                        MouseArea {
                                            id: copyMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                JournalController.copyToClipboard(commitItem.commitId)
                                                root.shellNotify(qsTr("Copied %1").arg(commitItem.sha))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state.
            Column {
                visible: timeline.count === 0
                anchors.centerIn: parent
                spacing: 8
                MDIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "history"; size: 44; color: Theme.color("outline")
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (searchField.text.length > 0) ? qsTr("No commits match") : qsTr("No history yet")
                    font.family: Typography.family
                    font.pixelSize: 13
                    color: Theme.color("onSurfaceVariant")
                }
            }
        }
    }

    // Wired by the shell.
    signal closeRequested()
    signal restoreConfirm(string commitId, int laterCount)
    function shellNotify(message) { root.notifyRequested(message) }
    signal notifyRequested(string message)
}
