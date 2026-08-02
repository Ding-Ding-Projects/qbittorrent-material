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
    \qmltype TrackersFilterList
    \brief The "Trackers" sidebar sub-panel.

    Bound to a \c TrackersFilterModel instance. Special rows: "All", "Trackerless",
    and — when tracker statuses are \e not shown in a separate panel — "Tracker
    error", "Other error" and "Warning". The remaining rows are one per tracker
    host. Roles: \c label, \c count, \c value (host), \c type (0 All, 1 Trackerless,
    2 TrackerError, 3 OtherError, 4 Warning, 5 Host), \c announceFlag.

    Selecting maps by \c type to the matching criterion on the shared \l proxy:
    host → \c setTrackerFilter(value); Trackerless → \c setTrackerFilter("");
    status rows → \c setAnnounceStatusFilter(announceFlag); All clears both.
*/
Column {
    id: root

    /*! The shared \c TorrentFilterProxyModel. */
    property var proxy: null

    /*! Mirrors \c TransferListFilters/SeparateTrackerStatusFilter. */
    property bool separateStatus: false

    width: parent ? parent.width : implicitWidth
    spacing: 0

    // Local selection state.
    property string selectedHost: ""
    property int selectedType: 0   // 0 == All (default)

    function _typeIcon(type) {
        switch (type) {
        case 0:  return Icons.dns;         // All
        case 1:  return Icons.cloud_off;   // Trackerless
        case 2:  return Icons.error;       // Tracker error
        case 3:  return Icons.error;       // Other error
        case 4:  return Icons.warning;     // Warning
        default: return Icons.dns;         // host
        }
    }

    function _apply(type, host, announceFlag) {
        root.selectedType = type;
        root.selectedHost = host;
        if (!root.proxy)
            return;
        switch (type) {
        case 0: // All — clear both tracker and announce criteria.
            Log.info("ui", "Tracker filter -> All");
            root.proxy.clearTrackerFilter();
            root.proxy.setAnnounceStatusFilter(-1);
            break;
        case 1:
            Log.info("ui", "Tracker filter -> Trackerless");
            root.proxy.trackerFilter = "";
            break;
        case 2:
        case 3:
        case 4:
            Log.info("ui", "Tracker filter -> announce status " + announceFlag);
            root.proxy.setAnnounceStatusFilter(announceFlag);
            break;
        default:
            Log.info("ui", "Tracker filter -> host '" + host + "'");
            root.proxy.trackerFilter = host;
            break;
        }
    }

    TrackersFilterModel {
        id: trackersModel
        separateStatusFilter: root.separateStatus
    }

    TrackersFilterMenu {
        id: contextMenu
        proxy: root.proxy
        onRemoveTrackerRequested: (host) => {
            if (typeof TransferController.removeTrackerFromAll === "function") {
                Log.info("ui", "Removing tracker '" + host + "' from all torrents");
                TransferController.removeTrackerFromAll(host);
            } else {
                Log.warning("ui", "Remove tracker: TransferController.removeTrackerFromAll is not available");
            }
        }
    }

    Repeater {
        model: trackersModel
        delegate: ItemDelegate {
            id: rowItem
            required property int index
            required property var model
            readonly property bool selected: (rowItem.model.type === root.selectedType)
                && ((rowItem.model.type !== 5) || (rowItem.model.value === root.selectedHost))
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
                    icon: root._typeIcon(rowItem.model.type)
                    size: 18
                    color: rowItem.selected ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                    Layout.leftMargin: Spacing.sm
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: rowItem.model.label
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

            onClicked: root._apply(rowItem.model.type, rowItem.model.value, rowItem.model.announceFlag)

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root._apply(rowItem.model.type, rowItem.model.value,
                                    rowItem.model.announceFlag);
                    } else {
                        contextMenu.isHost = (rowItem.model.type === 5);
                        contextMenu.host = contextMenu.isHost ? rowItem.model.value : "";
                        Log.debug("ui", "Tracker filter context menu (host=" + contextMenu.host + ")");
                        contextMenu.popup();
                    }
                }
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "TrackersFilterList ready")
}
