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
    \qmltype EditWebSeedDialog
    \brief One-line prompt to edit an existing HTTP source (web seed) URL.

    Seed \l originalUrl and \l row before \c open(). Rejects duplicates (other
    than the original) inline. On accept emits \l webSeedEdited() with the old
    and new URL; the caller replaces via \c webSeedModel.editWebSeed().
*/
Dialog {
    id: root

    /*! The URL currently being edited (and the initial field text). */
    property string originalUrl: ""

    /*! Row index of the web seed in the model (carried for the caller). */
    property int row: -1

    /*! Emitted with the row, the original URL and the new URL. */
    signal webSeedEdited(int row, string oldUrl, string newUrl)

    title: qsTr("Edit web seed URL")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, (parent ? parent.width : 480) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    onOpened: {
        Log.debug("ui", "EditWebSeedDialog opened for row " + row)
        urlField.text = originalUrl
        urlField.forceActiveFocus()
        urlField.selectAll()
    }

    function _isDuplicate() {
        const t = urlField.text.trim()
        const m = PropertiesController.webSeedModel
        return t !== originalUrl && m && m.contains(t)
    }

    function acceptEnabled() {
        return urlField.text.trim().length > 0 && !_isDuplicate()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Web seed URL:")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        TextField {
            id: urlField
            Layout.fillWidth: true
            selectByMouse: true
            font: Typography.mono
            onAccepted: if (root.acceptEnabled()) root.accept()
        }

        Label {
            text: qsTr("This web seed is already in the list.")
            visible: root._isDuplicate()
            font: Typography.labelSmall
            color: Theme.color("error")
            Layout.fillWidth: true
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
            enabled: root.acceptEnabled()
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "EditWebSeedDialog accepted for row " + row)
        root.webSeedEdited(row, originalUrl, urlField.text.trim())
    }

    onRejected: Log.debug("ui", "EditWebSeedDialog rejected")
}
