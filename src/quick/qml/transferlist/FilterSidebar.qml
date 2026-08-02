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
    \qmltype FilterSidebar
    \brief The left filter sidebar of the Transfers tab.

    A vertically stacked, scrollable column of collapsible sections, in order:
    Status, Categories, Tags, (Tracker status — only when the
    \c TransferListFilters/SeparateTrackerStatusFilter preference is on) and
    Trackers. Each section hosts its dedicated sub-panel; every panel applies its
    selection to the shared \l proxy (a \c TorrentFilterProxyModel owned by
    \l TransfersTab). Section expanded-state persists per section.
*/
Rectangle {
    id: root

    /*! The shared sort/filter proxy every panel drives (set by \l TransfersTab). */
    property var proxy: null

    color: Theme.color("surface")

    // Not a binding on Preferences.value() (a plain function call is not
    // reactive) — recomputed on startup and whenever preferences change.
    property bool separateTrackerStatus: false

    function _refreshPrefs() {
        separateTrackerStatus =
            Preferences.value("TransferListFilters/SeparateTrackerStatusFilter", false) === true;
    }

    // Live-refresh when the pref changes so the section appears / disappears.
    Connections {
        target: Preferences
        function onChanged() { root._refreshPrefs(); }
    }

    ScrollView {
        id: filterScroll
        anchors.fill: parent
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        ColumnLayout {
            // The vertical scrollbar consumes part of the viewport.  Sizing the
            // delegates to the outer rectangle placed their labels and click
            // targets underneath it, which was especially visible with the
            // longest high-playfulness translations.
            width: Math.max(0, filterScroll.availableWidth)
            spacing: 0

            CollapsibleSection {
                Layout.fillWidth: true
                title: qsTr("Status")
                icon: Icons.filter_list
                persistKey: "TransferListFilters/Status"
                onToggled: (open) => Log.debug("ui", "Status filter section -> " + open)
                StatusFilterPanel { width: parent ? parent.width : 0; proxy: root.proxy }
            }

            CollapsibleSection {
                Layout.fillWidth: true
                title: qsTr("Categories")
                icon: Icons.category
                persistKey: "TransferListFilters/Categories"
                onToggled: (open) => Log.debug("ui", "Categories filter section -> " + open)
                CategoryFilterTree { width: parent ? parent.width : 0; proxy: root.proxy }
            }

            CollapsibleSection {
                Layout.fillWidth: true
                title: qsTr("Tags")
                icon: Icons.sell
                persistKey: "TransferListFilters/Tags"
                onToggled: (open) => Log.debug("ui", "Tags filter section -> " + open)
                TagFilterList { width: parent ? parent.width : 0; proxy: root.proxy }
            }

            CollapsibleSection {
                Layout.fillWidth: true
                visible: root.separateTrackerStatus
                title: qsTr("Tracker status")
                icon: Icons.warning
                persistKey: "TransferListFilters/TrackerStatus"
                onToggled: (open) => Log.debug("ui", "Tracker status filter section -> " + open)
                TrackerStatusFilterPanel { width: parent ? parent.width : 0; proxy: root.proxy }
            }

            CollapsibleSection {
                Layout.fillWidth: true
                title: qsTr("Trackers")
                icon: Icons.dns
                persistKey: "TransferListFilters/Trackers"
                onToggled: (open) => Log.debug("ui", "Trackers filter section -> " + open)
                TrackersFilterList {
                    width: parent ? parent.width : 0
                    proxy: root.proxy
                    separateStatus: root.separateTrackerStatus
                }
            }

            // Absorb remaining vertical space so sections stack from the top.
            Item { Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }

    Component.onCompleted: {
        _refreshPrefs();
        Log.debug("ui", "FilterSidebar ready (separateTrackerStatus=" + separateTrackerStatus + ")");
    }
}
