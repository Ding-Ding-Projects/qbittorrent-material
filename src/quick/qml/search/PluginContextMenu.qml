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
    \qmltype PluginContextMenu
    \brief Right-click menu for the installed-plugins table.

    Set \l pluginIds (the selected plugin ids) and \l firstEnabled (the enabled
    state of the first selection, used to seed the checkable "Enabled" item)
    before \c open().
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search plugin actions")

    /*! Selected plugin ids the actions operate on. */
    property var pluginIds: []

    /*! Enabled state of the first selected plugin. */
    property bool firstEnabled: false

    Material.elevation: 8

    onAboutToShow: Log.debug("search", "Plugin context menu for " + pluginIds.length + " plugin(s)")

    MenuItem {
        text: qsTr("Enabled")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: root.firstEnabled
        onTriggered: {
            Log.info("search", "Context: set enabled=" + checked + " for " + root.pluginIds.length + " plugin(s)")
            SearchController.enablePlugins(root.pluginIds, checked)
        }
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("Uninstall")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.deleteIcon; size: 18; color: Theme.color("error") }
            Label { text: qsTr("Uninstall"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Context: uninstall " + root.pluginIds.length + " plugin(s)")
            SearchController.uninstallPlugins(root.pluginIds)
        }
    }
}
