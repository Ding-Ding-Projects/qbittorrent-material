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
    \qmltype BitTorrentPage
    \brief Options → BitTorrent page (legacy TAB_BITTORRENT).

    Privacy (DHT / PeX / LSD / encryption / anonymous), max active checking,
    Torrent Queueing (+ ignore-slow sub-group), Seeding Limits (ratio / seeding
    time / inactive time with the match-any/all mode + limit-reached action) and
    the two auto-append-trackers groups.
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
        property string paletteSettingKey: settingKey
        property string paletteSettingTitle: text
        property string paletteSettingKind: "toggle"
        property var paletteSettingDefault: defaultValue
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "BitTorrent: " + settingKey + " -> " + checked)
        }
    }

    Component.onCompleted: Log.debug("ui", "BitTorrentPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== Privacy =========================================================
        MaterialCard {
            title: qsTr("Privacy")
            titleIcon: Icons.swap_vert
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Enable DHT (decentralized network) to find more peers")
                settingKey: "BitTorrent/Session/DHTEnabled"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Enable Peer Exchange (PeX) to find more peers")
                settingKey: "BitTorrent/Session/PeXEnabled"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Enable Local Peer Discovery to find more peers")
                settingKey: "BitTorrent/Session/LSDEnabled"
                defaultValue: true
            }
            LabeledField {
                label: qsTr("Encryption mode:")
                labelWidth: 180
                Layout.fillWidth: true
                ComboBox {
                    property string paletteSettingKey: "BitTorrent/Session/Encryption"
                    property string paletteSettingTitle: qsTr("Encryption mode")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 0
                    Layout.fillWidth: true
                    model: [ qsTr("Allow encryption"), qsTr("Require encryption"), qsTr("Disable encryption") ]
                    currentIndex: (root.rev, OptionsController.value("BitTorrent/Session/Encryption", 0))
                    onActivated: (i) => OptionsController.setValue("BitTorrent/Session/Encryption", i)
                }
            }
            OptCheck {
                text: qsTr("Enable anonymous mode")
                settingKey: "BitTorrent/Session/AnonymousModeEnabled"
                defaultValue: false
            }
        }

        // ==== Max active checking ============================================
        MaterialCard {
            title: qsTr("Torrent checking")
            Layout.fillWidth: true
            LabeledField {
                label: qsTr("Maximum active checking torrents:")
                labelWidth: 260
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/MaxActiveCheckingTorrents"
                    property string paletteSettingTitle: qsTr("Maximum active checking torrents")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 1
                    from: -1; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/MaxActiveCheckingTorrents", 1))
                    textFromValue: (v, l) => v === -1 ? qsTr("∞") : Number(v).toLocaleString(l, 'f', 0)
                    valueFromText: (t) => t.indexOf("∞") !== -1 ? -1 : (parseInt(t.replace(/[^0-9\-]/g, "")) || -1)
                    onValueModified: OptionsController.setValue("BitTorrent/Session/MaxActiveCheckingTorrents", value)
                }
            }
        }

        // ==== Torrent Queueing ================================================
        CheckableGroupBox {
            property string paletteSettingKey: "BitTorrent/Session/QueueingSystemEnabled"
            property string paletteSettingTitle: title
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: false
            title: qsTr("Torrent Queueing")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("BitTorrent/Session/QueueingSystemEnabled", false))
            onToggled: (v) => OptionsController.setValue("BitTorrent/Session/QueueingSystemEnabled", v)

            LabeledField {
                label: qsTr("Maximum active downloads:")
                labelWidth: 240
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/MaxActiveDownloads"
                    property string paletteSettingTitle: qsTr("Maximum active downloads")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 3
                    from: -1; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/MaxActiveDownloads", 3))
                    onValueModified: OptionsController.setValue("BitTorrent/Session/MaxActiveDownloads", value)
                }
            }
            LabeledField {
                label: qsTr("Maximum active uploads:")
                labelWidth: 240
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/MaxActiveUploads"
                    property string paletteSettingTitle: qsTr("Maximum active uploads")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 3
                    from: -1; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/MaxActiveUploads", 3))
                    onValueModified: OptionsController.setValue("BitTorrent/Session/MaxActiveUploads", value)
                }
            }
            LabeledField {
                label: qsTr("Maximum active torrents:")
                labelWidth: 240
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/MaxActiveTorrents"
                    property string paletteSettingTitle: qsTr("Maximum active torrents")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 5
                    from: -1; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/MaxActiveTorrents", 5))
                    onValueModified: OptionsController.setValue("BitTorrent/Session/MaxActiveTorrents", value)
                }
            }

            CheckableGroupBox {
                property string paletteSettingKey: "BitTorrent/Session/IgnoreSlowTorrentsForQueueing"
                property string paletteSettingTitle: title
                property string paletteSettingKind: "toggle"
                property var paletteSettingDefault: false
                title: qsTr("Do not count slow torrents in these limits")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("BitTorrent/Session/IgnoreSlowTorrentsForQueueing", false))
                onToggled: (v) => OptionsController.setValue("BitTorrent/Session/IgnoreSlowTorrentsForQueueing", v)
                LabeledField {
                    label: qsTr("Download rate threshold:")
                    labelWidth: 220
                    Layout.fillWidth: true
                    SpinBox {
                        property string paletteSettingKey: "BitTorrent/Session/SlowTorrentsDownloadRate"
                        property string paletteSettingTitle: qsTr("Slow torrent download rate threshold")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: 2
                        from: 0; to: 2000000; editable: true
                        value: (root.rev, OptionsController.value("BitTorrent/Session/SlowTorrentsDownloadRate", 2))
                        textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("KiB/s")
                        valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 0
                        onValueModified: OptionsController.setValue("BitTorrent/Session/SlowTorrentsDownloadRate", value)
                    }
                }
                LabeledField {
                    label: qsTr("Upload rate threshold:")
                    labelWidth: 220
                    Layout.fillWidth: true
                    SpinBox {
                        property string paletteSettingKey: "BitTorrent/Session/SlowTorrentsUploadRate"
                        property string paletteSettingTitle: qsTr("Slow torrent upload rate threshold")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: 2
                        from: 0; to: 2000000; editable: true
                        value: (root.rev, OptionsController.value("BitTorrent/Session/SlowTorrentsUploadRate", 2))
                        textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("KiB/s")
                        valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 0
                        onValueModified: OptionsController.setValue("BitTorrent/Session/SlowTorrentsUploadRate", value)
                    }
                }
                LabeledField {
                    label: qsTr("Torrent inactivity timer:")
                    labelWidth: 220
                    Layout.fillWidth: true
                    SpinBox {
                        property string paletteSettingKey: "BitTorrent/Session/SlowTorrentsInactivityTimer"
                        property string paletteSettingTitle: qsTr("Slow torrent inactivity timer")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: 60
                        from: 1; to: 999999; editable: true
                        value: (root.rev, OptionsController.value("BitTorrent/Session/SlowTorrentsInactivityTimer", 60))
                        textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("sec")
                        valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 1
                        onValueModified: OptionsController.setValue("BitTorrent/Session/SlowTorrentsInactivityTimer", value)
                    }
                }
            }
        }

        // ==== Seeding Limits ==================================================
        MaterialCard {
            title: qsTr("Seeding Limits")
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: maxRatioCheck
                    text: qsTr("When ratio reaches")
                    settingKey: "Seeding/MaxRatioEnabled"
                    defaultValue: false
                }
                Item { Layout.fillWidth: true }
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/GlobalMaxRatio"
                    property string paletteSettingTitle: qsTr("Global maximum share ratio")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 1.0
                    enabled: maxRatioCheck.checked
                    from: 0; to: 2147483647; editable: true; stepSize: 1
                    property real ratio: (root.rev, OptionsController.value("BitTorrent/Session/GlobalMaxRatio", 1.0))
                    value: Math.round(ratio * 100)
                    textFromValue: (v, l) => Number(v / 100).toLocaleString(l, 'f', 2)
                    valueFromText: (t, l) => Math.round(Number.fromLocaleString(l, t) * 100)
                    onValueModified: OptionsController.setValue("BitTorrent/Session/GlobalMaxRatio", value / 100)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: maxSeedCheck
                    text: qsTr("When total seeding time reaches")
                    settingKey: "Seeding/MaxSeedingMinutesEnabled"
                    defaultValue: false
                }
                Item { Layout.fillWidth: true }
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/GlobalMaxSeedingMinutes"
                    property string paletteSettingTitle: qsTr("Global maximum seeding time")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 1440
                    enabled: maxSeedCheck.checked
                    from: 0; to: 9999999; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/GlobalMaxSeedingMinutes", 1440))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("min")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 0
                    onValueModified: OptionsController.setValue("BitTorrent/Session/GlobalMaxSeedingMinutes", value)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: maxInactiveCheck
                    text: qsTr("When inactive seeding time reaches")
                    settingKey: "Seeding/MaxInactiveSeedingMinutesEnabled"
                    defaultValue: false
                }
                Item { Layout.fillWidth: true }
                SpinBox {
                    property string paletteSettingKey: "BitTorrent/Session/GlobalMaxInactiveSeedingMinutes"
                    property string paletteSettingTitle: qsTr("Global maximum inactive seeding time")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 1440
                    enabled: maxInactiveCheck.checked
                    from: 0; to: 9999999; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/GlobalMaxInactiveSeedingMinutes", 1440))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("min")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 0
                    onValueModified: OptionsController.setValue("BitTorrent/Session/GlobalMaxInactiveSeedingMinutes", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.lg
                RadioButton {
                    property string paletteSettingKey: "BitTorrent/Session/ShareLimitsMode"
                    property string paletteSettingTitle: qsTr("Seeding limits match mode")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 0
                    text: qsTr("Any of the above")
                    font: Typography.bodyMedium
                    checked: (root.rev, OptionsController.value("BitTorrent/Session/ShareLimitsMode", 0)) === 0
                    onToggled: if (checked) OptionsController.setValue("BitTorrent/Session/ShareLimitsMode", 0)
                }
                RadioButton {
                    text: qsTr("All the above")
                    font: Typography.bodyMedium
                    checked: (root.rev, OptionsController.value("BitTorrent/Session/ShareLimitsMode", 0)) === 1
                    onToggled: if (checked) OptionsController.setValue("BitTorrent/Session/ShareLimitsMode", 1)
                }
            }

            LabeledField {
                label: qsTr("then")
                labelWidth: 60
                Layout.fillWidth: true
                ComboBox {
                    property string paletteSettingKey: "BitTorrent/Session/ShareLimitAction"
                    property string paletteSettingTitle: qsTr("Action when seeding limit is reached")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 0
                    Layout.fillWidth: true
                    enabled: maxRatioCheck.checked || maxSeedCheck.checked || maxInactiveCheck.checked
                    model: [ qsTr("Stop torrent"), qsTr("Remove torrent"),
                             qsTr("Remove torrent and its files"),
                             qsTr("Enable super seeding for torrent") ]
                    currentIndex: (root.rev, OptionsController.value("BitTorrent/Session/ShareLimitAction", 0))
                    onActivated: (i) => OptionsController.setValue("BitTorrent/Session/ShareLimitAction", i)
                }
            }
        }

        // ==== Auto-append trackers ============================================
        CheckableGroupBox {
            property string paletteSettingKey: "BitTorrent/Session/AddTrackersEnabled"
            property string paletteSettingTitle: title
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: false
            title: qsTr("Automatically append these trackers to new downloads:")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("BitTorrent/Session/AddTrackersEnabled", false))
            onToggled: (v) => OptionsController.setValue("BitTorrent/Session/AddTrackersEnabled", v)
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                TextArea {
                    property string paletteSettingKey: "BitTorrent/Session/AdditionalTrackers"
                    property string paletteSettingTitle: qsTr("Additional trackers for new downloads")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    placeholderText: qsTr("One tracker URL per line")
                    font: Typography.mono
                    text: (root.rev, OptionsController.value("BitTorrent/Session/AdditionalTrackers", ""))
                    onEditingFinished: OptionsController.setValue("BitTorrent/Session/AdditionalTrackers", text)
                }
            }
        }

        CheckableGroupBox {
            property string paletteSettingKey: "BitTorrent/Session/AddTrackersFromURLEnabled"
            property string paletteSettingTitle: title
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: false
            title: qsTr("Automatically append trackers from URL to new downloads:")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("BitTorrent/Session/AddTrackersFromURLEnabled", false))
            onToggled: (v) => OptionsController.setValue("BitTorrent/Session/AddTrackersFromURLEnabled", v)
            LabeledField {
                label: qsTr("URL:")
                labelWidth: 80
                Layout.fillWidth: true
                TextField {
                    property string paletteSettingKey: "BitTorrent/Session/AdditionalTrackersURL"
                    property string paletteSettingTitle: qsTr("Additional trackers source URL")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    Layout.fillWidth: true
                    text: (root.rev, OptionsController.value("BitTorrent/Session/AdditionalTrackersURL", ""))
                    onEditingFinished: OptionsController.setValue("BitTorrent/Session/AdditionalTrackersURL", text)
                }
            }
            Label {
                text: qsTr("Fetched trackers")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                Layout.fillWidth: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                TextArea {
                    property string paletteSettingKey: "BitTorrent/Session/AdditionalTrackersFromURL"
                    property string paletteSettingTitle: qsTr("Fetched additional trackers")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    readOnly: true
                    font: Typography.mono
                    color: Theme.color("onSurfaceVariant")
                    text: (root.rev, OptionsController.value("BitTorrent/Session/AdditionalTrackersFromURL", ""))
                }
            }
        }
    }
}
