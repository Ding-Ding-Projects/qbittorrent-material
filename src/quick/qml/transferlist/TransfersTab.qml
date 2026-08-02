/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore
import qBittorrent

/*!
    Transfers workspace translated from the supplied applied kit: page title and
    primary action first, one dominant bordered table, then the real torrent
    properties surface. The shared proxy still drives both this table and the
    persistent shell sidebar.
*/
Item {
    id: root

    property var shell: null
    // Kept for shell/API compatibility; the filter UI now lives in the global nav.
    property bool sidebarVisible: false
    property alias proxy: transferProxy

    function toggleFilterFocus() { transferList.focusFilter() }

    TorrentFilterProxyModel {
        id: transferProxy
        sourceModel: TransferListModel
    }

    Settings {
        id: layoutState
        category: "TransfersTab"
        property string innerState: ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.xl
        spacing: Spacing.lg

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.lg

            ColumnLayout {
                spacing: Spacing.xs
                Label {
                    text: qsTr("Transfers")
                    font: Typography.pageTitle
                    color: Theme.color("onBackground")
                }
                Label {
                    text: qsTr("%1 torrents shown").arg(transferProxy.count || 0)
                    font: Typography.bodyLarge
                    color: Theme.color("muted")
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                id: addButton
                action: root.shell ? root.shell.actionOpen : null
                highlighted: true
                implicitHeight: Spacing.controlHeight
                leftPadding: Spacing.lg
                rightPadding: Spacing.lg
                contentItem: RowLayout {
                    spacing: Spacing.sm
                    MDIcon { icon: Icons.add; size: 18; color: Theme.color("onPrimary") }
                    Label {
                        text: qsTr("Add torrent")
                        font: Typography.labelLarge
                        color: Theme.color("onPrimary")
                    }
                }
                Accessible.name: qsTr("Add torrent")
            }
        }

        SplitView {
            id: innerSplit
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Vertical

            handle: Rectangle {
                implicitHeight: Spacing.lg
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 48
                    height: 3
                    radius: 2
                    color: SplitHandle.pressed
                        ? Theme.color("primary") : Theme.color("outlineVariant")
                }
            }

            TransferListView {
                id: transferList
                proxy: transferProxy
                shell: root.shell
                SplitView.fillHeight: true
                SplitView.minimumHeight: 220
            }

            PropertiesPanel {
                id: properties
                SplitView.preferredHeight: 270
                SplitView.minimumHeight: collapsedHeight
            }

            Component.onCompleted: {
                if (layoutState.innerState.length > 0)
                    innerSplit.restoreState(layoutState.innerState)
            }
            Component.onDestruction: layoutState.innerState = innerSplit.saveState()
        }
    }

    Component.onCompleted: Log.info("ui", "Design-system Transfers workspace ready")
}
