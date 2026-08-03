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
    \qmltype RulesListContextMenu
    \brief Right-click menu for the auto-download rules list.

    \l selectionCount governs which entries are shown; the menu emits a
    \c request* signal per action that the dialog wires to the
    \c RuleEditorController.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search rule actions")

    property int selectionCount: 0

    signal requestAdd()
    signal requestDelete()
    signal requestRename()
    signal requestClone()
    signal requestClearEpisodes()

    Material.elevation: 8

    onAboutToShow: Log.debug("rss", "RulesListContextMenu opened (selection=" + selectionCount + ")")

    MenuItem {
        text: qsTr("Add new rule...")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "RulesMenu: Add"); root.requestAdd() }
    }

    MenuItem {
        text: root.selectionCount > 1 ? qsTr("Delete selected rules") : qsTr("Delete rule")
        visible: (root.selectionCount >= 1) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "RulesMenu: Delete"); root.requestDelete() }
    }

    MenuSeparator { visible: root.selectionCount === 1 }

    MenuItem {
        text: qsTr("Rename rule...")
        visible: (root.selectionCount === 1) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "RulesMenu: Rename"); root.requestRename() }
    }

    MenuItem {
        text: qsTr("Clone rule...")
        visible: (root.selectionCount === 1) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "RulesMenu: Clone"); root.requestClone() }
    }

    MenuSeparator { visible: root.selectionCount >= 1 }

    MenuItem {
        text: qsTr("Clear downloaded episodes...")
        visible: (root.selectionCount >= 1) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("rss", "RulesMenu: Clear downloaded episodes"); root.requestClearEpisodes() }
    }
}
