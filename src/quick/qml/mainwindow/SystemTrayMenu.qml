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
import QtQuick.Window
import QtQuick.Controls.Material
import qBittorrent

/*!
    SystemTrayMenu — the Material menu popped at the cursor when the user
    right-clicks the system-tray icon (DesktopIntegration.contextMenuRequested).
    It re-uses the shell's shared Actions and mirrors the legacy desktop-
    integration menu (§5). The whole menu is disabled while the UI is locked.
*/
SearchableMenu {
    id: trayMenu

    searchAccessibleName: qsTr("Search tray actions")

    /// Main.qml root (shell).
    required property var shell

    Material.elevation: 8
    enabled: !(AppController.locked || false)
    onAboutToShow: Log.debug("ui", "System tray menu about to show")

    // Show / Hide the main window.
    MenuItem {
        text: trayMenu.shell.visible && (trayMenu.shell.visibility !== Window.Minimized)
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
              ? qsTr("Hide") : qsTr("Show")
        onTriggered: {
            Log.info("ui", "Tray menu: toggle visibility")
            trayMenu.shell.toggleVisibility()
        }
    }
    MenuSeparator {}

    MenuItem {
        action: trayMenu.shell.actionOpen
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
    }
    MenuItem {
        action: trayMenu.shell.actionDownloadFromURL
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
    }
    MenuSeparator {}

    MenuItem {
        action: trayMenu.shell.actionUseAlternativeSpeedLimits
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
    }
    MenuItem {
        action: trayMenu.shell.actionSetGlobalSpeedLimits
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
    }
    MenuSeparator {}

    MenuItem {
        action: trayMenu.shell.actionResumeSession
        visible: trayMenu.shell.sessionPaused
        height: visible ? implicitHeight : 0
    }
    MenuItem {
        action: trayMenu.shell.actionPauseSession
        visible: !trayMenu.shell.sessionPaused
        height: visible ? implicitHeight : 0
    }
    MenuSeparator {}

    MenuItem {
        action: trayMenu.shell.actionExit
        visible: trayMenu.matches(text)
        height: visible ? implicitHeight : 0
    }
}
