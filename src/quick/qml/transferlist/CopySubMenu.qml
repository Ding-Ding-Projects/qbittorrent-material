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
import qBittorrent

/*!
    \qmltype CopySubMenu
    \brief "Copy ►" submenu of the transfer-list row context menu.

    Copies attributes of the current selection to the clipboard through the
    \c TransferController clipboard verbs (\c copyName, \c copyHash — info hash v1
    with a v2 fallback — and \c copyMagnet).

    Menu items carry a leading Material Symbols glyph rendered by an anchored
    \c MDIcon; the item text is inset via \c leftPadding so it never overlaps.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search copy actions")

    title: qsTr("Copy")

    MenuItem {
        text: qsTr("Name")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.content_copy; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Copy → Name")
            TransferController.copyName()
        }
    }

    MenuItem {
        text: qsTr("Info hash")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.tag; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Copy → Info hash")
            TransferController.copyHash()
        }
    }

    MenuItem {
        text: qsTr("Magnet link")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.link; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Copy → Magnet link")
            TransferController.copyMagnet()
        }
    }
}
