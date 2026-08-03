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
    ToolbarContextMenu — the right-click menu on the top toolbar offering an
    exclusive choice of button text position. Emits \c positionSelected with the
    chosen Qt::ToolButtonStyle-ordered index (0 icons only … 4 follow style).
*/
SearchableMenu {
    id: menu

    /// The currently active text position (drives the checkmarks).
    property int currentPosition: 0

    /// Emitted when the user picks a text position.
    signal positionSelected(int position)

    searchPlaceholder: qsTr("Search toolbar options")
    searchAccessibleName: qsTr("Search toolbar text-position options")
    onOpened: Log.debug("ui", "Toolbar text-position menu opened")

    ButtonGroup {
        id: styleGroup
        exclusive: true
    }

    MenuItem {
        text: qsTr("Icons Only")
        visible: menu.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.currentPosition === 0
        ButtonGroup.group: styleGroup
        onTriggered: menu.choose(0)
    }
    MenuItem {
        text: qsTr("Text Only")
        visible: menu.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.currentPosition === 1
        ButtonGroup.group: styleGroup
        onTriggered: menu.choose(1)
    }
    MenuItem {
        text: qsTr("Text Alongside Icons")
        visible: menu.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.currentPosition === 2
        ButtonGroup.group: styleGroup
        onTriggered: menu.choose(2)
    }
    MenuItem {
        text: qsTr("Text Under Icons")
        visible: menu.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.currentPosition === 3
        ButtonGroup.group: styleGroup
        onTriggered: menu.choose(3)
    }
    MenuItem {
        text: qsTr("Follow System Style")
        visible: menu.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.currentPosition === 4
        ButtonGroup.group: styleGroup
        onTriggered: menu.choose(4)
    }

    function choose(pos) {
        Log.info("ui", "Toolbar text position selected: " + pos)
        menu.positionSelected(pos)
    }
}
