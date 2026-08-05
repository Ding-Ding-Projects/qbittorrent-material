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
    \qmltype PluginSourceDialog
    \brief The two-step "where does the plugin come from" picker: a local file
           or a web link.

    Emits \c askForLocalFile() or \c askForUrl() (and closes); the parent wires
    those to an OS file dialog and to \l NewPluginUrlDialog respectively.
*/
Dialog {
    id: root

    title: qsTr("Plugin source")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(400, (parent ? parent.width : 400) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    /*! The user chose to install from a local file. */
    signal askForLocalFile()

    /*! The user chose to install from a web link. */
    signal askForUrl()

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: Log.debug("search", "PluginSourceDialog opened")

    contentItem: ColumnLayout {
        spacing: Spacing.lg

        Label {
            text: qsTr("Search plugin source:")
            font: Typography.titleMedium
            color: Theme.color("onSurface")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.md

            Button {
                Layout.fillWidth: true
                text: qsTr("Local file")
                contentItem: ColumnLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.insert_drive_file; size: 24; color: Theme.color("primary"); Layout.alignment: Qt.AlignHCenter }
                    Label { text: qsTr("Local file"); font: Typography.labelLarge; color: Theme.color("onSurface"); Layout.alignment: Qt.AlignHCenter }
                }
                onClicked: {
                    Log.info("search", "Plugin source: local file")
                    root.askForLocalFile()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: qsTr("Web link")
                contentItem: ColumnLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.link; size: 24; color: Theme.color("primary"); Layout.alignment: Qt.AlignHCenter }
                    Label { text: qsTr("Web link"); font: Typography.labelLarge; color: Theme.color("onSurface"); Layout.alignment: Qt.AlignHCenter }
                }
                onClicked: {
                    Log.info("search", "Plugin source: web link")
                    root.askForUrl()
                    root.close()
                }
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }
}
