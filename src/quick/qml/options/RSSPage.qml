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
    \qmltype RSSPage
    \brief Options → RSS page (legacy TAB_RSS).

    RSS Reader (fetch enable + intervals), the Auto Downloader enable + "Edit
    auto downloading rules..." launcher, and the Smart Episode Filter group.
*/
Flickable {
    id: root

    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    /*! Emitted when the user asks to edit auto-download rules (host opens the
        AutomatedRssDownloader screen). */
    signal editRulesRequested()

    component OptCheck: CheckBox {
        property string settingKey: ""
        property bool defaultValue: false
        property string paletteSettingKey: settingKey
        property string paletteSettingTitle: text
        property string paletteSettingKind: "toggle"
        property var paletteSettingDefault: defaultValue
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "RSS: " + settingKey + " -> " + checked)
        }
    }

    Component.onCompleted: Log.debug("ui", "RSSPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== RSS Reader ======================================================
        MaterialCard {
            title: qsTr("RSS Reader")
            titleIcon: Icons.rss_feed
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Enable fetching RSS feeds")
                settingKey: "RSS/Session/EnableProcessing"
                defaultValue: false
            }
            LabeledField {
                label: qsTr("Feeds refresh interval:")
                labelWidth: 280
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "RSS/Session/RefreshInterval"
                    property string paletteSettingTitle: qsTr("Feeds refresh interval")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 30
                    from: 1; to: 999999; editable: true
                    value: (root.rev, OptionsController.value("RSS/Session/RefreshInterval", 30))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("min")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 1
                    onValueModified: OptionsController.setValue("RSS/Session/RefreshInterval", value)
                }
            }
            LabeledField {
                label: qsTr("Same host request delay:")
                labelWidth: 280
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "RSS/Session/FetchDelay"
                    property string paletteSettingTitle: qsTr("Same host request delay")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 2
                    from: 0; to: 2147483646; editable: true
                    value: (root.rev, OptionsController.value("RSS/Session/FetchDelay", 2))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("sec")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 0
                    onValueModified: OptionsController.setValue("RSS/Session/FetchDelay", value)
                }
            }
            LabeledField {
                label: qsTr("Maximum number of articles per feed:")
                labelWidth: 280
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "RSS/Session/MaxArticlesPerFeed"
                    property string paletteSettingTitle: qsTr("Maximum number of articles per feed")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 50
                    from: 1; to: 2147483646; editable: true
                    value: (root.rev, OptionsController.value("RSS/Session/MaxArticlesPerFeed", 50))
                    onValueModified: OptionsController.setValue("RSS/Session/MaxArticlesPerFeed", value)
                }
            }
        }

        // ==== Auto Downloader =================================================
        MaterialCard {
            title: qsTr("RSS Torrent Auto Downloader")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Enable auto downloading of RSS torrents")
                settingKey: "RSS/AutoDownloader/EnableProcessing"
                defaultValue: false
            }
            Button {
                property string paletteActionKey: "edit-auto-download-rules"
                property string paletteActionTitle: text
                text: qsTr("Edit auto downloading rules...")
                onClicked: {
                    Log.info("ui", "RSS: edit auto-download rules requested")
                    root.editRulesRequested()
                }
            }
        }

        // ==== Smart Episode Filter ===========================================
        MaterialCard {
            title: qsTr("RSS Smart Episode Filter")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Download REPACK/PROPER episodes")
                settingKey: "RSS/AutoDownloader/DownloadRepacks"
                defaultValue: false
            }
            Label {
                text: qsTr("Filters:")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                Layout.fillWidth: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                TextArea {
                    property string paletteSettingKey: "RSS/AutoDownloader/SmartEpisodeFilter"
                    property string paletteSettingTitle: qsTr("RSS smart episode filters")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    font: Typography.mono
                    placeholderText: qsTr("One filter per line")
                    text: (root.rev, OptionsController.value("RSS/AutoDownloader/SmartEpisodeFilter", ""))
                    onEditingFinished: OptionsController.setValue("RSS/AutoDownloader/SmartEpisodeFilter", text)
                }
            }
        }
    }
}
