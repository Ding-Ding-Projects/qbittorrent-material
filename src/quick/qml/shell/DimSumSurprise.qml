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
    fresh 10% draw per eligible launch and exposes only a verified public-catalog
    photo already cached beneath the application's data directory. */
Item {
    id: root
    anchors.fill: parent
    visible: Experience.startupDishVisible && root.hasVerifiedDish
    z: 9800

    readonly property var dish: Experience.startupDish || ({})
    readonly property var dishNames: dish.name || ({})
    readonly property var dishAlternatives: dish.alt || ({})
    readonly property string englishName: String(dishNames.en || "")
    readonly property string cantoneseName: String(dishNames.zhHant || "")
    readonly property string englishAlternative: String(dishAlternatives.en || englishName)
    readonly property string cantoneseAlternative: String(dishAlternatives.yue || cantoneseName)
    readonly property string localImageUrl: String(dish.image || "")
    readonly property string publicPhotoUrl: String(dish.publicPhotoUrl || "")
    readonly property string catalogRevision: String(dish.catalogRevision || "")
    readonly property string dishName: I18n.language === I18n.English
        ? englishName
        : (I18n.language === I18n.Cantonese
            ? cantoneseName
            : englishName + " · " + cantoneseName)
    readonly property string dishAlt: I18n.language === I18n.English
        ? englishAlternative
        : (I18n.language === I18n.Cantonese
            ? cantoneseAlternative
            : englishAlternative + " · " + cantoneseAlternative)
    readonly property bool hasVerifiedDish: englishName.length > 0
        && cantoneseName.length > 0
        && localImageUrl.length > 0
        && publicPhotoUrl.length > 0
        && catalogRevision.length > 0
        && dishImage.status === Image.Ready

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
        anchors.rightMargin: Spacing.md
        anchors.bottomMargin: Spacing.md
        readonly property bool compact: width < 360
        width: Math.min(430, Math.max(0, parent.width - Spacing.md * 2))
        height: Math.min(Math.max(0, parent.height - Spacing.md * 2),
            cardContent.implicitHeight + Spacing.md * 2)
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

        ScrollView {
            id: cardScroll
            anchors.fill: parent
            anchors.margins: Spacing.md
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            GridLayout {
                id: cardContent
                width: cardScroll.availableWidth
                columns: card.compact ? 1 : 2
                columnSpacing: Spacing.md
                rowSpacing: Spacing.sm

                Image {
                    id: dishImage
                    Layout.row: 0
                    Layout.column: 0
                    Layout.preferredWidth: card.compact
                        ? Math.min(180, cardScroll.availableWidth) : 118
                    Layout.preferredHeight: card.compact ? 104 : 138
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    source: root.localImageUrl
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 360
                    sourceSize.height: 360
                    asynchronous: true
                    visible: status === Image.Ready
                    Accessible.name: root.dishAlt
                    Accessible.role: Accessible.Graphic
                    onStatusChanged: {
                        if (status === Image.Error && Experience.startupDishVisible)
                            Experience.dismissStartupDish()
                    }
                }

                ColumnLayout {
                    Layout.row: card.compact ? 1 : 0
                    Layout.column: card.compact ? 0 : 1
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
                            wrapMode: Text.WordWrap
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
                        text: qsTr("A verified public catalog photo cached in application data. This 10% startup surprise never blocks the app or steals focus.")
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        id: startupPhotoLink
                        Layout.fillWidth: true
                        text: qsTr("Open public dim sum photo")
                        flat: true
                        focusPolicy: Qt.StrongFocus
                        implicitHeight: Math.max(40,
                            startupPhotoLinkLabel.implicitHeight + topPadding + bottomPadding)
                        Accessible.name: text
                        Accessible.description: qsTr("Open the public catalog photo for %1")
                            .arg(root.dishName)
                        contentItem: Label {
                            id: startupPhotoLinkLabel
                            text: startupPhotoLink.text
                            font: startupPhotoLink.font
                            color: startupPhotoLink.enabled
                                ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                        }
                        onClicked: Qt.openUrlExternally(root.publicPhotoUrl)
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Catalog revision %1").arg(root.catalogRevision)
                        font: Typography.labelSmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
