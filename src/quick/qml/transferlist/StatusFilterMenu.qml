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
    \qmltype StatusFilterMenu
    \brief Context menu for the status / tracker-status filter panels.

    Offers the four bulk actions that operate on the currently \e visible
    torrents (those passing the active filters), matching qBittorrent's
    \c StatusFilterWidget context menu. Because \c TransferController acts on its
    \c selectedIds, each action first sets the selection to \c proxy.visibleIds()
    and then invokes the corresponding verb.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search status actions")

    /*! The shared \c TorrentFilterProxyModel whose visible rows are the target. */
    property var proxy: null

    modal: false
    Material.elevation: Spacing.elevationMenu

    // Point the controller selection at every visible torrent, then run `verb`.
    function _actOnVisible(verb) {
        if (!root.proxy)
            return;
        const ids = root.proxy.visibleIds();
        if (!ids || ids.length === 0) {
            Log.debug("ui", "Status filter menu: no visible torrents to act on");
            return;
        }
        TransferController.selectedIds = ids;
        verb();
    }

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
        onTriggered: {
            Log.info("ui", "Status filter menu → Start visible")
            root._actOnVisible(() => TransferController.start())
        }
    }

    MenuItem {
        text: qsTr("Force start torrents")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.bolt; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Status filter menu → Force start visible")
            root._actOnVisible(() => TransferController.forceStart())
        }
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
        onTriggered: {
            Log.info("ui", "Status filter menu → Stop visible")
            root._actOnVisible(() => TransferController.stop())
        }
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
        onTriggered: {
            Log.info("ui", "Status filter menu → Remove visible")
            root._actOnVisible(() => TransferController.deleteSelected(false))
        }
    }
}
