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
    \qmltype DownloadFromURLDialog
    \brief Material rebuild of the legacy \c DownloadFromURLDialog.

    A multi-line editor (one link per line — HTTP, magnet or info-hash) that, on
    open, auto-pastes any clipboard lines that look downloadable. On submit it
    de-duplicates the trimmed non-empty lines (order preserved) and emits
    \l urlsAccepted() for the caller to hand to the add-torrent manager.
    \c Ctrl+Return also submits.
*/
Dialog {
    id: root

    /*! Emitted with the cleaned, de-duplicated list of links. */
    signal urlsAccepted(var urls)

    /*! Disabled by deterministic documentation captures to protect clipboard data. */
    property bool allowClipboardAutopaste: true

    title: qsTr("Download from URLs")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    // Off-screen editor used only to read the clipboard for auto-paste.
    TextEdit {
        id: clipboardReader
        visible: false
    }

    // A line is "downloadable" if it is an HTTP(S) URL, a magnet link, or a
    // v1/v2 info-hash (hex or base32). Mirrors DownloadManager::hasSupportedScheme.
    function isDownloadable(line) {
        const s = line.trim()
        if (s.length === 0)
            return false
        if (/^(https?|ftp|magnet):/i.test(s))
            return true
        if (/^[0-9A-Fa-f]{40}$/.test(s))           // v1 SHA-1 hex
            return true
        if (/^[0-9A-Fa-f]{64}$/.test(s))           // v2 SHA-256 hex
            return true
        if (/^[2-7A-Za-z]{32}$/.test(s))           // v1 SHA-1 base32
            return true
        return false
    }

    function autoPasteClipboard() {
        var clip = ""
        try {
            clipboardReader.clear()
            clipboardReader.selectAll()
            clipboardReader.paste()
            clip = clipboardReader.text
            clipboardReader.clear()
        } catch (e) {
            Log.warning("ui", "DownloadFromURLDialog could not read clipboard: " + e)
            return
        }
        if (!clip || clip.length === 0)
            return

        const kept = clip.split(/\r?\n/).filter(isDownloadable)
        if (kept.length > 0) {
            urlsArea.text = kept.join("\n")
            Log.debug("ui", "DownloadFromURLDialog auto-pasted " + kept.length + " link(s)")
        }
    }

    function submit() {
        const seen = ({})
        const urls = []
        const lines = urlsArea.text.split(/\r?\n/)
        for (var i = 0; i < lines.length; ++i) {
            const u = lines[i].trim()
            if (u.length === 0 || seen[u])
                continue
            seen[u] = true
            urls.push(u)
        }
        if (urls.length === 0) {
            Log.warning("ui", "DownloadFromURLDialog: no URL entered")
            NotificationCenter.notify(qsTr("Please type at least one URL."), "warning")
            return
        }
        Log.info("ui", "DownloadFromURLDialog submitting " + urls.length + " URL(s)")
        root.urlsAccepted(urls)
        root.close()
    }

    onOpened: {
        Log.debug("ui", "DownloadFromURLDialog opened")
        urlsArea.clear()
        if (root.allowClipboardAutopaste)
            autoPasteClipboard()
        urlsArea.forceActiveFocus()
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
        spacing: Spacing.sm

        Label {
            text: qsTr("Add torrent links")
            font: Typography.titleSmall
            color: Theme.color("onSurface")
            Layout.fillWidth: true
        }

        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: 160

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
                    id: urlsArea
                    wrapMode: TextEdit.NoWrap
                    font: Typography.mono
                    color: Theme.color("onSurface")
                    selectByMouse: true

                    Keys.onPressed: (event) => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && (event.modifiers & Qt.ControlModifier)) {
                            root.submit()
                            event.accepted = true
                        }
                    }
                }
            }
        }

        Label {
            text: qsTr("One link per line (HTTP links, Magnet links and info-hashes are supported)")
            font: Typography.labelSmall
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
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
            onClicked: root.reject()
        }

        Button {
            text: qsTr("Download")
            highlighted: true
            enabled: urlsArea.text.trim().length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: root.submit()
        }
    }

    onRejected: Log.debug("ui", "DownloadFromURLDialog rejected")
}
