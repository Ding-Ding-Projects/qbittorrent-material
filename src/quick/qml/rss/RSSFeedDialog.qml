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
    \qmltype RSSFeedDialog
    \brief The "RSS Feed Options" dialog — add a new subscription or edit an
           existing feed's URL and refresh interval.

    The OK button is disabled while the URL is empty. A refresh interval of 0
    means "use the session default" (shown as "Default"). On accept it emits
    \c accepted(url, intervalSeconds, editMode, path).
*/
Dialog {
    id: root

    /*! Destination folder path for a new subscription. */
    property string destFolder: ""

    /*! Whether the dialog is editing an existing feed (vs. adding). */
    property bool editMode: false

    /*! The feed path being edited (edit mode only). */
    property string path: ""

    signal submitted(string url, int intervalSeconds, bool editMode, string path)

    title: qsTr("RSS Feed Options")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, (parent ? parent.width : 480) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    function openForAdd(dest) {
        editMode = false
        destFolder = dest
        path = ""
        urlField.text = RSSController.clipboardURL()
        intervalSpin.value = 0
        Log.info("rss", "RSSFeedDialog opened for add (dest='" + dest + "')")
        open()
    }

    function openForEdit(feedPath) {
        editMode = true
        path = feedPath
        destFolder = ""
        urlField.text = RSSController.feedURL(feedPath)
        intervalSpin.value = RSSController.feedRefreshInterval(feedPath)
        Log.info("rss", "RSSFeedDialog opened for edit (path='" + feedPath + "')")
        open()
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        LabeledField {
            Layout.fillWidth: true
            labelWidth: 120
            label: qsTr("URL:")
            TextField {
                id: urlField
                Layout.fillWidth: true
                selectByMouse: true
                placeholderText: qsTr("https://")
            }
        }

        LabeledField {
            Layout.fillWidth: true
            labelWidth: 120
            label: qsTr("Refresh interval:")
            SpinBox {
                id: intervalSpin
                Layout.fillWidth: true
                from: 0
                to: 2147483647
                editable: true
                textFromValue: (value) => value === 0 ? qsTr("Default") : (value + " " + qsTr("sec"))
                valueFromText: (text) => {
                    const n = parseInt(text)
                    return isNaN(n) ? 0 : n
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
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            text: qsTr("OK")
            highlighted: true
            enabled: urlField.text.trim().length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("rss", "RSSFeedDialog accepted (url='" + urlField.text + "', interval=" + intervalSpin.value + ")")
        root.submitted(urlField.text.trim(), intervalSpin.value, root.editMode, root.path)
    }
    onRejected: Log.debug("rss", "RSSFeedDialog cancelled")
}
