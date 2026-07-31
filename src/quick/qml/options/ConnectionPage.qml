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
    \qmltype ConnectionPage
    \brief Options → Connection page (legacy TAB_CONNECTION).

    Peer protocol, Listening Port, Connection Limits, I2P, Proxy Server (with the
    legacy \c adjustProxyOptions enable matrix) and IP Filtering (including the
    "Manually banned IP addresses..." button that opens \c BanListOptionsDialog).
*/
Flickable {
    id: root

    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    // Current proxy type drives the enable matrix.
    readonly property int proxyType: (root.rev, OptionsController.value("Network/Proxy/Type", 0))
    readonly property bool proxyAuthSupported: proxyType === 2 || proxyType === 3   // SOCKS5 / HTTP
    readonly property bool proxyIsSocks4: proxyType === 1
    readonly property bool proxyNone: proxyType === 0

    component OptCheck: CheckBox {
        property string settingKey: ""
        property bool defaultValue: false
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "Connection: " + settingKey + " -> " + checked)
        }
    }

    // Enable-checkbox + limit-spin pair (getter returns -1 when unchecked).
    component LimitRow: RowLayout {
        property string enableKey: ""
        property string valueKey: ""
        property string labelText: ""
        property int fromValue: 2
        property int defaultValue: 0
        Layout.fillWidth: true
        spacing: Spacing.sm
        OptCheck {
            id: en
            text: parent.labelText
            settingKey: parent.enableKey
            defaultValue: true
        }
        Item { Layout.fillWidth: true }
        SpinBox {
            enabled: en.checked
            editable: true
            from: parent.fromValue; to: 2147483647
            value: (root.rev, OptionsController.value(parent.valueKey, parent.defaultValue))
            onValueModified: OptionsController.setValue(parent.valueKey, value)
        }
    }

    Component.onCompleted: Log.debug("ui", "ConnectionPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== Protocol ========================================================
        MaterialCard {
            title: qsTr("Connection")
            titleIcon: Icons.lan
            Layout.fillWidth: true
            LabeledField {
                label: qsTr("Peer connection protocol:")
                labelWidth: 260
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("TCP and μTP"), qsTr("TCP"), qsTr("μTP") ]
                    currentIndex: (root.rev, OptionsController.value("BitTorrent/Session/BTProtocol", 0))
                    onActivated: (i) => OptionsController.setValue("BitTorrent/Session/BTProtocol", i)
                }
            }
        }

        // ==== Listening Port ==================================================
        MaterialCard {
            title: qsTr("Listening Port")
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                Label {
                    text: qsTr("Port used for incoming connections:")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                Item { Layout.fillWidth: true }
                SpinBox {
                    id: portSpin
                    editable: true
                    from: 0; to: 65535
                    value: (root.rev, OptionsController.value("BitTorrent/Session/Port", 0))
                    textFromValue: (v, l) => v === 0 ? qsTr("Any") : Number(v).toLocaleString(l, 'f', 0)
                    valueFromText: (t) => {
                        var n = parseInt(t.replace(/[^0-9]/g, ""))
                        return isNaN(n) ? 0 : n
                    }
                    onValueModified: OptionsController.setValue("BitTorrent/Session/Port", value)
                }
                Button {
                    text: qsTr("Random")
                    onClicked: {
                        var p = 1024 + Math.floor(Math.random() * (65535 - 1024))
                        Log.info("ui", "Connection: random port " + p)
                        portSpin.value = p
                        OptionsController.setValue("BitTorrent/Session/Port", p)
                    }
                }
            }
            OptCheck {
                text: qsTr("Use UPnP / NAT-PMP port forwarding from my router")
                settingKey: "Network/PortForwardingEnabled"
                defaultValue: true
            }
        }

        // ==== Connections Limits ==============================================
        MaterialCard {
            title: qsTr("Connections Limits")
            Layout.fillWidth: true
            LimitRow {
                labelText: qsTr("Global maximum number of connections:")
                enableKey: "Connection/MaxConnectionsEnabled"
                valueKey: "BitTorrent/Session/MaxConnections"
                fromValue: 2; defaultValue: 500
            }
            LimitRow {
                labelText: qsTr("Maximum number of connections per torrent:")
                enableKey: "Connection/MaxConnectionsPerTorrentEnabled"
                valueKey: "BitTorrent/Session/MaxConnectionsPerTorrent"
                fromValue: 2; defaultValue: 100
            }
            LimitRow {
                labelText: qsTr("Global maximum number of upload slots:")
                enableKey: "Connection/MaxUploadsEnabled"
                valueKey: "BitTorrent/Session/MaxUploads"
                fromValue: 0; defaultValue: 20
            }
            LimitRow {
                labelText: qsTr("Maximum number of upload slots per torrent:")
                enableKey: "Connection/MaxUploadsPerTorrentEnabled"
                valueKey: "BitTorrent/Session/MaxUploadsPerTorrent"
                fromValue: 0; defaultValue: 4
            }
        }

        // ==== I2P =============================================================
        CheckableGroupBox {
            title: qsTr("I2P (experimental)")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("BitTorrent/Session/I2P/Enabled", false))
            onToggled: (v) => OptionsController.setValue("BitTorrent/Session/I2P/Enabled", v)
            LabeledField {
                label: qsTr("Host:")
                labelWidth: 100
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    text: (root.rev, OptionsController.value("BitTorrent/Session/I2P/Address", "127.0.0.1"))
                    onEditingFinished: OptionsController.setValue("BitTorrent/Session/I2P/Address", text.trim())
                }
            }
            LabeledField {
                label: qsTr("Port:")
                labelWidth: 100
                Layout.fillWidth: true
                SpinBox {
                    from: 1; to: 65535; editable: true
                    value: (root.rev, OptionsController.value("BitTorrent/Session/I2P/Port", 7656))
                    onValueModified: OptionsController.setValue("BitTorrent/Session/I2P/Port", value)
                }
            }
            OptCheck {
                text: qsTr("Mixed mode")
                settingKey: "BitTorrent/Session/I2P/MixedMode"
                defaultValue: false
            }
        }

        // ==== Proxy Server ====================================================
        MaterialCard {
            title: qsTr("Proxy Server")
            Layout.fillWidth: true

            LabeledField {
                label: qsTr("Type:")
                labelWidth: 120
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("(None)"), qsTr("SOCKS4"), qsTr("SOCKS5"), qsTr("HTTP") ]
                    currentIndex: (root.rev, OptionsController.value("Network/Proxy/Type", 0))
                    onActivated: (i) => OptionsController.setValue("Network/Proxy/Type", i)
                }
            }
            LabeledField {
                label: qsTr("Host:")
                labelWidth: 120
                Layout.fillWidth: true
                TextField {
                    Layout.fillWidth: true
                    enabled: !root.proxyNone
                    text: (root.rev, OptionsController.value("Network/Proxy/IP", ""))
                    onEditingFinished: OptionsController.setValue("Network/Proxy/IP", text.trim())
                }
            }
            LabeledField {
                label: qsTr("Port:")
                labelWidth: 120
                Layout.fillWidth: true
                SpinBox {
                    enabled: !root.proxyNone
                    from: 1; to: 65535; editable: true
                    value: (root.rev, OptionsController.value("Network/Proxy/Port", 8080))
                    onValueModified: OptionsController.setValue("Network/Proxy/Port", value)
                }
            }
            Label {
                visible: root.proxyIsSocks4
                text: qsTr("Some functions are unavailable with the chosen proxy type!")
                font: Typography.labelSmall
                color: Theme.color("warning")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            OptCheck {
                text: qsTr("Perform hostname lookup via proxy")
                settingKey: "Network/Proxy/HostnameLookupEnabled"
                defaultValue: true
                enabled: root.proxyAuthSupported
            }

            CheckableGroupBox {
                title: qsTr("Authentication")
                Layout.fillWidth: true
                enabled: root.proxyAuthSupported
                checked: (root.rev, OptionsController.value("Network/Proxy/AuthEnabled", false))
                onToggled: (v) => OptionsController.setValue("Network/Proxy/AuthEnabled", v)
                LabeledField {
                    label: qsTr("Username:")
                    labelWidth: 120
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        text: (root.rev, OptionsController.value("Network/Proxy/Username", ""))
                        onEditingFinished: OptionsController.setValue("Network/Proxy/Username", text.trim())
                    }
                }
                LabeledField {
                    label: qsTr("Password:")
                    labelWidth: 120
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        text: (root.rev, OptionsController.value("Network/Proxy/Password", ""))
                        onEditingFinished: OptionsController.setValue("Network/Proxy/Password", text.trim())
                    }
                }
                Label {
                    text: qsTr("Note: The password is saved unencrypted")
                    font: Typography.labelSmall
                    color: Theme.color("onSurfaceVariant")
                    Layout.fillWidth: true
                }
            }

            CheckableGroupBox {
                title: qsTr("Use proxy for BitTorrent purposes")
                Layout.fillWidth: true
                enabled: !root.proxyNone
                checked: (root.rev, OptionsController.value("Network/Proxy/Profiles/BitTorrent", false))
                onToggled: (v) => OptionsController.setValue("Network/Proxy/Profiles/BitTorrent", v)
                OptCheck {
                    text: qsTr("Use proxy for peer connections")
                    settingKey: "BitTorrent/Session/ProxyPeerConnections"
                    defaultValue: false
                }
            }
            OptCheck {
                text: qsTr("Use proxy for RSS purposes")
                settingKey: "Network/Proxy/Profiles/RSS"
                defaultValue: false
                enabled: root.proxyAuthSupported
            }
            OptCheck {
                text: qsTr("Use proxy for general purposes")
                settingKey: "Network/Proxy/Profiles/Misc"
                defaultValue: false
                enabled: root.proxyAuthSupported
            }
        }

        // ==== IP Filtering ====================================================
        MaterialCard {
            title: qsTr("IP Filtering")
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: ipFilterEnable
                    text: qsTr("Filter path (.dat, .p2p, .p2b):")
                    settingKey: "BitTorrent/Session/IPFilteringEnabled"
                    defaultValue: false
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                PathField {
                    Layout.fillWidth: true
                    enabled: ipFilterEnable.checked
                    pickFolder: false
                    title: qsTr("Choose an IP filter file")
                    path: (root.rev, OptionsController.value("BitTorrent/Session/IPFilter", ""))
                    onPathChanged: OptionsController.setValue("BitTorrent/Session/IPFilter", path)
                }
                IconButton {
                    symbol: Icons.refresh
                    tooltip: qsTr("Reload the filter")
                    enabled: ipFilterEnable.checked
                    onClicked: {
                        Log.info("ui", "Connection: reload IP filter")
                        OptionsController.reloadIPFilter()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                Button {
                    text: qsTr("Manually banned IP addresses...")
                    onClicked: {
                        Log.info("ui", "Connection: opening BanListOptionsDialog")
                        banListDialog.open()
                    }
                }
                Item { Layout.fillWidth: true }
            }
            OptCheck {
                text: qsTr("Apply to trackers")
                settingKey: "BitTorrent/Session/TrackerFilteringEnabled"
                defaultValue: false
            }
        }
    }

    // IP filter parse result feedback.
    Connections {
        target: OptionsController
        function onIpFilterParsed(error, ruleCount) {
            if (error)
                NotificationCenter.notify(qsTr("Failed to parse the provided IP filter"), "error")
            else
                NotificationCenter.notify(qsTr("Successfully parsed the provided IP filter: %1 rules were found.").arg(ruleCount), "success")
        }
    }

    BanListOptionsDialog { id: banListDialog }
}
