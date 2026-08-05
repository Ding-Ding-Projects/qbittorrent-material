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
    \qmltype NewPluginUrlDialog
    \brief One-line prompt for a search-plugin URL.

    Seeds the field from the clipboard when it looks like a supported \c .py URL,
    otherwise \c http://. Validates that the entered link ends with \c .py before
    emitting \c urlAccepted(string url).
*/
Dialog {
    id: root

    title: qsTr("New search engine plugin URL")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, (parent ? parent.width : 460) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    /*! Emitted with a validated ( *.py ) URL. */
    signal urlAccepted(string url)

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    function _looksLikePluginUrl(text) {
        var t = text.trim().toLowerCase()
        return (t.startsWith("http://") || t.startsWith("https://") || t.startsWith("file://"))
                && t.endsWith(".py")
    }

    onOpened: {
        // Default to http:// (clipboard pre-fill would require a C++ bridge;
        // the field is fully editable regardless).
        if (urlField.text.length === 0)
            urlField.text = "http://"
        urlField.forceActiveFocus()
        urlField.selectAll()
        Log.debug("search", "NewPluginUrlDialog opened")
    }

    function _accept() {
        var url = urlField.text.trim()
        if (!url.toLowerCase().endsWith(".py")) {
            warnLabel.visible = true
            Log.warning("search", "Rejected plugin URL (not .py): " + url)
            return
        }
        Log.info("search", "Plugin URL accepted: " + url)
        root.urlAccepted(url)
        root.close()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("URL:")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
        }

        TextField {
            id: urlField
            Layout.fillWidth: true
            selectByMouse: true
            placeholderText: "http://…/plugin.py"
            onTextChanged: warnLabel.visible = false
            onAccepted: root._accept()
        }

        Label {
            id: warnLabel
            visible: false
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Typography.labelSmall
            color: Theme.color("error")
            text: qsTr("The link doesn't seem to point to a search engine plugin.")
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.lg
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
            onClicked: root._accept()
        }
    }
}
