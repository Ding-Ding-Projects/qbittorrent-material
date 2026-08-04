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
    \qmltype AdvancedPage
    \brief Options → Advanced page (legacy TAB_ADVANCED / AdvancedSettings).

    The legacy flat two-column "Setting / Value" table becomes a Material
    settings list grouped under "qBittorrent" and "libtorrent" cards. Every row
    stages through \c OptionsController.value/setValue using the exact legacy
    config keys. Platform-/build-gated rows are always shown here (the controller
    is free to hide unsupported keys).
*/
Flickable {
    id: root

    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    // ---- Inline key/value row helpers -----------------------------------------
    component AdvCheck: LabeledField {
        id: advc
        property string settingKey: ""
        property bool defaultValue: false
        labelWidth: 440
        Layout.fillWidth: true
        CheckBox {
            property string paletteSettingKey: advc.settingKey
            property string paletteSettingTitle: advc.label
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: advc.defaultValue
            checked: (root.rev, OptionsController.value(advc.settingKey, advc.defaultValue))
            onToggled: {
                OptionsController.setValue(advc.settingKey, checked)
                Log.debug("ui", "Advanced: " + advc.settingKey + " -> " + checked)
            }
        }
    }

    component AdvSpin: LabeledField {
        id: advs
        property string settingKey: ""
        property int defaultValue: 0
        property int fromValue: 0
        property int toValue: 2147483647
        property string suffix: ""
        property string specialText: ""
        property int specialValue: -2147483647
        labelWidth: 440
        Layout.fillWidth: true
        SpinBox {
            property string paletteSettingKey: advs.settingKey
            property string paletteSettingTitle: advs.label
            property string paletteSettingKind: "destination"
            property var paletteSettingDefault: advs.defaultValue
            editable: true
            from: advs.fromValue; to: advs.toValue
            value: (root.rev, OptionsController.value(advs.settingKey, advs.defaultValue))
            textFromValue: (v, l) => (advs.specialText.length > 0 && v === advs.specialValue)
                                     ? advs.specialText
                                     : (Number(v).toLocaleString(l, 'f', 0)
                                        + (advs.suffix.length > 0 ? (" " + advs.suffix) : ""))
            valueFromText: (t) => {
                if (advs.specialText.length > 0 && t.indexOf(advs.specialText) !== -1)
                    return advs.specialValue
                var n = parseInt(("" + t).replace(/[^0-9\-]/g, ""))
                return isNaN(n) ? advs.defaultValue : n
            }
            onValueModified: OptionsController.setValue(advs.settingKey, value)
        }
    }

    component AdvCombo: LabeledField {
        id: advcb
        property string settingKey: ""
        property int defaultValue: 0
        property var items: []
        labelWidth: 440
        Layout.fillWidth: true
        ComboBox {
            property string paletteSettingKey: advcb.settingKey
            property string paletteSettingTitle: advcb.label
            property string paletteSettingKind: "destination"
            property var paletteSettingDefault: advcb.defaultValue
            Layout.fillWidth: true
            model: advcb.items
            currentIndex: (root.rev, OptionsController.value(advcb.settingKey, advcb.defaultValue))
            onActivated: (i) => OptionsController.setValue(advcb.settingKey, i)
        }
    }

    component AdvLine: LabeledField {
        id: advl
        property string settingKey: ""
        property string defaultValue: ""
        property string placeholder: ""
        labelWidth: 440
        Layout.fillWidth: true
        TextField {
            property string paletteSettingKey: advl.settingKey
            property string paletteSettingTitle: advl.label
            property string paletteSettingKind: "destination"
            property var paletteSettingDefault: advl.defaultValue
            Layout.fillWidth: true
            placeholderText: advl.placeholder
            text: (root.rev, OptionsController.value(advl.settingKey, advl.defaultValue))
            onEditingFinished: OptionsController.setValue(advl.settingKey, text)
        }
    }

    Component.onCompleted: Log.debug("ui", "AdvancedPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== qBittorrent Section =============================================
        MaterialCard {
            title: qsTr("qBittorrent Section")
            titleIcon: Icons.settings_suggest
            Layout.fillWidth: true

            AdvCombo {
                label: qsTr("Resume data storage type (requires restart)")
                settingKey: "BitTorrent/Session/ResumeDataStorageType"
                items: [ qsTr("Fastresume files"), qsTr("SQLite database (experimental)") ]
            }
            AdvCombo {
                label: qsTr("Torrent content removing mode")
                settingKey: "BitTorrent/Session/TorrentContentRemoveOption"
                items: [ qsTr("Delete files permanently"), qsTr("Move files to trash (if possible)") ]
            }
            AdvSpin {
                label: qsTr("Physical memory (RAM) usage limit")
                settingKey: "Application/MemoryWorkingSetLimit"
                defaultValue: 512; fromValue: 1; suffix: qsTr("MiB")
            }
            AdvCombo {
                label: qsTr("Process memory priority")
                settingKey: "Application/ProcessMemoryPriority"
                items: [ qsTr("Normal"), qsTr("Below normal"), qsTr("Medium"), qsTr("Low"), qsTr("Very low") ]
            }
            LabeledField {
                label: qsTr("Network interface")
                labelWidth: 440
                Layout.fillWidth: true
                ComboBox {
                    property string paletteSettingKey: "BitTorrent/Session/Interface"
                    property string paletteSettingTitle: qsTr("Network interface")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    Layout.fillWidth: true
                    textRole: "text"
                    valueRole: "value"
                    model: (root.rev, OptionsController.networkInterfaces())
                    currentIndex: Math.max(0, indexOfValue(OptionsController.value("BitTorrent/Session/Interface", "")))
                    onActivated: OptionsController.setValue("BitTorrent/Session/Interface", currentValue)
                }
            }
            LabeledField {
                label: qsTr("Optional IP address to bind to")
                labelWidth: 440
                Layout.fillWidth: true
                ComboBox {
                    property string paletteSettingKey: "BitTorrent/Session/InterfaceAddress"
                    property string paletteSettingTitle: qsTr("Optional IP address to bind to")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    Layout.fillWidth: true
                    textRole: "text"
                    valueRole: "value"
                    model: (root.rev, OptionsController.networkInterfaceAddresses())
                    currentIndex: Math.max(0, indexOfValue(OptionsController.value("BitTorrent/Session/InterfaceAddress", "")))
                    onActivated: OptionsController.setValue("BitTorrent/Session/InterfaceAddress", currentValue)
                }
            }
            AdvSpin {
                label: qsTr("Save resume data interval [0: disabled]")
                settingKey: "BitTorrent/Session/SaveResumeDataInterval"
                defaultValue: 60; fromValue: 0; suffix: qsTr("min")
                specialText: qsTr("0 (disabled)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Save statistics interval [0: disabled]")
                settingKey: "BitTorrent/Session/SaveStatisticsInterval"
                defaultValue: 15; fromValue: 0; suffix: qsTr("min")
                specialText: qsTr("0 (disabled)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr(".torrent file size limit")
                settingKey: "BitTorrent/TorrentFileSizeLimit"
                defaultValue: 100; fromValue: 1; suffix: qsTr("MiB")
            }
            AdvCheck {
                label: qsTr("Confirm torrent recheck")
                settingKey: "Preferences/Advanced/confirmTorrentRecheck"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Recheck torrents on completion")
                settingKey: "Preferences/Advanced/RecheckOnCompletion"; defaultValue: false
            }
            AdvLine {
                label: qsTr("Customize application instance name")
                settingKey: "Application/InstanceName"
            }
            AdvSpin {
                label: qsTr("Refresh interval")
                settingKey: "BitTorrent/Session/RefreshInterval"
                defaultValue: 1500; fromValue: 30; toValue: 99999; suffix: qsTr("ms")
            }
            AdvCheck {
                label: qsTr("Resolve peer countries")
                settingKey: "Preferences/Connection/ResolvePeerCountries"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Resolve peer host names")
                settingKey: "Preferences/Connection/ResolvePeerHostNames"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Display notifications")
                settingKey: "GUI/Notifications/Enabled"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Display notifications for added torrents")
                settingKey: "GUI/Notifications/TorrentAdded"; defaultValue: false
            }
            AdvSpin {
                label: qsTr("Notification timeout [0: infinite, -1: system default]")
                settingKey: "GUI/Notifications/Timeout"
                defaultValue: -1; fromValue: -1; suffix: qsTr("ms")
                specialText: qsTr("-1 (system default)"); specialValue: -1
            }
            AdvCheck {
                label: qsTr("Confirm removal of all tags")
                settingKey: "Preferences/Advanced/confirmRemoveAllTags"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Confirm removal of tracker from all torrents")
                settingKey: "GUI/ConfirmActions/RemoveTrackerFromAllTorrents"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Reannounce to all trackers when IP or port changed")
                settingKey: "BitTorrent/Session/ReannounceWhenAddressChanged"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Download tracker's favicon")
                settingKey: "GUI/DownloadTrackerFavicon"; defaultValue: false
            }
            AdvSpin {
                label: qsTr("Save path history length")
                settingKey: "AddNewTorrentDialog/SavePathHistoryLength"
                defaultValue: 8; fromValue: 0; toValue: 99
            }
            AdvCheck {
                label: qsTr("Enable speed graphs")
                settingKey: "SpeedWidget/Enabled"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Enable icons in menus")
                settingKey: "Preferences/Advanced/EnableIconsInMenus"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Attach \"Add new torrent\" dialog to main window")
                settingKey: "AddNewTorrentDialog/Attached"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Enable embedded tracker")
                settingKey: "BitTorrent/TrackerEnabled"; defaultValue: false
            }
            AdvSpin {
                label: qsTr("Embedded tracker port")
                settingKey: "Preferences/Advanced/trackerPort"
                defaultValue: 9000; fromValue: 1; toValue: 65535
            }
            AdvCheck {
                label: qsTr("Enable port forwarding for embedded tracker")
                settingKey: "Preferences/Advanced/trackerPortForwarding"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Enable Mark-of-the-Web (MOTW) for downloaded files")
                settingKey: "Preferences/Advanced/markOfTheWeb"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Ignore SSL errors")
                settingKey: "Preferences/Advanced/IgnoreSSLErrors"; defaultValue: false
            }
            AdvLine {
                label: qsTr("Python executable path (may require restart)")
                settingKey: "Preferences/Search/pythonExecutablePath"
                placeholder: qsTr("(Auto detect if empty)")
            }
            AdvCheck {
                label: qsTr("Start BitTorrent session in paused state")
                settingKey: "BitTorrent/Session/StartPaused"; defaultValue: false
            }
            AdvSpin {
                label: qsTr("BitTorrent session shutdown timeout [-1: unlimited]")
                settingKey: "BitTorrent/Session/ShutdownTimeout"
                defaultValue: -1; fromValue: -1; suffix: qsTr("sec")
                specialText: qsTr("-1 (unlimited)"); specialValue: -1
            }
        }

        // ==== libtorrent Section =============================================
        MaterialCard {
            title: qsTr("libtorrent Section")
            titleIcon: Icons.settings_suggest
            Layout.fillWidth: true

            AdvSpin {
                label: qsTr("Bdecode depth limit")
                settingKey: "BitTorrent/BdecodeDepthLimit"; defaultValue: 100; fromValue: 0
            }
            AdvSpin {
                label: qsTr("Bdecode token limit")
                settingKey: "BitTorrent/BdecodeTokenLimit"; defaultValue: 10000000; fromValue: 0
            }
            AdvSpin {
                label: qsTr("Asynchronous I/O threads")
                settingKey: "BitTorrent/Session/AsyncIOThreadsCount"; defaultValue: 10; fromValue: 1; toValue: 1024
            }
            AdvSpin {
                label: qsTr("Hashing threads")
                settingKey: "BitTorrent/Session/HashingThreadsCount"; defaultValue: 1; fromValue: 1; toValue: 1024
            }
            AdvSpin {
                label: qsTr("File pool size")
                settingKey: "BitTorrent/Session/FilePoolSize"; defaultValue: 100; fromValue: 1
            }
            AdvSpin {
                label: qsTr("Outstanding memory when checking torrents")
                settingKey: "BitTorrent/Session/CheckingMemUsageSize"; defaultValue: 32; fromValue: 1; toValue: 1024; suffix: qsTr("MiB")
            }
            AdvSpin {
                label: qsTr("Disk queue size")
                settingKey: "BitTorrent/Session/DiskQueueSize"; defaultValue: 1024; fromValue: 1; suffix: qsTr("KiB")
            }
            AdvCombo {
                label: qsTr("Disk IO type (requires restart)")
                settingKey: "BitTorrent/Session/DiskIOType"
                items: [ qsTr("Default"), qsTr("Memory mapped files"), qsTr("POSIX-compliant"), qsTr("Simple pread/pwrite") ]
            }
            AdvCombo {
                label: qsTr("Disk IO read mode")
                settingKey: "BitTorrent/Session/DiskIOReadMode"
                items: [ qsTr("Disable OS cache"), qsTr("Enable OS cache") ]
                defaultValue: 1
            }
            AdvCombo {
                label: qsTr("Disk IO write mode")
                settingKey: "BitTorrent/Session/DiskIOWriteMode"
                items: [ qsTr("Disable OS cache"), qsTr("Enable OS cache"), qsTr("Write-through") ]
                defaultValue: 1
            }
            AdvCheck {
                label: qsTr("Use piece extent affinity")
                settingKey: "BitTorrent/Session/PieceExtentAffinity"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Send upload piece suggestions")
                settingKey: "BitTorrent/Session/SuggestMode"; defaultValue: false
            }
            AdvSpin {
                label: qsTr("Send buffer watermark")
                settingKey: "BitTorrent/Session/SendBufferWatermark"; defaultValue: 500; fromValue: 1; suffix: qsTr("KiB")
            }
            AdvSpin {
                label: qsTr("Send buffer low watermark")
                settingKey: "BitTorrent/Session/SendBufferLowWatermark"; defaultValue: 10; fromValue: 1; suffix: qsTr("KiB")
            }
            AdvSpin {
                label: qsTr("Send buffer watermark factor")
                settingKey: "BitTorrent/Session/SendBufferWatermarkFactor"; defaultValue: 50; fromValue: 1; suffix: qsTr("%")
            }
            AdvSpin {
                label: qsTr("Outgoing connections per second")
                settingKey: "BitTorrent/Session/ConnectionSpeed"; defaultValue: 30; fromValue: 0
            }
            AdvCheck {
                label: qsTr("Allow outgoing connections when seeding")
                settingKey: "BitTorrent/Session/SeedingOutgoingConnectionsEnabled"; defaultValue: true
            }
            AdvSpin {
                label: qsTr("Socket send buffer size [0: system default]")
                settingKey: "BitTorrent/Session/SocketSendBufferSize"; defaultValue: 0; fromValue: 0; suffix: qsTr("KiB")
                specialText: qsTr("0 (system default)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Socket receive buffer size [0: system default]")
                settingKey: "BitTorrent/Session/SocketReceiveBufferSize"; defaultValue: 0; fromValue: 0; suffix: qsTr("KiB")
                specialText: qsTr("0 (system default)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Socket backlog size")
                settingKey: "BitTorrent/Session/SocketBacklogSize"; defaultValue: 30; fromValue: 1
            }
            AdvSpin {
                label: qsTr("Outgoing ports (Min) [0: disabled]")
                settingKey: "BitTorrent/Session/OutgoingPortsMin"; defaultValue: 0; fromValue: 0; toValue: 65535
                specialText: qsTr("0 (disabled)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Outgoing ports (Max) [0: disabled]")
                settingKey: "BitTorrent/Session/OutgoingPortsMax"; defaultValue: 0; fromValue: 0; toValue: 65535
                specialText: qsTr("0 (disabled)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("UPnP lease duration [0: permanent lease]")
                settingKey: "BitTorrent/Session/UPnPLeaseDuration"; defaultValue: 0; fromValue: 0; suffix: qsTr("s")
                specialText: qsTr("0 (permanent lease)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Differentiated Services Code Point (DSCP) for connections to peers")
                settingKey: "BitTorrent/Session/PeerToS"; defaultValue: 1; fromValue: 0; toValue: 255
            }
            AdvCombo {
                label: qsTr("µTP-TCP mixed mode algorithm")
                settingKey: "BitTorrent/Session/uTPMixedMode"
                items: [ qsTr("Prefer TCP"), qsTr("Peer proportional (throttles TCP)") ]
            }
            AdvSpin {
                label: qsTr("Internal hostname resolver cache expiry interval")
                settingKey: "BitTorrent/Session/HostnameCacheTTL"; defaultValue: 1200; fromValue: 0; suffix: qsTr("s")
            }
            AdvCheck {
                label: qsTr("Support internationalized domain name (IDN)")
                settingKey: "BitTorrent/Session/IDNSupportEnabled"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Allow multiple connections from the same IP address")
                settingKey: "BitTorrent/Session/MultiConnectionsPerIp"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Validate HTTPS tracker certificates")
                settingKey: "BitTorrent/Session/ValidateHTTPSTrackerCertificate"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Server-side request forgery (SSRF) mitigation")
                settingKey: "BitTorrent/Session/SSRFMitigation"; defaultValue: true
            }
            AdvCheck {
                label: qsTr("Disallow connection to peers on privileged ports")
                settingKey: "BitTorrent/Session/BlockPeersOnPrivilegedPorts"; defaultValue: false
            }
            AdvCombo {
                label: qsTr("Upload slots behavior")
                settingKey: "BitTorrent/Session/ChokingAlgorithm"
                items: [ qsTr("Fixed slots"), qsTr("Upload rate based") ]
            }
            AdvCombo {
                label: qsTr("Upload choking algorithm")
                settingKey: "BitTorrent/Session/SeedChokingAlgorithm"
                items: [ qsTr("Round-robin"), qsTr("Fastest upload"), qsTr("Anti-leech") ]
                defaultValue: 1
            }
            AdvCheck {
                label: qsTr("Always announce to all trackers in a tier")
                settingKey: "BitTorrent/Session/AnnounceToAllTrackers"; defaultValue: false
            }
            AdvCheck {
                label: qsTr("Always announce to all tiers")
                settingKey: "BitTorrent/Session/AnnounceToAllTiers"; defaultValue: true
            }
            AdvLine {
                label: qsTr("IP address reported to trackers (requires restart)")
                settingKey: "BitTorrent/Session/AnnounceIP"
            }
            AdvSpin {
                label: qsTr("Port reported to trackers (requires restart) [0: listening port]")
                settingKey: "BitTorrent/Session/AnnouncePort"; defaultValue: 0; fromValue: 0; toValue: 65535
            }
            AdvSpin {
                label: qsTr("Max concurrent HTTP announces")
                settingKey: "BitTorrent/Session/MaxConcurrentHTTPAnnounces"; defaultValue: 50; fromValue: 0
            }
            AdvSpin {
                label: qsTr("Stop tracker timeout [0: disabled]")
                settingKey: "BitTorrent/Session/StopTrackerTimeout"; defaultValue: 2; fromValue: 0; suffix: qsTr("s")
                specialText: qsTr("0 (disabled)"); specialValue: 0
            }
            AdvSpin {
                label: qsTr("Peer turnover disconnect percentage")
                settingKey: "BitTorrent/Session/PeerTurnover"; defaultValue: 4; fromValue: 0; toValue: 100; suffix: qsTr("%")
            }
            AdvSpin {
                label: qsTr("Peer turnover threshold percentage")
                settingKey: "BitTorrent/Session/PeerTurnoverCutOff"; defaultValue: 90; fromValue: 0; toValue: 100; suffix: qsTr("%")
            }
            AdvSpin {
                label: qsTr("Peer turnover disconnect interval")
                settingKey: "BitTorrent/Session/PeerTurnoverInterval"; defaultValue: 300; fromValue: 30; toValue: 3600; suffix: qsTr("s")
            }
            AdvSpin {
                label: qsTr("Maximum outstanding requests to a single peer")
                settingKey: "BitTorrent/Session/RequestQueueSize"; defaultValue: 500; fromValue: 1
            }
            AdvLine {
                label: qsTr("DHT bootstrap nodes")
                settingKey: "BitTorrent/Session/DHTBootstrapNodes"
                placeholder: qsTr("Resets to default if empty")
            }
            AdvSpin {
                label: qsTr("I2P inbound quantity")
                settingKey: "BitTorrent/Session/I2P/InboundQuantity"; defaultValue: 3; fromValue: 1; toValue: 16
            }
            AdvSpin {
                label: qsTr("I2P outbound quantity")
                settingKey: "BitTorrent/Session/I2P/OutboundQuantity"; defaultValue: 3; fromValue: 1; toValue: 16
            }
            AdvSpin {
                label: qsTr("I2P inbound length")
                settingKey: "BitTorrent/Session/I2P/InboundLength"; defaultValue: 3; fromValue: 0; toValue: 7
            }
            AdvSpin {
                label: qsTr("I2P outbound length")
                settingKey: "BitTorrent/Session/I2P/OutboundLength"; defaultValue: 3; fromValue: 0; toValue: 7
            }
        }
    }
}
