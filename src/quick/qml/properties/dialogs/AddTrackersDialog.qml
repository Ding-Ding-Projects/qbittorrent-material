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
import QtCore
import qBittorrent

/*!
    \qmltype AddTrackersDialog
    \brief Modal Material dialog to add trackers to the current torrent.

    Mirrors the legacy \c trackersadditiondialog: a multi-line list (one tracker
    per line, blank lines separate tiers) plus a "µTorrent compatible list URL"
    row whose download button fetches a remote list and appends it. On accept it
    emits \l trackersAccepted() with the whole text; the caller forwards it to
    \c PropertiesController.addTrackers() which runs \c parseTrackerEntries().
*/
Dialog {
    id: root

    /*! Emitted with the multi-line tracker text to add. */
    signal trackersAccepted(string text)

    title: qsTr("Add trackers")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    // Persist the last used list URL, mirroring AddTrackersDialog/TrackersListURL.
    Settings {
        id: persist
        category: "AddTrackersDialog"
        property string trackersListURL: ""
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
        Log.debug("ui", "AddTrackersDialog opened")
        trackersArea.clear()
        listUrlField.text = persist.trackersListURL
        trackersArea.forceActiveFocus()
    }

    // Bound in QML to PropertiesController's fetch signal so the fetched list is
    // appended when it arrives.
    Connections {
        target: PropertiesController
        enabled: root.visible
        // The remote-list fetch signals are optional engine-deep glue; tolerate
        // their absence instead of warning.
        ignoreUnknownSignals: true
        function onTrackerListFetched(text) {
            Log.info("ui", "AddTrackersDialog received fetched tracker list")
            if (text && text.length) {
                if (trackersArea.text.length && !trackersArea.text.endsWith("\n"))
                    trackersArea.append("")
                trackersArea.append(text)
            }
            fetchBusy.running = false
        }
        function onTrackerListFetchFailed(message) {
            Log.warning("ui", "AddTrackersDialog tracker list fetch failed: " + message)
            fetchBusy.running = false
        }
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("List of trackers to add (one per line):")
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
                    id: trackersArea
                    wrapMode: TextEdit.NoWrap
                    font: Typography.mono
                    color: Theme.color("onSurface")
                    selectByMouse: true
                }
            }
        }

        Label {
            text: qsTr("µTorrent compatible list URL:")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: Spacing.sm
            Layout.fillWidth: true

            TextField {
                id: listUrlField
                Layout.fillWidth: true
                placeholderText: qsTr("https://…")
                selectByMouse: true
                onTextChanged: persist.trackersListURL = text
            }

            IconButton {
                symbol: Icons.download
                tooltip: qsTr("Download trackers list")
                enabled: listUrlField.text.trim().length > 0 && !fetchBusy.running
                onClicked: {
                    Log.info("ui", "AddTrackersDialog download list: " + listUrlField.text)
                    fetchBusy.running = true
                    PropertiesController.fetchTrackerList(listUrlField.text.trim())
                }
            }

            // The controller always terminates a fetch, success or failure, so
            // the indicator can never be left spinning on a dead request.
            Connections {
                target: PropertiesController
                function onTrackerListFetchFinished() {
                    fetchBusy.running = false
                }
            }

            BusyIndicator {
                id: fetchBusy
                running: false
                visible: running
                implicitWidth: 24
                implicitHeight: 24
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
            enabled: trackersArea.text.trim().length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "AddTrackersDialog accepted")
        root.trackersAccepted(trackersArea.text)
    }

    onRejected: Log.debug("ui", "AddTrackersDialog rejected")
}
