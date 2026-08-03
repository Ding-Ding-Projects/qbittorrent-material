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
    \qmltype ColumnHeaderMenu
    \brief Header context menu offering per-column visibility toggles plus a
           "Resize columns" action, with a last-visible-column guard.

    \l columns is the same descriptor list \l DataTable uses; each entry's
    \c visible flag is toggled in place. Unchecking is blocked when only one
    column remains visible (the guard keeps at least one column on screen).
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search columns")

    /*!
        The column descriptor list (array of objects with at least \c role,
        \c title and \c visible). Toggled two-way.
    */
    property var columns: []

    /*! Emitted when the user picks "Resize columns". */
    signal resizeRequested()

    /*! Emitted when a column's visibility changes. */
    signal visibilityChanged(string role, bool visible)

    modal: false

    function _visibleCount() {
        var n = 0
        for (var i = 0; i < columns.length; ++i)
            if (columns[i].visible)
                ++n
        return n
    }

    // Per-column checkable items, generated from the descriptor list.
    Instantiator {
        id: columnItems
        model: root.columns
        delegate: MenuItem {
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            required property var modelData
            required property int index
            text: modelData.title
            checkable: true
            checked: modelData.visible
            // Guard: don't allow hiding the final visible column.
            enabled: !modelData.visible || root._visibleCount() > 1
            onTriggered: {
                var cols = root.columns
                cols[index].visible = checked
                root.columns = cols
                Log.debug("ui", "ColumnHeaderMenu: '" + modelData.title + "' visible -> " + checked)
                root.visibilityChanged(modelData.role, checked)
            }
        }
        onObjectAdded: (index, object) => root.insertItem(index, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }

    MenuSeparator {}

    MenuItem {
        text: qsTr("Resize columns")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: {
            Log.debug("ui", "ColumnHeaderMenu: resize columns requested")
            root.resizeRequested()
        }
    }
}
