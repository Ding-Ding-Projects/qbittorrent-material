# qBittorrent Material — Feature Inventory (from discovery)

Exhaustive inventory of the upstream qBittorrent desktop client, area by area, used as the spec for this rewrite.


---

# Area: Main Window Shell — menu bar, toolbar, status bar, system tray, central tabs, and the filter/properties split

# Main Window Shell

Source of truth: `src/gui/mainwindow.{h,cpp,ui}`, `src/gui/statusbar.{h,cpp}`, `src/gui/desktopintegration.{h,cpp}`, `src/gui/hidabletabwidget.{h,cpp}`, `src/gui/transferlistfilterswidget.cpp`, `src/gui/transferlistmodel.h`, `src/gui/properties/proptabbar.{h,cpp}`, `src/gui/transferlistfilters/statusfilterwidget.cpp`.

The Widgets class is `MainWindow final : public GUIApplicationComponent<QMainWindow>`. Its `.ui` (class `Ui::MainWindow`) is a `QMainWindow` with `contextMenuPolicy = CustomContextMenu`, default geometry `914 x 563`, a `centralWidget` (QVBoxLayout `centralWidgetLayout`, margins L7/T3/R5/B0), a `menubar`, a `toolBar`, and a `statusBar` placeholder. All top-level "screens" below live inside this one window.

## 1. Layout hierarchy (what to rebuild in QML)

```
MainWindow (ApplicationWindow)
├── MenuBar                         (native menu, section 2)
├── TopToolBar                      (section 3; visibility bound to Preferences::isToolbarDisplayed)
├── central column (centralWidgetLayout)
│   └── HidableTabWidget  m_tabs    (section 7 — tab bar auto-hides when only 1 tab)
│       ├── Tab 0 "Transfers (N)"   → QSplitter m_splitter (Horizontal)
│       │      ├── [optional] TransferListFiltersWidget  (sidebar, index 0, collapsible)
│       │      └── QSplitter hSplitter (Vertical, non-collapsible children, NoFrame)
│       │             ├── TransferListWidget  m_transferListWidget   (top)
│       │             └── PropertiesWidget     m_propertiesWidget    (bottom)
│       ├── Tab (index 1) "Search"        → SearchWidget      (created on demand)
│       ├── Tab "RSS (N)"                 → RSSWidget         (created on demand)
│       └── Tab "Execution Log"           → ExecutionLogWidget(created on demand)
└── StatusBar  m_statusBar          (section 4; visibility bound to Preferences::isStatusbarDisplayed)
```

Splitters:
- `m_splitter` (Horizontal): child 0 (sidebar) initially `setCollapsible(0,false)`; when sidebar added it becomes `setCollapsible(0,true)`, `setStretchFactor(0,0)`, `setStretchFactor(1,1)`, and sized from `Preferences::getFiltersSidebarWidth()`. `splitterMoved` → `saveSplitterSettings()` → `Preferences::setFiltersSidebarWidth(sizes()[0])`.
- `hSplitter` (Vertical): transfer list over properties; `splitterMoved` → `saveSettings()`.

## 2. Menu bar

Top-level order (from `.ui` `addaction` on `menubar`): **File, Edit, View, Tools, Plugins, Help**. On macOS a native **Window** menu is inserted before Help; some roles are reassigned (see §12). On Unix, `actionOptions` text becomes "Preferences".

Every action below is a real `QAction` from `mainwindow.ui`. Format: `objectName` — "Text" [shortcut] {checkable} → slot/target. Icon names are the `UIThemeManager::getIcon(...)` keys set in the ctor.

### File (`menuFile`, "&File")
- `actionOpen` — "&Add Torrent File..." (iconText "Open", icon `list-add`) [QKeySequence::Open = Ctrl+O] → `on_actionOpen_triggered()` (multi-select `QFileDialog::getOpenFileNames`, filter `*.torrent`, then `app()->addTorrentManager()->addTorrent(file)`; remembers dir via `Preferences::getMainLastDir/setMainLastDir`).
- `actionDownloadFromURL` — "Add Torrent &Link..." (iconText "Open URL", icon `insert-link`) [Ctrl+Shift+O] → `on_actionDownloadFromURL_triggered()` (opens `DownloadFromURLDialog`; `urlsReadyToBeDownloaded` → `downloadFromURLList`).
- `actionCloseWindow` — "Close Window" [QKeySequence::Close] → `on_actionCloseWindow_triggered()`. **macOS only** — `setVisible(false)` elsewhere.
- separator
- `actionExit` — "E&xit" (icon `application-exit`) [Ctrl+Q] → `on_actionExit_triggered()` (sets `m_forceExit=true`, `close()`). MenuRole = QuitRole.

### Edit (`menuEdit`, "&Edit")
- `actionStart` — "Sta&rt" (icon `torrent-start`/`media-playback-start`) [Ctrl+S] → `TransferListWidget::startSelectedTorrents`.
- `actionStop` — "Sto&p" (icon `torrent-stop`/`media-playback-pause`) [Ctrl+P] → `TransferListWidget::stopSelectedTorrents`.
- separator
- `actionDelete` — "&Remove" (icon `list-remove`) [`Utils::KeySequence::deleteItem()`, shortcutContext WidgetShortcut so it is inert at window level] → `TransferListWidget::softDeleteSelectedTorrents`.
- `m_queueSeparatorMenu` (dynamic separator inserted before actionTopQueuePos; visibility tracks queueing system)
- `actionTopQueuePos` — "Top of Queue" (tooltip "Move to the top of the queue", icon `go-top`) [Ctrl+Shift+Plus] → `topQueuePosSelectedTorrents`.
- `actionIncreaseQueuePos` — "Move Up Queue" (icon `go-up`) [Ctrl+Plus] → `increaseQueuePosSelectedTorrents`.
- `actionDecreaseQueuePos` — "Move Down Queue" (icon `go-down`) [Ctrl+Minus] → `decreaseQueuePosSelectedTorrents`.
- `actionBottomQueuePos` — "Bottom of Queue" (icon `go-bottom`) [Ctrl+Shift+Minus] → `bottomQueuePosSelectedTorrents`.
- separator
- `actionPauseSession` — "Pau&se Session" (icon `pause-session`/`media-playback-pause`) [Ctrl+Shift+P] → `TransferListWidget::pauseSession`. Visible only when session **not** paused.
- `actionResumeSession` — "R&esume Session" (icon `torrent-start`/`media-playback-start`) [Ctrl+Shift+S] → `TransferListWidget::resumeSession`. Visible only when session **is** paused.

The five queue actions + `m_queueSeparator`/`m_queueSeparatorMenu` are shown/hidden together based on `BitTorrent::Session::isQueueingSystemEnabled()` (also toggles the transfer-list queue-position column via `TransferListWidget::hideQueuePosColumn`).

### View (`menuView`, "&View")
- separator
- `actionTopToolBar` — "&Top Toolbar" {checkable} (tooltip "Display Top Toolbar") → `on_actionTopToolBar_triggered()` → `toolBar->setVisible`, `Preferences::setToolbarDisplayed`.
- `actionShowStatusbar` — "Status &Bar" {checkable} → `on_actionShowStatusbar_triggered()` → `Preferences::setStatusbarDisplayed` + `showStatusBar()`.
- `actionShowFiltersSidebar` — "Filters Sidebar" {checkable} → `on_actionShowFiltersSidebar_triggered(bool)` → `Preferences::setFiltersSidebarVisible` + `showFiltersSidebar()`.
- `actionSpeedInTitleBar` — "S&peed in Title Bar" {checkable} (tooltip "Show Transfer Speed in Title Bar") → `on_actionSpeedInTitleBar_triggered()` → `Preferences::showSpeedInTitleBar` + `refreshWindowTitle()`.
- separator
- `actionSearchWidget` — "Search &Engine" {checkable} → `on_actionSearchWidget_triggered()` (validates Python via `Utils::ForeignApps::pythonInfo()`; on Windows offers to auto-install Python 3.14.5; toggles `Preferences::setSearchEnabled` + `displaySearchTab`).
- `actionRSSReader` — "&RSS Reader" {checkable} → `on_actionRSSReader_triggered()` → `Preferences::setRSSWidgetVisible` + `displayRSSTab`.
- `menuLog` ("&Log", icon `help-contents`):
  - `actionExecutionLogs` — "Show" {checkable} → `on_actionExecutionLogs_triggered(bool)` (creates/deletes ExecutionLogWidget tab; enables/disables the 4 message-type actions; `setExecutionLogEnabled`).
  - separator
  - `actionNormalMessages` — "Normal Messages" {checkable} → toggles `Log::NORMAL` flag.
  - `actionInformationMessages` — "Information Messages" {checkable} → toggles `Log::INFO`.
  - `actionWarningMessages` — "Warning Messages" {checkable} → toggles `Log::WARNING`.
  - `actionCriticalMessages` — "Critical Messages" {checkable} → toggles `Log::CRITICAL`.
- separator
- `actionStatistics` — "&Statistics" (icon `view-statistics`) [Ctrl+I] → `on_actionStatistics_triggered()` (opens `StatsDialog`).
- separator
- `actionLock` — "L&ock qBittorrent" (iconText "Lock", icon `object-locked`) [Ctrl+L] → `on_actionLock_triggered()`. Has a submenu `lockMenu` with "&Set Password" (`defineUILockPassword`) and "&Clear Password" (`clearUILockPassword`). On non-macOS, visible only when `desktopIntegration()->isActive()`.

### Tools (`menuOptions`, "&Tools")
- `actionCreateTorrent` — "Torrent &Creator" (icon `torrent-creator`/`document-edit`) [QKeySequence::New = Ctrl+N] → `on_actionCreateTorrent_triggered()` (opens `TorrentCreatorDialog`).
- separator
- `actionManageCookies` — "Manage Cookies..." (tooltip "Manage stored network cookies", icon `browser-cookies`) → `manageCookies()` (opens `CookiesDialog`).
- `actionOptions` — "&Options..." / "Preferences" on Unix (icon `configure`/`preferences-system`) [Alt+O] → `on_actionOptions_triggered()` (opens `OptionsDialog`). MenuRole = PreferencesRole.
- separator
- `menuAutoShutdownOnDownloadsCompletion` ("On Downloads &Done", icon `task-complete`/`application-exit`) — an exclusive `QActionGroup`:
  - `actionAutoShutdownDisabled` — "&Do nothing" {checkable} (default checked).
  - `actionAutoExit` — "&Exit qBittorrent" {checkable} → `Preferences::setShutdownqBTWhenDownloadsComplete`.
  - `actionAutoSuspend` — "&Suspend System" {checkable} → `setSuspendWhenDownloadsComplete`.
  - `actionAutoHibernate` — "&Hibernate System" {checkable} → `setHibernateWhenDownloadsComplete` (disabled on macOS).
  - `actionAutoReboot` — "&Reboot System" {checkable} → `setRebootWhenDownloadsComplete`.
  - `actionAutoShutdown` — "Sh&utdown System" {checkable} → `setShutdownWhenDownloadsComplete`.
  - (system-power items disabled unless `!Q_OS_UNIX || Q_OS_MACOS || QBT_USES_DBUS`.)

### Plugins (`menuPlugins`, "Plugins") — only when `ENABLE_PLUGINS`; hidden otherwise
- `actionManagePlugins` — "Manage Plugins..." (tooltip "Manage installed plugins", icon `plugins`) → `managePlugins()` (opens `PluginsDialog`).
- separator
- Dynamic per-plugin action items appended/removed via `PluginsEngine` signals (`pluginInstalled/Uninstalled/Updated/EnabledChanged`); each triggers `PluginsEngine::invokePlugin(id)`. Tracked in `QHash<QString,QAction*> m_pluginActions`.

### Help (`menuHelp`, "&Help")
- `actionDocumentation` — "&Documentation" (icon `help-contents`) [QKeySequence::HelpContents] → opens `https://doc.qbittorrent.org`.
- `actionCheckForUpdates` — "Check for Updates" (tooltip "Check for Program Updates", icon `view-refresh`) → `checkProgramUpdate(true)`. **Windows/macOS only** (`setVisible(false)` elsewhere). MenuRole = ApplicationSpecificRole. During check, text/tooltip change to "Checking for Updates..." and it disables.
- separator
- `actionDonateMoney` — "Do&nate!" (tooltip "If you like qBittorrent, please donate!", icon `wallet-open`) → opens `https://www.qbittorrent.org/donate`.
- `actionAbout` — "&About" (icon `help-about`) → `on_actionAbout_triggered()` (opens `AboutDialog`). MenuRole = AboutRole.

### Actions defined in `.ui` but not on any menu (attached elsewhere)
- `actionSetGlobalSpeedLimits` — "Set Global Speed Limits..." (icon `speedometer`) → `on_actionSetGlobalSpeedLimits_triggered()` (opens `SpeedLimitDialog`). Used by tray menu.
- `actionUseAlternativeSpeedLimits` — "Alternative Speed Limits" {checkable} → `toggleAlternativeSpeeds()`. Used by tray menu + reflects status-bar toggle.
- `actionOpenDestinationFolder` — "Open Destination Folder" (iconText "Open Folder", icon `directory`) → `openSelectedTorrentsFolder`. Toolbar only.
- `actionToggleVisibility` — "Show" → `toggleVisibility()`. Tray menu only; text flips "Show"/"Hide" on `menu aboutToShow`.
- `actionMinimize` — "Minimize" [Ctrl+M, macOS] → `minimizeWindow()`.

## 3. Top toolbar (`toolBar`)

`QToolBar` (movable=false, floatable=false, horizontal, area=TopToolBarArea, `toolButtonStyle=ToolButtonFollowStyle`). Action order from `.ui`:

`actionOpen`, `actionDownloadFromURL`, `actionDelete`, **sep**, `actionStart`, `actionStop`, `actionOpenDestinationFolder`, `actionTopQueuePos`, `actionIncreaseQueuePos`, `actionDecreaseQueuePos`, `actionBottomQueuePos`, **sep**, `actionCreateTorrent`, **sep**, `actionOptions`, `actionLock`.

Injected in the ctor (before `actionLock`):
- A stretch spacer `QWidget` (Expanding).
- `m_columnFilterWidget` (inserted via `insertWidget(actionLock, …)`, action handle `m_columnFilterAction`): an HBox holding a `LineEdit m_columnFilterEdit` (fixed width 200, placeholder "Filter torrents...", custom context menu adds a checkable "Use regular expressions" bound to `Preferences::getRegexAsFilteringPatternForTransferList/set…`), a `QLabel` "Filter by:", and `QComboBox m_columnFilterComboBox`. The combo is populated from four `TransferListModel::Column` values — **Name, Save Path, Info Hash v1, Info Hash v2** (`TR_NAME, TR_SAVE_PATH, TR_INFOHASH_V1, TR_INFOHASH_V2`), labels pulled from the model header. `textChanged`/`currentIndexChanged` → `applyTransferListFilter()` → `TransferListWidget::applyFilter(text, column)`. `m_columnFilterAction` is shown only on the Transfers tab (hidden on other tabs via `tabChanged`).
- `m_queueSeparator` (dynamic separator inserted before `actionTopQueuePos`; visibility tracks queueing system).

Toolbar context menu (`m_toolbarMenu`, `addToolbarContextMenu()`, shown on `customContextMenuRequested`): exclusive group of five checkable items setting `toolButtonStyle` and persisting `Preferences::setToolbarTextPosition`:
- "Icons Only" → `Qt::ToolButtonIconOnly`
- "Text Only" → `Qt::ToolButtonTextOnly`
- "Text Alongside Icons" → `Qt::ToolButtonTextBesideIcon`
- "Text Under Icons" → `Qt::ToolButtonTextUnderIcon`
- "Follow System Style" → `Qt::ToolButtonFollowStyle`

Initial style read from `Preferences::getToolbarTextPosition()`. Toolbar visibility restored from `Preferences::isToolbarDisplayed()`; hiding it also clears the filter edit.

## 4. Status bar (`StatusBar : QStatusBar`)

Global stylesheet zeroes margins/`::item` border. Widgets added via `addPermanentWidget` in this left→right order (each `createSeparator()` is a vertical `QFrame::VLine`):

1. `m_freeDiskSpaceLbl` (QLabel) — "Free space: N/A" → "Free space: <friendlyUnit>". Updated from `Session::freeDiskSpace()` and `freeDiskSpaceChecked(qint64)`. Visible per `Preferences::isStatusbarFreeDiskSpaceDisplayed()`.
2. `m_freeDiskSpaceSeparator`.
3. `m_lastExternalIPsLbl` (QLabel) — "External IP: N/A" / "External IP: %1" / "External IPs: %1, %2" from `Session::lastExternalIPv4Address()` + `lastExternalIPv6Address()`. Visible per `Preferences::isStatusbarExternalIPDisplayed()`.
4. `m_lastExternalIPsSeparator`.
5. `m_DHTLbl` (QLabel) — "DHT: %1 nodes" from `Session::status().dhtNodes`. Whole label+separator visible only when `Session::isDHTEnabled()`.
6. `m_DHTSeparator`.
7. `m_connecStatusLblIcon` (flat QPushButton, PointingHandCursor, NoFocus, small icon) — connection state. Icons/tooltips:
   - not listening → icon `disconnected`, tooltip "Connection Status: / Offline. This usually means that qBittorrent failed to listen on the selected port for incoming connections."
   - listening + `status().hasIncomingConnections` → icon `connected`, tooltip "Connection Status: / Online".
   - listening + firewalled → icon `firewalled`, tooltip "Connection status: / No direct connections. This may indicate network configuration problems."
   - Click → `connectionButtonClicked` signal → MainWindow `showConnectionSettings()` (opens Options on the Connection tab: `on_actionOptions_triggered()` + `m_options->showConnectionTab()`).
8. separator.
9. `m_altSpeedsBtn` (flat QPushButton, mid×small icon) — alt-speed toggle. `updateAltSpeedsBtn(bool)`: enabled → icon `slow`, tooltip "Click to switch to regular speed limits", `setDown(true)`; disabled → icon `slow_off`, tooltip "Click to switch to alternative speed limits", `setDown(false)`. Click → `alternativeSpeedsButtonClicked` → MainWindow `toggleAlternativeSpeeds()`. Kept in sync with `Session::speedLimitModeChanged`.
10. separator.
11. `m_dlSpeedLbl` (`createSpeedButton`, flat, min-width 200, left-aligned text, icon `downloading`/`downloading_small`) — text `friendlyUnit(payloadDownloadRate,true)` + optional `[limit]` when `downloadSpeedLimit()>0` + `(friendlyUnit(totalPayloadDownload))`. Click → `capSpeed()` (opens `SpeedLimitDialog`).
12. separator.
13. `m_upSpeedLbl` (icon `upload`/`seeding`) — same pattern with `payloadUploadRate`, `uploadSpeedLimit()`, `(totalPayloadUpload)`. Click → `capSpeed()`.

Refresh: `Session::statsUpdated` → `refresh()` = updateConnectionStatus + updateDHTNodesNumber + updateExternalAddressesLabel + updateSpeedLabels. `Preferences::changed` → `optionsSaved()` re-evaluates free-space/external-IP visibility. `showRestartRequired()` inserts a warning icon (SP_MessageBoxWarning) + label "qBittorrent needs to be restarted!" at positions 0/1. Signals: `alternativeSpeedsButtonClicked()`, `connectionButtonClicked()`. Data source `BitTorrent::SessionStatus` fields consumed: `hasIncomingConnections`, `dhtNodes`, `payloadDownloadRate`, `payloadUploadRate`, `totalPayloadDownload`, `totalPayloadUpload`.

The status bar is created lazily in `showStatusBar(bool)`: on show, `new StatusBar` and `setStatusBar(...)`; on hide, `setStatusBar(nullptr)`.

## 5. System tray / desktop integration menu (`DesktopIntegration`)

`DesktopIntegration : QObject` owns a `QMenu *m_menu` and (non-macOS) `QSystemTrayIcon *m_systrayIcon`. Tray icon created only when `Preferences::systemTrayEnabled()`; icon from `UIThemeManager::getSystrayIcon()` (KDE workaround renders to 32px pixmap). Activation: `QSystemTrayIcon::Trigger` → `activationRequested()` → MainWindow `toggleVisibility()` (macOS: `activate()`). `notificationClicked` → `desktopNotificationClicked()`. `stateChanged` re-evaluates `actionLock` visibility. Tooltip set from `refreshTrayIconTooltip()`: running → "DL speed: %1\nUP speed: %2", paused → "Paused".

Menu contents (`populateDesktopIntegrationMenu()`), reusing the same `QAction`s as the menus/toolbar:
- (non-macOS) `actionToggleVisibility` ("Show"/"Hide"), then separator.
- `actionOpen`, `actionDownloadFromURL`, separator.
- `actionUseAlternativeSpeedLimits` {checkable}, `actionSetGlobalSpeedLimits`, separator.
- `actionResumeSession`, `actionPauseSession`.
- (non-macOS) separator, `actionExit`.
- When UI is locked the whole menu is `setEnabled(false)`.

macOS: the same `QMenu` is installed as the Dock menu (`setAsDockMenu()`), dock-click overridden to `activationRequested`. Notifications: DBus (`DBusNotifier`) when `QBT_USES_DBUS` (timeout key `GUI/Notifications/Timeout`, default -1), else `QSystemTrayIcon::showMessage` (5000 ms), else macOS native. `showNotification(title,msg)` is a no-op when notifications disabled. Notifications enabled key `GUI/Notifications/Enabled` (default true).

## 6. Global keyboard shortcuts (`createKeyboardShortcuts()` + `.ui`)

| Shortcut | Action / slot |
|---|---|
| Ctrl+O | actionOpen (Add torrent file) |
| Ctrl+Shift+O | actionDownloadFromURL |
| Ctrl+N | actionCreateTorrent |
| Del (`Utils::KeySequence::deleteItem()`) | actionDelete (WidgetShortcut — handled by list) |
| Ctrl+Q | actionExit |
| Ctrl+S / Ctrl+P | Start / Stop selected |
| Ctrl+Shift+S / Ctrl+Shift+P | Resume / Pause session |
| Ctrl+Shift+Plus / Ctrl+Plus | Top / Move up queue |
| Ctrl+Minus / Ctrl+Shift+Minus | Move down / Bottom queue |
| Ctrl+I | actionStatistics |
| Alt+O | actionOptions |
| F1 (HelpContents) | actionDocumentation |
| Ctrl+L | actionLock |
| Alt+1 / Alt+2 / Alt+3 / Alt+4 | Switch to Transfers / Search / RSS / Execution Log tab (`displayTransferTab/displaySearchTab/displayRSSTab/displayExecutionLogTab`) |
| Ctrl+F (Find) and Ctrl+E | `toggleFocusBetweenLineEdits()` — moves focus between transfer filter box and the Content-tab file filter |
| Ctrl+M | actionMinimize (macOS) |
| Ctrl+W (Close) | actionCloseWindow (macOS) |
| Ctrl+V / paste | `keyPressEvent`: paste clipboard, add each line that `Utils::Misc::isTorrentLink()` as a torrent |

Tab-switch shortcuts lazily create their widget (set the corresponding checkable View action, then `setCurrentWidget`).

## 7. Central tab area (`HidableTabWidget m_tabs`)

`HidableTabWidget : QTabWidget` — the tab bar hides itself when `count()==1` and re-appears at ≥2 tabs; single-tab focus policy is `NoFocus` (StrongFocus when >1). On macOS it suppresses pane painting under QMacStyle.

Tabs:
- **Transfers** — index 0, always present. Icon `folder-remote` (non-macOS). Title dynamic: `tr("Transfers (%1)")` from `TransferListWidget::getSourceModel()->rowCount()`, refreshed on `rowsInserted/rowsRemoved` via `updateNbTorrents()`. Content = `m_splitter` (see §1/§8/§9/§10). Selecting this tab shows the toolbar filter widget and calls `PropertiesWidget::loadDynamicData()`.
- **Search** — inserted at index 1 when enabled (`displaySearchTab(bool)`); icon `edit-find`; `SearchWidget`. On `searchFinished(failed)` shows a desktop notification ("Search Engine" / "Search has finished" or "Search has failed") if not the current tab. Selecting the tab focuses the search input.
- **RSS** — appended when enabled (`displayRSSTab(bool)`); icon `application-rss`; `RSSWidget`. Title `tr("RSS (%1)")` where %1 = `RSS::Session::instance()->rootFolder()->unreadCount()`, updated via `unreadCountUpdated` → `handleRSSUnreadCountUpdated`.
- **Execution Log** — appended when enabled (`on_actionExecutionLogs_triggered(true)`); icon `help-contents`; `ExecutionLogWidget(executionLogMsgTypes(), ...)`.

`tabChanged(int)` compares `currentWidget()` against `m_splitter`/`m_searchWidget` rather than index (order is not fixed). `currentTabWidget()` returns nullptr when minimized/hidden, else the transfer list for index 0 or the current widget.

## 8. Left/right split — filter sidebar + transfer list + properties

Sidebar presence is governed by `actionShowFiltersSidebar` / `Preferences::isFiltersSidebarVisible()`. When absent, MainWindow applies persisted filters directly: `applyStatusFilter(Preferences::getTransSelFilter())`, `applyCategoryFilter("")`, `applyTagFilter(nullopt)`, `applyTrackerFilter({})`. `TransferListWidget::currentTorrentChanged` → `PropertiesWidget::loadTorrentInfos`.

## 9. Filter sidebar (`TransferListFiltersWidget`)

Background role `QPalette::Base`; a `QScrollArea` (no horizontal scrollbar, NoFrame) holds a vertical stack of collapsible section items (`TransferListFiltersWidgetItem` with a header title + `toggled` persistence). Sections, in order:

1. **"Status"** — `StatusFilterWidget`. Checked state key `Preferences::getStatusFilterState/setStatusFilterState`. Fixed rows (label pattern "<name> (<count>)"), backed by `TorrentFilter` enum: **All, Downloading, Seeding, Completed, Running, Stopped, Active, Inactive, Stalled, Stalled Uploading, Stalled Downloading, Checking, Moving, Errored**.
2. **"Categories"** — `CategoryFilterWidget`. Key `getCategoryFilterState/setCategoryFilterState`. `categoryChanged` → `applyCategoryFilter`; context actions Start/ForceStart/Stop/Delete visible torrents.
3. **"Tags"** — `TagFilterWidget`. Key `getTagFilterState/setTagFilterState`. `tagChanged` → `applyTagFilter`; same context actions.
4. **[optional] "Tracker status"** — `TrackerStatusFilterWidget`, inserted at the trackers position only when `Preferences::useSeparateTrackerStatusFilter()`; key `getTrackerStatusFilterState/setTrackerStatusFilterState`. Dynamically added/removed on preference change.
5. **"Trackers"** — `TrackersFilterWidget` (`m_trackersFilterWidget`), constructed with the `downloadFavicon` flag. Key `getTrackerFilterState/setTrackerFilterState`. `setDownloadTrackerFavicon(value)` forwards to it (driven by `GUI/DownloadTrackerFavicon`).

## 10. Properties panel (`PropertiesWidget` + `PropTabBar`)

`PropTabBar : QHBoxLayout` is a `QButtonGroup` of tab buttons with signals `tabChanged(int)` / `visibilityToggled(bool)`. `PropertyTab` enum and labels:
- `MainTab` = **"General"**
- `TrackersTab` = **"Trackers"**
- `PeersTab` = **"Peers"**
- `URLSeedsTab` = **"HTTP Sources"**
- `FilesTab` = **"Content"**
- `SpeedTab` = **"Speed"**

MainWindow reads/writes it via `PropertiesWidget`: `getFilesList()`, `getTrackerList()`, `getPeerList()` (all get `setAlternatingRowColors(Preferences::useAlternatingRowColors())`), `tabBar()`, `contentFilterLine()` (focused by Ctrl+F when Content tab active), `loadTorrentInfos`, `loadDynamicData`, `getCurrentTorrent`, `reloadPreferences`, `saveSettings`, `readSettings`.

## 11. Transfer list columns (`TransferListModel::Column`)

Full enum order (header text comes from `headerData`): `TR_QUEUE_POSITION`(#), `TR_NAME`, `TR_SIZE`, `TR_TOTAL_SIZE`, `TR_PROGRESS`, `TR_STATUS`, `TR_SEEDS`, `TR_PEERS`, `TR_DLSPEED`, `TR_UPSPEED`, `TR_ETA`, `TR_RATIO`, `TR_POPULARITY`, `TR_CATEGORY`, `TR_TAGS`, `TR_ADD_DATE`, `TR_SEED_DATE`, `TR_TRACKER`, `TR_DLLIMIT`, `TR_UPLIMIT`, `TR_AMOUNT_DOWNLOADED`, `TR_AMOUNT_UPLOADED`, `TR_AMOUNT_DOWNLOADED_SESSION`, `TR_AMOUNT_UPLOADED_SESSION`, `TR_AMOUNT_LEFT`, `TR_TIME_ELAPSED`, `TR_SAVE_PATH`, `TR_COMPLETED`, `TR_RATIO_LIMIT`, `TR_SEEN_COMPLETE_DATE`, `TR_LAST_ACTIVITY`, `TR_AVAILABILITY`, `TR_DOWNLOAD_PATH`, `TR_INFOHASH_V1`, `TR_INFOHASH_V2`, `TR_REANNOUNCE`, `TR_PRIVATE`, `TR_CREATE_DATE`, then `NB_COLUMNS`. (`m_columnFilterComboBox` uses TR_NAME / TR_SAVE_PATH / TR_INFOHASH_V1 / TR_INFOHASH_V2.) The model exposes `UnderlyingDataRole = Qt::UserRole` and `AdditionalUnderlyingDataRole` for sort/raw data. Row-state icons cached: checking/completed/downloading/error/moving/stopped/queued/stalledDL/stalledUP/uploading; row text colors per `TorrentState`; zero-value hiding mode Never/Stopped/Always.

## 12. Persistence keys (all `GUI/`-prefixed unless noted)

Owned by MainWindow/DesktopIntegration `SettingValue`s:
- `GUI/Log/Enabled` (bool) — execution log tab enabled.
- `GUI/Log/Types` (Log::MsgTypes, default `Log::MsgType::ALL`) — enabled log message types.
- `GUI/DownloadTrackerFavicon` (bool).
- `GUI/Notifications/Enabled` (bool, default true).
- `GUI/Notifications/Timeout` (int, default -1; DBus builds only).

Read/written through `Preferences::instance()` (persist keys internal to Preferences): `isUILocked/setUILocked`, `getUILockPassword/setUILockPassword` (PBKDF2 via `Utils::Password`), `speedInTitleBar/showSpeedInTitleBar`, `isToolbarDisplayed/setToolbarDisplayed`, `isStatusbarDisplayed/setStatusbarDisplayed`, `isStatusbarFreeDiskSpaceDisplayed`, `isStatusbarExternalIPDisplayed`, `isRSSWidgetEnabled/setRSSWidgetVisible`, `isSearchEnabled/setSearchEnabled`, `getToolbarTextPosition/setToolbarTextPosition`, `isFiltersSidebarVisible/setFiltersSidebarVisible`, `getFiltersSidebarWidth/setFiltersSidebarWidth`, `getMainGeometry/setMainGeometry`, `getTransSelFilter`, `getMainLastDir/setMainLastDir`, `minimizeToTray`, `minimizeToTrayNotified/setMinimizeToTrayNotified`, `closeToTray`, `closeToTrayNotified/setCloseToTrayNotified`, `confirmOnExit/setConfirmOnExit`, `systemTrayEnabled`, `useAlternatingRowColors`, `getRegexAsFilteringPatternForTransferList/set…`, `shutdownWhenDownloadsComplete`, `rebootWhenDownloadsComplete`, `suspendWhenDownloadsComplete`, `hibernateWhenDownloadsComplete`, `shutdownqBTWhenDownloadsComplete`, `preventFromSuspendWhenDownloading`, `preventFromSuspendWhenSeeding`, `isUpdateCheckEnabled`, plus the six filter-section state keys in §9.

## 13. Backend/engine API consumed by the shell

`BitTorrent::Session::instance()`:
- state/signals: `isPaused()`, `paused`, `resumed`, `statsUpdated`, `torrentsUpdated(QList<Torrent*>)`, `freeDiskSpaceChecked(qint64)`, `speedLimitModeChanged(bool)`.
- `status()` → `SessionStatus` (fields used: `hasIncomingConnections`, `dhtNodes`, `payloadDownloadRate`, `payloadUploadRate`, `totalPayloadDownload`, `totalPayloadUpload`).
- `isListening()`, `isDHTEnabled()`, `isQueueingSystemEnabled()`.
- `isAltGlobalSpeedLimitEnabled()`, `setAltGlobalSpeedLimitEnabled(bool)`, `downloadSpeedLimit()`, `uploadSpeedLimit()`.
- `freeDiskSpace()`, `lastExternalIPv4Address()`, `lastExternalIPv6Address()`, `torrents()`.
- Per-torrent (power mgmt): `isActive()`, `isFinished()`, `isStopped()`, `isErrored()`, `hasMetadata()`, `isMoving()`.

`GUIApplicationComponent`/`IGUIApplication` (`app()`): `addTorrentManager()->addTorrent(source)`, `desktopIntegration()` (menu/notifications/state/tooltip), `transferListWidget()`, `propertiesWidget()`.

`TransferListWidget` slots wired to actions: `startSelectedTorrents`, `stopSelectedTorrents`, `pauseSession`, `resumeSession`, `openSelectedTorrentsFolder`, `softDeleteSelectedTorrents`, `topQueuePosSelectedTorrents`, `increaseQueuePosSelectedTorrents`, `decreaseQueuePosSelectedTorrents`, `bottomQueuePosSelectedTorrents`, `applyFilter`, `applyStatusFilter`, `applyCategoryFilter`, `applyTagFilter`, `applyTrackerFilter`, `hideQueuePosColumn`, `getSourceModel`, `deleteVisibleTorrents`, `stopVisibleTorrents`, `startVisibleTorrents`, `forceStartVisibleTorrents`; signal `currentTorrentChanged`.

## 14. Window behaviors to preserve

- **Title** (`refreshWindowTitle`): base = `"qBittorrent " QBT_VERSION` + optional " — <suffix>". Paused → `"[PAUSED] %1"`. Speed-in-title → `"[D: %1, U: %2] %3"`.
- **Close** (`closeEvent`): if `closeToTray()` and tray active and not forced → hide instead of quit (one-time "closed to tray" notification). If `confirmOnExit()` and any active torrent → 3-button dialog "Exiting qBittorrent" ("Some files are currently transferring.\nAre you sure you want to quit qBittorrent?") with No / Yes / Always Yes (Always Yes sets `confirmOnExit=false`). macOS close = hide unless forced.
- **Minimize** (`event` WindowStateChange): if `minimizeToTray()` and tray active and no modal window → hide (one-time "minimized to tray" notification).
- **UI lock**: `on_actionLock_triggered` requires a password (prompts via `defineUILockPassword` if none), sets `Preferences::setUILocked(true)`, disables the tray menu, hides window. `unlockUI()` prompts and verifies via `Utils::Password::PBKDF2::verify`; min password length 3.
- **Power management** (`updatePowerManagementState`, 60 s `PREVENT_SUSPEND_INTERVAL` timer): sets `PowerManagement::ActivityState::Busy/Idle` based on `preventFromSuspendWhenDownloading`/`preventFromSuspendWhenSeeding` and torrent states.
- **Restart-required**: a `QFileSystemWatcher` on the executable → `notifyOfUpdate` shows `StatusBar::showRestartRequired()` and logs a CRITICAL message.
- **Update check** (Win/macOS): 24 h `QTimer`; `ProgramUpdater` → non-modal "qBittorrent Update Available" / "No updates available." dialogs.
- **Startup visibility**: depends on `WindowState initialState`, tray availability, `m_uiLocked`, and `minimizeToTray()` (shows/minimizes/hides accordingly). Geometry restored from `getMainGeometry()`; if none, centered on first show.

---

# Area: Transfer List (main torrent table, row context menu, and left filter sidebar)

## Transfer List — implementation-ready spec

Rebuild target: Qt6 QML + Material. This section covers the **main torrent table** (`TransferListWidget` = a `QTreeView` in list mode over `TransferListModel` -> `TransferListSortModel`, cells drawn by `TransferListDelegate`), the **right-click context menu**, and the **left filter sidebar** (`TransferListFiltersWidget` with Status / Categories / Tags / Trackers / Tracker-status sub-panels).

### Architecture (map to QML)
- **Source model** `TransferListModel` : `QAbstractListModel`, one row per `BitTorrent::Torrent*`, `NB_COLUMNS` columns. Backing store is a boost multi-index container (random-access + hashed-by-handle). In QML use a `QAbstractListModel` exposing one role per column plus `UnderlyingDataRole`/`AdditionalUnderlyingDataRole` equivalents, or a flat role set.
- **Proxy** `TransferListSortModel` : `QSortFilterProxyModel`. `setDynamicSortFilter(true)`, filter key column = `TR_NAME`, filter role = `Qt::DisplayRole`, sort role = `UnderlyingDataRole`, case-insensitive. Holds a `TorrentFilter m_filter` (status + category + tag + trackerHost + announceStatus + idSet + private). Does custom `compare()` per column and a **two-level sort** (primary column + remembered previous column as sub-sort; persisted as `TransferList/SubSortColumn` and `TransferList/SubSortOrder`).
- **Delegate** `TransferListDelegate`: default styled rendering except `TR_PROGRESS` which draws a **progress bar** (via a `ProgressBarPainter`). Bar is drawn "disabled" (greyed) when torrent state is `Error`, `StoppedDownloading`, or `Unknown`. If pref `getProgressBarFollowsTextColor()` is on, bar uses the row's `Qt::ForegroundRole` color. `sizeHint()` forces every row's height to at least the Name column height (icon+text).
- **View**: `setUniformRowHeights(true)`, `setRootIsDecorated(false)`, `setAllColumnsShowFocus(true)`, sorting enabled, `ExtendedSelection`, `DropOnly` drag-drop accepted, first header section movable, last section not stretched, header text elide right. Header state saved/restored via `Preferences::getTransHeaderState()/setTransHeaderState()` (this also persists column order, widths, sort indicator, hidden columns).

---

### 1. Column inventory (`TransferListModel::Column` enum order = default logical order)

Each column below lists: enum, header text (`Qt::DisplayRole` of headerData), the **display formatting** (`displayValue()`), the **raw sort value** (`internalValue()` under `UnderlyingDataRole`; alt value under `AdditionalUnderlyingDataRole`), alignment, and the source `Torrent` accessor. Columns marked **[hidden]** start hidden on first run (only shown if user enables). Right-aligned columns are noted; all others left-aligned.

| # | Enum | Header | Display format | Raw/sort value | Torrent API |
|---|------|--------|----------------|----------------|-------------|
| 0 | `TR_QUEUE_POSITION` | `#` | `queuePosition()+1` if ≥0 else `*` (right-align) | `queuePosition()` (int) | `queuePosition()` |
| 1 | `TR_NAME` | `Name` | torrent name; **carries the state icon** (DecorationRole) and is editable | `name()` (QString, natural sort) | `name()`, `setName()` |
| 2 | `TR_SIZE` | `Size` | `friendlyUnit(wantedSize())` (right) | `wantedSize()` | `wantedSize()` |
| 3 | `TR_TOTAL_SIZE` **[hidden]** | `Total Size` | `friendlyUnit(totalSize())` (right) | `totalSize()` | `totalSize()` (incl. unwanted files) |
| 4 | `TR_PROGRESS` | `Progress` | drawn as progress bar; text = `100%` if ≥1 else `%.1f%%` | `progress()*100` (real) | `progress()` |
| 5 | `TR_STATUS` | `Status` | status string per state (see §2); if `Error` appends `": " + error()` | `state()` (enum, sorted by int value) | `state()`, `error()` |
| 6 | `TR_SEEDS` | `Seeds` | `"<connected> (<total>)"` e.g. `2 (10)` (right) | `seedsCount()`; alt `totalSeedsCount()` | active vs total seeds |
| 7 | `TR_PEERS` | `Peers` | `"<connected> (<total>)"` (right) | `leechsCount()`; alt `totalLeechersCount()` | active vs total leechers |
| 8 | `TR_DLSPEED` | `Down Speed` | `friendlyUnit(rate, isSpeed=true)` e.g. `1.2 MiB/s` (right) | `downloadPayloadRate()` | payload DL rate |
| 9 | `TR_UPSPEED` | `Up Speed` | `friendlyUnit(rate, isSpeed=true)` (right) | `uploadPayloadRate()` | payload UL rate |
| 10 | `TR_ETA` | `ETA` | `userFriendlyDuration(eta, MAX_ETA)`; ∞ shown as blank/∞ when ≥MAX_ETA (right) | `eta()` | `eta()` |
| 11 | `TR_RATIO` | `Ratio` | `fromDouble(realRatio(),2)`; `C_INFINITY` (∞) when -1 or ≥`MAX_RATIO` (right) | `realRatio()` (real) | `realRatio()` |
| 12 | `TR_POPULARITY` **[hidden]** | `Popularity` (tooltip: "Ratio / Time Active (in months), indicates how popular the torrent is") | same ∞ rule, 2 decimals (right) | `popularity()` (real) | `popularity()` |
| 13 | `TR_CATEGORY` | `Category` | `category()` string (editable) | `category()` (natural sort) | `category()`, `setCategory()` |
| 14 | `TR_TAGS` | `Tags` | tags joined with `", "` | `tags()` (TagSet, natural pairwise compare) | `tags()` |
| 15 | `TR_ADD_DATE` **[hidden]** | `Added On` | `QLocale short` local datetime | `addedTime()` (QDateTime) | `addedTime()` |
| 16 | `TR_SEED_DATE` **[hidden]** | `Completed On` | `QLocale short` local datetime | `completedTime()` | `completedTime()` |
| 17 | `TR_TRACKER` **[hidden]** | `Tracker` | `currentTracker()` URL | `currentTracker()` (natural sort) | `currentTracker()` |
| 18 | `TR_DLLIMIT` **[hidden]** | `Down Limit` | `friendlyUnit(limit,true)` if >0 else `C_INFINITY` (∞) (right) | `downloadLimit()` | `downloadLimit()` |
| 19 | `TR_UPLIMIT` **[hidden]** | `Up Limit` | as above (right) | `uploadLimit()` | `uploadLimit()` |
| 20 | `TR_AMOUNT_DOWNLOADED` **[hidden]** | `Downloaded` | `friendlyUnit(totalDownload())` (right) | `totalDownload()` | total incl. wasted/protocol |
| 21 | `TR_AMOUNT_UPLOADED` **[hidden]** | `Uploaded` | `friendlyUnit(totalUpload())` (right) | `totalUpload()` | total uploaded ever |
| 22 | `TR_AMOUNT_DOWNLOADED_SESSION` **[hidden]** | `Session Downloaded` | `friendlyUnit(totalPayloadDownload())` (right) | `totalPayloadDownload()` | this-session DL |
| 23 | `TR_AMOUNT_UPLOADED_SESSION` **[hidden]** | `Session Uploaded` | `friendlyUnit(totalPayloadUpload())` (right) | `totalPayloadUpload()` | this-session UL |
| 24 | `TR_AMOUNT_LEFT` **[hidden]** | `Remaining` | `friendlyUnit(remainingSize())` (right) | `remainingSize()` | bytes left |
| 25 | `TR_TIME_ELAPSED` **[hidden]** | `Time Active` | `userFriendlyDuration(activeTime())`; if seeded, `"%1 (seeded for %2)"` with `finishedTime()` | `activeTime()`; alt `finishedTime()` | active/seeding time |
| 26 | `TR_SAVE_PATH` **[hidden]** | `Save Path` | `savePath().toString()` | `savePath()` (natural sort) | `savePath()`, `setSavePath()` |
| 27 | `TR_COMPLETED` **[hidden]** | `Completed` | `friendlyUnit(completedSize())` (right) | `completedSize()` | done bytes |
| 28 | `TR_RATIO_LIMIT` **[hidden]** | `Ratio Limit` | ratio-string of `effectiveShareLimits().ratioLimit` (∞ rule) (right) | same (real) | share limit |
| 29 | `TR_SEEN_COMPLETE_DATE` **[hidden]** | `Last Seen Complete` | `QLocale short` datetime | `lastSeenComplete()` | last seen complete |
| 30 | `TR_LAST_ACTIVITY` **[hidden]** | `Last Activity` | `"%1 ago"` with `userFriendlyDuration(timeSinceActivity())`; 0 shown as "< 1m ago" (right) | `timeSinceActivity()` | since last piece xfer |
| 31 | `TR_AVAILABILITY` **[hidden]** | `Availability` | `fromDouble(distributedCopies(),3)` or `N/A` if <0 (right) | `distributedCopies()` (real) | distributed copies |
| 32 | `TR_DOWNLOAD_PATH` **[hidden]** | `Incomplete Save Path` | `downloadPath().toString()` | `downloadPath()` (natural sort) | `downloadPath()` |
| 33 | `TR_INFOHASH_V1` **[hidden]** | `Info Hash v1` | hash hex or `N/A` if invalid | `infoHash().v1()` (SHA1Hash) | v1 hash |
| 34 | `TR_INFOHASH_V2` **[hidden]** | `Info Hash v2` | hash hex or `N/A` | `infoHash().v2()` (SHA256Hash) | v2 hash |
| 35 | `TR_REANNOUNCE` **[hidden]** | `Reannounce In` | `userFriendlyDuration(nextAnnounce())` (right) | `nextAnnounce()` | seconds to next announce |
| 36 | `TR_PRIVATE` **[hidden]** | `Private` | `Yes`/`No` if metadata present else `N/A` | `isPrivate()` (bool, only if `hasMetadata()`) | private flag |
| 37 | `TR_CREATE_DATE` **[hidden]** | `Created On` | `QLocale short` datetime | `creationDate()` | .torrent creation date |

Notes:
- **Right-aligned columns** (both header and cells): queue #, size, total size, ETA, seeds, peers, up/down speed, up/down limit, ratio, ratio-limit, popularity, all amount/completed/remaining, last activity, availability, reannounce.
- **Editable cells** (via `setData`, `Qt::DisplayRole`): `TR_NAME` (rename) and `TR_CATEGORY` only.
- **Tooltips** (`Qt::ToolTipRole`) show the full display value for: Name, Status, Category, Tags, Tracker, Save Path, Incomplete Save Path, Info Hash v1, Info Hash v2. Header tooltip only for Popularity.
- `TR_QUEUE_POSITION` column is **suppressed entirely** (skipped in header menu, hidable via `hideQueuePosColumn`) when `Session::isQueueingSystemEnabled()` is false.
- "At least one column always visible" invariant is enforced; if a saved column width is ≤0 it is auto-resized to contents.

### 1a. Hide-zero-values mode (`configure()` from prefs `getHideZeroValues()` + `getHideZeroComboValues()`)
Three modes: `Never`, `Stopped` (only blank zero values for stopped-downloading torrents), `Always`. When active, zero/negative numeric fields (speeds, amounts, limits, ratio, availability, reannounce, seeds/peers "0 (0)", ETA≥MAX, hashes if invalid, private=false) render as **empty string** instead of `0`/`∞`/`N/A`.

### 1b. Cell foreground color (state colors)
If pref `useTorrentStatesColors()` is on, each row's text color = `m_stateThemeColors[state]`, sourced from UI theme keys `TransferList.<StateName>` (e.g. `TransferList.Downloading`, `TransferList.StalledUploading`, `TransferList.Error`, `TransferList.Moving`, `TransferList.MissingFiles`, etc. — one per `TorrentState`).

---

### 2. Status strings & state icons (`TR_STATUS` text + `TR_NAME` decoration)

`state()` is `BitTorrent::TorrentState`. Status string map (`m_statusStrings`) and icon map (`getIconByState`):

| TorrentState(s) | Status text | Icon key (primary, fallback) |
|---|---|---|
| `Downloading` | "Downloading" | `downloading` |
| `ForcedDownloading` | (uses Downloading icon) | `downloading` |
| `DownloadingMetadata` | "Downloading metadata" | `downloading` |
| `ForcedDownloadingMetadata` | "[F] Downloading metadata" | `downloading` |
| `ForcedDownloading` (text) | "[F] Downloading" | — |
| `Uploading` / `StalledUploading` | "Seeding" | `upload`/`uploading` (Uploading), `stalledUP` (StalledUploading) |
| `ForcedUploading` | "[F] Seeding" | `upload`/`uploading` |
| `StalledDownloading` | "Stalled" | `stalledDL` |
| `QueuedDownloading` / `QueuedUploading` | "Queued" | `queued` |
| `CheckingDownloading` / `CheckingUploading` | "Checking" | `force-recheck`/`checking` |
| `CheckingResumeData` | "Checking resume data" | `force-recheck`/`checking` |
| `StoppedDownloading` | "Stopped" | `stopped`/`media-playback-pause` |
| `StoppedUploading` | "Completed" | `checked-completed`/`completed` |
| `Moving` | "Moving" | `set-location` |
| `MissingFiles` | "Missing Files" | `error` |
| `Error` | "Errored" (+ `": "+error()`) | `error` |

---

### 3. Row interactions

**Double-click** (`torrentDoubleClicked`) — action depends on finished state and prefs `getActionOnDblClOnTorrentFn()` (finished) / `getActionOnDblClOnTorrentDl()` (downloading). Action enum (`optionsdialog.h`): `TOGGLE_STOP=0`, `OPEN_DEST=1`, `PREVIEW_FILE=2`, `NO_ACTION=3`, `SHOW_OPTIONS=4`.
- `TOGGLE_STOP`: if stopped → `start()`, else `stop()`.
- `PREVIEW_FILE`: if torrent has previewable files → open Preview-select dialog, else open destination folder.
- `OPEN_DEST`: open destination folder (opens `contentPath()` or `savePath()`; single-file → reveal-in-folder, else open folder).
- `SHOW_OPTIONS`: open Torrent Options dialog.

**Keyboard shortcuts** (WidgetShortcut scope):
- `F2` → rename selected.
- Delete key (`Utils::KeySequence::deleteItem()`) → soft delete (keep files, with confirm).
- Shift+Delete (`permanentlyDeleteItem()`) → permanent delete (delete files).
- `Return` / `Enter` → double-click action.
- `Ctrl+R` → force recheck.
- `Ctrl+M` → force start.

**Drag & drop (drop only)**: accepts URLs/text. `.torrent`/magnet links → added via `addTorrentManager()->addTorrent()`. Other dropped files → open Torrent Creator dialog on first file. Shift+wheel = horizontal scroll.

**Selection → current torrent**: `currentChanged` emits `currentTorrentChanged(torrent)` (drives the properties panel elsewhere).

---

### 4. Column-visibility header menu (`displayColumnHeaderMenu`, right-click on header)
Title "Column visibility", tooltips visible. One **checkable** action per column (skips queue position when queueing disabled); label = column header text, tooltip = column tooltip. Unchecking is blocked if it would hide the last visible column. Checking a zero-width column auto-resizes it. Separator, then **"Resize columns"** (tooltip "Resize all non-hidden columns to the size of their contents") — resizes every non-hidden column to contents. All changes call `saveSettings()`.

---

### 5. Torrent row context menu (`displayListMenu`, right-click a row)

Actions are built once and shown conditionally based on a single pass computing aggregate flags over the selection (`needsStart`, `needsStop`, `needsForce`, `needsPreview`, `oneHasMetadata`, `oneNotFinished`, `allSameCategory`+`firstCategory`, `allSameAutoTMM`+`firstAutoTMM`, per-selection `tagsInAll`/`tagsInAny`, `allSameSuperSeeding`+`superSeedingMode`, `allSameSequentialDownloadMode`+`sequentialDownloadMode`, `allSamePrioFirstlast`+`prioritizeFirstLast`, `hasInfohashV1`, `hasInfohashV2`, `oneCanForceReannounce`).

**Menu order (top → bottom):**
1. **Start** (icon `torrent-start`) — shown if `needsStart`. `startSelectedTorrents()` → `torrent->start()`. *(shortcut text "&Start")*
2. **Stop** (icon `torrent-stop`) — shown if `needsStop`. `stopSelectedTorrents()` → `torrent->stop()`.
3. **Force Start** (icon `torrent-start-forced`) — shown if `needsForce`. `forceStartSelectedTorrents()` → `start(TorrentOperatingMode::Forced)`.
4. — separator —
5. **Remove** (icon `list-remove`) — `softDeleteSelectedTorrents()` → deletion-confirmation dialog (see §5a).
6. — separator —
7. **Set location…** (icon `set-location`) — folder chooser; on accept sets `setAutoTMMEnabled(false)` then `setSavePath(newLoc)` for each.
8. **Rename…** (icon `edit-rename`) — *only when exactly 1 selected*. Text input; newlines collapsed to space; writes via model `setData` Name.
9. **Manage content…** (icon `edit-rename`) — *only when exactly 1 selected*. Opens `TorrentContentLayoutDialog`.
10. **Edit trackers…** (icon `edit-rename`) — opens `TrackerEntriesDialog` seeded with trackers common to all selected; on accept `replaceTrackers()` on each.
11. **Category ►** submenu (icon `view-categories`) — see §5b.
12. **Tags ►** submenu (icon `tags`) — see §5c.
13. **Automatic Torrent Management** (TriState) — tooltip "Automatic mode means that various torrent properties (e.g. save path) will be decided by the associated category". Checked/unchecked/partial from `allSameAutoTMM`/`firstAutoTMM`. `setSelectedAutoTMMEnabled()`; enabling shows a confirm ("…They may be relocated.").
14. — separator —
15. **Torrent options…** (icon `configure`) — `setTorrentOptions()` opens `TorrentOptionsDialog` (per-torrent speed/ratio/etc.).
16. **Super seeding mode** (TriState) — shown only when *no selected torrent is unfinished* AND `oneHasMetadata`. State from `allSameSuperSeeding`/`superSeedingMode`. `setSuperSeeding()` (only on torrents with metadata).
17. — separator —
18. **Preview file…** (icon `view-preview`) — shown if `needsPreview` (any has metadata). Opens preview-select dialog per torrent; errors if no previewable files.
19. **Download in sequential order** (TriState) — shown if `oneNotFinished`. `setSequentialDownload()`.
20. **Download first and last pieces first** (TriState) — shown if `oneNotFinished`. `setFirstLastPiecePriority()`.
21. — separator (only if a preview/sequential action was added) —
22. **Force recheck** (icon `force-recheck`) — shown if `oneHasMetadata`. `recheckSelectedTorrents()` → `forceRecheck()` (optional confirm pref `confirmTorrentRecheck`).
23. **Force reannounce** (icon `reannounce`) — always shown; **enabled only if** `oneCanForceReannounce` (a torrent that is not stopped/queued/errored/checking). Disabled tooltip: "Can not force reannounce if torrent is Stopped/Queued/Errored/Checking". → `forceReannounce()` + `forceDHTAnnounce()`.
24. — separator —
25. **Open destination folder** (icon `directory`) — `openSelectedTorrentsFolder()`.
26. — separator (if queueing) —
27. **Queue ►** submenu (icon `queued`) — shown only if `Session::isQueueingSystemEnabled()` AND `oneNotFinished`. See §5d.
28. **Copy ►** submenu (icon `edit-copy`) — see §5e.
29. **Export .torrent…** (icon `edit-copy`) — tooltip "Exported torrent is not necessarily the same as the imported". Folder chooser; writes `<validName>.torrent` (dedup `(n)`), via `torrent->exportToFile()`; warns on errors.
30. **Export transfer list…** — the page action opens the scoped transfer-list
    export dialog for all session torrents; this context-menu action opens it
    for the current selection. The dialog offers JSON, JSONL, YAML, TOML, XML,
    CSV, TSV, Markdown, HTML, and SQL, discloses UTF-8/LF output and format
    coercion, and writes the 14-column summary through the QML
    `TransferController` bridge. This is export-only; no importer is implied.

#### 5a. Deletion-confirmation dialog
If pref `confirmTorrentDeletion()` on, open `DeletionConfirmationDialog(count, firstName, deleteLocalFiles)` (modal); on accept re-fetch selection and `removeTorrent(id, RemoveContent|KeepContent)` per `isRemoveContentSelected()`. Otherwise remove immediately. `TorrentRemoveOption::RemoveContent` vs `KeepContent`.

#### 5b. Category submenu
- **New…** (icon `list-add`) → `TorrentCategoryDialog::createCategory` then assign to selection.
- **Reset** (icon `edit-clear`) → set category to `""` (uncategorized).
- separator, then one action per existing category (from `Session::categories()`, natural-sorted, `&`→`&&` escaped, icon `view-categories`); action is **checked** if `allSameCategory` and it equals the selection's category. Clicking sets that category on all selected.

#### 5c. Tags submenu
- **Add…** (icon `list-add`) → comma-separated tag input (validates each tag; loops on invalid), adds each valid tag to selection.
- **Remove All** (icon `edit-clear`) → clears tags on all selected; if pref `confirmRemoveAllTags()` on, confirm first.
- separator, then one **TriStateAction** per existing `Session::tags()` (label via `tagToWidgetText`, stays open on interaction). State: Checked if in all selected, PartiallyChecked if in some, Unchecked if none. Toggling on → `addTag`; off → `removeTag`.

#### 5d. Queue submenu (only when queueing enabled)
- **Move to top** (icon `go-top`) → `topTorrentsQueuePos`.
- **Move up** (icon `go-up`) → `increaseTorrentsQueuePos`.
- **Move down** (icon `go-down`) → `decreaseTorrentsQueuePos`.
- **Move to bottom** (icon `go-bottom`) → `bottomTorrentsQueuePos`.
All take `extractIDs(getSelectedTorrents())` and only act if this is the current tab widget.

#### 5e. Copy submenu
- **Name** (icon `name`) → newline-joined `name()`.
- **Info hash v1** (icon `hash`) → joined valid v1 hashes; enabled only if `hasInfohashV1`.
- **Info hash v2** (icon `hash`) → v2 hashes; enabled only if `hasInfohashV2`.
- **Magnet link** (icon `torrent-magnet`) → joined `createMagnetURI()`.
- **Torrent ID** (icon `help-about`) → joined `id().toString()`.
- **Comment** (icon `edit-copy`) → non-empty `comment()` joined with `\n---------\n`.
- **Content Path** (icon `directory`) → joined non-empty `contentPath()`.

---

### 6. Left filter sidebar (`TransferListFiltersWidget`)

A vertically stacked, scrollable column of **collapsible section headers** (`TransferListFiltersWidgetItem`, a checkable/expandable header whose toggled(bool) both shows/hides the child widget and persists a Preference). Sections, in order:

1. **Status** — header text "Status"; expanded state pref `getStatusFilterState()/setStatusFilterState`. Toggling off applies the "All" filter.
2. **Categories** — "Categories"; pref `getCategoryFilterState()`. Toggling off clears the category filter; on re-applies current category.
3. **Tags** — "Tags"; pref `getTagFilterState()`. Toggling off clears tag filter.
4. **Tracker status** — "Tracker status"; pref `getTrackerStatusFilterState()`. **Only present when** pref `useSeparateTrackerStatusFilter()` is on (dynamically inserted/removed at position between Tags and Trackers when that pref changes).
5. **Trackers** — "Trackers"; pref `getTrackerFilterState()`; favicon download controlled by `setDownloadTrackerFavicon`.

Each sub-panel is a `QListWidget`/`QTreeView` sized exactly to content, no scrollbars, small icons. Each has a **custom context menu** and applies its selection to the transfer list via `TransferListWidget::applyStatusFilter / applyCategoryFilter / applyTagFilter / applyTrackerFilter / applyAnnounceStatusFilter`. Filters are ANDed in `TorrentFilter::match` (`matchStatus && matchHash && matchCategory && matchTag && matchPrivate && matchTracker`).

#### 6a. Status filter panel (`StatusFilterWidget`, rows fixed by `TorrentFilter::Status` order)
Rows (each shows a live count `Label (N)`), icon, and `TorrentFilter` semantics:

| Row idx | Label | Icon | Match semantics |
|---|---|---|---|
| 0 `All` | "All (N)" (N = total torrents) | `filter-all` | always true |
| 1 `Downloading` | "Downloading (N)" | `downloading` | `isDownloading()` |
| 2 `Seeding` | "Seeding (N)" | `upload`/`uploading` | `isUploading()` |
| 3 `Completed` | "Completed (N)" | `checked-completed` | `isCompleted()` |
| 4 `Running` | "Running (N)" | `torrent-start` | `isRunning()` (shown as **Running**, enum value `Running`) |
| 5 `Stopped` | "Stopped (N)" | `stopped` | `isStopped()` |
| 6 `Active` | "Active (N)" | `filter-active` | `isActive()` |
| 7 `Inactive` | "Inactive (N)" | `filter-inactive` | `isInactive()` |
| 8 `Stalled` | "Stalled (N)" | `filter-stalled` | state == StalledUploading OR StalledDownloading |
| 9 `StalledUploading` | "Stalled Uploading (N)" | `stalledUP` | state == StalledUploading |
| 10 `StalledDownloading` | "Stalled Downloading (N)" | `stalledDL` | state == StalledDownloading |
| 11 `Checking` | "Checking (N)" | `force-recheck` | Checking Up/Down/ResumeData |
| 12 `Moving` | "Moving (N)" | `set-location` | `isMoving()` |
| 13 `Errored` | "Errored (N)" | `error` | `isErrored()` |

- Counts maintained incrementally per torrent (`updateTorrentStatus` with a per-torrent bitset; `Stalled = StalledUploading + StalledDownloading`).
- Pref `getHideZeroStatusFilters()`: hide rows whose count is 0 (except All); if the current selection becomes hidden, revert to All.
- Selected row persisted via `getTransSelFilter()/setTransSelFilter()` (restored on startup; falls back to All if stored row is hidden).
- **Context menu**: Start torrents / Force start torrents / Stop torrents / Remove torrents — each acts on **currently visible** torrents (`startVisibleTorrents`, `forceStartVisibleTorrents`, `stopVisibleTorrents`, `deleteVisibleTorrents`).
- Applying a status filter also auto-selects the first row of the list if nothing selected.

#### 6b. Categories filter tree (`CategoryFilterWidget` over `CategoryFilterProxyModel`/`CategoryFilterModel`)
- Tree (supports nested subcategories via `/`); indentation auto-collapses to 0 when no subcategories exist.
- Special rows: **row 0 = "All"** (all categories), **row 1 = "Uncategorized"** (category == `""`). Rows below / any child = a real category; selecting emits `categoryChanged(categoryName)`.
- Each node shows its torrent count (`Qt::UserRole` = count); model auto-expands parents on insert.
- **Context menu**: **Add category…** (always); if a non-special row selected: **Add subcategory…**, **Edit category…**, **Remove category**; always: **Remove unused categories** (removes categories with count 0); separator; **Start / Force start / Stop / Remove torrents** (visible-torrents actions). Uses `TorrentCategoryDialog::createCategory/editCategory`, `Session::removeCategory`.

#### 6c. Tags filter list (`TagFilterWidget` over `TagFilterProxyModel`/`TagFilterModel`)
- Flat list (indentation 0). Special rows: **row 0 = "All"** (all tags → no filter), **row 1 = "Untagged"** (empty tag → torrents with no tags). Other rows = a real tag; selecting emits `tagChanged(std::optional<Tag>)`.
- Each row shows count (`Qt::UserRole`).
- **Context menu**: **Add tag…** (always; validates, warns on duplicate/invalid); if non-special selected: **Remove tag**; always: **Remove unused tags** (count 0); separator; **Start / Force start / Stop / Remove torrents** (visible-torrents actions). Uses `Session::addTag/removeTag`.

#### 6d. Trackers filter list (`TrackersFilterWidget`)
Special rows depend on `useSeparateTrackerStatusFilter`:
- Always: **row 0 "All (N)"** (icon `trackers`), **row 1 "Trackerless (N)"** (icon `trackerless`, host == `""`).
- When tracker-status is **not** separated (`m_handleTrackerStatuses` true), three extra status rows are inserted at rows 1–3 (before host rows): **"Tracker error (N)"** (`tracker-error`), **"Other error (N)"** (`tracker-error`), **"Warning (N)"** (`tracker-warning`).
- Below special rows: one row **per tracker host**, "`host (N)`", natural-sorted, with a **downloaded favicon** as icon (fetched from `scheme://faviconHost/favicon.ico`, `.ico` failure retries `.png`; only if `m_downloadTrackerFavicon`; temp icon files cleaned up on destroy). Host derived via `getTrackerHost(url)` (QUrl host).
- Counts maintained incrementally on `trackersAdded/Removed/Reset` and `trackerEntryStatusesUpdated` session signals; trackerless bucket adjusted when a torrent gains/loses all trackers; host rows auto-removed when count hits 0.
- **applyFilter(row)** maps: All → clear tracker + announce filters; Trackerless → `applyTrackerFilter("")`; (status rows, when merged) → `applyAnnounceStatusFilter(HasOtherError/HasTrackerError/HasWarning)`; host row → `applyTrackerFilter(hostname)`.
- **Context menu**: if a host row selected: **Remove tracker** (removes that tracker from *all* torrents; confirm dialog with "Don't ask me again" tied to pref `confirmRemoveTrackerFromAllTorrents`) + separator; then **Start / Force start / Stop / Remove torrents** (visible-torrents actions).

#### 6e. Tracker-status filter panel (`TrackerStatusFilterWidget`, only in separate mode)
Fixed rows: **0 "All (N)"** (`trackers`), **1 "Warning (N)"** (`tracker-warning`), **2 "Tracker error (N)"** (`tracker-error`), **3 "Other error (N)"** (`tracker-error`). Selecting applies `applyAnnounceStatusFilter(nullopt / HasWarning / HasTrackerError / HasOtherError)`. Counts from each torrent's `announceStatus()` flags (`TorrentAnnounceStatusFlag::HasWarning/HasTrackerError/HasOtherError`), maintained on tracker signals. Context menu = Start/Force start/Stop/Remove visible torrents.

---

### 7. Sorting details (`TransferListSortModel::compare`)
Per-column comparison (sort role = `UnderlyingDataRole`):
- Natural string compare: Name, Category, Save Path, Incomplete Save Path, Tracker.
- Hash compare: Info hash v1/v2 (three-way on hash).
- Tags: pairwise natural compare then size.
- Signed long-long, "negative = invalid sorts last": amounts, completed, left, ETA, last activity, reannounce, size, time active, total size.
- Real, invalid-last: availability, progress, ratio, ratio limit, popularity.
- Int three-way: status (by enum int), queue position, dl/up speed, dl/up limit.
- Bool w/ validity: private.
- Seeds/Peers: compare active count first, then total (`AdditionalUnderlyingDataRole`).
- **Sub-sort**: ties broken by the previously-sorted column (`m_subSortColumn`), with sign handling when the two orders differ. Persisted in `TransferList/SubSortColumn` / `TransferList/SubSortOrder`.

---

### 8. Session/engine API surface consumed (for the QML backend bridge)
`BitTorrent::Session::instance()`: `torrents()`, `torrentsCount()`, `pause()`, `resume()`, `removeTorrent(id, TorrentRemoveOption)`, `increase/decrease/top/bottomTorrentsQueuePos(idList)`, `isQueueingSystemEnabled()`, `categories()`, `removeCategory()`, `tags()`, `addTag()`, `removeTag()`. Signals driving live updates: `torrentsLoaded`, `torrentAboutToBeRemoved`, `torrentsUpdated`, `torrentFinished`, `torrentMetadataReceived`, `torrentStarted`, `torrentStopped`, `torrentFinishedChecking`, `trackerEntryStatusesUpdated`, `trackersAdded`, `trackersRemoved`, `trackersReset`.

`BitTorrent::Torrent`: all accessors in the column table plus `start()/start(Forced)/stop()`, state predicates (`isStopped/isFinished/isForced/isErrored/hasMissingFiles/isChecking/isQueued/isRunning/isDownloading/isUploading/isCompleted/isActive/isInactive/isMoving`), `forceRecheck()`, `forceReannounce()`, `forceDHTAnnounce()`, `setSuperSeeding()/superSeeding()`, `setSequentialDownload()/isSequentialDownload()`, `setFirstLastPiecePriority()/hasFirstLastPiecePriority()`, `setAutoTMMEnabled()/isAutoTMMEnabled()`, `setSavePath()`, `setCategory()`, `addTag()/removeTag()/clearTags()/hasTag()`, `createMagnetURI()`, `id()`, `comment()`, `contentPath()`, `filePaths()/filesCount()`, `exportToFile()`, `trackers()/replaceTrackers()/removeTrackers()`, `announceStatus()`, `belongsToCategory()`.

### 9. Preference keys touched by this area
`getTransHeaderState/setTransHeaderState` (column layout), `getTransSelFilter/setTransSelFilter` (status row), `getStatusFilterState/getCategoryFilterState/getTagFilterState/getTrackerFilterState/getTrackerStatusFilterState` (+ setters, section expanded state), `useSeparateTrackerStatusFilter`, `getHideZeroStatusFilters`, `getHideZeroValues`+`getHideZeroComboValues`, `useTorrentStatesColors`, `getProgressBarFollowsTextColor`, `getRegexAsFilteringPatternForTransferList` (search box interprets pattern as regex vs wildcard), `confirmTorrentDeletion`, `confirmTorrentRecheck`, `confirmRemoveAllTags`, `confirmRemoveTrackerFromAllTorrents`, `getActionOnDblClOnTorrentFn`, `getActionOnDblClOnTorrentDl`. Sub-sort: `TransferList/SubSortColumn`, `TransferList/SubSortOrder`.

Key file paths: `src/gui/transferlistwidget.{h,cpp}`, `transferlistmodel.{h,cpp}`, `transferlistsortmodel.{h,cpp}`, `transferlistdelegate.{h,cpp}`, `transferlistfilterswidget.{h,cpp}`, `transferlistfilters/{statusfilterwidget,categoryfilterwidget,tagfilterwidget,trackersfilterwidget,trackerstatusfilterwidget,basefilterwidget}.{h,cpp}`, and `src/base/torrentfilter.{h,cpp}`.

---

# Area: Torrent Properties Panel (src/gui/properties/* and src/gui/trackerlist/*)

# Torrent Properties Panel — Implementation-Ready Spec

Source of truth: `src/gui/properties/*`, `src/gui/trackerlist/*`, plus the Content tab widget in `src/gui/torrentcontentwidget.*` and content model in `src/gui/torrentcontentmodel*.*`. Backend consumed via `BitTorrent::Torrent` (`src/base/bittorrent/torrent.h`), `BitTorrent::PeerInfo` (`peerinfo.h`), `BitTorrent::TrackerEntry`/`TrackerEntryStatus` (`trackerentry.h`, `trackerentrystatus.h`), `BitTorrent::TorrentContentHandler` (`torrentcontenthandler.h`).

---

## 1. Container: `PropertiesWidget` + `PropTabBar`

**Files:** `propertieswidget.{h,cpp,ui}`, `proptabbar.{h,cpp}`

Layout is a vertical stack: a `QStackedWidget` (`stackedProperties`) on top, and a horizontal tab-button bar (`PropTabBar`) below it. The whole widget lives inside the main window's vertical `QSplitter` as the bottom pane; clicking the already-selected tab collapses the pane (slide behavior).

### PropTabBar (`proptabbar.cpp`)
A `QHBoxLayout` of exclusive `QPushButton`s in a `QButtonGroup`. Enum `PropertyTab` order = stacked-widget page index:
| Index | enum | Button label | Icon | Shortcut |
|---|---|---|---|---|
| 0 | `MainTab` | `General` | `help-about`/`document-properties` | Alt+G |
| 1 | `TrackersTab` | `Trackers` | `trackers`/`network-server` | Alt+C |
| 2 | `PeersTab` | `Peers` | `peers` | Alt+R |
| 3 | `URLSeedsTab` | `HTTP Sources` | `network-server` | Alt+B |
| 4 | `FilesTab` | `Content` | `directory` | Alt+Z |
| — | (spacer, expanding) | | | |
| 5 | `SpeedTab` | `Speed` | `chart-line` | Alt+D |

Signals: `tabChanged(int)` → `stackedProperties.setCurrentIndex`; `visibilityToggled(bool)` → `setVisibility`. Selecting current tab again emits `visibilityToggled(false)` and sets `m_currentIndex=-1` (collapse). `setCurrentIndex`: clicking already-active tab collapses; from collapsed state emits `visibilityToggled(true)`.

### Slide/visibility (`setVisibility`)
- Collapsed (`REDUCED`): hides `stackedProperties`, stores splitter sizes, hides splitter handle(1), sets handle width 0, forces panel max height to tab-bar height.
- Expanded (`VISIBLE`): restores handle + sizes, forces refresh via `loadDynamicData()`.

### Data lifecycle
- `loadTorrentInfos(Torrent*)`: `clear()`, set torrent on child widgets (`m_downloadedPieces`, `m_piecesAvailability`, `m_trackerList`, `filesList` via `setContentHandler`, `m_peerList`). Sets static General-tab fields (see §2). Calls `loadUrlSeeds()`, then `loadDynamicData()`.
- `loadDynamicData()`: only runs if torrent valid AND state==VISIBLE; switches on `stackedProperties.currentIndex()`: `MainTab` refreshes all transfer/info dynamic fields + pieces bars; `PeersTab` → `m_peerList->loadPeers(torrent)`; `FilesTab` → `filesList->refresh()`. Wired to `QStackedWidget::currentChanged` so switching tab refreshes.
- Save/restore via `readSettings()`/`saveSettings()` (see Settings keys below).
- `reloadPreferences()`: `peerList->updatePeerHostNameResolutionState()`, `updatePeerCountryResolutionState()`.
- `configure()` (on `Preferences::changed`): sets content drag enabled; swaps Speed tab between real `SpeedWidget` and a placeholder `QLabel` ("Speed graphs are disabled / You can enable it in Advanced Options") based on `isSpeedWidgetEnabled()`.

### Settings keys (from `preferences.cpp`)
- `TorrentProperties/SplitterSizes` (QString "a,b")
- `TorrentProperties/CurrentTab` (int, default -1)
- `TorrentProperties/Visible` (bool, default false)
- `GUI/Qt6/TorrentProperties/FilesListState` (QByteArray header state)
- `GUI/Qt6/TorrentProperties/PeerListState` (QByteArray)
- `GUI/Qt6/TorrentProperties/TrackerListState` (QByteArray)
- `GUI/PropertiesWidget/FilterPatternFormat` (content filter format enum)
- `SpeedWidget/Enabled` (bool default true), `SpeedWidget/period` (int default 1), `SpeedWidget/graph_enable_%1` (per graph id; UP=0/DOWN=1 default true)
- `Preferences/Connection/ResolvePeerCountries`, `Preferences/Connection/ResolvePeerHostNames`
- `Preferences/General/TorrentContentDragEnabled`, `Preferences/General/HideZeroValues`, `Preferences/General/HideZeroComboValues`

---

## 2. General Tab (`pageGeneral`)

`QScrollArea` containing three groups. All value labels are PlainText except Comment (RichText). All static setup is in `loadTorrentInfos`; dynamic values updated each `loadDynamicData()` MainTab pass. `clear()` empties every `*Val` label.

### 2a. Pieces bars group (`groupBar`, grid)
Two rows, each: right-aligned caption label, the bar widget (col 1), a value label (col 2). A horizontal `Line` (`lineBelowBars`) separates from Transfer group.
- Row 0: `Progress:` → `DownloadedPiecesBar` → `labelProgressVal` (e.g. `93.5%`).
- Row 1: `Availability:` → `PieceAvailabilityBar` → `labelAverageAvailabilityVal` (distributed copies, 3 decimals).
- Visibility toggled by `showPiecesDownloaded(bool)` / `showPiecesAvailability(bool)`. Availability shown only when torrent hasMetadata AND not finished/stopped/queued/checking.

### 2b. Transfer group (`groupTransferBox`, title "Transfer", 6-col grid, label:value pairs)
| UI label | Value object | Source (Torrent API) & format |
|---|---|---|
| `Time Active:` | labelElapsedVal | `activeTime()`; if `isFinished()`: `"%1 (seeded for %2)".arg(userFriendlyDuration(activeTime()), userFriendlyDuration(finishedTime()))` |
| `ETA:` | labelETAVal | `userFriendlyDuration(eta(), MAX_ETA)` |
| `Connections:` | labelConnectionsVal | `"%1 (%2 max)".arg(connectionsCount()).arg(connectionsLimit()<0 ? ∞ : connectionsLimit())` |
| `Downloaded:` | labelDlTotalVal | `"%1 (%2 this session)".arg(friendlyUnit(totalDownload()), friendlyUnit(totalPayloadDownload()))` |
| `Uploaded:` | labelUpTotalVal | `"%1 (%2 this session)".arg(friendlyUnit(totalUpload()), friendlyUnit(totalPayloadUpload()))` |
| `Seeds:` | labelSeedsVal | `"%1 (%2 total)".arg(seedsCount(), totalSeedsCount())` |
| `Download Speed:` | labelDlSpeedVal | `"%1 (%2 avg.)".arg(friendlyUnit(downloadPayloadRate(),true), dlAvg)` where dlAvg=totalDownload()/(activeTime()-finishedTime()) |
| `Upload Speed:` | labelUpSpeedVal | `"%1 (%2 avg.)"` with ulAvg=totalUpload()/activeTime() |
| `Peers:` | labelPeersVal | `"%1 (%2 total)".arg(leechsCount(), totalLeechersCount())` |
| `Download Limit:` | labelDlLimitVal | `downloadLimit()<=0 ? ∞ : friendlyUnit(downloadLimit(),true)` |
| `Upload Limit:` | labelUpLimitVal | `uploadLimit()<=0 ? ∞ : friendlyUnit(uploadLimit(),true)` |
| `Wasted:` | labelWastedVal | `friendlyUnit(wastedSize())` |
| `Share Ratio:` | labelShareRatioVal | `realRatio()`; `≥ MAX_RATIO ? ∞ : fromDouble(ratio,2)` |
| `Reannounce In:` | labelReannounceInVal | `userFriendlyDuration(nextAnnounce())` |
| `Last Seen Complete:` | labelLastSeenCompleteVal | `lastSeenComplete()` localized short, else `Never` |
| `Popularity:` | labelPopularityVal | `popularity()`; `≥ MAX_RATIO ? ∞ : fromDouble(popularity,2)`. Tooltip: "Ratio / Time Active (in months), indicates how popular the torrent is" |

`C_INFINITY` (∞) from `base/unicodestrings.h`. `MAX_RATIO = Torrent::MAX_RATIO`.

### 2c. Information group (`groupInfosBox`, title "Information", 6-col grid)
| UI label | Value object | Source & format |
|---|---|---|
| `Total Size:` | labelTotalSizeVal | `friendlyUnit(totalSize())` (metadata only) |
| `Pieces:` | labelTotalPiecesVal | `"%1 x %2 (have %3)".arg(piecesCount()).arg(friendlyUnit(pieceLength())).arg(piecesHave())` |
| `Created By:` | labelCreatedByVal | `creator()` |
| `Added On:` | labelAddedOnVal | `addedTime()` localized short |
| `Completed On:` | labelCompletedOnVal | `completedTime()` localized short (empty if invalid) |
| `Created On:` | labelCreatedOnVal | `creationDate()` localized short |
| `Private:` | labelPrivateVal | `isPrivate() ? Yes : No`; `N/A` when no metadata (selectable text) |
| `Info Hash v1:` | labelInfohash1Val | `infoHash().v1()` valid → toString(), else `N/A` (selectable) |
| `Info Hash v2:` | labelInfohash2Val | `infoHash().v2()` valid → toString(), else `N/A` (selectable) |
| `Save Path:` | labelSavePathVal | `savePath().toString()`, wordWrap, selectable; updated live via `Session::torrentSavePathChanged` → `updateSavePath` |
| `Comment:` | labelCommentVal | `parseHtmlLinks(comment().toHtmlEscaped())`, RichText, `openExternalLinks=true`, TextBrowserInteraction |

**Backend API read:** `infoHash()`, `creationDate()`, `totalSize()`, `comment()`, `creator()`, `isPrivate()`, `hasMetadata()`, `savePath()`, `wastedSize()`, `totalUpload/Download()`, `totalPayloadUpload/Download()`, `upload/downloadLimit()`, `activeTime()`, `finishedTime()`, `isFinished()`, `connectionsCount/Limit()`, `eta()`, `nextAnnounce()`, `realRatio()`, `popularity()`, `seedsCount()`, `totalSeedsCount()`, `leechsCount()`, `totalLeechersCount()`, `downloadPayloadRate()`, `uploadPayloadRate()`, `lastSeenComplete()`, `completedTime()`, `addedTime()`, `piecesCount()`, `pieceLength()`, `piecesHave()`, `progress()`, `distributedCopies()`, `pieces()`, plus async `fetchPieceAvailability()`→`QList<int>`, `fetchDownloadingPieces()`→`QBitArray`, `fetchURLSeeds()`→`QList<QUrl>`. States checked: `isFinished/isStopped/isQueued/isChecking`.

---

## 3. Pieces Bars (`PiecesBar` base + `DownloadedPiecesBar` + `PieceAvailabilityBar`)

**Files:** `piecesbar.{h,cpp}`, `downloadedpiecesbar.{h,cpp}`, `pieceavailabilitybar.{h,cpp}`.

Custom `QWidget` painting a 1px-bordered horizontal bar (fixed height 18px, expanding width). Renders a `QImage` scaled to widget width; hover highlights a region (`highlightFile`) with tooltip. Colors from theme via `backgroundColor/borderColor/pieceColor/highlightedPieceColor/colorBoxBorderColor`; 256-level gradient `pieceColors()`; `mixTwoColors(rgb1,rgb2,ratio)`.
- **DownloadedPiecesBar** `setProgress(QBitArray pieces, QBitArray downloadedPieces)`: completed pieces in piece color, in-progress in a distinct `m_dlPieceColor`. `bitfieldToFloatVector` scales bitfield to widget pixel columns.
- **PieceAvailabilityBar** `setAvailability(QList<int> avail)`: shading proportional to availability count; `intToFloatVector` scaling.
- Both implement `renderImage()`, `simpleToolTipText()`, `clear()`.

QML rebuild: a `Canvas`/custom-painted item bound to `pieces`/`downloadingPieces`/`availability` arrays; a hover tooltip. Material equivalent: thin segmented bar.

---

## 4. Trackers Tab (`pageTrackers`)

**Files:** `trackerlist/trackerlistwidget.{h,cpp}`, `trackerlistmodel.{h,cpp}`, `trackerlistsortmodel.{h,cpp}`, `trackerlistitemdelegate.{h,cpp}`.

Layout: `TrackerListWidget` (a `QTreeView`) + a right-side vertical button column with `trackerUpButton` (icon `go-up`) and `trackerDownButton` (icon `go-down`) between two vertical spacers. Up button → `decreaseSelectedTrackerTiers`; Down → `increaseSelectedTrackerTiers`.

### Tree model (`TrackerListModel`, `QAbstractItemModel`, hierarchical)
Top-level rows: 3 sticky rows first, then one row per tracker. Tracker rows have child rows = per-endpoint announce statuses (name + BT protocol version). Sticky rows (`StickyRow`): `ROW_DHT=0` `** [DHT] **`, `ROW_PEX=1` `** [PeX] **`, `ROW_LSD=2` `** [LSD] **` (grey foreground via `QColorConstants::Svg::grey`).

**Columns (`TrackerListColumn`):**
| Index | enum | Header text | Right-aligned |
|---|---|---|---|
| 0 | COL_URL | `URL/Announce Endpoint` | no |
| 1 | COL_TIER | `Tier` | yes |
| 2 | COL_PROTOCOL | `BT Protocol` | yes (hidden when libtorrent2: `setColumnHidden(COL_PROTOCOL,true)`) |
| 3 | COL_STATUS | `Status` | no |
| 4 | COL_PEERS | `Peers` | yes |
| 5 | COL_SEEDS | `Seeds` | yes |
| 6 | COL_LEECHES | `Leeches` | yes |
| 7 | COL_TIMES_DOWNLOADED | `Times Downloaded` | yes |
| 8 | COL_MSG | `Message` | no |
| 9 | COL_NEXT_ANNOUNCE | `Next Announce` | yes |
| 10 | COL_MIN_ANNOUNCE | `Min Announce` | yes |

Cell semantics per row type:
- URL = item name (tracker URL, endpoint name, or sticky label).
- Tier = `tier` for tracker rows only (blank for sticky + endpoints).
- BT Protocol = `v<btVersion>` for endpoint rows only.
- Status: endpoints → `statusText()`; sticky → `statusDHT/PeX/LSD(torrent)` which returns `Disabled` (session off), `Disabled for this torrent` (private or per-torrent disabled), or `Working`; trackers → `statusText()`.
- `statusText()` maps `TrackerEndpointState` → `Working`/`Not working`/`Tracker error`/`Unreachable`/`Not contacted yet`; `Updating...` when `isUpdating`; invalid → `Invalid state!`.
- Peers/Seeds/Leeches/Times Downloaded = `prettyCount(val)` = number, or `N/A` if `val==-1`.
- Message = `message`. DHT/PeX/LSD message = `This torrent is private` when private.
- Next/Min Announce = `userFriendlyDuration(secsToNextAnnounce / secsToMinAnnounce, -1, TimeResolution::Seconds)`; recomputed every 4s (`ANNOUNCE_TIME_REFRESH_INTERVAL`, single-shot `QTimer` → `refreshAnnounceTimes`).
- Sort role = `TrackerListModel::SortRole` (Qt::UserRole); returns raw numeric/string per column. **`TrackerListSortModel`** keeps the 3 sticky rows pinned to top regardless of sort order/direction.

**Item delegate** (`TrackerListItemDelegate`): when a tracker row is expanded, clears the display text of COL_PEERS/SEEDS/LEECHES/TIMES_DOWNLOADED/MSG/NEXT_ANNOUNCE/MIN_ANNOUNCE on the parent (values shown on the endpoint children instead).

### Model live updates (Session signals)
`trackersAdded` → `onTrackersAdded`; `trackersRemoved` → `onTrackersRemoved`; `trackersReset` → `onTrackersChanged`; `trackerEntryStatusesUpdated(QHash<QString,TrackerEntryStatus>)` → `onTrackersUpdated`. Sticky DHT/PeX/LSD seed+peer counts computed from `torrent->fetchPeerInfo()` counting peers with `fromDHT()/fromPeX()/fromLSD()` split by `isSeed()`, skipping `isConnecting()`.

### View behavior
Sorting enabled, extended selection, uniform row heights, expandsOnDoubleClick=false, first section movable, last section not stretched, elide right. Double-click → `editSelectedTracker`. Shift+wheel = horizontal scroll. `setModel()` is blocked (assert). Column state persisted to `GUI/Qt6/TorrentProperties/TrackerListState`.

### Context menu (`showTrackerListMenu`)
Always: **Add trackers...** (icon `list-add`) → `openAddTrackersDialog`.
If ≥1 real tracker row selected (sticky rows excluded by `getSelectedTrackerRows`):
- **Edit tracker URL...** (`edit-rename`) → `editSelectedTracker`
- **Remove tracker** (`edit-clear`/`list-remove`) → `deleteSelectedTrackers`
- **Copy tracker URL** (`edit-copy`) → `copyTrackerUrl`
- **Force reannounce to selected trackers** (`reannounce`/`view-refresh`) → `reannounceSelected` (only if not stopped)
If not stopped: separator + **Force reannounce to all trackers** → `torrent->forceReannounce(); torrent->forceDHTAnnounce()`.

Header right-click → **Column visibility** menu (checkable per column, min 1 visible) + **Resize columns**.

### Hotkeys
F2 → edit; Delete (`Utils::KeySequence::deleteItem()`) → remove; Ctrl+C → copy URL.

### Actions / backend API
- `getSelectedTrackerRows()` filters out child rows and sticky rows.
- Tier up/down: read `torrent->trackers()` (`QList<TrackerEntryStatus>`), build `QList<TrackerEntry>{url,tier}` decrement/increment tier (clamp ≥0 / ≤max), `torrent->replaceTrackers(adjusted)`.
- Edit: `AutoExpandableDialog::getText` for new URL; validates non-empty valid `QUrl`, no duplicate, then `replaceTrackers`.
- Remove: `torrent->removeTrackers(QStringList urls)`.
- Copy: URLs joined by newline to clipboard.
- Reannounce selected: `torrent->forceReannounce(index)` per matching tracker index; DHT row → `torrent->forceDHTAnnounce()`.
- **TrackerEntry** struct: `{QString url; int tier=0}`. **TrackerEntryStatus**: `url, tier, isUpdating, state (TrackerEndpointState), message, numPeers, numSeeds, numLeeches, numDownloaded, nextAnnounceTime, minAnnounceTime, QHash<pair<QString,int>,TrackerEndpointStatus> endpoints`. **TrackerEndpointStatus**: adds `name, btVersion`. **TrackerEndpointState** enum: `NotContacted=1, Working=2, NotWorking=4, TrackerError=5, Unreachable=6`.

### AddTrackersDialog (`trackersadditiondialog.*`)
Modal `QDialog` title "Add trackers". Widgets: label "List of trackers to add (one per line):", multiline `QTextEdit` (`textEditTrackersList`, no wrap, plain text), label "µTorrent compatible list URL:", `QLineEdit` (`lineEditListURL`) + `QPushButton` download (tooltip "Download trackers list") which fetches a remote list and appends, OK/Cancel. On accept → `torrent->addTrackers(parseTrackerEntries(text))`. Persists dialog size + last list URL.

---

## 5. Peers Tab (`pagePeers`)

**Files:** `peerlistwidget.{h,cpp}`, `peerlistsortmodel.{h,cpp}`, `peersadditiondialog.{h,cpp,ui}`.

`PeerListWidget` is a `QTreeView` over a `QStandardItemModel` (flat rows) wrapped by `PeerListSortModel`. `loadPeers(torrent)` uses async `torrent->fetchPeerInfo()` → `QList<PeerInfo>`; rows keyed by `PeerEndpoint {PeerAddress address; QString connectionType}`. I2P peers reloaded fully each pass; stale peers removed.

**Columns (`PeerListColumns`):**
| Index | enum | Header text | Notes |
|---|---|---|---|
| 0 | COUNTRY | `Country/Region` | flag icon (DecorationRole); hidden unless ResolvePeerCountries |
| 1 | IP | `IP/Address` | display = IP or resolved hostname or I2P address; tooltip = IP |
| 2 | PORT | `Port` | right-aligned; `N/A` for I2P |
| 3 | CONNECTION | `Connection` | `PeerInfo::connectionType()` |
| 4 | FLAGS | `Flags` | `flags()`; tooltip `flagsDescription()` |
| 5 | CLIENT | `Client` | `client()` (html-escaped) |
| 6 | PEERID_CLIENT | `Peer ID Client` | `peerIdClient()`; hidden by default |
| 7 | PROGRESS | `Progress` | `fromDouble(progress()*100,1)+"%"`, right |
| 8 | DOWN_SPEED | `Down Speed` | `friendlyUnit(payloadDownSpeed(),true)`, right |
| 9 | UP_SPEED | `Up Speed` | `friendlyUnit(payloadUpSpeed(),true)`, right |
| 10 | TOT_DOWN | `Downloaded` | `friendlyUnit(totalDownload())`, right |
| 11 | TOT_UP | `Uploaded` | `friendlyUnit(totalUpload())`, right |
| 12 | RELEVANCE | `Relevance` | `fromDouble(relevance()*100,1)+"%"`, right |
| 13 | DOWNLOADING_PIECE | `Files` | files for `downloadingPieceIndex()` joined by `;`; tooltip joined by newline |
| 14 | CONTRIBUTION | `Contribution` | computed % = totalUpload/(progress*totalSize), right |
| 15 | IP_HIDDEN | (hidden) | raw IP string for ban/copy; always hidden |
| 16 | COL_COUNT | (hidden) | |

Note the display order differs from enum: header setup registers CONNECTION after FLAGS but column index order is as above; sortable via `PeerListSortModel` (natural compare for IP + CLIENT via `UnderlyingDataRole`; COUNTRY sorts by tooltip country name). Zero-value hiding: when `HideZeroValues && HideZeroComboValues==0`, speed/total cells with ≤0 render empty.

`hideZeroValues` gating, right-align via TextAlignmentRole, `UnderlyingDataRole` (=Qt::UserRole in `PeerListSortModel`) holds raw sortable value. Hostname resolution via `Net::ReverseResolution` when `ResolvePeerHostNames`; country flag via `UIThemeManager::getFlagIcon(country())` + `Net::GeoIPManager::CountryName` when `ResolvePeerCountries`.

### View behavior
Root not decorated, not expandable, uniform rows, extended selection, no edit triggers, first section movable, last section not stretched, elide right, sorting enabled. IP_HIDDEN + COL_COUNT hidden; PEERID_CLIENT hidden by default (only if no saved column state). At least one visible column enforced. Shift+wheel horizontal scroll. Column state persisted to `GUI/Qt6/TorrentProperties/PeerListState`.

### Context menu (`showPeerListMenu`)
- **Add peers...** (icon `peers-add`) → opens AddPeersDialog, then `torrent->connectPeer(addr)` per parsed peer; info box on partial/complete success. Disabled with tooltip when: private ("Cannot add peers to a private torrent"), checking ("...when the torrent is checking"), queued ("...when the torrent is queued").
- **Copy IP:port** (`edit-copy`) → `copySelectedPeers` (IPv6 wrapped in `[]`). Disabled ("No peer was selected") if no selection.
- separator
- **Ban peer permanently** (`peers-remove`) → `banSelectedPeers`: confirm dialog, then `Session::instance()->banIP(ip)` per selected IP (from IP_HIDDEN col) + log; reload. Disabled if no selection.

Header right-click → **Column visibility** (checkable; COUNTRY entry skipped when countries disabled; min 1 visible) + **Resize columns**.

### Hotkeys
Ctrl+C → copy peers; Delete → ban peers.

### AddPeersDialog (`peersadditiondialog.*`)
`QDialog` title "Add Peers". Label "List of peers to add (one IP per line):", `QTextEdit` (`textEditPeers`, no wrap, plain, placeholder "Format: IPv4:port / [IPv6]:port"), OK/Cancel. `validateInput`: split lines, `BitTorrent::PeerAddress::parse(line)`; warn on empty/invalid; returns `QList<PeerAddress>` via static `askForPeers(parent)`.

### PeerInfo API read
`address()`→PeerAddress{ip,port}, `connectionType()`, `useI2PSocket()`, `I2PAddress()`, `client()`, `peerIdClient()`, `payloadDownSpeed()`, `payloadUpSpeed()`, `totalDownload()`, `totalUpload()`, `progress()`, `flags()`, `flagsDescription()`, `relevance()`, `country()`, `downloadingPieceIndex()`, plus `fromDHT/fromPeX/fromLSD/isSeed/isConnecting` (used by Trackers sticky rows). Files for piece via `torrent->info().filesForPiece(index)`.

---

## 6. HTTP Sources Tab (`pageSources`)

**File:** `propertieswidget.cpp` (web-seed logic inline).

A `QListWidget` (`listWebSeeds`, extended selection, custom context menu). Populated by `loadUrlSeeds()` = async `torrent->fetchURLSeeds()` → one `QListWidgetItem` per URL string.

### Context menu (`displayWebSeedListMenu`)
- **Add web seed...** (`list-add`) → `askWebSeed`: `AutoExpandableDialog::getText` (title "Add web seed", label "Add web seed:", default `http://www.`); duplicate check (warn "This web seed is already in the list."); `torrent->addUrlSeeds({url})`; reload.
If ≥1 selected:
- **Remove web seed** (`edit-clear`/`list-remove`) → `deleteSelectedUrlSeeds` → `torrent->removeUrlSeeds(list)`.
- separator
- **Copy web seed URL** (`edit-copy`) → newline-joined to clipboard.
- **Edit web seed URL...** (`edit-rename`) → `editWebSeed`: single selection only; getText prefilled; dup check; remove old + add new.

### Hotkeys
F2 → edit; Delete → remove; double-click → edit.

### Torrent API read/write
`fetchURLSeeds()`, `addUrlSeeds(QList<QUrl>)`, `removeUrlSeeds(QList<QUrl>)`.

---

## 7. Content Tab (`pageContents`) — `TorrentContentWidget`

**Files:** `torrentcontentwidget.{h,cpp}`, `torrentcontentmodel*.{h,cpp}`, `torrentcontentitemdelegate.{h,cpp}`, `torrentcontentfiltermodel.*`, plus filter LineEdit + format menu in `propertieswidget.cpp`.

Top row (`contentFilterLayout`): **Select All** button (`selectAllButton`→`checkAll`), **Select None** (`selectNoneButton`→`checkNone`), horizontal spacer, then a `LineEdit` filter (`m_contentFilterLine`, fixed width 300, placeholder "Filter files...", custom context menu adds a `FilterPatternFormatMenu` for Wildcards/PlainText/Regex). Below: the `TorrentContentWidget` tree.

`setContentHandler(TorrentContentHandler*)` binds the model; `refresh()` recomputes progress/priority/availability. Configured here: `setContentDragAllowed(true)`, `setDoubleClickAction(Open)`, `setOpenByEnterKey(true)`. Drag enabled per `TorrentContentDragEnabled` (Alt inverts). `stateChanged` signal → PropertiesWidget `saveSettings`.

### Tree columns (`TorrentContentModelItem::TreeItemColumns` / `TorrentContentWidget::Column`)
| Index | enum | Header text (`torrentcontentmodel.cpp`) |
|---|---|---|
| 0 | COL_NAME | `Name` (has checkbox + file/folder icon) |
| 1 | COL_SIZE | `Total Size` |
| 2 | COL_PROGRESS | `Progress` (progress-bar delegate) |
| 3 | COL_PRIO | `Download Priority` (combobox editor) |
| 4 | COL_REMAINING | `Remaining` |
| 5 | COL_AVAILABILITY | `Availability` |

- **Name**: `Qt::CheckStateRole` per-item tri-state checkbox (folders propagate to children); editable = rename. Icon via `QFileIconProvider`.
- **Progress**: delegate paints a `QProgressBar` (`m_progressBarPainter.paint`), disabled look when priority==Ignored; value from `UnderlyingDataRole` (progress*..).
- **Download Priority**: delegate creates a `QComboBox` editor: index0 "Do not download", 1 "Normal", 2 "High", 3 "Maximum", and "Mixed" only for mixed-priority items. Maps to `DownloadPriority {Ignored=0, Normal=1, High=6, Maximum=7, Mixed=-1}`. Editing commits on index change; `AllEditTriggers` + single-click opens editor (`clicked`→`edit`).

### Model roles/behavior (`TorrentContentModel`)
`UnderlyingDataRole = Qt::UserRole` (raw sortable). `setData` on Name+CheckStateRole toggles priority (checked=Normal, unchecked=Ignored via check propagation). Rename via `setData` on Name → `contentHandler->renameFile/renameFolder`; failure emits `renameFailed` → warning box "Rename error". Live updates: `updateFilesProgress/Priorities/Availability`, `metadataReceived`, `fileRenamed`, `folderRenamed`. Root header row constructed with labels `{Name, Total Size, Progress, Download Priority, Remaining, Availability}`.

### View behavior
DragOnly drag-drop, multi-selection, expandsOnDoubleClick=false, sorting enabled, uniform rows, first section movable, custom header menu. Auto-expands single-child folder chains (`expandRecursively`, `rowsInserted`). Space/Select key toggles checkboxes on selected rows. Shift+wheel horizontal scroll. `setModel()` blocked.

### Context menu (`displayContextMenu`)
Single selection (when `actualStorageLocation()` non-empty):
- **Open** (`folder-documents`) → `openItem` (flushCache + `Utils::Gui::openPath`)
- **Open containing folder** (`directory`) → `openParentFolder` (`openFolderSelect`, macOS `MacUtils::openFiles`)
- **Copy path** (`edit-copy`) → `copyFullPath`
Always (single): **Rename...** (`edit-rename`) → `renameSelectedFile` (AutoExpandableDialog "Renaming"/"New name:"), **Batch rename...** (`edit-rename`) → `batchRenameFiles` (opens `TorrentContentLayoutDialog`), separator, submenu **Priority**: `Do not download` / `Normal` / `High` / `Maximum`, separator, `By shown file order` (`applyPrioritiesByOrder`).
Multi selection: flat items **Do not download**, **Normal priority**, **High priority**, **Maximum priority**, separator, **Priority by shown file order**. `applyPriorities(priority)` sets COL_PRIO on all selected; menu auto-closes on model reset.

Header right-click → **Column visibility** (Name locked/disabled, others toggle; only in `Editable` mode) + **Resize columns**.

### Hotkeys / actions
F2 → rename; Enter/Return → open (when `openByEnterKey`). Double-click → Open (configured). `applyPrioritiesByOrder`: splits selection into 3 groups → Maximum/High/Normal.

### TorrentContentHandler API read/write
`hasMetadata()`, `filesCount()`, `filePath(i)`, `fileSize(i)`, `actualStorageLocation()`, `actualFilePath(i)`, `filePriorities()`, `filesProgress()`, async `fetchAvailableFileFractions()`, `renameFile(i,path)`, `prioritizeFiles(QList<DownloadPriority>)`, `flushCache()`; signals `metadataReceived/fileRenamed/folderRenamed/folderRenamingFailed`. `Torrent` derives from `TorrentContentHandler`.

---

## 8. Speed Tab (`pageSpeed`) — `SpeedWidget` + `SpeedPlotView`

**Files:** `speedwidget.{h,cpp}`, `speedplotview.{h,cpp}`.

`configure()` places either a `SpeedWidget` (when `SpeedWidget/Enabled`) or a placeholder label. `SpeedWidget` layout: top `QHBoxLayout` with **`Period:`** bold label + `QComboBox` (`m_periodCombobox`) + stretch + a `ComboBoxMenuButton` (`m_graphsButton`, single item "Select Graphs" that pops a checkable menu). Below: the `SpeedPlotView`.

### Period combo items (index → `TimePeriod`)
`1 Minute`(MIN1=0), `5 Minutes`(MIN5), `30 Minutes`(MIN30), `3 Hours`(HOUR3), `6 Hours`(HOUR6), `12 Hours`(HOUR12), `24 Hours`(HOUR24). Change → `plot->setPeriod`. Persisted `SpeedWidget/period` (default 1 = 5 Minutes).

### Graphs menu (checkable, one per `GraphID`, all default-checked in UI but persistence defaults only UP/DOWN on)
Order = `SpeedPlotView::GraphID`: `Total Upload`(UP=0), `Total Download`(DOWN), `Payload Upload`, `Payload Download`, `Overhead Upload`, `Overhead Download`, `DHT Upload`, `DHT Download`, `Tracker Upload`, `Tracker Download` (NB_GRAPHS=10). Toggling → `plot->setGraphEnable(id, checked)`; persisted per-id `SpeedWidget/graph_enable_%1`.

### SpeedPlotView (`QGraphicsView`, custom `paintEvent`)
- Data fed via `pushPoint(SampleData = array<quint64,NB_GRAPHS>)` on `Session::statsUpdated`; sample filled from `SessionStatus`: uploadRate, downloadRate, payloadUpload/DownloadRate, ipOverheadUpload/DownloadRate, dhtUpload/DownloadRate, trackerUpload/DownloadRate.
- Multi-resolution averaging: `Averager`s at 5min/1s, 30min/6s, 6h/36s, 12h/72s, 24h/144s (circular buffers); `setPeriod` selects `m_currentAverager` + `m_currentMaxDuration`.
- Pens: upload = blue `#3299FF`, download = green `#86C43F`, width 1.5. Line styles distinguish graph families: Total=solid, Payload=Dash, Overhead=DashDot, DHT=DashDotDot, Tracker=Dot.
- Y axis: `getRoundedYScale` picks nice max; 5 labels at 100/75/50/25/0% via `formatLabel` (localized value + NBSP + unit string, e.g. `KiB/s`). Grid: 4 horizontal quarter lines + 6 vertical time divisions (dashed grey `rgba(128,128,128,128)`).
- Legend: top-left, 50%-transparent background rect; for each enabled graph draws a colored line sample + name.

QML rebuild: a live line chart (Canvas or Qt Charts) with the same 10 series, period selector, and a series-toggle menu; legend overlay.

---

## 9. Shared dialogs / helpers to rebuild
- **AutoExpandableDialog** (`gui/autoexpandabledialog.h`) — one-line text-input dialog reused for: tracker edit, web-seed add/edit, file rename. Signature `getText(parent, title, label, echoMode, defaultText, &ok[, selectFileNameOnly])`.
- **TorrentContentLayoutDialog** (`torrentcontentlayoutdialog.*`) — "Batch rename..." target.
- **FilterPatternFormatMenu** (`gui/filterpatternformatmenu.h`) — Wildcards/PlainText/Regex selection for the content filter.
- **UIThemeManager** icons + `getFlagIcon(country)`; **Utils::Misc** `friendlyUnit`, `userFriendlyDuration`; **Utils::String** `fromDouble`, `wildcardToRegexPattern`.

## 10. QML/Material mapping notes
- PropTabBar → Material `TabBar`/`TabButton` row with the same 6 tabs + collapse-on-reclick behavior; Speed tab pushed to the right.
- General tab groups → two Material "cards" (Transfer, Information) with label/value rows in a responsive 2–3 column grid, plus a pieces-bar card on top.
- Trackers/Peers/Content trees → `TreeView`/`TableView` (Qt Quick) with the exact columns above; column-visibility + resize via header context menu; sort proxies preserving sticky DHT/PeX/LSD rows (Trackers) and natural IP/Client sort (Peers).
- Content Priority cell → Material `ComboBox` delegate; Progress cell → Material `ProgressBar` delegate; Name cell → `CheckBox` + icon.
- Speed tab → live chart component + period `ComboBox` + graph-toggle menu button.
- Persist the same settings keys (or Qt6-namespaced equivalents) for header/column state, splitter, current tab, visibility, speed period/graph flags.

---

# Area: Add Torrent, Torrent Options, Category, Tags, and Content-Layout dialogs

## Overview & data model

All of these dialogs read/write a single core struct, `BitTorrent::AddTorrentParams` (`src/base/bittorrent/addtorrentparams.h`), or mutate live `BitTorrent::Torrent` objects. Reproducing them in QML requires exposing this struct and the `Session`/`Torrent` APIs to QML. The exact struct fields (with defaults) are:

```
struct AddTorrentParams {
    QString name;
    QString category;
    TagSet tags;                                  // set of Tag
    Path savePath;
    std::optional<bool> useDownloadPath;          // nullopt = "use global/category default"
    Path downloadPath;
    bool sequential = false;
    bool firstLastPiecePriority = false;
    bool addForced = false;
    std::optional<bool> addToQueueTop;
    std::optional<bool> addStopped;               // note: INVERSE of "Start torrent"
    std::optional<Torrent::StopCondition> stopCondition;
    PathList filePaths;                           // per-file target paths (used when metadata present)
    QList<DownloadPriority> filePriorities;        // per-file priority
    bool skipChecking = false;
    std::optional<BitTorrent::TorrentContentLayout> contentLayout;
    std::optional<bool> useAutoTMM;
    int uploadLimit = -1;
    int downloadLimit = -1;
    ShareLimits shareLimits;
    SSLParameters sslParameters;
};
```

Key enums:
- `TorrentContentLayout` (int-castable, index order in combo): `Original=0`, `Subfolder=1` ("Create subfolder"), `NoSubfolder=2` ("Don't create subfolder"). In the Add dialog the combo index is cast directly to this enum.
- `Torrent::StopCondition`: `None`, `MetadataReceived`, `FilesChecked` (stored via `QVariant::fromValue` in combo item data, not by index).
- `DownloadPriority : int` (`src/base/bittorrent/downloadpriority.h`): `Ignored=0`, `Normal=1`, `High=6`, `Maximum=7`, `Mixed=-1`.
- `ShareLimitsMode`: `Default=-1`, `MatchAny=0`, `MatchAll=1`.
- `ShareLimitAction`: `Default=-1`, `Stop=0`, `Remove=1`, `EnableSuperSeeding=2`, `RemoveWithContent=3`.
- Sentinel constants (`sharelimits.h`): `DEFAULT_RATIO_LIMIT=-2`, `NO_RATIO_LIMIT=-1`, `DEFAULT_SEEDING_TIME_LIMIT=-2`, `NO_SEEDING_TIME_LIMIT=-1`.

Two custom widgets are reused across dialogs and must be rebuilt as QML components:
- `FileSystemPathComboEdit` / `FileSystemPathLineEdit` (`gui/fspathedit.h`): a path editor. Combo variant has item history (`count()`, `item(i)`, `insertItem`, `addItem`, `setCurrentIndex`, `currentIndex`, `clear`). Both expose `setMode(FileSystemPathEdit::Mode::DirectorySave)`, `setDialogCaption()`, `setMaxVisibleItems()`, `selectedPath()`, `setSelectedPath(Path)`, `setPlaceholder(Path)`, signal `selectedPathChanged(Path)`.
- `TorrentShareLimitsWidget` (see its own section).

---

## SCREEN 1 — Add New Torrent Dialog
Source: `src/gui/addnewtorrentdialog.{h,cpp,ui}` (class `AddNewTorrentDialog : QDialog`). Root layout `QVBoxLayout`; default size 900x680. The whole body is inside a frameless `QScrollArea` containing a horizontal `QSplitter` (`childrenCollapsible=false`): LEFT = options frame, RIGHT = content tree panel. Splitter + tree-header state persisted.

Constructor signature: `AddNewTorrentDialog(const TorrentDescriptor &torrentDescr, const AddTorrentParams &inParams, QWidget *parent)`. Emits `torrentAccepted(TorrentDescriptor, AddTorrentParams)` / `torrentRejected(TorrentDescriptor)`. Public: `isDoNotDeleteTorrentChecked()`, `updateMetadata(TorrentInfo)`.

### LEFT panel controls (top → bottom)

1. **Torrent Management Mode** row (`labelTorrentManagementMode` "Torrent Management Mode:", combo `comboTMM`). Items: index 0 = "Manual", index 1 = "Automatic". Tooltip: "Automatic mode means that various torrent properties(eg save path) will be decided by the associated category". Initial index from `addTorrentParams.useAutoTMM.value_or(!session->isAutoTMMDisabledByDefault())`. On change → `TMMChanged(index)`.
   - When index != 1 (Manual): `groupBoxSavePath` enabled, save/download combos populated from history via `populateSavePaths()`.
   - When index == 1 (Automatic): `groupBoxSavePath` disabled; savePath/downloadPath forced to `session->categorySavePath(category)` / `categoryDownloadPath(category)` (single read-only item); download-path group checked iff downloadPath non-empty; default focus moves to category combo.

2. **"Save at"** group box (`groupBoxSavePath`, title "Save at"):
   - `savePath` = `FileSystemPathComboEdit`, mode DirectorySave, caption "Choose save path", maxVisibleItems 20. History-backed (see settings keys). On `selectedPathChanged` → remembers index + `updateDiskSpaceLabel()`.
   - Nested **checkable group box** `groupBoxDownloadPath`, title "Use another path for incomplete torrent", `checkable=true`, initially unchecked. Contains `downloadPath` = `FileSystemPathComboEdit` (same config). Toggling calls `onUseDownloadPathChanged(checked)` which sets download combo index to remembered index or -1.
   - Row with right-aligned checkbox `checkBoxRememberLastSavePath` "Remember last used save path" (bound to setting `RememberLastSavePath`).

3. **"Torrent options"** group box (`groupBoxSettings`, title "Torrent options"):
   - **Category** row: label `labelCategory` "Category:", editable `categoryComboBox` (`editable=true`, `insertPolicy=InsertAtTop`, hsizetype Expanding). Populated in `setCurrentContext`: adds `addTorrentParams.category` (if non-empty), then stored default category (if non-empty), then an empty item `""`, then all `session->categories()` sorted with `Utils::Compare::NaturalLessThan<CaseInsensitive>` excluding dupes. On change → `categoryChanged(index)`: in Automatic mode, updates save/download path from category and calls `updateDiskSpaceLabel()`.
   - Right-aligned checkbox `defaultCategoryCheckbox` "Set as default category" → on accept stores category into `DefaultCategory` setting.
   - **Tags** row: label `tagsLabel` "Tags:", read-only `tagsLineEdit` (placeholder "Click [...] button to add/remove tags."), tool button `tagsEditButton` text "..." tooltip "Add/remove tags". Button opens `TorrentTagsDialog(currentTags, this)` (WA_DeleteOnClose, `.open()`); on accept sets `torrentParams.tags = dlg->tags()` and refreshes line edit via `Utils::String::joinIntoString(tags, ", ")`.
   - **Grid of checkboxes / stop condition** (`gridLayout`):
     - (0,0) `startTorrentCheckBox` "Start torrent". Bound to `!addStopped`. Toggling enables/disables the stop-condition label+combo.
     - (0,1) stop-condition sub-layout: label `stopConditionLabel` "Stop condition:" + combo `stopConditionComboBox`. Items built in code with `QVariant::fromValue`: "None"→`StopCondition::None`, "Files checked"→`FilesChecked`; "Metadata received"→`MetadataReceived` is inserted at index 1 ONLY when metadata is NOT yet available, and removed once metadata arrives. Rich tooltip explains None/Metadata received/Files checked. Enabled only when Start torrent checked. Special rule: if metadata present and stopCondition==MetadataReceived, Start is unchecked and condition reset to None.
     - (1,0) `addToQueueTopCheckBox` "Add to top of queue" (bound to `addToQueueTop.value_or(session->isAddTorrentToQueueTop())`).
     - (1,1) `skipCheckingCheckBox` "Skip hash check" (bound to `skipChecking`).
     - (2,0) `sequentialCheckBox` "Download in sequential order" (bound to `sequential`).
     - (2,1) `firstLastCheckBox` "Download first and last pieces first" (bound to `firstLastPiecePriority`).
     - (3,0) `doNotDeleteTorrentCheckBox` "Do not delete .torrent file", tooltip "When checked, the .torrent file will not be deleted regardless of the settings at the \"Download\" page of the Options dialog". Visible only when `TorrentFileGuard::autoDeleteMode() != Never`.
   - **Content layout** row: label `contentLayoutLabel` "Content layout:" + combo `contentLayoutComboBox` items index 0 "Original", 1 "Create subfolder", 2 "Don't create subfolder" (index cast directly to `TorrentContentLayout`). On change → `contentLayoutChanged()` which, if metadata present, calls `m_contentAdaptor->applyContentLayout(...)` to restructure file paths in the tree.

4. **"Torrent information"** group box (`infoGroup`, title "Torrent information", grid `gridLayout_2`, vsizetype Expanding):
   - "Size:" → `labelSizeData` — set by `updateDiskSpaceLabel()`: text `"%1 (Free space on disk: %2)"` where %1 is friendly torrent size (sum of `fileSize(i)` for files with priority > Ignored) or "Not available", %2 = `friendlyUnit(queryFreeDiskSpace(savePath))`. Free space is queried walking up parent paths until a valid value.
   - "Date:" → `labelDateData` — `QLocale().toString(creationDate, ShortFormat)` or "Not available" / "Not Available" (magnet: "Not Available").
   - "Info hash v1:" → `labelInfohash1Data` (selectable by mouse) — `infoHash.v1()` string or "N/A".
   - "Info hash v2:" → `labelInfohash2Data` (selectable) — `infoHash.v2()` string or "N/A".
   - "Comment:" (top-aligned) → `labelCommentData` inside a `QScrollArea`; RichText, wordWrap, `openExternalLinks=true`, selectable by keyboard+mouse. Text = `Utils::Misc::parseHtmlLinks(comment.toHtmlEscaped())`; magnet placeholder "Not Available".

### RIGHT panel (`layoutWidget` → `verticalLayout_5`)
- Toolbar row (`contentFilterLayout`): `buttonSelectAll` "Select All" (→ `contentTreeView->checkAll()`), `buttonSelectNone` "Select None" (→ `checkNone()`), a horizontal spacer, and a code-inserted `LineEdit m_filterLine` (placeholder "Filter files...", Expanding). Filter line has custom context menu (`showContentFilterContextMenu()`) that appends a `FilterPatternFormatMenu` (see Screen 4). `Ctrl+F` (QKeySequence::Find) focuses + selects the filter. Text changes call `setContentFilterPattern()` → `contentTreeView->setFilterPattern(text, format)`.
- `contentTreeView` = `TorrentContentWidget` (see Screen 2), Expanding, `CustomContextMenu`, `ExtendedSelection`, `sortingEnabled=true`.

### FOOTER (below scroll area)
- `checkBoxNeverShow` "Never show again" + spacer. On accept: `Preferences::setAddNewTorrentDialogEnabled(!checked)`.
- Metadata row (`metadataLayout`): indeterminate `QProgressBar progMetaLoading` (max=0, textVisible=false), label `lblMetaLoading` (set by `setMetadataProgressIndicator(visible, text)` — texts: "Retrieving metadata...", "Parsing metadata...", "Metadata retrieval complete"), and `buttonSave` "Save as .torrent file...".
- `buttonBox` = `QDialogButtonBox` with Ok + Cancel.

### Behaviors / API used
- `buttonSave` → `saveTorrentFile()`: `QFileDialog::getSaveFileName` filter "Torrent file (*.torrent)", default `~/name.torrent`, appends `TORRENT_FILE_EXTENSION` if missing, calls `torrentDescr.saveToFile(path)`; on failure `QMessageBox::critical("I/O Error", "Couldn't export torrent metadata file '%1'. Reason: %2.")`. Hidden until metadata present. For v2 torrents button disabled with tooltip "Cannot create v2 torrent until its data is fully downloaded."
- `accept()`: if Manual mode and `savePath` invalid → `QMessageBox::warning("Invalid save path", "The \"Save at\" path contains invalid characters.")` and abort. Else `updateCurrentContext()` (writes all UI back into params), emit `torrentAccepted`, persist Never-show pref.
- `reject()`: emit `torrentRejected`; if no metadata, `session->cancelDownloadMetadata(infoHash.toTorrentID())`.
- `done()`: persists dialog size, splitter state, tree header state.
- Title: torrent name; for magnet w/o metadata "Magnet link" or the descriptor name.
- `updateCurrentContext()` write-back rules: `skipChecking`, `category`, `addToQueueTop`, `addStopped = !startChecked`, `stopCondition` (from combo item data), `contentLayout = (TorrentContentLayout)comboIndex`, `sequential`, `firstLastPiecePriority`, `useAutoTMM`. In Manual mode also writes `savePath` (+ updates save-path history), `useDownloadPath` (= download group checked), `downloadPath` (+ history). In Automatic mode clears savePath/downloadPath and sets `useDownloadPath=nullopt`.

### Session/Preferences API consumed by this dialog
`Session`: `isAutoTMMDisabledByDefault`, `isAddTorrentToQueueTop`, `isAddTorrentStopped`, `torrentContentLayout`, `torrentStopCondition`, `categories`, `categorySavePath`, `categoryDownloadPath`, `savePath`, `downloadPath`, `isDownloadPathEnabled`, `isExcludedFileNamesEnabled`, `applyFilenameFilter(paths, priorities)`, `cancelDownloadMetadata`. `Preferences`: `isAddNewTorrentDialogEnabled`/`setAddNewTorrentDialogEnabled`, `isAddNewTorrentDialogTopLevel`, `addNewTorrentDialogSavePathHistoryLength`.

### Settings keys (persisted)
- `AddNewTorrentDialog/SavePathHistory` (QStringList), `AddNewTorrentDialog/DownloadPathHistory` (QStringList) — front-inserted, trimmed to `addNewTorrentDialogSavePathHistoryLength`.
- `AddNewTorrentDialog/DialogSize` (QSize), `AddNewTorrentDialog/DefaultCategory` (QString), `AddNewTorrentDialog/RememberLastSavePath` (bool).
- `GUI/Qt6/AddNewTorrentDialog/TreeHeaderState` (QByteArray), `GUI/Qt6/AddNewTorrentDialog/SplitterState` (QByteArray).
- `GUI/AddNewTorrentDialog/FilterPatternFormat` (FilterPatternFormat, default Wildcards).

---

## SCREEN 2 — Torrent Content Tree (embedded `TorrentContentWidget`)
Source: `src/gui/torrentcontentwidget.{h,cpp}` (`TorrentContentWidget : QTreeView`). Model column enum `Column { Name=0, Size=1, Progress=2, Priority=3, Remaining=4, Availability=5 }`. Column header display names (from `TorrentContentModel`): **"Name", "Total Size", "Progress", "Download Priority", "Remaining", "Availability"**.

In the Add dialog these are configured: columns **Progress, Remaining, Availability are hidden**; `setColumnsVisibilityMode(Locked)`; `setDoubleClickAction(Rename)`. So the Add dialog effectively shows **Name / Total Size / Download Priority**.

- Column 0 "Name" cells are **checkable** (`Qt::CheckStateRole`) — checking/unchecking toggles include/exclude (maps to Ignored priority). `checkAll()` / `checkNone()` set all rows checked/unchecked.
- Column 3 "Download Priority" is a combo-delegate: values Do-not-download / Normal / High / Maximum (and "Mixed" for folders with mixed children).
- Double-click Name → rename (in-place). Double-click action configurable Open/Rename.
- Filtering: `setFilterPattern(text, FilterPatternFormat)` filters the tree; single-item folders auto-expand.
- `TorrentContentModel` is driven by a `BitTorrent::TorrentContentHandler`. In the Add dialog the handler is the private `TorrentContentAdaptor` which wraps `TorrentInfo` + `filePaths` + `filePriorities`; it implements: `hasMetadata`, `filesCount`, `fileSize(i)`, `filePath(i)`, `filePriorities`, `filesProgress` (all 0), `fetchAvailableFileFractions` (all 0), `actualStorageLocation` (empty), `renameFile(i, newPath)`, `applyContentLayout(layout)` (adds/strips root folder, emits `fileRenamed`), `prioritizeFiles(priorities)` (emits change → `updateDiskSpaceLabel`). Signals `fileRenamed(index, oldPath)` and `folderRenamed(newFolder, oldFolder, renamedFiles)`.

---

## SCREEN 3 — Torrent Content Tree Context Menu
Source: `TorrentContentWidget::displayContextMenu()` (`CustomContextMenu`). Two shapes:

**Single selection** (in this order):
- If `actualStorageLocation()` non-empty (NOT the case inside Add dialog, where it is empty): "Open" (icon folder-documents), "Open containing folder" (icon directory), "Copy path" (icon edit-copy).
- "Rename..." (icon edit-rename) → `renameSelectedFile()`: `AutoExpandableDialog::getText(title "Renaming", label "New name:")`, trims, writes via `model()->setData`.
- "Batch rename..." (icon edit-rename) → `batchRenameFiles()` → opens **Manage Torrent Content Dialog** (Screen 11).
- separator.
- Sub-menu **"Priority"** with actions: "Do not download" (Ignored), "Normal" (Normal), "High" (High), "Maximum" (Maximum), separator, "By shown file order" → `applyPrioritiesByOrder()`.

**Multi selection** (flat, no submenu): "Do not download", "Normal priority", "High priority", "Maximum priority", separator, "Priority by shown file order".

`applyPrioritiesByOrder()`: splits selected rows into 3 groups and assigns Maximum / High / Normal respectively.

**Column-header menu** (`displayColumnHeaderMenu`, only when `ColumnsVisibilityMode::Editable` — NOT in Add dialog which is Locked): checkable entry per column (Name disabled/always-on), separator, "Resize columns" (tooltip "Resize all non-hidden columns to the size of their contents").

---

## SCREEN 4 — Content Filter Pattern-Format Menu
Source: `FilterPatternFormatMenu` (appended to the filter LineEdit's standard context menu). Lets the user pick the `FilterPatternFormat` (Wildcards / regex etc.); selection persisted to `GUI/AddNewTorrentDialog/FilterPatternFormat` and re-applies the current filter. (Enum defined in `filterpatternformat.h`.)

---

## SCREEN 5 — Add Torrent Parameters Widget (reusable defaults editor)
Source: `src/gui/addtorrentparamswidget.{h,cpp,ui}` (`AddTorrentParamsWidget : QWidget`). This is the "tri-state / has-default" variant used where every option may be left at "Default" (e.g. RSS auto-download rules, category default params). Constructor `AddTorrentParamsWidget(AddTorrentParams = {}, parent)`; `setAddTorrentParams()`, `addTorrentParams()`.

Controls (top → bottom), all combos start with a "Default" item (currentData invalid → `std::nullopt`):
- **TMM** row: label "Torrent Management Mode:", combo `comboTTM` items: "Default"(no data), "Manual"(false), "Automatic"(true) → `useAutoTMM` optional. Same tooltip as Add dialog.
- **"Save at"** group `groupBoxSavePath`: italic note label `defaultsNoteLabel` "Note: the current defaults are displayed for reference." (shown when TMM=Default/Automatic, i.e. path editing disabled); `savePathEdit` = `FileSystemPathLineEdit` (DirectorySave, caption "Choose save path", uses placeholder to show suggested default via `session->suggestedSavePath(category, tmm)`). Row: label "Use another path for incomplete torrents:" + combo `useDownloadPathComboBox` items "Default"(no data)/"Yes"(true)/"No"(false) → `useDownloadPath` optional. Then `downloadPathEdit` = `FileSystemPathLineEdit`; enabled only when useDownloadPath==Yes; placeholder from `session->suggestedDownloadPath(...)`.
- **Category** row: label "Category:", editable combo `categoryComboBox` (InsertAtTop). Populated with current category (if any), empty item, then sorted `session->categories()`. On change updates default paths + share-limit defaults, and (if auto-TMM) the useDownloadPath combo from `categoryOptions(category).downloadPath`.
- **Tags** row: label "Tags:", read-only `tagsLineEdit` (placeholder "Click [...] button to add/remove tags."), `tagsEditButton` "..." → opens `TorrentTagsDialog` (same pattern as Add dialog).
- **`miscParamsWidget`** laid out with a `FlowLayout`, containing:
  - `contentLayoutWidget`: label "Content layout:" + combo `contentLayoutComboBox` items "Default"(no data)/"Original"/"Create subfolder"/"Don't create subfolder" (data = `TorrentContentLayout` value) → `contentLayout` optional.
  - `skipCheckingCheckBox` "Skip hash check" (plain bool `skipChecking`).
  - `startTorrentWidget`: label "Start torrent:" + combo `startTorrentComboBox` "Default"/"Yes"(true)/"No"(false); stored as `addStopped = !value`.
  - `stopConditionWidget`: label "Stop condition:" + combo `stopConditionComboBox` "Default"/"None"/"Metadata received"/"Files checked" (data = StopCondition) → `stopCondition` optional.
  - `addToQueueTopWidget`: label "Add to top of queue:" + combo `addToQueueTopComboBox` "Default"/"Yes"/"No" → `addToQueueTop` optional.
- **"Torrent share limits"** group `torrentShareLimitsBox` embedding `TorrentShareLimitsWidget` (Screen 6). Defaults come from `session->categoryShareLimits(category)` (UsedDefaults = Global when category empty else Category).

`cleanParams()`: if TMM default/automatic → clears savePath/downloadPath/useDownloadPath; if useDownloadPath not Yes → clears downloadPath. `addTorrentParams()` also pulls the five share-limit values out of the embedded widget.

---

## SCREEN 6 — Torrent Share Limits Widget (reusable)
Source: `src/gui/torrentsharelimitswidget.{h,cpp,ui}` (`TorrentShareLimitsWidget : QWidget`). Grid of 3 limit rows + 2 rows below. Getters return `std::optional` (nullopt when combo left on the blank uninitialized item).

Combo mode indices for each limit combo: `0 Default`, `1 Unlimited`, `2 Set to` (item text for index 0 is retitled — see below). Rows:
- "Ratio:" — combo `comboBoxRatioMode` + `spinBoxRatioValue` (QDoubleSpinBox, step 0.05, max INT_MAX, enabled only in "Set to"). `ratioLimit()` returns `DEFAULT_RATIO_LIMIT` / `NO_RATIO_LIMIT` / spin value.
- "Seeding time:" — combo `comboBoxSeedingTimeMode` + `spinBoxSeedingTimeValue` (QSpinBox, suffix " min", max 9999999, default 1440). Returns `DEFAULT_SEEDING_TIME_LIMIT` / `NO_SEEDING_TIME_LIMIT` / value.
- "Inactive seeding time:" — combo `comboBoxInactiveSeedingTimeMode` + `spinBoxInactiveSeedingTimeValue` (same as above).
- "Mode:" row — combo `comboBoxMode` items: blank / "Match any limit" (MatchAny) / "Match all the limits" (MatchAll); index 0 is the "Default" item.
- "Action when the limit is reached:" row — combo `comboBoxAction` items: blank / "Stop torrent" / "Remove torrent" / "Remove torrent and its content" / "Enable super seeding for torrent"; index 0 is "Default".

`setDefaults(UsedDefaults {Global|Category}, ShareLimits)` retitles the index-0 items:
- Global: "Default", and for action/mode `"Default (%1)"` when the default itself is non-default (e.g. "Default (Stop torrent)").
- Category: "From category", and `"From category (%1)"` analogously.
Default spin values are shown when the corresponding combo sits on the Default item and the default value ≥ 0; otherwise the spin is cleared and suffix removed. Setter methods: `setRatioLimit`, `setSeedingTimeLimit`, `setInactiveSeedingTimeLimit`, `setShareLimitsMode`, `setShareLimitAction`. Action/mode display strings come from `shareLimitActionName()` / `shareLimitsModeName()`.

---

## SCREEN 7 — Torrent Options Dialog (multi-torrent edit)
Source: `src/gui/torrentoptionsdialog.{h,cpp,ui}` (`TorrentOptionsDialog : QDialog`). Title "Torrent Options", size 450x540. Constructor `TorrentOptionsDialog(parent, QList<Torrent*> torrents)` — edits one OR many torrents at once. For each field the ctor computes "all torrents share the same value"; if not, the control is shown **partially/indeterminate** (checkboxes → `Qt::PartiallyChecked`; spin limits → special text `C_INEQUALITY`; share-limit widget left blank; category → special placeholder item).

Controls (top → bottom):
1. `checkAutoTMM` tri-state checkbox "Automatic Torrent Management", tooltip "Automatic mode means that various torrent properties (e.g. save path) will be decided by the associated category". On click → `handleTMMChanged()`.
2. **"Save at"** group `groupBoxSavePath`: `savePath` (`FileSystemPathComboEdit`, DirectorySave), checkbox `checkUseDownloadPath` "Use another path for incomplete torrent" (tri-state), and `downloadPath` (`FileSystemPathComboEdit`, initially disabled). Group disabled when auto-TMM on. `handleUseDownloadPathChanged()` enables downloadPath only when checked and fills a default from `session->downloadPath()` if empty.
3. **Category** row (grid): label "Category:", editable combo `comboCategory` (InsertAtTop, maxVisibleItems INT_MAX). If not all-same-category, a leading item `"--Currently used categories--"` (`"--%1--"`.arg(tr("Currently used categories"))) is added and used as placeholder. Otherwise sets/adds the shared category. Then empty item, then sorted `session->categories()`. On `activated` → `handleCategoryChanged()`.
4. **"Torrent Speed Limits"** group `groupBox` (grid): 
   - "Upload:" — slider `sliderUploadLimit` + spin `spinUploadLimit` (specialValueText "∞", suffix " KiB/s", max 2000000, AdaptiveDecimalStepType). 
   - "Download:" — slider `sliderDownloadLimit` + spin `spinDownloadLimit` (same). 
   - Warning label `labelWarning` "These will not exceed the global limits". 
   - Slider max derived from global (or alt-global) up/down limits /1024 (min 10000, or the torrent's own value if larger). Sliders and spins are two-way synced. If values differ across torrents, spin min set to -1, value -1, specialValueText `C_INEQUALITY`; first user edit switches min→0 and specialValueText→`C_INFINITY`.
5. **"Torrent Share Limits"** group `torrentShareLimitsBox` embedding `TorrentShareLimitsWidget` (Screen 6). Defaults from `session->categoryShareLimits(firstTorrentCategory)`; per-field values only set when all torrents agree.
6. **Bottom checkbox grid** (`gridLayout_3`):
   - (0,0) `checkDisableDHT` "Disable DHT for this torrent"
   - (0,1) `checkSequential` "Download in sequential order"
   - (1,0) `checkDisablePEX` "Disable PeX for this torrent"
   - (1,1) `checkFirstLastPieces` "Download first and last pieces first"
   - (2,0) `checkDisableLSD` "Disable LSD for this torrent"
   - DHT/PEX/LSD get tooltip "Not applicable to private torrents"; if ALL selected torrents are private they are force-checked + disabled; otherwise tri-state when torrents disagree.
7. `buttonBox` Ok + Cancel.

`accept()` applies per torrent (only when the control changed vs. its captured `m_initialValues`, so partial/indeterminate controls are skipped): `setAutoTMMEnabled`, and if auto-TMM off `setSavePath` / `setDownloadPath` (or `{}` when useDownloadPath unchecked); category via `setCategory` (adds category first if new, `session->addCategory`); `setUploadLimit(value*1024)`, `setDownloadLimit(value*1024)`; `setShareLimits(ShareLimits)` (each field only overwritten if changed); for non-private torrents `setDHTDisabled` / `setPEXDisabled` / `setLSDDisabled`; `setSequentialDownload`; `setFirstLastPiecePriority`.

`Torrent` getters read: `isAutoTMMEnabled`, `savePath`, `downloadPath`, `category`, `uploadLimit`, `downloadLimit`, `shareLimits`, `isPrivate`, `isDHTDisabled`, `isPEXDisabled`, `isLSDDisabled`, `isSequentialDownload`, `hasFirstLastPiecePriority`, `id`. Setting persisted: `TorrentOptionsDialog/Size` (QSize).

---

## SCREEN 8 — Add/Edit Category Dialog
Source: `src/gui/torrentcategorydialog.{h,cpp,ui}` (`TorrentCategoryDialog : QDialog`). Title "Torrent Category Properties", size 493x268. Two static entry points: `createCategory(parent, parentCategoryName={})` (loops on exec, validates, calls `Session::addCategory`) and `editCategory(parent, categoryName)` (WA_DeleteOnClose, name read-only, `.open()`, on accept `Session::setCategoryOptions`).

Controls:
- Grid: label "Name:" + `textCategoryName` (`QLineEdit`). In edit mode disabled via `setCategoryNameEditable(false)`. On text change → `categoryNameChanged()`: updates save/download placeholders from `session->categorySavePath/DownloadPath(name, options())`, updates parent-category share-limit defaults, and enables the Ok button only when name non-empty. `setCategoryName()` selects the sub-category portion after the last `/`.
- label "Save path:" + `comboSavePath` (`FileSystemPathComboEdit`, DirectorySave, caption "Choose save path").
- **"Save path for incomplete torrents:"** group `groupBox`: row label "Use another path for incomplete torrents:" + combo `comboUseDownloadPath` items index 0 "Default", 1 "Yes", 2 "No" (maxVisibleItems 3). Row label "Path:" (`labelDownloadPath`) + `comboDownloadPath` (`FileSystemPathComboEdit`, DirectorySave, caption "Choose download path"), initially disabled. `useDownloadPathChanged(index)` enables path+label only when index==1, restores last-entered path, and updates placeholder.
- **"Torrent share limits"** group `torrentShareLimitsBox` embedding `TorrentShareLimitsWidget` (Screen 6); defaults from parent category via `session->categoryShareLimits(parentCategoryName)` (UsedDefaults Category when parent non-empty else Global).
- `buttonBox` Ok + Cancel; Ok disabled until a name is present.

`categoryOptions()` builds `BitTorrent::CategoryOptions`: `savePath`; `downloadPath = {enabled,path}` — index1 → `{true, comboDownloadPath}`, index2 → `{false, {}}`, index0 → unset (nullopt); `shareLimits` from the widget with `value_or(DEFAULT_*)`. `setCategoryOptions()` does the inverse mapping. Validation strings in `createCategory`: invalid name → "Invalid category name" / "Category name cannot contain '\\'.\nCategory name cannot start/end with '/'.\nCategory name cannot contain '//' sequence."; duplicate → "Category creation error" / "Category with the given name already exists.\nPlease choose a different name and try again." New sub-category default name uses tr("New Category"), prefixed by `parent/`.

---

## SCREEN 9 — Add Tag inline input dialog
Source: `TorrentTagsDialog::addNewTag()` (`+` button). Uses `AutoExpandableDialog::getText(this, tr("Add tag"), tr("Tag:"), Normal, ...)`. Validation: empty/cancel → abort; invalid tag → `QMessageBox::warning("Invalid tag name", "Tag name '%1' is invalid.")`; existing tag → `QMessageBox::warning("Tag exists", "Tag name already exists.")`; else a new checked `QCheckBox` is inserted before the `+` button.

---

## SCREEN 10 — Torrent Tags Dialog
Source: `src/gui/torrenttagsdialog.{h,cpp,ui}` (`TorrentTagsDialog : QDialog`). Title "Torrent Tags", size 484x313. Constructor `TorrentTagsDialog(const TagSet &initialTags, parent)`; `tags()` returns selected `TagSet`.
- `scrollArea` (horizontal scrollbar always off, resizable) whose inner widget uses a `FlowLayout` of `QCheckBox` — one per tag in `initialTags ∪ session->tags()`, checked if in `initialTags`. Checkbox text via `Utils::Gui::tagToWidgetText(tag)` / reverse `widgetTextToTag`.
- Trailing `QPushButton "+"` → `addNewTag()` (Screen 9).
- `buttonBox` Ok + Cancel.
- `tags()` iterates all layout items except the last (the `+` button) collecting checked ones. Setting persisted: `GUI/TorrentTagsDialog/Size` (QSize).

---

## SCREEN 11 — Manage Torrent Content Dialog (batch rename / content layout)
Source: `src/gui/torrentcontentlayoutdialog.{h,cpp,ui}` (`TorrentContentLayoutDialog : QDialog`). Title "Manage Torrent Content", size 618x369, window icon "edit-rename". Constructor `TorrentContentLayoutDialog(TorrentContentHandler *contentHandler, parent)`. Opened from the content-tree "Batch rename..." action.
- `treeView` (`QTreeView`, `AllEditTriggers`, alternatingRowColors, ExtendedSelection) bound to `TorrentContentLayoutModel(contentHandler)`. Model columns: `COL_INDEX=0` header "Index" (right-aligned), `COL_PATH=1` header "Path". Editing a Path cell renames the file/folder. A custom `TorrentContentLayoutItemDelegate` renders changed paths in italic (role `PATH_CHANGED_ROLE = Qt::UserRole`).
- First row auto-selected on open.
- `buttonBox` = Apply + Close. Apply is enabled only when `model->haveChangedFilePaths()` (tracked via `dataChanged`). Apply → `model->applyChangedFilePaths()`. Close → `reject()`.
- On rename failure model emits `renameFailed(firstErrorMessage, errorsCount)` → `RaisedMessageBox::warning("Rename error", ...)`, appending tr("There are %n more renaming error(s).", ..., errorsCount-1) when >1.
- Model reject-on-destroy: if the content handler is destroyed the dialog auto-rejects. Settings persisted: `GUI/TorrentContentLayoutDialog/Size` (QSize), `GUI/TorrentContentLayoutDialog/ViewState` (QByteArray header state).

---

## SCREEN driver — GUIAddTorrentManager (how the Add dialog is launched)
Source: `src/gui/guiaddtorrentmanager.{h,cpp}` (`GUIAddTorrentManager`). `addTorrent(source, params={}, AddTorrentOption {Default|ShowDialog|SkipDialog})`:
- SkipDialog (or Default when `!pref->isAddNewTorrentDialogEnabled()`) → adds directly via base `AddTorrentManager::addTorrent`.
- URL/http source → downloads via `Net::DownloadManager` (limit `getTorrentFileSizeLimit`, proxy `useProxyForGeneralPurposes`), then processes; magnet/torrent-file parsed via `TorrentDescriptor::parse`/`loadFromFile`/`load`.
- **Duplicate handling** (`processTorrent`): if torrent already present and `confirmMergeTrackers()`: private → `RaisedMessageBox::warning("Torrent is already present", "Trackers cannot be merged because it is a private torrent.")`; else `RaisedMessageBox::question("Torrent is already present", "Torrent '%1' is already in the transfer list. Do you want to merge trackers from new source?", Yes|No)`; Yes → `addTrackers` + `addUrlSeeds`. Otherwise `handleDuplicateTorrent`.
- Otherwise constructs `AddNewTorrentDialog(torrentDescr, params, attached ? mainWindow : nullptr)`, WA_DeleteOnClose, non-attached gets `Qt::Window` flag; positioned by `adjustDialogGeometry` (centered on parent, clamped to screen). If no metadata → `session->downloadMetadata(torrentDescr)` and the manager forwards `Session::metadataDownloaded` → `dialog->updateMetadata(metadata)` (matched by info hash). On `torrentAccepted` it optionally preserves the .torrent file (if "Do not delete .torrent file" checked) and calls `addTorrentToSession(source, descr, params)`. Attach behavior governed by `Preferences::isAddNewTorrentDialogAttached()` (always non-attached on macOS).


---

# Area: Options Dialog — Behavior, Downloads & Connection tabs

# Options Dialog — Behavior, Downloads & Connection tabs

Source of truth: `src/gui/optionsdialog.{h,cpp,ui}`. Backing config keys read from `src/base/preferences.cpp`, `src/base/bittorrent/sessionimpl.cpp`, `src/app/application.cpp`, `src/base/net/proxyconfigurationmanager.cpp`, `src/base/bittorrent/portforwarderimpl.cpp`, `src/base/net/smtpclient.h`.

## Dialog shell

- `OptionsDialog` is a `QDialog`. Left side is a `QListWidget` (`tabSelection`) driving a `QStackedWidget` (`tabOption`). Tab enum order: `TAB_UI(0)`, `TAB_DOWNLOADS(1)`, `TAB_CONNECTION(2)`, `TAB_SPEED(3)`, `TAB_BITTORRENT(4)`, `TAB_SEARCH(5)`, `TAB_RSS(6)`, `TAB_WEBUI(7)`, `TAB_ADVANCED(8)`. Behavior/Downloads/Connection are pages `tabBehaviorPage` / `tabDownloadsPage` / `tabConnectionPage`, each wrapped in a `QScrollArea`.
- Bottom `QDialogButtonBox` = **OK / Cancel / Apply**. `m_applyButton` starts disabled; every control's change signal calls `enableApplyButton()` to enable it. OK → `on_buttonBox_accepted()` → `applySettings()` → runs cross-tab validation (`schedTimesOk()` on Speed, WebUI auth/path checks) then `saveOptions()`, which calls `saveBehaviorTabOptions()`, `saveDownloadsTabOptions()`, `saveConnectionTabOptions()` (+ others). Cancel → `reject()`.
- Persisted window geometry keys: `GUI/Preferences/Geometry` family via `m_storeDialogSize`, `m_storeHSplitterSize`, `m_storeLastViewedPage` (last selected tab row).
- `showConnectionTab()` public slot selects row `TAB_CONNECTION`.

For every row below: **Label** = visible text, **Widget** = objectName / Qt class, **Key** = persisted setting key, **Default** = effective runtime default (config-key default; note where the `.ui` static default differs), **Enable dep** = enable/visibility rule.

---

## 1. BEHAVIOR TAB (`tabBehaviorPage`) — loaded/saved by `loadBehaviorTabOptions()` / `saveBehaviorTabOptions()`

### Group "Interface" (`UISettingsBox`)
Italic notice `labelRestartRequired`: "Changing Interface settings requires application restart".

| Label | Widget / type | Key | Default | Notes / deps |
|---|---|---|---|---|
| Language: | `comboLanguage` combo | `Preferences/General/Locale` | OS locale (matched via `setLocale`, falls back to `en`) | Items built by `initializeLanguageCombo()` (translation list); item userData = locale code. `getLocale()` reads currentIndex userData. |
| Style: | `comboStyle` combo | `Appearance/Style` | empty → `QApplication::style()->name()` | Item 0 = "System" (data `"system"`), separator, then sorted `QStyleFactory::keys()`. Windows-only italic hint `labelStyleHint`: "Fusion is recommended for best compatibility with Windows dark mode". |
| Color scheme: | `comboColorScheme` combo | UIThemeManager (`UIThemeManager::setColorScheme`) | `ColorScheme::System` | Only compiled when `QBT_HAS_COLORSCHEME_OPTION`; items Dark(`ColorScheme::Dark`), Light(`ColorScheme::Light`), System(`ColorScheme::System`). Hidden otherwise. |
| Use custom UI Theme (checkable groupbox) | `checkUseCustomTheme` QGroupBox | `Preferences/General/UseCustomUITheme` | `false` | Effective `useCustomUITheme()` also requires non-empty theme path. |
| › UI Theme file: | `customThemeFilePath` FileSystemPathLineEdit | `Preferences/General/CustomUIThemePath` | empty | Mode `FileOpen`; filter `qBittorrent UI Theme file (*.qbtheme config.json)`; caption "Select qBittorrent UI Theme file". |
| Use icons from system theme | `checkUseSystemIcon` checkbox | `Preferences/Advanced/useSystemIconTheme` | `false` | Only on Unix non-macOS; hidden elsewhere. |
| Customize UI Theme... | `buttonCustomizeUITheme` push | — | — | Opens `UIThemeDialog`. Enabled only when `checkUseCustomTheme` is **un**checked. |

### Group "Transfer List" (`groupBox_4`)

| Label | Widget / type | Key | Default | Notes / deps |
|---|---|---|---|---|
| Confirm when deleting torrents | `confirmDeletion` checkbox | `Preferences/Advanced/confirmTorrentDeletion` | `true` | tooltip "Shows a confirmation dialog upon torrent deletion". |
| Use alternating row colors | `checkAltRowColors` checkbox | `Preferences/General/AlternatingRowColors` | `true` | |
| Use different text colors by torrent states | `checkUseTorrentStatesColors` checkbox | `GUI/TransferList/UseTorrentStatesColors` | `true` | Toggling also enables/disables the next row. |
| Make progress bars follow text colors | `checkProgressBarFollowsTextColor` checkbox | `GUI/TransferList/ProgressBarFollowsTextColor` | `false` | Enabled only when `checkUseTorrentStatesColors` checked. |
| Hide zero and infinity values | `checkHideZero` checkbox | `Preferences/General/HideZeroValues` | `false` | Enables `comboHideZero`. |
| (paired combo) | `comboHideZero` combo | `Preferences/General/HideZeroComboValues` | `0` | Items: "Always"(0), "Stopped torrents only"(1). Enabled only when `checkHideZero` checked. |

Sub-group "Action on double-click" (`groupBox_7`) — both combos share the same 5 items, mapped by `setItemData` to enum `DoubleClickAction`:

- Item order → data: 0 "Start / stop torrent"→`TOGGLE_STOP(0)`, 1 "Open destination folder"→`OPEN_DEST(1)`, 2 "Preview file, otherwise open destination folder"→`PREVIEW_FILE(2)`, 3 "Open torrent options dialog"→`SHOW_OPTIONS(4)`, 4 "No action"→`NO_ACTION(3)`.

| Label | Widget | Key | Default |
|---|---|---|---|
| Downloading torrents: | `actionTorrentDlOnDblClBox` combo | `Preferences/Downloads/DblClOnTorDl` | `0` (TOGGLE_STOP) |
| Completed torrents: | `actionTorrentFnOnDblClBox` combo | `Preferences/Downloads/DblClOnTorFn` | `1` (OPEN_DEST) |

| Label | Widget | Key | Default |
|---|---|---|---|
| Auto hide zero status filters | `checkBoxHideZeroStatusFilters` checkbox | `TransferListFilters/HideZeroStatusFilters` | `false` |
| Use separate "Tracker status" filter | `checkBoxUseSeparateTrackerStatusFilter` checkbox | `TransferListFilters/SeparateTrackerStatusFilter` | `false` |

### Group "Torrent Content View" (`boxTorrentContent`)

| Label | Widget | Key | Default | Notes |
|---|---|---|---|---|
| Drag content from qBittorrent | `checkTorrentContentDrag` checkbox | `Preferences/General/TorrentContentDragEnabled` | `false` | tooltip "Replaces multi-selection (hold Alt key to invert)". |

### Group "Status Bar" (`statusBarGroup`)

| Label | Widget | Key | Default |
|---|---|---|---|
| Show free disk space | `checkBoxFreeDiskSpaceStatusBar` checkbox | `Preferences/General/StatusbarFreeDiskSpaceDisplayed` | `false` |
| Show external IP | `checkBoxExternalIPStatusBar` checkbox | `Preferences/General/StatusbarExternalIPDisplayed` | `false` |

### Group "Desktop" (`systrayBox`)

| Label | Widget / type | Key | Default | Notes / deps |
|---|---|---|---|---|
| Start qBittorrent on Windows start up | `checkStartup` checkbox | Windows registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (per-profile ID) | registry-derived | Windows only; hidden otherwise. `Preferences::WinStartup()`/`setWinStartup()`. |
| Show splash screen on start up | `checkShowSplash` checkbox | `Preferences/General/NoSplashScreen` (stored inverted) | key default `true` ⇒ checkbox **unchecked** by default (splash disabled). `.ui` static default is checked. | `checkShowSplash = !isSplashScreenDisabled()`; saved via `setSplashScreenDisabled(!checked)`. |
| Window state on start up: | `windowStateComboBox` combo | `GUI/StartUpWindowState` | `WindowState::Normal` | Items: Normal(`WindowState::Normal`), Minimized(`WindowState::Minimized`), Hidden(`WindowState::Hidden`, omitted on macOS). `app()->startUpWindowState()`/`setStartUpWindowState()`. |
| Confirmation on exit when torrents are active | `checkProgramExitConfirm` checkbox | `Preferences/General/ExitConfirm` | `true` | |
| Confirmation on auto-exit when downloads finish | `checkProgramAutoExitConfirm` checkbox | `ShutdownConfirmDlg/DontConfirmAutoExit` (stored inverted) | key default `false` ⇒ checkbox checked | `checked = !dontConfirmAutoExit()`. |
| Show &qBittorrent in notification area (checkable groupbox) | `checkShowSystray` QGroupBox | `Preferences/General/SystrayEnabled` | `true` | Non-macOS only (hidden on macOS). Force-disabled + unchecked if `QSystemTrayIcon::isSystemTrayAvailable()` is false (tooltip "Disabled due to failed to detect system tray presence"). |
| › Minimize qBittorrent to notification area | `checkMinimizeToSysTray` checkbox | `Preferences/General/MinimizeToTray` | `false` | |
| › Close qBittorrent to notification area | `checkCloseToSystray` checkbox | `Preferences/General/CloseToTray` | `true` | |
| › Tray icon style: | `comboTrayIcon` combo | UIThemeManager (`setTrayIconStyle(TrayIconStyle)`) | index 0 (Normal) | Items: "Normal"(0), "Monochrome"(1). |
| File association (groupbox `groupFileAssociation`) | — | — | — | Hidden on Linux (`#if !(Q_OS_WIN||Q_OS_MACOS)`). Contains two panels: |
| › Use qBittorrent for .torrent files | `checkAssociateTorrents` checkbox | macOS `MacUtils::setTorrentFileAssoc()` | OS state | macOS-only panel `assocPanel` (hidden on Windows). |
| › Use qBittorrent for magnet links | `checkAssociateMagnetLinks` checkbox | macOS `MacUtils::setMagnetLinkAssoc()` | OS state | macOS. |
| › (Windows) info label | `labelSetAssoc` in `defaultProgramPanel` | — | — | Windows text pointing to Control Panel Default Programs (hidden on macOS). |
| Check for program updates | `checkProgramUpdates` checkbox | `Preferences/Advanced/updateCheck` | `true` | Only on Windows/macOS; hidden on Linux. |
| Show speed in Dock | `checkShowSpeedInDock` checkbox | `Preferences/Desktop/ShowSpeedInDock` | `true` | macOS only. |
| Show qBittorrent in menu bar | `checkShowMenuBarIcon` checkbox | `Preferences/Desktop/ShowMacOSMenuBarIcon` | `true` | macOS only. |

### Group "Power Management" (`groupBox`)

| Label | Widget | Key | Default | Deps |
|---|---|---|---|---|
| Inhibit system sleep when torrents are downloading | `checkPreventFromSuspendWhenDownloading` checkbox | `Preferences/General/PreventFromSuspendWhenDownloading` | `false` | Force-disabled on Unix-non-macOS without D-Bus. |
| Inhibit system sleep when torrents are seeding | `checkPreventFromSuspendWhenSeeding` checkbox | `Preferences/General/PreventFromSuspendWhenSeeding` | `false` | Same D-Bus dep. |

### Group "&Log Files" (`checkFileLog`, checkable groupbox) — all keys under `Application/FileLogger/...`

| Label | Widget / type | Key | Default | Deps |
|---|---|---|---|---|
| &Log Files (enable) | `checkFileLog` QGroupBox | `Application/FileLogger/Enabled` | `true` | Master enable. `app()->isFileLoggerEnabled()`. |
| Save path: | `textFileLogPath` FileSystemPathLineEdit | `Application/FileLogger/Path` | `{DataLocation}/logs` | Mode `DirectorySave`, caption "Choose a save directory". |
| Backup the log file after: | `checkFileLogBackup` checkbox | `Application/FileLogger/Backup` | `true` | Enables `spinFileLogSize`. tooltip "Creates an additional log file after the log file reaches the specified file size". |
| (size spin) | `spinFileLogSize` spin, suffix " KiB" | `Application/FileLogger/MaxSizeBytes` | `65` KiB (`DEFAULT_FILELOG_SIZE`=66560 bytes) | UI range min 1 / max 1024000 KiB; stored in **bytes** (value×1024), clamped `[1024, 1048576000]`. |
| Delete backup logs older than: | `checkFileLogDelete` checkbox | `Application/FileLogger/DeleteOld` | `true` | Enables `spinFileLogAge` + `comboFileLogAgeType`. |
| (age spin) | `spinFileLogAge` spin | `Application/FileLogger/Age` | `1` (`.ui` static shows 6) | range min 1 / max 365, clamped `[1,365]`. |
| (age unit combo) | `comboFileLogAgeType` combo | `Application/FileLogger/AgeType` | `1` (months) | Items: "days"(0), "months"(1), "years"(2); out-of-range coerced to 1. |

### Standalone (Behavior)

| Label | Widget | Key | Default |
|---|---|---|---|
| Log performance warnings | `checkBoxPerformanceWarning` checkbox | `BitTorrent/Session/PerformanceWarning` | `false` |

**Not present on this tab** (task list vs. actual code): there is no "scan interval" control here (watched folders live on Downloads), and no "UI lock"/password here (that belongs to the WebUI tab). Desktop notifications are represented only by the systray group.

---

## 2. DOWNLOADS TAB (`tabDownloadsPage`) — `loadDownloadsTabOptions()` / `saveDownloadsTabOptions()`

### Group "When adding a torrent" (`torrentAdditionBox`)

| Label | Widget / type | Key | Default | Deps |
|---|---|---|---|---|
| Display &torrent content and some options (checkable groupbox) | `checkAdditionDialog` QGroupBox | `AddNewTorrentDialog/Enabled` | `true` | `useAdditionDialog()`. Also gates `checkConfirmMergeTrackers` enable. |
| › Bring torrent dialog to the front | `checkAdditionDialogFront` checkbox | `AddNewTorrentDialog/TopLevel` | `true` | |
| Torrent content layout: | `contentLayoutComboBox` combo | `BitTorrent/Session/TorrentContentLayout` | `Original`(0) | Items: "Original"(`TorrentContentLayout::Original`), "Create subfolder"(`Subfolder`), "Don't create subfolder"(`NoSubfolder`). |
| Add to top of queue | `checkAddToQueueTop` checkbox | `BitTorrent/Session/AddTorrentToTopOfQueue` | `false` | |
| Do not start the download automatically | `checkAddStopped` checkbox | `BitTorrent/Session/AddTorrentStopped` | `false` | `addTorrentsStopped()`. When checked, disables `stopConditionLabel`+`stopConditionComboBox`. |
| Torrent stop condition: | `stopConditionComboBox` combo | `BitTorrent/Session/TorrentStopCondition` | `None` | Items→data enum: "None"(`StopCondition::None`), "Metadata received"(`MetadataReceived`), "Files checked"(`FilesChecked`). Rich tooltip explains each. Enabled only when `checkAddStopped` unchecked. |

Sub-group "When adding a duplicate torrent" (`duplicateTorrentGroup`):

| Label | Widget | Key | Default | Deps |
|---|---|---|---|---|
| Merge trackers to existing torrent | `checkMergeTrackers` checkbox | `BitTorrent/MergeTrackersEnabled` | `false` | |
| Ask to merge trackers for manually added torrent | `checkConfirmMergeTrackers` checkbox | `GUI/ConfirmActions/MergeTrackers` | `true` | Enabled only when `checkAdditionDialog` checked; forced `false` when that groupbox is off. |

Sub-group "De&lete .torrent files afterwards " (`deleteTorrentBox`, checkable groupbox) → maps to `TorrentFileGuard::AutoDeleteMode`:

| Label | Widget | Mapping | Default |
|---|---|---|---|
| De&lete .torrent files afterwards (enable) | `deleteTorrentBox` QGroupBox | checked = mode ≠ `Never` | unchecked (`Never`) |
| › Also when addition is cancelled | `deleteCancelledTorrentBox` checkbox | checked ⇒ `Always`, else `IfAdded` | unchecked |

Save logic: `TorrentFileGuard::setAutoDeleteMode(!box ? Never : !cancelled ? IfAdded : Always)`. Hidden warning icon (`deleteTorrentWarningIcon`, `SP_MessageBoxCritical`) + label "Warning! Data loss possible!" become visible when `deleteTorrentBox` is checked.

### Standalone checkboxes (Downloads)

| Label | Widget | Key | Default | Notes |
|---|---|---|---|---|
| Pre-allocate disk space for all files | `checkPreallocateAll` checkbox | `BitTorrent/Session/Preallocation` | `false` | `preAllocateAllFiles()`. tooltip re HDD fragmentation. |
| Append .!qB extension to incomplete files | `checkAppendqB` checkbox | `BitTorrent/Session/AddExtensionToIncompleteFiles` | `false` | |
| Keep unselected files in ".unwanted" folder | `checkUnwantedFolder` checkbox | `BitTorrent/Session/UseUnwantedFolder` | `false` | |
| Enable recursive download dialog | `checkRecursiveDownload` checkbox | `Preferences/Advanced/DisableRecursiveDownload` (stored inverted) | enabled (`true`) | `isRecursiveDownloadEnabled = !DisableRecursiveDownload`. |

### Group "Saving Management" (`groupSavingManagement`)

Each TMM combo stores an inverted/boolean and maps index 0/1:

| Label | Widget | Key | Default index | Items (index→meaning) |
|---|---|---|---|---|
| Default Torrent Management Mode: | `comboSavingMode` combo | `BitTorrent/Session/DisableAutoTMMByDefault` (default `true`) | `0` = Manual | "Manual"(0), "Automatic"(1). Save: `setAutoTMMDisabledByDefault(index==0)`. |
| When Torrent Category changed: | `comboTorrentCategoryChanged` combo | `BitTorrent/Session/DisableAutoTMMTriggers/CategoryChanged` (default `false`) | `0` | "Relocate torrent"(0), "Switch torrent to Manual Mode"(1). |
| When Default Save/Incomplete Path changed: | `comboCategoryDefaultPathChanged` combo | `BitTorrent/Session/DisableAutoTMMTriggers/DefaultSavePathChanged` (default `true`) | `1` | "Relocate affected torrents"(0), "Switch affected torrents to Manual Mode"(1). |
| When Category Save Path changed: | `comboCategoryChanged` combo | `BitTorrent/Session/DisableAutoTMMTriggers/CategorySavePathChanged` (default `true`) | `1` | same two items. |
| Use Category paths in Manual Mode | `checkUseCategoryPaths` checkbox | `BitTorrent/Session/UseCategoryPathsInManualMode` | `false` | tooltip re resolving relative save path against category path. |

Path grid (`gridLayout_4`):

| Label | Widget / type | Key | Default | Deps |
|---|---|---|---|---|
| Default Save Path: | `textSavePath` FileSystemPathLineEdit | `BitTorrent/Session/DefaultSavePath` | OS Downloads folder (`specialFolderLocation(Downloads)`) | Mode `DirectorySave`. |
| Use another path for incomplete torrents: | `checkUseDownloadPath` checkbox + `textDownloadPath` | enable `BitTorrent/Session/TempPathEnabled` (`false`); path `BitTorrent/Session/TempPath` (default `{savePath}/temp`) | disabled | `textDownloadPath` enabled only when checkbox checked. |
| Copy .torrent files to: | `checkExportDir` checkbox + `textExportDir` | `BitTorrent/Session/TorrentExportDirectory` | empty (checkbox = !empty) | `getTorrentExportDir()` returns path or `{}`. Field enabled only when checked. |
| Copy .torrent files for finished downloads to: | `checkExportDirFin` checkbox + `textExportDirFin` | `BitTorrent/Session/FinishedTorrentExportDirectory` | empty | `getFinishedTorrentExportDir()`. Field enabled only when checked. |

### Group "Automatically add torrents from:" (`groupBox_2`) — watched folders

- `scanFoldersView` `QTreeView` bound to `WatchedFoldersModel` (wraps `TorrentFilesWatcher::instance()`). **1 column**, header "Watched Folder" (`headerData` returns `tr("Watched Folder")`; `columnCount()==1`, display = folder path). Single selection, select-rows, all edit triggers, `rootIsDecorated=false`.
- Buttons: `addWatchedFolderButton` "Add...", `editWatchedFolderButton` "Options.." (disabled until exactly 1 row selected), `removeWatchedFolderButton` "Remove" (disabled until ≥1 selected). Selection rules in `handleWatchedFolderViewSelectionChanged()`.
- **Add flow** (`on_addWatchedFolderButton_clicked`): `QFileDialog::getExistingDirectory` (caption "Select folder to monitor", start = `Preferences::getScanDirsLastPath().parentPath()`), then opens **`WatchedFolderOptionsDialog`**; on accept calls `WatchedFoldersModel::addFolder(dir, options)` and stores `Preferences/Downloads/ScanDirsLastPath`.
- **Edit flow** (`editWatchedFolderOptions`/double-click): opens `WatchedFolderOptionsDialog` seeded with `folderOptions(row)`; on accept `setFolderOptions(row, ...)`.
- Save: `WatchedFoldersModel::apply()`.
- **`WatchedFolderOptionsDialog`** (`watchedfolderoptionsdialog.ui`, title "Watched Folder Options"): `checkBoxRecursive` "Recursive mode" (+tooltip re subfolders) and a "Torrent parameters" group (`groupBoxParameters`) for save path / TMM overrides.

### Group "Excluded file names" (`groupExcludedFileNames`, checkable)

| Label | Widget / type | Key | Default | Notes |
|---|---|---|---|---|
| Excluded file names (enable) | `groupExcludedFileNames` QGroupBox | `BitTorrent/ExcludedFileNamesEnabled` | `false` | `session->isExcludedFileNamesEnabled()`. |
| (list) | `textExcludedFileNames` QPlainTextEdit (no wrap) | `BitTorrent/Session/ExcludedFileNames` | empty | Newline-separated; saved via `split('\n', SkipEmptyParts)`. Long tooltip documents wildcard syntax (`*`, `?`, `[...]`). |

### Group "Email notification &upon download completion" (`groupMailNotification`, checkable) — keys under `Preferences/MailNotification/...`

| Label | Widget / type | Key | Default | Notes |
|---|---|---|---|---|
| Email notification upon download completion (enable) | `groupMailNotification` QGroupBox | `Preferences/MailNotification/enabled` | `false` | |
| From: | `senderEmailTxt` QLineEdit | `.../sender` | empty | placeholder `qBittorrent_notification@example.com`. |
| To: | `lineEditDestEmail` QLineEdit | `.../email` | empty | tooltip documents `;` / `,` separators. |
| SMTP server: | `lineEditSMTPServer` QLineEdit | `.../smtp_server` | empty | placeholder `smtp.example.com:465`; `:port` suffix supported. |
| SMTP encryption: | `comboSMTPEncryption` combo | `.../SMTPEncryptionType` | `SMTPS` | Items→data enum `Net::SMTPEncryptionType`: None, STARTTLS, SMTPS. `labelSMTPEncryptionPortInfo` shows "Default port: N" via `changeSMTPEncryptionPortInfoLabel()` — None→25, STARTTLS→587, SMTPS→465 (`SMTP_DEFAULT_PORT`/`_STARTTLS`/`_SSL`). |
| Authentication (checkable groupbox) | `groupMailNotifAuth` QGroupBox | `.../req_auth` | `false` | |
| › Username: | `mailNotifUsername` QLineEdit | `.../username` | empty | |
| › Password: | `mailNotifPassword` QLineEdit (Password echo) | `.../password` | empty | |
| Send test email | `sendTestEmail` push | — | — | Calls `app()->sendTestEmail()`, then info dialog. |

### Group "Run external program" (`autoRunBox`)

| Label | Widget / type | Key | Default | Deps |
|---|---|---|---|---|
| Run on torrent added: (checkable groupbox) | `groupBoxRunOnAdded` QGroupBox | `AutoRun/OnTorrentAdded/Enabled` | `false` | |
| › (command) | `lineEditRunOnAdded` QLineEdit | `AutoRun/OnTorrentAdded/Program` | empty | trimmed on save. |
| Run on torrent finished: (checkable groupbox) | `groupBoxRunOnFinished` QGroupBox | `AutoRun/enabled` | `false` | |
| › (command) | `lineEditRunOnFinished` QLineEdit | `AutoRun/program` | empty | trimmed on save. |
| Show console window | `autoRunConsole` checkbox | `AutoRun/ConsoleEnabled` | `false` | Windows only; hidden otherwise. |
| (help text) | `labelAutoRunParam` label | — | — | Lists supported substitution params: `%N` name, `%L` category, `%G` tags, `%F` content path, `%R` root path, `%D` save path, `%C` file count, `%Z` size (bytes), `%T` current tracker, `%I` infohash v1, `%J` infohash v2, `%K` torrent ID, `%M` comment. |

**Not on this tab:** "disk cache" is not on Downloads in this codebase — it lives on the **Advanced** tab (`BitTorrent/Session/DiskCacheSize` default -1, `DiskCacheTTL` 60, `DiskQueueSize` 1MiB, `DiskIO*`).

---

## 3. CONNECTION TAB (`tabConnectionPage`) — `loadConnectionTabOptions()` / `saveConnectionTabOptions()`

### Top-level

| Label | Widget | Key | Default | Notes |
|---|---|---|---|---|
| Peer connection protocol: | `comboProtocol` combo | `BitTorrent/Session/BTProtocol` | `Both`(index 0) | Items→`BTProtocol` by index: "TCP and μTP"(0=Both), "TCP"(1), "μTP"(2). `session->btProtocol()`/`setBTProtocol`. |

### Group "Listening Port" (`ListeningPortBox`)

| Label | Widget / type | Key | Default | Notes |
|---|---|---|---|---|
| Port used for incoming connections: | `spinPort` spin | `BitTorrent/Session/Port` | key default `-1`; UI min 0 max 65535, `specialValueText="Any"` at 0 | `getPort()` = spin value. tooltip "Set to 0 to let your system pick an unused port". |
| Random | `randomButton` push | — | — | Sets `spinPort` to `Utils::Random::rand(1024, 65535)`. |
| Use UPnP / NAT-PMP port forwarding from my router | `checkUPnP` checkbox | `Network/PortForwardingEnabled` | `true` | `Net::PortForwarder::instance()->isEnabled()`/`setEnabled()`. |

### Group "Connections Limits" (`nbConnecBox`)
Each row = checkbox (enable) + spin. On load: checkbox checked iff session value > 0; spin enabled iff checked. Getter returns `-1` when unchecked.

| Label | Checkbox / Spin | Key | Default | Spin range (ui value) |
|---|---|---|---|---|
| Global maximum number of connections: | `checkMaxConnections` / `spinMaxConnec` | `BitTorrent/Session/MaxConnections` | `500` (>0 ⇒ checked) | min 2, max 2147483647 (ui 500) |
| Maximum number of connections per torrent: | `checkMaxConnectionsPerTorrent` / `spinMaxConnecPerTorrent` | `BitTorrent/Session/MaxConnectionsPerTorrent` | `100` | min 2, max 2147483647 (ui 100) |
| Global maximum number of upload slots: | `checkMaxUploads` / `spinMaxUploads` | `BitTorrent/Session/MaxUploads` | `20` (ui static 8) | min 0, max 2147483647 |
| Maximum number of upload slots per torrent: | `checkMaxUploadsPerTorrent` / `spinMaxUploadsPerTorrent` | `BitTorrent/Session/MaxUploadsPerTorrent` | `4` | min 0, max 2147483647 |

Getters: `getMaxConnections()/getMaxConnectionsPerTorrent()/getMaxUploads()/getMaxUploadsPerTorrent()` → spin value or `-1`.

### Group "I2P (experimental)" (`groupI2P`, checkable) — only when `QBT_USES_LIBTORRENT2 && TORRENT_USE_I2P`; hidden otherwise

| Label | Widget / type | Key | Default |
|---|---|---|---|
| I2P (experimental) (enable) | `groupI2P` QGroupBox | `BitTorrent/Session/I2P/Enabled` | `false` |
| Host: | `textI2PHost` QLineEdit | `BitTorrent/Session/I2P/Address` | `127.0.0.1` |
| Port: | `spinI2PPort` spin (min 1, max 65535, ui 8080) | `BitTorrent/Session/I2P/Port` | `7656` |
| Mixed mode | `checkI2PMixed` checkbox | `BitTorrent/Session/I2P/MixedMode` | `false` |

(Save trims host: `setI2PAddress(text().trimmed())`.)

### Group "Proxy Server" (`groupProxy`) — proxy fields under `Network/Proxy/...` via `Net::ProxyConfigurationManager` (`ProxyConfiguration{type, ip, port, authEnabled, username, password, hostnameLookupEnabled}`)

| Label | Widget / type | Key | Default | Notes |
|---|---|---|---|---|
| Type: | `comboProxyType` combo | `Network/Proxy/Type` | `Net::ProxyType::None` | Items→data enum: "(None)"(`None`), "SOCKS4"(`SOCKS4`), "SOCKS5"(`SOCKS5`), "HTTP"(`HTTP`). Change → `adjustProxyOptions()`. |
| Host: | `textProxyIP` QLineEdit | `Network/Proxy/IP` | `""` when type None, else `0.0.0.0` | `getProxyIp()` trims. |
| Port: | `spinProxyPort` spin (min 1, max 65535, ui 8080) | `Network/Proxy/Port` | `8080` | |
| (unavailable notice) | `labelProxyTypeUnavailable` italic label | — | — | "Some functions are unavailable with the chosen proxy type!" — visible only for SOCKS4. |
| Perform hostname lookup via proxy | `checkProxyHostnameLookup` checkbox | `Network/Proxy/HostnameLookupEnabled` | `true` | Enabled only for SOCKS5/HTTP. |
| A&uthentication (checkable groupbox) | `checkProxyAuth` QGroupBox | `Network/Proxy/AuthEnabled` | `false` (widget starts disabled) | Enabled only for SOCKS5/HTTP (`isAuthSupported`). |
| › Username: | `textProxyUsername` QLineEdit | `Network/Proxy/Username` | empty | trimmed. |
| › Password: | `textProxyPassword` QLineEdit (Password echo) | `Network/Proxy/Password` | empty | trimmed. Static note label_23 "Note: The password is saved unencrypted". |
| Use proxy for BitTorrent purposes (checkable groupbox) | `checkProxyBitTorrent` QGroupBox | `Network/Proxy/Profiles/BitTorrent` | `false` | Enabled when type ≠ None. Toggling also re-runs `adjustProxyOptions()`. |
| › Use proxy for peer connections | `checkProxyPeerConnections` checkbox | `BitTorrent/Session/ProxyPeerConnections` | `false` | `session->isProxyPeerConnectionsEnabled()`. tooltip "Otherwise, the proxy server is only used for tracker connections". |
| Use proxy for RSS purposes | `checkProxyRSS` checkbox | `Network/Proxy/Profiles/RSS` | `false` | Enabled only for SOCKS5/HTTP. |
| Use proxy for general purposes | `checkProxyMisc` checkbox | `Network/Proxy/Profiles/Misc` | `false` | Enabled only for SOCKS5/HTTP. |

**`adjustProxyOptions()` enable matrix:**
- **None** → host/port labels+fields disabled; hostname-lookup, RSS, Misc, BitTorrent, PeerConnections all disabled; unavailable-label hidden; auth disabled.
- **SOCKS4** → host/port + `checkProxyBitTorrent` + `checkProxyPeerConnections` enabled; hostname-lookup + RSS + Misc disabled; unavailable-label **shown**; auth disabled (SOCKS4 has no auth).
- **SOCKS5 / HTTP** → everything enabled including auth (`checkProxyAuth`).

### Group "IP Fi&ltering" (`groupIPFilter`)

| Label | Widget / type | Key | Default | Deps / notes |
|---|---|---|---|---|
| Filter path (.dat, .p2p, .p2b): | `checkIPFilter` checkbox + `textFilterPath` FileSystemPathLineEdit | enable `BitTorrent/Session/IPFilteringEnabled` (`false`); file `BitTorrent/Session/IPFilter` (empty) | disabled | `isIPFilteringEnabled()`=checkbox; `getFilter()`=path. Field + refresh button enabled only when `checkIPFilter` checked. File filter: `All supported filters (*.dat *.p2p *.p2b);;.dat (*.dat);;.p2p (*.p2p);;.p2b (*.p2b)`; caption "Choose an IP filter file". |
| (reload) | `IpFilterRefreshBtn` QToolButton (icon `view-refresh`, tooltip "Reload the filter") | — | — | `on_IpFilterRefreshBtn_clicked()` force-reloads filter via `session->setIPFilterFile({})` then real path; `IPFilterParsed` signal → success/failure dialog ("Successfully parsed the provided IP filter: N rules were applied." / "Failed to parse the provided IP filter"). |
| Manually banned IP addresses... | `banListButton` push | — | — | Opens **`BanListOptionsDialog`** (edits `BitTorrent/Session/BannedIPs`); accept enables Apply. |
| Apply to trackers | `checkIpFilterTrackers` checkbox | `BitTorrent/Session/TrackerFilteringEnabled` | `false` | `session->isTrackerFilteringEnabled()`. |

> Note: the "IP subnet whitelist..." button (`IPSubnetWhitelistButton` → `IPSubnetWhitelistOptionsDialog`) and "Filter tracker" URL lists are **not** on this Connection tab — the subnet whitelist button lives on the **WebUI** tab. The Connection IP-filter section covers filter file + "Apply to trackers" only.

---

## Backend/engine API consumed by these three tabs

- **`BitTorrent::Session::instance()`** (Downloads/Connection + Behavior perf-warning): `btProtocol()/setBTProtocol(BTProtocol)`, `port()/setPort(int)`, `maxConnections()/setMaxConnections`, `maxConnectionsPerTorrent()/set…`, `maxUploads()/set…`, `maxUploadsPerTorrent()/set…`, `torrentContentLayout()/setTorrentContentLayout(TorrentContentLayout)`, `isAddTorrentToQueueTop()/set…`, `isAddTorrentStopped()/set…`, `torrentStopCondition()/setTorrentStopCondition(Torrent::StopCondition)`, `isMergeTrackersEnabled()/set…`, `isPreallocationEnabled()/set…`, `isAppendExtensionEnabled()/set…`, `isUnwantedFolderEnabled()/set…`, `isAutoTMMDisabledByDefault()/set…`, `isDisableAutoTMMWhenCategoryChanged()/set…`, `isDisableAutoTMMWhenCategorySavePathChanged()/set…`, `isDisableAutoTMMWhenDefaultSavePathChanged()/set…`, `useCategoryPathsInManualMode()/set…`, `savePath()/setSavePath(Path)`, `isDownloadPathEnabled()/set…`, `downloadPath()/setDownloadPath(Path)`, `torrentExportDirectory()/set…`, `finishedTorrentExportDirectory()/set…`, `isExcludedFileNamesEnabled()/set…`, `excludedFileNames()/setExcludedFileNames(QStringList)`, `I2PAddress()/set…`, `I2PPort()/set…`, `I2PMixedMode()/set…`, `isI2PEnabled()/setI2PEnabled`, `isProxyPeerConnectionsEnabled()/set…`, `isIPFilteringEnabled()/setIPFilteringEnabled`, `isTrackerFilteringEnabled()/set…`, `IPFilterFile()/setIPFilterFile(Path)`, `isPerformanceWarningEnabled()/set…`; signal `IPFilterParsed(bool error, int ruleCount)`.
- **`Net::PortForwarder::instance()`**: `isEnabled()/setEnabled(bool)`.
- **`Net::ProxyConfigurationManager::instance()`**: `proxyConfiguration()/setProxyConfiguration(Net::ProxyConfiguration)`.
- **`Preferences::instance()`**: all `Preferences/...`, `AutoRun/...`, `AddNewTorrentDialog/...`, `MailNotification/...`, `Network/Proxy/Profiles/...`, `GUI/...`, `TransferListFilters/...`, `Appearance/Style`, `ShutdownConfirmDlg/DontConfirmAutoExit` getters/setters listed above; plus `loadTranslation(locale)` on locale change.
- **`app()` (Application/IGUIApplication)**: file-logger getters/setters, `startUpWindowState()/setStartUpWindowState(WindowState)`, `sendTestEmail()`, `fileLoggerPath()`.
- **`UIThemeManager::instance()`**: `colorScheme()/setColorScheme(ColorScheme)`, `trayIconStyle()/setTrayIconStyle(TrayIconStyle)`.
- **`TorrentFileGuard`**: `autoDeleteMode()/setAutoDeleteMode(AutoDeleteMode)` with `Never / IfAdded / Always`.
- **`TorrentFilesWatcher::instance()`** via `WatchedFoldersModel` (`addFolder`, `folderOptions`, `setFolderOptions`, `removeRow`, `apply`).

### Enums referenced
- `DoubleClickAction { TOGGLE_STOP=0, OPEN_DEST=1, PREVIEW_FILE=2, NO_ACTION=3, SHOW_OPTIONS=4 }` (combo order maps 0,1,2,4,3).
- `BitTorrent::TorrentContentLayout { Original, Subfolder, NoSubfolder }` (by combo index).
- `BitTorrent::Torrent::StopCondition { None, MetadataReceived, FilesChecked }`.
- `BitTorrent::BTProtocol { Both, TCP, UTP }` (by combo index).
- `Net::ProxyType { None, SOCKS4, SOCKS5, HTTP }` (as used by the combo).
- `Net::SMTPEncryptionType { None, STARTTLS, SMTPS }`; ports 25 / 587 / 465.
- `WindowState { Normal, Minimized, Hidden }`; `ColorScheme { Dark, Light, System }`; `TrayIconStyle { Normal, Monochrome }`.

---

# Area: Options Dialog — Speed, BitTorrent, RSS, WebUI & Advanced tabs

## Options Dialog — shared structure

Source: `src/gui/optionsdialog.{h,cpp,ui}`, `src/gui/advancedsettings.{h,cpp}`.

The dialog is a two-pane preferences window: a left `QListWidget` (`tabSelection`) drives a right-hand `QStackedWidget` (`tabOption`) via `OptionsDialog::changePage()` (each list row maps 1:1 to a stacked page by index). Tab order (enum `Tabs` in `optionsdialog.h`): `TAB_UI(0)`, `TAB_DOWNLOADS(1)`, `TAB_CONNECTION(2)`, `TAB_SPEED(3)`, `TAB_BITTORRENT(4)`, `TAB_SEARCH(5)`, `TAB_RSS(6)`, `TAB_WEBUI(7)`, `TAB_ADVANCED(8)`. WebUI row is hidden when built with `DISABLE_WEBUI`. Each page is a `QScrollArea` wrapping a vertical layout of `QGroupBox`es. Bottom button box: OK / Cancel / Apply. Any control change calls `enableApplyButton()` (connected per-widget). `saveOptions()` calls each tab's `save*TabOptions()`; the constructor calls each `load*TabOptions()`. Last-viewed page persisted in `GUI/...LastViewedPage` (`m_storeLastViewedPage`).

Backends: `BitTorrent::Session::instance()` (session settings), `Preferences::instance()` (app/UI settings), `RSS::Session` + `RSS::AutoDownloader`, plus `IGUIApplication`/`MainWindow`/`DesktopIntegration` for the Advanced tab. Config keys below are the literal `SettingValue`/`value()` keys and defaults as found in `sessionimpl.cpp`, `preferences.cpp`, `rss_session.cpp`, `rss_autodownloader.cpp`, `application.cpp`, `mainwindow.cpp`, `desktopintegration.cpp`.

---

## SPEED TAB (`tabSpeedPage`) — load/`saveSpeedTabOptions`

### GroupBox "Global Rate Limits" (`rateLimitBox`)
- Icon label `labelGlobalRate` (pixmap `slow_off`, medium icon size).
- **Upload:** (`label_10`) — `spinUploadLimit` **QSpinBox**, suffix ` KiB/s`, specialValueText `∞` (0 = unlimited), max 2000000, AdaptiveDecimalStepType, .ui default 100. Bound `session->globalUploadSpeedLimit()/setGlobalUploadSpeedLimit()` (value ×1024). Key `BitTorrent/Session/GlobalUPSpeedLimit`, default 0 (lowerLimited 0).
- **Download:** (`label_11`) — `spinDownloadLimit` **QSpinBox**, same props. Bound `globalDownloadSpeedLimit()/setGlobalDownloadSpeedLimit()`. Key `BitTorrent/Session/GlobalDLSpeedLimit`, default 0.

### GroupBox "Alternative Rate Limits" (`altRateLimitBox`)
- Icon label `labelAltRate` (pixmap `slow`).
- **Upload:** `spinUploadLimitAlt` **QSpinBox** (suffix ` KiB/s`, `∞`, max 2000000, .ui default 10). Bound `altGlobalUploadSpeedLimit()/setAltGlobalUploadSpeedLimit()` (×1024). Key `BitTorrent/Session/AlternativeGlobalUPSpeedLimit`, default 10.
- **Download:** `spinDownloadLimitAlt` **QSpinBox** (same). Bound `altGlobalDownloadSpeedLimit()/set...`. Key `BitTorrent/Session/AlternativeGlobalDLSpeedLimit`, default 10.
- **Checkable GroupBox "Schedule the use of alternative rate limits" (`groupBoxSchedule`)** — checkable, default unchecked. Bound `session->isBandwidthSchedulerEnabled()/setBandwidthSchedulerEnabled()`. Key `BitTorrent/Session/BandwidthSchedulerEnabled`, default false. Contains:
  - **From:** (`label_6`) `timeEditScheduleFrom` **QTimeEdit** (displayFormat `hh:mm`, wrapping, .ui default 08:00). Bound `pref->getSchedulerStartTime()/setSchedulerStartTime()`. Key `Preferences/Scheduler/start_time`, default QTime(8,0).
  - **To:** (`label_17`) `timeEditScheduleTo` **QTimeEdit** (.ui default 20:00). Key `Preferences/Scheduler/end_time`, default QTime(20,0). (Validation `schedTimesOk()`: from and to must differ.)
  - **When:** (`label_18`) `comboBoxScheduleDays` **QComboBox**. Static items index 0..2: `Every day`, `Weekdays`, `Weekends`; then `translatedWeekdayNames()` appended at load (Monday..Sunday → indices 3..9 mapping to `Scheduler::Days`). Bound `pref->getSchedulerDays()/setSchedulerDays()` via `static_cast<Scheduler::Days>(index)`. Key `Preferences/Scheduler/days`, default `Scheduler::Days::EveryDay`.

### GroupBox "Rate Limits Settings" (`rateLimitsGroupBox`)
- **QCheckBox "Apply rate limit to µTP protocol" (`checkLimituTPConnections`)** — `session->isUTPRateLimited()/setUTPRateLimited()`. Key `BitTorrent/Session/uTPRateLimited`, default true.
- **QCheckBox "Apply rate limit to transport overhead" (`checkLimitTransportOverhead`)** — `includeOverheadInLimits()/setIncludeOverheadInLimits()`. Key `BitTorrent/Session/IncludeOverheadInLimits`, default false.
- **QCheckBox "Apply rate limit to peers on LAN" (`checkLimitLocalPeerRate`)** — inverted: `setIgnoreLimitsOnLAN(!checked)`, load `setChecked(!ignoreLimitsOnLAN())`. Key `BitTorrent/Session/IgnoreLimitsOnLAN`, default false.

### macOS-only (checkboxes physically on the UI tab but loaded/saved here)
- `checkShowSpeedInDock` "Show speed in Dock" — key `Preferences/Desktop/ShowSpeedInDock`, default true.
- `checkShowMenuBarIcon` "Show qBittorrent in menu bar" — key `Preferences/Desktop/ShowMacOSMenuBarIcon`, default true. Both `hide()`'d on non-macOS.

---

## BITTORRENT TAB (`tabBitTorrentPage`) — load/`saveBittorrentTabOptions`

### GroupBox "Privacy" (`AddBTFeaturesBox`)
- **QCheckBox "Enable DHT (decentralized network) to find more peers" (`checkDHT`)**, tooltip "Find peers on the DHT network", .ui checked. `session->isDHTEnabled()/setDHTEnabled()` (helper `isDHTEnabled()`). Key `BitTorrent/Session/DHTEnabled`, default true.
- **QCheckBox "Enable Peer Exchange (PeX) to find more peers" (`checkPeX`)**, .ui checked. `isPeXEnabled()/setPeXEnabled()`. Key `BitTorrent/Session/PeXEnabled`, default true. (Note: changing PeX warns a restart is required — handled in saveOptions.)
- **QCheckBox "Enable Local Peer Discovery to find more peers" (`checkLSD`)**, .ui checked. `isLSDEnabled()/setLSDEnabled()`. Key `BitTorrent/Session/LSDEnabled`, default true.
- **"Encryption mode:" (`lbl_encryption`)** — `comboEncryption` **QComboBox**, items index 0/1/2 = `Allow encryption` / `Require encryption` / `Disable encryption`. `session->encryption()/setEncryption()` (raw int index). Key `BitTorrent/Session/Encryption`, default 0.
- **QCheckBox "Enable anonymous mode" (`checkAnonymousMode`)** + link label `label_anonymous` (wiki Anonymous-Mode). `isAnonymousModeEnabled()/setAnonymousModeEnabled()`. Key `BitTorrent/Session/AnonymousModeEnabled`, default false.

### Row (not in a groupbox)
- **"Maximum active checking torrents:" (`labelMaxActiveCheckingTorrents`)** — `spinBoxMaxActiveCheckingTorrents` **QSpinBox**, min −1, max 2147483647, specialValueText `∞`. `maxActiveCheckingTorrents()/setMaxActiveCheckingTorrents()`. Key `BitTorrent/Session/MaxActiveCheckingTorrents`, default 1.

### Checkable GroupBox "Torrent Queueing" (`checkEnableQueueing`) — default unchecked
Bound `session->isQueueingSystemEnabled()/setQueueingSystemEnabled()` (helper `isQueueingSystemEnabled()`). Key `BitTorrent/Session/QueueingSystemEnabled`, default false.
- **"Maximum active downloads:" (`label_max_active_dl`)** — `spinMaxActiveDownloads` (min −1, max 2147483647, `∞`). `maxActiveDownloads()/setMaxActiveDownloads()`. Key `BitTorrent/Session/MaxActiveDownloads`, default 3 (lowerLimited −1).
- **"Maximum active uploads:" (`label_max_active_up`)** — `spinMaxActiveUploads`. Key `BitTorrent/Session/MaxActiveUploads`, default 3.
- **"Maximum active torrents:" (`maxActiveTorrents_lbl`)** — `spinMaxActiveTorrents`. Key `BitTorrent/Session/MaxActiveTorrents`, default 5.
- **Checkable GroupBox "Do not count slow torrents in these limits" (`checkIgnoreSlowTorrentsForQueueing`)** — default unchecked. `ignoreSlowTorrentsForQueueing()/setIgnoreSlowTorrentsForQueueing()`. Key `BitTorrent/Session/IgnoreSlowTorrentsForQueueing`, default false. Shared tooltip on the three labels: "A torrent will be considered slow if its download and upload rates stay below these values for 'Torrent inactivity timer' seconds". Contains:
  - **"Download rate threshold:" (`labelDownloadRateForSlowTorrents`)** — `spinDownloadRateForSlowTorrents` (suffix ` KiB/s`, max 2000000, .ui default 2). `downloadRateForSlowTorrents()/set...`. Key `BitTorrent/Session/SlowTorrentsDownloadRate`, default 2.
  - **"Upload rate threshold:" (`labelUploadRateForSlowTorrents`)** — `spinUploadRateForSlowTorrents`. Key `BitTorrent/Session/SlowTorrentsUploadRate`, default 2.
  - **"Torrent inactivity timer:" (`labelSlowTorrentInactivityTimer`)** — `spinSlowTorrentsInactivityTimer` (suffix ` sec`, min 1, max 999999, .ui default 60). `slowTorrentsInactivityTimer()/set...`. Key `BitTorrent/Session/SlowTorrentsInactivityTimer`, default 60.

### GroupBox "Seeding Limits" (`seedingLimitsBox`)
Saved together via `session->setShareLimits({ratioLimit, seedingTimeLimit, inactiveSeedingTimeLimit, mode, action})`.
- **QCheckBox "When ratio reaches" (`checkMaxRatio`)** + `spinMaxRatio` **QDoubleSpinBox** (singleStep 0.05, .ui value 1.0, max set to INT_MAX at load; enabled only when checkbox checked). Getter `getMaxRatio()` returns value or −1 when unchecked. Key `BitTorrent/Session/GlobalMaxRatio`, default −1 (i.e. disabled; clamps <0 → −1).
- **QCheckBox "When total seeding time reaches" (`checkMaxSeedingMinutes`)** + `spinMaxSeedingMinutes` **QSpinBox** (suffix ` min`, max 9999999, .ui default 1440). `getMaxSeedingMinutes()` returns value or −1. Key `BitTorrent/Session/GlobalMaxSeedingMinutes`, default −1 (disabled).
- **QCheckBox "When inactive seeding time reaches" (`checkMaxInactiveSeedingMinutes`)** + `spinMaxInactiveSeedingMinutes` (suffix ` min`, max 9999999, .ui default 1440). `getMaxInactiveSeedingMinutes()` → value or −1. Key `BitTorrent/Session/GlobalMaxInactiveSeedingMinutes`, default −1.
- **Radio group (mode):** `radioButtonShareLimitsModeAny` "Any of the above" (.ui checked) vs `radioButtonShareLimitsModeAll` "All the above" → `ShareLimitsMode::MatchAny` / `MatchAll`. Key `BitTorrent/Session/ShareLimitsMode`, default `MatchAny`.
- **"then" (`label`)** — `comboRatioLimitAct` **QComboBox** (enabled only if any of the three limits enabled — `toggleComboRatioLimitAct()`). Items index 0..3: `Stop torrent`, `Remove torrent`, `Remove torrent and its files`, `Enable super seeding for torrent` → `ShareLimitAction::Stop/Remove/RemoveWithContent/EnableSuperSeeding`. Key `BitTorrent/Session/ShareLimitAction`, default `Stop`.

### Checkable GroupBox "Automatically append these trackers to new downloads:" (`checkEnableAddTrackers`) — default unchecked
- `session->isAddTrackersEnabled()/setAddTrackersEnabled()`. Key `BitTorrent/Session/AddTrackersEnabled`, default false.
- `textTrackers` **QPlainTextEdit** (tabChangesFocus) — `additionalTrackers()/setAdditionalTrackers()`. Key `BitTorrent/Session/AdditionalTrackers`.

### Checkable GroupBox "Automatically append trackers from URL to new downloads:" (`checkAddTrackersFromURL`) — default unchecked
- `isAddTrackersFromURLEnabled()/setAddTrackersFromURLEnabled()`. Key `BitTorrent/Session/AddTrackersFromURLEnabled`, default false.
- **"URL:" (`labelCustomizeTrackersListUrl`)** `textTrackersURL` **QLineEdit** — `additionalTrackersURL()/setAdditionalTrackersURL()`. Key `BitTorrent/Session/AdditionalTrackersURL`.
- **"Fetched trackers" (`labeltrackersFromURL`)** `textTrackersFromURL` **QPlainTextEdit** readOnly — display only, `additionalTrackersFromURL()`. Key `BitTorrent/Session/AdditionalTrackersFromURL`.

---

## RSS TAB (`tabRSSPage`) — load/`saveRSSTabOptions`

Backends: `RSS::Session::instance()`, `RSS::AutoDownloader::instance()`.

### GroupBox "RSS Reader" (`groupRSSReader`)
- **QCheckBox "Enable fetching RSS feeds" (`checkRSSEnable`)** — `rssSession->isProcessingEnabled()/setProcessingEnabled()`. Key `RSS/Session/EnableProcessing` (no explicit default → false).
- **"Feeds refresh interval:" (`label_111`)** — `spinRSSRefreshInterval` **QSpinBox** (suffix ` min`, min 1, max 999999, .ui default 5). `refreshInterval()/setRefreshInterval()`. Key `RSS/Session/RefreshInterval`, default 30.
- **"Same host request delay:" (`labelRSSFetchDelay`)** — `spinRSSFetchDelay` **QSpinBox** (suffix ` sec`, max 2147483646, .ui default 2). `fetchDelay().count()/setFetchDelay(seconds)`. Key `RSS/Session/FetchDelay`, default 2.
- **"Maximum number of articles per feed:" (`label_12`)** — `spinRSSMaxArticlesPerFeed` **QSpinBox** (max 2147483646, .ui default 100). `maxArticlesPerFeed()/setMaxArticlesPerFeed()`. Key `RSS/Session/MaxArticlesPerFeed`, default 50.

### GroupBox "RSS Torrent Auto Downloader" (`groupRSSAutoDownloader`)
- **QCheckBox "Enable auto downloading of RSS torrents" (`checkRSSAutoDownloaderEnable`)** — `autoDownloader->isProcessingEnabled()/setProcessingEnabled()`. Key `RSS/AutoDownloader/EnableProcessing`, default false.
- **QPushButton "Edit auto downloading rules..." (`btnEditRules`)** — opens modeless `AutomatedRssDownloader` dialog (WA_DeleteOnClose).

### GroupBox "RSS Smart Episode Filter" (`groupRSSSmartEpisodeFilter`)
- **QCheckBox "Download REPACK/PROPER episodes" (`checkSmartFilterDownloadRepacks`)** — `downloadRepacks()/setDownloadRepacks()`. Key `RSS/AutoDownloader/DownloadRepacks`.
- **"Filters:" (`label_5`)** `textSmartEpisodeFilters` **QPlainTextEdit** (tabChangesFocus) — newline-joined list; `smartEpisodeFilters()` / `setSmartEpisodeFilters(split '\n', SkipEmptyParts)`. Key `RSS/AutoDownloader/SmartEpisodeFilter`.

---

## WEBUI TAB (`tabWebUIPage`) — load/`saveWebUITabOptions` (compiled out under `DISABLE_WEBUI`)

Backend: `Preferences::instance()`. All keys under `Preferences/WebUI/*` unless noted.

### Checkable GroupBox "Web User Interface (Remote control)" (`checkWebUI`) — default unchecked
- Bound `pref->isWebUIEnabled()/setWebUIEnabled()` (helper `isWebUIEnabled()`). Key `Preferences/WebUI/Enabled`.
- Italic error label `labelWebUIError` — shows "WebUI configuration failed. Reason: %1" from `app()->webUI()->errorMessage()`, else hidden.
- **"IP address:" (`lblWebUIAddress`)** `textWebUIAddress` **QLineEdit** (tooltip re IPv4/IPv6, `0.0.0.0`/`::`/`*`). `getWebUIAddress()/setWebUIAddress()`. Key `.../Address`, default `*`.
- **"Port:" (`lblWebUIPort`)** `spinWebUIPort` **QSpinBox** (min 1, max 65535, .ui default 8080). `getWebUIPort()/setWebUIPort()`. Key `.../Port`, default 8080.
- **QCheckBox "Use UPnP / NAT-PMP to forward the port from my router" (`checkWebUIUPnP`)**, .ui checked. `useUPnPForWebUIPort()/setUPnPForWebUIPort()`. Key `.../UseUPnP`, default false.

#### Checkable sub-GroupBox "Use HTTPS instead of HTTP" (`checkWebUIHttps`) — default unchecked
- `isWebUIHttpsEnabled()/setWebUIHttpsEnabled()`. Key `.../HTTPS/Enabled`, default false.
- **Cert status icon `lblSslCertStatus`** + **"Certificate:" (`lblWebUICrt`)** `textWebUIHttpsCert` **FileSystemPathLineEdit** (Mode FileOpen, filter `Certificate (*.cer *.crt *.pem)`). `getWebUIHttpsCertificatePath()/setWebUIHttpsCertificatePath()`. Key `.../HTTPS/CertificatePath`. `webUIHttpsCertChanged()` validates via `Utils::Net::isSSLCertificatesValid` and sets a `security-high`/`security-low` pixmap.
- **Key status icon `lblSslKeyStatus`** + **"Key:" (`lblWebUIKey`)** `textWebUIHttpsKey` **FileSystemPathLineEdit** (filter `Private key (*.key *.pem)`). `getWebUIHttpsKeyPath()/setWebUIHttpsKeyPath()`. Key `.../HTTPS/KeyPath`. Validated via `Utils::SSLKey::load` in `webUIHttpsKeyChanged()`.
- Link label `lblWebUICertInfo` (Apache SSL FAQ).

#### GroupBox "Authentication" (`groupWebUIAuth`)
- Sub-GroupBox "User" (`groupWebUIUser`):
  - **"Username:" (`lblWebUIUsername`)** `textWebUIUsername` **QLineEdit**. `getWebUIUsername()/setWebUIUsername()`. Key `.../Username`, default `admin`. Validation (`webUIAuthenticationOk`): min length 3 (`isValidWebUIUsernameLength`), must not contain `:` (`isValidWebUIUsernameCharacterSet`).
  - **"Password:" (`lblWebUIPassword`)** `textWebUIPassword` **QLineEdit** (echoMode Password, placeholder "Change current password"). Never pre-filled. On save, if non-empty and ≥6 chars → `setWebUIPassword(Utils::Password::PBKDF2::generate(pw))`. Key `.../Password_PBKDF2` (QByteArray). Empty keeps current password.
- Sub-GroupBox "API Key" (`groupWebUIAPIKey`):
  - **"Key:" (`lblWebUIAPIKey`)** `textWebUIAPIKey` **QLineEdit** readOnly (masked via `maskAPIKey`, placeholder "Generate a key"). Backed by `m_currentAPIKey`; persisted immediately (not via Apply) to key `.../APIKey`.
  - `btnWebUIAPIKeyCopy` (icon edit-copy, tooltip "Copy API key") → copies to clipboard.
  - `btnWebUIAPIKeyRotate` (icon view-refresh) → confirm dialog "Generate API key"/"Rotate API key", generates `Utils::APIKey::generate()`, applies immediately.
  - `btnWebUIAPIKeyDelete` (icon list-remove) → confirm "Delete API key", clears + applies. `setupWebUIAPIKey()` toggles enabled states / tooltips based on `Utils::APIKey::isValid`.
- **QCheckBox "Bypass authentication for clients on localhost" (`checkBypassLocalAuth`)** — inverted: load `setChecked(!isWebUILocalAuthEnabled())`, save `setWebUILocalAuthEnabled(!checked)`. Key `.../LocalHostAuth`, default true.
- **QCheckBox "Bypass authentication for clients in whitelisted IP subnets" (`checkBypassAuthSubnetWhitelist`)** — `isWebUIAuthSubnetWhitelistEnabled()/set...`; also enables `IPSubnetWhitelistButton`. Key `.../AuthSubnetWhitelistEnabled`, default false.
- **QPushButton "IP subnet whitelist..." (`IPSubnetWhitelistButton`)** → `IPSubnetWhitelistOptionsDialog` (edits list key `.../AuthSubnetWhitelist`, QStringList).
- **"Ban client after consecutive failures:" (`lblBanCounter`)** `spinBanCounter` **QSpinBox** (specialValueText "Never" at 0, max 2147483647). `getWebUIMaxAuthFailCount()/setWebUIMaxAuthFailCount()`. Key `.../MaxAuthenticationFailCount`, default 5.
- **"ban for:" (`lblBanDuration`)** `spinBanDuration` **QSpinBox** (suffix ` sec`, min 1, max 2147483647). `getWebUIBanDuration().count()/setWebUIBanDuration(seconds)`. Key `.../BanDuration`, default 3600.
- **"Session timeout:" (`lblSessionTimeout`)** `spinSessionTimeout` **QSpinBox** (specialValueText "Disabled" at 0, suffix ` sec`, max 2147483647). `getWebUISessionTimeout()/setWebUISessionTimeout()`. Key `.../SessionTimeout`, default 3600.

#### Checkable GroupBox "Use alternative WebUI" (`groupAltWebUI`) — default unchecked
- `isAltWebUIEnabled()/setAltWebUIEnabled()`. Key `.../AlternativeUIEnabled`, default false.
- **"Files location:" (`labelWebUIRootFolder`)** `textWebUIRootFolder` **FileSystemPathLineEdit** (Mode DirectoryOpen). `getWebUIRootFolder()/setWebUIRootFolder()`. Key `.../RootFolder`. Validation `isAlternativeWebUIPathValid()`: must be non-empty when enabled.
- Link label `lblAltWebUIList` (list of alternate WebUIs).

#### GroupBox "Security" (`groupBox_3`)
- **QCheckBox "Enable clickjacking protection" (`checkClickjacking`)** — `isWebUIClickjackingProtectionEnabled()/set...`. Key `.../ClickjackingProtection`, default true.
- **QCheckBox "Enable Cross-Site Request Forgery (CSRF) protection" (`checkCSRFProtection`)** — Key `.../CSRFProtection`, default true.
- **QCheckBox "Enable cookie Secure flag (requires HTTPS or localhost connection)" (`checkSecureCookie`)** — `isWebUISecureCookieEnabled()/set...`. Key `.../SecureCookie`, default true.
- **Checkable GroupBox "Enable Host header validation" (`groupHostHeaderValidation`)** — `isWebUIHostHeaderValidationEnabled()/set...`. Key `.../HostHeaderValidation`, default true. Contains **"Server domains:" (`labelServerDomains`)** `textServerDomains` **QLineEdit** (tooltip re DNS-rebinding; `;`-separated, wildcard `*`). `getServerDomains()/setServerDomains()`. Key `.../ServerDomains`, default `*`.

#### Checkable GroupBox "Add custom HTTP headers" (`groupWebUIAddCustomHTTPHeaders`)
- `isWebUICustomHTTPHeadersEnabled()/set...`. Key `.../CustomHTTPHeadersEnabled`, default false.
- `textWebUICustomHTTPHeaders` **QPlainTextEdit** (NoWrap, placeholder "Header: value pairs, one per line"). `getWebUICustomHTTPHeaders()/set...`. Key `.../CustomHTTPHeaders`.

#### Checkable GroupBox "Enable reverse proxy support" (`groupEnableReverseProxySupport`)
- `isWebUIReverseProxySupportEnabled()/set...`. Key `.../ReverseProxySupportEnabled`, default false.
- **"Trusted proxies list:" (`lblReverseProxiesList`)** `textTrustedReverseProxiesList` **QLineEdit** (tooltip re X-Forwarded-For; `;`-separated). `getWebUITrustedReverseProxiesList()/set...`. Key `.../TrustedReverseProxiesList`.
- Link label `labelReverseProxyLink`.

#### Checkable GroupBox "Update my dynamic domain name" (`checkDynDNS`) — default unchecked
- `isDynDNSEnabled()/setDynDNSEnabled()`. Key `Preferences/DynDNS/Enabled`, default false.
- **"Service:" (`label_19`)** `comboDNSService` **QComboBox**, items index 0/1 = `DynDNS` / `No-IP` → `DNS::Service`. `getDynDNSService()/setDynDNSService(static_cast<DNS::Service>(index))`. Key `Preferences/DynDNS/Service`, default `DNS::Service::DynDNS`.
- **QPushButton "Register" (`registerDNSBtn`)** → opens `Net::DNSUpdater::getRegistrationUrl(service)` in browser.
- **"Domain name:" (`label_20`)** `domainNameTxt` **QLineEdit** (.ui default `changeme.dyndns.org`). Key `Preferences/DynDNS/DomainName`, default `changeme.dyndns.org`.
- **"Username:" (`label_21`)** `DNSUsernameTxt` **QLineEdit**. Key `Preferences/DynDNS/Username`.
- **"Password:" (`label_22`)** `DNSPasswordTxt` **QLineEdit** (echoMode Password). Key `Preferences/DynDNS/Password`.

---

## ADVANCED TAB (`tabAdvancedPage` → `AdvancedSettings`)

Source: `src/gui/advancedsettings.{h,cpp}`. This tab is a single **`QTableWidget`** (subclass `AdvancedSettings : GUIApplicationComponent<QTableWidget>`), 2 columns — header labels `Setting` / `Value` (enum `PROPERTY`, `VALUE`). `verticalHeader` hidden; `alternatingRowColors` on; `NoSelection`; `NoEditTriggers`. Rows built by `addRow(row, labelText, widget*)`; each label may append an HTML help link `(?)` to libtorrent/qBittorrent docs (`makeLink`). Two centered bold **section header rows** each carry an "Open documentation" link: `qBittorrent Section` (wiki) and `libtorrent Section` (libtorrent reference). `saveAdvancedSettings()` writes each widget; `settingsChanged` signal fires on any edit. Rows in enum `AdvSettingsRows` order below (platform/`#ifdef` gating noted).

### qBittorrent Section
| Setting label | Widget | Type | API (get/set) | Config key | Default | Range/notes |
|---|---|---|---|---|---|---|
| Resume data storage type (requires restart) | `m_comboBoxResumeDataStorage` | Combo | `session->resumeDataStorageType()/setResumeDataStorageType()` | `BitTorrent/Session/ResumeDataStorageType` | `Legacy` | items: `Fastresume files`→Legacy, `SQLite database (experimental)`→SQLite |
| Torrent content removing mode | `m_comboBoxTorrentContentRemoveOption` | Combo | `torrentContentRemoveOption()/set...` | `BitTorrent/Session/TorrentContentRemoveOption` | `Delete` | items: `Delete files permanently`→Delete, `Move files to trash (if possible)`→MoveToTrash |
| Physical memory (RAM) usage limit *(libtorrent2 & !Linux & !macOS)* | `m_spinBoxMemoryWorkingSetLimit` | SpinBox | `app()->memoryWorkingSetLimit()/setMemoryWorkingSetLimit()` | `Application/MemoryWorkingSetLimit` | (app default) | min 1, max INT_MAX, suffix ` MiB` |
| Process memory priority *(Windows)* | `m_comboBoxOSMemoryPriority` | Combo | `app()->processMemoryPriority()/setProcessMemoryPriority()` | `Application/ProcessMemoryPriority` | — | items Normal/Below normal/Medium/Low/Very low → `MemoryPriority` |
| Network interface | `m_comboBoxInterface` | Combo | `networkInterface()/setNetworkInterface()` + `setNetworkInterfaceName()` | `BitTorrent/Session/Interface`, `.../InterfaceName` | Any interface | item 0 `Any interface`(empty); then each `QNetworkInterface` (data=iface.name) |
| Optional IP address to bind to | `m_comboBoxInterfaceAddress` | Combo | `networkInterfaceAddress()/setNetworkInterfaceAddress()` | `BitTorrent/Session/InterfaceAddress` | All addresses | items `All addresses`(empty), `All IPv4 addresses`(0.0.0.0), `All IPv6 addresses`(::), then live addrs; rebuilt by `updateInterfaceAddressCombo()` |
| Save resume data interval [0: disabled] | `m_spinBoxSaveResumeDataInterval` | SpinBox | `saveResumeDataInterval()/set...` | `BitTorrent/Session/SaveResumeDataInterval` | 60 | min 0, max INT_MAX, suffix ` min`, specialValue `0 (disabled)` |
| Save statistics interval [0: disabled] | `m_spinBoxSaveStatisticsInterval` | SpinBox | `saveStatisticsInterval().count()/set(minutes)` | `BitTorrent/Session/SaveStatisticsInterval` | 15 | min 0, suffix ` min`, special `0 (disabled)` |
| .torrent file size limit | `m_spinBoxTorrentFileSizeLimit` | SpinBox | `pref->getTorrentFileSizeLimit()/set...` (×1024×1024) | `BitTorrent/TorrentFileSizeLimit` | 104857600 (100 MiB) | min 1, max INT_MAX/1MiB, suffix ` MiB` |
| Confirm torrent recheck | `m_checkBoxConfirmTorrentRecheck` | CheckBox | `pref->confirmTorrentRecheck()/set...` | `Preferences/Advanced/confirmTorrentRecheck` | true | |
| Recheck torrents on completion | `m_checkBoxRecheckCompleted` | CheckBox | `pref->recheckTorrentsOnCompletion()/recheckTorrentsOnCompletion(v)` | `Preferences/Advanced/RecheckOnCompletion` | false | |
| Customize application instance name | `m_lineEditAppInstanceName` | LineEdit | `app()->instanceName()/setInstanceName()` | `Application/InstanceName` | (empty) | tooltip appends text to window title |
| Refresh interval | `m_spinBoxListRefresh` | SpinBox | `session->refreshInterval()/setRefreshInterval()` | `BitTorrent/Session/RefreshInterval` | 1500 | min 30, max 99999, suffix ` ms` |
| Resolve peer countries | `m_checkBoxResolveCountries` | CheckBox | `pref->resolvePeerCountries()/resolvePeerCountries(v)` | `Preferences/Connection/ResolvePeerCountries` | false | |
| Resolve peer host names | `m_checkBoxResolveHosts` | CheckBox | `pref->resolvePeerHostNames()/...` | `Preferences/Connection/ResolvePeerHostNames` | false | |
| Display notifications | `m_checkBoxProgramNotifications` | CheckBox | `desktopIntegration()->isNotificationsEnabled()/setNotificationsEnabled()` | `GUI/Notifications/Enabled` | true | |
| Display notifications for added torrents | `m_checkBoxTorrentAddedNotifications` | CheckBox | `app()->isTorrentAddedNotificationsEnabled()/set...` | `GUI/Notifications/TorrentAdded` | false | |
| Notification timeout [0: infinite, -1: system default] *(DBus)* | `m_spinBoxNotificationTimeout` | SpinBox | `desktopIntegration()->notificationTimeout()/setNotificationTimeout()` | `GUI/Notifications/Timeout` | -1 | min −1, max INT_MAX; dynamic suffix (` ms`/infinite/system default) |
| Confirm removal of all tags | `m_checkBoxConfirmRemoveAllTags` | CheckBox | `pref->confirmRemoveAllTags()/set...` | `Preferences/Advanced/confirmRemoveAllTags` | true | |
| Confirm removal of tracker from all torrents | `m_checkBoxConfirmRemoveTrackerFromAllTorrents` | CheckBox | `pref->confirmRemoveTrackerFromAllTorrents()/set...` | `GUI/ConfirmActions/RemoveTrackerFromAllTorrents` | true | |
| Reannounce to all trackers when IP or port changed | `m_checkBoxReannounceWhenAddressChanged` | CheckBox | `isReannounceWhenAddressChangedEnabled()/set...` | `BitTorrent/Session/ReannounceWhenAddressChanged` | false | |
| Download tracker's favicon | `m_checkBoxTrackerFavicon` | CheckBox | `mainWindow()->isDownloadTrackerFavicon()/setDownloadTrackerFavicon()` | `GUI/DownloadTrackerFavicon` | — | |
| Save path history length | `m_spinBoxSavePathHistoryLength` | SpinBox | `pref->addNewTorrentDialogSavePathHistoryLength()/set...` | `AddNewTorrentDialog/SavePathHistoryLength` | 8 | range 0–99 |
| Enable speed graphs | `m_checkBoxSpeedWidgetEnabled` | CheckBox | `pref->isSpeedWidgetEnabled()/setSpeedWidgetEnabled()` | `SpeedWidget/Enabled` | true | |
| Enable icons in menus *(!macOS)* | `m_checkBoxIconsInMenusEnabled` | CheckBox | `pref->iconsInMenusEnabled()/set...` | `Preferences/Advanced/EnableIconsInMenus` | true | |
| Attach "Add new torrent" dialog to main window *(!macOS)* | `m_checkBoxAttachedAddNewTorrentDialog` | CheckBox | `pref->isAddNewTorrentDialogAttached()/set...` | `AddNewTorrentDialog/Attached` | false | |
| Enable embedded tracker | `m_checkBoxTrackerStatus` | CheckBox | `session->isTrackerEnabled()/setTrackerEnabled()` | `BitTorrent/TrackerEnabled` | false | |
| Embedded tracker port | `m_spinBoxTrackerPort` | SpinBox | `pref->getTrackerPort()/setTrackerPort()` | `Preferences/Advanced/trackerPort` | 9000 | min 1, max 65535 |
| Enable port forwarding for embedded tracker | `m_checkBoxTrackerPortForwarding` | CheckBox | `pref->isTrackerPortForwardingEnabled()/set...` | `Preferences/Advanced/trackerPortForwarding` | false | |
| Enable Mark-of-the-Web (MOTW)… *(Win)* / Enable quarantine… *(macOS)* | `m_checkBoxMarkOfTheWeb` | CheckBox | `pref->isMarkOfTheWebEnabled()/set...` | `Preferences/Advanced/markOfTheWeb` | true | |
| Ignore SSL errors | `m_checkBoxIgnoreSSLErrors` | CheckBox | `pref->isIgnoreSSLErrors()/set...` | `Preferences/Advanced/IgnoreSSLErrors` | false | tooltip re RSS/updates/geoip |
| Python executable path (may require restart) | `m_pythonExecutablePath` | LineEdit | `pref->getPythonExecutablePath()/set...` | `Preferences/Search/pythonExecutablePath` | (empty) | placeholder "(Auto detect if empty)" |
| Start BitTorrent session in paused state | `m_checkBoxStartSessionPaused` | CheckBox | `session->isStartPaused()/setStartPaused()` | `BitTorrent/Session/StartPaused` | false | |
| BitTorrent session shutdown timeout [-1: unlimited] | `m_spinBoxSessionShutdownTimeout` | SpinBox | `session->shutdownTimeout()/setShutdownTimeout()` | `BitTorrent/Session/ShutdownTimeout` | -1 | min −1, suffix ` sec`, special `-1 (unlimited)` |

### libtorrent Section
| Setting label | Widget | Type | API | Config key | Default | Range/notes |
|---|---|---|---|---|---|---|
| Bdecode depth limit | `m_spinBoxBdecodeDepthLimit` | SpinBox | `pref->getBdecodeDepthLimit()/set...` | `BitTorrent/BdecodeDepthLimit` | 100 | min 0, max INT_MAX |
| Bdecode token limit | `m_spinBoxBdecodeTokenLimit` | SpinBox | `pref->getBdecodeTokenLimit()/set...` | `BitTorrent/BdecodeTokenLimit` | 10000000 | min 0, max INT_MAX |
| Asynchronous I/O threads | `m_spinBoxAsyncIOThreads` | SpinBox | `asyncIOThreads()/setAsyncIOThreads()` | `BitTorrent/Session/AsyncIOThreadsCount` | 10 | min 1, max 1024 |
| Hashing threads *(libtorrent2)* | `m_spinBoxHashingThreads` | SpinBox | `hashingThreads()/setHashingThreads()` | `BitTorrent/Session/HashingThreadsCount` | 1 | min 1, max 1024 |
| File pool size | `m_spinBoxFilePoolSize` | SpinBox | `filePoolSize()/setFilePoolSize()` | `BitTorrent/Session/FilePoolSize` | 100 | min 1, max INT_MAX |
| Outstanding memory when checking torrents | `m_spinBoxCheckingMemUsage` | SpinBox | `checkingMemUsage()/setCheckingMemUsage()` | `BitTorrent/Session/CheckingMemUsageSize` | 32 | min 1; max 1024 (64-bit) / 128 (32-bit); suffix ` MiB` |
| Disk cache *(libtorrent1 only)* | `m_spinBoxCache` | SpinBox | `diskCacheSize()/setDiskCacheSize()` | `BitTorrent/Session/DiskCacheSize` | -1 | min −1; dynamic suffix ` MiB`/(disabled)/(auto); max 33554431 (64-bit)/1536 (32-bit) |
| Disk cache expiry interval *(libtorrent1)* | `m_spinBoxCacheTTL` | SpinBox | `diskCacheTTL()/setDiskCacheTTL()` | `BitTorrent/Session/DiskCacheTTL` | 60 | min 1, suffix ` s` |
| Disk queue size | `m_spinBoxDiskQueueSize` | SpinBox | `diskQueueSize()/setDiskQueueSize()` (×1024) | `BitTorrent/Session/DiskQueueSize` | 1048576 (1024 KiB) | min 1, suffix ` KiB` |
| Disk IO type (requires restart) *(libtorrent2)* | `m_comboBoxDiskIOType` | Combo | `diskIOType()/setDiskIOType()` | `BitTorrent/Session/DiskIOType` | `Default` | items Default/Memory mapped files/POSIX-compliant/Simple pread/pwrite (+Pread/pwrite if LT≥2.1) |
| Disk IO read mode | `m_comboBoxDiskIOReadMode` | Combo | `diskIOReadMode()/setDiskIOReadMode()` | `BitTorrent/Session/DiskIOReadMode` | `EnableOSCache` | items Disable OS cache/Enable OS cache |
| Disk IO write mode | `m_comboBoxDiskIOWriteMode` | Combo | `diskIOWriteMode()/setDiskIOWriteMode()` | `BitTorrent/Session/DiskIOWriteMode` | `EnableOSCache` | items Disable/Enable OS cache (+Write-through if libtorrent2) |
| Coalesce reads & writes *(libtorrent1)* | `m_checkBoxCoalesceRW` | CheckBox | `isCoalesceReadWriteEnabled()/setCoalesceReadWriteEnabled()` | `BitTorrent/Session/CoalesceReadWrite` | true(Win)/false(other) | |
| Use piece extent affinity | `m_checkBoxPieceExtentAffinity` | CheckBox | `usePieceExtentAffinity()/setPieceExtentAffinity()` | `BitTorrent/Session/PieceExtentAffinity` | false | |
| Send upload piece suggestions | `m_checkBoxSuggestMode` | CheckBox | `isSuggestModeEnabled()/setSuggestMode()` | `BitTorrent/Session/SuggestMode` | false | |
| Send buffer watermark | `m_spinBoxSendBufferWatermark` | SpinBox | `sendBufferWatermark()/set...` | `BitTorrent/Session/SendBufferWatermark` | 500 | min 1, suffix ` KiB` |
| Send buffer low watermark | `m_spinBoxSendBufferLowWatermark` | SpinBox | `sendBufferLowWatermark()/set...` | `BitTorrent/Session/SendBufferLowWatermark` | 10 | min 1, suffix ` KiB` |
| Send buffer watermark factor | `m_spinBoxSendBufferWatermarkFactor` | SpinBox | `sendBufferWatermarkFactor()/set...` | `BitTorrent/Session/SendBufferWatermarkFactor` | 50 | min 1, suffix ` %` |
| Outgoing connections per second | `m_spinBoxConnectionSpeed` | SpinBox | `connectionSpeed()/setConnectionSpeed()` | `BitTorrent/Session/ConnectionSpeed` | 30 | min 0, max INT_MAX |
| Allow outgoing connections when seeding | `m_checkBoxSeedingOutgoingConnections` | CheckBox | `isSeedingOutgoingConnectionsEnabled()/set...` | `BitTorrent/Session/SeedingOutgoingConnectionsEnabled` | true | |
| Socket send buffer size [0: system default] | `m_spinBoxSocketSendBufferSize` | SpinBox | `socketSendBufferSize()/set...` (×1024) | `BitTorrent/Session/SocketSendBufferSize` | 0 | min 0, suffix ` KiB`, special `0 (system default)` |
| Socket receive buffer size [0: system default] | `m_spinBoxSocketReceiveBufferSize` | SpinBox | `socketReceiveBufferSize()/set...` (×1024) | `BitTorrent/Session/SocketReceiveBufferSize` | 0 | min 0, suffix ` KiB`, special `0 (system default)` |
| Socket backlog size | `m_spinBoxSocketBacklogSize` | SpinBox | `socketBacklogSize()/set...` | `BitTorrent/Session/SocketBacklogSize` | 30 | min 1, max INT_MAX |
| Outgoing ports (Min) [0: disabled] | `m_spinBoxOutgoingPortsMin` | SpinBox | `outgoingPortsMin()/set...` | `BitTorrent/Session/OutgoingPortsMin` | 0 | 0–65535, special `0 (disabled)` |
| Outgoing ports (Max) [0: disabled] | `m_spinBoxOutgoingPortsMax` | SpinBox | `outgoingPortsMax()/set...` | `BitTorrent/Session/OutgoingPortsMax` | 0 | 0–65535, special `0 (disabled)` |
| UPnP lease duration [0: permanent lease] | `m_spinBoxUPnPLeaseDuration` | SpinBox | `UPnPLeaseDuration()/set...` | `BitTorrent/Session/UPnPLeaseDuration` | 0 | min 0, suffix ` s`, special `0 (permanent lease)` |
| Differentiated Services Code Point (DSCP) for connections to peers | `m_spinBoxPeerDSCP` | SpinBox | `peerDSCP()/setPeerDSCP()` | `BitTorrent/Session/PeerToS` | 0x01 (1) | 0–255 |
| µTP-TCP mixed mode algorithm | `m_comboBoxUtpMixedMode` | Combo | `utpMixedMode()/setUtpMixedMode()` | `BitTorrent/Session/uTPMixedMode` | `TCP` | items `Prefer TCP`→TCP, `Peer proportional (throttles TCP)`→Proportional (label uses `C_UTP` glyph) |
| Internal hostname resolver cache expiry interval | `m_spinBoxHostnameCacheTTL` | SpinBox | `hostnameCacheTTL()/set...` | `BitTorrent/Session/HostnameCacheTTL` | 1200 | min 0, suffix ` s` |
| Support internationalized domain name (IDN) | `m_checkBoxIDNSupport` | CheckBox | `isIDNSupportEnabled()/setIDNSupportEnabled()` | `BitTorrent/Session/IDNSupportEnabled` | false | |
| Allow multiple connections from the same IP address | `m_checkBoxMultiConnectionsPerIp` | CheckBox | `multiConnectionsPerIpEnabled()/set...` | `BitTorrent/Session/MultiConnectionsPerIp` | false | |
| Validate HTTPS tracker certificates | `m_checkBoxValidateHTTPSTrackerCertificate` | CheckBox | `validateHTTPSTrackerCertificate()/set...` | `BitTorrent/Session/ValidateHTTPSTrackerCertificate` | true | |
| Server-side request forgery (SSRF) mitigation | `m_checkBoxSSRFMitigation` | CheckBox | `isSSRFMitigationEnabled()/set...` | `BitTorrent/Session/SSRFMitigation` | true | |
| Disallow connection to peers on privileged ports | `m_checkBoxBlockPeersOnPrivilegedPorts` | CheckBox | `blockPeersOnPrivilegedPorts()/set...` | `BitTorrent/Session/BlockPeersOnPrivilegedPorts` | false | |
| Upload slots behavior | `m_comboBoxChokingAlgorithm` | Combo | `chokingAlgorithm()/setChokingAlgorithm()` | `BitTorrent/Session/ChokingAlgorithm` | `FixedSlots` | items `Fixed slots`→FixedSlots, `Upload rate based`→RateBased |
| Upload choking algorithm | `m_comboBoxSeedChokingAlgorithm` | Combo | `seedChokingAlgorithm()/set...` | `BitTorrent/Session/SeedChokingAlgorithm` | `FastestUpload` | items `Round-robin`→RoundRobin, `Fastest upload`→FastestUpload, `Anti-leech`→AntiLeech |
| Always announce to all trackers in a tier | `m_checkBoxAnnounceAllTrackers` | CheckBox | `announceToAllTrackers()/set...` | `BitTorrent/Session/AnnounceToAllTrackers` | false | |
| Always announce to all tiers | `m_checkBoxAnnounceAllTiers` | CheckBox | `announceToAllTiers()/set...` | `BitTorrent/Session/AnnounceToAllTiers` | true | |
| IP address reported to trackers (requires restart) | `m_lineEditAnnounceIP` | LineEdit | `announceIP()/setAnnounceIP()` (validated via QHostAddress) | `BitTorrent/Session/AnnounceIP` | (empty) | |
| Port reported to trackers (requires restart) [0: listening port] | `m_spinBoxAnnouncePort` | SpinBox | `announcePort()/setAnnouncePort()` | `BitTorrent/Session/AnnouncePort` | 0 | 0–65535 |
| Max concurrent HTTP announces | `m_spinBoxMaxConcurrentHTTPAnnounces` | SpinBox | `maxConcurrentHTTPAnnounces()/set...` | `BitTorrent/Session/MaxConcurrentHTTPAnnounces` | 50 | max INT_MAX |
| Stop tracker timeout [0: disabled] | `m_spinBoxStopTrackerTimeout` | SpinBox | `stopTrackerTimeout()/set...` | `BitTorrent/Session/StopTrackerTimeout` | 2 | max INT_MAX, suffix ` s`, special `0 (disabled)` |
| Peer turnover disconnect percentage | `m_spinBoxPeerTurnover` | SpinBox | `peerTurnover()/setPeerTurnover()` | `BitTorrent/Session/PeerTurnover` | 4 | 0–100, suffix ` %` |
| Peer turnover threshold percentage | `m_spinBoxPeerTurnoverCutoff` | SpinBox | `peerTurnoverCutoff()/set...` | `BitTorrent/Session/PeerTurnoverCutOff` | 90 | 0–100, suffix ` %` |
| Peer turnover disconnect interval | `m_spinBoxPeerTurnoverInterval` | SpinBox | `peerTurnoverInterval()/set...` | `BitTorrent/Session/PeerTurnoverInterval` | 300 | 30–3600, suffix ` s` |
| Maximum outstanding requests to a single peer | `m_spinBoxRequestQueueSize` | SpinBox | `requestQueueSize()/setRequestQueueSize()` | `BitTorrent/Session/RequestQueueSize` | 500 | min 1, max INT_MAX |
| DHT bootstrap nodes | `m_lineEditDHTBootstrapNodes` | LineEdit | `getDHTBootstrapNodes()/setDHTBootstrapNodes()` | `BitTorrent/Session/DHTBootstrapNodes` | `DEFAULT_DHT_BOOTSTRAP_NODES` | placeholder "Resets to default if empty" |
| I2P inbound quantity *(libtorrent2 & I2P)* | `m_spinBoxI2PInboundQuantity` | SpinBox | `I2PInboundQuantity()/set...` | `BitTorrent/Session/I2P/InboundQuantity` | 3 | 1–16 |
| I2P outbound quantity *(same gate)* | `m_spinBoxI2POutboundQuantity` | SpinBox | `I2POutboundQuantity()/set...` | `BitTorrent/Session/I2P/OutboundQuantity` | 3 | 1–16 |
| I2P inbound length | `m_spinBoxI2PInboundLength` | SpinBox | `I2PInboundLength()/set...` | `BitTorrent/Session/I2P/InboundLength` | 3 | 0–7 |
| I2P outbound length | `m_spinBoxI2POutboundLength` | SpinBox | `I2POutboundLength()/set...` | `BitTorrent/Session/I2P/OutboundLength` | 3 | 0–7 |

Build-flag gates for Advanced rows: `QBT_USES_LIBTORRENT2` (Hashing threads, Disk IO type, Write-through mode, Memory working set limit; excludes Disk cache/TTL & Coalesce RW), `Q_OS_WIN` (Process memory priority; MOTW label), `Q_OS_MACOS` (excludes icons-in-menus & attached-dialog rows; MOTW→quarantine label), `QBT_USES_DBUS` (Notification timeout), `TORRENT_USE_I2P` (I2P rows), `QBT_APP_64BIT` (spinbox maxima).

---

## Sub-dialogs referenced from these tabs
- **AutomatedRssDownloader** — opened from RSS tab `btnEditRules`; full rule editor (separate screen, out of scope here).
- **IPSubnetWhitelistOptionsDialog** — opened from WebUI `IPSubnetWhitelistButton`; edits `Preferences/WebUI/AuthSubnetWhitelist` (QStringList of CIDR subnets). On accept → `enableApplyButton`.
- **BanListOptionsDialog** — opened via `on_banListButton_clicked` (button lives on Connection tab, listed for completeness).
- **API key confirmations** — `QMessageBox::question` for generate/rotate/delete API key (applied immediately, bypassing Apply).

## QML/Material rebuild notes
- Checkable `QGroupBox` (schedule, queueing, ignore-slow, add-trackers, HTTPS, alt-WebUI, host-header, custom-headers, reverse-proxy, DynDNS, WebUI-enabled) → Material expandable card with a header switch that enables/disables its body.
- `specialValueText` semantics (`∞`, `0 (disabled)`, `Never`, `Disabled`, `0 (system default)`, `-1 (unlimited)`) must be reproduced as placeholder/sentinel handling on numeric fields.
- Inverted bindings to preserve: `checkLimitLocalPeerRate` ↔ `IgnoreLimitsOnLAN` (NOT), `checkBypassLocalAuth` ↔ `LocalHostAuth` (NOT).
- Immediate-apply exceptions: WebUI API-key rotate/delete call `Preferences::apply()` directly; everything else defers to the dialog's OK/Apply.
- The Advanced tab is a flat 2-column key/value table with two section-divider rows and per-row `(?)` doc links — in Material this becomes a settings list grouped under "qBittorrent" and "libtorrent" headers.

---

# Area: Search

# Search Area — Implementation-Ready Spec

Rebuilds the qBittorrent Qt Widgets "Search" tab as Qt6 QML + Material. Source of truth (read, not guessed):

- Backend: `src/base/search/searchhandler.{h,cpp}`, `searchpluginmanager.{h,cpp}`, `searchdownloadhandler.{h,cpp}`
- GUI: `src/gui/search/searchwidget.{h,cpp,ui}`, `searchjobwidget.{h,cpp,ui}`, `searchsortmodel.{h,cpp}`, `searchpluginselectdialog.{h,cpp,ui}`, `searchpluginsourcedialog.{h,cpp,ui}`

> NOTE: The task mentioned `searchlistdelegate` — **no such file exists** in the current tree (`src/gui/search/searchlistdelegate*` returns nothing). The results table uses the default `QTreeView` item delegate; visited-link styling is done by writing `Qt::ForegroundRole` on the model rows (see "Visited-row styling"). Do not plan a custom delegate QML component; a standard `TableView`/`TreeView` delegate suffices.

---

## 1. Backend API (the engine layer the QML must consume)

### 1.1 `SearchResult` struct (`searchhandler.h`)
One row of results. Fields (exact names):
| field | type | meaning |
|---|---|---|
| `fileName` | QString | torrent/file name |
| `fileUrl` | QString | download URL (magnet: or http torrent link) |
| `fileSize` | qlonglong | size in bytes; `-1`/0 possible |
| `nbSeeders` | qlonglong | seeders; `-1` = unknown |
| `nbLeechers` | qlonglong | leechers; `-1` = unknown |
| `engineName` | QString | resolved plugin name (short id) |
| `siteUrl` | QString | search-engine site URL (used to resolve engineName) |
| `descrLink` | QString | description/details page URL |
| `pubDate` | QDateTime | publication date (may be invalid) |

### 1.2 `SearchPluginInfo` struct (`searchpluginmanager.h`)
| field | type | meaning |
|---|---|---|
| `name` | QString | short id (used as key, filename stem, `engineName`) |
| `version` | `SearchPluginVersion` = `Utils::Version<2>` | e.g. `2.11` |
| `fullName` | QString | human display name |
| `url` | QString | engine site URL |
| `supportedCategories` | QStringList | e.g. `all`, `movies`, `tv`… |
| `iconPath` | Path | local `.png`/`.ico` favicon path |
| `enabled` | bool | enabled state |

### 1.3 `SearchPluginManager` (singleton — `SearchPluginManager::instance()`)
Query methods:
- `QStringList allPlugins()` — all installed plugin ids
- `QStringList enabledPlugins()` — only enabled
- `QStringList supportedCategories()` — union of categories across enabled plugins
- `QStringList getPluginCategories(const QString &pluginName)` — categories for `"all"` / `"enabled"` / `"multi"` / a specific name
- `SearchPluginInfo *pluginInfo(const QString &name)`
- `QString pluginNameBySiteURL(const QString &siteURL)`
- `QString pluginFullName(const QString &pluginName)`
- `static QString categoryFullName(const QString &categoryName)` — localized category label (table below)
- `static SearchPluginVersion getPluginVersion(const Path &filePath)`
- `static Path pluginsLocation()` / `static Path engineLocation()`

Mutation / lifecycle methods:
- `void enablePlugin(const QString &name, bool enabled = true)` — persists to `SearchEngines/disabledEngines` pref
- `void updatePlugin(const QString &name)` — downloads `<updateUrl><name>.py`
- `void installPlugin(const QString &source)` — source may be http(s) URL, `file:` URL, or local `.py` path
- `bool uninstallPlugin(const QString &name)` — returns false for bundled plugins that can't be removed
- `static void updateIconPath(SearchPluginInfo *plugin)`
- `void checkForUpdates()` — downloads `versions.txt` from update server
- `SearchHandler *startSearch(pattern, category, usedPlugins)`
- `SearchDownloadHandler *downloadTorrent(pluginName, url)`
- `QProcessEnvironment proxyEnvironment()`

Signals (all `(QString name[, ...])`):
- `pluginEnabled(name, enabled)`
- `pluginInstalled(name)`
- `pluginInstallationFailed(name, reason)`
- `pluginUninstalled(name)`
- `pluginUpdated(name)`
- `pluginUpdateFailed(name, reason)`
- `checkForUpdatesFinished(QHash<QString, SearchPluginVersion> updateInfo)`
- `checkForUpdatesFailed(reason)`

Update server URL (constant): `https://raw.githubusercontent.com/qbittorrent/search-plugins/refs/heads/master/nova3/engines/` (+`versions.txt` for the manifest, +`<name>.py` for a plugin).

Category id → localized label table (from `categoryFullName`): `all`→"All categories", `anime`→"Anime", `books`→"Books", `games`→"Games", `movies`→"Movies", `music`→"Music", `pictures`→"Pictures", `software`→"Software", `tv`→"TV shows".

### 1.4 `SearchHandler` (one per running query — created by `startSearch`)
- Runs external Python: `python <PYTHON_ISOLATE_MODE_FLAG> <PYTHON_UTF8_MODE_FLAG> <engineLocation>/nova2.py <usedPlugins joined by ','> <category> <pattern split on spaces>`.
- **Hard 3-minute timeout** (`QTimer` single-shot 3min) → auto-`cancelSearch()`.
- API: `bool isActive()`, `QString pattern()`, `QList<SearchResult> results()`, `void cancelSearch()` (kill on Windows, terminate on Unix).
- Signals: `newSearchResults(QList<SearchResult>)` (streamed incrementally as process emits stdout), `searchFinished(bool cancelled=false)`, `searchFailed(QString errorMessage)`.
- stdout line format parsed by `parseSearchResult`: `dl_link | name | size | seeds | leechers | engine_url | [desc_link] | [pub_date_epoch_secs]`. Fields after `engine_url` are optional. Non-numeric/negative seeds/leechers → `-1`. `pubDate` only set when epoch secs > 0.

### 1.5 `SearchDownloadHandler` (created by `downloadTorrent`)
- Runs `python … nova2dl.py <pluginName> <url>`; on success emits `downloadFinished(QString path, QString errorMessage)` where `path` is the downloaded `.torrent` file path (stdout `"<path> <url>"`, split on space, size==2).
- Used only for **non-magnet** download links; magnet links bypass this and are added directly.

### 1.6 Result flow (end-to-end)
1. User enters pattern, picks category + plugin scope, clicks **Search**.
2. `startSearch()` → new `SearchHandler` → new results tab (`SearchJobWidget`) added and made current.
3. `newSearchResults` → `SearchJobWidget::appendSearchResults` appends rows to `QStandardItemModel`; `SearchSortModel` proxy filters/sorts; results count label updates.
4. `searchFinished`/`searchFailed` → tab status changes → tab icon + tooltip update; `SearchWidget::searchFinished(bool failed)` emitted (drives main-window notification).
5. Double-click a row or context-menu **Download** → `downloadTorrent(rowIndex, option)`: magnet → `addTorrentManager()->addTorrent(...)`; else `SearchDownloadHandler` fetches `.torrent`, then adds it. Row is marked "visited" (greyed).

---

## 2. Search Tab — top bar (`SearchWidget` / `searchwidget.ui`)

Root layout is a `QVBoxLayout`:

### 2.1 Search bar row (`searchBarLayout`, horizontal)
1. **Search input** — `LineEdit` `lineEditSearchPattern` (custom LineEdit with a clear button). Rich tooltip explaining phrase syntax: plain words = AND; double-quoted = exact phrase. Enter/Return triggers the Search button. `textEdited` toggles new-query state. Has a `QCompleter` (case-insensitive, sorted, natural-order) backed by search history when history length > 0.
2. **Category dropdown** — `QComboBox comboCategory`. Populated by `fillCatCombobox()`: first item `All categories` (data `"all"`), then a separator, then categories supported by the currently-selected plugin scope, sorted locale-aware by label. Each item stores `(displayLabel, categoryId)`.
3. **Plugin scope dropdown** — `QComboBox selectPlugin`. Populated by `fillPluginComboBox()`, fixed first three items:
   - `Only enabled` → data `"enabled"`
   - `All plugins` → data `"all"`
   - `Select...` → data `"multi"`
   - then a separator, then each **enabled** plugin by full name (data = plugin id), sorted locale-aware.
   - Selecting `Select...` (`"multi"`) immediately opens the Search Plugins dialog (`selectMultipleBox`). Changing this box also refills the category box.
4. **Search button** — `QPushButton searchButton`, text "Search", icon `edit-find`. `searchButtonClicked()`.
5. **Stop button** — `QPushButton stopButton`, text "Stop". Hidden by default; **toggles with Search button** while the current tab's status is `Ongoing` and the query string is unchanged (`adjustSearchButton()`). `stopButtonClicked()` → `m_currentSearchTab->cancelSearch()`.

**Selection accessors:** `selectedCategory()` returns the category id from `comboCategory` current item data. `selectedPlugins()` maps scope: `"all"`→`allPlugins()`, `"enabled"`/`"multi"`→`enabledPlugins()`, otherwise `{specificPluginId}`.

### 2.2 Stacked content (`QStackedWidget stackedPages`)
- **`emptyPage`** — shown when `allPlugins().isEmpty()`. Centered label: *"There aren't any search plugins installed.\nClick the "Search plugins..." button at the bottom right of the window to install some."* When empty, the input, both combos, and Search button are all disabled (`selectActivePage()`).
- **`searchPage`** — holds `QTabWidget tabWidget` (tabsClosable=true, movable=true). One tab per search (a `SearchJobWidget`). Tab title = search pattern (with `&`→`&&` escaping). Tab icon reflects status (see icon map). Tab tooltip = status text.

### 2.3 Bottom bar
- Right-aligned **`QPushButton pluginsButton`**, text "Search plugins...", icon `plugins` (fallback `preferences-system-network`). Opens Search Plugins dialog (`pluginsButtonClicked` → `SearchPluginSelectDialog`).

### 2.4 Tab bar interactions (event filter on `tabWidget->tabBar()`)
- **Middle-click** a tab → close it.
- **Right-click** a tab → tab context menu (`showTabMenu`).
- **Double-click** a tab → copy that tab's pattern back into the search input.
- Tab close button / `tabCloseRequested` → `closeTab(index)`.

### 2.5 Tab context menu (`showTabMenu`)
- If tab **not** Ongoing: **"Refresh tab"** (re-runs the query in place via `refreshTab` → new `SearchHandler` assigned to the same tab).
- If tab **is** Ongoing: **"Stop search"** (`cancelSearch`).
- separator
- **"Close tab"**
- **"Close all tabs"**

### 2.6 Keyboard shortcuts (SearchWidget)
- `QKeySequence::Find` **and** `Ctrl+E` → toggle focus between the search input and the current tab's results-filter LineEdit (select-all on focus).
- `QKeySequence::Close` → close current tab.
- Enter/Return in search input → click Search.

### 2.7 Status → icon / text maps
Status icon (`statusIconName`, used on tabs): `Ongoing`→`queued`, `Finished`→`task-complete`, `Aborted`→`task-reject`, `Error`→`error`, `NoResults`→`dialog-warning`.
Status text (`statusText`, tab tooltip / statusTip): `Ongoing`→"Searching...", `Finished`→"Search has finished", `Aborted`→"Search aborted", `Error`→"An error occurred during search...", `NoResults`→"Search returned no results".

### 2.8 Validation / notifications on Search
- Empty pattern → `QMessageBox::critical` title "Empty search pattern", body "Please type a search pattern first".
- Python not installed (`Utils::ForeignApps::pythonInfo().isValid()` false) → desktop notification: title "Search Engine", body "Please install Python to use the Search Engine." (same guard on Refresh tab).

### 2.9 History & session persistence (SearchWidget "DataStorage", runs on a background IO thread)
- Data dir: `<Data>/SearchUI/`. Files: `History.txt` (newline-separated patterns), `Session.json`, and per-tab `<tabID>.json` (result rows).
- History gated by pref `Search/HistoryLength` (default 50, clamped 0–99; 0 disables). New patterns appended, de-duplicated, trimmed to length.
- Session (open tabs + current tab) persisted only when pref `Search/StoreOpenedSearchTabs` is true; per-tab results persisted only when `Search/StoreOpenedSearchTabResults` is true. On startup, tabs (and optionally results) are restored.
- Session JSON keys: top-level `Tabs` (array), `CurrentTab`; per-tab `ID`, `SearchPattern`. Result-row JSON keys: `FileName`, `FileURL`, `FileSize`, `SeedersCount`, `LeechersCount`, `EngineName`, `SiteURL`, `DescrLink`, `PubDate` (epoch secs).
- Max file sizes: history/session/results each 10 MiB.

---

## 3. Search Results Tab (`SearchJobWidget` / `searchjobwidget.ui`)

`QVBoxLayout`: filter row on top, results table below.

### 3.1 Filter row (`horizontalLayout`)
Left→right:
1. **Results filter input** — a `LineEdit` (`m_lineEditSearchResultsFilter`, inserted at index 0 at runtime, not in the .ui), placeholder "Filter search results...". `textChanged` → `filterSearchResults`. Filters via wildcard→regex by default, or raw regex if pref `SearchTab/UseRegexAsFilteringPattern` is on. Custom context menu adds a checkable **"Use regular expressions"** action bound to that pref.
2. **Results count label** — `QLabel resultsLbl`: "Results (showing <i>%1</i> out of <i>%2</i>):" (filtered / total).
3. horizontal spacer
4. Label **"Search in:"** + **`QComboBox filterMode`** — items: `Torrent names only` (data `OnlyNames`) and `Everywhere` (data `Everywhere`); tooltip explains that some engines return matches in descriptions/inner filenames, `Everywhere` disables name filtering, `Torrent names only` keeps only rows whose name matches the query. Persisted via `SettingValue<NameFilteringMode>` key **`Search/FilteringMode`** (default `OnlyNames`).
5. Label **"Seeds:"** + `QSpinBox minSeeds` (0–1000) + label **"to"** + `QSpinBox maxSeeds` (0–1000, specialValueText "∞" at max meaning unlimited). Tooltips: "Minimum/Maximum number of seeds".
6. Label **"Size:"** + `QDoubleSpinBox minSize` (0–1000) + `QComboBox minSizeUnit` + label **"to"** + `QDoubleSpinBox maxSize` (0–1000, specialValueText "∞") + `QComboBox maxSizeUnit`. Unit combos filled with Byte/KiB/MiB/GiB/TiB/PiB/EiB. Defaults: min = 0 MiB, max = -1 (∞) GiB.

All filter controls feed the proxy model live (`updateNameFilter`, `updateSeedsFilter`, `updateSizeFilter`).

### 3.2 Results table (`QTreeView resultsBrowser`)
Backed by `QStandardItemModel` → `SearchSortModel` proxy. Configured: `rootIsDecorated=false`, `allColumnsShowFocus=true`, `sortingEnabled=true`, `ExtendedSelection`, no edit triggers, header first-section movable, last-section NOT stretched, elide right.

**Model columns** (`SearchSortModel::SearchColumn`, index order):
| idx | enum | header label (tr) | visible? | display | align |
|---|---|---|---|---|---|
| 0 | `NAME` | "Name" | yes | fileName | left |
| 1 | `SIZE` | "Size" | yes | `friendlyUnit(fileSize)` | right |
| 2 | `SEEDS` | "Seeders" | yes | number | right |
| 3 | `LEECHES` | "Leechers" | yes | number | right |
| 4 | `ENGINE_NAME` | "Engine" | yes | engineName | left |
| 5 | `ENGINE_URL` | "Engine URL" | yes | siteUrl | left |
| 6 | `PUB_DATE` | "Published On" | yes | `QLocale short` of local pubDate | left |
| 7 | `DL_LINK` | (none) | **hidden always** | fileUrl | — |
| 8 | `DESC_LINK` | (none) | **hidden always** | descrLink | — |

`NB_SEARCH_COLUMNS` = 9. Only columns 0–6 are user-toggleable; `DL_LINK`(7)/`DESC_LINK`(8) are permanently hidden data carriers. (The legacy macros `ENGINE_URL_COLUMN 4` / `URL_COLUMN 5` in the header match ENGINE_NAME/ENGINE_URL indices — note the naming is slightly off but the numeric indices are authoritative.)

Two roles per cell: `Qt::DisplayRole` (formatted string) and `SearchSortModel::UnderlyingDataRole` = `Qt::UserRole` (raw typed value used for sort + filter). Also `Qt::TextAlignmentRole` for right-aligned numeric columns. Visited-link marker role: `LinkVisitedRole = Qt::UserRole + 100` on column 0.

Header state persisted as `QByteArray` via pref **`GUI/Qt6/SearchTab/HeaderState`** (saved on resize/move/sort-indicator change).

### 3.3 Sorting & filtering (`SearchSortModel`)
- `setSortRole/​setFilterRole = UnderlyingDataRole`.
- `lessThan`: NAME and ENGINE_URL use natural (human) case-insensitive compare; all other columns use default typed compare.
- `filterAcceptsRow` combines: (a) name-word filter — when name-filter enabled and search term non-empty, every whitespace-split word (or the whole quoted phrase) must be a case-insensitive substring of the NAME's underlying data; (b) size range (minSize>0 / maxSize>=0, bytes); (c) seeds range; (d) leeches range; then base regex filter (the results-filter LineEdit's regex, applied on the display via base class). Setters: `enableNameFilter`, `setNameFilter`, `setSizeFilter`, `setSeedsFilter`, `setLeechesFilter`. Uses Qt 6.10 `beginFilterChange/endFilterChange` where available, else `invalidateRowsFilter`.

### 3.4 Results context menu (`contextMenuEvent`)
Order:
1. Icon `download` — **"Open download window"** → `downloadTorrents(AddTorrentOption::ShowDialog)`
2. Icon `downloading` (fallback `download`) — **"Download"** → `downloadTorrents(AddTorrentOption::SkipDialog)`
3. separator
4. Icon `application-url` — **"Open description page"** → `openTorrentPages()` (opens each selected row's `DESC_LINK` in the browser; blocks/ warns on empty URLs and on local-file URLs as potentially malicious)
5. Submenu icon `edit-copy` **"Copy"**:
   - Icon `name` — **"Name"** → copies NAME column values
   - Icon `insert-link` — **"Download link"** → copies DL_LINK values
   - Icon `application-url` — **"Description page URL"** → copies DESC_LINK values

`AddTorrentOption` enum: `Default`, `ShowDialog`, `SkipDialog`. Download acts on all selected rows. Enter/Return key on the table = Download (default option).

### 3.5 Column-header context menu (`displayColumnHeaderMenu`, right-click header)
Title "Column visibility", tooltips visible. For columns 0–6: a checkable action per column (checked = visible); unchecking is refused if it would hide the last visible column; re-showing a zero-width column auto-resizes to contents. Then a separator and **"Resize columns"** (tooltip "Resize all non-hidden columns to the size of their contents"). Every change persists header state.

### 3.6 Visited-row styling
On download of a row, `setRowVisited(row)` sets `LinkVisitedRole=true` on col 0 and paints the whole row with `QPalette(Disabled, WindowText)` via `Qt::ForegroundRole`. On UI theme change (`UIThemeManager::themeChanged`), all rows flagged visited are repainted with the new disabled-text color. (This replaces what a delegate would do — implement in QML by tracking a per-row `visited` flag and applying a muted foreground color that follows the theme.)

### 3.7 Two construction paths
- Live search: `SearchJobWidget(id, SearchHandler*, app, parent)` → `assignSearchHandler` wires the three handler signals, sets status `Ongoing`.
- Restored from session: `SearchJobWidget(id, searchPattern, QList<SearchResult>, app, parent)` → just seeds rows, no handler.
`assignSearchHandler` also clears existing rows (used by "Refresh tab").

---

## 4. Search Plugins dialog (`SearchPluginSelectDialog` / `searchpluginselectdialog.ui`)

Modeless dialog, title "Search plugins", **accepts drag-and-drop** of `.py` files / URLs (drop installs each; accepts `text/plain` and `text/uri-list`). Size persisted via `SettingValue<QSize>` key **`SearchPluginSelectDialog/Size`**.

Layout (`QVBoxLayout`):
1. Bold+underline label **"Installed search plugins:"**
2. **`QTreeWidget pluginsTree`** (ExtendedSelection, uniformRowHeights, not expandable, sortingEnabled, custom context menu, `rootIsDecorated=false`, first section movable, default sort col 0 ascending). Columns (`PluginColumns` enum):
   | idx | enum | header | content |
   |---|---|---|---|
   | 0 | `PLUGIN_NAME` | "Name" | fullName + favicon icon (DecorationRole) |
   | 1 | `PLUGIN_VERSION` | "Version" | version string |
   | 2 | `PLUGIN_URL` | "Url" | site url |
   | 3 | `PLUGIN_STATE` | "Enabled" | "Yes"/"No" |
   | 4 | `PLUGIN_ID` | (blank) | plugin id — **column hidden** |
   Enabled rows are painted **green**, disabled rows **red** (foreground role, all columns). **Double-clicking a row toggles enabled/disabled** (`togglePluginState` → `enablePlugin`).
3. Wrapping label (warning): "Warning: Be sure to comply with your country's copyright laws when downloading torrents from any of these search engines."
4. Italic label with external link: "You can get new search engine plugins here: https://plugins.qbittorrent.org" (openExternalLinks).
5. Button row: **"Install a new one"** (`installButton`), **"Check for updates"** (`updateButton`), **"Close"** (`closeButton`).

Row favicon handling: if `iconPath` exists use it; else download `<plugin.url>/favicon.ico` via DownloadManager and, on success, copy into `pluginsLocation()/<id>.<ico|png>` and set as the row's DecorationRole (with a double-decode validity check).

### 4.1 Plugin context menu (`displayContextMenu`, right-click tree)
- **"Enabled"** (`actionEnable`, checkable; reflects first selected plugin's state) → `enableSelection(bool)` enables/disables all selected.
- separator
- **"Uninstall"** (`actionUninstall`, icon `list-remove`) → `on_actionUninstall_triggered`: uninstall each selected; bundled plugins can't be removed → they're disabled instead and flagged. Ends with either `QMessageBox::warning` "Uninstall warning" ("Some plugins could not be uninstalled because they are included in qBittorrent. Only the ones you added yourself can be uninstalled.\nThose plugins were disabled.") or `QMessageBox::information` "Uninstall success" ("All selected plugins were uninstalled successfully").

### 4.2 Check for updates (`updateButton`)
`checkForUpdates()` downloads `versions.txt`; on `checkForUpdatesFinished(updateInfo)`: if empty → info "All your plugins are already up to date."; else calls `updatePlugin()` for each outdated plugin. On `checkForUpdatesFailed` → warning "Sorry, couldn't check for plugin updates. %1". After a batch of installs/updates completes, an aggregate info box "Search plugin update" lists "Plugins installed or updated: %1". A wait-cursor is shown while async ops are pending (ref-counted `startAsyncOp`/`finishAsyncOp`).

### 4.3 Install-result signal handling
- `pluginInstalled(name)` → add row, mark for aggregate report.
- `pluginInstallationFailed(name, reason)` → info "Search plugin install" ("Couldn't install "%1" search engine plugin. %2").
- `pluginUpdated(name)` → update row version, mark for report.
- `pluginUpdateFailed(name, reason)` → info "Search plugin update" ("Couldn't update "%1" search engine plugin. %2").

---

## 5. Plugin source dialog (`SearchPluginSourceDialog` / `searchpluginsourcedialog.ui`)

Small dialog, title "Plugin source". Size persisted via `SettingValue<QSize>` key **`SearchPluginSourceDialog/Size`**. Content: bold+underline label "Search plugin source:" + two buttons:
- **"Local file"** (`localButton`) → emits `askForLocalFile()` and closes.
- **"Web link"** (`urlButton`) → emits `askForUrl()` and closes.

Wiring in the select dialog:
- `askForLocalFile` → `askForLocalPlugin()`: `QFileDialog::getOpenFileNames` titled "Select search plugins", home dir, filter "qBittorrent search plugin (*.py)"; installs each chosen file.
- `askForUrl` → `askForPluginUrl()`: opens `AutoExpandableDialog::getText` titled **"New search engine plugin URL"**, prompt "URL:", default = clipboard text if it's a supported-scheme URL ending `.py`, else `http://`. Re-prompts with warning "Invalid link" ("The link doesn't seem to point to a search engine plugin.") until the URL ends with `.py` or is cancelled; then `installPlugin(url)`.

`installPlugin` accepts: http(s) URL (downloaded via DownloadManager, honoring "use proxy for general purposes"), `file:` URL, or local `.py` path. Non-`.py` local files → `pluginInstallationFailed` with "Unknown search engine plugin file format." Version guard: installing a same-or-older version → `pluginUpdateFailed` "A more recent version of this plugin is already installed." Install/rollback uses a `.bak` backup.

---

## 6. Settings keys (authoritative)
| key | type | default | meaning |
|---|---|---|---|
| `Search/HistoryLength` | int | 50 (clamp 0–99) | search-input completer history size; 0 disables |
| `Search/StoreOpenedSearchTabs` | bool | false | persist open tabs across restart |
| `Search/StoreOpenedSearchTabResults` | bool | false | also persist each tab's result rows |
| `Search/FilteringMode` | enum(`NameFilteringMode`) | `OnlyNames` | results "Search in:" mode |
| `SearchTab/UseRegexAsFilteringPattern` | bool | false | results-filter uses raw regex vs wildcard |
| `GUI/Qt6/SearchTab/HeaderState` | QByteArray | (empty) | results table header layout |
| `SearchEngines/disabledEngines` | QStringList | (empty) | list of disabled plugin ids |

Enums for QML: `NameFilteringMode { Everywhere, OnlyNames }`; `Status { Ready, Ongoing, Finished, Error, Aborted, NoResults }`; `AddTorrentOption { Default, ShowDialog, SkipDialog }`.

---

## 7. QML/Material rebuild notes
- Replace `QStackedWidget` empty/search pages with a `StackLayout` or `Loader` keyed on `plugins.length === 0`.
- Search bar → a Material `TextField` (with clear affordance + completer/`Menu` for history), two `ComboBox`es, and a primary `Button` that swaps to a Stop button while `status === Ongoing`.
- Results tabs → a `TabBar`/`TabButton` + `SwipeView`/`StackLayout`; each page is a results `TableView`/`TreeView`. Preserve middle-click-close, right-click tab menu, double-click-to-copy-pattern.
- Results table → `TableView` with the 7 visible columns above (2 hidden data roles carried on the model), right-aligned numeric columns, natural sort on Name/Engine URL, live seeds/size/name filtering, per-row visited (muted) styling that reacts to theme, header column-visibility menu with "can't hide last column" rule + "Resize columns".
- Context menus → Material `Menu`s exactly mirroring section 3.4 (Open download window / Download / Open description page / Copy ▸ Name, Download link, Description page URL).
- Plugins dialog → a Material dialog with a table (Name+icon / Version / Url / Enabled), green/red enabled coloring (or a Material `Switch`), double-click / context-menu toggle, Install / Check for updates / Close, plus drag-drop install; keep the two-step "Local file / Web link" source picker and the URL input dialog.
- Keep the backend `SearchPluginManager`/`SearchHandler`/`SearchDownloadHandler` process-driven engine layer as-is behind a thin QML-facing controller; it already exposes all needed signals/slots. Python (`nova2.py`, `nova2dl.py`) remains the execution backend; guard all search/refresh actions on `pythonInfo().isValid()`.


---

# Area: RSS tab (feeds tree, articles list, article preview, toolbar, context menus), RSS Feed Options dialog, Automated Download Rules dialog, and the base/rss engine API

# RSS Tab & Automated Download Rules — Implementation Spec

Source files inventoried (all under `src/`):
- `gui/rss/rsswidget.{h,cpp,ui}` — main RSS tab
- `gui/rss/feedlistwidget.{h,cpp}` — feeds tree
- `gui/rss/articlelistwidget.{h,cpp}` — articles list
- `gui/rss/rssfeeddialog.{h,cpp,ui}` — new/edit subscription dialog
- `gui/rss/automatedrssdownloader.{h,cpp,ui}` — Automated Download Rules dialog
- `gui/rss/htmlbrowser.{h,cpp}` — article preview browser (QTextBrowser subclass)
- `gui/addtorrentparamswidget.{h,cpp,ui}` — embedded "Torrent parameters" panel used by rules
- `base/rss/rss_session.*`, `rss_item.*`, `rss_folder.*`, `rss_feed.*`, `rss_article.*`, `rss_autodownloader.*`, `rss_autodownloadrule.*`

---

## 1. RSS Tab (main view) — `RSSWidget`

Root is a `QVBoxLayout` (`verticalLayout_2`). Window title in .ui is "Search" (unused; the tab label is set by the parent). Structure top-to-bottom:

1. **`labelWarn`** (QLabel, italic, `color: red;`, wordWrap): text = "Fetching of RSS feeds is disabled now! You can enable it in application settings." Hidden when `RSS::Session::instance()->isProcessingEnabled()` is true; visibility toggled by `handleSessionProcessingStateChanged(bool)` (bound to `Session::processingStateChanged`). Show = `!enabled`.
2. **Toolbar** (`horizontalLayout`, QHBoxLayout) — see §2.
3. **`splitterSide`** (QSplitter, Horizontal, Expanding): left = `feedListWidget` (FeedListWidget), right = a container (`layoutWidget` / `verticalLayout`) holding:
   - **`news_lbl`** (QLabel, bold): "Torrents: (double-click to download)"
   - **`splitterMain`** (QSplitter, Horizontal, Expanding): left = `articleListWidget` (ArticleListWidget), right = `textBrowser` (HtmlBrowser).

So the tab is a 3-pane layout: Feeds tree | Articles list | Article preview, with a header label above the article/preview pair.

### Persistence (Preferences keys, exact)
- `GUI/RSSWidget/OpenedFolders` (QStringList) — expanded folder paths. Saved via `saveFoldersOpenState()`; each path from `FeedListWidget::itemPath(item)`; restored by `loadFoldersOpenState()` splitting on `\`.
- `GUI/Qt6/RSSWidget/FeedListState` (QByteArray) — feed tree `QHeaderView::saveState()`. Saved on `sortIndicatorChanged` and on destruction.
- `GUI/Qt6/RSSWidget/SideSplitterState` (QByteArray) — `splitterSide` state.
- `GUI/Qt6/RSSWidget/MainSplitterState` (QByteArray) — `splitterMain` state. Both splitter states saved on `splitterMoved`.

### Signals out
- `unreadCountUpdated(int count)` — emitted by `handleUnreadCountChanged()` from `Session::rootFolder()->unreadCount()` when root folder `unreadCountChanged` fires. Parent tab uses this to show a badge/count on the RSS tab.

### Keyboard shortcuts (scoped to `feedListWidget`, `Qt::WidgetShortcut`)
- **F2** → `renameSelectedRSSItem()`
- **Delete** (`Utils::KeySequence::deleteItem()`) → `deleteSelectedItems()`

### Filter box (`m_rssFilter`, a `LineEdit`)
Created in code (not in .ui), `maximumWidth=200`, placeholder "Filter feed items...", inserted into the toolbar right after `spacer1`. On `textChanged` → `handleRSSFilterTextChanged(newFilter)` which re-populates the article list for the current feed item with the new title filter (case-insensitive substring on article title).

---

## 2. RSS Toolbar (`horizontalLayout`)

Left-aligned QPushButtons, then a horizontal spacer (`spacer1`), then the filter LineEdit, then a right-aligned button. Buttons (exact object names / captions / icons / slots):

| Button | Caption | Icon (theme id, fallback) | Action |
|---|---|---|---|
| `newFeedButton` | "New subscription" | `list-add` | `on_newFeedButton_clicked()` — opens RSSFeedDialog to add a feed |
| `markReadButton` | "Mark items read" | `task-complete` / `mail-mark-read` | `on_markReadButton_clicked()` — mark selected feeds/folders read |
| `updateAllButton` | "Update all" (tooltip "Refresh RSS streams") | `view-refresh` | `refreshAllFeeds()` |
| `rssDownloaderBtn` | "RSS Downloader..." | `downloading` / `download` | `on_rssDownloaderBtn_clicked()` — opens AutomatedRssDownloader |

(Icons are only assigned `#ifndef Q_OS_MACOS`.) There is **no** dedicated "RSS settings" button in this widget — RSS fetch/processing settings live in the app Options dialog; the toolbar only has the four buttons above plus the filter. The Material rebuild should keep: New subscription, Mark items read, Update all, filter field, RSS Downloader.

### Toolbar behaviors
- **New subscription** (`on_newFeedButton_clicked`): computes destination folder from current selection (if selected item is a feed, uses its parent; if All/Unread sticky or none, uses `rootFolder()`). Pre-fills URL from clipboard if it has a supported scheme, else `https://`. Loops opening `RSSFeedDialog` until a feed is added or cancelled; on success expands parent and selects the new feed. `addFeed(feedURL, joinPath(destFolder.path, feedURL), refreshInterval)`.
- **Mark items read**: iterates selected feed-tree items, calls `RSS::Item::markAsRead()` on each; breaks after the All or Unread sticky item (those already cover everything).
- **Update all**: `Session::instance()->rootFolder()->refresh()`.

---

## 3. Feeds Tree — `FeedListWidget` (extends QTreeWidget)

Single column, header text "RSS feeds". `contextMenuPolicy = CustomContextMenu`, `dragDropMode = InternalMove`, `selectionMode = ExtendedSelection`, `columnCount = 1`. Sorting enabled after initial fill.

### Node model
- Backing RSS item pointer stored in `item->data(0, Qt::UserRole)` as `intptr_t` (reinterpret_cast of `RSS::Item*`). Retrieved via `getRSSItem()`.
- Custom role `ItemTagRole = Qt::UserRole + 1` holds an `ItemTag` enum: `RegularItem=0`, `AllArticlesItem`, `UnreadArticlesItem`.
- Two **sticky items** created in the ctor, always sorted to the top (custom `operator<` in `FeedListItem` keeps sticky items above regular items regardless of sort order):
  - **All** — text "All", icon `mail-inbox`, tag AllArticlesItem. UserRole points at rootFolder.
  - **Unread (N)** — text `Unread  (%1)` with rootFolder unread count, icon `mail-inbox`, tag UnreadArticlesItem. Count text updated on rootFolder `unreadCountChanged`.
- Regular items display `"%1  (%2)"` = name + unreadCount (two spaces before the paren). Feeds get `rssFeedIcon()`; folders get icon `directory`.

### Feed icon states (`rssFeedIcon`)
- Loading (`feed->isLoading()`) → icon `loading`.
- Error (`feed->hasError()`) → icon `task-reject` / `unavailable`.
- Otherwise → the downloaded favicon at `feed->iconPath()`, fallback `application-rss`.

### Live updates (bound to `RSS::Session` signals)
- `itemAdded` → `handleItemAdded` → create tree node under mapped parent.
- `feedStateChanged` → refresh decoration icon.
- `feedIconLoaded` → refresh icon if not loading/error.
- `itemPathChanged` → `handleItemPathChanged` — update display text and re-parent node.
- `itemAboutToBeRemoved` → delete node; if only root remains, clear current item (prevents Unread repopulation).
- Per-item `RSS::Item::unreadCountChanged` → `handleItemUnreadCountChanged` updates the `name (count)` text (or the Unread sticky text for root).

### Drag & drop
- `dragMoveEvent`: reject drops **onto** the All/Unread sticky items, reject **dragging** the sticky items, and reject dropping **onto a feed** (only folders/root accept drops).
- `dropEvent`: destination = folder under cursor or rootFolder; for each selected item calls `Session::moveItem(item, joinPath(destFolder.path, item.name))`; expands destination.

### Public API used by RSSWidget
`stickyItemAllArticles()`, `stickyItemUnreadArticles()`, `isStickyItem()`, `getAllOpenedFolders()`, `getRSSItem()`, `mapRSSItem()`, `itemPath()`, `isFeed()`, `isFolder()`.

### Feeds context menu (`displayRSSListMenu`, right-click)
Clears selection if clicking empty space. All entries are `QAction`s defined in the .ui:

**When ≥1 item selected:**
- `actionUpdate` — "Update" (icon `view-refresh`)
- `actionMarkItemsRead` — "Mark items read" (icon `task-complete`/`mail-mark-read`)
- separator
- **If exactly 1 selected AND not a sticky item:**
  - `actionRename` — "Rename..." (icon `edit-rename`)
  - `actionEditFeed` — "Feed options..." (icon `edit-rename`) — **only if the item is a feed**
  - `actionDelete` — "Delete" (icon `edit-clear`)
  - separator
  - `actionNewFolder` — "New folder..." (icon `folder-new`) — **only if the item is a folder**
- **If >1 selected:** `actionDelete`, separator
- `actionNewSubscription` — "New subscription..." (icon `list-add`)
- **If first selected is a feed:** separator + `actionCopyFeedURL` — "Copy feed URL" (icon `edit-copy`)

**When nothing selected:** `actionNewSubscription`, `actionNewFolder`, separator, `actionUpdateAllFeeds` ("Update all feeds", icon `view-refresh`).

### Feed-tree action handlers
- **actionDelete / deleteSelectedItems**: confirm `QMessageBox::question` "Deletion confirmation" / "Are you sure you want to delete the selected RSS feeds?"; skip sticky items; `Session::removeItem(itemPath)`.
- **actionRename / renameSelectedRSSItem**: `AutoExpandableDialog::getText` "Please choose a new name for this RSS feed" / "New feed name:" prefilled with current name; `Session::moveItem(item, joinPath(parentPath, newName))`; on error shows "Rename failed". (Also triggered by double-click and F2.)
- **actionEditFeed / editSelectedRSSFeed**: opens `RSSFeedDialog` prefilled with feed URL + refresh interval; on accept sets `feed->setRefreshInterval(...)` then `Session::setFeedURL(feed, newURL)`.
- **actionUpdate / refreshSelectedItems**: if the All or Unread sticky is selected → refreshAllFeeds(); else `item->refresh()`.
- **actionNewFolder / askNewFolder**: `AutoExpandableDialog::getText` "Please choose a folder name" / "Folder name:" default "New folder"; `Session::addFolder(joinPath(destFolder.path, name))`.
- **actionCopyFeedURL / copySelectedFeedsURL**: copies newline-joined feed URLs to clipboard.
- Double-click on a feed item → `renameSelectedRSSItem()` (connected via `QAbstractItemView::doubleClicked`).

---

## 4. Articles List — `ArticleListWidget` (extends QListWidget)

`contextMenuPolicy = CustomContextMenu`, iconSize = `Utils::Gui::smallIconSize()`, `selectionMode = ExtendedSelection`. Flat list of the current feed/folder's articles.

### Item model
- DisplayRole = `article->title()`.
- `Qt::UserRole` = `QVariant::fromValue(RSS::Article*)`. Retrieve via `getRSSArticle()`.
- Read/unread styling (`applyUITheme`):
  - **Read**: foreground color `RSS.ReadArticle` theme color (fallback = palette Inactive WindowText); icon `rss_read_article` / `sphere`.
  - **Unread**: foreground color `RSS.UnreadArticle` (fallback = palette Active Link); icon `rss_unread_article` / `sphere`.
  - Re-applied on `UIThemeManager::themeChanged`.

### Populating (`setRSSItem(rssItem, unreadOnly, filter)`)
- Called from RSSWidget on feed selection change and on filter text change.
- `unreadOnly = true` only when the **Unread** sticky item is current.
- Filter = case-insensitive substring on `article->title()`.
- Clears list, disconnects previous item, connects new item's `newArticle` / `articleRead` / `articleAboutToBeRemoved`. For each article, include if `!(unreadOnly && isRead)` AND (filter empty OR title contains filter).
- New articles (`handleArticleAdded`) are inserted at the **top** (index 0).
- Maintains `checkInvariant()`: list count == mapping count.

### Selection / current-item behavior (in RSSWidget)
- `currentItemChanged` → `handleCurrentArticleItemChanged(current, previous)`:
  - Clears `textBrowser`.
  - **Marks the *previous* article as read** (`article->markAsRead()`), then renders the current article. (So navigating away from an article marks it read.)
- Double-click on an article → `downloadSelectedTorrents()`.

### Articles context menu (`displayItemsListMenu`)
Scans selected articles to compute `hasTorrent` (any non-empty `torrentUrl()`) and `hasLink` (any non-empty `link()`):
- `actionDownloadTorrent` — "Download torrent" (icon `downloading`/`download`) — if hasTorrent.
- `actionOpenNewsURL` — "Open news URL" (icon `application-url`) — if hasLink.
- Menu not shown if empty.

### Article action handlers
- **downloadSelectedTorrents**: for each selected article → `markAsRead()` then `app()->addTorrentManager()->addTorrent(article->torrentUrl())`.
- **openSelectedArticlesUrls**: for each selected article → `markAsRead()`, open `article->link()` via `QDesktopServices::openUrl`. Guards: empty link → counted, warn "The following article has no news URL provided:\n%1" (+ "There are %1 more articles with the same issue."); local-file link → blocked + logged WARNING "Blocked opening RSS article URL..." and warn dialog. Security-relevant: local-file URLs must be blocked in the rebuild.

---

## 5. Article Preview — `HtmlBrowser` (`textBrowser`, extends QTextBrowser)

`setOpenLinks(false)`; an event filter re-renders the current article on `QEvent::PaletteChange` (theme change). Anchor clicks (`anchorClicked`): if URL has a supported scheme AND path ends `.torrent`, or scheme == `magnet` → `addTorrentManager()->addTorrent(url)`; otherwise `QDesktopServices::openUrl`.

### Rendered HTML (`renderArticle`) — header block + body
Header is a red-bordered `div` containing, in order:
- **Title** — bold, background = palette Highlight color, text color = HighlightedText.
- **Date** — `"Date: "` + `QLocale::system().toString(date.toLocalTime(), ShortFormat)`, background = AlternateBase (only if date valid).
- **Feed** — `"Feed: "` + `article->feed()->title()` — **only when a sticky (All/Unread) item is current** (so the user knows which feed).
- **Author** — `"Author: "` + author (if non-empty).
- **Open link** — anchor to `article->link()` labeled "Open link" (if non-empty).

Body: `article->description()`. If `Qt::mightBeRichText(description)` → inserted as-is. Otherwise BBCode→HTML conversion is applied and wrapped in `<pre>`:
- `[img]...[/img]` → `<img src="\1">`
- `[url=...]...[/url]` → `<a href>...</a>`
- `[b]/[i]/[u]/[s]` → HTML tags
- `[color=...]...[/color]` → `<span style="color:...">`
- `[size=...]...[/size]` → `<span style="font-size:...px">`

Finally, relative URLs in `href`/`src` are converted to absolute against the article link's base URL (`convertRelativeUrlToAbsolute`).

---

## 6. RSS Feed Options Dialog — `RSSFeedDialog` (`rssfeeddialog.ui`)

Window title "RSS Feed Options". `QGridLayout`:
- Row 0: `labelFeedURL` "URL:" + `textFeedURL` (QLineEdit).
- Row 1: `labelRefreshInterval` "Refresh interval:" + `spinRefreshInterval` (QSpinBox): max = INT_MAX, `AdaptiveDecimalStepType`, suffix " sec", `specialValueText = "Default"` (value 0 = use session default).
- Vertical spacer, then `buttonBox` (Ok | Cancel).

Behavior: **Ok disabled while URL is empty** (`feedURLChanged` enables it). `refreshInterval()` returns `std::chrono::seconds(spin.value())`. Used both for **add** (New subscription) and **edit** (Feed options...).

---

## 7. Automated Download Rules Dialog — `AutomatedRssDownloader` (`automatedrssdownloader.ui`)

Window title "RSS Downloader". Opened modeless via `open()` with `WA_DeleteOnClose`. Root `QVBoxLayout` (`verticalLayout_4`):

1. **`labelWarn`** (italic red, wordWrap): "Auto downloading of RSS torrents is currently disabled. You can enable it in application settings." Hidden when `RSS::AutoDownloader::instance()->isProcessingEnabled()`; toggled by `handleProcessingStateChanged(bool)`.
2. **`mainSplitter`** (QSplitter Horizontal, 3 panes; collapsible: pane0=false, pane1=false, pane2=true — only the preview collapses):
   - **Pane 0 — Rules list column** (`ruleListLayout`)
   - **Pane 1 — `ruleDefSplitter`** (QSplitter Vertical): rule definition scroll area on top, "Apply Rule to Feeds" list on bottom
   - **Pane 2 — Matching RSS Articles** preview
3. **Bottom buttons** (`buttonsLayout`): `importBtn` "&Import...", `exportBtn` "&Export...", `buttonBox` (Close).

### Persistence (SettingValue keys, exact)
- `RssFeedDownloader/geometrySize` (QSize) — dialog size.
- `GUI/Qt6/RSSFeedDownloader/HSplitterSizes` (QByteArray) — `mainSplitter` state.
- `GUI/Qt6/RSSFeedDownloader/RuleDefSplitterState` (QByteArray) — `ruleDefSplitter` state.
Saved on destruction (`saveSettings`), which also calls `saveEditedRule()` first.

### 7a. Rules list column (Pane 0)
Header row (`ruleListHeaderLayout`): bold label `ruleListLabel` "Download Rules", then four `QToolButton`s (iconSize 24x20):
- `cloneRuleBtn` (icon `edit-copy`, tooltip "Clone selected rule to a new rule.\nThe cloned rule will be set as disabled and the downloaded episodes history will be cleared.") → `cloneSelectedRule()`. Enabled only when exactly 1 rule selected.
- `renameRuleBtn` (icon `edit-rename`, tooltip "Rename selected rule. You can also use the F2 hotkey to rename.") → `onRenameRuleBtnClicked()`→`renameSelectedRule()`. Enabled only when exactly 1 selected.
- `removeRuleBtn` (icon `edit-clear`/`list-remove`) → `onRemoveRuleBtnClicked()`.
- `addRuleBtn` (icon `list-add`) → `onAddRuleBtnClicked()`.

**`ruleList`** (QListWidget, `CustomContextMenu`, sortingEnabled, ExtendedSelection): one checkable item per rule (`Qt::ItemIsUserCheckable`), checkState = rule.isEnabled() ? Checked : Unchecked, text = rule name. 
- `itemSelectionChanged` → `updateRuleDefinitionBox()`.
- `itemChanged` (check toggle) → `handleRuleCheckStateChange()` sets that item current (so toggling enable also selects it and persists via saveEditedRule).
- Double-click / F2 → `renameSelectedRule()`. Delete key → `onRemoveRuleBtnClicked()`.
- Populated from `AutoDownloader::instance()->rules()`; kept in sync via `ruleAdded`/`ruleRenamed`/`ruleChanged`/`ruleAboutToBeRemoved` signals.

**Rules list context menu (`displayRulesListMenu`):**
- "Add new rule..." (icon `list-add`) → onAddRuleBtnClicked
- If exactly 1 selected: "Delete rule" (`edit-clear`/`list-remove`); sep; "Rename rule..." (`edit-rename`); sep; "Clone rule..." (`edit-copy`)
- If >1 selected: "Delete selected rules"
- If ≥1 selected: sep; "Clear downloaded episodes..." (`edit-clear`) → `clearSelectedRuleDownloadedEpisodeList()`

**Add rule** (`onAddRuleBtnClicked`): `AutoExpandableDialog::getText` "New rule name" / "Please type the name of the new download rule."; reject empty; conflict check via `hasRule` → warn "Rule name conflict" / "A rule with this name already exists, please choose another name."; clears selection then `setRule(AutoDownloadRule(ruleName))`.
**Remove** (`onRemoveRuleBtnClicked`): confirm "Rule deletion confirmation" — single: "Are you sure you want to remove the download rule named '%1'?"; multi: "Are you sure you want to remove the selected download rules?"; then `removeRule(name)` per item.
**Rename** (`renameSelectedRule`): loop `AutoExpandableDialog::getText` "Rule renaming" / "Please type the new rule name" prefilled; conflict check; `renameRule(old, new)`.
**Clone** (`cloneSelectedRule`): loop `AutoExpandableDialog::getText` "Rule cloning" / "Please type the name for the clone of the download rule." prefilled with source name; conflict check; clears selection then `cloneRule(src, cloneName)`.
**Clear downloaded episodes** (`clearSelectedRuleDownloadedEpisodeList`): confirm "Clear downloaded episodes" / "Are you sure you want to clear the list of downloaded episodes for the selected rule?"; sets `m_currentRule.setPreviouslyMatchedEpisodes({})` then `handleRuleDefinitionChanged()`.

### 7b. Rule definition panel (`ruleScrollArea`, top of `ruleDefSplitter`)
`QScrollArea` (vertical scrollbar always on). Enabled only when exactly one rule is selected; disabled + cleared otherwise. Controls top-to-bottom (`verticalLayout_8`):

1. **Priority** (`priorityLayout`): `priorityLabel` "Priority:" + `prioritySpinBox` (QSpinBox, range INT_MIN..INT_MAX) → `AutoDownloadRule::priority`.
2. **`checkRegex`** (QCheckBox) "Use Regular Expressions" → `useRegex`. Toggling updates field tooltips (regex vs wildcard help) and re-validates the must/mustNot lines.
3. **Match grid** (`gridLayout`), each row = label + QLineEdit + a small (18x18) status QLabel that shows a `dialog-warning`/`task-attention` pixmap + error tooltip when invalid:
   - Row 0: `labelMustContain` "Must Contain:" + `lineContains` (+ `labelMustStat`) → `mustContain`.
   - Row 1: `labelMustNotContain` "Must Not Contain:" + `lineNotContains` (+ `labelMustNotStat`) → `mustNotContain`.
   - Row 2: `lblEFilter` "Episode Filter:" + `lineEFilter` (+ `labelEpFilterStat`/`lblEFilterStat`) → `episodeFilter`.
4. **`checkSmart`** (QCheckBox) "Use Smart Episode Filter" (tooltip: "Smart Episode Filter will check the episode number to prevent downloading of duplicates.\nSupports the formats: S01E01, 1x1, 2017.12.31 and 31.12.2017 (Date formats also support - as a separator)") → `useSmartFilter`.
5. **Ignore period** (`ignorePeriodLayout`): `lblIgnoreDays` "Ignore Subsequent Matches for (0 to Disable)" + `spinIgnorePeriod` (QSpinBox, range 0..365, suffix " days", `specialValueText = "Disabled"`) → `ignoreDays`.
6. **`lblLastMatch`** (right-aligned): "Last Match: %1 days ago" (`dateTime.daysTo(now)`), or "Last Match: Unknown" when no lastMatch.
7. **`torrentParametersGroupBox`** (QGroupBox, flat, title "Torrent parameters"): host layout into which an `AddTorrentParamsWidget` is inserted at runtime — see §8.
8. Vertical spacer.

**Field validation:**
- `updateMustLineValidity` / `updateMustNotLineValidity`: for each token, if regex mode use text as-is, else split on `|` and `Utils::String::wildcardToRegexPattern`. Compile `QRegularExpression` (CaseInsensitive). On invalid: red text (`QLineEdit { color: #ff0000; }`), warning pixmap, tooltip = "Position %1: %2" (regex offset + errorString).
- `updateEpisodeFilterValidity`: valid if empty OR matches `m_episodeRegex` = `^(^\d{1,4}x(\d{1,4}(-(\d{1,4})?)?;){1,}){1,1}` (CaseInsensitive). Invalid → red + warning pixmap.
- Episode Filter tooltip (rich text) documents the format: `1x2;8-15;5;30-;` example; season mandatory non-zero, episode mandatory positive, must end with `;`, single/normal-range/infinite-range.
- Regex/wildcard tooltip (`updateFieldsToolTips`): regex → "Regex mode: use Perl-compatible regular expressions"; wildcard → `?` single char, `*` zero+ chars, whitespace = AND (all words any order), `|` = OR, plus note that an empty `|` clause matches/excludes all articles.

**Edit save flow:** any definition change → `handleRuleDefinitionChanged()` → `updateEditedRule()` (writes UI values into `m_currentRule`) + `updateMatchingArticles()`. Selecting a different rule or closing the dialog calls `saveEditedRule()` → `updateEditedRule()` + `AutoDownloader::setRule(m_currentRule)`. `updateEditedRule` writes: enabled (from item checkstate), priority, useRegex, useSmartFilter, mustContain, mustNotContain, episodeFilter, ignoreDays, and `addTorrentParams` from the embedded widget.

### 7c. Apply Rule to Feeds (`listFeeds`, bottom of `ruleDefSplitter`)
- `lblListFeeds` (QLabel) "Apply Rule to Feeds:" + `listFeeds` (QListWidget).
- Populated (`loadFeedList`) from `Session::instance()->feeds()`: item text = feed name, `Qt::UserRole` = feed URL, flags include `ItemIsUserCheckable | ItemIsAutoTristate`.
- `updateFeedList`: enabled only when ≥1 rule selected; hides all items when disabled. For the current selection, each feed item is Checked (all selected rules include it), PartiallyChecked (some do), or Unchecked (none). Sorted alphabetically. Both `lblListFeeds` and `listFeeds` enabled state track selection.
- `itemChanged` → `handleFeedCheckStateChange`: for each selected rule, add/remove the feed URL from `rule.feedURLs()`; if it's the current rule update `m_currentRule`, else `setRule(rule)` immediately; then `handleRuleDefinitionChanged()` to refresh the preview.

### 7d. Matching RSS Articles preview (Pane 2)
- Bold `matchingArticlesLabel` "Matching RSS Articles" + `matchingArticlesTree` (QTreeWidget, header hidden, single column, sortingEnabled, sorted col 0 ascending).
- `updateMatchingArticles`: clears tree; for each selected rule and each of its feed URLs, resolve `Session::feedByURL(url)`; for each article call `rule.matches(article->data())`; collect matching `article->title()`s; group under a bold top-level feed node (icon `directory`, tooltip = feed name, UserRole = feed URL) via `addFeedArticlesToTree`. De-dupes on `(feedName, articleTitle)`. Auto-expands feed nodes. This is the live "apply rule test" preview — it recomputes whenever the rule definition, feed selection, or ignore-period changes.

### 7e. Import / Export
- **Export** (`onExportBtnClicked`): if no rules → warn "Invalid action" / "The list is empty, there is nothing to export." File dialog "Export RSS rules" with filters `Rules (*.json)` (`m_formatFilterJSON`) and `Rules (legacy) (*.rssrules)` (`m_formatFilterLegacy`); appends `.json`/`.rssrules` as needed; `AutoDownloader::exportRules(format)` → `Utils::IO::saveToFile`; on error "I/O Error" / "Failed to create the destination file. Reason: %1".
- **Import** (`onImportBtnClicked`): file dialog "Import RSS rules" (same filters), max 10 MiB; `AutoDownloader::importRules(data, format)`; catches `RSS::ParsingError` → "Import error" / "Failed to import the selected rules file. Reason: %1". Read failure → "Import error" / "Failed to read the file. %1".
- Extensions: `EXT_JSON = ".json"`, `EXT_LEGACY = ".rssrules"`.

---

## 8. Torrent parameters panel — `AddTorrentParamsWidget` (`addtorrentparamswidget.ui`)

Embedded inside the rule's "Torrent parameters" group box. Binds to a `BitTorrent::AddTorrentParams`. Controls (this is the "assign category / save to different dir / add paused / content layout" surface referenced in the task):

- **`comboTTM`** — "Torrent Management Mode:" combo (Automatic vs Manual TMM). Automatic = properties (e.g. save path) decided by category.
- **`groupBoxSavePath`** "Save at": `defaultsNoteLabel` (italic "Note: the current defaults are displayed for reference."), `savePathEdit` (FileSystemPathLineEdit) = **save to different dir**; `useDownloadPathLabel` "Use another path for incomplete torrents:" + `useDownloadPathComboBox` (Default/Yes/No tri-state) + `downloadPathEdit`.
- **`categoryComboBox`** — "Category:" editable combo (InsertAtTop) = **assign category**.
- **`tagsLineEdit`** (read-only) + `tagsEditButton` "..." — "Tags:" (add/remove via dialog).
- **`miscParamsWidget`** with:
  - `contentLayoutComboBox` — "Content layout:" = **content layout** (Original / Subfolder / NoSubfolder — from `BitTorrent::TorrentContentLayout`).
  - `startTorrentComboBox` — "Start torrent:" = **add paused** equivalent (tri-state Default/Yes/No mapped to `addStopped`).
  - `stopConditionComboBox` — "Stop condition:".
  - `addToQueueTopComboBox` — "Add to top of queue:".
  - `skipCheckingCheckBox` — "Skip hash check".
- **`torrentShareLimitsBox`** "Torrent share limits" containing a `TorrentShareLimitsWidget`.

Combos are tri-state (Default / explicit) so a rule can leave a param unset (`std::optional`). `setAddTorrentParams` / `addTorrentParams()` marshal to/from the rule.

---

## 9. Base RSS engine API (`namespace RSS`)

### `RSS::Session` (singleton, QObject) — `rss_session.h`
Config file format is JSON (folders as objects, feeds as `{uid,url}`). Settings (SettingsStorage keys):
- `RSS/Session/EnableProcessing` (bool) — `isProcessingEnabled()/setProcessingEnabled()`; signal `processingStateChanged(bool)`.
- `RSS/Session/RefreshInterval` (int, default **30** minutes) — `refreshInterval()/setRefreshInterval()`.
- `RSS/Session/FetchDelay` (qint64 seconds, default **2**) — `fetchDelay()/setFetchDelay()`.
- `RSS/Session/MaxArticlesPerFeed` (int, default **50**) — `maxArticlesPerFeed()/setMaxArticlesPerFeed()`; signal `maxArticlesPerFeedChanged(int)`.

Methods: `instance()`, `addFolder(path) -> expected<Folder*,QString>`, `addFeed(url, path, refreshInterval={}) -> expected<Feed*,QString>`, `setFeedURL(path/feed, url) -> expected<void,QString>`, `moveItem(path/item, destPath) -> expected<void,QString>`, `removeItem(path) -> expected<void,QString>`, `items()`, `itemByPath(path)`, `feeds()`, `feedByURL(url)`, `rootFolder()`.
Signals: `itemAdded(Item*)`, `itemPathChanged(Item*)`, `itemAboutToBeRemoved(Item*)`, `feedIconLoaded(Feed*)`, `feedStateChanged(Feed*)`, `feedURLChanged(Feed*, oldURL)`, plus the two above.

### `RSS::Item` (abstract base) — `rss_item.h`
Path-addressed tree node. `PathSeparator` = `\`. Static path helpers: `isValidPath`, `joinPath(a,b)`, `expandPath`, `parentPath`, `relativeName`. Virtuals: `articles()`, `unreadCount()`, `markAsRead()`, `refresh()`, `updateFetchDelay()`, `toJsonValue(withData)`. Accessors `path()`, `name()`. Signals: `pathChanged`, `unreadCountChanged`, `aboutToBeDestroyed`, `newArticle(Article*)`, `articleRead(Article*)`, `articleAboutToBeRemoved(Article*)`.

### `RSS::Folder : Item` — `rss_folder.h`
`items()` returns child items. `articles()`/`unreadCount()` aggregate children; `markAsRead()`/`refresh()` cascade.

### `RSS::Feed : Item` — `rss_feed.h`
`uid()`, `url()`, `title()`, `lastBuildDate()`, `hasError()`, `isLoading()`, `articleByGUID(guid)`, `iconPath() -> Path`, `refreshInterval()/setRefreshInterval()` (`std::chrono::seconds`; 0 = use session default). Signals: `iconLoaded`, `titleChanged`, `stateChanged`, `urlChanged(oldURL)`, `refreshIntervalChanged(old)`. State drives the tree icon (loading/error/favicon).

### `RSS::Article` (QObject) — `rss_article.h`
Immutable-ish value read from feed. Field getters: `feed()`, `guid()`, `date() -> QDateTime`, `title()`, `author()`, `description()`, `torrentUrl()`, `link()`, `isRead()`, `data() -> QVariantHash`. `markAsRead()`; signal `read(Article*)`. Static string keys used in `data()` (and by rule matching):
`KeyId="id"`, `KeyDate="date"`, `KeyTitle="title"`, `KeyAuthor="author"`, `KeyDescription="description"`, `KeyTorrentURL="torrentURL"`, `KeyLink="link"`, `KeyIsRead="isRead"`. Static `articleDateRecentThan(article, date)`.

### `RSS::AutoDownloader` (singleton, ApplicationComponent<QObject>) — `rss_autodownloader.h`
Settings:
- `RSS/AutoDownloader/EnableProcessing` (bool, default **false**) — `isProcessingEnabled()/setProcessingEnabled()`; signal `processingStateChanged(bool)`.
- `RSS/AutoDownloader/SmartEpisodeFilter` (QVariant/QStringList) — `smartEpisodeFilters()/setSmartEpisodeFilters()`. Default filters when unset: `s(\d+)e(\d+)`, `(\d+)x(\d+)`, `(\d{4}[.\-]\d{1,2}[.\-]\d{1,2})`, `(\d{1,2}[.\-]\d{1,2}[.\-]\d{4})`. `smartEpisodeRegex()` returns the compiled combined regex `(?:_|\b)(?:<joined>)(?:_|\b)`.
- `RSS/AutoDownloader/DownloadRepacks` (bool, default **true**) — `downloadRepacks()/setDownloadRepacks()`.

Rule CRUD: `hasRule(name)`, `ruleByName(name) -> AutoDownloadRule`, `rules() -> QList`, `setRule(rule)`, `cloneRule(name, cloneName)`, `renameRule(name, newName)`, `removeRule(name)`. Import/Export: `exportRules(format=JSON) -> QByteArray`, `importRules(data, format=JSON)` (throws `RSS::ParsingError`). `enum class RulesFileFormat { Legacy, JSON }`. Signals: `ruleAdded(name)`, `ruleChanged(name)`, `ruleRenamed(name, oldName)`, `ruleAboutToBeRemoved(name)`. Rules persisted to `rss/download_rules.json`. Processing matches new articles against enabled rules and adds torrents.

### `RSS::AutoDownloadRule` (value type, QSharedDataPointer) — `rss_autodownloadrule.h/.cpp`
Properties (getter/setter): `name`, `isEnabled/setEnabled` (default true), `priority/setPriority` (default 0), `mustContain/setMustContain`, `mustNotContain/setMustNotContain`, `feedURLs/setFeedURLs`, `ignoreDays/setIgnoreDays` (default 0), `lastMatch/setLastMatch (QDateTime)`, `useRegex/setUseRegex` (default false), `useSmartFilter/setUseSmartFilter` (default false), `episodeFilter/setEpisodeFilter`, `previouslyMatchedEpisodes/setPreviouslyMatchedEpisodes`, `addTorrentParams/setAddTorrentParams (BitTorrent::AddTorrentParams)`.

Note: `mustContain`/`mustNotContain` are stored internally as `QStringList` and joined with `|` for the getter. In non-regex mode the setter splits the input on `|` into alternative expressions; in regex mode the whole string is one expression. A single empty token = no condition.

Matching: `matches(articleData) -> bool` and `accepts(articleData) -> bool` (matches + updates lastMatch + appends to previouslyMatchedEpisodes). `matches` checks, in order: ignoreDays window (`articleDate < lastMatch + ignoreDays`), mustContain (any expr matches), mustNotContain (none matches), episodeFilter (`SxEE` range grammar), smart episode filter (dedupe by computed episode name; REPACK/PROPER handling gated on `downloadRepacks()`).

Serialization JSON keys (`toJsonObject`/`fromJsonObject`): `enabled`, `priority`, `useRegex`, `mustContain`, `mustNotContain`, `episodeFilter`, `affectedFeeds` (array), `lastMatch` (RFC2822), `ignoreDays`, `smartFilter`, `previouslyMatchedEpisodes` (array), and nested `torrentParams` (via `BitTorrent::serializeAddTorrentParams`). Deprecated flat keys still written for back-compat: `addPaused`, `torrentContentLayout`, `savePath`, `assignedCategory`. Legacy dict keys (`toLegacyDict`/`fromLegacyDict`): `name`, `must_contain`, `must_not_contain`, `save_path`, `affected_feeds`, `enabled`, `category_assigned`, `use_regex`, `add_paused` (0=default,1=always,2=never), `episode_filter`, `last_match`, `ignore_days`.

---

## 10. Notes for the Material/QML rebuild
- The RSS tab is a 3-pane responsive split (Feeds | Articles | Preview) with a toolbar and a warning banner; persist splitter sizes and expanded folders.
- Feed tree needs two pinned virtual nodes (All, Unread(N)) that always sort above real items and cannot be drag targets/sources; unread counts render inline as `name  (n)`.
- Article read/unread is driven by navigation (leaving an article marks it read) and by explicit actions; color + icon differ by state and must react to theme changes.
- The rules dialog's live "Matching RSS Articles" tree is the rule test — recompute on every rule/feed/ignore-period edit using `AutoDownloadRule::matches(article.data())`.
- Reuse a shared "Add torrent parameters" component (TTM, save path, incomplete path, category, tags, content layout, start/stop condition, queue-top, skip-check, share limits) for the rule's torrent parameters; all combos are tri-state to allow "unset".
- Security: block opening article links that resolve to local files (as the Widgets code does) and only treat `.torrent`/`magnet` anchors as torrent adds.

---

# Area: Auxiliary Dialogs & Menus (Statistics, Execution Log, About, Torrent Creator, and utility dialogs)

# Auxiliary Dialogs & Menus — Implementation Spec

Source: `src/gui/*` (Qt Widgets, `.ui` + `.cpp`). All settings keys below are the literal strings passed to `SettingValue<T>` via each dialog's `#define SETTINGS_KEY(name) u"<Prefix>/" name`. In QML/Material, replace `SettingValue<T>` with an equivalent `Settings`/config store using the exact same keys. All persisted dialog sizes are stored as `QSize`. `UIThemeManager::instance()->getIcon(name, fallback)` supplies themed icons; `getColor(key)` supplies themed colors.

---

## 1. Statistics Dialog (`statsdialog`)
- Window title: **Statistics**. Base size 330×510. Non-modal; a `QScrollArea` (NoFrame, resizable) holds four `QGroupBox` sections in a vertical layout, plus a bottom `QDialogButtonBox` with a single **Close** button. Close button closes the dialog.
- Settings key: `StatisticsDialog/Size`.
- Live update: `connect(BitTorrent::Session::instance(), &Session::statsUpdated, this, &StatsDialog::update)`; `update()` also called once at construction.
- Data sources: `BitTorrent::Session::instance()->status()` → `BitTorrent::SessionStatus`; `->cacheStatus()` → `BitTorrent::CacheStatus`. Formatting helpers: `Utils::Misc::friendlyUnit(bytes)`, `Utils::String::fromDouble(value, 2)`.

Rows (label text → value expression), each row is a grid: left `QLabel` (caption), right `QLabel` (value, right-aligned):

**Group "User statistics"** (`groupUser`):
| Caption | Value binding |
|---|---|
| All-time upload: | `friendlyUnit(status.allTimeUpload)` |
| All-time download: | `friendlyUnit(status.allTimeDownload)` |
| All-time share ratio: | `(atd>0 && atu>0) ? fromDouble(atu/atd, 2) : "-"` |
| Session waste: | `friendlyUnit(status.totalWasted)` |
| Connected peers: | `QString::number(status.peersCount)` |

**Group "Cache statistics"** (`groupCache`):
| Caption | Value binding |
|---|---|
| Read cache hits: | `"%1%".arg(readRatio>0 ? fromDouble(100*cacheStatus.readRatio,2) : "0")` — **hidden entirely when built against libtorrent 2** (`QBT_USES_LIBTORRENT2`); both caption+value hidden |
| Total buffer size: | `friendlyUnit(cacheStatus.totalUsedBuffers * 16 * 1024)` |

**Group "Performance statistics"** (`groupPerf`):
| Caption | Value binding |
|---|---|
| Write cache overload: | `"%1%".arg((diskWriteQueue>0 && peersCount>0) ? fromDouble(100.*diskWriteQueue/peersCount,2) : "0")` |
| Read cache overload: | `"%1%".arg((diskReadQueue>0 && peersCount>0) ? fromDouble(100.*diskReadQueue/peersCount,2) : "0")` |
| Queued I/O jobs: | `QString::number(cacheStatus.jobQueueLength)` |
| Average time in queue: | `tr("%1 ms").arg(cacheStatus.averageJobTime)` |
| Total queued size: | `friendlyUnit(cacheStatus.queuedBytes)` |
| Request latency: | `tr("%1 ms").arg(cacheStatus.requestLatency)` — caption has tooltip "The time it takes from receiving a request from a peer until we're sending the response back on the socket" |

**Group "Tracker statistics"** (`groupTracker`):
| Caption | Value binding |
|---|---|
| Queued tracker announces: | `QString::number(status.queuedTrackerAnnounces)` |

Backend structs (rebuild engine must expose these fields):
- `SessionStatus` (relevant): `qint64 allTimeDownload, allTimeUpload, totalWasted, diskReadQueue, diskWriteQueue, dhtNodes, peersCount, queuedTrackerAnnounces` (full struct also has payload/total up/down rates, ipOverhead, dht, tracker rates & totals, `hasIncomingConnections`).
- `CacheStatus`: `qint64 totalUsedBuffers, jobQueueLength, averageJobTime, queuedBytes, requestLatency; qreal readRatio` (readRatio is libtorrent1-only; TODO removal when LT ≥ 2.0).

Note: the DHT-nodes / connected-peers "performance" items requested map to `status.dhtNodes` and `status.peersCount`; in the current UI `peersCount` is shown under **User statistics → Connected peers**, and `dhtNodes` is available in the struct but not currently displayed. Provide both in the Material rebuild.

---

## 2. Execution Log Widget (`executionlogwidget`)
- A `QWidget` (not a dialog; embedded as a bottom panel/tab in the main window). Root is a `QTabWidget` `tabConsole` with **tabPosition = East** (vertical tabs on the right). No margins.
- Two tabs, each a `QListView` (custom `LogListView`) added into the tab's layout:
  - Tab 0 **General** (`tabGeneral`) → `LogMessageModel` via `LogFilterModel`. Tab icon `help-contents` (fallback `view-calendar-journal`), non-macOS only.
  - Tab 1 **Blocked IPs** (`tabBan`) → `LogPeerModel` (no filter). Tab icon `ip-blocked` (fallback `view-filter`).
- Constructor takes `Log::MsgTypes types` (initial filter mask). `setMessageTypes(types)` updates the general-tab filter live.

**Log message model** (`BaseLogModel`, single column, list model, ring buffer `MAX_VISIBLE_MESSAGES = 20000`, newest inserted at row 0). Roles: `TimeRole=Qt::UserRole, MessageRole, TimeForegroundRole, MessageForegroundRole, TypeRole`. Each row = `time - message`.
- `LogMessageModel`: seeds from `Logger::instance()->getMessages()`, appends on `Logger::newLogMessage(Log::Msg)`. Time formatted `QLocale::system().toString(QDateTime::fromSecsSinceEpoch(ts), ShortFormat)`.
- `LogPeerModel`: seeds from `Logger::instance()->getPeers()`, appends on `Logger::newLogPeer(Log::Peer)`. Message text: blocked → `tr("%1 was blocked. Reason: %2.").arg(ip, reason)`, else `tr("%1 was banned").arg(ip)`.

**Message types & colors** (`Log::MsgType` flags: `ALL=-1, NORMAL=0x1, INFO=0x2, WARNING=0x4, CRITICAL=0x8`). Foreground colors via theme keys:
- Timestamp text → `Log.TimeStamp`
- NORMAL → `Log.Normal` (fallback active WindowText palette color)
- INFO → `Log.Info`
- WARNING → `Log.Warning`
- CRITICAL → `Log.Critical`
- Banned-peer rows (Blocked IPs tab) → `Log.BannedPeer`

**Rendering**: custom delegate paints one line as `time` (in TimeStamp color) + ` - ` separator + `message` (in type color), computing x-offsets from `QFontMetrics`. Selection uses HighlightedText role.

**Interactions**:
- Selection mode: ExtendedSelection. `Ctrl+C` / `QKeySequence::Copy` → `copySelection()` copies selected rows joined by `\n`, each row = `time - message`.
- Right-click context menu (`WA_DeleteOnClose`): **Copy** (icon `edit-copy`, only shown when `currentIndex().isValid()`) → `LogListView::copySelection`; **Clear** (icon `edit-clear`) → `BaseLogModel::reset()` (clears the buffer, begin/endResetModel).

**Filtering**: `LogFilterModel` is a `QSortFilterProxyModel`; `filterAcceptsRow` accepts row if `m_types.testFlag(row TypeRole)`. `setMessageTypes` uses `beginFilterChange/endFilterChange(Rows)` on Qt ≥ 6.10, else `invalidateRowsFilter()`. (The main window drives which of NORMAL/INFO/WARNING/CRITICAL are enabled.)

`Logger` API: `addMessage(msg, type)`, `addPeer(ip, blocked, reason)`, `getMessages(lastKnownId=-1)`, `getPeers(lastKnownId=-1)`; signals `newLogMessage`, `newLogPeer`. Structs: `Log::Msg{int id; MsgType type; qint64 timestamp; QString message}`, `Log::Peer{int id; bool blocked; qint64 timestamp; QString ip, reason}`.

---

## 3. About Dialog (`aboutdialog`)
- Window title: **About qBittorrent**. Base 545×295, resizable; `adjustSize()` if no saved size. Settings key: `AboutDialog/Size`.
- Header row: logo (`getScaledPixmap("qbittorrent-tray", 32)`) + `labelName` = `"<b><h2>qBittorrent <QBT_VERSION> (<N>-bit)</h2></b>"` (N = `QT_POINTER_SIZE*8`).
- Body is a `QTabWidget` `tw_tabs` with 6 tabs:

**Tab "About"** (`aboutTab`): mascot image (`:/icons/mascot.png`) + rich-text label. Text = intro `tr("An advanced BitTorrent client programmed in C++, based on Qt toolkit and libtorrent-rasterbar.")` (C++ made non-breaking), copyright `tr("Copyright %1 2006-2026 The qBittorrent project").arg(C_COPYRIGHT)`, then a link table: **Home Page:** https://www.qbittorrent.org, **Forum:** https://forum.qbittorrent.org, **Bug Tracker:** https://bugs.qbittorrent.org. External links open in browser.

**Tab "Authors"** (`authorTab`): two group boxes.
- **Current maintainer**: Name `Sledgehammer999`, Nationality `Greece`, E-mail `sledgehammer999@qbittorrent.org` (mailto link).
- **Original author**: Name `Christophe Dumez`, Nationality `France`, E-mail `chris@qbittorrent.org` (mailto link).

**Tab "Special Thanks"** (`thanksTab`): `QTextBrowser` loading `:/thanks.html`, openExternalLinks.

**Tab "Translators"** (`translationTab`): `QTextBrowser` loading `:/translators.html`, NoWrap, openExternalLinks.

**Tab "License"** (`licenseTab`): `QTextBrowser` loading `:/gpl.html`, openExternalLinks.

**Tab "Software Used"** (`SoftwareUsedTab`): header row "qBittorrent was built with the following libraries:" + **Copy to clipboard** button (`btnCopyToClipboard`). A grid lists label:value pairs (values right-of a spacer):
- **Qt:** `QT_VERSION_STR`
- **Libtorrent:** `Utils::Misc::libtorrentVersionString()`
- **Boost:** `Utils::Misc::boostVersionString()`
- **OpenSSL:** `Utils::Misc::opensslVersionString()`
- **zlib:** `Utils::Misc::zlibVersionString()`
- When `ENABLE_PLUGINS`: two extra rows appended at runtime — **Lua** (`PluginsEngine::luaVersion()`), **LuaBridge** (`PluginsEngine::luaBridgeVersion()`).
- Below a separator: DB-IP attribution label `tr("The free IP to Country Lite database by DB-IP is used for resolving the countries of peers. The database is licensed under the Creative Commons Attribution 4.0 International License")` + link https://db-ip.com/.
- **Copy to clipboard** builds `"<label> <ver>\n"` for Qt/Libt/Boost/OpenSSL/zlib and sets it on the clipboard.

---

## 4. Torrent Creator Dialog (`torrentcreatordialog`)
- Window title: **Torrent Creator**. Base 592×731, `acceptDrops=true`, resizable, scroll-area body. Settings prefix `TorrentCreator/`.
- Constructed with `(QWidget *parent, const Path &defaultPath)`.

**Section "Select file/folder to share"** (`groupBox`):
- **Path:** `FileSystemPathLineEdit textInputPath` (custom widget `gui/fspathedit.h`), set to `Mode::ReadOnly`.
- A dim "[Drag and drop area]" label; buttons **Select file** (`addFileButton`), **Select folder** (`addFolderButton`).
- **Select file** → `QFileDialog::getOpenFileName(...)`; **Select folder** → `getExistingDirectory(...)`. Non-Windows uses `QFileDialog::DontResolveSymlinks`. Drag-drop: accepts `text/plain`/`text/uri-list`; drop takes the first URL (file → local path, else string).

**Section "Settings"** (`groupBox_2`):
- **Torrent format** (`widgetTorrentFormat`, LT2 only; hidden on LT1): `comboTorrentFormat` items index0 **V2**, index1 **Hybrid**, index2 **V1**. `getTorrentFormat()` maps 0→`TorrentFormat::V2`, 1→`Hybrid`, 2→`V1`. Default stored index **1 (Hybrid)**.
- **Piece size:** `comboPieceSize`. Item 0 = **Auto** (data `0`); then for i=4..17 an item with data `1024<<i` shown via `friendlyUnit(size,false,0)` — i.e. **16 KiB, 32 KiB, 64 KiB, 128 KiB, 256 KiB, 512 KiB, 1 MiB, 2 MiB, 4 MiB, 8 MiB, 16 MiB, 32 MiB, 64 MiB, 128 MiB**. `getPieceSize()` = `currentData().toInt()`.
- **Calculate number of pieces:** button (`buttonCalcTotalPieces`) + result label `labelTotalPieces`. Runs `BitTorrent::TorrentCreator::calculateTotalPieces(path, pieceSize, ignoreDotfiles, [torrentFormat | isAlignmentOptimized, paddedFileSizeLimit])` on a worker `QThread`; label shows "Calculating..." then the count.
- **Ignore dotfiles** checkbox (`checkIgnoreDotfiles`, default checked) — tooltip about filenames starting with `.`.
- **Private torrent (Won't distribute on DHT network)** checkbox (`checkPrivate`).
- **Start seeding immediately** checkbox (`checkStartSeeding`, default checked). Toggling it enables/disables the next checkbox.
- **Ignore share ratio limits for this torrent** checkbox (`checkIgnoreShareLimits`, enabled only when Start seeding is checked).
- **Optimize alignment** (`checkOptimizeAlignment`, a *checkable* `QGroupBox`, LT1 only; hidden on LT2): contains **Align to piece boundary for files larger than:** + spinbox `spinPaddedFileSizeLimit` (suffix " KiB", min −1, max 2147483647, special value at −1 = "Disabled"). `getPaddedFileSizeLimit()` = `value>=0 ? value*1024 : -1`.

**Section "Fields"** (`groupBox_3`, grid label+editor):
- **Tracker URLs:** `QTextEdit trackersList` (plain text, tab-changes-focus) — tooltip "You can separate tracker tiers / groups with an empty line." On create, trackers = trimmed text with runs of 3+ newlines collapsed to a blank-line separator, split on `\n`.
- **Web seed URLs:** `QTextEdit URLSeedsList` — split on `\n`, `SkipEmptyParts`.
- **Comments:** `QTextEdit txtComment`.
- **Source:** `QLineEdit lineEditSource`.

**Footer**: **Progress:** label + `QProgressBar progressBar` (0–100). Button box **Cancel** + **Ok** (Ok relabeled **Create Torrent**, centered).

**Create flow** (`onCreateButtonClicked`): resolve path (Windows canonicalizes shortcuts), check readable → error `tr("Torrent creation failed")`/`tr("Reason: Path to file/folder is not readable.")`. Save dialog `tr("Select where to save the new torrent")`, filter `tr("Torrent Files (*.torrent)")`, default name `<input filename>.torrent` under `TorrentCreator/LastSavePath` (default home). Validate name; append `.torrent` if missing. Disable all inputs, set wait cursor. Build `BitTorrent::TorrentCreatorParams{ ignoreDotfiles, isPrivate, [torrentFormat | isAlignmentOptimized, paddedFileSizeLimit], pieceSize, sourcePath, torrentFilePath, comment, source, trackers, urlSeeds }`, create `BitTorrent::TorrentCreator` (a `QRunnable`), run on a single-thread `QThreadPool`. Signals: `creationSuccess(TorrentCreatorResult)`, `creationFailure(QString)`, `progressUpdated(int)`; dialog `rejected` → `requestInterruption()`.
- **Success**: message `tr("Torrent creator")` / `tr("Torrent created:")\n<path>`. If **Start seeding** checked: `TorrentDescriptor::loadFromFile(result.torrentFilePath)`, then `Session::addTorrent(desc, AddTorrentParams{ addStopped=false, contentLayout=Original, savePath=result.savePath, skipChecking=true, stopCondition=None, useAutoTMM=false, useDownloadPath=false })`; if **Ignore share limits** checked, set `shareLimits{ ratioLimit=NO_RATIO_LIMIT, seedingTimeLimit=NO_SEEDING_TIME_LIMIT, inactiveSeedingTimeLimit=NO_SEEDING_TIME_LIMIT }`. On load failure: critical `tr("Add torrent failed")`.
- **Failure**: info box `tr("Torrent creation failed")` with reason; re-enable inputs.

**Persisted settings** (prefix `TorrentCreator/`): `Size`, `PieceSize` (combo index), `IgnoreDotfiles` (default true), `PrivateTorrent`, `StartSeeding`, `IgnoreRatio`, `TorrentFormat` (LT2, default index 1) / `OptimizeAlignment` (default true) + `PaddedFileSizeLimit` (default −1) (LT1), `LastAddPath`, `TrackerList`, `WebSeedList`, `Comments`, `LastSavePath`, `Source`.

Backend API: `TorrentCreatorParams`/`TorrentCreatorResult{Path torrentFilePath, savePath; int pieceSize}`, enum `TorrentFormat{V1,V2,Hybrid}` (LT2 only), `TorrentCreator::calculateTotalPieces(...)`, `TORRENT_FILE_EXTENSION`.

---

## 5. Speed Limit Dialog (`speedlimitdialog`)
- Window title: **Global Speed Limits**. Base 481×272. Settings key `SpeedLimitDialog/Size`. Buttons **Cancel**/**Ok**.
- Two group boxes, each a grid with an icon + Upload/Download rows; each row is a `QSlider` synced bidirectionally with a `QSpinBox` (suffix " KiB/s", special value `∞` at 0, max 2000000, AdaptiveDecimalStepType).
  - **Speed limits** (`groupBox`): icon `slow_off`. `sliderUploadLimit`/`spinUploadLimit`, `sliderDownloadLimit`/`spinDownloadLimit`.
  - **Alternative speed limits** (`groupBox_2`): icon `slow`. `sliderAltUploadLimit`/`spinAltUploadLimit`, `sliderAltDownloadLimit`/`spinAltDownloadLimit`.
- Values are KiB (bytes/1024). Slider max initialized `max(10000, currentLimit/1024)`; grows if a spinbox exceeds it.
- Read on open: `Session::globalUploadSpeedLimit()`, `globalDownloadSpeedLimit()`, `altGlobalUploadSpeedLimit()`, `altGlobalDownloadSpeedLimit()`.
- On **Ok** (`accept`): for each of the 4 values, only if changed from initial, write `setGlobalUploadSpeedLimit(v*1024)`, `setGlobalDownloadSpeedLimit`, `setAltGlobalUploadSpeedLimit`, `setAltGlobalDownloadSpeedLimit`.

---

## 6. Cookies Dialog (`cookiesdialog` + `cookiesmodel`)
- Window title: **Manage Cookies**. Base 618×369. Window icon `browser-cookies`. Settings keys: `CookiesDialog/Size`, header state `GUI/Qt6/CookiesDialog/ViewState`. Buttons **Cancel**/**Ok**.
- Layout: `QTreeView treeView` (AllEditTriggers, alternatingRowColors, ExtendedSelection) + vertical toolbar with **buttonAdd** (icon `list-add`) and **buttonDelete** (icon `list-remove`), spaced.
- Model `CookiesModel` (`QAbstractItemModel`) over `QList<QNetworkCookie>`, all cells editable. Columns (enum `Column`):
  | # | Enum | Header | Getter/setter |
  |---|---|---|---|
  | 0 | COL_DOMAIN | **Domain** | `cookie.domain()` / `setDomain` |
  | 1 | COL_PATH | **Path** | `cookie.path()` / `setPath` |
  | 2 | COL_NAME | **Name** | `cookie.name()` (Latin1) / `setName` |
  | 3 | COL_VALUE | **Value** | `cookie.value()` (Latin1) / `setValue` |
  | 4 | COL_EXPDATE | **Expiration Date** | `cookie.expirationDate()` (QDateTime) / `setExpirationDate` |
- Data source: `Net::DownloadManager::instance()->allCookies()`; on **Ok** → `setAllCookies(model->cookies())`.
- **Add**: inserts a new row after the current one; new cookie default expiration = now + 2 years; selects it. **Delete**: removes all selected rows (descending order). Selects row 0 on open if any.

---

## 7. Download from URL Dialog (`downloadfromurldialog`)
- Window title: **Download from URLs**. Base 501×220. Settings key `DownloadFromURLDialog/Size`. Buttons **Cancel**/**Ok** (Ok relabeled **Download**, centered).
- Body: bold label **Add torrent links**; `QTextEdit textUrls` (NoWrap, plain text, tab-changes-focus); italic hint "One link per line (HTTP links, Magnet links and info-hashes are supported)".
- On open: auto-paste clipboard lines that are "downloadable" (preserving order): a line is downloadable if `Net::DownloadManager::hasSupportedScheme`, or starts with `magnet:`, or is a 40-char hex (v1 SHA-1) / 32-char base32 SHA-1 / (LT2) 64-char hex (v2 SHA-256) info-hash.
- **Submit** (`onSubmit`, also triggered by `Ctrl+Return`): split textarea on `\n`, trim, drop empties, de-duplicate (order-preserving). If empty → warning `tr("No URL entered")`/`tr("Please type at least one URL.")`. Else `emit urlsReadyToBeDownloaded(QStringList)` and `accept()`.

---

## 8. Tracker Entries Dialog — "Edit trackers" (`trackerentriesdialog`)
- Window title: **Edit trackers**. Base 506×500. Settings key `TrackerEntriesDialog/Size`. Buttons **Cancel**/**Ok**.
- Body: explanatory `QLabel` (one tracker URL per line; blank lines split groups into tiers; top group = tier 0, etc.; note about common subset of selected torrents) + `QPlainTextEdit plainTextEdit` (tab-changes-focus).
- `setTrackers(QList<TrackerEntry>)`: groups entries by `tier` into text blocks, tier 0 first, blank line between tiers.
- `trackers()`: `BitTorrent::parseTrackerEntries(plainText)` → `QList<TrackerEntry>` (`TrackerEntry{QString url; int tier}`).

---

## 9. Trackers Addition Dialog — "Add trackers" (`trackersadditiondialog`)
- Window title: **Add trackers**. Base 367×274. Settings keys `AddTrackersDialog/Size`, `AddTrackersDialog/TrackersListURL`. Buttons **Cancel**/**Ok** (Ok relabeled **Add**). Constructed with a target `BitTorrent::Torrent*`.
- Body: label "List of trackers to add (one per line):"; `QTextEdit textEditTrackersList` (NoWrap, plain text); label "µTorrent compatible list URL:"; row of `QLineEdit lineEditListURL` + **downloadButton** (icon `downloading`/`download`, tooltip "Download trackers list").
- **Download** (`onDownloadButtonClicked`): empty URL → warning `tr("Trackers list URL error")`/`tr("The trackers list URL cannot be empty")`. Else disable button, wait cursor, `Net::DownloadManager::instance()->download(url, Preferences::useProxyForGeneralPurposes(), ...)`. On finish: restore cursor/button; failure → warning `tr("Download trackers list error")`/`tr("Error occurred when downloading the trackers list. Reason: \"%1\"")`; success → append fetched text (trimmed) to the editor.
- **On accept** (`onAccepted`): `entries = parseTrackerEntries(text)`, base tier = `currentTrackers.last().tier + 1` (0 if none), each entry's tier `clampingAdd(entry.tier, baseTier)`, then `torrent->addTrackers(entries)`. Uses `torrent->trackers()` → `QList<TrackerEntryStatus>`.

---

## 10. Deletion Confirmation Dialog (`deletionconfirmationdialog`)
- Window title: **Remove torrent(s)**. Base 463×128. No size persistence. Constructed `(parent, int torrentsCount, QString name, bool defaultDeleteFiles)`. `isRemoveContentSelected()` returns the checkbox state.
- Body: warning icon (`dialog-warning`, largeIconSize) + message label:
  - 1 torrent: `tr("Are you sure you want to remove '%1' from the transfer list?").arg(name)`
  - N torrents: `tr("Are you sure you want to remove these %1 torrents from the transfer list?").arg(N)`
- Row: **rememberBtn** `QToolButton` (icon `object-locked`, tooltip "Remember choice", disabled until state differs from stored pref) + **Also remove the content files** checkbox (`checkRemoveContent`, italic).
- Init checked = `defaultDeleteFiles || Preferences::removeTorrentContent()`.
- Toggling the checkbox: enables rememberBtn iff new state ≠ `Preferences::removeTorrentContent()`; and relabels Ok button **Remove torrent and content** (checked) / **Remove torrent** (unchecked).
- Clicking rememberBtn: `Preferences::setRemoveTorrentContent(checkRemoveContent)`, then disables itself.
- Buttons **Cancel**/**Ok**; **Cancel** has initial focus.

---

## 11. Ban List Options Dialog (`banlistoptionsdialog`)
- Window title: **List of banned IP addresses**. Base 360×450. Settings key `BanListOptionsDialog/Size`. Buttons **Cancel**/**Ok**.
- Body (framed panel): `QTreeView bannedIPList` (header hidden, ExtendedSelection, sortingEnabled ascending col 0, rootIsDecorated=false) over a `QStringListModel` wrapped in a `QSortFilterProxyModel` (dynamic sort). Row of `QLineEdit txtIP` + **Ban IP** button (`buttonBanIP`, disabled until valid) + **Delete** button (`buttonDeleteIP`).
- Data: `Session::instance()->bannedIPs()`.
- **txtIP changed**: enable Ban IP iff `Utils::Net::parseIPRange(ip, true)` has value.
- **Ban IP**: validate `parseIPRange`; invalid → warning `tr("Warning")`/`tr("The entered IP address or range is invalid.")`. Normalize valid single IPs via `QHostAddress::toString()` (RFC5952). Duplicate → warning `tr("The entered IP is already banned.")`. Else append to model, clear field, set modified.
- **Delete**: remove selected rows (descending), set modified.
- **Ok** (`on_buttonBox_accepted`): if modified, collect proxy rows in sorted order → `Session::setBannedIPs(list)` + accept; else reject.

---

## 12. IP Subnet Whitelist Options Dialog (`ipsubnetwhitelistoptionsdialog`)
- Window title: **List of whitelisted IP subnets**. Base 360×450. Settings key `IPSubnetWhitelistOptionsDialog/Size`. Buttons **Cancel**/**Ok**.
- Body (framed panel): `QTreeView whitelistedIPSubnetList` (header hidden, sortingEnabled, rootIsDecorated=false) over `QStringListModel` + `QSortFilterProxyModel`. `QLineEdit txtIPSubnet` (placeholder "Example: 172.17.32.0/24, fdff:ffff:c8::/40"). Buttons **Add subnet** (`buttonWhitelistIPSubnet`, disabled until valid) + **Delete** (`buttonDeleteIPSubnet`).
- Data: `Preferences::instance()->getWebUIAuthSubnetWhitelist()` → list of `Utils::Net::Subnet`, shown via `subnetToString`.
- **txtIPSubnet changed**: enable Add iff `Utils::Net::parseSubnet(str)` has value.
- **Add subnet**: parse; invalid → critical `tr("Error")`/`tr("The entered subnet is invalid.")`. Else append normalized string, clear, modified.
- **Delete**: remove selected rows, modified.
- **Ok**: if modified, collect sorted proxy rows → `Preferences::setWebUIAuthSubnetWhitelist(subnets)` + accept; else reject.

---

## 13. Preview Select Dialog (`previewselectdialog`)
- Window title: **Preview selection**. Base 462×256. Settings keys `PreviewSelectDialog/Size`, header state `GUI/Qt6/PreviewSelectDialog/HeaderState`. Buttons **Cancel**/**Ok** (Ok relabeled **Preview**, centered). Constructed with `const BitTorrent::Torrent*`. Emits `readyToPreviewFile(Path)`.
- Header label: `tr("The following files from torrent \"%1\" support previewing, please select one of them:").arg(torrent->name())`.
- `QTreeView previewList` (sortingEnabled, uniformRowHeights, alternatingRowColors per `Preferences::useAlternatingRowColors()`) over a `QStandardItemModel`. Columns (enum `PreviewColumn`): `NAME` **Name**, `SIZE` **Size**, `PROGRESS` **Progress**, `FILE_INDEX` (hidden). Custom `PreviewListDelegate` renders the Progress column as a progress bar.
- Population: iterate `torrent->filesCount()`; include file `i` iff `Utils::Misc::isPreviewable(torrent->filePath(i))`. Per row set: Name = `filePath.filename()` (+ SortRole same), Size = `friendlyUnit(torrent->fileSize(i))` display with raw bytes as SortRole, Progress = `torrent->filesProgress()[i]` (display+sort), FILE_INDEX = `i`. Sort by Name ascending. Header context menu is custom; first section movable; row 0 selected by default; Name column initially 60% width.
- **Header context menu**: single action **Resize columns** (tooltip "Resize all non-hidden columns to the size of their contents") → resize each non-hidden column to contents.
- **Preview** (double-click or Ok): take selected row's FILE_INDEX; `torrent->flushCache()`; `path = torrent->actualStorageLocation() / torrent->actualFilePath(idx)`. If not `path.exists()` → critical `tr("Preview impossible")`/`tr("Sorry, we can't preview this file: \"%1\".")` (parented to the main window when it's the only file, and reject). Else `emit readyToPreviewFile(path)` + accept.
- `showEvent`: if only ≤1 previewable file, auto-invoke preview (no choice).

---

## 14. Watched Folder Options Dialog (`watchedfolderoptionsdialog`)
- Window title: **Watched Folder Options**. Base 462×392. Settings key `WatchedFolderOptionsDialog/DialogSize`. Buttons **Cancel**/**Ok**. Constructed with `TorrentFilesWatcher::WatchedFolderOptions`.
- Body: **Recursive mode** checkbox (`checkBoxRecursive`, tooltip: watches folder + subfolders; in Manual TMM appends subfolder name to Save path) + group box **Torrent parameters** (`groupBoxParameters`) which hosts an embedded **`AddTorrentParamsWidget`**.
- `watchedFolderOptions()` returns `{ recursive = checkBoxRecursive.isChecked(), addTorrentParams = paramsWidget.addTorrentParams() }`.

**Embedded `AddTorrentParamsWidget`** (fields the Material rebuild must reproduce inside this dialog):
- **Torrent Management Mode:** combo `comboTTM` (Automatic/Manual; tooltip about category-decided properties).
- Group **Save at**: italic note "Note: the current defaults are displayed for reference."; `FileSystemPathLineEdit savePathEdit`; row **Use another path for incomplete torrents:** combo `useDownloadPathComboBox` + `FileSystemPathLineEdit downloadPathEdit`.
- **Category:** editable combo `categoryComboBox` (insert-at-top).
- **Tags:** read-only `tagsLineEdit` (placeholder "Click [...] button to add/remove tags.") + `tagsEditButton` ("...", tooltip "Add/remove tags").
- Misc params: **Content layout:** combo (`contentLayoutComboBox`), **Skip hash check** checkbox (`skipCheckingCheckBox`), **Start torrent:** combo (`startTorrentComboBox`), **Stop condition:** combo (`stopConditionComboBox`), **Add to top of queue:** combo (`addToQueueTopComboBox`).
- Group **Torrent share limits**: embedded `TorrentShareLimitsWidget` (ratio / seeding-time / inactive-seeding-time limits).

---

## 15. Shutdown Confirm Dialog (`shutdownconfirmdialog`)
- Base 410×140. Modal via static `askForConfirmation(parent, ShutdownDialogAction)` → bool (Accepted). Always-on-top, centered on screen. No size persistence.
- Body: warning icon (`QStyle::SP_MessageBoxWarning`, 32px) + `shutdownText` label + **Don't show again** checkbox (`neverShowAgainCheckbox`, visible **only** for the Exit action). Buttons **Cancel**/**Ok**; **Cancel** is default + focused.
- 15-second auto-accept countdown: `QTimer` (1s interval) decrements; text = `<action msg>\nYou can cancel the action within %1 seconds.\n`. Reaching 0 auto-accepts.
- Per `ShutdownDialogAction` enum `{Exit, Shutdown, Suspend, Hibernate, Reboot}` (from `base/types.h`):
  | Action | Window title | Message | Ok button |
  |---|---|---|---|
  | Exit | Exit confirmation | qBittorrent will now exit. | E&xit Now |
  | Shutdown | Shutdown confirmation | The computer is going to shutdown. | &Shutdown Now |
  | Suspend | Suspend confirmation | The computer is going to enter suspend mode. | &Suspend Now |
  | Hibernate | Hibernate confirmation | The computer is going to enter hibernation mode. | &Hibernate Now |
  | Reboot | Reboot confirmation | The computer is going to reboot. | &Reboot Now |
- On **accept**: `Preferences::setDontConfirmAutoExit(neverShowAgainCheckbox.isChecked())`.

---

## 16. Filter Pattern Format Menu (`filterpatternformatmenu`)
- A `QMenu` (submenu), title **Pattern Format**. Constructed `(FilterPatternFormat, parent)`. Emits `patternFormatChanged(FilterPatternFormat)`.
- Three exclusive checkable actions in a `QActionGroup`: **Plain text**, **Wildcards**, **Regular expression** → enum `FilterPatternFormat{PlainText, Wildcards, Regex}`. The passed-in format is pre-checked (default/fallback = Wildcards). Toggling a checked action emits `patternFormatChanged` with the corresponding value.

---

## Cross-cutting engine/API surface used by these screens
- `BitTorrent::Session::instance()`: `status()`, `cacheStatus()`, signal `statsUpdated`; `globalUploadSpeedLimit/globalDownloadSpeedLimit/altGlobalUploadSpeedLimit/altGlobalDownloadSpeedLimit` (+ setters); `bannedIPs()/setBannedIPs()`; `addTorrent(TorrentDescriptor, AddTorrentParams)`.
- `BitTorrent::Torrent`: `name(), trackers() (QList<TrackerEntryStatus>), addTrackers(QList<TrackerEntry>), filesCount(), filePath(i), fileSize(i), filesProgress(), isPreviewable helper, flushCache(), actualStorageLocation(), actualFilePath(i)`.
- `BitTorrent::parseTrackerEntries(QString)`, `TrackerEntry{url,tier}`.
- `Net::DownloadManager::instance()`: `allCookies()/setAllCookies()`, `download(url, useProxy, receiver, slot)`, `hasSupportedScheme()`; `DownloadResult{status,data,errorString}`, `DownloadStatus::Success`.
- `Preferences::instance()`: `removeTorrentContent()/setRemoveTorrentContent()`, `getWebUIAuthSubnetWhitelist()/setWebUIAuthSubnetWhitelist()`, `useProxyForGeneralPurposes()`, `useAlternatingRowColors()`, `setDontConfirmAutoExit()`.
- `Logger::instance()`: messages/peers ring buffers + signals (see §2).
- Theme: `UIThemeManager::getIcon(name, fallback)`, `getScaledPixmap(name, px)`, `getColor(key)`, signal `themeChanged`.
- Formatting: `Utils::Misc::friendlyUnit(bytes[,isSpeed,precision])`, `Utils::String::fromDouble(v,prec)`, version strings (`libtorrentVersionString`, `boostVersionString`, `opensslVersionString`, `zlibVersionString`).

---

# Area: Theme System — Color Scheme, Named UI Colors, Icon Set, Progress Bars & Formatting Utilities

## Theme System — Colors, Icons, Progress Bars & Formatting

Source of truth files: `src/gui/uithememanager.{h,cpp}`, `src/gui/uithemesource.{h,cpp}`, `src/gui/uithemecommon.h`, `src/gui/color.h`, `src/gui/colorscheme.h`, `src/gui/progressbarpainter.{h,cpp}`, `src/gui/transferlistdelegate.cpp`, `src/gui/transferlistmodel.{h,cpp}`, `src/base/utils/misc.{h,cpp}`, `src/base/utils/string.{h,cpp}`, `src/base/unicodestrings.h`, `src/icons/`.

---

### 1. Color-scheme architecture (as built today)

**`UIThemeManager`** (singleton; `initInstance()` / `freeInstance()` / `instance()`) is the single entry point. Public API the rest of the GUI consumes:
- `QColor getColor(const QString &id)` — the only color lookup. Resolves against the current **ColorMode** (`isDarkTheme()` returns true when `QPalette::Active/Base` lightness < 127).
- `QIcon getIcon(iconId, fallback = {})` and private `getIcon(iconId, fallback, ColorMode)`.
- `QIcon getSystrayIcon()`, `QIcon getFlagIcon(countryIsoCode)`, `QPixmap getScaledPixmap(iconId, height)`.
- `ColorScheme colorScheme()` / `setColorScheme(ColorScheme)` (only compiled when `QT_VERSION >= 6.8`, guarded by `QBT_HAS_COLORSCHEME_OPTION`).
- `TrayIconStyle trayIconStyle()` / `setTrayIconStyle(TrayIconStyle)`.
- Signal `themeChanged()` — emitted on color-scheme change; every widget that caches colors/icons reconnects and reloads (e.g. `TransferListModel::loadUIThemeResources`, `ProgressBarPainter::applyUITheme`).

**Enums**
- `enum class ColorMode { Light, Dark }` (`uithemesource.h`) — internal light/dark selector.
- `enum class ColorScheme { System, Light, Dark }` (`colorscheme.h`, `Q_ENUM_NS`) — user-facing preference. Applied by `qApp->styleHints()->setColorScheme(...)` or `unsetColorScheme()` for System.
- `enum class TrayIconStyle { Normal, Monochrome }` (`trayiconstyle.h`).

**Settings keys** (real keys):
- `Appearance/ColorScheme` (default `ColorScheme::System`).
- `Appearance/TrayIconStyle` (default `TrayIconStyle::Normal`).
- `Preferences/General/UseCustomUITheme` (bool, default false).
- `Preferences/General/CustomUIThemePath` (Path).
- `Preferences/Advanced/useSystemIconTheme` (bool, default false; Unix/non-macOS only).
- `GUI/TransferList/UseTorrentStatesColors` (bool, default **true**) — toggles per-state row text coloring.
- `GUI/TransferList/ProgressBarFollowsTextColor` (bool, default false) — progress bar chunk adopts the row's foreground color.

**Theme sources** (strategy pattern, base `UIThemeSource` with `getColor`, `getIconPath`, `readStyleSheet`):
- `DefaultThemeSource` — built-in colors from `defaultUIThemeColors()`; also reads optional user overrides from `<config>/themes/default/config.json`. Icons resolved from Qt resource root `:` under `icons/`, `icons/light/`, `icons/dark/`. Palette is not customizable here.
- `CustomThemeSource` (base for the two below) — reads `config.json` (keys `colors`, `colors.dark`) and a `stylesheet.qss`; falls back to `DefaultThemeSource` for any missing id/icon.
- `QRCThemeSource` — for `.qbtheme` files (registered as a Qt resource under `/uitheme`).
- `FolderThemeSource` — for a folder containing `config.json`; rewrites `:/uitheme` stylesheet references to the folder path.

**Config file constants** (`uithemecommon.h`): `CONFIG_FILE_NAME = "config.json"`, `STYLESHEET_FILE_NAME = "stylesheet.qss"`, `KEY_COLORS = "colors"`, `KEY_COLORS_LIGHT = "colors.light"`, `KEY_COLORS_DARK = "colors.dark"`. JSON color values are parsed via `QColor{string}`; invalid ⇒ warning + skipped.

**QML/Material rebuild recommendation:** Replace the whole palette-override + `.qbtheme`/QSS mechanism with a Material 3 `ColorScheme`. Keep exactly three user options (`System`/`Light`/`Dark`) bound to Qt Quick Controls Material theme + a `Qt.styleHints.colorScheme` follow. Keep the named-color indirection (below) as a QML singleton `Theme` exposing one property per id so the mapping stays data-driven and user-overridable.

---

### 2. Named UI colors — the exact set (`defaultUIThemeColors()` in `uithemecommon.h`)

Each id has a `{light, dark}` pair. `{}` means "invalid/unset" → falls through to the widget's default palette text color. Colors come from `Color::Primer` (`color.h`), Primer Primitives v7.9. Primer hex values:

| Primer function var | Light hex | Dark hex |
|---|---|---|
| accentEmphasis | `#0969da` | `#1f6feb` |
| accentFg | `#0969da` | `#58a6ff` |
| dangerFg | `#cf222e` | `#f85149` |
| doneFg | `#8250df` | `#a371f7` |
| fgMuted | `#57606a` | `#8b949e` |
| fgSubtle | `#6e7781` | `#6e7681` |
| severeFg | `#bc4c00` | `#db6d28` |
| successEmphasis | `#2da44e` | `#238636` |
| successFg | `#1a7f37` | `#3fb950` |
| scaleYellow6 | `#7d4e00` | `#845306` |

**Log group** (execution log line coloring):
| Color id | Meaning | Primer | Light / Dark |
|---|---|---|---|
| `Log.TimeStamp` | timestamp prefix | fgSubtle | `#6e7781` / `#6e7681` |
| `Log.Normal` | normal log text | — (default) | unset |
| `Log.Info` | info messages | accentFg | `#0969da` / `#58a6ff` |
| `Log.Warning` | warnings | severeFg | `#bc4c00` / `#db6d28` |
| `Log.Critical` | critical/errors | dangerFg | `#cf222e` / `#f85149` |
| `Log.BannedPeer` | banned peer log | dangerFg | `#cf222e` / `#f85149` |

**RSS group:** `RSS.ReadArticle` and `RSS.UnreadArticle` — both unset `{}` (styling is via bold/normal font + icons, not color).

**TransferList group — per-torrent-state row TEXT color.** Keyed by `BitTorrent::TorrentState` (see `torrent.h`; enum values: `Unknown=-1, ForcedDownloading, Downloading, ForcedDownloadingMetadata, DownloadingMetadata, StalledDownloading, ForcedUploading, Uploading, StalledUploading, CheckingResumeData, QueuedDownloading, QueuedUploading, CheckingUploading, CheckingDownloading, StoppedDownloading, StoppedUploading, Moving, MissingFiles, Error`). Mapping built in `torrentStateColorsFromUITheme()`:

| Color id (state) | Status string shown | Primer | Light / Dark |
|---|---|---|---|
| `TransferList.Downloading` | "Downloading" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.StalledDownloading` | "Stalled" | successEmphasis | `#2da44e` / `#238636` |
| `TransferList.DownloadingMetadata` | "Downloading metadata" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.ForcedDownloadingMetadata` | "[F] Downloading metadata" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.ForcedDownloading` | "[F] Downloading" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.Uploading` | "Seeding" | accentFg | `#0969da` / `#58a6ff` |
| `TransferList.StalledUploading` | "Seeding" | accentEmphasis | `#0969da` / `#1f6feb` |
| `TransferList.ForcedUploading` | "[F] Seeding" | accentFg | `#0969da` / `#58a6ff` |
| `TransferList.QueuedDownloading` | "Queued" | scaleYellow6 | `#7d4e00` / `#845306` |
| `TransferList.QueuedUploading` | "Queued" | scaleYellow6 | `#7d4e00` / `#845306` |
| `TransferList.CheckingDownloading` | "Checking" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.CheckingUploading` | "Checking" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.CheckingResumeData` | "Checking resume data" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.StoppedDownloading` | "Stopped" | fgMuted | `#57606a` / `#8b949e` |
| `TransferList.StoppedUploading` | "Completed" | doneFg | `#8250df` / `#a371f7` |
| `TransferList.Moving` | "Moving" | successFg | `#1a7f37` / `#3fb950` |
| `TransferList.MissingFiles` | "Missing Files" | dangerFg | `#cf222e` / `#f85149` |
| `TransferList.Error` | "Errored: &lt;msg&gt;" | dangerFg | `#cf222e` / `#f85149` |

Row coloring is applied in `TransferListModel::data()` under `Qt::ForegroundRole` only when `m_useTorrentStatesColors` (pref above) is on. `Unknown` state has no entry → default text color.

**PiecesBar group** (torrent-content pieces bar): `PiecesBar.Border`, `PiecesBar.Piece`, `PiecesBar.PartialPiece`, `PiecesBar.MissingPiece` — all unset `{}` (defaults derive from palette Highlight/Base at paint time).

**ProgressBar:** single id `ProgressBar` — unset `{}` by default; it is the progress-bar **chunk** color (see §4).

**Palette overrides** (`defaultPaletteColors()`, all `{}` in default theme; only settable by custom themes, read from the *light* section for back-compat): `Palette.Window`, `.WindowText`, `.Base`, `.AlternateBase`, `.Text`, `.ToolTipBase`, `.ToolTipText`, `.BrightText`, `.Highlight`, `.HighlightedText`, `.Button`, `.ButtonText`, `.Link`, `.LinkVisited`, `.Light`, `.Midlight`, `.Mid`, `.Dark`, `.Shadow`, plus disabled variants `.WindowTextDisabled`, `.TextDisabled`, `.ToolTipTextDisabled`, `.BrightTextDisabled`, `.HighlightedTextDisabled`, `.ButtonTextDisabled`. In Material these map straight onto the M3 scheme roles and should NOT be surfaced as user color slots.

---

### 3. Material color-role mapping recommendation

Material 3 ships only `primary / secondary / tertiary / error` semantic families. qBittorrent needs **success (green)**, **warning (amber)**, **done/complete (purple)**, **info (blue)** and **muted (grey)** in addition. Recommendation: define **extended (custom) M3 color roles** seeded from the exact Primer hexes above, generating tonal palettes so each has `color / onColor / colorContainer / onColorContainer` in both schemes. Bind the named ids to roles as follows:

| qBt named id(s) | Semantic | Material role (recommended) | Notes |
|---|---|---|---|
| `TransferList.Downloading`, `DownloadingMetadata`, `ForcedDownloading*`, `Checking*`, `Moving` | active/OK green | custom `success` (seed from `#1a7f37`/`#3fb950`) | full-emphasis green |
| `TransferList.StalledDownloading` | download waiting | custom `success` dimmed → `onSuccessContainer` / success @ ~70% | maps `successEmphasis` |
| `TransferList.Uploading`, `ForcedUploading` | seeding | `primary` (M3 blue) | maps `accentFg` |
| `TransferList.StalledUploading` | seeding waiting | `primary` dimmed / `onPrimaryContainer` | maps `accentEmphasis` |
| `TransferList.QueuedDownloading`, `QueuedUploading` | queued | custom `warning` (seed `#7d4e00`/`#845306`) | amber/yellow |
| `TransferList.StoppedDownloading` | stopped/paused | `onSurfaceVariant` (or `outline`) | maps `fgMuted` |
| `TransferList.StoppedUploading` | completed | custom `done` (seed `#8250df`/`#a371f7`) or `tertiary` | purple |
| `TransferList.MissingFiles`, `TransferList.Error` | error | `error` | M3 error family |
| `Log.Info` | info | `primary` | blue |
| `Log.Warning` | warning | custom `warning` / `error` dim | severe orange |
| `Log.Critical`, `Log.BannedPeer` | critical | `error` | red |
| `Log.TimeStamp` | subtle meta | `onSurfaceVariant` | grey |
| `ProgressBar` chunk (unset) | progress fill | `primary` (default) | see §4 |
| `PiecesBar.Piece` (unset) | have-piece | `primary` | |
| `PiecesBar.PartialPiece` (unset) | partial | `primary` @ 50% / `primaryContainer` | |
| `PiecesBar.MissingPiece` (unset) | missing | `surfaceVariant` | |
| `PiecesBar.Border` (unset) | border | `outlineVariant` | |

Keep the `{light,dark}` override capability by letting the QML `Theme` singleton read a JSON with the same `colors` / `colors.dark` structure, so existing user themes remain portable.

---

### 4. Progress-bar painting (`ProgressBarPainter`)

- Constructed with a hidden **dummy `QProgressBar`**; on Windows/macOS it is forced to the **Fusion** style (`QProxyStyle("fusion")`) so the fill renders consistently.
- `void paint(QPainter*, const QStyleOptionViewItem &option, const QString &text, int progress, const QColor &color = {})`:
  - Builds `QStyleOptionProgressBar`: `minimum=0`, `maximum=100`, `progress`, `text`, `textVisible=true`.
  - `rect = option.rect.adjusted(0, 1, 0, -1)`; sets `QStyle::State_Horizontal` (required by Qt6).
  - Color group `Active` if enabled else `Disabled`.
  - Chunk color priority: explicit `color` arg (if valid) → else `m_chunkColor` (= `getColor("ProgressBar")`, may be invalid → style default). Set via `palette.setColor(QPalette::Highlight, ...)`.
  - Draws `PE_PanelItemViewItem` (row background) then `CE_ProgressBar`.
- `applyUITheme()` reloads `m_chunkColor` from `getColor("ProgressBar")`, reconnected on `themeChanged()`.
- **Delegate usage** (`TransferListDelegate::paint`, column `TR_PROGRESS`): progress = `index.data(UnderlyingDataRole).toReal()` (0–100; model returns `torrent->progress()*100`). The cell is drawn **disabled** (greyed) when state ∈ {`Error`, `StoppedDownloading`, `Unknown`}. If `GUI/TransferList/ProgressBarFollowsTextColor` is set, the chunk color = the row's `Qt::ForegroundRole` (state color); else default. Progress display text: `"100%"` when ≥1 else `fromDouble(progress*100, 1) + "%"`.

**QML rebuild:** a Material `ProgressBar` (or a custom delegate `Rectangle` fill) inside the table cell, with `value` 0–1, an overlaid centered `%` label, `enabled:false` styling for the three states above, and an optional binding to switch the fill color to the row's state color when the "follows text color" setting is on.

---

### 5. Transfer-list columns (real enum `TransferListModel::Column`)

Order and header text (from `headerData`): `TR_QUEUE_POSITION`("#"), `TR_NAME`("Name"), `TR_SIZE`("Size"), `TR_TOTAL_SIZE`("Total Size"), `TR_PROGRESS`("Progress"), `TR_STATUS`("Status"), `TR_SEEDS`("Seeds"), `TR_PEERS`("Peers"), `TR_DLSPEED`("Down Speed"), `TR_UPSPEED`("Up Speed"), `TR_ETA`("ETA"), `TR_RATIO`("Ratio"), `TR_POPULARITY`("Popularity"), `TR_CATEGORY`("Category"), `TR_TAGS`("Tags"), `TR_ADD_DATE`("Added On"), `TR_SEED_DATE`("Completed On"), `TR_TRACKER`("Tracker"), `TR_DLLIMIT`("Down Limit"), `TR_UPLIMIT`("Up Limit"), `TR_AMOUNT_DOWNLOADED`("Downloaded"), `TR_AMOUNT_UPLOADED`("Uploaded"), `TR_AMOUNT_DOWNLOADED_SESSION`("Session Downloaded"), `TR_AMOUNT_UPLOADED_SESSION`("Session Uploaded"), `TR_AMOUNT_LEFT`("Remaining"), `TR_TIME_ELAPSED`("Time Active"), `TR_SAVE_PATH`("Save Path"), `TR_COMPLETED`("Completed"), `TR_RATIO_LIMIT`("Ratio Limit"), `TR_SEEN_COMPLETE_DATE`("Last Seen Complete"), `TR_LAST_ACTIVITY`("Last Activity"), `TR_AVAILABILITY`("Availability"), `TR_DOWNLOAD_PATH`("Incomplete Save Path"), `TR_INFOHASH_V1`("Info Hash v1"), `TR_INFOHASH_V2`("Info Hash v2"), `TR_REANNOUNCE`("Reannounce In"), `TR_PRIVATE`("Private"), `TR_CREATE_DATE`("Created On"), `NB_COLUMNS`.

Right-aligned columns: all numeric/time columns (SIZE, TOTAL_SIZE, ETA, SEEDS, PEERS, UP/DL SPEED, UP/DL LIMIT, RATIO, RATIO_LIMIT, POPULARITY, QUEUE_POSITION, LAST_ACTIVITY, AVAILABILITY, REANNOUNCE, all AMOUNT_* + COMPLETED). Editable columns (via `setData`): `TR_NAME`, `TR_CATEGORY`. `TR_NAME` also carries the state **DecorationRole** icon and is used for `sizeHint` height. Custom roles: `UnderlyingDataRole = Qt::UserRole`, `AdditionalUnderlyingDataRole` (the "alt" value, e.g. total vs current seeds).

**State → icon** (`getIconByState`, cached in `loadUIThemeResources`):
| State(s) | icon id (fallback) |
|---|---|
| Downloading, ForcedDownloading, DownloadingMetadata, ForcedDownloadingMetadata | `downloading` |
| StalledDownloading | `stalledDL` |
| StalledUploading | `stalledUP` |
| Uploading, ForcedUploading | `upload` (`uploading`) |
| StoppedDownloading | `stopped` (`media-playback-pause`) |
| StoppedUploading | `checked-completed` (`completed`) |
| QueuedDownloading, QueuedUploading | `queued` |
| Checking* / CheckingResumeData | `force-recheck` (`checking`) |
| Moving | `set-location` |
| Unknown, MissingFiles, Error | `error` |

---

### 6. Formatting utilities

**`Utils::Misc`** (`misc.{h,cpp}`):
- `enum class SizeUnit { Byte, KibiByte, MebiByte, GibiByte, TebiByte, PebiByte, ExbiByte }` (IEC binary, base-1024). Unit strings: `B, KiB, MiB, GiB, TiB, PiB, EiB` (translatable, `misc` context).
- `enum class TimeResolution { Seconds, Minutes }`.
- `QString unitString(SizeUnit, bool isSpeed=false)` — appends `/s` when speed.
- `QString friendlyUnit(qint64 bytes, bool isSpeed=false, int precision=-1)` — divides by 1024 until <1024; value + `QChar::Nbsp` + unit. Default precision from `friendlyUnitPrecision`: Byte→0, KiB/MiB→1, GiB→2, else→3. Negative bytes → "Unknown".
- `QString friendlyUnitCompact(qint64 bytes)` — divides by **1000** threshold, single-letter unit, precision 2/1/0 by magnitude (used for compact status-bar style displays).
- `int friendlyUnitPrecision(SizeUnit)`, `qint64 sizeInBytes(qreal, SizeUnit)`.
- `QString userFriendlyDuration(qlonglong seconds, qlonglong maxCap=-1, TimeResolution=Minutes)` — returns `C_INFINITY` ("∞") when seconds<0 or ≥maxCap; `"0"`; sub-minute → `"< 1m"` (Minutes) or `"%1s"` (Seconds); `"%1m"`; `"%1h %2m"`; `"%1d %2h"`; `"%1y %2d"`.
- `bool isPreviewable(Path)` — audio/video MIME or a fixed multimedia-extension set (.3GP, .AAC, .AVI, .FLAC, .MKV, .MP3, .MP4, .OGG, .WAV, .WMV, … full list in `misc.cpp`).
- `bool isTorrentLink(QString)` — magnet:, `.torrent`, or a supported download scheme.
- `QString parseHtmlLinks(QString)`, `languageToLocalizedString(QStringView)`, plus version strings (`osName`, `boostVersionString`, `libtorrentVersionString`, `opensslVersionString`, `zlibVersionString`).

**`Utils::String`** (`string.{h,cpp}`):
- `QString fromDouble(double n, int precision)` — floors (`std::floor(n*10^p)/10^p`) to avoid QString round-up, then `QLocale::system().toString(..., 'f', precision)`. This is the number formatter behind ratio/availability/progress.
- `parseBool`, `parseInt`, `parseDouble`, `splitCommand`, `wildcardToRegexPattern`, `fromLatin1`, `fromLocal8Bit`, templated `joinIntoString(container, sep)`, `fromEnum<T>` / `toEnum<T>` (via `QMetaEnum`, int underlying required), `unquote`.

**Model-level display formatting** (`TransferListModel::displayValue`, reproduce verbatim in QML):
- Ratio / ratio-limit / popularity: `∞` when value==-1 or ≥ `BitTorrent::Torrent::MAX_RATIO`, else `fromDouble(value, 2)`.
- Availability: `fromDouble(value, 3)` or "N/A" if <0.
- ETA: `userFriendlyDuration(value, MAX_ETA)`.
- Limits: `friendlyUnit(value, true)` or `∞` (`C_INFINITY`) when ≤0.
- Sizes/speeds: `friendlyUnit(...)`.
- Seeds/Peers: `"current (total)"`.
- Queue position: `value+1` or `"*"` when <0.
- Last activity: `"%1 ago"` around `userFriendlyDuration`.
- Time active: `"%1 (seeded for %2)"` when seeding time >0.
- Dates: `QLocale().toString(dt.toLocalTime(), QLocale::ShortFormat)`.
- Private: "Yes"/"No"/"N/A".
- `HideZeroValuesMode { Never, Stopped, Always }` gated by prefs `getHideZeroValues` + `getHideZeroComboValues`.

Unicode constants (`unicodestrings.h`): `C_INFINITY = "∞"`, `C_COPYRIGHT = "©"`, `C_INEQUALITY = "≠"`, plus `C_LOCALE_*` language names.

---

### 7. Icon set (88 named icons + 369 country flags)

Icons are SVG in `src/icons/` (Qt resource root `:`), resolved by id → `icons/<id>.svg` (or `.png`), with per-mode override folders `icons/dark/` (dark) and user `themes/default/icons/{light,dark}/`. `getIcon(id, fallback)` uses `fallback` only for freedesktop/system-icon-theme lookups on Unix. Full id set is `defaultUIThemeIcons()` in `uithemecommon.h`. Country flags: `getFlagIcon(iso)` → `:/icons/flags/<iso>.svg` (cached). Tray: `qbittorrent-tray`, `qbittorrent-tray-mono`, `qbittorrent-tray-light`, `qbittorrent-tray-dark`.

**Icon id → action → Material Symbols recommendation** (grep-verified call sites):

Main toolbar / menu (`mainwindow.cpp`):
| Action | qBt icon (fallback) | Material Symbol |
|---|---|---|
| Add torrent file (`actionOpen`) | `list-add` | `note_add` |
| Add torrent link (`actionDownloadFromURL`) | `insert-link` | `add_link` |
| Global speed limits (`actionSetGlobalSpeedLimits`) | `speedometer` | `speed` |
| Create torrent (`actionCreateTorrent`) | `torrent-creator` (`document-edit`) | `build` |
| About (`actionAbout`) | `help-about` | `info` |
| Statistics (`actionStatistics`) | `view-statistics` | `bar_chart` |
| Queue → top/up/down/bottom | `go-top`/`go-up`/`go-down`/`go-bottom` | `vertical_align_top` / `arrow_upward` / `arrow_downward` / `vertical_align_bottom` |
| Delete (`actionDelete`) | `list-remove` | `delete` |
| Documentation (`actionDocumentation`) | `help-contents` | `menu_book` |
| Donate (`actionDonateMoney`) | `wallet-open` | `volunteer_activism` |
| Exit (`actionExit`) | `application-exit` | `logout` |
| Lock (`actionLock`) | `object-locked` | `lock` |
| Options (`actionOptions`) | `configure` (`preferences-system`) | `settings` |
| Start (`actionStart`/`actionResumeSession`) | `torrent-start` (`media-playback-start`) | `play_arrow` / `play_circle` |
| Stop (`actionStop`) | `torrent-stop` (`media-playback-pause`) | `pause` |
| Pause session (`actionPauseSession`) | `pause-session` | `pause_circle` |
| Auto-shutdown menu | `task-complete` | `power_settings_new` |
| Manage cookies (`actionManageCookies`) | `browser-cookies` | `cookie` |
| Manage plugins (`actionManagePlugins`) | `plugins` | `extension` |
| Log menu (`menuLog`) | `help-contents` | `article` |
| Check for updates (`actionCheckForUpdates`) | `view-refresh` | `system_update` |
| Open destination folder | `directory` | `folder_open` |

Transfer-list context menu (`transferlistwidget.cpp`):
| Item | qBt icon | Material Symbol |
|---|---|---|
| Start / Stop / Force start | `torrent-start` / `torrent-stop` / `torrent-start-forced` | `play_arrow` / `pause` / `bolt` (or `play_arrow`) |
| Remove | `list-remove` | `delete` |
| Preview file | `view-preview` | `preview` |
| Torrent options | `configure` | `tune` |
| Open destination folder | `directory` | `folder_open` |
| Move up/down/top/bottom | `go-up`/`go-down`/`go-top`/`go-bottom` | `arrow_upward` / `arrow_downward` / `vertical_align_top` / `vertical_align_bottom` |
| Set location | `set-location` (`inode-directory`) | `drive_file_move` |
| Force recheck | `force-recheck` (`document-edit-verify`) | `fact_check` |
| Force reannounce | `reannounce` (`document-edit-verify`) | `campaign` |
| Copy → Magnet link | `torrent-magnet` (`kt-magnet`) | `link` |
| Copy → Torrent ID | `help-about` (`edit-copy`) | `content_copy` |
| Copy → Comment | `edit-copy` | `content_copy` |
| Copy → Name | `name` (`edit-copy`) | `content_copy` |
| Copy → Info hash v1/v2 | `hash` (`edit-copy`) | `tag` |
| Copy → Content path | `directory` (`edit-copy`) | `content_copy` |
| Rename / Manage content / Edit trackers | `edit-rename` | `edit` |
| Export .torrent | `edit-copy` | `save_alt` |
| Category submenu | `view-categories` | `category` |
| Category → New / Reset | `list-add` / `edit-clear` | `add` / `clear` |
| Tags submenu | `tags` (`view-categories`) | `sell` |
| Tags → Add / Remove All | `list-add` / `edit-clear` | `add` / `clear` |
| Queue submenu | `queued` | `low_priority` |
| Copy submenu | `edit-copy` | `content_copy` |

Status bar (`statusbar.cpp`): `firewalled` → `gpp_maybe`/`shield`; `connected` → `cloud_done`; `disconnected` → `cloud_off`; `downloading` (DL speed) → `download`; `upload` (UP speed) → `upload`; `slow` / `slow_off` (alt-speed toggle) → `speed` (filled/outlined).

Status filter sidebar (`statusfilterwidget.cpp`): `filter-all` → `apps`; `downloading` → `download`; `upload` (seeding) → `upload`; `checked-completed` → `check_circle`; `torrent-start` (running) → `play_arrow`; `stopped` → `pause`; `filter-active` → `trending_up`; `filter-inactive` → `trending_down`; `filter-stalled` → `hourglass_empty`; `stalledUP`/`stalledDL` → `upload`/`download`; `force-recheck` (checking) → `fact_check`; `set-location` (moving) → `drive_file_move`; `error` → `error`.

Category / tag / tracker filters: `view-categories` → `category`; `tags` → `sell`; `trackers` (`network-server`) → `dns`; `tracker-warning` → `warning`; `tracker-error` → `error`; `trackerless` → `cloud_off`; `directory` → `folder`.

Options dialog tabs (`optionsdialog.cpp`): `preferences-desktop` (Behavior/UI) → `palette`; `preferences-bittorrent` → `swap_vert`; `network-connect` (Connection) → `lan`; `download` (Downloads) → `download`; `speedometer` (Speed) → `speed`; `application-rss` (RSS) → `rss_feed`; `edit-find` (Search) → `search`; `preferences-webui` (WebUI) → `language`; `preferences-advanced` → `settings_suggest`.

Properties tab bar (`proptabbar.cpp`): `help-about` (General) → `description`; `trackers` → `dns`; `peers` → `groups`; `network-server` (HTTP sources) → `public`; `directory` (Content) → `folder`; `chart-line` (Speed graph) → `show_chart`.

RSS (`rsswidget.cpp`, `feedlistwidget.cpp`, `articlelistwidget.cpp`): `application-rss` → `rss_feed`; `rss_read_article` → `mark_email_read`; `rss_unread_article` → `mail`; `mail-inbox` → `inbox`; `folder-new` → `create_new_folder`; `loading` → `progress_activity`; `task-reject` → `block`; `task-complete` (mark read) → `done_all`; `edit-copy`/`edit-rename`/`edit-clear`/`view-refresh`/`application-url` → `content_copy` / `edit` / `clear` / `refresh` / `open_in_new`.

Search (`searchwidget.cpp`, `searchjobwidget.cpp`): `edit-find` → `search`; `plugins` → `extension`; `download` → `download`; `downloading` → `downloading`; `application-url` → `open_in_new`; `name` → `content_copy`; `insert-link` → `content_copy`.

Peers (`peerlistwidget.cpp`): `peers-add` → `person_add`; `peers-remove` → `person_remove`; `edit-copy` → `content_copy`.

Shared dialog/utility icons: `dialog-warning` → `warning`; `object-locked` → `lock`; `list-add` → `add`; `list-remove` → `delete`/`remove`; `edit-clear` → `clear`; `edit-copy` → `content_copy`; `edit-find` → `search`; `edit-rename` → `edit`; `view-refresh` → `refresh`; `folder-documents` → `folder_open`; `folder-remote` → `cloud`; `directory` → `folder`; `set-location` → `drive_file_move`; `firewalled` → `shield`; `fileicon` → `insert_drive_file`; `torrent-magnet` → `link`; `torrent-creator` → `build`; `chart-line` → `show_chart`; `security-high`/`security-low` → `shield` / `gpp_bad`; `network-connect` → `lan`; `ip-blocked` → `block`; `reannounce` → `campaign`; `hash` → `tag`; `ratio` → `balance`; `peers` → `groups`; `tags` → `sell`; `view-preview` → `preview`; `view-statistics` → `bar_chart`; `view-categories` → `category`; `wallet-open` → `account_balance_wallet`; `system-log-out` → `logout`; `pause-session` → `pause_circle`.

**QML rebuild:** ship the Material Symbols variable font, expose an `Icons` QML singleton mapping every legacy id → codepoint, and keep `getFlagIcon` as-is (the 369 flag SVGs are reusable verbatim; there is no Material equivalent). Country flags live under `src/icons/flags/*.svg` and are referenced by lowercase ISO code.

---

### 8. Notes for the QML/Material implementer
- Preserve the three-value `ColorScheme` and the two-value `TrayIconStyle` verbatim (same setting keys) for config compatibility.
- Preserve the named-color id strings so existing `config.json` user themes keep working through a JSON-backed `Theme` singleton (`colors` + `colors.dark`).
- Row text color, progress-bar chunk color, and state icon are three independent channels driven by the same `TorrentState` — keep them decoupled (they are toggled by different prefs: `UseTorrentStatesColors` and `ProgressBarFollowsTextColor`).
- Number/size/duration formatting must be reproduced exactly (floor-not-round in `fromDouble`, `∞` for infinite ratio/limit/eta, Nbsp between value and unit) to keep display parity.


---

# Area: Backend Engine API (BitTorrent Session / Torrent / Preferences contract)

# Backend Engine API Contract (libtorrent-rasterbar layer)

This is the non-visual C++ engine surface the QML/Material GUI must consume. It is the abstraction over libtorrent-rasterbar. The GUI never touches `lt::` types directly — it only uses the `BitTorrent::` interface classes below. Two singleton facades drive everything: `BitTorrent::Session` (torrent engine + all BT/network settings) and `Preferences` (all UI/app settings). All values are `Qt` types (`Path`, `QString`, `qlonglong`, `QDateTime`, `QBitArray`, `TagSet`). To port to QML, wrap `Session`/`Torrent` in `QObject`/`Q_PROPERTY` adapters or expose list models backed by `torrents()`.

All source paths below are absolute-relative to repo root `src/base/`.

---

## 1. Architecture & lifecycle

- **`BitTorrent::Session`** (`bittorrent/session.h`) is a pure-virtual `QObject`; **`SessionImpl`** (`bittorrent/sessionimpl.h`) is the concrete implementation.
  - Static lifecycle: `Session::initInstance()`, `Session::freeInstance()`, `Session::instance()` → returns `Session *`.
- **`BitTorrent::Torrent`** (`bittorrent/torrent.h`) is a pure-virtual `QObject` derived from `TorrentContentHandler`; **`TorrentImpl`** is concrete. Torrents are owned by the Session; the GUI holds raw `Torrent *` pointers whose lifetime is bounded by `torrentAboutToBeRemoved`.
- **`Preferences`** (`preferences.h`) is a singleton `QObject`: `Preferences::initInstance()`, `freeInstance()`, `instance()`. Emits `changed()`; committed via `apply()`.
- **Threading**: the native libtorrent session runs on a dedicated IO thread. `SessionImpl::invoke()` posts to the session thread (`Qt::QueuedConnection`); `invokeAsync()` runs on a `QThreadPool`. Expensive per-torrent reads are async and return `QFuture<T>` (`fetchPeerInfo`, `fetchURLSeeds`, `fetchPieceAvailability`, `fetchDownloadingPieces`, `fetchAvailableFileFractions`). The QML layer must treat these as futures/promises.
- **Update model**: the engine periodically refreshes torrent state and emits `torrentsUpdated(QList<Torrent*>)` (delta of changed torrents) and `statsUpdated()`. `refreshInterval()`/`setRefreshInterval()` controls cadence (ms). The transfer list / properties panes are all driven off these two signals + the granular per-torrent signals below.

---

## 2. Core value types & enums (exact values)

### Identity — `bittorrent/infohash.h`
- `class TorrentID : public Digest32<160>` — 40-hex SHA-1-style id. Statics: `fromString(QString)`, `fromInfoHash(InfoHash)`, `fromSHA1Hash`, `fromSHA256Hash`. `toString()`.
- `class InfoHash` — wraps v1 (`SHA1Hash`) and optionally v2 (`SHA256Hash`, libtorrent2 hybrid). Methods: `isValid()`, `isHybrid()`, `v1()`, `v2()`, `toTorrentID()`, `toString()`.

### `TorrentState` — `bittorrent/torrent.h` (drives status column, colors, filters)
`Unknown = -1`, `ForcedDownloading`, `Downloading`, `ForcedDownloadingMetadata`, `DownloadingMetadata`, `StalledDownloading`, `ForcedUploading`, `Uploading`, `StalledUploading`, `CheckingResumeData`, `QueuedDownloading`, `QueuedUploading`, `CheckingUploading`, `CheckingDownloading`, `StoppedDownloading`, `StoppedUploading`, `Moving`, `MissingFiles`, `Error`.

### `TorrentOperatingMode` — `AutoManaged = 0`, `Forced = 1`. Passed to `Torrent::start(mode)`.

### `Torrent::StopCondition` — `None = 0`, `MetadataReceived = 1`, `FilesChecked = 2`.

### `TorrentContentLayout` — `bittorrent/torrentcontentlayout.h`: `Original`, `Subfolder`, `NoSubfolder`.

### `TorrentContentRemoveOption` — `bittorrent/torrentcontentremoveoption.h`: `Delete`, `MoveToTrash`.

### `TorrentRemoveOption` — `bittorrent/session.h`: `KeepContent`, `RemoveContent` (arg to `removeTorrent`).

### `DownloadPriority` — `bittorrent/downloadpriority.h`: `Ignored = 0`, `Normal = 1`, `High = 6`, `Maximum = 7`, `Mixed = -1`. Helper `isValidDownloadPriority()`.

### Share limits — `bittorrent/sharelimits.h`
- Sentinels: `DEFAULT_RATIO_LIMIT = -2`, `NO_RATIO_LIMIT = -1`, `DEFAULT_SEEDING_TIME_LIMIT = -2`, `NO_SEEDING_TIME_LIMIT = -1`.
- `enum ShareLimitAction`: `Default = -1`, `Stop = 0`, `Remove = 1`, `EnableSuperSeeding = 2`, `RemoveWithContent = 3` (numeric values are persisted — must not change).
- `enum ShareLimitsMode`: `Default = -1`, `MatchAny = 0`, `MatchAll = 1`.
- `struct ShareLimits { qreal ratioLimit; int seedingTimeLimit; int inactiveSeedingTimeLimit; ShareLimitsMode mode; ShareLimitAction action; }` (all default to the Default sentinels).

### Session settings enums — `bittorrent/session.h` (`SessionSettingsEnums`)
- `BTProtocol`: `Both=0`, `TCP=1`, `UTP=2`.
- `ChokingAlgorithm`: `FixedSlots=0`, `RateBased=1`.
- `SeedChokingAlgorithm`: `RoundRobin=0`, `FastestUpload=1`, `AntiLeech=2`.
- `MixedModeAlgorithm`: `TCP=0`, `Proportional=1`.
- `DiskIOReadMode`: `DisableOSCache=0`, `EnableOSCache=1`.
- `DiskIOWriteMode`: `DisableOSCache=0`, `EnableOSCache=1`, `WriteThrough=2` (lt2 only).
- `DiskIOType`: `Default=0`, `MMap=1`, `Posix=2`, `SimplePreadPwrite=3`, `PreadPwrite=4` (lt≥2.1).
- `ResumeDataStorageType`: `Legacy`, `SQLite`.

### `TorrentAnnounceStatus` — `bittorrent/torrentannouncestatus.h` (QFlags)
`TorrentAnnounceStatusFlag`: `HasNoProblem=0`, `HasWarning=1`, `HasTrackerError=2`, `HasOtherError=4`.

### Status structs
- `SessionStatus` (`bittorrent/sessionstatus.h`): `hasIncomingConnections`, `payloadDownloadRate`, `payloadUploadRate`, `uploadRate`, `downloadRate`, `ipOverheadUploadRate`, `ipOverheadDownloadRate`, `dhtUploadRate`, `dhtDownloadRate`, `trackerUploadRate`, `trackerDownloadRate`, `allTimeDownload`, `allTimeUpload`, `totalDownload`, `totalUpload`, `totalPayloadDownload`, `totalPayloadUpload`, `ipOverheadUpload/Download`, `dhtUpload/Download`, `trackerUpload/Download`, `totalWasted`, `diskReadQueue`, `diskWriteQueue`, `dhtNodes`, `peersCount`, `queuedTrackerAnnounces`. (All `qint64`/`bool`.) Feeds the status bar + Speed/Statistics tabs.
- `CacheStatus` (`bittorrent/cachestatus.h`): `totalUsedBuffers`, `jobQueueLength`, `averageJobTime`, `queuedBytes`, `readRatio` (qreal), `requestLatency`.

### `AddTorrentError` — `bittorrent/addtorrenterror.h`: `struct { enum Kind { DuplicateTorrent, Other }; Kind kind; QString message; }` (payload of `addTorrentFailed`).

### `PeerAddress` — `bittorrent/peeraddress.h`: `{ QHostAddress ip; ushort port; }`, `parse(QStringView)`, `toString()`.

### `SSLParameters` — `bittorrent/sslparameters.h`: `{ QSslCertificate certificate; QSslKey privateKey; QByteArray dhParams; }`, `isValid()`.

---

## 3. `Session` API surface — `bittorrent/session.h`

All methods are pure-virtual on `Session`, implemented in `SessionImpl`. Grouped by area. Getters are `const`.

### 3.1 Default paths / TMM
- `Path savePath()` / `setSavePath(Path)`
- `Path downloadPath()` / `setDownloadPath(Path)` (incomplete-files temp dir)
- `bool isDownloadPathEnabled()` / `setDownloadPathEnabled(bool)`
- `bool useCategoryPathsInManualMode()` / `setUseCategoryPathsInManualMode(bool)`
- `Path suggestedSavePath(categoryName, std::optional<bool> useAutoTMM)`, `Path suggestedDownloadPath(...)`
- Auto Torrent Management Mode toggles: `isAutoTMMDisabledByDefault()`/set, `isDisableAutoTMMWhenCategoryChanged()`/set, `isDisableAutoTMMWhenDefaultSavePathChanged()`/set, `isDisableAutoTMMWhenCategorySavePathChanged()`/set.

### 3.2 Categories (static helpers + instance)
- Static: `isValidCategoryName(QString)`, `subcategoryName(QString)`, `parentCategoryName(QString)`, `expandCategory(QString)→QStringList`.
- `QStringList categories()`
- `CategoryOptions categoryOptions(name)` / `bool setCategoryOptions(name, CategoryOptions)`
- `Path categorySavePath(name)` and overload `(name, CategoryOptions)`
- `Path categoryDownloadPath(name)` and overload
- `ShareLimits categoryShareLimits(name)`
- `bool addCategory(name, CategoryOptions = {})`, `bool removeCategory(name)`
- `CategoryOptions` (`bittorrent/categoryoptions.h`): `{ Path savePath; std::optional<DownloadPathOption> downloadPath; ShareLimits shareLimits; }`, plus `fromJSON`/`toJSON`. `DownloadPathOption` (`bittorrent/downloadpathoption.h`): `{ bool enabled; Path path; }`.

### 3.3 Tags
- `TagSet tags()`, `bool hasTag(Tag)`, `bool addTag(Tag)`, `bool removeTag(Tag)`. (`TagSet`/`Tag` from `base/tagset.h`.)

### 3.4 Global share limits (session-wide)
- `const ShareLimits &shareLimits()` / `setShareLimits(ShareLimits)`.

### 3.5 Torrent-add behavior defaults
- `isAddTorrentToQueueTop()`/set, `isAddTorrentStopped()`/set, `isStartPaused()`/set
- `Torrent::StopCondition torrentStopCondition()` / `setTorrentStopCondition(...)`
- `TorrentContentLayout torrentContentLayout()` / set
- `bool isAppendExtensionEnabled()` / set (`.!qB` on incomplete files)
- `bool isUnwantedFolderEnabled()` / set
- `bool isPreallocationEnabled()` / set
- `TorrentContentRemoveOption torrentContentRemoveOption()` / set

### 3.6 Export dirs, refresh, misc
- `Path torrentExportDirectory()` / set, `Path finishedTorrentExportDirectory()` / set
- `int refreshInterval()` / set
- `int saveResumeDataInterval()` / set, `std::chrono::minutes saveStatisticsInterval()` / set
- `int shutdownTimeout()` / set
- `bool isPerformanceWarningEnabled()` / set
- `ResumeDataStorageType resumeDataStorageType()` / set

### 3.7 Network / listen / connection
- `int port()` / `setPort(int)`; `bool isListening()`
- `bool isSSLEnabled()`/set, `int sslPort()`/set
- `QString networkInterface()`/set, `networkInterfaceName()`/set, `networkInterfaceAddress()`/set
- `int encryption()`/set (0=allow,1=force,2=disable convention)
- `int maxActiveCheckingTorrents()`/set
- `BTProtocol btProtocol()`/set
- `int outgoingPortsMin()`/set, `int outgoingPortsMax()`/set
- `int UPnPLeaseDuration()`/set, `int peerDSCP()`/set
- `bool isProxyPeerConnectionsEnabled()`/set
- `bool multiConnectionsPerIpEnabled()`/set
- `bool validateHTTPSTrackerCertificate()`/set, `bool isSSRFMitigationEnabled()`/set, `bool blockPeersOnPrivilegedPorts()`/set
- `bool isIDNSupportEnabled()`/set, `int hostnameCacheTTL()`/set
- `bool isReannounceWhenAddressChangedEnabled()`/set
- `QString lastExternalIPv4Address()`, `QString lastExternalIPv6Address()`

### 3.8 DHT / LSD / PeX / anonymous / queueing
- `isDHTEnabled()`/set, `QString getDHTBootstrapNodes()`/set
- `isLSDEnabled()`/set, `isPeXEnabled()`/set
- `isAnonymousModeEnabled()`/set
- `isQueueingSystemEnabled()`/set; `int maxActiveDownloads()`/set, `maxActiveUploads()`/set, `maxActiveTorrents()`/set
- `ignoreSlowTorrentsForQueueing()`/set, `downloadRateForSlowTorrents()`/set, `uploadRateForSlowTorrents()`/set, `slowTorrentsInactivityTimer()`/set

### 3.9 Speed / bandwidth limits
- `int globalDownloadSpeedLimit()`/set, `globalUploadSpeedLimit()`/set (bytes/s)
- `altGlobalDownloadSpeedLimit()`/set, `altGlobalUploadSpeedLimit()`/set
- `downloadSpeedLimit()`/set, `uploadSpeedLimit()`/set (active limit view)
- `bool isAltGlobalSpeedLimitEnabled()`/set (alt speed toggle)
- `bool isBandwidthSchedulerEnabled()`/set
- `bool isUTPRateLimited()`/set, `MixedModeAlgorithm utpMixedMode()`/set
- `bool ignoreLimitsOnLAN()`/set, `bool includeOverheadInLimits()`/set

### 3.10 Connection counts / choking
- `int maxConnections()`/set, `maxConnectionsPerTorrent()`/set, `maxUploads()`/set, `maxUploadsPerTorrent()`/set
- `int connectionSpeed()`/set
- `ChokingAlgorithm chokingAlgorithm()`/set, `SeedChokingAlgorithm seedChokingAlgorithm()`/set
- `bool isSeedingOutgoingConnectionsEnabled()`/set
- `int peerTurnover()`/set, `peerTurnoverCutoff()`/set, `peerTurnoverInterval()`/set

### 3.11 Trackers (session-level)
- `bool isTrackerEnabled()`/set (embedded tracker), `int announcePort()` handled via preferences too
- `bool isAddTrackersEnabled()`/set, `QString additionalTrackers()`/set
- `bool isAddTrackersFromURLEnabled()`/set, `QString additionalTrackersURL()`/set, `QString additionalTrackersFromURL()` (read-only fetched list)
- `bool announceToAllTrackers()`/set, `bool announceToAllTiers()`/set
- `bool isMergeTrackersEnabled()`/set
- `bool isTrackerFilteringEnabled()`/set
- `int maxConcurrentHTTPAnnounces()`/set, `int stopTrackerTimeout()`/set
- `QString announceIP()`/set, `int announcePort()`/set
- `void reannounceToAllTrackers() const` (global re-announce action)

### 3.12 I2P
- `isI2PEnabled()`/set, `I2PAddress()`/set, `I2PPort()`/set, `I2PMixedMode()`/set, `I2PInboundQuantity()`/set, `I2POutboundQuantity()`/set, `I2PInboundLength()`/set, `I2POutboundLength()`/set.

### 3.13 Disk / performance
- `asyncIOThreads()`/set, `hashingThreads()`/set, `filePoolSize()`/set, `checkingMemUsage()`/set
- `diskCacheSize()`/set, `diskCacheTTL()`/set, `qint64 diskQueueSize()`/set
- `DiskIOType diskIOType()`/set, `DiskIOReadMode diskIOReadMode()`/set, `DiskIOWriteMode diskIOWriteMode()`/set
- `isCoalesceReadWriteEnabled()`/set, `usePieceExtentAffinity()`/set, `isSuggestModeEnabled()`/`setSuggestMode`
- `sendBufferWatermark()`/set, `sendBufferLowWatermark()`/set, `sendBufferWatermarkFactor()`/set
- `socketSendBufferSize()`/set, `socketReceiveBufferSize()`/set, `socketBacklogSize()`/set
- `int requestQueueSize()`/set

### 3.14 IP filtering / bans
- `bool isIPFilteringEnabled()`/set, `Path IPFilterFile()`/set
- `QStringList bannedIPs()`/set, `void banIP(QString)`
- `QStringList excludedFileNames()`/set, `bool isExcludedFileNamesEnabled()`/set
- `void applyFilenameFilter(const PathList &files, QList<DownloadPriority> &priorities)` (mutates priorities in place)

### 3.15 Global run/pause + torrent collection
- `bool isRestored()` (startup restore finished), `bool isPaused()`, `void pause()`, `void resume()`
- `Torrent *getTorrent(TorrentID)`, `Torrent *findTorrent(InfoHash)`
- `QList<Torrent *> torrents()`, `qsizetype torrentsCount()` — **primary list source for the transfer view**
- `const SessionStatus &status()`, `const CacheStatus &cacheStatus()`
- `qint64 freeDiskSpace()`

### 3.16 Add / remove / metadata / queue
- `bool isKnownTorrent(InfoHash)`
- `bool addTorrent(const TorrentDescriptor &, const AddTorrentParams & = {})`
- `bool removeTorrent(TorrentID, TorrentRemoveOption = KeepContent)`
- `bool downloadMetadata(const TorrentDescriptor &)`, `bool cancelDownloadMetadata(TorrentID)`
- Queue moves: `increaseTorrentsQueuePos(QList<TorrentID>)`, `decreaseTorrentsQueuePos(...)`, `topTorrentsQueuePos(...)`, `bottomTorrentsQueuePos(...)`

### 3.17 Session signals (drive the whole UI)
`startupProgressUpdated(int)`, `addTorrentFailed(InfoHash, AddTorrentError)`, `allTorrentsFinished()`, `categoryAdded(QString)`, `categoryRemoved(QString)`, `categoryOptionsChanged(QString)`, `IPFilterParsed(bool error, int ruleCount)`, `metadataDownloaded(TorrentInfo)`, `restored()`, `paused()`, `resumed()`, `speedLimitModeChanged(bool alternative)`, `statsUpdated()`, `subcategoriesSupportChanged()`, `tagAdded(Tag)`, `tagRemoved(Tag)`, `torrentsLoaded(QList<Torrent*>)`, `torrentsUpdated(QList<Torrent*>)`, `freeDiskSpaceChecked(qint64)`.
Per-torrent: `torrentAboutToBeRemoved(Torrent*)`, `torrentAdded(Torrent*)`, `torrentCategoryChanged(Torrent*, oldCategory)`, `torrentFinished(Torrent*)`, `torrentFinishedChecking(Torrent*)`, `torrentMetadataReceived(Torrent*)`, `torrentStopped(Torrent*)`, `torrentStarted(Torrent*)`, `torrentSavePathChanged(Torrent*)`, `torrentSavingModeChanged(Torrent*)`, `torrentTagAdded/Removed(Torrent*, Tag)`, `torrentContentFileRenamed(Torrent*, int index, Path oldFilePath)`, `torrentContentFolderRenamed(...)`, `torrentContentFolderRenamingFailed(...)`, `torrentIOError(Torrent*, QString)`, `trackersAdded(Torrent*, QList<TrackerEntry>)`, `trackersReset(Torrent*, oldStatuses, newEntries)`, `trackersRemoved(Torrent*, QStringList)`, `trackerSuccess/Warning/Error(Torrent*, QString tracker)`, `trackerEntryStatusesUpdated(Torrent*, QHash<QString, TrackerEntryStatus>)`.

---

## 4. `Torrent` API surface — `bittorrent/torrent.h`

Derives from `TorrentContentHandler`. Constants: `static const qreal MAX_RATIO`. Non-virtual helpers: `TorrentID id()`, `bool isRunning()`, `qlonglong remainingSize()`, `toggleSequentialDownload()`, `toggleFirstLastPiecePriority()`.

### 4.1 Identity / metadata getters
`Session *session()`, `InfoHash infoHash()`, `QString name()`, `QDateTime creationDate()`, `QString creator()`, `QString comment()` / `setComment(QString)`, `bool isPrivate()`, `qlonglong totalSize()`, `wantedSize()`, `completedSize()`, `pieceLength()`, `wastedSize()`, `QString currentTracker()`, `TorrentInfo info()`.

### 4.2 Paths / TMM / category / tags
`bool isAutoTMMEnabled()` / `setAutoTMMEnabled(bool)`, `Path savePath()` / set, `Path downloadPath()` / set, `Path rootPath()`, `Path contentPath()` (semantics documented inline in header — root vs content path for single/multi-file torrents), `QString category()`, `bool belongsToCategory(QString)`, `bool setCategory(QString)`. Tags: `TagSet tags()`, `hasTag`, `addTag`, `removeTag`, `clearTags()`.

### 4.3 Progress / pieces
`int piecesCount()`, `int piecesHave()`, `qreal progress()` (0..1), `QBitArray pieces()`, `qreal distributedCopies()` (availability), `int connectionsCount()`, `connectionsLimit()`.

### 4.4 Dates / times
`QDateTime addedTime()`, `completedTime()`, `lastSeenComplete()`, `qlonglong activeTime()`, `finishedTime()`, `timeSinceUpload()`, `timeSinceDownload()`, `timeSinceActivity()`, `qlonglong eta()`, `qlonglong nextAnnounce()`.

### 4.5 Sizes / speeds / ratio (transfer-list columns)
`qlonglong totalDownload()`, `totalUpload()`, `totalPayloadUpload()`, `totalPayloadDownload()`, `int uploadPayloadRate()`, `downloadPayloadRate()`, `qreal realRatio()`, `qreal popularity()`, `int downloadLimit()`, `uploadLimit()`.

### 4.6 Seeds / peers counts
`int seedsCount()`, `peersCount()`, `leechsCount()`, `totalSeedsCount()`, `totalPeersCount()`, `totalLeechersCount()`.

### 4.7 State predicates
`bool isFinished()`, `isStopped()`, `isQueued()`, `isForced()`, `isChecking()`, `isDownloading()`, `isMoving()`, `isUploading()`, `isCompleted()`, `isActive()`, `isInactive()`, `isErrored()`, `isSequentialDownload()`, `hasFirstLastPiecePriority()`, `hasMissingFiles()`, `hasError()`, `superSeeding()`, `isDHTDisabled()`, `isPEXDisabled()`, `isLSDDisabled()`. Aggregate: `TorrentState state()`, `int queuePosition()`, `QString error()`, `TorrentAnnounceStatus announceStatus()`.

### 4.8 Trackers / seeds
`QList<TrackerEntryStatus> trackers()`, `QList<QUrl> urlSeeds()`.

### 4.9 Share limits
`const ShareLimits &shareLimits()` / `setShareLimits(ShareLimits)`, `ShareLimits effectiveShareLimits()` (resolves Default sentinels against global/category).

### 4.10 File paths (see also TorrentContentHandler §5)
`PathList filePaths()`, `PathList actualFilePaths()`.

### 4.11 Actions / setters
`setName(QString)`, `setSequentialDownload(bool)`, `setFirstLastPiecePriority(bool)`, `stop()`, `start(TorrentOperatingMode = AutoManaged)`, `forceReannounce(int index = -1)`, `forceDHTAnnounce()`, `forceRecheck()`, `setUploadLimit(int)`, `setDownloadLimit(int)`, `setSuperSeeding(bool)`, `setDHTDisabled(bool)`, `setPEXDisabled(bool)`, `setLSDDisabled(bool)`, `addTrackers(QList<TrackerEntry>)`, `removeTrackers(QStringList)`, `replaceTrackers(QList<TrackerEntry>)`, `addUrlSeeds(QList<QUrl>)`, `removeUrlSeeds(QList<QUrl>)`, `bool connectPeer(PeerAddress)`, `clearPeers()`, `setMetadata(TorrentInfo)`.
Stop condition: `StopCondition stopCondition()` / `setStopCondition(...)`. SSL: `SSLParameters getSSLParameters()` / `setSSLParameters(...)`.

### 4.12 Export
`QString createMagnetURI()`, `nonstd::expected<QByteArray,QString> exportToBuffer()`, `nonstd::expected<void,QString> exportToFile(Path)`.

### 4.13 Async detail fetchers (return `QFuture`)
`QFuture<QList<PeerInfo>> fetchPeerInfo()` (Peers tab), `QFuture<QList<QUrl>> fetchURLSeeds()`, `QFuture<QList<int>> fetchPieceAvailability()` (per-piece availability), `QFuture<QBitArray> fetchDownloadingPieces()` (pieces currently being downloaded — piece bar). `TorrentImpl` adds `QFuture<QList<qreal>> fetchAvailableFileFractions()`.

### 4.14 TorrentImpl-only additions (`bittorrent/torrentimpl.h`)
Enums: `MoveStorageMode { FailIfExist, KeepExistingFiles, Overwrite }`, `MoveStorageContext { AdjustCurrentLocation, ChangeSavePath, ChangeDownloadPath }`, `MaintenanceJob { None, HandleMetadata }`, `struct FileErrorInfo { lt::error_code error; lt::operation_t operation; }`. Concrete overrides `Path actualStorageLocation()`, `Path filePath(int)`, `Path actualFilePath(int)`, `qlonglong fileSize(int)`, `QList<DownloadPriority> filePriorities()`, `QList<qreal> filesProgress()`, `bool hasMetadata()`, `void renameFile(int, Path)`, `void prioritizeFiles(QList<DownloadPriority>)`, `void flushCache()`.

---

## 5. `TorrentContentHandler` — `bittorrent/torrentcontenthandler.h`

Base `QObject` for the file-tree/content pane (files list, priorities, renaming). Pure-virtual:
`bool hasMetadata()`, `int filesCount()`, `Path filePath(int)`, `qlonglong fileSize(int)`, `Path actualStorageLocation()`, `Path actualFilePath(int fileIndex)`, `QList<DownloadPriority> filePriorities()`, `QList<qreal> filesProgress()`, `QFuture<QList<qreal>> fetchAvailableFileFractions()`, `void renameFile(int index, Path newPath)`, `void prioritizeFiles(QList<DownloadPriority>)`, `void flushCache()`.
Convenience: `renameFile(Path oldPath, Path newPath)`, `renameFolder(Path oldFolderPath, Path newFolderPath)` (calls protected `doRenameFolder`).
Signals: `metadataReceived()`, `fileRenamed(int index, Path oldFilePath)`, `folderRenamed(newFolderPath, oldFolderPath, QHash<int,Path> renamedFiles)`, `folderRenamingFailed(newFolderPath, oldFolderPath, renamedFiles, QList<int> failedFileIndexes)`.

---

## 6. `TorrentInfo` — `bittorrent/torrentinfo.h`

Immutable metadata wrapper over `lt::torrent_info`. Constructed from `lt::torrent_info`. Getters: `isValid()`, `InfoHash infoHash()`, `QString name()`, `bool isPrivate()`, `qlonglong totalSize()`, `int filesCount()`, `int pieceLength()`, `int pieceLength(int index)`, `int piecesCount()`, `Path filePath(int)`, `PathList filePaths()`, `qlonglong fileSize(int)`, `qlonglong fileOffset(int)`, `PathList filesForPiece(int pieceIndex)`, `QList<int> fileIndicesForPiece(int)`, `QList<QByteArray> pieceHashes()`. Piece ranges: `using PieceRange = IndexRange<int>`; `PieceRange filePieces(Path)`, `filePieces(int fileIndex)`. `QByteArray rawData()`, `bool matchesInfoHash(InfoHash)`. Native accessors excluded from GUI reuse.

---

## 7. `TorrentDescriptor` — `bittorrent/torrentdescriptor.h`

The "add source" abstraction (from .torrent file, magnet, or raw data). Static factories return `nonstd::expected<TorrentDescriptor,QString>`: `load(QByteArray)`, `loadFromFile(Path)`, `parse(QString)` (magnet/infohash string). Instance: `saveToFile(Path)`, `saveToBuffer()`. Getters: `InfoHash infoHash()`, `QString name()`, `QDateTime creationDate()`, `QString creator()`, `QString comment()`, `QList<TrackerEntry> trackers()`, `QList<QUrl> urlSeeds()`, `const std::optional<TorrentInfo> &info()`, `void setTorrentInfo(TorrentInfo)`. This is what the Add-Torrent dialog builds and passes to `Session::addTorrent`.

---

## 8. `AddTorrentParams` — `bittorrent/addtorrentparams.h`

Struct passed alongside `TorrentDescriptor` to `addTorrent`. Fields: `QString name`, `QString category`, `TagSet tags`, `Path savePath`, `std::optional<bool> useDownloadPath`, `Path downloadPath`, `bool sequential = false`, `bool firstLastPiecePriority = false`, `bool addForced = false`, `std::optional<bool> addToQueueTop`, `std::optional<bool> addStopped`, `std::optional<Torrent::StopCondition> stopCondition`, `PathList filePaths`, `QList<DownloadPriority> filePriorities`, `bool skipChecking = false`, `std::optional<TorrentContentLayout> contentLayout`, `std::optional<bool> useAutoTMM`, `int uploadLimit = -1`, `int downloadLimit = -1`, `ShareLimits shareLimits`, `SSLParameters sslParameters`. Free functions: `parseAddTorrentParams(QJsonObject)`, `serializeAddTorrentParams(AddTorrentParams)`. The `std::optional` fields mean "use session default when unset" — the Add dialog must preserve tri-state semantics.

---

## 9. `PeerInfo` — `bittorrent/peerinfo.h`

Per-peer row for the Peers tab (built from `lt::peer_info` + a `QBitArray` of all pieces). Source flags: `fromDHT()`, `fromPeX()`, `fromLSD()`. Connection/state: `isInteresting()`, `isChocked()`, `isRemoteInterested()`, `isRemoteChocked()`, `isSupportsExtensions()`, `isLocalConnection()`, `isHandshake()`, `isConnecting()`, `isOnParole()`, `isSeed()`, `optimisticUnchoke()`, `isSnubbed()`, `isUploadOnly()`, `isEndgameMode()`, `isHolepunched()`. Transport: `useI2PSocket()`, `useUTPSocket()`, `useSSLSocket()`, `isRC4Encrypted()`, `isPlaintextEncrypted()`. Display columns: `PeerAddress address()`, `QString I2PAddress()`, `QString client()`, `QString peerIdClient()`, `qreal progress()`, `int payloadUpSpeed()`, `int payloadDownSpeed()`, `qlonglong totalUpload()`, `qlonglong totalDownload()`, `QBitArray pieces()`, `QString connectionType()`, `qreal relevance()`, `QString flags()`, `QString flagsDescription()`, `QString country()`, `int downloadingPieceIndex()`.

---

## 10. Tracker model

- `TrackerEntry` (`bittorrent/trackerentry.h`): `{ QString url; int tier = 0; }`. Free fns: `parseTrackerEntries(QStringView)→QList<TrackerEntry>`, `operator==`, `qHash`.
- `TrackerEntryStatus` (`bittorrent/trackerentrystatus.h`): drives the Trackers tab. Fields: `QString url`, `int tier`, `bool isUpdating`, `TrackerEndpointState state`, `QString message`, `int numPeers/numSeeds/numLeeches/numDownloaded` (default -1), `AnnounceTimePoint nextAnnounceTime`, `minAnnounceTime`, `QHash<std::pair<QString,int>, TrackerEndpointStatus> endpoints`, `void clear()`.
- `TrackerEndpointState` enum: `NotContacted=1`, `Working=2`, `NotWorking=4`, `TrackerError=5`, `Unreachable=6`.
- `TrackerEndpointStatus`: `{ QString name; int btVersion=1; bool isUpdating; TrackerEndpointState state; QString message; int numPeers/numSeeds/numLeeches/numDownloaded; AnnounceTimePoint nextAnnounceTime/minAnnounceTime; }`.

---

## 11. Settings storage primitives — `settingvalue.h`

- `template<class T> SettingValue { SettingValue(QString keyName); T get(defaultValue={}); operator T(); operator=(T) }` — thin wrapper over `SettingsStorage` (rare read/write).
- `template<class T> CachedSettingValue { CachedSettingValue(keyName, defaultValue={}[, proxyFunc]); T get(); operator T(); operator=(T) }` — caches value in memory, only writes through on change. `SessionImpl` stores **every** BT setting as a `CachedSettingValue<T>` member (see `sessionimpl.h` lines 655–786 for the full authoritative list of config keys/types, e.g. `m_globalMaxRatio` (qreal), `m_globalMaxSeedingMinutes` (int), `m_globalMaxInactiveSeedingMinutes` (int), `m_shareLimitAction` (ShareLimitAction), `m_shareLimitsMode` (ShareLimitsMode), plus one member per Session getter/setter above). The new engine must persist the same keys for config compatibility. Underlying store is `SettingsStorage` (INI/QSettings-style key→value).

---

## 12. `Preferences` — `preferences.h` (all UI/app settings; grouped as in source)

Singleton `QObject`; `changed()` signal; `apply()` commits. Auxiliary enums: `Scheduler::Days { EveryDay=0, Weekday=1, Weekend=2, Monday=3 … Sunday=9 }`; `DNS::Service { DynDNS=0, NoIP=1, None=-1 }`.

**General/UI**: `getLocale`/set, `useCustomUITheme`/set, `customUIThemePath`/set, `removeTorrentContent`/set, `confirmOnExit`/set, `speedInTitleBar`/`showSpeedInTitleBar`, `useAlternatingRowColors`/set, `useTorrentStatesColors`/set, `getProgressBarFollowsTextColor`/set, `getHideZeroValues`/set, `getHideZeroComboValues`/set, `isStatusbarDisplayed`/set, `isStatusbarFreeDiskSpaceDisplayed`/set, `isStatusbarExternalIPDisplayed`/set, `isToolbarDisplayed`/set, `isTorrentContentDragEnabled`/set, `isSplashScreenDisabled`/set, `preventFromSuspendWhenDownloading`/set, `preventFromSuspendWhenSeeding`/set, `getStyle`/set, (Win) `WinStartup`/set.

**Downloads**: `getScanDirsLastPath`/set, mail-notification block (`isMailNotificationEnabled`, `getMailNotificationSender/Email/SMTP`, `getMailNotificationSMTPEncryptionType` → `Net::SMTPEncryptionType`, `getMailNotificationSMTPAuth/Username/Password`), `getActionOnDblClOnTorrentDl`/set, `getActionOnDblClOnTorrentFn`/set.

**Connection scheduler**: `getSchedulerStartTime`/set (`QTime`), `getSchedulerEndTime`/set, `getSchedulerDays`/set (`Scheduler::Days`).

**Search**: `isSearchEnabled`/set; Search UI: `searchHistoryLength`/set, `storeOpenedSearchTabs`/set, `storeOpenedSearchTabResults`/set.

**WebUI / HTTP server**: `isWebUIEnabled`/set, `getServerDomains`/set, `getWebUIAddress`/set, `getWebUIPort`/set (`quint16`), `useUPnPForWebUIPort`/set. Auth: `isWebUILocalAuthEnabled`/set, `isWebUIAuthSubnetWhitelistEnabled`/set, `getWebUIAuthSubnetWhitelist`/`setWebUIAuthSubnetWhitelist(QStringList)` (`QList<Utils::Net::Subnet>`), `getWebUIUsername`/set, `getWebUIPassword`/set (`QByteArray`), `getWebUIApiKey`/set, `getWebUIMaxAuthFailCount`/set, `getWebUIBanDuration`/set (`std::chrono::seconds`), `getWebUISessionTimeout`/set. Security: `isWebUIClickjackingProtectionEnabled`/set, `isWebUICSRFProtectionEnabled`/set, `isWebUISecureCookieEnabled`/set, `isWebUIHostHeaderValidationEnabled`/set. HTTPS: `isWebUIHttpsEnabled`/set, `getWebUIHttpsCertificatePath`/set, `getWebUIHttpsKeyPath`/set, `isAltWebUIEnabled`/set, `getWebUIRootFolder`/set. Custom headers: `isWebUICustomHTTPHeadersEnabled`/set, `getWebUICustomHTTPHeaders`/set. Reverse proxy: `isWebUIReverseProxySupportEnabled`/set, `getWebUITrustedReverseProxiesList`/set.

**Dynamic DNS**: `isDynDNSEnabled`/set, `getDynDNSService`/set (`DNS::Service`), `getDynDomainName`/set, `getDynDNSUsername`/set, `getDynDNSPassword`/set.

**Advanced / behavior**: `getUILockPassword`/set (`QByteArray`), `isUILocked`/set; auto-run: `isAutoRunOnTorrentAddedEnabled`/set + program, `isAutoRunOnTorrentFinishedEnabled`/set + program, (Win) `isAutoRunConsoleEnabled`/set. Downloads-complete actions: `shutdownWhenDownloadsComplete`/set, `rebootWhenDownloadsComplete`/set, `suspendWhenDownloadsComplete`/set, `hibernateWhenDownloadsComplete`/set, `shutdownqBTWhenDownloadsComplete`/set, `dontConfirmAutoExit`/set. `recheckTorrentsOnCompletion`/set, `resolvePeerCountries`/set, `resolvePeerHostNames`/set, (Unix non-mac) `useSystemIcons`/set, `isRecursiveDownloadEnabled`/set, `getTrackerPort`/set, `isTrackerPortForwardingEnabled`/set, `isMarkOfTheWebEnabled`/set, `isIgnoreSSLErrors`/set, `getPythonExecutablePath`/set, (Win/mac) `isUpdateCheckEnabled`/set, (mac) `isSpeedInDockEnabled`/set + `isMacOSMenuBarIconEnabled`/set. Confirmation toggles: `confirmTorrentDeletion`/set, `confirmTorrentRecheck`/set, `confirmRemoveAllTags`/set, `confirmMergeTrackers`/set, `confirmRemoveTrackerFromAllTorrents`/set. System tray (non-mac): `systemTrayEnabled`/set, `minimizeToTrayNotified`/set, `minimizeToTray`/set, `closeToTray`/set, `closeToTrayNotified`/set, `iconsInMenusEnabled`/set. Parse limits: `getTorrentFileSizeLimit`/set (`qint64`), `getBdecodeDepthLimit`/set, `getBdecodeTokenLimit`/set.

**Persisted UI state (not in Options GUI)**: `getDNSLastUpd`/set, `getDNSLastIP`/set, `getMainGeometry`/set, `isFiltersSidebarVisible`/set, `getFiltersSidebarWidth`/set, `getMainLastDir`/set, `getPeerListState`/set, `getPropSplitterSizes`/set, `getPropFileListState`/set, `getPropCurTab`/set, `getPropVisible`/set, `getTrackerListState`/set, RSS state (`getRssOpenFolders`/set, `getRssFeedListState`/set, `getRssSideSplitterState`/set, `getRssMainSplitterState`/set), `getSearchTabHeaderState`/set, `getRegexAsFilteringPatternForSearchJob`/set, `getSearchEngDisabled`/set, `getTorImportLastContentDir`/set, `getTorImportGeometry`/set. Sidebar filter visibility (read-only getters + public slots to set): `getStatusFilterState`/`setStatusFilterState`, `getCategoryFilterState`/`setCategoryFilterState`, `getTagFilterState`/`setTagFilterState`, `getTrackerFilterState`/`setTrackerFilterState`, `getTrackerStatusFilterState`/`setTrackerStatusFilterState`, `useSeparateTrackerStatusFilter`/set, `getTransSelFilter`/set, `getHideZeroStatusFilters`/set, `getTransHeaderState`/set, `getRegexAsFilteringPatternForTransferList`/set, `getToolbarTextPosition`/set. `isRSSWidgetEnabled`/`setRSSWidgetVisible`.

**Network**: `getNetworkCookies`/set (`QList<QNetworkCookie>`), `useProxyForBT`/set, `useProxyForRSS`/set, `useProxyForGeneralPurposes`/set.

**SpeedWidget**: `isSpeedWidgetEnabled`/set, `getSpeedWidgetPeriod`/set, `getSpeedWidgetGraphEnable(int id)`/`setSpeedWidgetGraphEnable(int id,bool)`.

**AddNewTorrentDialog**: `isAddNewTorrentDialogEnabled`/set, `isAddNewTorrentDialogTopLevel`/set, `addNewTorrentDialogSavePathHistoryLength`/set, `isAddNewTorrentDialogAttached`/set.

Public slots: the five `set*FilterState(bool)` above + `apply()`.

---

## 13. `TorrentFileGuard` — `torrentfileguard.h`

Deferred-delete helper for source .torrent files after add. `FileGuard(Path)` deletes on destruction unless `setAutoRemove(false)`. `TorrentFileGuard(Path)` reads the auto-delete preference; `markAsAddedToSession()` records success. `enum AutoDeleteMode : int { Never, IfAdded, Always }` (names are persisted — do not rename). Statics `AutoDeleteMode autoDeleteMode()` / `setAutoDeleteMode(mode)`. The Add-Torrent flow must call this so the "Delete .torrent after adding" option works.

---

## 14. Reimplementation notes for the new C++ engine layer

- Keep this exact interface (class + method names) so the QML view-models bind to a stable contract; back it with libtorrent-rasterbar.
- Preserve persisted enum numeric values (`ShareLimitAction`, `ShareLimitsMode`) and enum names (`TorrentFileGuard::AutoDeleteMode`) and all `CachedSettingValue` keys for config-file compatibility.
- `nonstd::expected<T,QString>` (from `base/3rdparty/expected.hpp`) is used for fallible ops (descriptor load, export) — map to a QML-friendly result type.
- `QFuture`-returning detail fetchers must remain async; wire them to QML via `QFutureWatcher` or a promise property.
- The GUI update loop hinges on `Session::torrents()` + `torrentsUpdated`/`statsUpdated` and the granular per-torrent signals; a QML `QAbstractListModel` should subscribe to these rather than polling.
