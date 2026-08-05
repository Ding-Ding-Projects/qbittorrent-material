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
    \qmltype EditTrackerDialog
    \brief One-line prompt to edit a tracker's announce URL.

    Seed \l originalUrl before \c open(); on accept emits \l trackerEdited() with
    the (trimmed, non-empty) new URL. The caller passes the old + new URL to
    \c PropertiesController.editTracker() which validates and replaces.
*/
Dialog {
    id: root

    /*! The current URL being edited (also the initial field text). */
    property string originalUrl: ""

    /*! Row index of the tracker in the model (carried for the caller). */
    property int row: -1

    /*! Emitted with the new URL. */
    signal trackerEdited(int row, string newUrl)

    title: qsTr("Edit tracker URL")
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
        Log.debug("ui", "EditTrackerDialog opened for row " + row)
        urlField.text = originalUrl
        urlField.forceActiveFocus()
        urlField.selectAll()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Tracker URL:")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        TextField {
            id: urlField
            Layout.fillWidth: true
            selectByMouse: true
            font: Typography.mono
            onAccepted: if (acceptEnabled()) root.accept()
        }
    }

    function acceptEnabled() {
        return urlField.text.trim().length > 0
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
        Log.info("ui", "EditTrackerDialog accepted for row " + row)
        root.trackerEdited(row, urlField.text.trim())
    }

    onRejected: Log.debug("ui", "EditTrackerDialog rejected")
}
