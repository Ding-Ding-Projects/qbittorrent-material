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
    \qmltype TrackersTab
    \brief The properties "Trackers" tab.

    A Material \c TableView (with a synced \c HorizontalHeaderView) over
    \c PropertiesController.trackerModel — the \c TrackerListModel whose top-level
    rows are the sticky \c [DHT] / \c [PeX] / \c [LSD] pseudo-rows followed by one
    row per tracker. The model is multi-column (URL / Tier / BT Protocol / Status
    / Peers / Seeds / Leeches / Times Downloaded / Message / Next Announce / Min
    Announce), read per cell through \c model.display, with sticky rows rendered
    muted.

    The tracker model is read-only, so add/edit/remove/reannounce dispatch to the
    controller. Those mutation verbs are invoked defensively (see \l _invoke) so a
    not-yet-wired bridge degrades to a Snackbar instead of throwing.
*/
Item {
    id: root

    readonly property var trackerModel: PropertiesController.trackerModel

    // Per-column fixed widths, indexed by TrackerListModel column order.
    readonly property var _widths: [280, 56, 90, 120, 70, 70, 70, 120, 200, 110, 110]
    readonly property var _titles: [
        qsTr("URL/Announce Endpoint"), qsTr("Tier"), qsTr("BT Protocol"), qsTr("Status"),
        qsTr("Peers"), qsTr("Seeds"), qsTr("Leeches"), qsTr("Times Downloaded"),
        qsTr("Message"), qsTr("Next Announce"), qsTr("Min Announce")
    ]

    // Captured as the URL column renders: row -> url / sticky flag.
    property var _urlByRow: ({})
    property var _stickyByRow: ({})

    function _urlOf(row) { return _urlByRow[row] !== undefined ? _urlByRow[row] : "" }
    function _isSticky(row) { return _stickyByRow[row] === true }

    // Every one of these is a real controller verb; the tab used to route them
    // through a shim that only wrote a log line, so the whole tracker mutation
    // menu looked live and did nothing.
    function _invoke(method) {
        const args = Array.prototype.slice.call(arguments, 1)
        return PropertiesController[method].apply(PropertiesController, args)
    }

    // The controller reports every outcome, so a command can never appear to
    // have worked when it did not.
    Connections {
        target: PropertiesController
        function onTrackerActionFinished(ok, message) {
            Log.info("ui", "Tracker action: " + message)
            NotificationCenter.notify(message, ok ? "success" : "warning")
        }
    }

    // Minimal QML-only clipboard (hidden, off-screen TextEdit).
    TextEdit { id: clip; visible: false; width: 0; height: 0 }
    function _copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        Log.info("ui", "TrackersTab copied tracker URL to clipboard")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.sm
        spacing: 0

        HorizontalHeaderView {
            id: header
            Layout.fillWidth: true
            syncView: tableView
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property int column
                implicitHeight: 32
                color: Theme.color("surfaceVariant")

                Label {
                    anchors.fill: parent
                    leftPadding: Spacing.sm
                    rightPadding: Spacing.sm
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: column >= 4 && column <= 10 ? Text.AlignRight : Text.AlignLeft
                    text: column < root._titles.length ? root._titles[column] : ""
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.color("outline")
                }
            }
        }

        TableView {
            id: tableView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.trackerModel
            boundsBehavior: Flickable.StopAtBounds
            columnSpacing: 0
            rowSpacing: 0

            property int selectedRow: -1

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            columnWidthProvider: (column) => column < root._widths.length ? root._widths[column] : 100
            rowHeightProvider: () => 34

            delegate: Rectangle {
                id: cell
                required property int row
                required property int column
                required property var model

                implicitHeight: 34
                readonly property bool sticky: model.sticky === true
                readonly property bool selected: tableView.selectedRow === row

                color: selected
                       ? Qt.alpha(Theme.color("primary"), 0.12)
                       : (hover.hovered ? Qt.alpha(Theme.color("onSurface"), 0.08) : "transparent")

                HoverHandler { id: hover }

                // Capture URL + sticky for the row as the first column renders.
                Component.onCompleted: if (column === 0) {
                    root._urlByRow[row] = "" + (model.display !== undefined ? model.display : "")
                    root._stickyByRow[row] = cell.sticky
                }
                onModelChanged: if (column === 0) {
                    root._urlByRow[row] = "" + (model.display !== undefined ? model.display : "")
                    root._stickyByRow[row] = cell.sticky
                }

                Label {
                    anchors.fill: parent
                    leftPadding: Spacing.sm
                    rightPadding: Spacing.sm
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: (model.alignRight === true) ? Text.AlignRight : Text.AlignLeft
                    text: model.display !== undefined && model.display !== null ? ("" + model.display) : ""
                    font: Typography.bodyMedium
                    color: cell.sticky ? Theme.color("muted") : Theme.color("onSurface")
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.color("outlineVariant"), 0.5)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        tableView.selectedRow = cell.row
                        if (mouse.button === Qt.RightButton) {
                            const p = mapToItem(root, mouse.x, mouse.y)
                            trackerMenu.x = p.x
                            trackerMenu.y = p.y
                            trackerMenu.open()
                        }
                    }
                    onDoubleClicked: {
                        tableView.selectedRow = cell.row
                        if (!root._isSticky(cell.row))
                            root._openEdit(cell.row)
                    }
                }
            }
        }
    }

    // ---- Context menu ---------------------------------------------------------
    Menu {
        id: trackerMenu
        Material.elevation: Spacing.elevationMenu

        readonly property int currentRow: tableView.selectedRow
        readonly property bool realRow: currentRow >= 0 && !root._isSticky(currentRow)

        MenuItem {
            text: qsTr("Add trackers...")
            enabled: PropertiesController.hasTorrent
            onTriggered: {
                Log.info("ui", "TrackersTab add trackers")
                addTrackersDialog.open()
            }
        }

        MenuSeparator { visible: trackerMenu.realRow }

        MenuItem {
            text: qsTr("Edit tracker URL...")
            visible: trackerMenu.realRow
            height: visible ? implicitHeight : 0
            onTriggered: root._openEdit(trackerMenu.currentRow)
        }
        MenuItem {
            text: qsTr("Remove tracker")
            visible: trackerMenu.realRow
            height: visible ? implicitHeight : 0
            onTriggered: {
                const url = root._urlOf(trackerMenu.currentRow)
                Log.info("ui", "TrackersTab remove tracker " + url)
                root._invoke("removeTrackers", [url])
            }
        }
        MenuItem {
            text: qsTr("Copy tracker URL")
            visible: trackerMenu.realRow
            height: visible ? implicitHeight : 0
            onTriggered: root._copy(root._urlOf(trackerMenu.currentRow))
        }
        MenuItem {
            text: qsTr("Force reannounce to selected trackers")
            visible: trackerMenu.realRow
            height: visible ? implicitHeight : 0
            onTriggered: {
                const url = root._urlOf(trackerMenu.currentRow)
                Log.info("ui", "TrackersTab reannounce tracker " + url)
                root._invoke("reannounceToTrackers", [url])
            }
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Force reannounce to all trackers")
            enabled: PropertiesController.hasTorrent
            onTriggered: {
                Log.info("ui", "TrackersTab reannounce all")
                root._invoke("reannounceToAllTrackers")
            }
        }
    }

    function _openEdit(row) {
        if (row < 0 || root._isSticky(row))
            return
        editTrackerDialog.row = row
        editTrackerDialog.originalUrl = root._urlOf(row)
        editTrackerDialog.open()
    }

    // ---- Dialogs --------------------------------------------------------------
    AddTrackersDialog {
        id: addTrackersDialog
        onTrackersAccepted: (text) => {
            Log.info("ui", "TrackersTab committing added trackers")
            root._invoke("addTrackers", text)
        }
    }

    EditTrackerDialog {
        id: editTrackerDialog
        onTrackerEdited: (row, newUrl) => {
            Log.info("ui", "TrackersTab edit tracker row " + row)
            root._invoke("editTracker", root._urlOf(row), newUrl)
        }
    }

    Component.onCompleted: Log.debug("ui", "TrackersTab loaded")
}
