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
    AppMenuBar — the compact application-menu button used by the 64 px shell
    bar. It keeps the complete File / Edit / View / Workspace / Tools / Plugins /
    Help command hierarchy without adding a second row of desktop chrome.
    Every item is still driven by the shared \c Action objects from Main.qml.
*/
ToolButton {
    id: menuBar

    /// The Main.qml root, exposing the shared Action objects + shell state.
    required property var shell

    implicitWidth: 40
    implicitHeight: 40
    display: AbstractButton.IconOnly
    flat: true
    Accessible.name: qsTr("Application menu")

    contentItem: MDIcon {
        icon: Icons.more_vert
        size: 20
        color: Theme.color("onSurfaceVariant")
        anchors.centerIn: parent
    }

    background: Rectangle {
        radius: height / 2
        color: menuBar.down || menuBar.hovered ? Theme.color("surfaceWarm") : "transparent"
        border.width: menuBar.activeFocus ? 2 : 0
        border.color: Theme.color("primary")
    }

    ToolTip.visible: hovered
    ToolTip.text: qsTr("Application menu")
    ToolTip.delay: 500

    onClicked: applicationMenu.popup()

    // A menu item that renders a leading Material Symbols glyph next to its label.
    // (Checkable items keep the default checkmark indicator, so they omit the glyph.)
    component IconMenuItem: MenuItem {
        id: ctl
        property string glyph: ""
        function displayText(value) {
            return String(value).replace(/&&/g, "\uE000")
                .replace(/&/g, "").replace(/\uE000/g, "&")
        }
        implicitHeight: 40
        contentItem: RowLayout {
            spacing: Spacing.md
            MDIcon {
                visible: ctl.glyph.length > 0
                icon: ctl.glyph
                size: 18
                opacity: ctl.enabled ? 1.0 : 0.4
                color: Theme.color("onSurface")
                Layout.leftMargin: Spacing.xs
            }
            Label {
                text: ctl.displayText(ctl.text)
                font: Typography.bodyMedium
                color: Theme.color("onSurface")
                opacity: ctl.enabled ? 1.0 : 0.4
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // The menu is where users go to learn what a command's shortcut is;
            // an item that hides it makes the menu the only route to a command
            // that has a faster one. Read it from the bound action so the label
            // and the registered binding cannot drift apart, and show nothing
            // at all rather than padding the column when there is no binding.
            Label {
                id: shortcutLabel
                text: (ctl.action && ctl.action.shortcut)
                    ? ctl.action.shortcut.toString() : ""
                visible: text.length > 0
                font: Typography.labelMedium
                color: Theme.color("onSurfaceVariant")
                opacity: ctl.enabled ? 1.0 : 0.4
                Layout.rightMargin: Spacing.xs
            }
        }
        Accessible.description: shortcutLabel.text.length > 0
            ? qsTr("Keyboard shortcut %1").arg(shortcutLabel.text) : ""
    }

    Menu {
        id: applicationMenu
        y: menuBar.height
        Material.elevation: 8

    // ---- File ---------------------------------------------------------------
    Menu {
        title: qsTr("&File")
        Material.elevation: 8
        onOpened: Log.debug("ui", "File menu opened")

        IconMenuItem { action: menuBar.shell.actionOpen; glyph: Icons.note_add }
        IconMenuItem { action: menuBar.shell.actionDownloadFromURL; glyph: Icons.add_link }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionExit; glyph: Icons.logout }
    }

    // ---- Edit ---------------------------------------------------------------
    Menu {
        title: qsTr("&Edit")
        Material.elevation: 8
        onOpened: Log.debug("ui", "Edit menu opened")

        IconMenuItem { action: menuBar.shell.actionStart; glyph: Icons.play_arrow }
        IconMenuItem { action: menuBar.shell.actionStop; glyph: Icons.pause }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionDelete; glyph: Icons.deleteIcon }

        MenuSeparator { visible: menuBar.shell.queueingEnabled }
        IconMenuItem {
            action: menuBar.shell.actionTopQueuePos
            glyph: Icons.vertical_align_top
            visible: menuBar.shell.queueingEnabled
            height: visible ? implicitHeight : 0
        }
        IconMenuItem {
            action: menuBar.shell.actionIncreaseQueuePos
            glyph: Icons.arrow_upward
            visible: menuBar.shell.queueingEnabled
            height: visible ? implicitHeight : 0
        }
        IconMenuItem {
            action: menuBar.shell.actionDecreaseQueuePos
            glyph: Icons.arrow_downward
            visible: menuBar.shell.queueingEnabled
            height: visible ? implicitHeight : 0
        }
        IconMenuItem {
            action: menuBar.shell.actionBottomQueuePos
            glyph: Icons.vertical_align_bottom
            visible: menuBar.shell.queueingEnabled
            height: visible ? implicitHeight : 0
        }

        MenuSeparator {}
        IconMenuItem {
            action: menuBar.shell.actionPauseSession
            glyph: Icons.pause_circle
            visible: !menuBar.shell.sessionPaused
            height: visible ? implicitHeight : 0
        }
        IconMenuItem {
            action: menuBar.shell.actionResumeSession
            glyph: Icons.play_circle
            visible: menuBar.shell.sessionPaused
            height: visible ? implicitHeight : 0
        }
    }

    // ---- View ---------------------------------------------------------------
    Menu {
        title: qsTr("&View")
        Material.elevation: 8
        onOpened: Log.debug("ui", "View menu opened")

        MenuItem { action: menuBar.shell.actionTopToolBar }
        MenuItem { action: menuBar.shell.actionShowStatusbar }
        MenuItem { action: menuBar.shell.actionShowFiltersSidebar }
        MenuItem { action: menuBar.shell.actionSpeedInTitleBar }
        MenuSeparator {}
        MenuItem { action: menuBar.shell.actionSearchWidget }
        MenuItem { action: menuBar.shell.actionRSSReader }

        Menu {
            title: qsTr("&Log")
            Material.elevation: 8
            MenuItem { action: menuBar.shell.actionExecutionLogs }
            MenuSeparator {}
            MenuItem { action: menuBar.shell.actionNormalMessages }
            MenuItem { action: menuBar.shell.actionInformationMessages }
            MenuItem { action: menuBar.shell.actionWarningMessages }
            MenuItem { action: menuBar.shell.actionCriticalMessages }
        }

        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionStatistics; glyph: Icons.bar_chart }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionLock; glyph: Icons.lock }
        Menu {
            title: qsTr("Lock Options")
            Material.elevation: 8
            MenuItem { action: menuBar.shell.actionSetLockPassword }
            MenuItem { action: menuBar.shell.actionClearLockPassword }
        }
    }

    // ---- Workspace ----------------------------------------------------------
    Menu {
        title: qsTr("&Workspace")
        Material.elevation: 8
        onOpened: Log.debug("ui", "Workspace menu opened")

        IconMenuItem { action: menuBar.shell.actionWorkspaceNewTab; glyph: Icons.add }
        IconMenuItem { action: menuBar.shell.actionWorkspaceCloseTab; glyph: Icons.close }
        IconMenuItem { action: menuBar.shell.actionWorkspaceCustomizeTab; glyph: Icons.edit }
        IconMenuItem { action: menuBar.shell.actionWorkspaceRenameApp; glyph: Icons.edit }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionWorkspaceSync; glyph: Icons.refresh }
        IconMenuItem { action: menuBar.shell.actionWorkspaceOpenRepository; glyph: Icons.folder_open }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionWorkspaceImport; glyph: Icons.upload }
        IconMenuItem { action: menuBar.shell.actionWorkspaceExport; glyph: Icons.save_alt }
        IconMenuItem { action: menuBar.shell.actionWorkspaceImportRepository; glyph: Icons.upload }
        IconMenuItem { action: menuBar.shell.actionWorkspaceExportRepository; glyph: Icons.save_alt }
    }

    // ---- Tools --------------------------------------------------------------
    Menu {
        title: qsTr("&Tools")
        Material.elevation: 8
        onOpened: Log.debug("ui", "Tools menu opened")

        IconMenuItem { action: menuBar.shell.actionCreateTorrent; glyph: Icons.build }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionManageCookies; glyph: Icons.cookie }
        IconMenuItem { action: menuBar.shell.actionOptions; glyph: Icons.settings }
        MenuSeparator {}

        Menu {
            title: qsTr("On Downloads &Done")
            Material.elevation: 8
            MenuItem { action: menuBar.shell.actionAutoShutdownDisabled }
            MenuItem { action: menuBar.shell.actionAutoExit }
            MenuItem { action: menuBar.shell.actionAutoSuspend }
            MenuItem { action: menuBar.shell.actionAutoHibernate }
            MenuItem { action: menuBar.shell.actionAutoReboot }
            MenuItem { action: menuBar.shell.actionAutoShutdown }
        }
    }

    // ---- Plugins (only when ENABLE_PLUGINS; hidden otherwise) ----------------
    Menu {
        title: qsTr("Plugins")
        Material.elevation: 8
        enabled: menuBar.shell.pluginsMenuVisible
        // NOTE: Qt Quick MenuBar cannot hide a whole Menu at runtime; when the
        // build lacks plugin support we simply disable it. Dynamic per-plugin
        // items are appended here by the plugins engine (TODO(engine)).
        IconMenuItem { action: menuBar.shell.actionManagePlugins; glyph: Icons.extension }
        MenuSeparator {}
    }

    // ---- Help ---------------------------------------------------------------
    Menu {
        title: qsTr("&Help")
        Material.elevation: 8
        onOpened: Log.debug("ui", "Help menu opened")

        IconMenuItem { action: menuBar.shell.actionDocumentation; glyph: Icons.menu_book }
        IconMenuItem { action: menuBar.shell.actionCheckForUpdates; glyph: Icons.system_update }
        MenuSeparator {}
        IconMenuItem { action: menuBar.shell.actionDonateMoney; glyph: Icons.volunteer_activism }
        IconMenuItem { action: menuBar.shell.actionAbout; glyph: Icons.info }
    }
    }
}
