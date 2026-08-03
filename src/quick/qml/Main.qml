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
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*!
    Main.qml — the single Material \c ApplicationWindow that hosts the whole app.

    It owns:
      - the shared \c Action objects (mirroring the legacy \c mainwindow.ui QActions),
        so the menu bar, toolbar and tray menu all trigger the exact same verbs;
      - the shell view-state (toolbar/statusbar/sidebar visibility, enabled tabs,
        auto-shutdown mode, log message-type toggles) persisted through Preferences;
      - the top-level Material chrome (menu bar / toolbar header / status-bar footer /
        central tabs) plus every shell dialog and the UI-lock overlay.

    All heavy per-feature flows are delegated to the bridge controllers
    (AppController, TransferController, SpeedLimitController, …) and to the
    per-feature screen/dialog QML types referenced here by name (single module).
*/
ApplicationWindow {
    id: root
    objectName: "mainWindow"

    function argumentValue(name, fallbackValue) {
        var prefix = name + "="
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; ++i) {
            if (String(args[i]).startsWith(prefix))
                return String(args[i]).slice(prefix.length)
        }
        return fallbackValue
    }

    readonly property string captureOutput: argumentValue("--capture-ui", "")
    readonly property bool captureMode: captureOutput.length > 0
    readonly property int capturePage: parseInt(argumentValue("--capture-page", "0")) || 0
    readonly property string captureTheme: argumentValue("--capture-theme", "light")
    readonly property string captureStyle: argumentValue("--capture-style", "")
    readonly property string captureDialog: argumentValue("--capture-dialog", "")
    readonly property int captureWidth: parseInt(argumentValue("--capture-width", "1440")) || 1440
    readonly property int captureHeight: parseInt(argumentValue("--capture-height", "900")) || 900
    property int captureOriginalScheme: ThemeManager.colorScheme

    // -- Window basics --------------------------------------------------------
    width: captureMode ? captureWidth : 1280
    height: captureMode ? captureHeight : 800
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    color: Theme.color("background")

    // Size the first normal window to 80% of the screen's usable area.  This is
    // deliberately imperative instead of a width/height binding: users remain
    // free to resize the window without a binding snapping it back afterwards.
    readonly property real preferredScreenCoverage: 0.8
    property rect _lastAvailableScreenGeometry: Qt.rect(0, 0, 0, 0)
    property bool _screenSizingInitialized: false
    property bool _screenSizingScheduled: false
    property bool _initialScreenSizingPending: false

    function availableScreenGeometry() {
        // Window.screen is a QScreen, whose availableGeometry excludes taskbars
        // and other areas reserved by the window manager.
        if (root.screen) {
            var available = root.screen.availableGeometry
            if (available && available.width > 0 && available.height > 0)
                return Qt.rect(available.x, available.y, available.width, available.height)
        }

        // Screen attached properties become valid after the window is shown.
        // Keep conservative defaults for headless and unusual platform plugins.
        var fallbackWidth = Number(Screen.width)
        var fallbackHeight = Number(Screen.height)
        var fallbackX = Number(Screen.virtualX)
        var fallbackY = Number(Screen.virtualY)
        if (!isFinite(fallbackWidth) || fallbackWidth <= 0)
            fallbackWidth = 1280
        if (!isFinite(fallbackHeight) || fallbackHeight <= 0)
            fallbackHeight = 720
        if (!isFinite(fallbackX))
            fallbackX = 0
        if (!isFinite(fallbackY))
            fallbackY = 0
        return Qt.rect(fallbackX, fallbackY, fallbackWidth, fallbackHeight)
    }

    function boundedWindowDimension(value, minimum, available) {
        // If an exceptionally small screen cannot accommodate the minimum, keep
        // the documented minimum-size contract and let the window manager cope.
        return Math.max(minimum, Math.min(Math.round(value), Math.floor(available)))
    }

    function applyScreenGeometry(initialSizing) {
        var available = root.availableScreenGeometry()

        // Maximized/full-screen/minimized windows belong to the window manager.
        // Remember the new screen but leave their restore geometry untouched.
        if (!initialSizing && root.visibility !== Window.Windowed) {
            root._lastAvailableScreenGeometry = available
            return
        }

        var previous = root._lastAvailableScreenGeometry
        var hasPrevious = previous.width > 0 && previous.height > 0
        var targetWidth
        var targetHeight

        if (initialSizing || !hasPrevious) {
            targetWidth = available.width * root.preferredScreenCoverage
            targetHeight = available.height * root.preferredScreenCoverage
        } else {
            // Preserve the user's chosen percentage when crossing screens or
            // when the usable area changes (for example, a relocated taskbar).
            targetWidth = root.width * available.width / previous.width
            targetHeight = root.height * available.height / previous.height
        }

        targetWidth = root.boundedWindowDimension(
                    targetWidth, root.minimumWidth, available.width)
        targetHeight = root.boundedWindowDimension(
                    targetHeight, root.minimumHeight, available.height)

        var targetX
        var targetY
        if (initialSizing) {
            targetX = available.x + (available.width - targetWidth) / 2
            targetY = available.y + (available.height - targetHeight) / 2
        } else {
            // Keep the current visual center during a screen transition, then
            // clamp the full window into the new screen's usable bounds.
            targetX = root.x + (root.width - targetWidth) / 2
            targetY = root.y + (root.height - targetHeight) / 2
        }

        var maximumX = available.x + Math.max(0, available.width - targetWidth)
        var maximumY = available.y + Math.max(0, available.height - targetHeight)

        root.width = targetWidth
        root.height = targetHeight
        root.x = Math.round(Math.max(available.x, Math.min(targetX, maximumX)))
        root.y = Math.round(Math.max(available.y, Math.min(targetY, maximumY)))
        root._lastAvailableScreenGeometry = available
        root._screenSizingInitialized = true
    }

    function scheduleScreenGeometryUpdate(initialSizing) {
        if (initialSizing)
            root._initialScreenSizingPending = true
        if (root._screenSizingScheduled)
            return

        root._screenSizingScheduled = true
        Qt.callLater(function() {
            root._screenSizingScheduled = false
            var initialize = root._initialScreenSizingPending
                             || !root._screenSizingInitialized
            root._initialScreenSizingPending = false
            root.applyScreenGeometry(initialize)
        })
    }

    onScreenChanged: root.scheduleScreenGeometryUpdate(false)

    Connections {
        target: root.screen
        ignoreUnknownSignals: true

        function onAvailableGeometryChanged() {
            root.scheduleScreenGeometryUpdate(false)
        }
    }

    // -- Material palette wiring (done once, at the root; §4.3) ----------------
    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.color("primary")
    Material.primary: Theme.color("primary")
    Material.background: Theme.color("background")
    Material.foreground: Theme.color("onSurface")

    // -- Shell view state (initialized from Preferences in onCompleted) --------
    property bool toolbarVisible: true
    property bool statusbarVisible: true
    property bool sidebarVisible: true
    property bool speedInTitleBar: false
    property bool searchTabEnabled: false
    property bool rssTabEnabled: false
    property bool executionLogEnabled: false
    property bool logNormalEnabled: true
    property bool logInfoEnabled: true
    property bool logWarningEnabled: true
    property bool logCriticalEnabled: true
    property bool pluginsMenuVisible: false          // ENABLE_PLUGINS build flag; hidden by default

    // Auto-shutdown-on-completion: 0 nothing, 1 exit qBt, 2 suspend, 3 hibernate,
    // 4 reboot, 5 shutdown.
    property int autoShutdownMode: 0

    // -- Live session state (bound from the engine bridge) --------------------
    readonly property bool sessionPaused: Session.paused || false
    readonly property bool queueingEnabled: (Session.queueingEnabled === undefined) ? true : Session.queueingEnabled
    readonly property bool altSpeedEnabled: SpeedLimitController.alternativeLimitsEnabled || false
    readonly property int torrentCount: Session.torrentCount || 0
    readonly property bool trayAvailable: DesktopIntegration.available || false
    readonly property int currentTabIndex: centralTabs.currentIndex

    // TextInput and TextEdit expose this common editing surface; TextField and
    // TextArea inherit it. Reserve their standard editing sequences for the
    // focused editor while leaving intentional app commands (Open, Save, Find,
    // command palette, tab navigation, etc.) available.
    function isTextEditor(item) {
        return item !== null && item !== undefined
            && item.cursorPosition !== undefined
            && item.selectionStart !== undefined
            && item.selectionEnd !== undefined
            && item.canPaste !== undefined
            && item.canUndo !== undefined
    }
    readonly property bool textEditorHasFocus: root.isTextEditor(root.activeFocusItem)

    // -- Window title (§14) ---------------------------------------------------
    readonly property string appVersion: Qt.application.version.length > 0 ? Qt.application.version : "5.x"
    title: {
        // Qt's platform integration appends applicationDisplayName to an
        // explicit title. Keep the user-selected name in that single native
        // source so renamed apps never render as "Name - Name".
        var base = root.appVersion
        if (root.speedInTitleBar) {
            base = qsTr("[D: %1, U: %2] %3")
                .arg(statusBar.formatSpeed(Session.downloadRate || 0))
                .arg(statusBar.formatSpeed(Session.uploadRate || 0))
                .arg(base)
        }
        if (root.sessionPaused)
            base = qsTr("[PAUSED] %1").arg(base)
        return base
    }

    // =========================================================================
    //  Shared Actions (mirror mainwindow.ui QActions; used by menu + toolbar + tray)
    // =========================================================================

    // --- File ---
    property alias actionOpen: actionOpen
    Action {
        id: actionOpen
        text: qsTr("&Add Torrent File...")
        shortcut: StandardKey.Open
        onTriggered: root.addTorrentFile()
    }
    property alias actionDownloadFromURL: actionDownloadFromURL
    Action {
        id: actionDownloadFromURL
        text: qsTr("Add Torrent &Link...")
        shortcut: "Ctrl+Shift+O"
        onTriggered: root.addTorrentLink()
    }
    property alias actionExit: actionExit
    Action {
        id: actionExit
        text: qsTr("E&xit")
        shortcut: "Ctrl+Q"
        onTriggered: root.exitApp()
    }

    // --- Edit ---
    property alias actionUndo: actionUndo
    Action {
        id: actionUndo
        text: JournalController.canUndo
            ? qsTr("&Undo %1").arg(JournalController.lastActionDescription)
            : qsTr("&Undo")
        shortcut: StandardKey.Undo
        // Never steal Ctrl+Z from a focused text editor (e.g. the Workspace notes).
        enabled: JournalController.canUndo && !JournalController.busy
                 && !root.textEditorHasFocus
        onTriggered: {
            Log.info("ui", "Action: Undo last journaled change")
            JournalController.undoLast()
        }
    }
    property alias actionShowHistory: actionShowHistory
    Action {
        id: actionShowHistory
        text: qsTr("&History")
        shortcut: "Ctrl+H"
        onTriggered: root.togglePanel("history")
    }
    property alias actionStart: actionStart
    Action {
        id: actionStart
        text: qsTr("Sta&rt")
        shortcut: "Ctrl+S"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.startSelected()
    }
    property alias actionStop: actionStop
    Action {
        id: actionStop
        text: qsTr("Sto&p")
        shortcut: "Ctrl+P"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.stopSelected()
    }
    property alias actionDelete: actionDelete
    Action {
        id: actionDelete
        text: qsTr("&Remove")
        // Keep the action clickable, but yield the bare Delete key to editors.
        shortcut: root.textEditorHasFocus ? "" : StandardKey.Delete
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.removeSelected()
    }
    property alias actionTopQueuePos: actionTopQueuePos
    Action {
        id: actionTopQueuePos
        text: qsTr("Top of Queue")
        shortcut: "Ctrl+Shift++"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.queueTop()
    }
    property alias actionIncreaseQueuePos: actionIncreaseQueuePos
    Action {
        id: actionIncreaseQueuePos
        text: qsTr("Move Up Queue")
        shortcut: "Ctrl++"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.queueUp()
    }
    property alias actionDecreaseQueuePos: actionDecreaseQueuePos
    Action {
        id: actionDecreaseQueuePos
        text: qsTr("Move Down Queue")
        shortcut: "Ctrl+-"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.queueDown()
    }
    property alias actionBottomQueuePos: actionBottomQueuePos
    Action {
        id: actionBottomQueuePos
        text: qsTr("Bottom of Queue")
        shortcut: "Ctrl+Shift+-"
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.queueBottom()
    }
    property alias actionPauseSession: actionPauseSession
    Action {
        id: actionPauseSession
        text: qsTr("Pau&se Session")
        shortcut: "Ctrl+Alt+P"
        onTriggered: root.pauseSession()
    }
    property alias actionResumeSession: actionResumeSession
    Action {
        id: actionResumeSession
        text: qsTr("R&esume Session")
        shortcut: "Ctrl+Shift+S"
        onTriggered: root.resumeSession()
    }

    // --- Workspace ---
    property alias actionWorkspaceNewTab: actionWorkspaceNewTab
    Action {
        id: actionWorkspaceNewTab
        text: qsTr("&New Workspace Tab")
        shortcut: "Ctrl+T"
        enabled: WorkspaceManager.writable
        onTriggered: centralTabs.newWorkspaceTab()
    }
    property alias actionWorkspaceCloseTab: actionWorkspaceCloseTab
    Action {
        id: actionWorkspaceCloseTab
        text: qsTr("&Close Workspace Tab")
        shortcut: "Ctrl+W"
        enabled: WorkspaceManager.writable && root.currentTabIndex === 4 && WorkspaceManager.count > 0
        onTriggered: centralTabs.closeWorkspaceTab()
    }
    property alias actionWorkspaceCustomizeTab: actionWorkspaceCustomizeTab
    Action {
        id: actionWorkspaceCustomizeTab
        text: qsTr("Tab Name && &Appearance…")
        enabled: WorkspaceManager.writable && WorkspaceManager.count > 0
        onTriggered: centralTabs.customizeWorkspaceTab()
    }
    property alias actionWorkspaceRenameApp: actionWorkspaceRenameApp
    Action {
        id: actionWorkspaceRenameApp
        text: qsTr("&Rename Application…")
        enabled: WorkspaceManager.writable
        onTriggered: centralTabs.renameWorkspaceApplication()
    }
    property alias actionWorkspaceSync: actionWorkspaceSync
    Action {
        id: actionWorkspaceSync
        text: qsTr("&Save && Commit Workspace")
        shortcut: "Ctrl+S"
        enabled: WorkspaceManager.writable && root.currentTabIndex === 4
        onTriggered: centralTabs.syncWorkspace()
    }
    property alias actionWorkspaceImport: actionWorkspaceImport
    Action {
        id: actionWorkspaceImport
        text: qsTr("Import Workspace &JSON…")
        enabled: WorkspaceManager.writable
        onTriggered: centralTabs.importWorkspace()
    }
    property alias actionWorkspaceExport: actionWorkspaceExport
    Action {
        id: actionWorkspaceExport
        text: qsTr("Export Workspace J&SON…")
        onTriggered: centralTabs.exportWorkspace()
    }
    property alias actionWorkspaceImportRepository: actionWorkspaceImportRepository
    Action {
        id: actionWorkspaceImportRepository
        text: qsTr("Import Complete Git &Repository…")
        enabled: WorkspaceManager.writable
        onTriggered: centralTabs.importWorkspaceRepository()
    }
    property alias actionWorkspaceExportRepository: actionWorkspaceExportRepository
    Action {
        id: actionWorkspaceExportRepository
        text: qsTr("Export Complete &Git Repository…")
        enabled: WorkspaceManager.writable
        onTriggered: centralTabs.exportWorkspaceRepository()
    }
    property alias actionWorkspaceOpenRepository: actionWorkspaceOpenRepository
    Action {
        id: actionWorkspaceOpenRepository
        text: qsTr("Open &Managed Repository")
        onTriggered: centralTabs.openWorkspaceRepository()
    }

    // --- View (checkable) ---
    property alias actionTopToolBar: actionTopToolBar
    Action {
        id: actionTopToolBar
        text: qsTr("&Top Toolbar")
        checkable: true
        checked: root.toolbarVisible
        onTriggered: root.setToolbarVisible(checked)
    }
    property alias actionShowStatusbar: actionShowStatusbar
    Action {
        id: actionShowStatusbar
        text: qsTr("Status &Bar")
        checkable: true
        checked: root.statusbarVisible
        onTriggered: root.setStatusbarVisible(checked)
    }
    property alias actionShowFiltersSidebar: actionShowFiltersSidebar
    Action {
        id: actionShowFiltersSidebar
        text: qsTr("Filters Sidebar")
        checkable: true
        checked: root.sidebarVisible
        onTriggered: root.setSidebarVisible(checked)
    }
    property alias actionSpeedInTitleBar: actionSpeedInTitleBar
    Action {
        id: actionSpeedInTitleBar
        text: qsTr("S&peed in Title Bar")
        checkable: true
        checked: root.speedInTitleBar
        onTriggered: root.setSpeedInTitleBar(checked)
    }
    property alias actionSearchWidget: actionSearchWidget
    Action {
        id: actionSearchWidget
        text: qsTr("Search &Engine")
        checkable: true
        checked: root.searchTabEnabled
        onTriggered: root.setSearchTabEnabled(checked)
    }
    property alias actionRSSReader: actionRSSReader
    Action {
        id: actionRSSReader
        text: qsTr("&RSS Reader")
        checkable: true
        checked: root.rssTabEnabled
        onTriggered: root.setRSSTabEnabled(checked)
    }
    property alias actionExecutionLogs: actionExecutionLogs
    Action {
        id: actionExecutionLogs
        text: qsTr("Show")
        checkable: true
        checked: root.executionLogEnabled
        onTriggered: root.setExecutionLogEnabled(checked)
    }
    property alias actionNormalMessages: actionNormalMessages
    Action {
        id: actionNormalMessages
        text: qsTr("Normal Messages")
        checkable: true
        checked: root.logNormalEnabled
        enabled: root.executionLogEnabled
        onTriggered: root.setLogTypeEnabled("normal", checked)
    }
    property alias actionInformationMessages: actionInformationMessages
    Action {
        id: actionInformationMessages
        text: qsTr("Information Messages")
        checkable: true
        checked: root.logInfoEnabled
        enabled: root.executionLogEnabled
        onTriggered: root.setLogTypeEnabled("info", checked)
    }
    property alias actionWarningMessages: actionWarningMessages
    Action {
        id: actionWarningMessages
        text: qsTr("Warning Messages")
        checkable: true
        checked: root.logWarningEnabled
        enabled: root.executionLogEnabled
        onTriggered: root.setLogTypeEnabled("warning", checked)
    }
    property alias actionCriticalMessages: actionCriticalMessages
    Action {
        id: actionCriticalMessages
        text: qsTr("Critical Messages")
        checkable: true
        checked: root.logCriticalEnabled
        enabled: root.executionLogEnabled
        onTriggered: root.setLogTypeEnabled("critical", checked)
    }
    property alias actionStatistics: actionStatistics
    Action {
        id: actionStatistics
        text: qsTr("&Statistics")
        shortcut: "Ctrl+I"
        onTriggered: root.showStatistics()
    }
    property alias actionLock: actionLock
    Action {
        id: actionLock
        text: qsTr("L&ock qBittorrent")
        shortcut: "Ctrl+L"
        onTriggered: root.lockUI()
    }
    property alias actionSetLockPassword: actionSetLockPassword
    Action {
        id: actionSetLockPassword
        text: qsTr("&Set Password")
        onTriggered: root.defineLockPassword()
    }
    property alias actionClearLockPassword: actionClearLockPassword
    Action {
        id: actionClearLockPassword
        text: qsTr("&Clear Password")
        enabled: AppController.lockPasswordSet || false
        onTriggered: root.clearLockPassword()
    }

    // --- Tools ---
    property alias actionCreateTorrent: actionCreateTorrent
    Action {
        id: actionCreateTorrent
        text: qsTr("Torrent &Creator")
        shortcut: StandardKey.New
        onTriggered: root.createTorrent()
    }
    property alias actionManageCookies: actionManageCookies
    Action {
        id: actionManageCookies
        text: qsTr("Manage Cookies...")
        onTriggered: root.manageCookies()
    }
    property alias actionOptions: actionOptions
    Action {
        id: actionOptions
        // "Preferences" on Unix; kept as "Options" for cross-platform consistency here.
        text: qsTr("&Options...")
        shortcut: "Alt+O"
        onTriggered: root.showOptions()
    }
    // Auto-shutdown exclusive group
    property alias actionAutoShutdownDisabled: actionAutoShutdownDisabled
    Action {
        id: actionAutoShutdownDisabled
        text: qsTr("&Do nothing")
        checkable: true
        checked: root.autoShutdownMode === 0
        onTriggered: root.setAutoShutdownMode(0)
    }
    property alias actionAutoExit: actionAutoExit
    Action {
        id: actionAutoExit
        text: qsTr("&Exit qBittorrent")
        checkable: true
        checked: root.autoShutdownMode === 1
        onTriggered: root.setAutoShutdownMode(1)
    }
    property alias actionAutoSuspend: actionAutoSuspend
    Action {
        id: actionAutoSuspend
        text: qsTr("&Suspend System")
        checkable: true
        checked: root.autoShutdownMode === 2
        onTriggered: root.setAutoShutdownMode(2)
    }
    property alias actionAutoHibernate: actionAutoHibernate
    Action {
        id: actionAutoHibernate
        text: qsTr("&Hibernate System")
        checkable: true
        checked: root.autoShutdownMode === 3
        onTriggered: root.setAutoShutdownMode(3)
    }
    property alias actionAutoReboot: actionAutoReboot
    Action {
        id: actionAutoReboot
        text: qsTr("&Reboot System")
        checkable: true
        checked: root.autoShutdownMode === 4
        onTriggered: root.setAutoShutdownMode(4)
    }
    property alias actionAutoShutdown: actionAutoShutdown
    Action {
        id: actionAutoShutdown
        text: qsTr("Sh&utdown System")
        checkable: true
        checked: root.autoShutdownMode === 5
        onTriggered: root.setAutoShutdownMode(5)
    }

    // --- Plugins ---
    property alias actionManagePlugins: actionManagePlugins
    Action {
        id: actionManagePlugins
        text: qsTr("Manage Plugins...")
        onTriggered: root.managePlugins()
    }

    // --- Help ---
    property alias actionDocumentation: actionDocumentation
    Action {
        id: actionDocumentation
        text: qsTr("&Documentation")
        shortcut: StandardKey.HelpContents
        onTriggered: root.openDocumentation()
    }
    property alias actionCheckForUpdates: actionCheckForUpdates
    Action {
        id: actionCheckForUpdates
        text: qsTr("Check for Updates")
        onTriggered: root.checkForUpdates()
    }
    property alias actionDonateMoney: actionDonateMoney
    Action {
        id: actionDonateMoney
        text: qsTr("Do&nate!")
        onTriggered: root.donate()
    }
    property alias actionAbout: actionAbout
    Action {
        id: actionAbout
        text: qsTr("&About")
        onTriggered: root.showAbout()
    }

    // --- Actions not on any menu (toolbar / tray) ---
    property alias actionSetGlobalSpeedLimits: actionSetGlobalSpeedLimits
    Action {
        id: actionSetGlobalSpeedLimits
        text: qsTr("Set Global Speed Limits...")
        onTriggered: root.showGlobalSpeedLimits()
    }
    property alias actionUseAlternativeSpeedLimits: actionUseAlternativeSpeedLimits
    Action {
        id: actionUseAlternativeSpeedLimits
        text: qsTr("Alternative Speed Limits")
        checkable: true
        checked: root.altSpeedEnabled
        onTriggered: root.toggleAltSpeed()
    }
    property alias actionOpenDestinationFolder: actionOpenDestinationFolder
    Action {
        id: actionOpenDestinationFolder
        text: qsTr("Open Destination Folder")
        enabled: root.currentTabIndex === 0 && TransferController.selectionCount > 0
        onTriggered: root.openDestinationFolder()
    }

    // =========================================================================
    //  Chrome: compact application bar / persistent nav / status footer
    // =========================================================================

    // The redesigned 64px header (Material Redesign). The legacy AppToolBar
    // still ships but is superseded by AppHeader; its verbs live on in the
    // header's overflow AppMenuBar.
    header: AppHeader {
        id: appHeader
        shell: root
        visible: root.toolbarVisible
        currentTab: root.currentTabIndex
        filterProxy: centralTabs.proxy
        rssUnread: centralTabs.rssUnread
        unreadNotifications: NotificationCenter.unreadCount
        activePanel: root.activePanel
        onNavRequested: (index) => root.switchToTab(index)
        onPanelRequested: (panel) => root.togglePanel(panel)
        onRegexBuilderRequested: root.togglePanel("regex")
    }

    footer: AppStatusBar {
        id: statusBar
        shell: root
        visible: root.statusbarVisible
    }

    CentralTabs {
        id: centralTabs
        anchors.fill: parent
        shell: root
        transfersCount: root.torrentCount
        searchEnabled: root.searchTabEnabled
        rssEnabled: root.rssTabEnabled
        logEnabled: root.executionLogEnabled
        onFocusFilterRequested: appHeader.focusFilter()
    }

    // -- Redesigned right-anchored sheets (non-blocking) ----------------------
    property string activePanel: ""   // "", "history", "settings", "notifications", "regex", "add"

    function togglePanel(panel) {
        root.activePanel = (root.activePanel === panel) ? "" : panel
    }
    function closePanel() { root.activePanel = "" }

    HistorySheet {
        id: historySheet
        parent: centralTabs
        open: root.activePanel === "history"
        onCloseRequested: root.closePanel()
        onNotifyRequested: (m) => snackbar.show(m)
        onRestoreConfirm: (commitId, laterCount) => {
            restoreConfirmDialog.commitId = commitId
            restoreConfirmDialog.laterCount = laterCount
            restoreConfirmDialog.open()
        }
    }

    SettingsSheet {
        id: settingsSheet
        parent: centralTabs
        open: root.activePanel === "settings"
        onCloseRequested: root.closePanel()
        onOpenHistoryRequested: root.activePanel = "history"
        onOpenFullOptionsRequested: { root.closePanel(); root.showOptions() }
    }

    NotificationsSheet {
        id: notificationsSheet
        parent: centralTabs
        open: root.activePanel === "notifications"
        onCloseRequested: root.closePanel()
        onOpenHistoryRequested: root.activePanel = "history"
    }

    RegexBuilderSheet {
        id: regexBuilderSheet
        parent: centralTabs
        open: root.activePanel === "regex"
        filterProxy: centralTabs.proxy
        onCloseRequested: root.closePanel()
    }

    ConfirmDialog {
        id: restoreConfirmDialog
        parent: Overlay.overlay
        property string commitId: ""
        property int laterCount: 0
        title: qsTr("Restore to this point")
        text: laterCount === 1
            ? qsTr("This will revert 1 later action, recreating or removing torrents as needed.")
            : qsTr("This will revert %1 later actions, recreating or removing torrents as needed.").arg(laterCount)
        acceptText: qsTr("Restore")
        destructive: true
        onAccepted: JournalController.restoreTo(restoreConfirmDialog.commitId)
    }

    // =========================================================================
    //  Overlays & dialogs
    // =========================================================================

    Snackbar {
        id: snackbar
        parent: root.contentItem
    }

    // Drag-and-drop adding. Dropping a .torrent file or a magnet link on the
    // window is the way most people add torrents, and without this the drop is
    // a complete no-op — no dialog, no error, not even a log line.
    DropArea {
        id: torrentDropArea
        parent: root.contentItem
        anchors.fill: parent
        // Sit above page content but below the lock screen and modal dialogs.
        z: 50
        enabled: !AppController.locked

        keys: ["text/uri-list", "text/plain"]

        function _addableFromDrop(drop) {
            var sources = []
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; ++i) {
                    var u = drop.urls[i].toString()
                    // Accept .torrent files and magnet links; ignore anything
                    // else so dropping a folder or an image does nothing odd.
                    if (u.toLowerCase().startsWith("magnet:")
                            || u.toLowerCase().endsWith(".torrent"))
                        sources.push(u)
                }
            }
            if ((sources.length === 0) && drop.hasText) {
                var lines = drop.text.split(/[\r\n]+/)
                for (var j = 0; j < lines.length; ++j) {
                    var line = lines[j].trim()
                    if (line.length > 0)
                        sources.push(line)
                }
            }
            return sources
        }

        onEntered: (drag) => {
            drag.accepted = (drag.hasUrls || drag.hasText)
        }

        onDropped: (drop) => {
            var sources = torrentDropArea._addableFromDrop(drop)
            if (sources.length === 0) {
                Log.info("ui", "Drop ignored: nothing addable")
                NotificationCenter.notify(
                    qsTr("Drop a .torrent file or a magnet link to add it."),
                    "warning")
                drop.accepted = false
                return
            }

            Log.info("ui", "Drop accepted with " + sources.length + " source(s)")
            for (var i = 0; i < sources.length; ++i)
                AppController.addTorrentFromSource(sources[i])
            drop.accepted = true
        }

        // Visible affordance so a drag reads as "this window will take it".
        Rectangle {
            anchors.fill: parent
            visible: torrentDropArea.containsDrag
            color: Theme.color("primaryContainer")
            opacity: 0.28
            border.width: 2
            border.color: Theme.color("primary")
            radius: Spacing.radiusPanel

            Label {
                anchors.centerIn: parent
                text: qsTr("Drop to add torrents")
                font: Typography.titleLarge
                color: Theme.color("onSurface")
            }
        }
    }

    DimSumSurprise {
        parent: root.contentItem
    }

    // UI lock overlay — fills the whole window when locked.
    UILockScreen {
        id: lockScreen
        parent: Overlay.overlay
        anchors.fill: parent
        z: 10000
        visible: AppController.locked
    }

    ExitConfirmationDialog {
        id: exitDialog
        parent: Overlay.overlay
        onConfirmed: (always) => {
            Log.info("ui", "Exit confirmed (alwaysYes=" + always + ")")
            if (always)
                Preferences.setConfirmOnExit(false)
            AppController.exit(true)
        }
        onRejected: Log.debug("ui", "Exit cancelled by user")
    }

    LockPasswordDialog {
        id: lockPasswordDialog
        parent: Overlay.overlay
        onAccepted: (password) => {
            Log.info("ui", "UI lock password set")
            AppController.setLockPassword(password)
        }
    }

    SystemTrayMenu {
        id: trayMenu
        shell: root
    }

    // Shell dialogs (per-feature types, referenced by name in the single module).
    OptionsDialog { id: optionsDialog; parent: Overlay.overlay }
    CommandPalette {
        id: commandPalette
        commands: [
            { id: "tab.transfers", title: qsTr("Transfers"), group: qsTr("Navigate"), destination: qsTr("Main view · Transfers"), keywords: "torrents downloads" },
            { id: "tab.search", title: qsTr("Search"), group: qsTr("Navigate"), destination: qsTr("Main view · Search"), keywords: "plugins results" },
            { id: "tab.rss", title: qsTr("RSS"), group: qsTr("Navigate"), destination: qsTr("Main view · RSS"), keywords: "feeds rules" },
            { id: "tab.log", title: qsTr("Execution log"), group: qsTr("Navigate"), destination: qsTr("Main view · Log"), keywords: "messages blocked IP" },
            { id: "tab.workspace", title: qsTr("Workspace"), group: qsTr("Navigate"), destination: qsTr("Main view · Workspace"), keywords: "notes tabs" },
            { id: "action.addFile", title: qsTr("Add torrent file"), group: qsTr("Action"), destination: qsTr("File picker"), keywords: "open torrent" },
            { id: "action.addLink", title: qsTr("Add torrent link"), group: qsTr("Action"), destination: qsTr("Add link dialog"), keywords: "magnet URL clipboard" },
            { id: "action.history", title: qsTr("History"), group: qsTr("Action"), destination: qsTr("History panel"), keywords: "undo journal" },
            { id: "action.statistics", title: qsTr("Statistics"), group: qsTr("Action"), destination: qsTr("Statistics dialog"), keywords: "session totals" },
            { id: "action.about", title: qsTr("About"), group: qsTr("Action"), destination: qsTr("About dialog"), keywords: "version changelog" },
            { id: "options.0", title: qsTr("Options: Behavior"), group: qsTr("Settings"), destination: qsTr("Options · Behavior"), keywords: "language theme funny tray startup default apps" },
            { id: "options.1", title: qsTr("Options: Downloads"), group: qsTr("Settings"), destination: qsTr("Options · Downloads"), keywords: "save path incomplete watched folders" },
            { id: "options.2", title: qsTr("Options: Connection"), group: qsTr("Settings"), destination: qsTr("Options · Connection"), keywords: "port proxy UPnP IP filter" },
            { id: "options.3", title: qsTr("Options: Speed"), group: qsTr("Settings"), destination: qsTr("Options · Speed"), keywords: "limits scheduler bandwidth" },
            { id: "options.4", title: qsTr("Options: BitTorrent"), group: qsTr("Settings"), destination: qsTr("Options · BitTorrent"), keywords: "privacy encryption queue seeding DHT PeX" },
            { id: "options.5", title: qsTr("Options: Search"), group: qsTr("Settings"), destination: qsTr("Options · Search"), keywords: "plugins Python" },
            { id: "options.6", title: qsTr("Options: RSS"), group: qsTr("Settings"), destination: qsTr("Options · RSS"), keywords: "feeds refresh rules" },
            { id: "options.7", title: qsTr("Options: Web UI"), group: qsTr("Settings"), destination: qsTr("Options · Web UI"), keywords: "API key HTTPS authentication" },
            { id: "options.8", title: qsTr("Options: Advanced"), group: qsTr("Settings"), destination: qsTr("Options · Advanced"), keywords: "libtorrent cache network disk" }
        ]
        onCommandInvoked: (commandId) => root.invokePaletteCommand(commandId)
    }
    StatisticsDialog { id: statisticsDialog; parent: Overlay.overlay }
    TorrentCreatorDialog { id: torrentCreatorDialog; parent: Overlay.overlay }
    SpeedLimitDialog { id: speedLimitDialog; parent: Overlay.overlay }
    AboutDialog { id: aboutDialog; parent: Overlay.overlay }
    CookiesDialog { id: cookiesDialog; parent: Overlay.overlay }
    AddNewTorrentDialog { id: addNewTorrentDialog; parent: Overlay.overlay }
    DownloadFromURLDialog {
        id: downloadFromURLDialog
        parent: Overlay.overlay
        allowClipboardAutopaste: !root.captureMode
        onUrlsAccepted: (urls) => {
            Log.info("ui", "Adding " + urls.length + " URL(s) from link dialog")
            for (var i = 0; i < urls.length; ++i)
                AppController.addTorrentFromSource(urls[i])
        }
    }
    DeletionConfirmationDialog {
        id: deletionDialog
        parent: Overlay.overlay
        onConfirmed: (deleteFiles) => {
            Log.info("ui", "Delete confirmed (deleteFiles=" + deleteFiles + ")")
            TransferController.deleteSelected(deleteFiles)
        }
    }

    // Native OS file picker for "Add Torrent File..." (allowed OS dialog).
    Platform.FileDialog {
        id: openTorrentDialog
        title: qsTr("Add Torrent File")
        fileMode: Platform.FileDialog.OpenFiles
        nameFilters: [ qsTr("Torrent files (*.torrent)"), qsTr("All files (*)") ]
        onAccepted: {
            Log.info("ui", "Selected " + files.length + " torrent file(s)")
            for (var i = 0; i < files.length; ++i)
                AppController.addTorrentFromSource(files[i].toString())
        }
        onRejected: Log.debug("ui", "Add-torrent file dialog cancelled")
    }

    // =========================================================================
    //  Global keyboard shortcuts that aren't tied to a menu item (§6)
    // =========================================================================
    Shortcut { sequences: ["Alt+1"]; onActivated: root.switchToTab(0) }
    Shortcut { sequences: ["Alt+2"]; onActivated: root.switchToTab(1) }
    Shortcut { sequences: ["Alt+3"]; onActivated: root.switchToTab(2) }
    Shortcut { sequences: ["Alt+4"]; onActivated: root.switchToTab(3) }
    Shortcut { sequences: ["Alt+5"]; onActivated: root.switchToTab(4) }
    Shortcut { sequences: ["Ctrl+Shift+P"]; onActivated: commandPalette.openPalette() }
    Shortcut { sequences: ["Escape"]; enabled: root.activePanel.length > 0; onActivated: root.closePanel() }
    // Bulk selection on the transfer list. Both are gated on a focused text
    // editor so Ctrl+A still selects text while typing in a filter field.
    Shortcut {
        sequences: [StandardKey.SelectAll]
        enabled: root.currentTabIndex === 0 && !root.textEditorHasFocus
        onActivated: {
            Log.info("ui", "Select all filtered transfers")
            centralTabs.selectAllTransfers()
        }
    }
    Shortcut {
        sequences: ["Ctrl+Shift+I"]
        enabled: root.currentTabIndex === 0 && !root.textEditorHasFocus
        onActivated: {
            Log.info("ui", "Invert transfer selection")
            centralTabs.invertTransferSelection()
        }
    }
    Shortcut {
        sequences: [StandardKey.Find, "Ctrl+E"]
        enabled: root.currentTabIndex === 0
        onActivated: {
            Log.debug("ui", "Toggle focus between filter line edits")
            centralTabs.toggleFilterFocus()
        }
    }
    Shortcut {
        sequences: [StandardKey.Paste]
        enabled: root.currentTabIndex === 0 && !root.textEditorHasFocus
        onActivated: {
            Log.info("ui", "Paste-add from clipboard")
            AppController.pasteAdd()
        }
    }

    // =========================================================================
    //  Engine / controller wiring
    // =========================================================================
    Connections {
        target: AppController
        function onConfirmExitRequested() {
            Log.debug("ui", "AppController requested exit confirmation")
            exitDialog.openForExit()
        }
        function onAddTorrentRequested(source) {
            Log.info("ui", "Add-torrent requested from source")
            // Route to the add manager, which presents the Add dialog (or adds
            // silently per prefs). Calling AppController.addTorrentFromSource
            // here would re-emit this same signal — an infinite loop.
            GuiAddTorrentManager.addTorrent(source)
        }
        function onUpdateCheckFinished(available, latestVersion) {
            Log.info("ui", "Update check finished; available=" + available)
            if (available)
                snackbar.show(qsTr("A new version is available: %1").arg(latestVersion))
            else
                snackbar.show(qsTr("qBittorrent is up to date."))
        }
        function onNotify(message) {
            snackbar.show(message)
        }
        function onShowMainWindowRequested() { root.showAndRaise() }
        function onToggleMainWindowRequested() { root.toggleVisibility() }
        function onHideMainWindowRequested() { root.hide() }
    }

    // Global undo snackbar: every undoable journaled action offers a one-tap
    // UNDO. The commit id is captured per-message so a queued snackbar always
    // undoes the entry it was shown for.
    Connections {
        target: JournalController
        function onActionJournaled(commitId, description, undoable) {
            if (undoable)
                NotificationCenter.notify(description, "info", "", qsTr("Undo"),
                    "journal-undo:" + commitId)
            else
                snackbar.show(description)
        }
        function onOperationFinished(success, message) {
            if (message && message.length > 0)
                snackbar.show(message)
        }
    }

    Connections {
        target: NotificationCenter
        // Every user-facing event already passes through the notification
        // centre, so narrating that gives the narrator full coverage without a
        // second event bus to keep in sync. The severity becomes the category,
        // which is what drives the per-category cooldown — and "error" is the
        // one category the rate limits never silence.
        function onNotificationRaised(id, title, body, severity, actionLabel, actionId) {
            if (!NarratorController.enabled)
                return
            const spoken = (title && title.length > 0) ? (title + ". " + body) : body
            NarratorController.narrate(severity, spoken, I18n.t(spoken))
        }

        function onActionRequested(actionId, notificationId) {
            if (actionId.startsWith("journal-undo:")) {
                JournalController.undoEntry(actionId.slice("journal-undo:".length))
                NotificationCenter.dismiss(notificationId)
            }
            // Anything the app exports can be opened in the configured editor
            // straight from the notification that announced it, so the user is
            // never left to find the file on disk themselves.
            else if (actionId.startsWith("open-export:")) {
                const target = actionId.slice("open-export:".length)
                Log.info("ui", "Opening export in external editor: " + target)
                if (!DesktopIntegration.openInExternalEditor(target)) {
                    NotificationCenter.notify(
                        qsTr("No external editor is configured. Choose one in Settings."),
                        "warning")
                }
                NotificationCenter.dismiss(notificationId)
            }
        }
    }

    Connections {
        target: DesktopIntegration
        function onActivationRequested() {
            Log.debug("ui", "Tray activation -> toggle main window")
            root.toggleVisibility()
        }
        function onContextMenuRequested() {
            Log.debug("ui", "Tray context menu requested")
            trayMenu.popup()
        }
        function onNotificationClicked() {
            Log.debug("ui", "Notification clicked -> show window")
            root.showAndRaise()
        }
        function onEditorLaunchFinished(success, message) {
            NotificationCenter.notify(message, success ? "success" : "error",
                success ? qsTr("External editor opened") : qsTr("External editor failed"))
        }
    }

    Connections {
        target: Experience
        function onOperationFinished(success, message) {
            NotificationCenter.notify(message, success ? "success" : "error",
                success ? qsTr("Changelog action completed") : qsTr("Changelog action failed"))
        }
    }

    Connections {
        target: WorkspaceManager
        function onAppDisplayNameChanged() {
            DesktopIntegration.toolTip = WorkspaceManager.appDisplayName
        }
    }

    // =========================================================================
    //  Action implementations (the shell "slots")
    // =========================================================================

    function addTorrentFile() {
        Log.info("ui", "Action: Add Torrent File")
        openTorrentDialog.open()
    }
    function addTorrentLink() {
        Log.info("ui", "Action: Add Torrent Link")
        downloadFromURLDialog.open()
    }
    function createTorrent() {
        Log.info("ui", "Action: Torrent Creator")
        torrentCreatorDialog.open()
    }
    function manageCookies() {
        Log.info("ui", "Action: Manage Cookies")
        cookiesDialog.open()
    }
    function showOptions() {
        Log.info("ui", "Action: Options")
        optionsDialog.open()
    }
    function showOptionsConnectionTab() {
        Log.info("ui", "Action: Options (Connection tab)")
        if (optionsDialog.showConnectionTab !== undefined)
            optionsDialog.showConnectionTab()
        else
            optionsDialog.open()
    }
    function invokePaletteCommand(commandId) {
        Log.info("ui", "Command palette: " + commandId)
        if (commandId.indexOf("tab.") === 0) {
            var tabs = { "tab.transfers": 0, "tab.search": 1, "tab.rss": 2,
                "tab.log": 3, "tab.workspace": 4 }
            switchToTab(tabs[commandId])
        }
        else if (commandId.indexOf("options.") === 0)
            optionsDialog.showPage(parseInt(commandId.slice(8)))
        else if (commandId === "action.addFile") addTorrentFile()
        else if (commandId === "action.addLink") addTorrentLink()
        else if (commandId === "action.history") togglePanel("history")
        else if (commandId === "action.statistics") showStatistics()
        else if (commandId === "action.about") showAbout()
    }
    function exitApp() {
        Log.info("ui", "Action: Exit")
        AppController.exit(false)
    }

    function startSelected() {
        Log.info("ui", "Action: Start selected")
        TransferController.start()
    }
    function stopSelected() {
        Log.info("ui", "Action: Stop selected")
        TransferController.stop()
    }
    function removeSelected() {
        Log.info("ui", "Action: Remove selected")
        deletionDialog.torrentsCount = TransferController.selectionCount
        deletionDialog.torrentName = qsTr("selected torrent")
        deletionDialog.open()
    }

    Timer {
        id: captureTimer
        interval: 1400
        repeat: false
        onTriggered: {
            var saved = AppController.captureMainWindow(root.captureOutput)
            ThemeManager.colorScheme = root.captureOriginalScheme
            Log.info("ui", "Documentation capture finished; saved=" + saved)
            AppController.exit(true)
        }
    }

    Timer {
        id: captureSetupTimer
        interval: 120
        repeat: false
        onTriggered: {
            // Start the capture clock first so even a page/dialog setup error
            // cannot strand a documentation process.
            captureTimer.start()
            centralTabs.activateTab(root.capturePage)
            switch (root.captureDialog) {
            case "options": optionsDialog.open(); break
            case "add-link": downloadFromURLDialog.open(); break
            case "about": aboutDialog.initialTab = 0; aboutDialog.open(); break
            case "about-license": aboutDialog.initialTab = 4; aboutDialog.open(); break
            case "about-changelog": aboutDialog.initialTab = 5; aboutDialog.open(); break
            case "dim-sum": Experience.considerStartupSurprise(true, false, true); break
            case "statistics": statisticsDialog.open(); break
            case "speed-limits": speedLimitDialog.open(); break
            case "history": root.activePanel = "history"; break
            case "settings-sheet": root.activePanel = "settings"; break
            case "regex": root.activePanel = "regex"; break
            case "notifications": root.activePanel = "notifications"; break
            default: break
            }
        }
    }

    Timer {
        id: startupSurpriseTimer
        interval: 1800
        repeat: false
        onTriggered: Experience.considerStartupSurprise(root.captureMode,
            root.blockingFlowActive(), false)
    }
    function queueTop() { Log.info("ui", "Action: Queue top"); TransferController.queueTop() }
    function queueUp() { Log.info("ui", "Action: Queue up"); TransferController.queueUp() }
    function queueDown() { Log.info("ui", "Action: Queue down"); TransferController.queueDown() }
    function queueBottom() { Log.info("ui", "Action: Queue bottom"); TransferController.queueBottom() }
    function openDestinationFolder() {
        Log.info("ui", "Action: Open destination folder")
        TransferController.openDestination()
    }
    function pauseSession() {
        Log.info("ui", "Action: Pause session")
        TransferController.pauseSession()
    }
    function resumeSession() {
        Log.info("ui", "Action: Resume session")
        TransferController.resumeSession()
    }

    function showStatistics() { Log.info("ui", "Action: Statistics"); statisticsDialog.open() }
    function showAbout() { Log.info("ui", "Action: About"); aboutDialog.open() }
    function showGlobalSpeedLimits() { Log.info("ui", "Action: Global speed limits"); speedLimitDialog.open() }
    function toggleAltSpeed() {
        Log.info("ui", "Action: Toggle alternative speed limits")
        SpeedLimitController.toggleAlternativeLimits()
    }
    function openDocumentation() {
        Log.info("ui", "Action: Documentation")
        Qt.openUrlExternally("https://ding-ding-projects.github.io/qbittorrent-material/#wiki")
    }
    function donate() {
        Log.info("ui", "Action: Donate")
        Qt.openUrlExternally("https://www.qbittorrent.org/donate")
    }
    function checkForUpdates() {
        Log.info("ui", "Action: Check for updates")
        AppController.checkForUpdates()
    }
    function managePlugins() {
        Log.info("ui", "Action: Manage plugins")
        // Search owns the plugin manager dialog. Route the legacy menu action
        // through the same destination path as the visible Search plugins
        // button so it cannot silently become a dead end.
        centralTabs.openSearchPlugins()
    }

    function lockUI() {
        Log.info("ui", "Action: Lock UI")
        if (!AppController.lockPasswordSet) {
            Log.debug("ui", "No lock password set; prompting to define one first")
            defineLockPassword()
            return
        }
        AppController.lock()
    }
    function defineLockPassword() {
        Log.info("ui", "Action: Define lock password")
        lockPasswordDialog.open()
    }
    function clearLockPassword() {
        Log.info("ui", "Action: Clear lock password")
        AppController.setLockPassword("")
        snackbar.show(qsTr("The UI lock password has been cleared."))
    }

    // -- View toggles (persist through Preferences) --
    function setToolbarVisible(v) {
        Log.info("ui", "Toolbar visible -> " + v)
        root.toolbarVisible = v
        Preferences.setToolbarDisplayed(v)
        Preferences.apply()
    }
    function setStatusbarVisible(v) {
        Log.info("ui", "Status bar visible -> " + v)
        root.statusbarVisible = v
        Preferences.setStatusbarDisplayed(v)
        Preferences.apply()
    }
    function setSidebarVisible(v) {
        Log.info("ui", "Filters sidebar visible -> " + v)
        root.sidebarVisible = v
        Preferences.setFiltersSidebarVisible(v)
        Preferences.apply()
    }
    function setSpeedInTitleBar(v) {
        Log.info("ui", "Speed in title bar -> " + v)
        root.speedInTitleBar = v
        Preferences.showSpeedInTitleBar(v)
        Preferences.apply()
    }
    function setSearchTabEnabled(v) {
        Log.info("ui", "Search tab enabled -> " + v)
        root.searchTabEnabled = v
        Preferences.setSearchEnabled(v)
        Preferences.apply()
        if (v && root.currentTabIndex !== 1)
            centralTabs.activateTab(1)
    }
    function setRSSTabEnabled(v) {
        Log.info("ui", "RSS tab enabled -> " + v)
        root.rssTabEnabled = v
        Preferences.setRSSWidgetVisible(v)
        Preferences.apply()
        if (v && root.currentTabIndex !== 2)
            centralTabs.activateTab(2)
    }
    function setExecutionLogEnabled(v) {
        Log.info("ui", "Execution log enabled -> " + v)
        root.executionLogEnabled = v
        Preferences.setValue("GUI/Log/Enabled", v)
        Preferences.apply()
        if (v && root.currentTabIndex !== 3)
            centralTabs.activateTab(3)
    }
    function setLogTypeEnabled(which, v) {
        Log.info("ui", "Log message type '" + which + "' -> " + v)
        switch (which) {
        case "normal": root.logNormalEnabled = v; break
        case "info": root.logInfoEnabled = v; break
        case "warning": root.logWarningEnabled = v; break
        case "critical": root.logCriticalEnabled = v; break
        }
        // Persist a bitmask (Normal=1, Info=2, Warning=4, Critical=8) to GUI/Log/Types.
        var mask = (root.logNormalEnabled ? 1 : 0)
                 | (root.logInfoEnabled ? 2 : 0)
                 | (root.logWarningEnabled ? 4 : 0)
                 | (root.logCriticalEnabled ? 8 : 0)
        Preferences.setValue("GUI/Log/Types", mask)
        Preferences.apply()
    }
    function setAutoShutdownMode(mode) {
        Log.info("ui", "Auto-shutdown mode -> " + mode)
        root.autoShutdownMode = mode
        Preferences.setShutdownqBTWhenDownloadsComplete(mode === 1)
        Preferences.setSuspendWhenDownloadsComplete(mode === 2)
        Preferences.setHibernateWhenDownloadsComplete(mode === 3)
        Preferences.setRebootWhenDownloadsComplete(mode === 4)
        Preferences.setShutdownWhenDownloadsComplete(mode === 5)
        Preferences.apply()
    }

    // -- Tab & window helpers --
    function switchToTab(index) {
        Log.debug("ui", "Switch to tab " + index)
        // Lazily enable the tab if the user jumps to it via a shortcut.
        if (index === 1 && !root.searchTabEnabled)
            root.setSearchTabEnabled(true)
        else if (index === 2 && !root.rssTabEnabled)
            root.setRSSTabEnabled(true)
        else if (index === 3 && !root.executionLogEnabled)
            root.setExecutionLogEnabled(true)
        centralTabs.activateTab(index)
    }
    function toggleVisibility() {
        if (root.visible && root.visibility !== Window.Minimized)
            root.hide()
        else
            root.showAndRaise()
    }
    function showAndRaise() {
        root.show()
        root.raise()
        root.requestActivate()
    }

    // =========================================================================
    //  Startup / shutdown
    // =========================================================================
    onClosing: (close) => {
        // AppController decides whether to confirm / hide-to-tray; veto the raw
        // close and let it drive the flow (it emits confirmExitRequested / hide).
        Log.debug("ui", "Window close requested")
        close.accepted = false
        AppController.exit(false)
    }

    Component.onCompleted: {
        // Configure deterministic documentation state before any persisted
        // preference reads. That keeps captures resilient to a stale or partial
        // profile and guarantees the timer is armed as early as possible.
        if (root.captureMode) {
            root.toolbarVisible = true
            root.statusbarVisible = true
            root.sidebarVisible = true
            root.width = root.captureWidth
            root.height = root.captureHeight
            root.searchTabEnabled = root.searchTabEnabled || root.capturePage === 1
            root.rssTabEnabled = root.rssTabEnabled || root.capturePage === 2
            root.executionLogEnabled = root.executionLogEnabled || root.capturePage === 3
            ThemeManager.colorScheme = root.captureTheme === "dark"
                ? ThemeManager.Dark : ThemeManager.Light
            if (root.captureStyle === "A") ThemeManager.uiStyle = ThemeManager.TonalRail
            else if (root.captureStyle === "B") ThemeManager.uiStyle = ThemeManager.SplitDock
            else if (root.captureStyle === "C") ThemeManager.uiStyle = ThemeManager.CardFlow
            captureSetupTimer.start()
        }

        Log.info("ui", "Main window constructed; initializing shell state from Preferences")
        DesktopIntegration.toolTip = WorkspaceManager.appDisplayName
        if (!root.captureMode) {
            root.scheduleScreenGeometryUpdate(true)
            root.toolbarVisible = Preferences.isToolbarDisplayed()
            root.statusbarVisible = Preferences.isStatusbarDisplayed()
            root.sidebarVisible = Preferences.isFiltersSidebarVisible()
            root.speedInTitleBar = Preferences.speedInTitleBar()
            root.searchTabEnabled = Preferences.isSearchEnabled()
            root.rssTabEnabled = Preferences.isRSSWidgetEnabled()
            root.executionLogEnabled = Preferences.value("GUI/Log/Enabled", false)
            if (!Preferences.value("Experience/FunnyDisclosureShown", false)) {
                NotificationCenter.notify(
                    qsTr("English and Cantonese funny levels style every message, including errors and warnings. Facts and available actions stay unchanged. You can change or reset both levels in Options at any time."),
                    "info", qsTr("Language voice controls"))
                Preferences.setValue("Experience/FunnyDisclosureShown", true)
                Preferences.apply()
            }
        }

        var mask = Preferences.value("GUI/Log/Types", 15)
        root.logNormalEnabled = (mask & 1) !== 0
        root.logInfoEnabled = (mask & 2) !== 0
        root.logWarningEnabled = (mask & 4) !== 0
        root.logCriticalEnabled = (mask & 8) !== 0

        if (Preferences.shutdownqBTWhenDownloadsComplete()) root.autoShutdownMode = 1
        else if (Preferences.suspendWhenDownloadsComplete()) root.autoShutdownMode = 2
        else if (Preferences.hibernateWhenDownloadsComplete()) root.autoShutdownMode = 3
        else if (Preferences.rebootWhenDownloadsComplete()) root.autoShutdownMode = 4
        else if (Preferences.shutdownWhenDownloadsComplete()) root.autoShutdownMode = 5
        else root.autoShutdownMode = 0

        Log.info("ui", "Shell ready. toolbar=" + root.toolbarVisible
                 + " statusbar=" + root.statusbarVisible + " sidebar=" + root.sidebarVisible)
        startupSurpriseTimer.start()
    }
    function blockingFlowActive() {
        if (root.activePanel.length > 0 || AppController.locked)
            return true
        var overlayChildren = Overlay.overlay ? Overlay.overlay.children : []
        for (var i = 0; i < overlayChildren.length; ++i) {
            var child = overlayChildren[i]
            if (child && child.visible && child.modal === true)
                return true
        }
        return false
    }
}
