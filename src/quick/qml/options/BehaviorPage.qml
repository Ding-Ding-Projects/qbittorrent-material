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
    \qmltype BehaviorPage
    \brief Options → Behavior page (legacy TAB_UI).

    Rebuilds the Interface, Transfer List, double-click actions, Torrent Content
    View, Status Bar, Desktop / system-tray, Power Management and Log Files groups.
    Hosts staged language and per-language funny-level controls, applying them
    atomically through \c I18n when OptionsController commits. The color-scheme
    selector remains bound to \c ThemeManager; other controls stage normally.
*/
Flickable {
    id: root

    // Reactive read cursor — every OptionsController.value() binding depends on
    // this so pages refresh when the controller (re)loads.
    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    // ---- Inline, key-bound helper controls ------------------------------------
    component OptCheck: CheckBox {
        property string settingKey: ""
        property bool defaultValue: false
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "Behavior: " + settingKey + " -> " + checked)
        }
    }

    Component.onCompleted: Log.debug("ui", "BehaviorPage ready")

    Connections {
        target: OptionsController
        function onLanguageSettingsChangeRequested(mode, englishLevel, cantoneseLevel) {
            I18n.setLanguageSettings(mode, englishLevel, cantoneseLevel)
        }
    }

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        // ==== Interface ========================================================
        MaterialCard {
            title: qsTr("Interface")
            titleIcon: Icons.palette
            Layout.fillWidth: true

            Label {
                text: qsTr("Some interface changes require an application restart to take full effect.")
                font: Typography.labelSmall
                color: Theme.color("warning")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            LabeledField {
                label: qsTr("Language:")
                labelWidth: 180
                Layout.fillWidth: true
                ComboBox {
                    id: languageBox
                    Layout.fillWidth: true
                    Accessible.name: qsTr("Language")
                    model: [ I18n.displayName(0), I18n.displayName(1), I18n.displayName(2) ]
                    currentIndex: (root.rev, OptionsController.value("language", I18n.language))
                    onActivated: (i) => {
                        Log.info("i18n", "User staged language index " + i)
                        OptionsController.setValue("language", i)
                    }
                }
            }

            LabeledField {
                label: qsTr("English funny level:")
                labelWidth: 180
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm
                    Slider {
                        id: englishFunnySlider
                        Layout.fillWidth: true
                        from: 1
                        to: 5
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: (root.rev, OptionsController.value("englishFunnyLevel", 1))
                        Accessible.name: qsTr("English funny level")
                        Accessible.description: qsTr("1 is fully professional and 5 is maximum playfulness")
                        onMoved: OptionsController.setValue("englishFunnyLevel", Math.round(value))
                    }
                    Label {
                        text: Math.round(englishFunnySlider.value) + " / 5"
                        font: Typography.labelMedium
                        Layout.minimumWidth: 42
                        horizontalAlignment: Text.AlignRight
                        Accessible.name: qsTr("English funny level %1 of 5").arg(Math.round(englishFunnySlider.value))
                    }
                }
            }

            LabeledField {
                label: qsTr("Cantonese funny level:")
                labelWidth: 180
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm
                    Slider {
                        id: cantoneseFunnySlider
                        Layout.fillWidth: true
                        from: 1
                        to: 5
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: (root.rev, OptionsController.value("cantoneseFunnyLevel", 3))
                        Accessible.name: qsTr("Cantonese funny level")
                        Accessible.description: qsTr("1 is fully professional and 5 is maximum playfulness")
                        onMoved: OptionsController.setValue("cantoneseFunnyLevel", Math.round(value))
                    }
                    Label {
                        text: Math.round(cantoneseFunnySlider.value) + " / 5"
                        font: Typography.labelMedium
                        Layout.minimumWidth: 42
                        horizontalAlignment: Text.AlignRight
                        Accessible.name: qsTr("Cantonese funny level %1 of 5").arg(Math.round(cantoneseFunnySlider.value))
                    }
                }
            }

            Label {
                text: qsTr("Funny levels style every message, including errors and warnings. They never change the facts, and you can reset them at any time.")
                font: Typography.labelSmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Accessible.name: text
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Reset funny levels")
                    flat: true
                    Accessible.name: text
                    onClicked: {
                        OptionsController.setValue("englishFunnyLevel", 1)
                        OptionsController.setValue("cantoneseFunnyLevel", 3)
                    }
                }
            }

            LabeledField {
                label: qsTr("Color scheme:")
                labelWidth: 180
                Layout.fillWidth: true
                ComboBox {
                    id: colorSchemeBox
                    Layout.fillWidth: true
                    // Item order maps directly to ThemeManager.ColorScheme.
                    model: [ qsTr("System"), qsTr("Light"), qsTr("Dark") ]
                    currentIndex: ThemeManager.colorScheme
                    onActivated: (i) => {
                        Log.info("theme", "User changed color scheme to " + i)
                        ThemeManager.colorScheme = i
                    }
                }
            }

            CheckableGroupBox {
                title: qsTr("Use custom UI Theme")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/General/UseCustomUITheme", false))
                onToggled: (v) => OptionsController.setValue("Preferences/General/UseCustomUITheme", v)

                LabeledField {
                    label: qsTr("UI Theme file:")
                    orientation: Qt.Vertical
                    Layout.fillWidth: true
                    PathField {
                        Layout.fillWidth: true
                        pickFolder: false
                        title: qsTr("Select qBittorrent UI Theme file")
                        placeholder: qsTr("Path to a .qbtheme or config.json file")
                        path: (root.rev, OptionsController.value("Preferences/General/CustomUIThemePath", ""))
                        onPathChanged: OptionsController.setValue("Preferences/General/CustomUIThemePath", path)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                Button {
                    text: qsTr("Customize UI Theme...")
                    // Legacy: enabled only when the custom-theme groupbox is OFF.
                    enabled: !(root.rev, OptionsController.value("Preferences/General/UseCustomUITheme", false))
                    onClicked: {
                        Log.info("ui", "Behavior: opening UIThemeDialog")
                        uiThemeDialog.open()
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // ==== Transfer List ====================================================
        MaterialCard {
            title: qsTr("Transfer List")
            Layout.fillWidth: true

            OptCheck {
                text: qsTr("Confirm when deleting torrents")
                settingKey: "Preferences/Advanced/confirmTorrentDeletion"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Use alternating row colors")
                settingKey: "Preferences/General/AlternatingRowColors"
                defaultValue: true
            }
            OptCheck {
                id: statesColors
                text: qsTr("Use different text colors by torrent states")
                settingKey: "GUI/TransferList/UseTorrentStatesColors"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Make progress bars follow text colors")
                settingKey: "GUI/TransferList/ProgressBarFollowsTextColor"
                defaultValue: false
                enabled: statesColors.checked
                leftPadding: Spacing.lg + indicator.width
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: hideZero
                    text: qsTr("Hide zero and infinity values")
                    settingKey: "Preferences/General/HideZeroValues"
                    defaultValue: false
                }
                ComboBox {
                    enabled: hideZero.checked
                    model: [ qsTr("Always"), qsTr("Stopped torrents only") ]
                    currentIndex: (root.rev, OptionsController.value("Preferences/General/HideZeroComboValues", 0))
                    onActivated: (i) => OptionsController.setValue("Preferences/General/HideZeroComboValues", i)
                }
            }

            OptCheck {
                text: qsTr("Auto hide zero status filters")
                settingKey: "TransferListFilters/HideZeroStatusFilters"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Use separate \"Tracker status\" filter")
                settingKey: "TransferListFilters/SeparateTrackerStatusFilter"
                defaultValue: false
            }
        }

        // ==== Action on double-click ==========================================
        MaterialCard {
            id: dblCard
            title: qsTr("Action on double-click")
            Layout.fillWidth: true

            // Combo item order → DoubleClickAction enum data (0,1,2,4,3).
            readonly property var dblClickValues: [0, 1, 2, 4, 3]
            readonly property var dblClickItems: [
                qsTr("Start / stop torrent"),
                qsTr("Open destination folder"),
                qsTr("Preview file, otherwise open destination folder"),
                qsTr("Open torrent options dialog"),
                qsTr("No action")
            ]
            function indexForValue(v) { return Math.max(0, dblClickValues.indexOf(v)) }

            LabeledField {
                label: qsTr("Downloading torrents:")
                labelWidth: 180
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: dblCard.dblClickItems
                    currentIndex: dblCard.indexForValue(
                                      (root.rev, OptionsController.value("Preferences/Downloads/DblClOnTorDl", 0)))
                    onActivated: (i) => OptionsController.setValue(
                                     "Preferences/Downloads/DblClOnTorDl", dblCard.dblClickValues[i])
                }
            }
            LabeledField {
                label: qsTr("Completed torrents:")
                labelWidth: 180
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: dblCard.dblClickItems
                    currentIndex: dblCard.indexForValue(
                                      (root.rev, OptionsController.value("Preferences/Downloads/DblClOnTorFn", 1)))
                    onActivated: (i) => OptionsController.setValue(
                                     "Preferences/Downloads/DblClOnTorFn", dblCard.dblClickValues[i])
                }
            }
        }

        // ==== Torrent Content View ============================================
        MaterialCard {
            title: qsTr("Torrent Content View")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Drag content from qBittorrent")
                settingKey: "Preferences/General/TorrentContentDragEnabled"
                defaultValue: false
            }
        }

        // ==== Status Bar ======================================================
        MaterialCard {
            title: qsTr("Status Bar")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Show free disk space")
                settingKey: "Preferences/General/StatusbarFreeDiskSpaceDisplayed"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Show external IP")
                settingKey: "Preferences/General/StatusbarExternalIPDisplayed"
                defaultValue: false
            }
        }

        // ==== Desktop / system tray ===========================================
        MaterialCard {
            title: qsTr("Desktop")
            Layout.fillWidth: true

            OptCheck {
                text: qsTr("Show splash screen on start up")
                // Stored inverted (NoSplashScreen); OptionsController exposes the
                // human-facing "show splash" key so QML stays simple.
                settingKey: "GUI/ShowSplashScreen"
                defaultValue: false
            }

            LabeledField {
                label: qsTr("Window state on start up:")
                labelWidth: 200
                Layout.fillWidth: true
                ComboBox {
                    Layout.fillWidth: true
                    model: [ qsTr("Normal"), qsTr("Minimized"), qsTr("Hidden") ]
                    currentIndex: (root.rev, OptionsController.value("GUI/StartUpWindowState", 0))
                    onActivated: (i) => OptionsController.setValue("GUI/StartUpWindowState", i)
                }
            }

            OptCheck {
                text: qsTr("Confirmation on exit when torrents are active")
                settingKey: "Preferences/General/ExitConfirm"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Confirmation on auto-exit when downloads finish")
                settingKey: "GUI/ConfirmAutoExit"
                defaultValue: true
            }
            OptCheck {
                text: qsTr("Check for program updates")
                settingKey: "Preferences/Advanced/updateCheck"
                defaultValue: true
            }

            ColumnLayout {
                visible: OptionsController.windowsDefaultAppsAvailable
                Layout.fillWidth: true
                spacing: Spacing.sm

                Label {
                    Layout.fillWidth: true
                    text: qsTr("File association")
                    font: Typography.titleSmall
                    color: Theme.color("onSurface")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("To set qBittorrent as the default program for .torrent files and Magnet links, open Windows Default Apps settings and add them manually.")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                    wrapMode: Text.WordWrap
                }
                Button {
                    text: qsTr("Open Windows Default Apps settings page")
                    Accessible.name: text
                    Accessible.description: qsTr("Opens Windows Settings to choose default applications for file and link types")
                    onClicked: {
                        Log.info("ui", "Behavior: opening Windows Default Apps settings")
                        OptionsController.openWindowsDefaultApps()
                    }
                }
            }

            CheckableGroupBox {
                title: qsTr("Show qBittorrent in notification area")
                Layout.fillWidth: true
                checked: (root.rev, OptionsController.value("Preferences/General/SystrayEnabled", true))
                onToggled: (v) => OptionsController.setValue("Preferences/General/SystrayEnabled", v)

                OptCheck {
                    text: qsTr("Minimize qBittorrent to notification area")
                    settingKey: "Preferences/General/MinimizeToTray"
                    defaultValue: false
                }
                OptCheck {
                    text: qsTr("Close qBittorrent to notification area")
                    settingKey: "Preferences/General/CloseToTray"
                    defaultValue: true
                }
                LabeledField {
                    label: qsTr("Tray icon style:")
                    labelWidth: 160
                    Layout.fillWidth: true
                    ComboBox {
                        Layout.fillWidth: true
                        model: [ qsTr("Normal"), qsTr("Monochrome") ]
                        // Keep this choice inside the Options transaction.  The
                        // active ThemeManager value changes only after Apply.
                        currentIndex: (root.rev, OptionsController.value(
                                               "trayIconStyle", ThemeManager.Normal))
                        onActivated: (i) => {
                            Log.info("theme", "Staged tray icon style -> " + i)
                            OptionsController.setValue("trayIconStyle", i)
                        }
                    }
                }
            }
        }

        // ==== Power Management ================================================
        MaterialCard {
            title: qsTr("Power Management")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Inhibit system sleep when torrents are downloading")
                settingKey: "Preferences/General/PreventFromSuspendWhenDownloading"
                defaultValue: false
            }
            OptCheck {
                text: qsTr("Inhibit system sleep when torrents are seeding")
                settingKey: "Preferences/General/PreventFromSuspendWhenSeeding"
                defaultValue: false
            }
        }

        // ==== Log Files =======================================================
        CheckableGroupBox {
            title: qsTr("Log Files")
            Layout.fillWidth: true
            checked: (root.rev, OptionsController.value("Application/FileLogger/Enabled", true))
            onToggled: (v) => OptionsController.setValue("Application/FileLogger/Enabled", v)

            LabeledField {
                label: qsTr("Save path:")
                orientation: Qt.Vertical
                Layout.fillWidth: true
                PathField {
                    Layout.fillWidth: true
                    title: qsTr("Choose a save directory")
                    path: (root.rev, OptionsController.value("Application/FileLogger/Path", ""))
                    onPathChanged: OptionsController.setValue("Application/FileLogger/Path", path)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: logBackup
                    text: qsTr("Backup the log file after:")
                    settingKey: "Application/FileLogger/Backup"
                    defaultValue: true
                }
                SpinBox {
                    enabled: logBackup.checked
                    from: 1; to: 1024000; stepSize: 1; editable: true
                    value: (root.rev, OptionsController.value("Application/FileLogger/MaxSizeKiB", 65))
                    textFromValue: (v, l) => Number(v).toLocaleString(l, 'f', 0) + " " + qsTr("KiB")
                    valueFromText: (t) => parseInt(t.replace(/[^0-9]/g, "")) || 1
                    onValueModified: OptionsController.setValue("Application/FileLogger/MaxSizeKiB", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm
                OptCheck {
                    id: logDelete
                    text: qsTr("Delete backup logs older than:")
                    settingKey: "Application/FileLogger/DeleteOld"
                    defaultValue: true
                }
                SpinBox {
                    enabled: logDelete.checked
                    from: 1; to: 365; editable: true
                    value: (root.rev, OptionsController.value("Application/FileLogger/Age", 1))
                    onValueModified: OptionsController.setValue("Application/FileLogger/Age", value)
                }
                ComboBox {
                    enabled: logDelete.checked
                    model: [ qsTr("days"), qsTr("months"), qsTr("years") ]
                    currentIndex: (root.rev, OptionsController.value("Application/FileLogger/AgeType", 1))
                    onActivated: (i) => OptionsController.setValue("Application/FileLogger/AgeType", i)
                }
            }
        }

        // ==== Standalone ======================================================
        MaterialCard {
            title: qsTr("Diagnostics")
            Layout.fillWidth: true
            OptCheck {
                text: qsTr("Log performance warnings")
                settingKey: "BitTorrent/Session/PerformanceWarning"
                defaultValue: false
            }
        }
    }

    UIThemeDialog { id: uiThemeDialog }

    Connections {
        target: OptionsController
        function onActionFeedback(action, success, message) {
            if (action === "windowsDefaultApps")
                NotificationCenter.notify(message, success ? "success" : "error")
        }
    }
}
