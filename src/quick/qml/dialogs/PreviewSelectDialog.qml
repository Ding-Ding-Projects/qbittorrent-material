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
    \qmltype PreviewSelectDialog
    \brief Material rebuild of the legacy \c PreviewSelectDialog.

    Lists the previewable media files of a torrent in a \l DataTable
    (Name / Size / Progress) and lets the user pick one to play. The caller seeds
    \l files with an array of \c {{ name, size, progress, path }} rows (\c size is
    an already-formatted string, \c progress is 0.0–1.0) and \l torrentName, then
    calls \c open(); the chosen file's path is emitted through
    \l readyToPreview(). When only a single file is previewable and
    \l autoPreviewSingle is set it is chosen automatically, mirroring the legacy
    behaviour.
*/
Dialog {
    id: root

    /*! Previewable files: array of { name, size, progress, path }. */
    property var files: []

    /*! Name of the torrent these files belong to (for the header prompt). */
    property string torrentName: ""

    /*! Auto-pick when exactly one file is previewable. */
    property bool autoPreviewSingle: true

    /*! Emitted with the local filesystem path of the chosen file. */
    signal readyToPreview(string path)

    title: qsTr("Preview file")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(620, (parent ? parent.width : 620) * 0.9)
    height: Math.min(480, (parent ? parent.height : 480) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    // Backing model built from the supplied files array.
    ListModel {
        id: filesModel
    }

    function _populate() {
        filesModel.clear()
        const list = root.files || []
        for (let i = 0; i < list.length; ++i) {
            const f = list[i]
            filesModel.append({
                "name": f.name !== undefined ? f.name : "",
                "size": f.size !== undefined ? f.size : "",
                "progress": f.progress !== undefined ? f.progress : 0.0,
                "path": f.path !== undefined ? f.path : ""
            })
        }
        table.currentRow = filesModel.count > 0 ? 0 : -1
        table.selectedRows = filesModel.count > 0 ? [0] : []
        Log.debug("ui", "PreviewSelectDialog populated " + filesModel.count + " previewable file(s)")
    }

    function _preview(row) {
        if ((row < 0) || (row >= filesModel.count))
            return
        const entry = filesModel.get(row)
        Log.info("ui", "PreviewSelectDialog previewing " + entry.path)
        root.readyToPreview(entry.path)
        root.close()
    }

    onOpened: {
        Log.debug("ui", "PreviewSelectDialog opened for \"" + torrentName + "\"")
        _populate()
        if (root.autoPreviewSingle && (filesModel.count === 1))
            Qt.callLater(root._preview, 0)
    }
    onClosed: Log.debug("ui", "PreviewSelectDialog closed")

    // Progress-bar cell delegate.
    Component {
        id: progressCellComp
        ProgressCell {
            anchors.fill: parent
            progress: (parent.value !== undefined && parent.value !== null) ? parent.value : 0.0
        }
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ColumnLayout {
        spacing: Spacing.sm

        Label {
            text: qsTr("The following files from torrent \"%1\" support previewing, please select one of them:").arg(root.torrentName)
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: filesModel
            persistKey: "PreviewSelectDialog"
            alternatingRows: true
            delegateFor: (col) => col.role === "progress" ? progressCellComp : null
            columns: [
                { role: "name", title: qsTr("Name"), width: 320, align: Qt.AlignLeft, visible: true, resizable: true },
                { role: "size", title: qsTr("Size"), width: 110, align: Qt.AlignRight, visible: true, resizable: true },
                { role: "progress", title: qsTr("Progress"), width: 120, align: Qt.AlignHCenter, visible: true, resizable: true }
            ]

            onActivated: (row) => root._preview(row)
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
            text: qsTr("Preview")
            highlighted: true
            enabled: table.currentRow >= 0
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                Log.debug("ui", "PreviewSelectDialog Preview clicked for row " + table.currentRow)
                root._preview(table.currentRow)
            }
        }
    }

    onRejected: Log.debug("ui", "PreviewSelectDialog cancelled")
}
