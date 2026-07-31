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
    \qmltype DownloadsPage
    \brief Options → Downloads page (legacy TAB_DOWNLOADS).

    Rebuilds "When adding a torrent", duplicate handling, .torrent auto-delete,
    disk allocation, Saving Management + paths, watched folders (a \c DataTable
    over \c OptionsController.watchedFoldersModel with Add / Options / Remove),
    excluded file names, email notification and the run-external-program groups.
*/
Flickable {
    id: root

    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    component OptCheck: CheckBox {
        property string settingKey: ""
        property bool defaultValue: false
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "Downloads: " + settingKey + " -> " + checked)
        }
    }

    // A path row: enable checkbox + PathField, both bound to keys.
    component PathRow: RowLayout {
        property string enableKey: ""
        property string pathKey: ""
        property string caption: ""
        property string labelText: ""
        Layout.fillWidth: true
        spacing: Spacing.sm
        OptCheck {
            id: en
            text: parent.labelText
            settingKey: parent.enableKey
            defaultValue: false
        }
        PathField {
            Layout.fillWidth: true
            enabled: en.checked
            title: parent.caption
            path: (root.rev, OptionsController.value(parent.pathKey, ""))
            onPathChanged: OptionsController.setValue(parent.pathKey, path)
        }
    }

    Component.onCompleted: Log.debug("ui", "DownloadsPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== When adding a torrent ===========================================
        MaterialCard {
            title: qsTr("When adding a torrent")
            titleIcon: Icons.note_add
            Layout.fillWidth: true

            CheckableGroupBox {
                id: additionDialog
                title: qsTr("Display torrent content and some options")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("AddNewTorrentDialog/Enabled", true))
                onToggled: (v) => OptionsController.setValue("AddNewTorrentDialog/Enabled", v)
                OptCheck {
                    text: qsTr("Bring torrent dialog to the front")
                    settingKey: "AddNewTorrentDialog/TopLevel"
                    defaultValue: true
                }
            }

            LabeledField {
                label: qsTr("Torrent content layout:")
                labelWidth: 220
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Original"), qsTr("Create subfolder"), qsTr("Don't create subfolder") ]
                    currentIndex: (root.rev, OptionsController.value("BitTorrent/Session/TorrentContentLayout", 0))
                    onActivated: (i) => OptionsController.setValue("BitTorrent/Session/TorrentContentLayout", i)
                }
            }

            OptCheck {
                text: qsTr("Add to top of queue")
                settingKey: "BitTorrent/Session/AddTorrentToTopOfQueue"
                defaultValue: false
            }
            OptCheck {
                id: addStopped
                text: qsTr("Do not start the download automatically")
                settingKey: "BitTorrent/Session/AddTorrentStopped"
                defaultValue: false
            }
            LabeledField {
                label: qsTr("Torrent stop condition:")
                labelWidth: 220
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    enabled: !addStopped.checked
                    model: [ qsTr("None"), qsTr("Metadata received"), qsTr("Files checked") ]
                    currentIndex: (root.rev, OptionsController.value("BitTorrent/Session/TorrentStopCondition", 0))
                    onActivated: (i) => OptionsController.setValue("BitTorrent/Session/TorrentStopCondition", i)
                }
            }

            // Duplicate handling
            SectionHeader { text: qsTr("When adding a duplicate torrent"); Layout.fillWidth: true }
            OptCheck {
                text: qsTr("Merge trackers to existing torrent")
                settingKey: "BitTorrent/MergeTrackersEnabled"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Ask to merge trackers for manually added torrent")
                settingKey: "GUI/ConfirmActions/MergeTrackers"
                defaultValue: true
                enabled: additionDialog.checked
            }

            // Delete .torrent afterwards
            CheckableGroupBox {
                id: deleteAfter
                title: qsTr("Delete .torrent files afterwards")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Downloads/DeleteTorrentAfter", false))
                onToggled: (v) => OptionsController.setValue("Downloads/DeleteTorrentAfter", v)
                OptCheck {
                    text: qsTr("Also when addition is cancelled")
                    settingKey: "Downloads/DeleteTorrentAfterCancelled"
                    defaultValue: false
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm
                    MDIcon { icon: Icons.warning; size: 20; color: Theme.color("error") }
                    Label {
                        text: qsTr("Warning! Data loss possible!")
                        font: Typography.labelSmall
                        color: Theme.color("error")
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ==== Disk allocation & misc ==========================================
        MaterialCard {
            title: qsTr("Disk Options")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Pre-allocate disk space for all files")
                settingKey: "BitTorrent/Session/Preallocation"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Append .!qB extension to incomplete files")
                settingKey: "BitTorrent/Session/AddExtensionToIncompleteFiles"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Keep unselected files in \".unwanted\" folder")
                settingKey: "BitTorrent/Session/UseUnwantedFolder"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Enable recursive download dialog")
                settingKey: "Preferences/Advanced/RecursiveDownloadEnabled"
                defaultValue: true
            }
        }

        // ==== Saving Management ===============================================
        MaterialCard {
            title: qsTr("Saving Management")
            titleIcon: Icons.folder
            Layout.fillWidth: true

            LabeledField {
                label: qsTr("Default Torrent Management Mode:")
                labelWidth: 300
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Manual"), qsTr("Automatic") ]
                    currentIndex: (root.rev, OptionsController.value("Downloads/DefaultTMM", 0))
                    onActivated: (i) => OptionsController.setValue("Downloads/DefaultTMM", i)
                }
            }
            LabeledField {
                label: qsTr("When Torrent Category changed:")
                labelWidth: 300
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Relocate torrent"), qsTr("Switch torrent to Manual Mode") ]
                    currentIndex: (root.rev, OptionsController.value("Downloads/OnCategoryChanged", 0))
                    onActivated: (i) => OptionsController.setValue("Downloads/OnCategoryChanged", i)
                }
            }
            LabeledField {
                label: qsTr("When Default Save/Incomplete Path changed:")
                labelWidth: 300
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Relocate affected torrents"), qsTr("Switch affected torrents to Manual Mode") ]
                    currentIndex: (root.rev, OptionsController.value("Downloads/OnDefaultSavePathChanged", 1))
                    onActivated: (i) => OptionsController.setValue("Downloads/OnDefaultSavePathChanged", i)
                }
            }
            LabeledField {
                label: qsTr("When Category Save Path changed:")
                labelWidth: 300
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Relocate affected torrents"), qsTr("Switch affected torrents to Manual Mode") ]
                    currentIndex: (root.rev, OptionsController.value("Downloads/OnCategorySavePathChanged", 1))
                    onActivated: (i) => OptionsController.setValue("Downloads/OnCategorySavePathChanged", i)
                }
            }
            OptCheck {
                text: qsTr("Use Category paths in Manual Mode")
                settingKey: "BitTorrent/Session/UseCategoryPathsInManualMode"
                defaultValue: false
            }

            LabeledField {
                label: qsTr("Default Save Path:")
                orientation: Qt.Vertical
                Layout.fillWidth: true
                PathField {
                    Layout.fillWidth: true
                    title: qsTr("Choose a save directory")
                    path: (root.rev, OptionsController.value("BitTorrent/Session/DefaultSavePath", ""))
                    onPathChanged: OptionsController.setValue("BitTorrent/Session/DefaultSavePath", path)
                }
            }
            PathRow {
                labelText: qsTr("Use another path for incomplete torrents:")
                enableKey: "BitTorrent/Session/TempPathEnabled"
                pathKey: "BitTorrent/Session/TempPath"
                caption: qsTr("Choose a directory for incomplete torrents")
            }
            PathRow {
                labelText: qsTr("Copy .torrent files to:")
                enableKey: "Downloads/ExportDirEnabled"
                pathKey: "BitTorrent/Session/TorrentExportDirectory"
                caption: qsTr("Choose an export directory")
            }
            PathRow {
                labelText: qsTr("Copy .torrent files for finished downloads to:")
                enableKey: "Downloads/FinishedExportDirEnabled"
                pathKey: "BitTorrent/Session/FinishedTorrentExportDirectory"
                caption: qsTr("Choose an export directory")
            }
        }

        // ==== Watched folders =================================================
        MaterialCard {
            title: qsTr("Automatically add torrents from:")
            Layout.fillWidth: true

            DataTable {
                id: watchedTable
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                model: OptionsController.watchedFoldersModel
                persistKey: "WatchedFolders"
                columns: [
                    { role: "path", title: qsTr("Watched Folder"), width: 480,
                      align: Qt.AlignLeft, visible: true, resizable: true }
                ]
                property int currentSelection: -1
                onActivated: (row) => {
                    watchedTable.currentSelection = row
                    Log.info("ui", "Watched folder edit (double-click) row " + row)
                    watchedDialog.openForEdit(row)
                }
                onSelectionChanged: watchedTable.currentSelection = currentRow
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                Button {
                    text: qsTr("Add...")
                    onClicked: {
                        Log.info("ui", "Watched folder Add clicked")
                        watchedDialog.openForAdd()
                    }
                }
                Button {
                    text: qsTr("Options...")
                    enabled: watchedTable.currentSelection >= 0
                    onClicked: {
                        Log.info("ui", "Watched folder Options clicked for row " + watchedTable.currentSelection)
                        watchedDialog.openForEdit(watchedTable.currentSelection)
                    }
                }
                Button {
                    text: qsTr("Remove")
                    enabled: watchedTable.currentSelection >= 0
                    onClicked: {
                        Log.info("ui", "Watched folder Remove row " + watchedTable.currentSelection)
                        OptionsController.removeWatchedFolder(watchedTable.currentSelection)
                        watchedTable.currentSelection = -1
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // ==== Excluded file names =============================================
        CheckableGroupBox {
            title: qsTr("Excluded file names")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("BitTorrent/ExcludedFileNamesEnabled", false))
            onToggled: (v) => OptionsController.setValue("BitTorrent/ExcludedFileNamesEnabled", v)
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                TextArea {
                    wrapMode: TextEdit.NoWrap
                    placeholderText: qsTr("One name pattern per line (wildcards *, ?, [...] supported)")
                    font: Typography.mono
                    text: (root.rev, OptionsController.value("BitTorrent/Session/ExcludedFileNames", ""))
                    onEditingFinished: OptionsController.setValue("BitTorrent/Session/ExcludedFileNames", text)
                }
            }
        }

        // ==== Email notification ==============================================
        CheckableGroupBox {
            title: qsTr("Email notification upon download completion")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("Preferences/MailNotification/enabled", false))
            onToggled: (v) => OptionsController.setValue("Preferences/MailNotification/enabled", v)

            LabeledField {
                label: qsTr("From:")
                labelWidth: 140
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholderText: "qBittorrent_notification@example.com"
                    text: (root.rev, OptionsController.value("Preferences/MailNotification/sender", ""))
                    onEditingFinished: OptionsController.setValue("Preferences/MailNotification/sender", text)
                }
            }
            LabeledField {
                label: qsTr("To:")
                labelWidth: 140
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    text: (root.rev, OptionsController.value("Preferences/MailNotification/email", ""))
                    onEditingFinished: OptionsController.setValue("Preferences/MailNotification/email", text)
                }
            }
            LabeledField {
                label: qsTr("SMTP server:")
                labelWidth: 140
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    placeholderText: "smtp.example.com:465"
                    text: (root.rev, OptionsController.value("Preferences/MailNotification/smtp_server", ""))
                    onEditingFinished: OptionsController.setValue("Preferences/MailNotification/smtp_server", text)
                }
            }
            LabeledField {
                label: qsTr("SMTP encryption:")
                labelWidth: 140
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("None"), qsTr("STARTTLS"), qsTr("SMTPS") ]
                    currentIndex: (root.rev, OptionsController.value("Preferences/MailNotification/SMTPEncryptionType", 2))
                    onActivated: (i) => OptionsController.setValue("Preferences/MailNotification/SMTPEncryptionType", i)
                }
            }
            CheckableGroupBox {
                title: qsTr("Authentication")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/MailNotification/req_auth", false))
                onToggled: (v) => OptionsController.setValue("Preferences/MailNotification/req_auth", v)
                LabeledField {
                    label: qsTr("Username:")
                    labelWidth: 140
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        text: (root.rev, OptionsController.value("Preferences/MailNotification/username", ""))
                        onEditingFinished: OptionsController.setValue("Preferences/MailNotification/username", text)
                    }
                }
                LabeledField {
                    label: qsTr("Password:")
                    labelWidth: 140
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        text: (root.rev, OptionsController.value("Preferences/MailNotification/password", ""))
                        onEditingFinished: OptionsController.setValue("Preferences/MailNotification/password", text)
                    }
                }
            }
            Button {
                text: qsTr("Send test email")
                onClicked: {
                    Log.info("ui", "Downloads: send test email")
                    OptionsController.sendTestEmail()
                }
            }
        }

        // ==== Run external program ============================================
        MaterialCard {
            title: qsTr("Run external program")
            Layout.fillWidth: true

            CheckableGroupBox {
                title: qsTr("Run on torrent added:")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("AutoRun/OnTorrentAdded/Enabled", false))
                onToggled: (v) => OptionsController.setValue("AutoRun/OnTorrentAdded/Enabled", v)
                TextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Command line")
                    text: (root.rev, OptionsController.value("AutoRun/OnTorrentAdded/Program", ""))
                    onEditingFinished: OptionsController.setValue("AutoRun/OnTorrentAdded/Program", text)
                }
            }
            CheckableGroupBox {
                title: qsTr("Run on torrent finished:")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("AutoRun/enabled", false))
                onToggled: (v) => OptionsController.setValue("AutoRun/enabled", v)
                TextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Command line")
                    text: (root.rev, OptionsController.value("AutoRun/program", ""))
                    onEditingFinished: OptionsController.setValue("AutoRun/program", text)
                }
            }
            Label {
                text: qsTr("Supported parameters: %N name, %L category, %G tags, %F content path, %R root path, %D save path, %C file count, %Z size, %T current tracker, %I infohash v1, %J infohash v2, %K torrent ID, %M comment.")
                font: Typography.labelSmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    WatchedFolderOptionsDialog {
        id: watchedDialog
        onCommitted: (row, options) => {
            if (row < 0) {
                Log.info("ui", "Adding watched folder: " + options.path)
                OptionsController.addWatchedFolder(options.path, options)
            } else {
                Log.info("ui", "Updating watched folder row " + row)
                OptionsController.setWatchedFolderOptions(row, options)
            }
        }
    }

    Connections {
        target: OptionsController
        function onActionFeedback(action, success, message) {
            if (action === "testEmail")
                NotificationCenter.notify(message, success ? "success" : "error")
        }
    }
}
