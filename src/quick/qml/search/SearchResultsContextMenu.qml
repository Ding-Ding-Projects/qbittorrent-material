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
    \qmltype SearchResultsContextMenu
    \brief Right-click menu for the search results table.

    Set \l tabId and \l rows (a list of proxy row indices, usually the current
    selection) before calling \c open()/\c popup(). Actions are delegated to the
    \c SearchController.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search result actions")

    /*! The owning SearchController tab id. */
    property int tabId: -1

    /*! The proxy row indices this menu acts on. */
    property var rows: []

    Material.elevation: 8

    onAboutToShow: Log.debug("search", "Results context menu for " + rows.length + " row(s)")

    MenuItem {
        text: qsTr("Open download window")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        icon.source: ""
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.download; size: 18; color: Theme.color("onSurface") }
            Label { text: qsTr("Open download window"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Context: open download window")
            for (var i = 0; i < root.rows.length; ++i)
                SearchController.downloadTorrent(root.tabId, root.rows[i], SearchController.ShowDialog)
        }
    }

    MenuItem {
        text: qsTr("Download")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.download; size: 18; color: Theme.color("primary") }
            Label { text: qsTr("Download"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Context: download")
            for (var i = 0; i < root.rows.length; ++i)
                SearchController.downloadTorrent(root.tabId, root.rows[i], SearchController.SkipDialog)
        }
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("Open description page")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        contentItem: Row {
            spacing: Spacing.sm
            MDIcon { icon: Icons.open_in_new; size: 18; color: Theme.color("onSurface") }
            Label { text: qsTr("Open description page"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
        }
        onTriggered: {
            Log.info("search", "Context: open description page(s)")
            SearchController.openDescriptionPages(root.tabId, root.rows)
        }
    }

    Menu {
        title: qsTr("Copy")
        Material.elevation: 8

        MenuItem {
            text: qsTr("Name")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            contentItem: Row {
                spacing: Spacing.sm
                MDIcon { icon: Icons.content_copy; size: 18; color: Theme.color("onSurface") }
                Label { text: qsTr("Name"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
            }
            onTriggered: {
                Log.debug("search", "Context: copy names")
                SearchController.copyNames(root.tabId, root.rows)
            }
        }
        MenuItem {
            text: qsTr("Download link")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            contentItem: Row {
                spacing: Spacing.sm
                MDIcon { icon: Icons.link; size: 18; color: Theme.color("onSurface") }
                Label { text: qsTr("Download link"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
            }
            onTriggered: {
                Log.debug("search", "Context: copy download links")
                SearchController.copyDownloadLinks(root.tabId, root.rows)
            }
        }
        MenuItem {
            text: qsTr("Description page URL")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            contentItem: Row {
                spacing: Spacing.sm
                MDIcon { icon: Icons.open_in_new; size: 18; color: Theme.color("onSurface") }
                Label { text: qsTr("Description page URL"); font: Typography.bodyMedium; color: Theme.color("onSurface") }
            }
            onTriggered: {
                Log.debug("search", "Context: copy description URLs")
                SearchController.copyDescriptionPages(root.tabId, root.rows)
            }
        }
    }
}
