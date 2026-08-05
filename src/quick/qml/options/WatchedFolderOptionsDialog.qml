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
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype WatchedFolderOptionsDialog
    \brief Add / edit a monitored ("watched") folder.

    For a new folder \l openForAdd() first shows the OS folder picker, then the
    dialog; \l openForEdit(row) seeds the dialog from
    \c OptionsController.watchedFolderOptions(row). Contains a "Recursive mode"
    switch plus the shared \c AddTorrentParamsForm for the torrent-parameter
    overrides. On OK it emits \c accepted(row, options); \c row is -1 for an add.
*/
Dialog {
    id: root

    /*! Row being edited; -1 means a brand-new watched folder. */
    property int row: -1

    /*! The chosen folder path. */
    property string folderPath: ""

    /*! The AddTorrentParams-shaped override object. */
    property var params: ({})

    /*! Emitted on OK with the row index and the assembled options object.
        Named \c committed to avoid shadowing \c Dialog's built-in
        \c accepted() signal. */
    signal committed(int row, var options)

    title: qsTr("Watched Folder Options")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) * 0.95)
    height: Math.min(560, (parent ? parent.height : 560) * 0.95)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale
    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    function openForAdd() {
        Log.info("ui", "WatchedFolderOptionsDialog: add flow (folder picker)")
        row = -1
        folderPath = ""
        params = {}
        recursiveSwitch.checked = false
        folderDialog.open()
    }

    function openForEdit(r) {
        Log.info("ui", "WatchedFolderOptionsDialog: edit row " + r)
        row = r
        var opts = OptionsController.watchedFolderOptions(r)
        folderPath = opts.path !== undefined ? opts.path : ""
        recursiveSwitch.checked = opts.recursive === true
        params = opts.params !== undefined ? opts.params : {}
        visible = true
    }

    Platform.FolderDialog {
        id: folderDialog
        title: qsTr("Select folder to monitor")
        onAccepted: {
            var s = decodeURIComponent(("" + folder).replace(/^file:\/\//, ""))
            if (/^\/[A-Za-z]:/.test(s))
                s = s.substring(1)
            root.folderPath = s
            Log.info("ui", "Watched folder picked: " + s)
            root.visible = true
        }
        onRejected: Log.debug("ui", "Watched folder pick cancelled")
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: Flickable {
        clip: true
        contentHeight: form.implicitHeight
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: form
            width: parent.width
            spacing: Spacing.md

            LabeledField {
                label: qsTr("Folder:")
                orientation: Qt.Vertical
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    text: root.folderPath
                    placeholderText: qsTr("No folder selected")
                }
            }

            Switch {
                id: recursiveSwitch
                text: qsTr("Recursive mode")
                font: Typography.bodyMedium
                onToggled: Log.debug("ui", "Watched folder recursive -> " + checked)
            }

            SectionHeader { text: qsTr("Torrent parameters"); Layout.fillWidth: true }

            AddTorrentParamsForm {
                id: paramsForm
                Layout.fillWidth: true
                params: root.params
                onChanged: root.params = params
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        topPadding: Spacing.sm
        spacing: Spacing.sm
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("OK")
            highlighted: true
            enabled: root.folderPath.length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        var options = {
            path: root.folderPath,
            recursive: recursiveSwitch.checked,
            params: paramsForm.params
        }
        Log.info("ui", "WatchedFolderOptionsDialog OK for row " + root.row + " path=" + root.folderPath)
        root.committed(root.row, options)
    }
    onRejected: Log.debug("ui", "WatchedFolderOptionsDialog cancelled")
    Component.onCompleted: Log.debug("ui", "WatchedFolderOptionsDialog constructed")
}
