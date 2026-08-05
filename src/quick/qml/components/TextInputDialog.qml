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
    \qmltype TextInputDialog
    \brief A one-line prompt (rename, add tag, new category, URL, …).

    Built on \c Popup (elevation 24, dialog radius) so it can deliver the edited
    value directly: \c accepted(string text). Call \c open(); handle
    \c onAccepted(text) / \c onRejected.

    \qml
    TextInputDialog {
        title: qsTr("Rename")
        label: qsTr("New name")
        text: torrent.name
        onAccepted: (t) => TransferController.rename(t)
    }
    \endqml
*/
Popup {
    id: root

    /*! Dialog title. */
    property string title: ""

    /*! Field label. */
    property string label: ""

    /*! Two-way: the initial / edited value. */
    property alias text: field.text

    /*! Field placeholder. */
    property string placeholder: ""

    /*! Optional automation/accessibility object name for the internal field. */
    property string inputObjectName: ""

    /*! Optional QML validator assigned to the field. */
    property var validator: null

    /*! Accept button label. */
    property string acceptText: qsTr("OK")

    /*! Reject button label. */
    property string rejectText: qsTr("Cancel")

    /*! Emitted with the committed text. */
    signal accepted(string text)

    /*! Emitted on cancel / dismiss. */
    signal rejected()

    // Popup.CloseOnEscape calls close() directly, so terminal state is tracked
    // here to deliver one rejection for Escape, Cancel, or external dismissal.
    property bool terminalHandled: false

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Spacing.xl

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) * 0.9)

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outline")
    }

    onOpened: {
        terminalHandled = false
        Log.debug("ui", "TextInputDialog opened: " + title)
        field.forceActiveFocus()
        field.selectAll()
    }

    onClosed: {
        if (terminalHandled)
            return

        terminalHandled = true
        Log.debug("ui", "TextInputDialog dismissed")
        root.rejected()
    }

    function _accept() {
        if (terminalHandled || !field.acceptableInput)
            return

        terminalHandled = true
        Log.info("ui", "TextInputDialog accepted: '" + field.text + "'")
        root.accepted(field.text)
        root.close()
    }

    function _reject() {
        if (terminalHandled)
            return

        terminalHandled = true
        Log.debug("ui", "TextInputDialog rejected")
        root.rejected()
        root.close()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: root.title
            font: Typography.sectionTitle
            color: Theme.color("onSurface")
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Label {
            text: root.label
            visible: root.label.length > 0
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        TextField {
            id: field
            objectName: root.inputObjectName
            Layout.fillWidth: true
            placeholderText: root.placeholder
            selectByMouse: true
            validator: root.validator
            implicitHeight: Spacing.controlHeight
            Accessible.name: root.label.length > 0 ? root.label
                                                   : (root.title.length > 0 ? root.title : qsTr("Text input"))
            Accessible.description: root.placeholder
            onAccepted: root._accept()
        }

        DialogButtonBox {
            Layout.fillWidth: true
            spacing: Spacing.sm
            padding: 0
            topPadding: Spacing.sm
            background: null

            Button {
                text: root.rejectText
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: root._reject()
            }

            Button {
                text: root.acceptText
                highlighted: true
                enabled: field.acceptableInput
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: root._accept()
            }
        }
    }
}
