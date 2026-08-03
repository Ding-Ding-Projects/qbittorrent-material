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
    \qmltype TagsSubMenu
    \brief "Tags ►" submenu — add existing tags to the selection.

    Lists every existing tag (\c Session.tags(), refreshed on the session's tag
    signals); picking one adds it to every selected torrent through
    \c TransferController.addTags. "Add…" (free-text, possibly several
    comma-separated tags) and "Remove All" bubble up to the owning view so it can
    prompt / confirm per the relevant preferences.

    Per-tag tri-state membership (present on all / some / none of the selection)
    is not shown because the bridge does not publish per-selection tag sets.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search tags")

    title: qsTr("Tags")

    /*! Emitted when the user picks "Add…"; the view opens a text prompt. */
    signal addTagRequested()

    /*! Emitted when the user picks "Remove All"; the view confirms + clears. */
    signal removeAllTagsRequested()

    // Reactive snapshot of the tag universe.
    property var tagList: []

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
        tagList = (typeof Session.tags === "function") ? _toArray(Session.tags()) : [];
    }

    Connections {
        target: Session
        function onTagAdded(tag) { root._refresh(); }
        function onTagRemoved(tag) { root._refresh(); }
    }

    Component.onCompleted: _refresh()

    MenuItem {
        text: qsTr("Add…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.add; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Tags → Add… requested")
            root.addTagRequested()
        }
    }

    MenuItem {
        text: qsTr("Remove All")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Tags → Remove All requested")
            root.removeAllTagsRequested()
        }
    }

    MenuSeparator {}

    // One entry per existing tag.
    Instantiator {
        id: tagItems
        model: root.tagList
        delegate: MenuItem {
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            required property var modelData
            text: ("" + modelData)
            leftPadding: 44
            MDIcon {
                icon: Icons.sell; size: 18; x: Spacing.md
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.color("onSurfaceVariant")
            }
            onTriggered: {
                Log.info("ui", "Tags → add '" + modelData + "' to selection")
                TransferController.addTags(["" + modelData])
            }
        }
        onObjectAdded: (index, object) => root.insertItem(root.count, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }
}
