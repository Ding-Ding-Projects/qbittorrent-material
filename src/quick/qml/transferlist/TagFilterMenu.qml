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
    \qmltype TagFilterMenu
    \brief Context menu for the Tags sidebar panel.

    Tag management (add / remove / remove unused) is bubbled up as signals so the
    owning \l TagFilterList can host the shared \c AddTagDialog and persist via
    \c Session. The bulk run/stop/remove actions operate on the currently visible
    torrents through the shared \l proxy.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search tag actions")

    /*! The shared \c TorrentFilterProxyModel (target of the bulk actions). */
    property var proxy: null

    /*! The right-clicked tag (empty for the "All" / "Untagged" rows). */
    property string tag: ""

    /*! Whether the right-clicked row is a real (removable) tag. */
    property bool isReal: false

    signal addTagRequested()
    signal removeTagRequested(string tag)
    signal removeUnusedTagsRequested()

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
        text: qsTr("Add tag…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.add; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Tag menu → Add tag"); root.addTagRequested() }
    }

    MenuItem {
        text: qsTr("Remove tag")
        visible: (root.isReal) && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.deleteIcon; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("error")
        }
        onTriggered: { Log.info("ui", "Tag menu → Remove tag"); root.removeTagRequested(root.tag) }
    }

    MenuItem {
        text: qsTr("Remove unused tags")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Tag menu → Remove unused tags"); root.removeUnusedTagsRequested() }
    }

    MenuSeparator {}

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
        onTriggered: { Log.info("ui", "Tag menu → Start visible"); root._actOnVisible(() => TransferController.start()) }
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
        onTriggered: { Log.info("ui", "Tag menu → Stop visible"); root._actOnVisible(() => TransferController.stop()) }
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
        onTriggered: { Log.info("ui", "Tag menu → Remove visible"); root._actOnVisible(() => TransferController.deleteSelected(false)) }
    }
}
