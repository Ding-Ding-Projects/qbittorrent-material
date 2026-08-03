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
    \qmltype QueueSubMenu
    \brief "Queue ►" submenu — move selected torrents within the download queue.

    Delegates to \c TransferController queue-move verbs (\c queueTop / \c queueUp
    / \c queueDown / \c queueBottom). The moves are no-ops when the session
    queueing system is disabled, so the submenu is always available.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search queue actions")

    title: qsTr("Queue")

    MenuItem {
        text: qsTr("Move to top")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.vertical_align_top; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Queue → Move to top")
            TransferController.queueTop()
        }
    }

    MenuItem {
        text: qsTr("Move up")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.arrow_upward; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Queue → Move up")
            TransferController.queueUp()
        }
    }

    MenuItem {
        text: qsTr("Move down")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.arrow_downward; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Queue → Move down")
            TransferController.queueDown()
        }
    }

    MenuItem {
        text: qsTr("Move to bottom")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.vertical_align_bottom; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Queue → Move to bottom")
            TransferController.queueBottom()
        }
    }
}
