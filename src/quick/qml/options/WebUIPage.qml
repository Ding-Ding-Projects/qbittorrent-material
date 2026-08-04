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
    \qmltype WebUIPage
    \brief Options → Web UI page (legacy TAB_WEBUI).

    The whole page is one big checkable card (WebUI enabled) containing address /
    port / UPnP, the HTTPS sub-group, Authentication (username / password + the
    immediately-applied API key with copy / rotate / delete via
    \c APIKeyConfirmDialog, plus the IP subnet whitelist launcher), alt-WebUI,
    Security, custom HTTP headers, reverse-proxy support and DynDNS.
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
            Log.debug("ui", "WebUI: " + settingKey + " -> " + checked)
        }
    }

    Component.onCompleted: Log.debug("ui", "WebUIPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        CheckableGroupBox {
            property string paletteSettingKey: "Preferences/WebUI/Enabled"
            property string paletteSettingTitle: title
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: false
            title: qsTr("Web User Interface (Remote control)")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("Preferences/WebUI/Enabled", false))
            onToggled: (v) => OptionsController.setValue("Preferences/WebUI/Enabled", v)

            LabeledField {
                label: qsTr("IP address:")
                labelWidth: 160
                Layout.fillWidth: true
                TextField {
                    property string paletteSettingKey: "Preferences/WebUI/Address"
                    property string paletteSettingTitle: qsTr("Web UI IP address")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: "*"
                    Layout.fillWidth: true
                    placeholderText: "*"
                    text: (root.rev, OptionsController.value("Preferences/WebUI/Address", "*"))
                    onEditingFinished: OptionsController.setValue("Preferences/WebUI/Address", text)
                }
            }
            LabeledField {
                label: qsTr("Port:")
                labelWidth: 160
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "Preferences/WebUI/Port"
                    property string paletteSettingTitle: qsTr("Web UI port")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 8080
                    from: 1; to: 65535; editable: true
                    value: (root.rev, OptionsController.value("Preferences/WebUI/Port", 8080))
                    onValueModified: OptionsController.setValue("Preferences/WebUI/Port", value)
                }
            }
            OptCheck {
                text: qsTr("Use UPnP / NAT-PMP to forward the port from my router")
                settingKey: "Preferences/WebUI/UseUPnP"
                defaultValue: false
            }

            // ---- HTTPS --------------------------------------------------------
            CheckableGroupBox {
                property string paletteSettingKey: "Preferences/WebUI/HTTPS/Enabled"
                property string paletteSettingTitle: title
                property string paletteSettingKind: "toggle"
                property var paletteSettingDefault: false
                title: qsTr("Use HTTPS instead of HTTP")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/WebUI/HTTPS/Enabled", false))
                onToggled: (v) => OptionsController.setValue("Preferences/WebUI/HTTPS/Enabled", v)
                LabeledField {
                    label: qsTr("Certificate:")
                    orientation: Qt.Vertical
                    Layout.fillWidth: true
                    PathField {
                        property string paletteSettingKey: "Preferences/WebUI/HTTPS/CertificatePath"
                        property string paletteSettingTitle: qsTr("HTTPS certificate path")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        Layout.fillWidth: true
                        pickFolder: false
                        title: qsTr("Select certificate")
                        path: (root.rev, OptionsController.value("Preferences/WebUI/HTTPS/CertificatePath", ""))
                        onPathChanged: OptionsController.setValue("Preferences/WebUI/HTTPS/CertificatePath", path)
                    }
                }
                LabeledField {
                    label: qsTr("Key:")
                    orientation: Qt.Vertical
                    Layout.fillWidth: true
                    PathField {
                        property string paletteSettingKey: "Preferences/WebUI/HTTPS/KeyPath"
                        property string paletteSettingTitle: qsTr("HTTPS private-key path")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        Layout.fillWidth: true
                        pickFolder: false
                        title: qsTr("Select key")
                        path: (root.rev, OptionsController.value("Preferences/WebUI/HTTPS/KeyPath", ""))
                        onPathChanged: OptionsController.setValue("Preferences/WebUI/HTTPS/KeyPath", path)
                    }
                }
            }

            // ---- Authentication ----------------------------------------------
            MaterialCard {
                title: qsTr("Authentication")
                titleIcon: Icons.lock
                Layout.fillWidth: true

                LabeledField {
                    label: qsTr("Username:")
                    labelWidth: 160
                    Layout.fillWidth: true
                    TextField {
                        property string paletteSettingKey: "Preferences/WebUI/Username"
                        property string paletteSettingTitle: qsTr("Web UI username")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: "admin"
                        Layout.fillWidth: true
                        text: (root.rev, OptionsController.value("Preferences/WebUI/Username", "admin"))
                        onEditingFinished: OptionsController.setValue("Preferences/WebUI/Username", text)
                    }
                }
                LabeledField {
                    label: qsTr("Password:")
                    labelWidth: 160
                    Layout.fillWidth: true
                    TextField {
                        property string paletteSettingKey: "Preferences/WebUI/Password_Plaintext"
                        property string paletteSettingTitle: qsTr("Web UI password")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        property bool paletteSettingSensitive: true
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: qsTr("Change current password")
                        onEditingFinished: if (text.length > 0) OptionsController.setValue("Preferences/WebUI/Password_Plaintext", text)
                    }
                }

                // API key — applied immediately (not via OK/Apply).
                SectionHeader { text: qsTr("API Key"); Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm
                    TextField {
                        property string paletteSettingKey: "Preferences/WebUI/APIKey"
                        property string paletteSettingTitle: qsTr("Web UI API key")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        property bool paletteSettingSensitive: true
                        Layout.fillWidth: true
                        readOnly: true
                        placeholderText: qsTr("Generate a key")
                        text: (root.rev, OptionsController.maskedApiKey())
                    }
                    IconButton {
                        property string paletteActionKey: "copy-api-key"
                        property string paletteActionTitle: tooltip
                        symbol: Icons.content_copy
                        tooltip: qsTr("Copy API key")
                        enabled: OptionsController.apiKeyValid
                        onClicked: {
                            Log.info("ui", "WebUI: copy API key")
                            if (OptionsController.copyApiKeyToClipboard())
                                NotificationCenter.notify(qsTr("API key copied to clipboard"), "success")
                            else
                                NotificationCenter.notify(qsTr("Could not copy the API key"), "error")
                        }
                    }
                    IconButton {
                        property string paletteActionKey: "rotate-or-generate-api-key"
                        property string paletteActionTitle: tooltip
                        symbol: Icons.refresh
                        tooltip: OptionsController.apiKeyValid ? qsTr("Rotate API key") : qsTr("Generate API key")
                        onClicked: {
                            apiKeyDialog.mode = OptionsController.apiKeyValid ? "rotate" : "generate"
                            apiKeyDialog.open()
                        }
                    }
                    IconButton {
                        property string paletteActionKey: "delete-api-key"
                        property string paletteActionTitle: tooltip
                        symbol: Icons.remove
                        tooltip: qsTr("Delete API key")
                        enabled: OptionsController.apiKeyValid
                        onClicked: {
                            apiKeyDialog.mode = "delete"
                            apiKeyDialog.open()
                        }
                    }
                }
            }

            OptCheck {
                text: qsTr("Bypass authentication for clients on localhost")
                // Human-facing key; OptionsController maps to inverted LocalHostAuth.
                settingKey: "WebUI/BypassLocalAuth"
                defaultValue: true
            }
            OptCheck {
                id: bypassSubnet
                text: qsTr("Bypass authentication for clients in whitelisted IP subnets")
                settingKey: "Preferences/WebUI/AuthSubnetWhitelistEnabled"
                defaultValue: false
            }
            Button {
                property string paletteActionKey: "edit-ip-subnet-whitelist"
                property string paletteActionTitle: text
                text: qsTr("IP subnet whitelist...")
                enabled: bypassSubnet.checked
                onClicked: {
                    Log.info("ui", "WebUI: opening IPSubnetWhitelistDialog")
                    subnetDialog.open()
                }
            }

            LabeledField {
                label: qsTr("Ban client after consecutive failures:")
                labelWidth: 300
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "Preferences/WebUI/MaxAuthenticationFailCount"
                    property string paletteSettingTitle: qsTr("Maximum Web UI authentication failures")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 5
                    from: 0; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("Preferences/WebUI/MaxAuthenticationFailCount", 5))
                    textFromValue: (v, l) => v === 0 ? qsTr("Never") : Number(v).toLocaleString(l, 'f', 0)
                    valueFromText: (t) => t.indexOf(qsTr("Never")) !== -1 ? 0 : (parseInt(t.replace(/[^0-9]/g, "")) || 0)
                    onValueModified: OptionsController.setValue("Preferences/WebUI/MaxAuthenticationFailCount", value)
                }
            }
            LabeledField {
                label: qsTr("ban for:")
                labelWidth: 300
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "Preferences/WebUI/BanDuration"
                    property string paletteSettingTitle: qsTr("Web UI client ban duration")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 3600
                    from: 1; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("Preferences/WebUI/BanDuration", 3600))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("sec")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 1
                    onValueModified: OptionsController.setValue("Preferences/WebUI/BanDuration", value)
                }
            }
            LabeledField {
                label: qsTr("Session timeout:")
                labelWidth: 300
                Layout.fillWidth: true
                SpinBox {
                    property string paletteSettingKey: "Preferences/WebUI/SessionTimeout"
                    property string paletteSettingTitle: qsTr("Web UI session timeout")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 3600
                    from: 0; to: 2147483647; editable: true
                    value: (root.rev, OptionsController.value("Preferences/WebUI/SessionTimeout", 3600))
                    textFromValue: (v, l) => v === 0 ? qsTr("Disabled") : (Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("sec"))
                    valueFromText: (t) => t.indexOf(qsTr("Disabled")) !== -1 ? 0 : (parseInt(t.replace(/[^0-9]/g, "")) || 0)
                    onValueModified: OptionsController.setValue("Preferences/WebUI/SessionTimeout", value)
                }
            }

            // ---- Alternative WebUI -------------------------------------------
            CheckableGroupBox {
                property string paletteSettingKey: "Preferences/WebUI/AlternativeUIEnabled"
                property string paletteSettingTitle: title
                property string paletteSettingKind: "toggle"
                property var paletteSettingDefault: false
                title: qsTr("Use alternative WebUI")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/WebUI/AlternativeUIEnabled", false))
                onToggled: (v) => OptionsController.setValue("Preferences/WebUI/AlternativeUIEnabled", v)
                LabeledField {
                    label: qsTr("Files location:")
                    orientation: Qt.Vertical
                    Layout.fillWidth: true
                    PathField {
                        property string paletteSettingKey: "Preferences/WebUI/RootFolder"
                        property string paletteSettingTitle: qsTr("Alternative Web UI files location")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        Layout.fillWidth: true
                        title: qsTr("Choose Alternative UI files location")
                        path: (root.rev, OptionsController.value("Preferences/WebUI/RootFolder", ""))
                        onPathChanged: OptionsController.setValue("Preferences/WebUI/RootFolder", path)
                    }
                }
            }

            // ---- Security -----------------------------------------------------
            MaterialCard {
                title: qsTr("Security")
                titleIcon: Icons.shield
                Layout.fillWidth: true
                OptCheck {
                    text: qsTr("Enable clickjacking protection")
                    settingKey: "Preferences/WebUI/ClickjackingProtection"
                    defaultValue: true
                }
                OptCheck {
                    text: qsTr("Enable Cross-Site Request Forgery (CSRF) protection")
                    settingKey: "Preferences/WebUI/CSRFProtection"
                    defaultValue: true
                }
                OptCheck {
                    text: qsTr("Enable cookie Secure flag (requires HTTPS or localhost connection)")
                    settingKey: "Preferences/WebUI/SecureCookie"
                    defaultValue: true
                }
                CheckableGroupBox {
                    property string paletteSettingKey: "Preferences/WebUI/HostHeaderValidation"
                    property string paletteSettingTitle: title
                    property string paletteSettingKind: "toggle"
                    property var paletteSettingDefault: true
                    title: qsTr("Enable Host header validation")
                    Layout.fillWidth: true
                    checked: (root.rev, OptionsController.value("Preferences/WebUI/HostHeaderValidation", true))
                    onToggled: (v) => OptionsController.setValue("Preferences/WebUI/HostHeaderValidation", v)
                    LabeledField {
                        label: qsTr("Server domains:")
                        orientation: Qt.Vertical
                        Layout.fillWidth: true
                        TextField {
                            property string paletteSettingKey: "Preferences/WebUI/ServerDomains"
                            property string paletteSettingTitle: qsTr("Web UI server domains")
                            property string paletteSettingKind: "destination"
                            property var paletteSettingDefault: "*"
                            Layout.fillWidth: true
                            placeholderText: "*"
                            text: (root.rev, OptionsController.value("Preferences/WebUI/ServerDomains", "*"))
                            onEditingFinished: OptionsController.setValue("Preferences/WebUI/ServerDomains", text)
                        }
                    }
                }
            }

            // ---- Custom HTTP headers -----------------------------------------
            CheckableGroupBox {
                property string paletteSettingKey: "Preferences/WebUI/CustomHTTPHeadersEnabled"
                property string paletteSettingTitle: title
                property string paletteSettingKind: "toggle"
                property var paletteSettingDefault: false
                title: qsTr("Add custom HTTP headers")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/WebUI/CustomHTTPHeadersEnabled", false))
                onToggled: (v) => OptionsController.setValue("Preferences/WebUI/CustomHTTPHeadersEnabled", v)
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    TextArea {
                        property string paletteSettingKey: "Preferences/WebUI/CustomHTTPHeaders"
                        property string paletteSettingTitle: qsTr("Custom HTTP headers")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        wrapMode: TextEdit.NoWrap
                        font: Typography.mono
                        placeholderText: qsTr("Header: value pairs, one per line")
                        text: (root.rev, OptionsController.value("Preferences/WebUI/CustomHTTPHeaders", ""))
                        onEditingFinished: OptionsController.setValue("Preferences/WebUI/CustomHTTPHeaders", text)
                    }
                }
            }

            // ---- Reverse proxy ------------------------------------------------
            CheckableGroupBox {
                property string paletteSettingKey: "Preferences/WebUI/ReverseProxySupportEnabled"
                property string paletteSettingTitle: title
                property string paletteSettingKind: "toggle"
                property var paletteSettingDefault: false
                title: qsTr("Enable reverse proxy support")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/WebUI/ReverseProxySupportEnabled", false))
                onToggled: (v) => OptionsController.setValue("Preferences/WebUI/ReverseProxySupportEnabled", v)
                LabeledField {
                    label: qsTr("Trusted proxies list:")
                    orientation: Qt.Vertical
                    Layout.fillWidth: true
                    TextField {
                        property string paletteSettingKey: "Preferences/WebUI/TrustedReverseProxiesList"
                        property string paletteSettingTitle: qsTr("Trusted reverse proxies list")
                        property string paletteSettingKind: "destination"
                        property var paletteSettingDefault: ""
                        Layout.fillWidth: true
                        text: (root.rev, OptionsController.value("Preferences/WebUI/TrustedReverseProxiesList", ""))
                        onEditingFinished: OptionsController.setValue("Preferences/WebUI/TrustedReverseProxiesList", text)
                    }
                }
            }
        }

        // ==== DynDNS ==========================================================
        CheckableGroupBox {
            property string paletteSettingKey: "Preferences/DynDNS/Enabled"
            property string paletteSettingTitle: title
            property string paletteSettingKind: "toggle"
            property var paletteSettingDefault: false
            title: qsTr("Update my dynamic domain name")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("Preferences/DynDNS/Enabled", false))
            onToggled: (v) => OptionsController.setValue("Preferences/DynDNS/Enabled", v)

            LabeledField {
                label: qsTr("Service:")
                labelWidth: 160
                Layout.fillWidth: true
                ComboBox {
                    property string paletteSettingKey: "Preferences/DynDNS/Service"
                    property string paletteSettingTitle: qsTr("Dynamic DNS service")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: 0
                    Layout.fillWidth: true
                    model: [ qsTr("DynDNS"), qsTr("No-IP") ]
                    currentIndex: (root.rev, OptionsController.value("Preferences/DynDNS/Service", 0))
                    onActivated: (i) => OptionsController.setValue("Preferences/DynDNS/Service", i)
                }
            }
            Button {
                property string paletteActionKey: "register-dyndns"
                property string paletteActionTitle: text
                text: qsTr("Register")
                onClicked: {
                    Log.info("ui", "WebUI: DynDNS register")
                    OptionsController.openDynDNSRegistration()
                }
            }
            LabeledField {
                label: qsTr("Domain name:")
                labelWidth: 160
                Layout.fillWidth: true
                TextField {
                    property string paletteSettingKey: "Preferences/DynDNS/DomainName"
                    property string paletteSettingTitle: qsTr("Dynamic DNS domain name")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: "changeme.dyndns.org"
                    Layout.fillWidth: true
                    text: (root.rev, OptionsController.value("Preferences/DynDNS/DomainName", "changeme.dyndns.org"))
                    onEditingFinished: OptionsController.setValue("Preferences/DynDNS/DomainName", text)
                }
            }
            LabeledField {
                label: qsTr("Username:")
                labelWidth: 160
                Layout.fillWidth: true
                TextField {
                    property string paletteSettingKey: "Preferences/DynDNS/Username"
                    property string paletteSettingTitle: qsTr("Dynamic DNS username")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    Layout.fillWidth: true
                    text: (root.rev, OptionsController.value("Preferences/DynDNS/Username", ""))
                    onEditingFinished: OptionsController.setValue("Preferences/DynDNS/Username", text)
                }
            }
            LabeledField {
                label: qsTr("Password:")
                labelWidth: 160
                Layout.fillWidth: true
                TextField {
                    property string paletteSettingKey: "Preferences/DynDNS/Password"
                    property string paletteSettingTitle: qsTr("Dynamic DNS password")
                    property string paletteSettingKind: "destination"
                    property var paletteSettingDefault: ""
                    property bool paletteSettingSensitive: true
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    text: (root.rev, OptionsController.value("Preferences/DynDNS/Password", ""))
                    onEditingFinished: OptionsController.setValue("Preferences/DynDNS/Password", text)
                }
            }
        }
    }

    IPSubnetWhitelistDialog { id: subnetDialog }

    APIKeyConfirmDialog {
        id: apiKeyDialog
        onConfirmed: (mode) => {
            Log.info("ui", "WebUI: API key action confirmed: " + mode)
            if (mode === "delete")
                OptionsController.deleteApiKey()
            else
                OptionsController.rotateApiKey()   // also used for first generation
        }
    }

    Connections {
        target: OptionsController
        function onActionFeedback(action, success, message) {
            if (action === "dynDNS")
                NotificationCenter.notify(message, success ? "success" : "error")
        }
    }
}
