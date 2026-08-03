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
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype TabularExportDialog
    \brief Chooses a faithful text format and destination for a transfer list.

    The scope is explicit before the file picker opens: the user can export
    the selected rows or every torrent in the session. A format's loss note is
    shown in this dialog, before the write, rather than discovered afterwards.
*/
Dialog {
    id: root

    objectName: "tabularExportDialog"
    title: qsTr("Export transfer list")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) * 0.92)
    height: Math.min(620, (parent ? parent.height : 620) * 0.9)
    padding: 0

    property bool selectedOnly: false
    property var formats: []
    property int formatIndex: 0

    readonly property var selectedFormat: {
        if (root.formats.length > root.formatIndex)
            return root.formats[root.formatIndex]
        return ({
            token: "json",
            name: qsTr("JSON"),
            extension: "json",
            lossNote: ""
        })
    }

    function openFor(onlySelected) {
        root.formats = TransferController.exportFormats()
        root.selectedOnly = onlySelected && TransferController.selectionCount > 0
        root.formatIndex = 0
        root.open()
    }

    function localPath(url) {
        if (url && typeof url.toLocalFile === "function")
            return url.toLocalFile()

        const raw = "" + url
        if (!raw.startsWith("file://"))
            return decodeURIComponent(raw)

        const encoded = raw.slice("file://".length)
        const decoded = decodeURIComponent(encoded)
        if (decoded.startsWith("/"))
            return decoded.replace(/^\/([A-Za-z]:)/, "$1")
        return "\\\\" + decoded.replace(/\//g, "\\")
    }

    function writeExport(url) {
        const path = root.localPath(url)
        const error = TransferController.exportTransfers(root.selectedFormat.token,
            path, root.selectedOnly)
        if (error && error.length > 0) {
            NotificationCenter.notify(error, "error", qsTr("Export failed"))
            return
        }

        const actionId = DesktopIntegration.externalEditorAvailable && path.length <= 140
            ? "open-export:" + path : ""
        NotificationCenter.notify(
            qsTr("Transfer list exported as %1.").arg(root.selectedFormat.name),
            "success", qsTr("Transfer list exported"),
            actionId.length > 0 ? qsTr("Open in editor") : "",
            actionId)
    }

    Material.elevation: Spacing.elevationDialog
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outline")
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
        spacing: Spacing.md

        Label {
            Layout.fillWidth: true
            text: root.selectedOnly
                ? qsTr("Export the %1 selected torrent(s).").arg(TransferController.selectionCount)
                : qsTr("Export all %1 torrent(s) in the session.").arg(Session.torrentCount)
            font: Typography.bodyMedium
            color: Theme.color("onSurface")
            wrapMode: Text.WordWrap
            Accessible.name: text
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("This is a 14-column summary with names, hashes, save paths, and transfer totals. Fields not listed here are not included; treat the file as private.")
            font: Typography.bodySmall
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
        }

        CheckBox {
            id: selectedOnlyCheck
            Layout.fillWidth: true
            text: qsTr("Export selected torrents only")
            font: Typography.bodyMedium
            checked: root.selectedOnly
            enabled: TransferController.selectionCount > 0
            Accessible.name: text
            Accessible.description: qsTr("When enabled, only the selected rows are written.")
            onToggled: root.selectedOnly = checked
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Format")
            font: Typography.labelLarge
            color: Theme.color("onSurfaceVariant")
        }

        ComboBox {
            id: formatCombo
            objectName: "tabularExportFormat"
            Layout.fillWidth: true
            font: Typography.bodyMedium
            model: root.formats
            textRole: "name"
            currentIndex: root.formatIndex
            Accessible.name: qsTr("Export format")
            Accessible.description: qsTr("Choose the file format for the transfer list.")
            onActivated: root.formatIndex = currentIndex
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("The file will be UTF-8 with LF line endings. Extension: .%1")
                .arg(root.selectedFormat.extension)
            font: Typography.labelSmall
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
        }

        Frame {
            Layout.fillWidth: true
            visible: root.selectedFormat.lossNote.length > 0
            padding: Spacing.sm

            background: Rectangle {
                radius: Spacing.radiusField
                color: Theme.color("surfaceVariant")
                border.width: 1
                border.color: Theme.color("outlineVariant")
            }

            Label {
                anchors.fill: parent
                text: qsTr("Before export: %1").arg(root.selectedFormat.lossNote)
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Accessible.name: text
            }
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
            onClicked: root.reject()
        }

        Button {
            text: qsTr("Choose file…")
            highlighted: true
            enabled: root.formats.length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: {
                root.close()
                saveDialog.defaultSuffix = root.selectedFormat.extension
                saveDialog.open()
            }
        }
    }

    Platform.FileDialog {
        id: saveDialog
        title: qsTr("Save %1 export").arg(root.selectedFormat.name)
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: root.selectedFormat.extension
        nameFilters: [
            qsTr("%1 files (*.%2)").arg(root.selectedFormat.name)
                .arg(root.selectedFormat.extension),
            qsTr("All files (*)")
        ]
        onAccepted: root.writeExport(file)
    }

    onOpened: formatCombo.forceActiveFocus()
}
