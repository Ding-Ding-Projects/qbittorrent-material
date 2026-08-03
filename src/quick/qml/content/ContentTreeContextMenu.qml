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
    \qmltype ContentTreeContextMenu
    \brief Right-click menu for the torrent content tree.

    Two shapes, selected by \l single:
    \list
      \li single selection — optional Open / Open containing folder / Copy path
          (only when \l hasStorage), Rename…, Batch rename…, then a Priority
          submenu (Do not download / Normal / High / Maximum / By shown file order);
      \li multi selection — flat priority actions plus "Priority by shown file order".
    \endlist

    The menu is pure UI: it emits a signal per action and the host \c
    TorrentContentTree maps the current selection onto the model.
*/
SearchableMenu {
    id: root

    searchAccessibleName: qsTr("Search content actions")

    /*! True when exactly one row is selected. */
    property bool single: true

    /*! True when the torrent has real files on disk (Content tab, not Add dialog). */
    property bool hasStorage: false

    signal openTriggered()
    signal openContainingFolderTriggered()
    signal copyPathTriggered()
    signal renameTriggered()
    signal batchRenameTriggered()
    signal prioritySelected(int value)
    signal priorityByOrderTriggered()

    modal: true
    Material.elevation: 8

    onOpened: Log.debug("ui", "ContentTreeContextMenu opened (single=" + single + ")")

    // ---- Single selection ---------------------------------------------------
    MenuItem {
        text: qsTr("Open")
        visible: (root.single && root.hasStorage) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: Open"); root.openTriggered() }
    }
    MenuItem {
        text: qsTr("Open containing folder")
        visible: (root.single && root.hasStorage) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: Open containing folder"); root.openContainingFolderTriggered() }
    }
    MenuItem {
        text: qsTr("Copy path")
        visible: (root.single && root.hasStorage) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: Copy path"); root.copyPathTriggered() }
    }
    MenuSeparator {
        visible: root.single && root.hasStorage
        height: visible ? implicitHeight : 0
    }
    MenuItem {
        text: qsTr("Rename...")
        visible: (root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: Rename"); root.renameTriggered() }
    }
    MenuItem {
        text: qsTr("Batch rename...")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        Accessible.name: qsTr("Batch rename selected files")
        onTriggered: { Log.info("ui", "Content: Batch rename"); root.batchRenameTriggered() }
    }
    MenuSeparator {
        visible: true
    }

    Menu {
        id: prioritySubMenu
        title: qsTr("Priority")
        visible: root.single
        Material.elevation: 8

        MenuItem {
            text: qsTr("Do not download", "Do not download (priority)")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            onTriggered: { Log.info("ui", "Content: priority Do-not-download"); root.prioritySelected(0) }
        }
        MenuItem {
            text: qsTr("Normal", "Normal (priority)")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            onTriggered: { Log.info("ui", "Content: priority Normal"); root.prioritySelected(1) }
        }
        MenuItem {
            text: qsTr("High", "High (priority)")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            onTriggered: { Log.info("ui", "Content: priority High"); root.prioritySelected(6) }
        }
        MenuItem {
            text: qsTr("Maximum", "Maximum (priority)")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            onTriggered: { Log.info("ui", "Content: priority Maximum"); root.prioritySelected(7) }
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("By shown file order")
            visible: root.matches(text)
            height: visible ? implicitHeight : 0
            onTriggered: { Log.info("ui", "Content: priority by shown file order"); root.priorityByOrderTriggered() }
        }
    }

    // ---- Multi selection ----------------------------------------------------
    MenuItem {
        text: qsTr("Do not download", "Do not download (priority)")
        visible: (!root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: priority Do-not-download (multi)"); root.prioritySelected(0) }
    }
    MenuItem {
        text: qsTr("Normal priority")
        visible: (!root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: priority Normal (multi)"); root.prioritySelected(1) }
    }
    MenuItem {
        text: qsTr("High priority")
        visible: (!root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: priority High (multi)"); root.prioritySelected(6) }
    }
    MenuItem {
        text: qsTr("Maximum priority")
        visible: (!root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: priority Maximum (multi)"); root.prioritySelected(7) }
    }
    MenuSeparator {
        visible: !root.single
        height: visible ? implicitHeight : 0
    }
    MenuItem {
        text: qsTr("Priority by shown file order")
        visible: (!root.single) && root.matches(text)
        height: visible ? implicitHeight : 0
        onTriggered: { Log.info("ui", "Content: priority by shown file order (multi)"); root.priorityByOrderTriggered() }
    }
}
