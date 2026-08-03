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
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype TransferRowContextMenu
    \brief The right-click context menu over a transfer-list row.

    Mirrors qBittorrent's \c displayListMenu. It operates on the current
    selection (\c TransferController.selectedIds); \c TransferController exposes
    only the action verbs and \c selectionCount, so item availability is gated by
    selection size — single-selection-only entries (Rename, Manage content) are
    hidden when more than one torrent is selected. The per-torrent toggles
    (AutoTMM, super seeding, sequential, first/last) are checkable session
    toggles: they apply on click but do not pre-reflect the torrents' current
    state (the bridge publishes no aggregate flags).

    Actions that need a dialog (rename, set location, category, tags, trackers,
    options, preview, export, delete) are bubbled up as signals so the owning
    \l TransferListView can host the Material dialogs; immediate actions dispatch
    straight to \c TransferController.
*/
SearchableMenu {
    id: root

    // ---- Signals the owning view handles (they need dialogs) ---------------
    signal renameRequested()
    signal setLocationRequested()
    signal manageContentRequested()
    signal editTrackersRequested()
    signal torrentOptionsRequested()
    signal previewRequested()
    signal exportRequested()
    signal exportListRequested()
    signal deleteRequested()
    signal newCategoryRequested()
    signal addTagRequested()
    signal removeAllTagsRequested()

    searchAccessibleName: qsTr("Search transfer actions")

    readonly property bool single: TransferController.selectionCount === 1
    property var startAction: null
    property var stopAction: null
    property var removeAction: null

    onAboutToShow: Log.debug("ui", "TransferRowContextMenu opening for "
                             + TransferController.selectionCount + " torrent(s)")

    // 1 — Start ---------------------------------------------------------------
    MenuItem {
        id: startItem
        text: qsTr("Start")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        rightPadding: 88
        Accessible.description: startShortcut.text.length > 0
            ? qsTr("Keyboard shortcut %1").arg(startShortcut.text) : ""
        MDIcon {
            icon: Icons.play_arrow; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        Label {
            id: startShortcut
            anchors.right: parent.right
            anchors.rightMargin: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.startAction ? root.startAction.shortcut.toString() : ""
            visible: text.length > 0
            font: Typography.labelMedium
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Start"); TransferController.start() }
    }

    // 2 — Stop ----------------------------------------------------------------
    MenuItem {
        id: stopItem
        text: qsTr("Stop")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        rightPadding: 88
        Accessible.description: stopShortcut.text.length > 0
            ? qsTr("Keyboard shortcut %1").arg(stopShortcut.text) : ""
        MDIcon {
            icon: Icons.pause; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        Label {
            id: stopShortcut
            anchors.right: parent.right
            anchors.rightMargin: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.stopAction ? root.stopAction.shortcut.toString() : ""
            visible: text.length > 0
            font: Typography.labelMedium
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Stop"); TransferController.stop() }
    }

    // 3 — Force Start ---------------------------------------------------------
    MenuItem {
        text: qsTr("Force Start")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.bolt; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Force Start"); TransferController.forceStart() }
    }

    MenuSeparator {}

    // 5 — Remove --------------------------------------------------------------
    MenuItem {
        id: removeItem
        text: qsTr("Remove")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        rightPadding: 88
        Accessible.description: removeShortcut.text.length > 0
            ? qsTr("Keyboard shortcut %1").arg(removeShortcut.text) : ""
        MDIcon {
            icon: Icons.deleteIcon; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("error")
        }
        Label {
            id: removeShortcut
            anchors.right: parent.right
            anchors.rightMargin: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.removeAction ? root.removeAction.shortcut.toString() : ""
            visible: text.length > 0
            font: Typography.labelMedium
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Remove"); root.deleteRequested() }
    }

    MenuSeparator {}

    // 7 — Set location… -------------------------------------------------------
    MenuItem {
        text: qsTr("Set location…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.drive_file_move; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Set location"); root.setLocationRequested() }
    }

    // 8 — Rename… (single selection only) ------------------------------------
    MenuItem {
        text: qsTr("Rename…")
        visible: root.single && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.edit; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Rename"); root.renameRequested() }
    }

    // 9 — Manage content… (single selection only) ----------------------------
    MenuItem {
        text: qsTr("Manage content…")
        visible: root.single && root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.folder; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Manage content"); root.manageContentRequested() }
    }

    // 10 — Edit trackers… -----------------------------------------------------
    MenuItem {
        text: qsTr("Edit trackers…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.dns; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Edit trackers"); root.editTrackersRequested() }
    }

    // 11 — Category ► ---------------------------------------------------------
    CategorySubMenu {
        id: categoryMenu
        visible: root.matches(title)
        height: visible ? implicitHeight : 0
        onNewCategoryRequested: root.newCategoryRequested()
    }

    // 12 — Tags ► -------------------------------------------------------------
    TagsSubMenu {
        id: tagsMenu
        visible: root.matches(title)
        height: visible ? implicitHeight : 0
        onAddTagRequested: root.addTagRequested()
        onRemoveAllTagsRequested: root.removeAllTagsRequested()
    }

    // 13 — Automatic Torrent Management (session toggle) ---------------------
    MenuItem {
        text: qsTr("Automatic Torrent Management")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        leftPadding: 44
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Automatic mode means that various torrent properties "
                           + "(e.g. save path) will be decided by the associated category")
        MDIcon {
            icon: parent.checked ? Icons.check : Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: parent.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant")
        }
        onToggled: {
            Log.info("ui", "Context → Automatic Torrent Management -> " + checked)
            TransferController.setAutoTMM(checked)
        }
    }

    MenuSeparator {}

    // 15 — Torrent options… ---------------------------------------------------
    MenuItem {
        text: qsTr("Torrent options…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.tune; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Torrent options"); root.torrentOptionsRequested() }
    }

    // 16 — Super seeding mode (session toggle) -------------------------------
    MenuItem {
        text: qsTr("Super seeding mode")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        leftPadding: 44
        MDIcon {
            icon: parent.checked ? Icons.check : Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: parent.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant")
        }
        onToggled: {
            Log.info("ui", "Context → Super seeding -> " + checked)
            TransferController.setSuperSeeding(checked)
        }
    }

    MenuSeparator {}

    // 18 — Preview file… ------------------------------------------------------
    MenuItem {
        text: qsTr("Preview file…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.preview; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Preview file"); root.previewRequested() }
    }

    // 19 — Download in sequential order (session toggle) ---------------------
    MenuItem {
        text: qsTr("Download in sequential order")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        leftPadding: 44
        MDIcon {
            icon: parent.checked ? Icons.check : Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: parent.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant")
        }
        onToggled: {
            Log.info("ui", "Context → Sequential download -> " + checked)
            TransferController.setSequential(checked)
        }
    }

    // 20 — Download first and last pieces first (session toggle) -------------
    MenuItem {
        text: qsTr("Download first and last pieces first")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        checkable: true
        leftPadding: 44
        MDIcon {
            icon: parent.checked ? Icons.check : Icons.close; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: parent.checked ? Theme.color("primary") : Theme.color("onSurfaceVariant")
        }
        onToggled: {
            Log.info("ui", "Context → First/last pieces first -> " + checked)
            TransferController.setFirstLastPiece(checked)
        }
    }

    MenuSeparator {}

    // 22 — Force recheck ------------------------------------------------------
    MenuItem {
        text: qsTr("Force recheck")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.fact_check; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Force recheck"); TransferController.forceRecheck() }
    }

    // 23 — Force reannounce ---------------------------------------------------
    MenuItem {
        text: qsTr("Force reannounce")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.campaign; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Force reannounce"); TransferController.forceReannounce() }
    }

    MenuSeparator {}

    // 25 — Open destination folder -------------------------------------------
    MenuItem {
        text: qsTr("Open destination folder")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.folder_open; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Context → Open destination folder")
            TransferController.openDestination()
        }
    }

    MenuSeparator {}

    // 27 — Queue ► ------------------------------------------------------------
    QueueSubMenu {
        id: queueMenu
        visible: root.matches(title)
        height: visible ? implicitHeight : 0
    }

    // 28 — Copy ► -------------------------------------------------------------
    CopySubMenu {
        id: copyMenu
        visible: root.matches(title)
        height: visible ? implicitHeight : 0
    }

    // 29 — Export .torrent… ---------------------------------------------------
    MenuItem {
        text: qsTr("Export .torrent…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Exported torrent is not necessarily the same as the imported")
        MDIcon {
            icon: Icons.save_alt; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: { Log.info("ui", "Context → Export .torrent"); root.exportRequested() }
    }

    // 30 — Export transfer list… ---------------------------------------------
    MenuItem {
        text: qsTr("Export transfer list…")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        leftPadding: 44
        MDIcon {
            icon: Icons.save_alt; size: 18; x: Spacing.md
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.color("onSurfaceVariant")
        }
        onTriggered: {
            Log.info("ui", "Context → Export transfer list")
            root.exportListRequested()
        }
    }
}
