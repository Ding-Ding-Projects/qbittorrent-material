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
    \qmltype ShutdownConfirmDialog
    \brief Material rebuild of the legacy \c ShutdownConfirmDlg.

    Confirms a power action (exit / shutdown / suspend / hibernate / reboot) with
    a 15-second auto-accept countdown. Set \l action before \c open(); on accept
    it emits \l confirmed(). For the Exit action a "Don't show again" checkbox is
    shown and, if ticked, persists to \c ShutdownConfirmDlg/DontConfirmAutoExit.
*/
Dialog {
    id: root

    // ShutdownDialogAction (base/types.h) numeric values.
    readonly property int actionExit: 0
    readonly property int actionShutdown: 1
    readonly property int actionSuspend: 2
    readonly property int actionHibernate: 3
    readonly property int actionReboot: 4

    /*! Which power action to confirm (one of the action* constants). */
    property int action: actionExit

    /*! Emitted when the user (or the countdown) confirms the action. */
    signal confirmed()

    property int _secondsLeft: 15

    function _actionMessage() {
        switch (action) {
        case actionExit: return qsTr("qBittorrent will now exit.")
        case actionShutdown: return qsTr("The computer is going to shutdown.")
        case actionSuspend: return qsTr("The computer is going to enter suspend mode.")
        case actionHibernate: return qsTr("The computer is going to enter hibernation mode.")
        case actionReboot: return qsTr("The computer is going to reboot.")
        }
        return ""
    }

    function _okLabel() {
        switch (action) {
        case actionExit: return qsTr("Exit Now")
        case actionShutdown: return qsTr("Shutdown Now")
        case actionSuspend: return qsTr("Suspend Now")
        case actionHibernate: return qsTr("Hibernate Now")
        case actionReboot: return qsTr("Reboot Now")
        }
        return qsTr("OK")
    }

    title: {
        switch (action) {
        case actionExit: return qsTr("Exit confirmation")
        case actionShutdown: return qsTr("Shutdown confirmation")
        case actionSuspend: return qsTr("Suspend confirmation")
        case actionHibernate: return qsTr("Hibernate confirmation")
        case actionReboot: return qsTr("Reboot confirmation")
        }
        return qsTr("Confirmation")
    }

    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, (parent ? parent.width : 440) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root._secondsLeft = root._secondsLeft - 1
            if (root._secondsLeft <= 0) {
                Log.info("ui", "ShutdownConfirmDialog countdown elapsed; auto-confirming")
                root.accept()
            }
        }
    }

    onOpened: {
        Log.debug("ui", "ShutdownConfirmDialog opened for action " + action)
        _secondsLeft = 15
        neverShowAgain.checked = false
        countdown.start()
    }

    onClosed: countdown.stop()

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
            spacing: Spacing.md
            Layout.fillWidth: true

            MDIcon {
                icon: Icons.warning
                size: 32
                color: Theme.color("warning")
                Layout.alignment: Qt.AlignTop
            }

            Label {
                text: root._actionMessage() + "\n"
                      + qsTr("You can cancel the action within %1 seconds.").arg(root._secondsLeft)
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        CheckBox {
            id: neverShowAgain
            visible: root.action === root.actionExit
            text: qsTr("Don't show again")
            font: Typography.bodyMedium
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Cancel")
            flat: true
            focus: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            text: root._okLabel()
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        countdown.stop()
        if (root.action === root.actionExit && neverShowAgain.checked) {
            Preferences.setValue("ShutdownConfirmDlg/DontConfirmAutoExit", true)
            Log.info("ui", "ShutdownConfirmDialog: user opted out of future exit confirmations")
        }
        Log.info("ui", "ShutdownConfirmDialog confirmed action " + root.action)
        root.confirmed()
    }

    onRejected: {
        countdown.stop()
        Log.debug("ui", "ShutdownConfirmDialog rejected")
    }
}
