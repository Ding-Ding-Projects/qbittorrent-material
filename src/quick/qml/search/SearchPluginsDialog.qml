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
    \qmltype SearchPluginsDialog
    \brief Material dialog listing installed search plugins with per-row enable
           switches, plus Install / Check-for-updates / Close actions and
           drag-and-drop \c .py install.

    Backed by \c SearchPluginsModel; all mutations go through
    \c SearchController.
*/
Dialog {
    id: root

    title: qsTr("Search plugins")
    modal: false
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(720, (parent ? parent.width : 720) * 0.9)
    height: Math.min(560, (parent ? parent.height : 560) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("search", "SearchPluginsDialog opened")
        pluginsModel.reload()
    }
    onClosed: Log.debug("search", "SearchPluginsDialog closed")

    SearchPluginsModel { id: pluginsModel }

    // Feedback from the controller (install/update/uninstall outcomes).
    Connections {
        target: SearchController
        function onPluginInstalled(name) {
            NotificationCenter.notify(qsTr("Search plugin \"%1\" installed").arg(SearchController.pluginFullName(name)), "success")
        }
        function onPluginInstallFailed(name, reason) {
            NotificationCenter.notify(qsTr("Couldn't install \"%1\" search engine plugin. %2").arg(name).arg(reason), "error")
        }
        function onPluginUpdated(name) {
            NotificationCenter.notify(qsTr("Search plugin \"%1\" updated").arg(SearchController.pluginFullName(name)), "success")
        }
        function onPluginUpdateFailed(name, reason) {
            NotificationCenter.notify(qsTr("Couldn't update \"%1\" search engine plugin. %2").arg(name).arg(reason), "error")
        }
        function onPluginUpdatesChecked(hasUpdates) {
            if (!hasUpdates)
                NotificationCenter.notify(qsTr("All your plugins are already up to date."), "info")
        }
        function onPluginUpdateCheckFailed(reason) {
            NotificationCenter.notify(qsTr("Sorry, couldn't check for plugin updates. %1").arg(reason), "error")
        }
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Installed search plugins:")
            font: Typography.titleMedium
            color: Theme.color("onSurface")
        }

        // ---- Plugins table (with drag-drop install) ----------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Spacing.radiusCard
            color: Theme.color("surface")
            border.color: dropArea.containsDrag ? Theme.color("primary") : Theme.color("outlineVariant")
            border.width: 1

            DropArea {
                id: dropArea
                anchors.fill: parent
                onDropped: (drop) => {
                    var files = []
                    for (var i = 0; i < drop.urls.length; ++i) {
                        var u = drop.urls[i].toString()
                        if (u.toLowerCase().endsWith(".py")) {
                            if (u.startsWith("file://"))
                                files.push(decodeURIComponent(u.replace("file:///", "").replace("file://", "")))
                            else
                                SearchController.installPluginFromUrl(u)
                        }
                    }
                    if (files.length > 0)
                        SearchController.installPluginsFromFiles(files)
                    Log.info("search", "Dropped " + drop.urls.length + " item(s) for install")
                }
            }

            DataTable {
                id: pluginsTable
                anchors.fill: parent
                anchors.margins: 1
                model: pluginsModel
                persistKey: "SearchPlugins"
                columns: [
                    { role: "fullName", title: qsTr("Name"),    width: 240, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "version",  title: qsTr("Version"), width: 90,  align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "url",      title: qsTr("Url"),     width: 240, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "enabled",  title: qsTr("Enabled"), width: 90,  align: Qt.AlignHCenter, visible: true, resizable: false }
                ]
                delegateFor: (col) => {
                    if (col.role === "enabled") return enabledCell
                    if (col.role === "fullName") return nameCell
                    return textCell
                }
                onActivated: (row) => {
                    var id = pluginsModel.pluginId(row)
                    var newState = !pluginsModel.isEnabled(row)
                    Log.info("search", "Double-click toggled plugin " + id + " -> " + newState)
                    SearchController.enablePlugin(id, newState)
                }
                onContextRequested: (row, pos) => {
                    var rows = pluginsTable.selectedRows.length > 0 ? pluginsTable.selectedRows : [row]
                    var ids = []
                    for (var i = 0; i < rows.length; ++i)
                        ids.push(pluginsModel.pluginId(rows[i]))
                    pluginMenu.pluginIds = ids
                    pluginMenu.firstEnabled = pluginsModel.isEnabled(rows[0])
                    pluginMenu.x = pos.x
                    pluginMenu.y = pos.y
                    pluginMenu.open()
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Typography.bodyMedium
            color: Theme.color("warning")
            text: qsTr("Warning: Be sure to comply with your country's copyright laws when downloading torrents from any of these search engines.")
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            textFormat: Text.RichText
            onLinkActivated: (link) => Qt.openUrlExternally(link)
            text: qsTr("You can get new search engine plugins here: %1")
                    .arg("<a href=\"https://plugins.qbittorrent.org\">https://plugins.qbittorrent.org</a>")
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        spacing: Spacing.sm

        Button {
            text: qsTr("Install a new one")
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                Log.info("search", "Install a new plugin requested")
                sourceDialog.open()
            }
        }
        Button {
            text: qsTr("Check for updates")
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                Log.info("search", "Check for plugin updates requested")
                SearchController.checkForPluginUpdates()
            }
        }
        Button {
            text: qsTr("Close")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.close()
        }
    }

    // ---- Cell delegates ----------------------------------------------------
    Component {
        id: nameCell
        Item {
            id: nameRoot
            anchors.fill: parent
            property var cell: parent
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Spacing.sm
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Spacing.xs
                Image {
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    source: pluginsModel.iconPathAt(nameRoot.cell.cellRow)
                    visible: source.toString().length > 0
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: nameRoot.cell.value !== undefined ? ("" + nameRoot.cell.value) : ""
                    font: Typography.bodyMedium
                    elide: Text.ElideRight
                    color: pluginsModel.isEnabled(nameRoot.cell.cellRow)
                           ? StateColors.success : StateColors.error
                }
            }
        }
    }

    Component {
        id: textCell
        Label {
            text: (parent.value !== undefined && parent.value !== null) ? ("" + parent.value) : ""
            font: Typography.bodyMedium
            elide: Text.ElideRight
            leftPadding: Spacing.sm
            rightPadding: Spacing.sm
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: parent.cellAlign
            anchors.fill: parent
            color: pluginsModel.isEnabled(parent.cellRow) ? StateColors.success : StateColors.error
        }
    }

    Component {
        id: enabledCell
        Item {
            id: enabledRoot
            anchors.fill: parent
            property var cell: parent
            Switch {
                anchors.centerIn: parent
                checked: enabledRoot.cell.value === true
                onToggled: {
                    var id = pluginsModel.pluginId(enabledRoot.cell.cellRow)
                    Log.info("search", "Switch toggled plugin " + id + " -> " + checked)
                    SearchController.enablePlugin(id, checked)
                }
            }
        }
    }

    PluginContextMenu {
        id: pluginMenu
    }

    PluginSourceDialog {
        id: sourceDialog
        onAskForLocalFile: localFilePicker.open()
        onAskForUrl: urlDialog.open()
    }

    NewPluginUrlDialog {
        id: urlDialog
        onUrlAccepted: (url) => {
            Log.info("search", "New plugin URL accepted: " + url)
            SearchController.installPluginFromUrl(url)
        }
    }

    // OS file picker for local .py plugins (the only permitted native dialog).
    Platform.FileDialog {
        id: localFilePicker
        title: qsTr("Select search plugins")
        fileMode: Platform.FileDialog.OpenFiles
        nameFilters: [ qsTr("qBittorrent search plugin (*.py)") ]
        onAccepted: {
            var paths = []
            for (var i = 0; i < files.length; ++i) {
                var u = files[i].toString()
                paths.push(decodeURIComponent(u.replace("file:///", "").replace("file://", "")))
            }
            Log.info("search", "Selected " + paths.length + " local plugin file(s)")
            SearchController.installPluginsFromFiles(paths)
        }
    }
}
