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
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype TorrentCreatorDialog
    \brief Material rebuild of the legacy \c TorrentCreatorDialog.

    Collects a source file/folder, piece size, format / alignment options and the
    free-form tracker / web-seed / comment / source fields, then hands them to
    \c TorrentCreatorController.createTorrent(). Progress and the terminal outcome
    are published back through the controller's \c progress property and its
    \c creationSucceeded / \c creationFailed / \c addTorrentFailed signals. The
    torrent-format radios are shown on libtorrent 2.x builds; the "Optimize
    alignment" group is shown on libtorrent 1.x builds — mirroring the engine.
*/
Dialog {
    id: root

    // 0 = V2, 1 = Hybrid, 2 = V1 (matches TorrentCreatorController's mapping).
    readonly property int torrentFormat: formatHybrid.checked ? 1 : (formatV1.checked ? 2 : 0)

    title: qsTr("Torrent Creator")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(640, (parent ? parent.width : 640) * 0.9)
    height: Math.min(720, (parent ? parent.height : 720) * 0.9)
    padding: Spacing.lg
    closePolicy: Popup.CloseOnEscape

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("ui", "TorrentCreatorDialog opened")
        TorrentCreatorController.clearTotalPieces()
    }
    onClosed: Log.debug("ui", "TorrentCreatorDialog closed")

    // Assemble the params map the controller expects and start creation.
    function _create(torrentFilePath) {
        const params = {
            "sourcePath": pathField.text,
            "torrentFilePath": torrentFilePath,
            "pieceSize": pieceSizeCombo.currentValue,
            "ignoreDotfiles": ignoreDotfilesCheck.checked,
            "isPrivate": privateCheck.checked,
            "torrentFormat": root.torrentFormat,
            "isAlignmentOptimized": alignmentGroup.checked,
            "paddedFileSizeLimit": alignmentGroup.checked ? paddedSpin.value : -1,
            "comment": commentArea.text,
            "source": sourceField.text,
            "trackers": trackersArea.text,
            "urlSeeds": webSeedsArea.text,
            "startSeeding": startSeedingCheck.checked,
            "ignoreShareLimits": ignoreShareLimitsCheck.checked
        }
        Log.info("ui", "TorrentCreatorDialog creating torrent from " + pathField.text)
        TorrentCreatorController.createTorrent(params)
    }

    // React to the controller's terminal outcomes.
    Connections {
        target: TorrentCreatorController

        function onCreationSucceeded(torrentFilePath, savePath) {
            Log.info("ui", "TorrentCreatorDialog creation succeeded: " + torrentFilePath)
            NotificationCenter.notify(qsTr("Torrent created successfully."), "success")
            root.close()
        }
        function onCreationFailed(message) {
            Log.warning("ui", "TorrentCreatorDialog creation failed: " + message)
            NotificationCenter.notify(qsTr("Torrent creation failed: %1").arg(message), "error")
        }
        function onAddTorrentFailed(message) {
            Log.warning("ui", "TorrentCreatorDialog add-for-seeding failed: " + message)
            NotificationCenter.notify(qsTr("Could not start seeding the new torrent: %1").arg(message), "error")
        }
    }

    // OS pickers (the only permitted native dialogs).
    Platform.FileDialog {
        id: sourceFileDialog
        title: qsTr("Select a file")
        onAccepted: {
            pathField.text = decodeURIComponent(("" + file).replace(/^file:\/\/\/?/, ""))
            Log.debug("ui", "TorrentCreatorDialog source file: " + pathField.text)
        }
    }

    Platform.FolderDialog {
        id: sourceFolderDialog
        title: qsTr("Select a folder")
        onAccepted: {
            pathField.text = decodeURIComponent(("" + folder).replace(/^file:\/\/\/?/, ""))
            Log.debug("ui", "TorrentCreatorDialog source folder: " + pathField.text)
        }
    }

    Platform.FileDialog {
        id: saveDialog
        title: qsTr("Save torrent file")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "torrent"
        nameFilters: [qsTr("Torrent files (*.torrent)")]
        onAccepted: {
            const path = decodeURIComponent(("" + file).replace(/^file:\/\/\/?/, ""))
            root._create(path)
        }
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: root.availableWidth
            spacing: Spacing.md

            // ---- Source -----------------------------------------------------
            MaterialCard {
                title: qsTr("Select file/folder to share")
                titleIcon: Icons.folder_open
                enabled: !TorrentCreatorController.creating
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    LabeledField {
                        label: qsTr("Path:")
                        Layout.fillWidth: true

                        TextField {
                            id: pathField
                            Layout.fillWidth: true
                            placeholderText: qsTr("Select a file or folder to share")
                            selectByMouse: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.sm

                        Item { Layout.fillWidth: true }

                        Button {
                            text: qsTr("Select file")
                            flat: true
                            onClicked: {
                                Log.debug("ui", "TorrentCreatorDialog Select file clicked")
                                sourceFileDialog.open()
                            }
                        }

                        Button {
                            text: qsTr("Select folder")
                            flat: true
                            onClicked: {
                                Log.debug("ui", "TorrentCreatorDialog Select folder clicked")
                                sourceFolderDialog.open()
                            }
                        }
                    }
                }
            }

            // ---- Settings ---------------------------------------------------
            MaterialCard {
                title: qsTr("Settings")
                titleIcon: Icons.settings
                enabled: !TorrentCreatorController.creating
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    // Torrent format (libtorrent 2.x).
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.md
                        visible: TorrentCreatorController.libtorrent2

                        Label {
                            text: qsTr("Torrent format:")
                            font: Typography.bodyMedium
                            color: Theme.color("onSurfaceVariant")
                        }

                        RadioButton { id: formatV2; text: qsTr("v2") }
                        RadioButton { id: formatHybrid; text: qsTr("Hybrid"); checked: true }
                        RadioButton { id: formatV1; text: qsTr("v1") }

                        Item { Layout.fillWidth: true }
                    }

                    // Piece size + piece-count estimator.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.md

                        Label {
                            text: qsTr("Piece size:")
                            font: Typography.bodyMedium
                            color: Theme.color("onSurfaceVariant")
                        }

                        ComboBox {
                            id: pieceSizeCombo
                            model: TorrentCreatorController.pieceSizes
                            textRole: "text"
                            valueRole: "value"
                            currentIndex: 0
                            Layout.preferredWidth: 140
                        }

                        Button {
                            text: qsTr("Calculate number of pieces:")
                            flat: true
                            onClicked: {
                                Log.debug("ui", "TorrentCreatorDialog calculate pieces")
                                TorrentCreatorController.calculateTotalPieces(
                                        pathField.text, pieceSizeCombo.currentValue,
                                        ignoreDotfilesCheck.checked, root.torrentFormat,
                                        alignmentGroup.checked,
                                        alignmentGroup.checked ? paddedSpin.value : -1)
                            }
                        }

                        Label {
                            text: TorrentCreatorController.totalPiecesText
                            font: Typography.mono
                            color: Theme.color("onSurface")
                        }

                        Item { Layout.fillWidth: true }
                    }

                    CheckBox {
                        id: ignoreDotfilesCheck
                        text: qsTr("Ignore dotfiles")
                        checked: true
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("If checked, filenames starting with a period punctuation mark `.` will not be added to the created torrent.")
                    }

                    CheckBox {
                        id: privateCheck
                        text: qsTr("Private torrent (Won't distribute on DHT network)")
                    }

                    CheckBox {
                        id: startSeedingCheck
                        text: qsTr("Start seeding immediately")
                        checked: true
                    }

                    CheckBox {
                        id: ignoreShareLimitsCheck
                        text: qsTr("Ignore share ratio limits for this torrent")
                        enabled: startSeedingCheck.checked
                    }

                    // Optimize alignment (libtorrent 1.x).
                    CheckableGroupBox {
                        id: alignmentGroup
                        title: qsTr("Optimize alignment")
                        checked: false
                        visible: !TorrentCreatorController.libtorrent2
                        Layout.fillWidth: true

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Spacing.md

                            Label {
                                text: qsTr("Align to piece boundary for files larger than:")
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                            }

                            SpinBox {
                                id: paddedSpin
                                from: -1
                                to: 2147483647
                                value: -1
                                editable: true

                                // -1 renders as "Disabled"; other values carry a " KiB" suffix.
                                textFromValue: (value) => (value < 0)
                                        ? qsTr("Disabled")
                                        : (value + qsTr(" KiB"))
                                valueFromText: (text) => {
                                    if (text === qsTr("Disabled"))
                                        return -1
                                    const n = parseInt(text)
                                    return isNaN(n) ? -1 : n
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            // ---- Fields -----------------------------------------------------
            MaterialCard {
                title: qsTr("Fields")
                titleIcon: Icons.edit
                enabled: !TorrentCreatorController.creating
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    Label {
                        text: qsTr("Tracker URLs:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Frame {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 90
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
                                ToolTip.visible: hovered && (text.length === 0)
                                ToolTip.text: qsTr("You can separate tracker tiers / groups with an empty line.")
                            }
                        }
                    }

                    Label {
                        text: qsTr("Web seed URLs:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Frame {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
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
                                id: webSeedsArea
                                wrapMode: TextEdit.NoWrap
                                font: Typography.mono
                                color: Theme.color("onSurface")
                                selectByMouse: true
                            }
                        }
                    }

                    Label {
                        text: qsTr("Comments:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Frame {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
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
                                id: commentArea
                                wrapMode: TextEdit.Wrap
                                font: Typography.bodyMedium
                                color: Theme.color("onSurface")
                                selectByMouse: true
                            }
                        }
                    }

                    LabeledField {
                        label: qsTr("Source:")
                        Layout.fillWidth: true

                        TextField {
                            id: sourceField
                            Layout.fillWidth: true
                            selectByMouse: true
                        }
                    }
                }
            }

            // ---- Progress ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.md

                Label {
                    text: qsTr("Progress:")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: TorrentCreatorController.progress
                }

                Label {
                    text: qsTr("%1%").arg(TorrentCreatorController.progress)
                    font: Typography.mono
                    color: Theme.color("onSurface")
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
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                if (TorrentCreatorController.creating) {
                    Log.info("ui", "TorrentCreatorDialog cancelling in-flight creation")
                    TorrentCreatorController.cancelCreation()
                } else {
                    Log.debug("ui", "TorrentCreatorDialog cancelled")
                    root.close()
                }
            }
        }

        Button {
            text: qsTr("Create")
            highlighted: true
            enabled: !TorrentCreatorController.creating && (pathField.text.trim().length > 0)
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                Log.debug("ui", "TorrentCreatorDialog Create clicked")
                saveDialog.open()
            }
        }
    }
}
