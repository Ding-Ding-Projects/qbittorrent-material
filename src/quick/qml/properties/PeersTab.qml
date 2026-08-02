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
    \qmltype PeersTab
    \brief The properties "Peers" tab.

    A \c DataTable over \c PropertiesController.peerModel (a \c PeerListModel) with
    the legacy peer columns and a country/region flag cell (shown only when peer
    country resolution is enabled). The context menu (Add peers / Copy IP:port /
    Ban peer) dispatches straight to the model's own invokables — \c addPeers,
    \c banPeers, \c peerEndpoint — so no extra controller surface is needed.

    The model only refreshes while its \c active flag is set; this view drives
    that flag from its own visibility so the async peer fetch runs solely while
    the Peers tab is on screen.
*/
Item {
    id: root

    readonly property var peerModel: PropertiesController.peerModel

    // Peer-country resolution toggle (legacy setting key preserved verbatim).
    readonly property bool resolveCountries:
        Preferences.value("Preferences/Connection/ResolvePeerCountries", false) === true

    // Keep the model's async refresh gated on this tab being visible.
    onVisibleChanged: {
        if (peerModel)
            peerModel.active = visible
        Log.debug("ui", "PeersTab visible=" + visible)
    }
    Component.onCompleted: {
        if (peerModel && visible)
            peerModel.active = true
        Log.debug("ui", "PeersTab loaded")
    }

    // Extract the bare host from an "ip:port" / "[ipv6]:port" endpoint.
    function _hostOf(endpoint) {
        if (endpoint.length === 0)
            return ""
        if (endpoint.charAt(0) === "[") {
            const close = endpoint.indexOf("]")
            return close > 0 ? endpoint.substring(1, close) : endpoint
        }
        const colon = endpoint.lastIndexOf(":")
        return colon > 0 ? endpoint.substring(0, colon) : endpoint
    }

    function _selectedEndpoints() {
        const out = []
        const rows = table.selectedRows
        for (let i = 0; i < rows.length; ++i) {
            const ep = peerModel.peerEndpoint(rows[i])
            if (ep.length > 0)
                out.push(ep)
        }
        return out
    }

    function _selectedHosts() {
        return _selectedEndpoints().map(_hostOf).filter(h => h.length > 0)
    }

    // Minimal QML-only clipboard (hidden, off-screen TextEdit).
    TextEdit {
        id: clip
        visible: false
        width: 0
        height: 0
    }
    function _copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        Log.info("ui", "PeersTab copied " + text.split("\n").length + " endpoint(s) to clipboard")
    }

    DataTable {
        id: table
        anchors.fill: parent
        anchors.margins: Spacing.sm
        model: root.peerModel
        persistKey: "TorrentProperties/PeerList"

        columns: [
            { role: "countryCode",   title: qsTr("Country/Region"), width: 120, align: Qt.AlignLeft,  visible: root.resolveCountries, resizable: true },
            { role: "ip",            title: qsTr("IP"),             width: 150, align: Qt.AlignLeft,  visible: true,  resizable: true },
            { role: "port",          title: qsTr("Port"),           width: 64,  align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "connection",    title: qsTr("Connection"),     width: 90,  align: Qt.AlignLeft,  visible: true,  resizable: true },
            { role: "flags",         title: qsTr("Flags"),          width: 90,  align: Qt.AlignLeft,  visible: true,  resizable: true },
            { role: "client",        title: qsTr("Client"),         width: 160, align: Qt.AlignLeft,  visible: true,  resizable: true },
            { role: "peerIdClient",  title: qsTr("Peer ID Client"), width: 140, align: Qt.AlignLeft,  visible: false, resizable: true },
            { role: "progress",      title: qsTr("Progress"),       width: 80,  align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "downSpeed",     title: qsTr("Down Speed"),     width: 100, align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "upSpeed",       title: qsTr("Up Speed"),       width: 100, align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "totalDownload", title: qsTr("Downloaded"),     width: 100, align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "totalUpload",   title: qsTr("Uploaded"),       width: 100, align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "relevance",     title: qsTr("Relevance"),      width: 90,  align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "contribution",  title: qsTr("Contribution"),  width: 100, align: Qt.AlignRight, visible: true,  resizable: true },
            { role: "files",         title: qsTr("Files"),          width: 200, align: Qt.AlignLeft,  visible: true,  resizable: true }
        ]

        delegateFor: (col) => col.role === "countryCode" ? countryCellComp : null

        onContextRequested: (row, pos) => {
            peerMenu.x = pos.x
            peerMenu.y = pos.y
            peerMenu.open()
        }
    }

    // Country/region flag + code cell.
    Component {
        id: countryCellComp
        Item {
            id: countryCell
            anchors.fill: parent
            readonly property string iso: (parent.value !== undefined && parent.value !== null)
                                          ? ("" + parent.value) : ""

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Spacing.sm
                spacing: Spacing.xs

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 12
                    fillMode: Image.PreserveAspectFit
                    visible: countryCell.iso.length > 0
                    source: countryCell.iso.length > 0 ? ("image://flags/" + countryCell.iso) : ""
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: countryCell.iso.toUpperCase()
                    font: Typography.bodyMedium
                    color: Theme.color("onSurface")
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- Context menu ---------------------------------------------------------
    Menu {
        id: peerMenu
        Material.elevation: Spacing.elevationMenu

        MenuItem {
            text: qsTr("Add peers...")
            enabled: PropertiesController.hasTorrent
            onTriggered: {
                Log.info("ui", "PeersTab add peers")
                addPeersDialog.open()
            }
        }
        MenuItem {
            text: qsTr("Copy IP:port")
            enabled: table.selectedRows.length > 0
            onTriggered: {
                const endpoints = root._selectedEndpoints()
                Log.info("ui", "PeersTab copy " + endpoints.length + " peer(s)")
                root._copy(endpoints.join("\n"))
            }
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Ban peer permanently")
            enabled: table.selectedRows.length > 0
            onTriggered: {
                Log.info("ui", "PeersTab ban peers requested " + JSON.stringify(table.selectedRows))
                banConfirm.open()
            }
        }
    }

    // ---- Dialogs --------------------------------------------------------------
    AddPeersDialog {
        id: addPeersDialog
        onPeersAccepted: (lines) => {
            if (!root.peerModel)
                return
            const accepted = root.peerModel.addPeers(lines)
            Log.info("ui", "PeersTab added " + accepted + " of " + lines.length + " peer line(s)")
        }
    }

    ConfirmDialog {
        id: banConfirm
        title: qsTr("Ban peer permanently")
        text: qsTr("Are you sure you want to permanently ban the selected peers?")
        destructive: true
        acceptText: qsTr("Ban")
        onAccepted: {
            const hosts = root._selectedHosts()
            Log.info("ui", "PeersTab ban confirmed for " + hosts.length + " host(s)")
            if (root.peerModel && hosts.length > 0)
                root.peerModel.banPeers(hosts)
        }
        onRejected: Log.debug("ui", "PeersTab ban cancelled")
    }
}
