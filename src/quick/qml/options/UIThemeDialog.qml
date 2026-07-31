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
    \qmltype UIThemeDialog
    \brief "Customize UI Theme" dialog.

    Lets the user load a color-override file (\c config.json / \c .qbtheme) into
    the running \c ThemeManager and preview how the key Material + qBittorrent
    extended roles resolve under the current scheme. Applying calls
    \c ThemeManager.loadColorOverrides(); the preview swatches read live
    \c Theme.color() values so the effect is immediate.
*/
Dialog {
    id: root

    // The roles previewed as swatches (grouped for legibility).
    readonly property var previewRoles: [
        "primary", "onPrimary", "primaryContainer", "secondary", "tertiary",
        "surface", "surfaceVariant", "onSurface", "onSurfaceVariant",
        "outline", "outlineVariant", "error",
        "success", "successEmphasis", "warning", "done", "info", "muted", "severe"
    ]

    property string themePath: ""

    title: qsTr("Customize UI Theme")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) * 0.95)
    height: Math.min(600, (parent ? parent.height : 600) * 0.95)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale
    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    function open() {
        Log.info("ui", "UIThemeDialog opened")
        visible = true
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

        LabeledField {
            label: qsTr("Theme file:")
            orientation: Qt.Vertical
            Layout.fillWidth: true
            PathField {
                Layout.fillWidth: true
                pickFolder: false
                title: qsTr("Select qBittorrent UI Theme file")
                placeholder: qsTr("Path to a config.json / .qbtheme file")
                path: root.themePath
                onPathChanged: root.themePath = path
            }
        }

        Label {
            text: qsTr("Color role preview")
            font: Typography.titleSmall
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: swatchGrid.implicitHeight
            ScrollBar.vertical: ScrollBar {}

            GridLayout {
                id: swatchGrid
                width: parent.width
                columns: 2
                columnSpacing: Spacing.md
                rowSpacing: Spacing.sm

                Repeater {
                    model: root.previewRoles
                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: Spacing.sm
                        Rectangle {
                            width: 28; height: 28
                            radius: Spacing.radiusField
                            color: Theme.color(modelData)
                            border.width: 1
                            border.color: Theme.color("outlineVariant")
                        }
                        Label {
                            text: modelData
                            font: Typography.bodyMedium
                            color: Theme.color("onSurface")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        topPadding: Spacing.sm
        spacing: Spacing.sm
        Button {
            text: qsTr("Close")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.reject()
        }
        Button {
            text: qsTr("Apply")
            highlighted: true
            enabled: root.themePath.length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: root.accept()
        }
    }

    onAccepted: {
        Log.info("ui", "UIThemeDialog applying theme overrides from " + root.themePath)
        var ok = ThemeManager.loadColorOverrides(root.themePath)
        if (ok)
            NotificationCenter.notify(qsTr("UI theme applied"), "success")
        else
            NotificationCenter.notify(qsTr("Failed to load the selected UI theme file"), "error")
    }
    onRejected: Log.debug("ui", "UIThemeDialog closed")
}
