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
    \qmltype SearchTabContextMenu
    \brief Right-click menu for a search results TAB button.

    Set \l tabId and \l ongoing before \c popup(). When the tab is running the
    first item is "Stop search"; otherwise it is "Refresh tab".
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search tab actions")

    /*! The SearchController tab id this menu targets. */
    property int tabId: -1

    /*! Whether that tab's search is currently running. */
    property bool ongoing: false

    Material.elevation: 8

    onAboutToShow: Log.debug("search", "Tab context menu for tab " + tabId + " ongoing=" + ongoing)

    MenuItem {
        text: root.ongoing ? qsTr("Stop search") : qsTr("Refresh tab")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon {
                icon: root.ongoing ? Icons.pause : Icons.refresh
                size: 18
                color: Theme.color("onSurface")
            }
            Label {
                text: root.ongoing ? qsTr("Stop search") : qsTr("Refresh tab")
                font: Typography.bodyMedium
                color: Theme.color("onSurface")
            }
        }
        onTriggered: {
            if (root.ongoing) {
                Log.info("search", "Tab menu: stop search tab " + root.tabId)
                SearchController.stopSearch(root.tabId)
            } else {
                Log.info("search", "Tab menu: refresh tab " + root.tabId)
                SearchController.refreshTab(root.tabId)
            }
        }
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("Close tab")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.close; size: 18; color: Theme.color("onSurface") }
            Label { text: qsTr("Close tab"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Tab menu: close tab " + root.tabId)
            SearchController.closeTab(root.tabId)
        }
    }

    MenuItem {
        text: qsTr("Close all tabs")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.deleteIcon; size: 18; color: Theme.color("onSurface") }
            Label { text: qsTr("Close all tabs"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Tab menu: close all tabs")
            SearchController.closeAllTabs()
        }
    }
}
