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
    \brief Confirmation for the WebUI API-key generate / rotate / delete actions.

    These actions apply immediately (bypassing the dialog-wide Apply), so they
    are gated behind an explicit confirmation. Set \l mode to
    \c "generate" / \c "rotate" / \c "delete", call \c open(); on confirmation it
    emits \c confirmed(mode). \c delete is treated as destructive.
*/
Dialog {
    id: root

    /*! One of "generate", "rotate", "delete". */
    property string mode: "generate"

    /*! Emitted when the user confirms the action; carries \l mode. */
    signal confirmed(string mode)

    readonly property bool destructive: mode === "delete"

    title: mode === "delete" ? qsTr("Delete API key")
                             : (mode === "rotate" ? qsTr("Rotate API key")
                                                  : qsTr("Generate API key"))

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
        MDIcon {
            visible: root.destructive
            icon: Icons.warning
            size: 28
            color: Theme.color("error")
            Layout.alignment: Qt.AlignTop
        }
        Label {
            text: root.mode === "delete"
                  ? qsTr("Are you sure you want to delete the current API key? Any client using it will lose access.")
                  : (root.mode === "rotate"
                     ? qsTr("Rotating the API key invalidates the current key immediately. Continue?")
                     : qsTr("Generate a new API key for programmatic access?"))
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
            text: qsTr("OK")
            highlighted: true
            Material.accent: root.destructive ? Theme.color("error") : Theme.color("primary")
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "APIKeyConfirmDialog confirmed (mode=" + mode + ")")
        root.confirmed(mode)
    }
    onRejected: Log.debug("ui", "APIKeyConfirmDialog cancelled (mode=" + mode + ")")
}
