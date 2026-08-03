/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qBittorrent

/*! A small, keyboard-accessible Material title bar for the frameless window. */
Rectangle {
    id: root

    required property var window

    readonly property bool maximized: root.window
        && root.window.visibility === Window.Maximized

    height: 40
    color: Theme.color("surfaceContainer")
    border.width: 1
    border.color: Theme.color("outlineVariant")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        spacing: 8

        MDIcon {
            icon: Icons.download
            size: 20
            color: Theme.color("primary")
        }

        Label {
            Layout.fillWidth: true
            text: root.window ? root.window.title : qsTr("qBittorrent")
            color: Theme.color("onSurface")
            font: Typography.titleSmall
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        AbstractButton {
            id: minimizeButton
            Layout.preferredWidth: 42
            Layout.fillHeight: true
            Accessible.name: qsTr("Minimize window")
            Accessible.description: qsTr("Minimize the qBittorrent window")
            background: Rectangle {
                color: minimizeButton.visualFocus || minimizeButton.hovered
                    ? Theme.color("hoverStrong") : "transparent"
                border.width: minimizeButton.visualFocus ? 2 : 0
                border.color: Theme.color("primary")
            }
            contentItem: MDIcon {
                anchors.centerIn: parent
                icon: Icons.remove
                size: 18
                color: Theme.color("onSurface")
            }
            onClicked: root.window.showMinimized()
        }

        AbstractButton {
            id: maximizeButton
            Layout.preferredWidth: 42
            Layout.fillHeight: true
            Accessible.name: root.maximized ? qsTr("Restore window") : qsTr("Maximize window")
            Accessible.description: root.maximized
                ? qsTr("Restore the qBittorrent window")
                : qsTr("Maximize the qBittorrent window")
            background: Rectangle {
                color: maximizeButton.visualFocus || maximizeButton.hovered
                    ? Theme.color("hoverStrong") : "transparent"
                border.width: maximizeButton.visualFocus ? 2 : 0
                border.color: Theme.color("primary")
            }
            contentItem: MDIcon {
                anchors.centerIn: parent
                name: root.maximized ? "filter_none" : "crop_square"
                size: 17
                color: Theme.color("onSurface")
            }
            onClicked: {
                if (root.maximized)
                    root.window.showNormal()
                else
                    root.window.showMaximized()
            }
        }

        AbstractButton {
            id: closeButton
            Layout.preferredWidth: 48
            Layout.fillHeight: true
            Accessible.name: qsTr("Close window")
            Accessible.description: qsTr("Close qBittorrent")
            background: Rectangle {
                color: closeButton.hovered ? Theme.color("error") : "transparent"
                border.width: closeButton.visualFocus ? 2 : 0
                border.color: Theme.color("error")
            }
            contentItem: MDIcon {
                anchors.centerIn: parent
                icon: Icons.close
                size: 18
                color: closeButton.hovered ? Theme.color("onError") : Theme.color("onSurface")
            }
            onClicked: root.window.close()
        }
    }

    MouseArea {
        id: dragArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 132
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        z: -1
        onPressed: root.window.startSystemMove()
        onDoubleClicked: {
            if (root.maximized)
                root.window.showNormal()
            else
                root.window.showMaximized()
        }
    }
}
