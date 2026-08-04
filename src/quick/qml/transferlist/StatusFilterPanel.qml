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
    \qmltype StatusFilterPanel
    \brief The "Status" sidebar sub-panel — fixed rows with live counts.

    Bound to a \c StatusFilterModel instance (fixed \c TorrentFilter::Status rows,
    each with a live count and a hide-zero policy). Selecting a row sets the shared
    \l proxy's status filter (\c proxy.setStatusFilter(value)); the active row is
    reflected from \c proxy.statusFilter. When
    \c TransferListFilters/HideZeroStatusFilters is on, zero-count rows are hidden
    (except "All") by the model.
*/
Column {
    id: root

    /*! The shared \c TorrentFilterProxyModel. */
    property var proxy: null
    property int rovingIndex: 0
    property var statusValues: []

    spacing: 0
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Status filters")

    function syncRovingIndex() {
        if (statusRepeater.count <= 0) {
            rovingIndex = -1
            return
        }
        if (proxy) {
            for (var i = 0; i < statusRepeater.count; ++i) {
                if (statusValues[i] === proxy.statusFilter) {
                    rovingIndex = i
                    return
                }
            }
        }
        rovingIndex = Math.max(0, Math.min(rovingIndex, statusRepeater.count - 1))
    }

    function activateIndex(index, focusReason) {
        if (statusRepeater.count <= 0)
            return
        var wrapped = ((index % statusRepeater.count) + statusRepeater.count)
            % statusRepeater.count
        var row = statusRepeater.itemAt(wrapped)
        if (!row)
            return
        rovingIndex = wrapped
        if (proxy && statusValues[wrapped] !== undefined)
            proxy.statusFilter = statusValues[wrapped]
        row.forceActiveFocus(focusReason)
    }

    function registerStatus(index, value) {
        var next = statusValues.slice()
        next[index] = value
        statusValues = next
    }

    function moveSelection(fromIndex, delta) {
        activateIndex(fromIndex + delta, Qt.TabFocusReason)
    }

    onProxyChanged: Qt.callLater(syncRovingIndex)

    // TorrentFilter::Status int -> the status glyph (DESIGN_SYSTEM §4).
    function _statusIcon(value) {
        switch (value) {
        case 0:  return Icons.apps;              // All
        case 1:  return Icons.download;          // Downloading
        case 2:  return Icons.upload;            // Seeding
        case 3:  return Icons.check_circle;      // Completed
        case 4:  return Icons.play_arrow;        // Running
        case 5:  return Icons.pause;             // Stopped
        case 6:  return Icons.trending_up;       // Active
        case 7:  return Icons.trending_down;     // Inactive
        case 8:  return Icons.hourglass_empty;   // Stalled
        case 9:  return Icons.hourglass_empty;   // Stalled Uploading
        case 10: return Icons.hourglass_empty;   // Stalled Downloading
        case 11: return Icons.fact_check;        // Checking
        case 12: return Icons.drive_file_move;   // Moving
        case 13: return Icons.error;             // Errored
        default: return Icons.apps;
        }
    }

    StatusFilterModel {
        id: statusModel
        hideZero: Preferences.value("TransferListFilters/HideZeroStatusFilters", false) === true
    }

    // Keep the model's hide-zero policy in sync with the preference.
    Connections {
        target: Preferences
        function onChanged() {
            statusModel.hideZero =
                Preferences.value("TransferListFilters/HideZeroStatusFilters", false) === true;
        }
    }

    Connections {
        target: root.proxy
        ignoreUnknownSignals: true
        function onStatusFilterChanged() { Qt.callLater(root.syncRovingIndex) }
    }

    Connections {
        target: statusModel
        function onModelReset() {
            root.statusValues = []
            Qt.callLater(root.syncRovingIndex)
        }
    }

    StatusFilterMenu { id: contextMenu; proxy: root.proxy }

    Repeater {
        id: statusRepeater
        model: statusModel
        onCountChanged: Qt.callLater(root.syncRovingIndex)
        delegate: ItemDelegate {
            id: rowItem
            required property int index
            required property var model
            readonly property bool selected: root.proxy && (root.proxy.statusFilter === model.value)
            width: root.width
            height: Spacing.controlHeight
            padding: Spacing.xs
            hoverEnabled: true
            activeFocusOnTab: rowItem.index === root.rovingIndex
            Accessible.role: Accessible.RadioButton
            Accessible.name: rowItem.model.label
            Accessible.description: qsTr("%1 torrents").arg(rowItem.model.count)
            Accessible.checked: rowItem.selected
            Component.onCompleted: root.registerStatus(rowItem.index, rowItem.model.value)
            onIndexChanged: root.registerStatus(rowItem.index, rowItem.model.value)
            onActiveFocusChanged: {
                if (activeFocus)
                    root.rovingIndex = rowItem.index
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                    root.moveSelection(rowItem.index, -1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                    root.moveSelection(rowItem.index, 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter) {
                    root.activateIndex(rowItem.index, Qt.ShortcutFocusReason)
                    event.accepted = true
                }
            }

            background: Rectangle {
                color: rowItem.selected ? Theme.color("surfaceWarm")
                                        : (rowPointer.containsMouse ? Theme.color("surfaceWarm") : "transparent")
                radius: Spacing.radiusControl
                border.width: rowItem.activeFocus ? 2 : 0
                border.color: Theme.color("focusRing")
            }

            contentItem: RowLayout {
                spacing: Spacing.sm
                MDIcon {
                    icon: root._statusIcon(rowItem.model.value)
                    size: 18
                    color: rowItem.selected ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                    Layout.leftMargin: Spacing.sm
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: rowItem.model.label + " (" + rowItem.model.count + ")"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    font: Typography.bodyMedium
                    color: rowItem.selected ? Theme.color("primary") : Theme.color("onSurface")
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        Log.debug("ui", "Status filter panel context menu");
                        contextMenu.popup();
                        return
                    }
                    Log.info("ui", "Status filter -> " + rowItem.model.label
                        + " (" + rowItem.model.value + ")");
                    root.activateIndex(rowItem.index, Qt.MouseFocusReason)
                }
            }
        }
    }

    Component.onCompleted: {
        Log.debug("ui", "StatusFilterPanel ready")
        Qt.callLater(syncRovingIndex)
    }
}
