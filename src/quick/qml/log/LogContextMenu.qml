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
    \qmltype LogContextMenu
    \brief Right-click menu for the execution-log lists: Copy + Clear.

    Mirrors the desktop client's log context menu. \c Copy is only enabled when a
    row is selected (\l canCopy); \c Clear always wipes the visible buffer. The
    host view wires \c onCopyRequested / \c onClearRequested to the actual work.
    Open with \c popup().
*/
Menu {
    id: root

    /*! Whether the Copy item is enabled (a row is selected). */
    property bool canCopy: true

    /*! Emitted when the user chooses Copy. */
    signal copyRequested()
    /*! Emitted when the user chooses Clear. */
    signal clearRequested()

    modal: true
    Material.elevation: Spacing.elevationMenu
    property string filterText: ""

    function matches(label) {
        return filterText.length === 0
            || String(label).toLocaleLowerCase().includes(filterText.toLocaleLowerCase())
    }

    MenuItem {
        focusPolicy: Qt.NoFocus
        implicitHeight: Spacing.controlHeight + (Spacing.sm * 2)
        contentItem: TextField {
            id: menuSearch
            enabled: true
            placeholderText: qsTr("Search actions")
            text: root.filterText
            selectByMouse: true
            Accessible.name: qsTr("Search log actions")
            onTextEdited: root.filterText = text
            Keys.onEscapePressed: root.close()
        }
    }

    MenuSeparator {}

    MenuItem {
        id: copyItem

        text: qsTr("Copy")
        enabled: root.canCopy
        visible: root.matches(text)
        height: visible ? implicitHeight : 0
        Accessible.keyShortcut: "Ctrl+C"

        contentItem: RowLayout {
            spacing: Spacing.sm

            MDIcon {
                icon: Icons.content_copy
                size: Spacing.iconSizeSmall
                color: copyItem.enabled ? Theme.color("onSurface") : Theme.color("outline")
            }

            Label {
                text: copyItem.text
                font: Typography.bodyMedium
                color: copyItem.enabled ? Theme.color("onSurface") : Theme.color("outline")
                Layout.fillWidth: true
            }

            Label {
                text: "Ctrl+C"
                font: Typography.labelMedium
                color: copyItem.enabled ? Theme.color("onSurfaceVariant") : Theme.color("outline")
            }
        }

        onTriggered: {
            Log.debug("ui", "Execution Log context menu: Copy")
            root.copyRequested()
        }
    }

    MenuItem {
        id: clearItem

        text: qsTr("Clear")
        visible: root.matches(text)
        height: visible ? implicitHeight : 0

        contentItem: RowLayout {
            spacing: Spacing.sm

            MDIcon {
                icon: Icons.deleteIcon
                size: Spacing.iconSizeSmall
                color: Theme.color("onSurface")
            }

            Label {
                text: clearItem.text
                font: Typography.bodyMedium
                color: Theme.color("onSurface")
                Layout.fillWidth: true
            }
        }

        onTriggered: {
            Log.debug("ui", "Execution Log context menu: Clear")
            root.clearRequested()
        }
    }

    onAboutToShow: root.filterText = ""
    onOpened: {
        Log.debug("ui", "Execution Log context menu opened; canCopy=" + root.canCopy)
        Qt.callLater(menuSearch.forceActiveFocus)
    }
}
