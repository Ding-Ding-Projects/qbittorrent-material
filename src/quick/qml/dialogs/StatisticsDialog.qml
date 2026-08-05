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
    \qmltype StatisticsDialog
    \brief Material rebuild of the legacy \c StatsDialog.

    Shows live user / cache / performance / tracker statistics grouped into
    \l MaterialCard sections. Every value binds to \c StatisticsController.stats
    (a pre-formatted map) which refreshes off \c Session::statsUpdated, so the
    figures update without any polling here.
*/
Dialog {
    id: root

    title: qsTr("Statistics")
    modal: false
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, (parent ? parent.width : 420) * 0.9)
    height: Math.min(implicitHeight, (parent ? parent.height : 640) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: Log.debug("ui", "StatisticsDialog opened")
    onClosed: Log.debug("ui", "StatisticsDialog closed")

    // One caption/value line inside a statistics card.
    component StatRow: RowLayout {
        property string caption: ""
        property string value: ""
        property string tip: ""

        Layout.fillWidth: true
        spacing: Spacing.md

        Label {
            text: caption
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
            wrapMode: Text.WordWrap

            ToolTip.visible: tip.length > 0 && captionHover.hovered
            ToolTip.text: tip
            HoverHandler { id: captionHover }
        }

        Label {
            text: value
            font: Typography.mono
            color: Theme.color("onSurface")
            horizontalAlignment: Text.AlignRight
        }
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: root.availableWidth
            spacing: Spacing.md

            MaterialCard {
                title: qsTr("User statistics")
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.xs

                    StatRow { caption: qsTr("All-time upload:"); value: StatisticsController.stats.allTimeUpload }
                    StatRow { caption: qsTr("All-time download:"); value: StatisticsController.stats.allTimeDownload }
                    StatRow { caption: qsTr("All-time share ratio:"); value: StatisticsController.stats.allTimeShareRatio }
                    StatRow { caption: qsTr("Session waste:"); value: StatisticsController.stats.sessionWaste }
                    StatRow { caption: qsTr("Connected peers:"); value: StatisticsController.stats.connectedPeers }
                }
            }

            MaterialCard {
                title: qsTr("Cache statistics")
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.xs

                    StatRow {
                        visible: StatisticsController.readCacheHitsVisible
                        caption: qsTr("Read cache hits:")
                        value: StatisticsController.stats.readCacheHits
                    }
                    StatRow { caption: qsTr("Total buffer size:"); value: StatisticsController.stats.totalBufferSize }
                }
            }

            MaterialCard {
                title: qsTr("Performance statistics")
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.xs

                    StatRow { caption: qsTr("Write cache overload:"); value: StatisticsController.stats.writeCacheOverload }
                    StatRow { caption: qsTr("Read cache overload:"); value: StatisticsController.stats.readCacheOverload }
                    StatRow { caption: qsTr("Queued I/O jobs:"); value: StatisticsController.stats.queuedIOJobs }
                    StatRow { caption: qsTr("Average time in queue:"); value: StatisticsController.stats.averageTimeInQueue }
                    StatRow { caption: qsTr("Total queued size:"); value: StatisticsController.stats.totalQueuedSize }
                    StatRow {
                        caption: qsTr("Request latency:")
                        value: StatisticsController.stats.requestLatency
                        tip: qsTr("The time it takes from receiving a request from a peer until we're sending the response back on the socket")
                    }
                    StatRow { caption: qsTr("DHT nodes:"); value: StatisticsController.stats.dhtNodes }
                }
            }

            MaterialCard {
                title: qsTr("Tracker statistics")
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.xs

                    StatRow { caption: qsTr("Queued tracker announces:"); value: StatisticsController.stats.queuedTrackerAnnounces }
                }
            }
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Close")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: Log.debug("ui", "StatisticsDialog closed")
}
