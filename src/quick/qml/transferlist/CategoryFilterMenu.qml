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
    \qmltype CategoryFilterMenu
    \brief Context menu for the Categories sidebar panel.

    Category management (add / add subcategory / edit / remove / remove unused) is
    bubbled up as signals so the owning \l CategoryFilterTree can host the shared
    \c CategoryDialog and persist via \c Session. The bulk run/stop/remove actions
    operate on the currently visible torrents through the shared \l proxy.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search category actions")

    /*! The shared \c TorrentFilterProxyModel (target of the bulk actions). */
    property var proxy: null

    /*! The right-clicked category (empty for the "All" / "Uncategorized" rows). */
    property string category: ""

    /*! Whether the right-clicked row is a real (removable/editable) category. */
    property bool isReal: false

    signal addCategoryRequested()
    signal addSubcategoryRequested(string parentCategory)
    signal editCategoryRequested(string category)
    signal removeCategoryRequested(string category)

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
        text: qsTr("Add category…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.add; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Category menu → Add category"); root.addCategoryRequested() }
    }

    MenuItem {
        text: qsTr("Add subcategory…")
        visible: (root.isReal) && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.category; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Category menu → Add subcategory"); root.addSubcategoryRequested(root.category) }
    }

    MenuItem {
        text: qsTr("Edit category…")
        visible: (root.isReal) && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.edit; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Category menu → Edit category"); root.editCategoryRequested(root.category) }
    }

    MenuItem {
        text: qsTr("Remove category")
        visible: (root.isReal) && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.deleteIcon; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("error")
        }
        onTriggered: { Log.info("ui", "Category menu → Remove category"); root.removeCategoryRequested(root.category) }
    }

    MenuItem {
        text: qsTr("Remove unused categories")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            if (typeof Session.removeUnusedCategories === "function") {
                Log.info("ui", "Category menu → Remove unused categories")
                Session.removeUnusedCategories()
            } else {
                Log.warning("ui", "Remove unused categories: Session.removeUnusedCategories is not available")
            }
        }
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
        onTriggered: { Log.info("ui", "Category menu → Start visible"); root._actOnVisible(() => TransferController.start()) }
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
        onTriggered: { Log.info("ui", "Category menu → Stop visible"); root._actOnVisible(() => TransferController.stop()) }
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
        onTriggered: { Log.info("ui", "Category menu → Remove visible"); root._actOnVisible(() => TransferController.deleteSelected(false)) }
    }
}
