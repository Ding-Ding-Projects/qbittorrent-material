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
    LockPasswordDialog — the Material dialog for defining the UI-lock password
    (§14: "L&ock qBittorrent"). It prompts for a new password and a confirmation,
    enforces the legacy minimum length of 3 characters, and only enables the
    accept button when both fields match and are long enough. On accept it emits
    \c accepted(string password); Main.qml forwards that to
    \c AppController.setLockPassword(). The password is never logged.

    \qml
    LockPasswordDialog {
        onAccepted: (password) => AppController.setLockPassword(password)
    }
    \endqml
*/
Popup {
    id: root

    /// Legacy minimum UI-lock password length (mainwindow.cpp: unlockUI()).
    readonly property int minLength: 3

    /// Emitted with the committed (validated) password when the user accepts.
    signal accepted(string password)

    /// Emitted when the user cancels or dismisses the dialog.
    signal rejected()

    // True when both fields agree and satisfy the minimum length.
    readonly property bool _valid:
        (passwordField.text.length >= minLength)
        && (passwordField.text === confirmField.text)

    // Popup.CloseOnEscape calls close() directly, so track the terminal path
    // and notify the caller exactly once for every cancellation route.
    property bool terminalHandled: false

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Spacing.lg

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, (parent ? parent.width : 420) * 0.9)

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        terminalHandled = false
        Log.debug("ui", "LockPasswordDialog opened")
        passwordField.clear()
        confirmField.clear()
        passwordField.forceActiveFocus()
    }

    onClosed: {
        if (!terminalHandled) {
            terminalHandled = true
            Log.debug("ui", "LockPasswordDialog dismissed")
            root.rejected()
        }

        // The popup instance persists after closing; never retain the secret
        // fields until the next time the user opens it.
        passwordField.clear()
        confirmField.clear()
    }

    function _accept() {
        if (terminalHandled || !root._valid) {
            Log.warning("ui", "LockPasswordDialog: invalid password (too short or mismatched)")
            return
        }

        terminalHandled = true
        // Deliberately never log the password value itself.
        Log.info("ui", "LockPasswordDialog accepted; new UI lock password set")
        root.accepted(passwordField.text)
        root.close()
    }

    function _reject() {
        if (terminalHandled)
            return

        terminalHandled = true
        Log.debug("ui", "LockPasswordDialog rejected")
        root.rejected()
        root.close()
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        RowLayout {
            spacing: Spacing.md
            Layout.fillWidth: true

            MDIcon {
                icon: Icons.lock
                size: 28
                color: Theme.color("primary")
                Layout.alignment: Qt.AlignVCenter
            }
            Label {
                text: qsTr("Set UI Lock Password")
                font: Typography.headlineSmall
                color: Theme.color("onSurface")
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Label {
            text: qsTr("Choose a password to lock the qBittorrent interface. You will need it to unlock the window again.")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        LabeledField {
            label: qsTr("Password")
            orientation: Qt.Vertical
            Layout.fillWidth: true

            TextField {
                id: passwordField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Enter a password")
                selectByMouse: true
                Accessible.name: qsTr("Password")
                onAccepted: confirmField.forceActiveFocus()
            }
        }

        LabeledField {
            label: qsTr("Confirm password")
            orientation: Qt.Vertical
            Layout.fillWidth: true

            TextField {
                id: confirmField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Re-enter the password")
                selectByMouse: true
                Accessible.name: qsTr("Confirm password")
                onAccepted: root._accept()
            }
        }

        // Inline validation hint (never reveals the entered text).
        Label {
            id: hintLabel
            Layout.fillWidth: true
            visible: (passwordField.text.length > 0) || (confirmField.text.length > 0)
            wrapMode: Text.WordWrap
            font: Typography.labelSmall
            color: root._valid ? StateColors.success : StateColors.error
            text: {
                if (passwordField.text.length < root.minLength)
                    return qsTr("Password must be at least %1 characters.").arg(root.minLength)
                if (passwordField.text !== confirmField.text)
                    return qsTr("Passwords do not match.")
                return qsTr("Passwords match.")
            }
        }

        DialogButtonBox {
            Layout.fillWidth: true
            spacing: Spacing.sm
            padding: 0
            topPadding: Spacing.sm
            background: null

            Button {
                text: qsTr("Cancel")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: root._reject()
            }

            Button {
                text: qsTr("Set Password")
                highlighted: true
                enabled: root._valid
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: root._accept()
            }
        }
    }
}
