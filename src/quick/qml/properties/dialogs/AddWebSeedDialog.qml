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
    \qmltype AddWebSeedDialog
    \brief One-line prompt to add an HTTP source (web seed) URL.

    Defaults the field to \c http://www. like the legacy dialog. Duplicate URLs
    are rejected inline (checked via \c PropertiesController.webSeedModel.contains()).
    On accept emits \l webSeedAdded() with the new URL.
*/
Dialog {
    id: root

    /*! Emitted with the new web-seed URL. */
    signal webSeedAdded(string url)

    title: qsTr("Add web seed")
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
        Log.debug("ui", "AddWebSeedDialog opened")
        urlField.text = "http://www."
        urlField.forceActiveFocus()
        urlField.selectAll()
    }

    function _isDuplicate() {
        const m = PropertiesController.webSeedModel
        return m ? m.contains(urlField.text.trim()) : false
    }

    function acceptEnabled() {
        return urlField.text.trim().length > 0 && !_isDuplicate()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Add web seed:")
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
            visible: urlField.text.trim().length > 0 && root._isDuplicate()
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
        Log.info("ui", "AddWebSeedDialog accepted: " + urlField.text.trim())
        root.webSeedAdded(urlField.text.trim())
    }

    onRejected: Log.debug("ui", "AddWebSeedDialog rejected")
}
