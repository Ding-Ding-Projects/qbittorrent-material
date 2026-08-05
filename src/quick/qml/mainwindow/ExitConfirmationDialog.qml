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
    ExitConfirmationDialog — the three-button "Exiting qBittorrent" confirmation
    shown when \c confirmOnExit is set and torrents are still transferring (§14).
    Buttons: No (cancel) / Yes (quit) / Always Yes (quit and stop asking).

    Emits \c confirmed(bool alwaysYes) when the user chooses to quit; the built-in
    \c rejected() fires on No.
*/
Dialog {
    id: dialog

    /// Emitted when the user confirms exit; @p alwaysYes disables future prompts.
    signal confirmed(bool alwaysYes)

    title: qsTr("Exiting qBittorrent")
    modal: true
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent ? parent.width * 0.9 : 480)

    Material.roundedScale: Material.MediumScale
    Material.elevation: 24
    padding: Spacing.lg

    /// Open the dialog for an exit request.
    function openForExit() {
        Log.debug("ui", "ExitConfirmationDialog opened")
        open()
    }

    contentItem: RowLayout {
        spacing: Spacing.lg
        MDIcon {
            icon: Icons.warning
            size: 32
            color: StateColors.warning
            Layout.alignment: Qt.AlignTop
        }
        ColumnLayout {
            spacing: Spacing.sm
            Layout.fillWidth: true
            Label {
                text: qsTr("Some files are currently transferring.")
                font: Typography.bodyLarge
                color: Theme.color("onSurface")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Label {
                text: qsTr("Are you sure you want to quit qBittorrent?")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    footer: DialogButtonBox {
        Material.background: "transparent"
        Button {
            text: qsTr("No")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("Always Yes")
            flat: true
            onClicked: {
                Log.info("ui", "Exit dialog: Always Yes")
                dialog.confirmed(true)
                dialog.close()
            }
        }
        Button {
            text: qsTr("Yes")
            highlighted: true
            onClicked: {
                Log.info("ui", "Exit dialog: Yes")
                dialog.confirmed(false)
                dialog.close()
            }
        }
    }

    onRejected: Log.debug("ui", "Exit dialog rejected")
}
