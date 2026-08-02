/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qBittorrent

/*! Non-blocking, focus-preserving startup delight. The controller performs one
    fresh 10% draw per eligible launch and supplies only bundled local assets. */
Item {
    id: root
    anchors.fill: parent
    visible: Experience.startupDishVisible
    z: 9800

    readonly property var dish: Experience.startupDish
    readonly property string dishName: I18n.language === I18n.English
        ? (dish.english || "")
        : (I18n.language === I18n.Cantonese
            ? (dish.cantonese || "")
            : (dish.english || "") + " · " + (dish.cantonese || ""))
    readonly property string dishAlt: I18n.language === I18n.English
        ? (dish.altEnglish || dishName)
        : (I18n.language === I18n.Cantonese
            ? (dish.altCantonese || dishName)
            : (dish.altEnglish || "") + " · " + (dish.altCantonese || ""))

    onVisibleChanged: if (visible) dismissTimer.restart()

    Timer {
        id: dismissTimer
        interval: 8000
        repeat: false
        onTriggered: Experience.dismissStartupDish()
    }

    Rectangle {
        id: card
        objectName: "dimSumStartupSurprise"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Spacing.lg
        anchors.bottomMargin: Spacing.lg
        width: Math.min(430, Math.max(320, parent.width - Spacing.xl * 2))
        height: 184
        radius: Spacing.radiusCard
        color: Theme.color("surfaceContainerHigh")
        border.width: 1
        border.color: Theme.color("outlineVariant")
        opacity: root.visible ? 1 : 0
        Accessible.name: qsTr("Dim sum surprise: %1").arg(root.dishName)
        Accessible.description: root.dishAlt
        Accessible.role: Accessible.Pane

        Behavior on opacity {
            NumberAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionBase }
        }

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.margins: Spacing.md
            spacing: Spacing.md

            Image {
                Layout.preferredWidth: 118
                Layout.preferredHeight: 138
                Layout.alignment: Qt.AlignVCenter
                source: root.dish.image || ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 360
                sourceSize.height: 360
                asynchronous: true
                Accessible.name: root.dishAlt
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Spacing.xs

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Today’s tiny steamer-basket hello")
                        font: Typography.labelLarge
                        color: Theme.color("primary")
                        elide: Text.ElideRight
                    }
                    IconButton {
                        symbol: Icons.close
                        tooltip: qsTr("Dismiss dim sum surprise")
                        onClicked: Experience.dismissStartupDish()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.dishName
                    font: Typography.titleLarge
                    color: Theme.color("onSurface")
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("A 10% startup surprise. It never blocks the app, steals focus, or fetches anything.")
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
