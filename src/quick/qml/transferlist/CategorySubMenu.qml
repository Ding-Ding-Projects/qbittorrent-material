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
    \qmltype CategorySubMenu
    \brief "Category ►" submenu — assign, reset or create the category for the
           current selection.

    Lists every existing category (\c Session.categories(), refreshed on the
    session's category signals). Assigning a category (or "Reset" → uncategorized)
    is applied immediately through \c TransferController.setCategory. Creating a
    new category needs a text prompt, so it is bubbled up via
    \l newCategoryRequested for the owning view to handle.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search categories")

    title: qsTr("Category")

    /*! Emitted when the user picks "New…"; the view opens a text prompt. */
    signal newCategoryRequested()

    // Reactive snapshot of the category universe.
    property var categoryList: []

    function _toArray(value) {
        if ((value === undefined) || (value === null))
            return [];
        if (Array.isArray(value))
            return value;
        const out = [];
        try {
            for (let i = 0; i < value.length; ++i)
                out.push(value[i]);
        } catch (err) { /* not iterable */ }
        return out;
    }

    function _refresh() {
        categoryList = (typeof Session.categories === "function")
                ? _toArray(Session.categories()) : [];
    }

    Connections {
        target: Session
        function onCategoryAdded(category) { root._refresh(); }
        function onCategoryRemoved(category) { root._refresh(); }
    }

    Component.onCompleted: _refresh()

    MenuItem {
        text: qsTr("New…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.add; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Category → New… requested")
            root.newCategoryRequested()
        }
    }

    MenuItem {
        text: qsTr("Reset")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Category → Reset (uncategorized)")
            TransferController.setCategory("")
        }
    }

    MenuSeparator {}

    // One entry per existing category.
    Instantiator {
        id: categoryItems
        model: root.categoryList
        delegate: MenuItem {
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            required property var modelData
            text: modelData
            leftPadding: 44
            MDIcon {
                icon: Icons.category; size: 18; x: Spacing.md
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.color("onSurfaceVariant")
            }
            onTriggered: {
                Log.info("ui", "Category → assign '" + modelData + "'")
                TransferController.setCategory(modelData)
            }
        }
        onObjectAdded: (index, object) => root.insertItem(root.count, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }
}
