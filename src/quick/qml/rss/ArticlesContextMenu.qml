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
    \qmltype ArticlesContextMenu
    \brief Right-click menu for the articles list.

    The host sets \l hasTorrent / \l hasLink before \c popup(); items hide when
    their action is unavailable, and the menu is not shown at all when neither
    applies.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search article actions")

    property bool hasTorrent: false
    property bool hasLink: false

    signal requestDownload()
    signal requestOpenUrl()

    Material.elevation: 8

    onAboutToShow: Log.debug("rss", "ArticlesContextMenu opened (torrent=" + hasTorrent + " link=" + hasLink + ")")

    MenuItem {
        text: qsTr("Download torrent")
        visible: (root.hasTorrent) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Download torrent"); root.requestDownload() }
    }

    MenuItem {
        text: qsTr("Open news URL")
        visible: (root.hasLink) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "Menu: Open news URL"); root.requestOpenUrl() }
    }
}
