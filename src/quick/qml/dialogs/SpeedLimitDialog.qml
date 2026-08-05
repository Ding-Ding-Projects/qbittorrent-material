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
    \qmltype SpeedLimitDialog
    \brief Material rebuild of the legacy \c SpeedLimitDialog ("Global Speed
           Limits").

    Two groups (regular + alternative) each expose an Upload and a Download row,
    where a \c Slider and a \l SpeedSpinBox stay in sync. Values are edited in
    KiB/s (0 = unlimited, shown as \c ∞); on OK they are handed to
    \c SpeedLimitController.apply(), which only writes the limits that changed.
*/
Dialog {
    id: root

    title: qsTr("Global Speed Limits")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("ui", "SpeedLimitDialog opened")
        SpeedLimitController.load()
        uploadRow.value = SpeedLimitController.uploadLimit
        downloadRow.value = SpeedLimitController.downloadLimit
        altUploadRow.value = SpeedLimitController.altUploadLimit
        altDownloadRow.value = SpeedLimitController.altDownloadLimit
    }

    // A single Upload/Download limit row: a slider synced with a spin box.
    component LimitRow: RowLayout {
        id: limitRow
        property string caption: ""
        property alias value: spin.value

        Layout.fillWidth: true
        spacing: Spacing.md

        Label {
            text: limitRow.caption
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.preferredWidth: 90
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            from: 0
            to: Math.max(10000, spin.value)
            stepSize: 1
            onMoved: spin.value = Math.round(value)
        }

        // Keeps the slider handle in sync even after a drag breaks the direct
        // binding, and after edits made through the spin box.
        Binding {
            target: slider
            property: "value"
            value: spin.value
        }

        SpeedSpinBox {
            id: spin
            from: 0
            to: 2000000
            unlimitedValue: 0
            Layout.preferredWidth: 150
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

    contentItem: ColumnLayout {
        spacing: Spacing.md

        MaterialCard {
            title: qsTr("Speed limits")
            titleIcon: Icons.speed
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm

                LimitRow { id: uploadRow; caption: qsTr("Upload:") }
                LimitRow { id: downloadRow; caption: qsTr("Download:") }
            }
        }

        MaterialCard {
            title: qsTr("Alternative speed limits")
            titleIcon: Icons.speed
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm

                LimitRow { id: altUploadRow; caption: qsTr("Upload:") }
                LimitRow { id: altDownloadRow; caption: qsTr("Download:") }
            }
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "SpeedLimitDialog accepted; applying global speed limits")
        SpeedLimitController.apply(uploadRow.value, downloadRow.value
                , altUploadRow.value, altDownloadRow.value)
    }

    onRejected: Log.debug("ui", "SpeedLimitDialog rejected")
}
