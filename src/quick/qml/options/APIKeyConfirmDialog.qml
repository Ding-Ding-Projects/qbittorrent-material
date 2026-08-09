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
    \qmltype APIKeyConfirmDialog
    \brief Confirmation for the staged WebUI API-key generate / rotate actions.

    API-key edits remain staged in OptionsController and persist only through
    the outer Options dialog's Apply or OK action. Set \l mode to \c "generate"
    or \c "rotate", call \c open(); on confirmation it emits \c confirmed(mode).
    Deletion deliberately bypasses this ordinary confirmation and is routed by
    WebUIPage through SuperConfirmDialog instead.
*/
Dialog {
    id: root

    /*! One of "generate" or "rotate". */
    property string mode: "generate"

    /*! Emitted when the user confirms the action; carries \l mode. */
    signal confirmed(string mode)

    title: mode === "rotate" ? qsTr("Rotate API key") : qsTr("Generate API key")

    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, (parent ? parent.width : 440) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale
    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    function open() {
        Log.info("ui", "APIKeyConfirmDialog opened (mode=" + mode + ")")
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

    contentItem: RowLayout {
        spacing: Spacing.md
        Label {
            text: root.mode === "rotate"
                  ? qsTr("Rotating the API key stages a replacement. The saved key remains active until you choose Apply or OK; then clients using it lose Web UI access.")
                  : qsTr("Generate a new API key for programmatic access. It is saved only after you choose Apply or OK.")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        topPadding: Spacing.sm
        spacing: Spacing.sm
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: root.mode === "rotate" ? qsTr("Stage rotation") : qsTr("Stage generation")
            highlighted: true
            Material.accent: Theme.color("primary")
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        // Deletion must never regress to this ordinary confirmation path. The
        // Web UI page owns the two-key/full-slider SuperConfirmDialog route.
        if (mode === "delete") {
            Log.warning("ui", "APIKeyConfirmDialog rejected unsafe delete confirmation route")
            return
        }
        Log.info("ui", "APIKeyConfirmDialog confirmed (mode=" + mode + ")")
        root.confirmed(mode)
    }
    onRejected: Log.debug("ui", "APIKeyConfirmDialog cancelled (mode=" + mode + ")")
}
