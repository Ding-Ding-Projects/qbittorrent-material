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
    \qmltype AddPeersDialog
    \brief Modal Material dialog to add peers to the current torrent.

    Mirrors the legacy \c peersadditiondialog: a multi-line editor, one peer per
    line, in the form \c IPv4:port or \c [IPv6]:port. On accept it emits
    \l peersAccepted() with the raw, non-empty lines; the caller (Peers tab)
    forwards them to \c PropertiesController.peerModel.addPeers() which validates
    each via \c BitTorrent::PeerAddress::parse().
*/
Dialog {
    id: root

    /*! Emitted with the array of trimmed, non-empty peer lines. */
    signal peersAccepted(var lines)

    title: qsTr("Add Peers")
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

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    onOpened: {
        Log.debug("ui", "AddPeersDialog opened")
        peersArea.clear()
        peersArea.forceActiveFocus()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("List of peers to add (one IP per line):")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: 180

            background: Rectangle {
                radius: Spacing.radiusField
                color: Theme.color("surfaceVariant")
                border.width: 1
                border.color: Theme.color("outlineVariant")
            }

            ScrollView {
                anchors.fill: parent
                clip: true

                TextArea {
                    id: peersArea
                    wrapMode: TextEdit.NoWrap
                    font: Typography.mono
                    color: Theme.color("onSurface")
                    placeholderText: qsTr("Format: IPv4:port / [IPv6]:port")
                    selectByMouse: true
                }
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
            text: qsTr("Add")
            highlighted: true
            enabled: peersArea.text.trim().length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        const lines = peersArea.text.split(/\r?\n/)
            .map(l => l.trim())
            .filter(l => l.length > 0)
        Log.info("ui", "AddPeersDialog accepted: " + lines.length + " line(s)")
        root.peersAccepted(lines)
    }

    onRejected: Log.debug("ui", "AddPeersDialog rejected")
}
