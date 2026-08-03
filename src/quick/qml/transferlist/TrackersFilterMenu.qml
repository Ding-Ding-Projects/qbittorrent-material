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
    \qmltype TrackersFilterMenu
    \brief Context menu for the Trackers sidebar panel.

    For a tracker-host row it offers "Remove tracker" (bubbled up as
    \l removeTrackerRequested for the owning \l TrackersFilterList to apply). The
    bulk run/stop/remove actions operate on the currently visible torrents through
    the shared \l proxy.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search tracker actions")

    /*! The shared \c TorrentFilterProxyModel (target of the bulk actions). */
    property var proxy: null

    /*! The right-clicked tracker host (empty for the special rows). */
    property string host: ""

    /*! Whether the right-clicked row is a tracker host. */
    property bool isHost: false

    signal removeTrackerRequested(string host)

    modal: false
    Material.elevation: Spacing.elevationMenu

    function _actOnVisible(verb) {
        if (!root.proxy)
            return;
        const ids = root.proxy.visibleIds();
        if (!ids || ids.length === 0)
            return;
        TransferController.selectedIds = ids;
        verb();
    }

    MenuItem {
        text: qsTr("Remove tracker from all torrents")
        visible: (root.isHost) && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.deleteIcon; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("error")
        }
        onTriggered: { Log.info("ui", "Tracker menu → Remove tracker"); root.removeTrackerRequested(root.host) }
    }

    MenuSeparator { visible: root.isHost }

    MenuItem {
        text: qsTr("Start torrents")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.play_arrow; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Tracker menu → Start visible"); root._actOnVisible(() => TransferController.start()) }
    }

    MenuItem {
        text: qsTr("Stop torrents")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.pause; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Tracker menu → Stop visible"); root._actOnVisible(() => TransferController.stop()) }
    }

    MenuItem {
        text: qsTr("Remove torrents")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.deleteIcon; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("error")
        }
        onTriggered: { Log.info("ui", "Tracker menu → Remove visible"); root._actOnVisible(() => TransferController.deleteSelected(false)) }
    }
}
