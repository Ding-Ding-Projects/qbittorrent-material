/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype AboutDialog
    \brief Material rebuild of the legacy \c AboutDialog.

    A tabbed "About" dialog (About / Authors / Special Thanks / Translation /
    License / Changelog). The License tab renders the bundled GPL notice supplied through
    the application context from \c :/html/gpl.html, rather than pasting it
    inline in QML. External links are opened in the system browser via
    \c Qt.openUrlExternally.
*/
Dialog {
    id: root

    // The C++ context loads the QRC once before Main.qml is instantiated. Keep
    // an explicit visible fallback if a packaging regression omits the asset.
    readonly property string licenseText: ApplicationInfo.licenseText.length > 0
                                       ? ApplicationInfo.licenseText
                                       : qsTr("Could not load the bundled license notice.")
    // Used by deterministic captures; regular invocations retain the About tab.
    property int initialTab: 0

    title: qsTr("About qBittorrent")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(860, (parent ? parent.width : 860) * 0.94)
    height: Math.min(560, (parent ? parent.height : 560) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("ui", "AboutDialog opened")
        tabBar.currentIndex = Math.max(0, Math.min(tabBar.count - 1, root.initialTab))
    }
    onClosed: Log.debug("ui", "AboutDialog closed")

    // A caption + rich-text link row used in the About tab.
    component LinkRow: RowLayout {
        property string caption: ""
        property string url: ""

        Layout.fillWidth: true
        spacing: Spacing.md

        Label {
            text: caption
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
        }

        Label {
            Layout.fillWidth: true
            textFormat: Text.RichText
            text: "<a href=\"" + url + "\">" + url + "</a>"
            font: Typography.bodyMedium
            color: Theme.color("onSurface")
            onLinkActivated: (link) => {
                Log.info("ui", "AboutDialog opening external link " + link)
                Qt.openUrlExternally(link)
            }
        }
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ColumnLayout {
        spacing: Spacing.sm

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            Material.background: "transparent"

            onCurrentIndexChanged: Log.debug("ui", "AboutDialog tab -> " + currentIndex)

            TabButton { text: qsTr("About") }
            TabButton { text: qsTr("Authors") }
            TabButton { text: qsTr("Special Thanks") }
            TabButton { text: qsTr("Translation") }
            TabButton { text: qsTr("License") }
            TabButton { text: qsTr("Changelog") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ---- About ------------------------------------------------------
            ScrollView {
                id: aboutScroll
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: aboutScroll.availableWidth
                    spacing: Spacing.md

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.lg

                        Image {
                            source: "qrc:/branding/logo-mark.svg"
                            sourceSize.width: 64
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64

                            // Graceful fallback when the artwork is not bundled yet.
                            MDIcon {
                                anchors.centerIn: parent
                                visible: parent.status !== Image.Ready
                                icon: Icons.info
                                size: 56
                                color: Theme.color("primary")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Spacing.xs

                            Label {
                                // Product name — a brand string, intentionally not translated.
                                text: "qBittorrent Material"
                                font: Typography.titleLarge
                                color: Theme.color("onSurface")
                            }

                            Label {
                                text: qsTr("Version %1").arg(Qt.application.version.length > 0
                                        ? Qt.application.version : qsTr("unknown"))
                                font: Typography.bodyMedium
                                color: Theme.color("onSurfaceVariant")
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("An advanced BitTorrent client programmed in C++, based on the Qt toolkit and libtorrent-rasterbar.")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurface")
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("Copyright %1 2006-2026 The qBittorrent project").arg("©")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }

                    LinkRow { caption: qsTr("Home Page:"); url: "https://www.qbittorrent.org" }
                    LinkRow { caption: qsTr("Forum:"); url: "https://forum.qbittorrent.org" }
                    LinkRow { caption: qsTr("Bug Tracker:"); url: "https://bugs.qbittorrent.org" }
                }
            }

            // ---- Authors ----------------------------------------------------
            ScrollView {
                id: authorsScroll
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: authorsScroll.availableWidth
                    spacing: Spacing.md

                    MaterialCard {
                        title: qsTr("Current maintainer")
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Spacing.xs

                            Label {
                                text: qsTr("Name: %1").arg("Sledgehammer999")
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                            }
                            Label {
                                text: qsTr("Nationality: %1").arg(qsTr("Greece"))
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                            }
                            Label {
                                Layout.fillWidth: true
                                textFormat: Text.RichText
                                text: qsTr("E-mail: %1").arg("<a href=\"mailto:sledgehammer999@qbittorrent.org\">sledgehammer999@qbittorrent.org</a>")
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                                onLinkActivated: (link) => Qt.openUrlExternally(link)
                            }
                        }
                    }

                    MaterialCard {
                        title: qsTr("Original author")
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Spacing.xs

                            Label {
                                text: qsTr("Name: %1").arg("Christophe Dumez")
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                            }
                            Label {
                                text: qsTr("Nationality: %1").arg(qsTr("France"))
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                            }
                            Label {
                                Layout.fillWidth: true
                                textFormat: Text.RichText
                                text: qsTr("E-mail: %1").arg("<a href=\"mailto:chris@qbittorrent.org\">chris@qbittorrent.org</a>")
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                                onLinkActivated: (link) => Qt.openUrlExternally(link)
                            }
                        }
                    }
                }
            }

            // ---- Special Thanks ---------------------------------------------
            ScrollView {
                id: thanksScroll
                clip: true
                contentWidth: availableWidth

                Label {
                    width: thanksScroll.availableWidth
                    wrapMode: Text.WordWrap
                    text: qsTr("Thanks to all the people who contributed code, translations, artwork, documentation, bug reports and financial support to qBittorrent over the years. This Material rewrite stands on the shoulders of the original qBittorrent project and its libraries: Qt, libtorrent-rasterbar, Boost, OpenSSL and zlib.")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurface")
                }
            }

            // ---- Translation ------------------------------------------------
            ScrollView {
                id: translationScroll
                clip: true
                contentWidth: availableWidth

                Label {
                    width: translationScroll.availableWidth
                    wrapMode: Text.WordWrap
                    text: qsTr("qBittorrent is translated into many languages by volunteers around the world. This build also ships a playful Cantonese / bilingual mode. Thank you to every translator who helped make qBittorrent speak your language.")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurface")
                }
            }

            // ---- License ----------------------------------------------------
            ScrollView {
                id: licenseScroll
                clip: true
                contentWidth: availableWidth
                // Keep the scrollable extent synchronized with the rich-text
                // label's implicit height.
                contentHeight: licenseLabel.implicitHeight

                Label {
                    id: licenseLabel
                    width: licenseScroll.availableWidth
                    wrapMode: Text.WordWrap
                    textFormat: Text.RichText
                    text: root.licenseText
                    font: Typography.bodyMedium
                    color: Theme.color("onSurface")
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }

            // ---- Changelog -------------------------------------------------
            ChangelogPage { }
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Close")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: {
                Log.debug("ui", "AboutDialog Close clicked")
                root.close()
            }
        }
    }
}
