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
    \qmltype BanListOptionsDialog
    \brief "List of banned IP addresses" editor (Connection tab).

    Loads the current \c BitTorrent/Session/BannedIPs list on open and, on OK,
    stages the edited list back through \c OptionsController (so it participates
    in the dialog-wide Apply). Add via the field + Enter / the add button;
    remove the selected row.
*/
Dialog {
    id: root

    readonly property string settingKey: "BitTorrent/Session/BannedIPs"

    title: qsTr("List of banned IP addresses")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, (parent ? parent.width : 440) * 0.95)
    height: Math.min(520, (parent ? parent.height : 520) * 0.95)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale
    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    ListModel { id: entries }

    property string validationMessage: ""

    function open() {
        entries.clear()
        validationMessage = ""
        var list = OptionsController.value(settingKey, [])
        for (var i = 0; i < list.length; ++i)
            entries.append({ value: list[i] })
        Log.info("ui", "BanListOptionsDialog opened with " + entries.count + " entries")
        visible = true
    }

    function addEntry(text) {
        var v = ("" + text).trim()
        if (v.length === 0)
            return false
        if (!OptionsController.isValidBannedIPAddress(v)) {
            validationMessage = qsTr("Enter a valid IPv4 or IPv6 address.")
            addField.forceActiveFocus()
            return false
        }
        for (var i = 0; i < entries.count; ++i) {
            if (entries.get(i).value === v) {
                validationMessage = qsTr("This IP address is already listed.")
                addField.forceActiveFocus()
                return false
            }
        }
        entries.append({ value: v })
        validationMessage = ""
        Log.debug("ui", "BanList add: " + v)
        return true
    }

    function stageEntries() {
        var list = []
        for (var i = 0; i < entries.count; ++i) {
            var value = entries.get(i).value
            if (!OptionsController.isValidBannedIPAddress(value)) {
                validationMessage = qsTr("Remove the invalid IP address before saving.")
                listView.currentIndex = i
                listView.positionViewAtIndex(i, ListView.Contain)
                listView.forceActiveFocus()
                return false
            }
            list.push(value)
        }
        OptionsController.setValue(settingKey, list)
        Log.info("ui", "BanListOptionsDialog saved " + list.length + " banned IPs")
        return true
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
        spacing: Spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.sm
            TextField {
                id: addField
                Layout.fillWidth: true
                placeholderText: qsTr("IPv4 or IPv6 address to ban")
                Accessible.name: qsTr("IP address to ban")
                Accessible.description: root.validationMessage.length > 0
                    ? root.validationMessage
                    : qsTr("Enter an exact IPv4 or IPv6 address.")
                onTextChanged: root.validationMessage = ""
                onAccepted: {
                    if (root.addEntry(text))
                        text = ""
                }
            }
            Button {
                text: qsTr("Add")
                onClicked: {
                    if (root.addEntry(addField.text))
                        addField.text = ""
                }
            }
        }

        Label {
            objectName: "banListValidationMessage"
            Layout.fillWidth: true
            visible: root.validationMessage.length > 0
            text: root.validationMessage
            color: Theme.color("error")
            wrapMode: Text.Wrap
            Accessible.name: root.validationMessage
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 0
            background: Rectangle {
                radius: Spacing.radiusField
                color: Theme.color("surfaceVariant")
                border.width: 1
                border.color: Theme.color("outlineVariant")
            }
            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: Spacing.xs
                clip: true
                model: entries
                currentIndex: -1
                Accessible.name: qsTr("Banned IP address list")
                Accessible.description: root.validationMessage.length > 0
                    ? root.validationMessage
                    : qsTr("Select an IP address to remove it from the list.")
                delegate: ItemDelegate {
                    required property int index
                    required property string value
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    onClicked: listView.currentIndex = index
                    contentItem: Label {
                        text: value
                        font: Typography.mono
                        color: Theme.color("onSurface")
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Button {
            text: qsTr("Remove")
            enabled: listView.currentIndex >= 0
            onClicked: {
                Log.debug("ui", "BanList remove row " + listView.currentIndex)
                entries.remove(listView.currentIndex)
                listView.currentIndex = -1
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
        topPadding: Spacing.sm
        spacing: Spacing.sm
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                if (root.stageEntries())
                    root.accept()
            }
        }
    }

    onOpened: addField.forceActiveFocus()
    onRejected: Log.debug("ui", "BanListOptionsDialog cancelled")
}
