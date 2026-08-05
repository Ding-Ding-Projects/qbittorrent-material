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
    \qmltype RenameFileDialog
    \brief One-line prompt to rename a file or folder in the Content tab.

    Seed \l row and \l originalName before \c open(). By default the base name
    (without the trailing extension) is preselected, matching the legacy
    "select file name only" behavior. On accept emits \l fileRenamed(); the
    caller maps the row to a source index and commits via
    \c TorrentContentModel.renameItem().
*/
Dialog {
    id: root

    /*! Row index of the content item (carried for the caller). */
    property int row: -1

    /*! The current name (and initial field text). */
    property string originalName: ""

    /*! Whether to preselect only the base name (excluding extension). */
    property bool selectBaseName: true

    /*! Emitted with the row and new name. */
    signal fileRenamed(int row, string newName)

    title: qsTr("Renaming")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, (parent ? parent.width : 480) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    onOpened: {
        Log.debug("ui", "RenameFileDialog opened for row " + row)
        nameField.text = originalName
        nameField.forceActiveFocus()
        const dot = selectBaseName ? originalName.lastIndexOf(".") : -1
        if (dot > 0)
            nameField.select(0, dot)
        else
            nameField.selectAll()
    }

    function acceptEnabled() {
        const t = nameField.text.trim()
        return t.length > 0 && t !== originalName
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("New name:")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        TextField {
            id: nameField
            Layout.fillWidth: true
            selectByMouse: true
            onAccepted: if (root.acceptEnabled()) root.accept()
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            text: qsTr("OK")
            highlighted: true
            enabled: root.acceptEnabled()
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "RenameFileDialog accepted for row " + row + " -> '" + nameField.text.trim() + "'")
        root.fileRenamed(row, nameField.text.trim())
    }

    onRejected: Log.debug("ui", "RenameFileDialog rejected")
}
