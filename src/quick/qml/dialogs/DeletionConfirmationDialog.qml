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
    \qmltype DeletionConfirmationDialog
    \brief Material rebuild of the legacy \c DeletionConfirmationDialog ("Remove
           torrent(s)").

    Warns before removing torrents and offers an "Also remove the content files"
    checkbox plus a "remember choice" affordance that persists the default to the
    \c Preferences key \c Preferences/General/DeleteTorrentsFilesAsDefault. Set
    \l torrentsCount / \l torrentName (and optionally \l defaultDeleteFiles)
    before \c open(); on accept it emits \l confirmed() with the final choice.
*/
Dialog {
    id: root

    /*! Number of torrents being removed (drives singular/plural wording). */
    property int torrentsCount: 1

    /*! Name of the (first) torrent — shown when removing exactly one. */
    property string torrentName: ""

    /*! Initial state of the "also delete content" checkbox. */
    property bool defaultDeleteFiles: false

    /*! The Preferences key backing the remembered default. */
    readonly property string _rememberKey: "Preferences/General/DeleteTorrentsFilesAsDefault"

    /*! Emitted on accept with the final "delete content files" choice. */
    signal confirmed(bool deleteFiles)

    title: qsTr("Remove torrent(s)")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) * 0.9)
    padding: Spacing.xl

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outline")
    }

    onOpened: {
        Log.debug("ui", "DeletionConfirmationDialog opened for " + torrentsCount + " torrent(s)")
        removeContent.checked = defaultDeleteFiles
                || (Preferences.value(_rememberKey, false) === true)
    }

    header: Label {
        text: root.title
        font: Typography.sectionTitle
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        RowLayout {
            spacing: Spacing.md
            Layout.fillWidth: true

            MDIcon {
                icon: Icons.warning
                size: 28
                color: Theme.color("warning")
                Layout.alignment: Qt.AlignTop
            }

            Label {
                text: root.torrentsCount === 1
                      ? qsTr("Are you sure you want to remove '%1' from the transfer list?").arg(root.torrentName)
                      : qsTr("Are you sure you want to remove these %1 torrents from the transfer list?").arg(root.torrentsCount)
                font: Typography.bodyLarge
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        RowLayout {
            spacing: Spacing.sm
            Layout.fillWidth: true

            CheckBox {
                id: removeContent
                text: qsTr("Also remove the content files")
                font: Typography.bodyMedium
                Layout.fillWidth: true
                onToggled: Log.debug("ui", "DeletionConfirmationDialog remove-content -> " + checked)
            }

            IconButton {
                id: rememberButton
                symbol: Icons.lock
                tooltip: qsTr("Remember choice")
                // Enabled only when the choice differs from the stored default.
                enabled: removeContent.checked !== (Preferences.value(root._rememberKey, false) === true)
                onClicked: {
                    Log.info("ui", "DeletionConfirmationDialog remembering choice: " + removeContent.checked)
                    Preferences.setValue(root._rememberKey, removeContent.checked)
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
            focus: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            id: confirmButton
            text: removeContent.checked ? qsTr("Remove torrent and content") : qsTr("Remove torrent")
            highlighted: true
            Material.accent: Theme.color("error")
            // Deleting content files destroys data that nothing in the app can
            // bring back, so that path goes through the super-confirmation gate.
            // Removing only from the transfer list is recoverable — the torrent
            // can be added again — and stays a single click.
            DialogButtonBox.buttonRole: removeContent.checked
                ? DialogButtonBox.ActionRole : DialogButtonBox.AcceptRole
            onClicked: {
                if (!removeContent.checked)
                    return
                Log.info("ui", "DeletionConfirmationDialog escalating to super confirmation")
                superConfirm.originatingControl = confirmButton
                superConfirm.open()
            }
        }
    }

    SuperConfirmDialog {
        id: superConfirm
        actionText: root.torrentsCount === 1
            ? qsTr("Delete '%1' and its content files").arg(root.torrentName)
            : qsTr("Delete %1 torrents and their content files").arg(root.torrentsCount)
        affectedText: root.torrentsCount === 1
            ? qsTr("'%1' and every file it downloaded").arg(root.torrentName)
            : qsTr("%1 torrents and every file they downloaded").arg(root.torrentsCount)
        consequenceText: qsTr("The downloaded files are erased from disk, not moved to the recycle bin.")
        confirmLabel: qsTr("Slide to delete the files")

        onAuthorized: {
            Log.info("ui", "Super confirmation authorized content deletion")
            root.confirmed(true)
            root.close()
        }
        onCancelled: Log.info("ui", "Super confirmation declined; nothing was deleted")
    }

    onAccepted: {
        Log.info("ui", "DeletionConfirmationDialog accepted; deleteFiles=" + removeContent.checked)
        root.confirmed(removeContent.checked)
    }

    onRejected: Log.debug("ui", "DeletionConfirmationDialog rejected")
}
