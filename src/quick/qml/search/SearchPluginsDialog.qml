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

    property string pendingPluginId: ""

    function pluginStateText(row) {
        var state = pluginsModel.pluginRecord(row).runtimeState || "not-installed"
        if (state === "ready") return qsTr("Ready")
        if (state === "waiting-python") return qsTr("Waiting for Python")
        if (state === "stale-registration") return qsTr("Waiting for runtime refresh")
        if (state === "quarantined") return qsTr("Quarantined")
        if (state === "import-failed") return qsTr("Import failed")
        if (state === "user-removed") return qsTr("Removed")
        if (state === "not-installed") return qsTr("Not installed")
        return state
    }

    function pluginIntegrityText(row) {
        var state = pluginsModel.pluginRecord(row).integrityState || "unknown"
        if (state === "verified-external") return qsTr("Verified")
        if (state === "user-managed") return qsTr("User managed")
        if (state === "user-modified") return qsTr("Modified")
        if (state === "user-removed") return qsTr("Removed")
        if (state === "missing") return qsTr("Missing")
        return state
    }

    function pluginStateColor(row) {
        var record = pluginsModel.pluginRecord(row)
        if (record.runtimeState === "ready")
            return record.enabled ? Theme.color("success") : Theme.color("onSurfaceVariant")
        if (record.runtimeWaiting || record.runtimeState === "quarantined"
                || record.runtimeState === "stale-registration")
            return Theme.color("warning")
        if (record.runtimeState === "import-failed")
            return Theme.color("error")
        return Theme.color("onSurfaceVariant")
    }

    function pluginHighlightColor(row) {
        return pluginsModel.highlightedPluginId === pluginsModel.pluginId(row)
            ? Qt.alpha(Theme.color("primaryContainer"), 0.9) : "transparent"
    }

    function revealPlugin(pluginId) {
        if (!pluginId || !pluginId.length)
            return false
        pluginsModel.flushPendingInventory()
        var row = pluginsModel.indexOfPlugin(pluginId)
        if (row < 0)
            return false
        if (!pluginsModel.highlightPlugin(pluginId) || !pluginsTable.revealRow(row))
            return false
        pendingPluginId = ""
        highlightClearTimer.restart()
        return true
    }

    function openPlugin(pluginId) {
        if (pluginId === "__command-palette-install-search-plugin__") {
            pendingPluginId = ""
            open()
            Qt.callLater(function() { root.openInstaller() })
            return
        }
        pendingPluginId = pluginId || ""
        open()
        Qt.callLater(function() { root.revealPlugin(root.pendingPluginId) })
    }

    function openInstaller() {
        if (SearchController.pluginOperationInProgress)
            return
        Log.info("search", "Install a new plugin requested")
        sourceDialog.open()
    }

    function notifyPluginOperationSummary(summary) {
        if (!summary)
            return

        var kind = summary.kind || "install"
        var state = summary.state || "failed"
        var requested = Number(summary.requested || 0)
        var succeeded = Number(summary.succeeded || 0)
        var failed = Number(summary.failed || 0)
        var skipped = Number(summary.skipped || 0)
        var message
        var severity

        if (kind === "catalog") {
            var installed = Number(summary.newlyInstalled || 0)
            var present = Number(summary.alreadyPresent || 0)
            var removed = Number(summary.userRemoved || 0)
            var awaiting = Number(summary.awaitingRuntime || 0)
            if (summary.runtimeUnavailable) {
                message = qsTr("Unofficial plugin files are ready on disk: %1 installed now, %2 already present, %3 kept removed, and %4 waiting for the search runtime. %5 Fix or select Python, then retry setup. %6 download failure(s) need attention. Per-plugin details remain in Search Plugins.")
                    .arg(installed).arg(present).arg(removed).arg(awaiting)
                    .arg(summary.runtimeError || qsTr("The search runtime is unavailable."))
                    .arg(failed)
                severity = "warning"
            } else if (failed > 0) {
                message = qsTr("Unofficial plugin setup finished with %1 failure(s): %2 installed, %3 already present, %4 kept removed. Open Search Plugins for the per-plugin diagnostics.")
                    .arg(failed).arg(installed).arg(present).arg(removed)
                severity = "warning"
            } else {
                message = qsTr("Unofficial plugin setup is ready: %1 installed, %2 already present, %3 kept removed.")
                    .arg(installed).arg(present).arg(removed)
                severity = "success"
            }
        } else if (state === "runtime-unavailable") {
            message = qsTr("The search-plugin %1 operation was stopped before it could fan out across %2 item(s). %3 Fix or select Python, then retry once. Per-plugin state remains available in Search Plugins.")
                .arg(kind === "update" ? qsTr("update") : kind === "runtime-recovery" ? qsTr("runtime recovery") : qsTr("install"))
                .arg(requested)
                .arg(summary.runtimeError || qsTr("The search runtime is unavailable."))
            severity = "warning"
        } else if (state === "no-updates") {
            message = skipped > 0
                ? qsTr("No installed search plugins need updates. %1 unavailable or deliberately removed catalog entry/entries were ignored.").arg(skipped)
                : qsTr("All installed search plugins are already up to date.")
            severity = "info"
        } else if (failed > 0) {
            message = qsTr("Search-plugin %1 finished: %2 succeeded, %3 failed, and %4 were skipped. Open Search Plugins for each plugin's diagnostic.")
                .arg(kind === "update" ? qsTr("update") : kind === "runtime-recovery" ? qsTr("runtime recovery") : qsTr("install"))
                .arg(succeeded).arg(failed).arg(skipped)
            severity = state === "failed" ? "error" : "warning"
        } else {
            message = qsTr("Search-plugin %1 finished successfully for %2 item(s); %3 were skipped.")
                .arg(kind === "update" ? qsTr("update") : kind === "runtime-recovery" ? qsTr("runtime recovery") : qsTr("install"))
                .arg(succeeded).arg(skipped)
            severity = "success"
        }

        NotificationCenter.notify(message, severity, qsTr("Search plugins"))
        if (Number(summary.serial || 0) > 0)
            SearchController.acknowledgePluginOperationSummary(summary.serial)
    }

    function replayPendingPluginOperationSummaries() {
        var pending = SearchController.pendingPluginOperationSummaries || []
        for (var i = 0; i < pending.length; ++i)
            notifyPluginOperationSummary(pending[i])
    }

    title: qsTr("Search plugins")
    modal: false
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(720, (parent ? parent.width : 720) * 0.9)
    height: Math.min(560, (parent ? parent.height : 560) * 0.9)
    padding: Spacing.lg
    // Keep the non-modal dialog above the notification host. The snackbar is
    // intentionally persistent for runtime failures, but it must not paint
    // across this dialog's table or action row while the user investigates.
    z: 9100

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("search", "SearchPluginsDialog opened")
        pluginsModel.flushPendingInventory()
        replayPendingPluginOperationSummaries()
        if (pendingPluginId.length)
            Qt.callLater(function() { root.revealPlugin(root.pendingPluginId) })
    }
    onClosed: Log.debug("search", "SearchPluginsDialog closed")

    SearchPluginsModel {
        id: pluginsModel
        inventory: SearchController.plugins
    }

    Timer {
        id: highlightClearTimer
        interval: 1800
        repeat: false
        onTriggered: pluginsModel.clearHighlight()
    }

    Connections {
        target: pluginsModel
        function onInventoryChanged() {
            if (root.pendingPluginId.length)
                Qt.callLater(function() { root.revealPlugin(root.pendingPluginId) })
        }
    }

    // One notification per complete operation. Individual outcomes stay in the
    // model/palette diagnostic fields and never fan out into a toast storm.
    Connections {
        target: SearchController
        function onPluginOperationSummaryReady(summary) {
            root.notifyPluginOperationSummary(summary)
        }
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Search plugins: %1 known").arg(pluginsModel.count)
            font: Typography.titleMedium
            color: Theme.color("onSurface")
            Accessible.name: text
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
                    { role: "runtimeState", title: qsTr("State"), width: 150, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "integrityState", title: qsTr("Integrity"), width: 120, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "catalogSourceUrl", title: qsTr("Source"), width: 260, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "diagnostic", title: qsTr("Status details"), width: 260, align: Qt.AlignLeft, visible: true, resizable: true },
                    { role: "enabled",  title: qsTr("Enabled"), width: 90,  align: Qt.AlignHCenter, visible: true, resizable: false }
                ]
                delegateFor: (col) => {
                    if (col.role === "enabled") return enabledCell
                    if (col.role === "fullName") return nameCell
                    if (col.role === "runtimeState") return stateCell
                    if (col.role === "integrityState") return integrityCell
                    return textCell
                }
                onActivated: (row) => {
                    if (!pluginsModel.isRegistered(row)) {
                        pluginsModel.highlightPlugin(pluginsModel.pluginId(row))
                        highlightClearTimer.restart()
                        return
                    }
                    var id = pluginsModel.pluginId(row)
                    var newState = !pluginsModel.isEnabled(row)
                    Log.info("search", "Double-click toggled plugin " + id + " -> " + newState)
                    SearchController.enablePlugin(id, newState)
                }
                onContextRequested: (row, pos) => {
                    var rows = pluginsTable.selectedRows.length > 0 ? pluginsTable.selectedRows : [row]
                    var ids = []
                    for (var i = 0; i < rows.length; ++i) {
                        if (pluginsModel.isRegistered(rows[i]))
                            ids.push(pluginsModel.pluginId(rows[i]))
                    }
                    if (ids.length === 0)
                        return
                    pluginMenu.pluginIds = ids
                    pluginMenu.firstEnabled = pluginsModel.isEnabled(
                        pluginsModel.indexOfPlugin(ids[0]))
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
            color: Number(SearchController.unofficialPluginStatus.failed || 0) > 0
                ? Theme.color("error")
                : SearchController.unofficialPluginStatus.runtimeUnavailable
                    ? Theme.color("warning") : Theme.color("onSurfaceVariant")
            visible: Number(SearchController.unofficialPluginStatus.canonicalCount || 0) > 0
                || SearchController.unofficialPluginStatus.state === "failed"
            text: SearchController.unofficialPluginStatus.inProgress
                ? qsTr("Verified unofficial catalog: %1 of %2 processed (%3 HTTPS sources available).")
                    .arg(SearchController.unofficialPluginStatus.completed || 0)
                    .arg(SearchController.unofficialPluginStatus.canonicalCount || 0)
                    .arg(SearchController.unofficialPluginStatus.availableSourceCount || 0)
                : SearchController.unofficialPluginStatus.runtimeUnavailable
                    ? qsTr("Verified unofficial catalog: %1 file(s) ready on disk and waiting for the search runtime, %2 download failure(s), %3 kept removed. %4")
                        .arg(SearchController.unofficialPluginStatus.awaitingRuntime || 0)
                        .arg(SearchController.unofficialPluginStatus.failed || 0)
                        .arg(SearchController.unofficialPluginStatus.userRemoved || 0)
                        .arg(SearchController.unofficialPluginStatus.runtimeError || qsTr("The search runtime is unavailable."))
                : qsTr("Verified unofficial catalog: %1 registered, %2 failure(s), %3 source link(s) unavailable but covered by verified alternatives.")
                    .arg(SearchController.unofficialPluginStatus.registered || 0)
                    .arg(SearchController.unofficialPluginStatus.failed || 0)
                    .arg(SearchController.unofficialPluginStatus.unavailableSourceCount || 0)
            Accessible.name: text
        }

        Label {
            Layout.fillWidth: true
            visible: (SearchController.unofficialPluginStatus.errors || []).length > 0
            text: (SearchController.unofficialPluginStatus.errors || []).join("\n")
            maximumLineCount: 4
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            font: Typography.bodySmall
            color: Theme.color("error")
            Accessible.name: text
            ToolTip.visible: errorHover.hovered
            ToolTip.text: text
            ToolTip.delay: 350
            HoverHandler { id: errorHover }
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
            enabled: !SearchController.pluginOperationInProgress
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: root.openInstaller()
        }
        Button {
            text: qsTr("Check for updates")
            enabled: !SearchController.pluginOperationInProgress
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                Log.info("search", "Check for plugin updates requested")
                SearchController.checkForPluginUpdates()
            }
        }
        Button {
            text: qsTr("Retry unofficial setup")
            visible: !SearchController.unofficialPluginStatus.inProgress
                && (SearchController.unofficialPluginStatus.state === "partial"
                    || SearchController.unofficialPluginStatus.state === "failed"
                    || SearchController.unofficialPluginStatus.state === "waiting-runtime")
            enabled: visible
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            Accessible.description: qsTr("Retry verified HTTPS downloads and plugin runtime validation without restarting the app")
            onClicked: SearchController.retryUnofficialPluginSync()
        }
        Button {
            text: qsTr("Close")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }

    // ---- Cell delegates ----------------------------------------------------
    Component {
        id: nameCell
        Item {
            id: nameRoot
            anchors.fill: parent
            property var cell: parent

            Rectangle {
                anchors.fill: parent
                color: root.pluginHighlightColor(nameRoot.cell.cellRow)
                Behavior on color {
                    ColorAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
                }
            }
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
                    color: root.pluginStateColor(nameRoot.cell.cellRow)
                }
            }
        }
    }

    Component {
        id: textCell
        Rectangle {
            id: textRoot
            anchors.fill: parent
            property var cell: parent
            color: root.pluginHighlightColor(cell.cellRow)
            Behavior on color {
                ColorAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
            }
            Label {
                anchors.fill: parent
                text: (textRoot.cell.value !== undefined && textRoot.cell.value !== null)
                    ? ("" + textRoot.cell.value) : ""
                font: Typography.bodyMedium
                elide: Text.ElideRight
                leftPadding: Spacing.sm
                rightPadding: Spacing.sm
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: textRoot.cell.cellAlign
                color: root.pluginStateColor(textRoot.cell.cellRow)
            }
        }
    }

    Component {
        id: stateCell
        Rectangle {
            id: stateRoot
            anchors.fill: parent
            property var cell: parent
            color: root.pluginHighlightColor(cell.cellRow)
            Behavior on color {
                ColorAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
            }
            Label {
                anchors.fill: parent
                text: root.pluginStateText(stateRoot.cell.cellRow)
                font: Typography.bodyMedium
                elide: Text.ElideRight
                leftPadding: Spacing.sm
                rightPadding: Spacing.sm
                verticalAlignment: Text.AlignVCenter
                color: root.pluginStateColor(stateRoot.cell.cellRow)
                Accessible.name: text
            }
        }
    }

    Component {
        id: integrityCell
        Rectangle {
            id: integrityRoot
            anchors.fill: parent
            property var cell: parent
            color: root.pluginHighlightColor(cell.cellRow)
            Behavior on color {
                ColorAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
            }
            Label {
                anchors.fill: parent
                text: root.pluginIntegrityText(integrityRoot.cell.cellRow)
                font: Typography.bodyMedium
                elide: Text.ElideRight
                leftPadding: Spacing.sm
                rightPadding: Spacing.sm
                verticalAlignment: Text.AlignVCenter
                color: root.pluginStateColor(integrityRoot.cell.cellRow)
                Accessible.name: text
            }
        }
    }

    Component {
        id: enabledCell
        Item {
            id: enabledRoot
            anchors.fill: parent
            property var cell: parent

            Rectangle {
                anchors.fill: parent
                color: root.pluginHighlightColor(enabledRoot.cell.cellRow)
                Behavior on color {
                    ColorAnimation { duration: ThemeManager.reducedMotion ? 0 : Spacing.motionFast }
                }
            }
            Switch {
                anchors.centerIn: parent
                visible: pluginsModel.isRegistered(enabledRoot.cell.cellRow)
                checked: enabledRoot.cell.value === true
                Accessible.name: qsTr("Enable %1").arg(
                    pluginsModel.pluginRecord(enabledRoot.cell.cellRow).label || qsTr("search plugin"))
                onClicked: {
                    var id = pluginsModel.pluginId(enabledRoot.cell.cellRow)
                    Log.info("search", "Switch toggled plugin " + id + " -> " + checked)
                    SearchController.enablePlugin(id, checked)
                }
            }
            Label {
                anchors.centerIn: parent
                visible: !pluginsModel.isRegistered(enabledRoot.cell.cellRow)
                text: "—"
                color: root.pluginStateColor(enabledRoot.cell.cellRow)
                Accessible.name: root.pluginStateText(enabledRoot.cell.cellRow)
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
