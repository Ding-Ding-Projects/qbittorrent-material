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
    \qmltype TrackerEntriesDialog
    \brief Material rebuild of the legacy \c TrackerEntriesDialog ("Edit
           trackers").

    A free-form editor where each line is a tracker URL and blank lines separate
    tiers (top group = tier 0). Seed \l trackersText before \c open(); on accept
    it emits \l trackersAccepted() with the whole text for the caller to run
    through \c parseTrackerEntries().
*/
Dialog {
    id: root

    /*! Two-way: the multi-line tracker text (tiers separated by blank lines). */
    property alias trackersText: editor.text

    /*! Emitted with the edited multi-line tracker text. */
    signal trackersAccepted(string text)

    title: qsTr("Edit trackers")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(540, (parent ? parent.width : 540) * 0.9)
    height: Math.min(implicitHeight, (parent ? parent.height : 640) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("ui", "TrackerEntriesDialog opened")
        editor.forceActiveFocus()
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
        spacing: Spacing.sm

        Label {
            text: qsTr("One tracker URL per line.\nBlank lines separate the list into tiers: the first group is tier 0, the next is tier 1, and so on.\nWhen multiple torrents are selected only their common trackers are shown.")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 280

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
                    id: editor
                    wrapMode: TextEdit.NoWrap
                    font: Typography.mono
                    color: Theme.color("onSurface")
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
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "TrackerEntriesDialog accepted")
        root.trackersAccepted(editor.text)
    }

    onRejected: Log.debug("ui", "TrackerEntriesDialog rejected")
}
