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

    spacing: 0

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

    StatusFilterMenu { id: contextMenu; proxy: root.proxy }

    Repeater {
        model: statusModel
        delegate: ItemDelegate {
            id: rowItem
            required property int index
            required property var model
            readonly property bool selected: root.proxy && (root.proxy.statusFilter === model.value)
            width: root.width
            height: Spacing.controlHeight
            padding: Spacing.xs
            hoverEnabled: true
            activeFocusOnTab: true

            background: Rectangle {
                color: rowItem.selected ? Theme.color("surfaceWarm")
                                        : (rowPointer.containsMouse ? Theme.color("surfaceWarm") : "transparent")
                radius: Spacing.radiusControl
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

            onClicked: {
                Log.info("ui", "Status filter -> " + model.label + " (" + model.value + ")");
                if (root.proxy)
                    root.proxy.setStatusFilter(model.value);
            }

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        if (root.proxy)
                            root.proxy.setStatusFilter(rowItem.model.value);
                    } else {
                        Log.debug("ui", "Status filter panel context menu");
                        contextMenu.popup();
                    }
                }
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "StatusFilterPanel ready")
}
