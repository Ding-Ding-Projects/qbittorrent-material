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
    \qmltype TrackerStatusFilterPanel
    \brief The "Tracker status" sidebar sub-panel (separate-filter mode only).

    Bound to a \c TrackerStatusFilterModel instance (fixed rows: All / Warning /
    Tracker error / Other error). Roles: \c label ("Name (count)"), \c count,
    \c announceFlag (the \c TorrentAnnounceStatusFlag int, or -1 for "All").
    Selecting a row applies \c proxy.setAnnounceStatusFilter(announceFlag) — "All"
    (-1) clears the announce criterion. Only shown when
    \c TransferListFilters/SeparateTrackerStatusFilter is enabled.
*/
Column {
    id: root

    /*! The shared \c TorrentFilterProxyModel. */
    property var proxy: null

    width: parent ? parent.width : implicitWidth
    spacing: 0

    // Local selection state (default: All).
    property int selectedFlag: -1

    // Row index (RowKind) -> glyph.
    function _rowIcon(index) {
        switch (index) {
        case 0:  return Icons.dns;       // All
        case 1:  return Icons.warning;   // Warning
        case 2:  return Icons.error;     // Tracker error
        case 3:  return Icons.error;     // Other error
        default: return Icons.dns;
        }
    }

    TrackerStatusFilterModel { id: trackerStatusModel }

    StatusFilterMenu { id: contextMenu; proxy: root.proxy }

    Repeater {
        model: trackerStatusModel
        delegate: ItemDelegate {
            id: rowItem
            required property int index
            required property var model
            readonly property bool selected: root.selectedFlag === rowItem.model.announceFlag
            width: root.width
            height: Spacing.controlHeight
            padding: Spacing.xs
            hoverEnabled: true
            activeFocusOnTab: true

            background: Rectangle {
                color: rowItem.selected ? Theme.color("surfaceWarm")
                                        : (rowItem.hovered ? Theme.color("surfaceWarm") : "transparent")
                radius: Spacing.radiusControl
            }

            contentItem: RowLayout {
                spacing: Spacing.sm
                MDIcon {
                    icon: root._rowIcon(rowItem.index)
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

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            onClicked: {
                root.selectedFlag = rowItem.model.announceFlag;
                Log.info("ui", "Tracker-status filter -> " + rowItem.model.label
                         + " (flag " + rowItem.model.announceFlag + ")");
                if (root.proxy)
                    root.proxy.setAnnounceStatusFilter(rowItem.model.announceFlag);
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: contextMenu.popup()
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "TrackerStatusFilterPanel ready")
}
