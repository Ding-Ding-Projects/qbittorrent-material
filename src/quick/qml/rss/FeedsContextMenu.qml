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
    \qmltype FeedsContextMenu
    \brief Right-click menu for the RSS feeds tree.

    The hosting \c RSSTab sets the state flags (\l isFeed / \l isFolder /
    \l isSticky / \l hasSelection) before calling \c popup(); the menu emits a
    \c request* signal per action which \c RSSTab wires to \c RSSController and
    the relevant dialogs.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search feed actions")

    property string currentPath: ""
    property bool isFeed: false
    property bool isFolder: false
    property bool isSticky: false
    property bool hasSelection: true

    signal requestUpdate()
    signal requestMarkRead()
    signal requestRename()
    signal requestEditFeed()
    signal requestDelete()
    signal requestNewFolder()
    signal requestNewSubscription()
    signal requestCopyUrl()
    signal requestUpdateAll()

    Material.elevation: 8

    onAboutToShow: Log.debug("rss", "FeedsContextMenu opened (feed=" + isFeed + " folder=" + isFolder + " sticky=" + isSticky + ")")

    // ---- With a selection --------------------------------------------------
    MenuItem {
        text: qsTr("Update")
        visible: (root.hasSelection) && root.matches(text)
        height: visible ? implicitHeight : 0
        icon.source: ""
        onTriggered: { Log.info("rss", "Menu: Update"); root.requestUpdate() }
    }
    MenuItem {
        text: qsTr("Mark items read")
        visible: (root.hasSelection) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Mark items read"); root.requestMarkRead() }
    }

    MenuSeparator { visible: root.hasSelection && !root.isSticky }

    MenuItem {
        text: qsTr("Rename...")
        visible: (root.hasSelection && !root.isSticky) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Rename"); root.requestRename() }
    }
    MenuItem {
        text: qsTr("Feed options...")
        visible: (root.isFeed) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Feed options"); root.requestEditFeed() }
    }
    MenuItem {
        text: qsTr("Delete")
        visible: (root.hasSelection && !root.isSticky) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Delete"); root.requestDelete() }
    }

    MenuSeparator { visible: root.isFolder }

    MenuItem {
        text: qsTr("New folder...")
        visible: (root.isFolder || !root.hasSelection) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: New folder"); root.requestNewFolder() }
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("New subscription...")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: New subscription"); root.requestNewSubscription() }
    }

    MenuSeparator { visible: root.isFeed }

    MenuItem {
        text: qsTr("Copy feed URL")
        visible: (root.isFeed) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Copy feed URL"); root.requestCopyUrl() }
    }

    // ---- Nothing selected --------------------------------------------------
    MenuItem {
        text: qsTr("Update all feeds")
        visible: (!root.hasSelection) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Update all feeds"); root.requestUpdateAll() }
    }
}
