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
    \qmltype FilterPatternFormatMenu
    \brief Context menu that selects the pattern format (plain text / Regular
           expression) for a \l FilterTextField.

    \l regexEnabled is two-way bindable; picking an entry flips it and emits
    \l formatChanged(). Open with \c popup().
*/
Menu {
    id: root

    /*! Two-way: whether the regex format is selected. */
    property bool regexEnabled: false
    property string regexFlags: "iu"

    /*! Emitted when the user changes the pattern format. */
    signal formatChanged()
    signal flagsChanged(string flags)
    signal builderRequested()

    modal: false

    MenuItem {
        text: qsTr("Plain text")
        checkable: true
        checked: !root.regexEnabled
        onTriggered: {
            root.regexEnabled = false
            Log.debug("ui", "Filter pattern format -> Plain text")
            root.formatChanged()
        }
    }

    MenuItem {
        text: qsTr("Regular expression")
        checkable: true
        checked: root.regexEnabled
        onTriggered: {
            root.regexEnabled = true
            Log.debug("ui", "Filter pattern format -> Regular expression")
            root.formatChanged()
        }
    }


    MenuSeparator {}

    MenuItem {
        text: qsTr("Ignore case (i)")
        checkable: true
        checked: root.regexFlags.indexOf("i") >= 0
        onTriggered: root.toggleFlag("i", checked)
    }

    MenuItem {
        text: qsTr("Multiline anchors (m)")
        checkable: true
        checked: root.regexFlags.indexOf("m") >= 0
        onTriggered: root.toggleFlag("m", checked)
    }

    MenuItem {
        text: qsTr("Dot matches newlines (s)")
        checkable: true
        checked: root.regexFlags.indexOf("s") >= 0
        onTriggered: root.toggleFlag("s", checked)
    }

    MenuItem {
        text: qsTr("Unicode properties (u)")
        checkable: true
        checked: root.regexFlags.indexOf("u") >= 0
        onTriggered: root.toggleFlag("u", checked)
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("Open anchored Regex Builder…")
        onTriggered: root.builderRequested()
    }

    function toggleFlag(flag, enabled) {
        var next = root.regexFlags.replace(flag, "")
        if (enabled)
            next += flag
        root.regexFlags = next
        root.flagsChanged(next)
    }
}
