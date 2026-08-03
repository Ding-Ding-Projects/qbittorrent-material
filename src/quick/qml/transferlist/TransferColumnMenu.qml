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
    \qmltype TransferColumnMenu
    \brief Transfer-list column-visibility menu ("Column visibility").

    Mirrors qBittorrent's \c displayColumnHeaderMenu: one checkable entry per
    column plus a trailing "Resize columns" action. The final visible column
    cannot be unchecked (last-column guard).

    \l columns is the same descriptor array \l TransferListView passes to
    \c DataTable (objects with \c role, \c title, \c visible). Toggling emits
    \l visibilityChanged; the view mutates its authoritative array and re-applies.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search columns")

    title: qsTr("Column visibility")

    /*! Column descriptors (array of { role, title, visible, … }). */
    property var columns: []

    /*! Emitted when a column's visibility is toggled. */
    signal visibilityChanged(string role, bool visible)

    /*! Emitted when "Resize columns" is chosen. */
    signal resizeRequested()

    modal: false
    Material.elevation: Spacing.elevationMenu

    function _visibleCount() {
        var n = 0;
        for (var i = 0; i < columns.length; ++i)
            if (columns[i].visible)
                ++n;
        return n;
    }

    Instantiator {
        id: columnItems
        model: root.columns
        delegate: MenuItem {
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            required property var modelData
            text: modelData.title
            checkable: true
            checked: modelData.visible
            // Guard: keep at least one column visible.
            enabled: !modelData.visible || root._visibleCount() > 1
            ToolTip.visible: hovered && modelData.tooltip !== undefined && modelData.tooltip.length > 0
            ToolTip.text: modelData.tooltip !== undefined ? modelData.tooltip : ""
            onTriggered: {
                Log.info("ui", "TransferColumnMenu: '" + modelData.title + "' visible -> " + checked)
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
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Resize all non-hidden columns to the size of their contents")
        onTriggered: {
            Log.debug("ui", "TransferColumnMenu: resize requested")
            root.resizeRequested()
        }
    }
}
