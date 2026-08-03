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
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype SearchPage
    \brief Options → Search.

    Every control here is bound to a setting \c OptionsController already stages
    and commits. This page previously rendered a paragraph explaining that its
    settings lived elsewhere, while the plumbing for all five of them was
    already in place and simply unrendered.

    The live status block reports the two prerequisites the Search tab actually
    depends on — a usable Python interpreter and the extracted plugin runtime —
    because a settings page that lets you point at an interpreter should also
    say whether the one currently selected works.
*/
Flickable {
    id: root

    // Reactive read cursor — every OptionsController.value() binding depends on
    // this so the page refreshes when the controller (re)loads.
    readonly property int rev: OptionsController.revision

    contentHeight: layout.implicitHeight + (2 * Spacing.lg)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    component OptCheck: CheckBox {
        property string settingKey: ""
        property bool defaultValue: false
        font: Typography.bodyMedium
        checked: (root.rev, OptionsController.value(settingKey, defaultValue))
        onToggled: {
            OptionsController.setValue(settingKey, checked)
            Log.debug("ui", "Search options: " + settingKey + " -> " + checked)
        }
    }

    Component.onCompleted: Log.debug("ui", "SearchPage ready")

    ColumnLayout {
        id: layout
        x: Spacing.lg
        y: Spacing.lg
        width: root.width - (2 * Spacing.lg)
        spacing: Spacing.lg

        MaterialCard {
            title: qsTr("Search")
            titleIcon: Icons.search
            Layout.fillWidth: true

            OptCheck {
                text: qsTr("Show the Search tab")
                settingKey: "searchEnabled"
                defaultValue: true
                Accessible.description: qsTr("Shows or hides the Search tab in the main window.")
            }

            OptCheck {
                text: qsTr("Remember open search tabs between sessions")
                settingKey: "storeOpenedSearchTabs"
                defaultValue: false
            }

            OptCheck {
                text: qsTr("Also remember each tab's results")
                settingKey: "storeOpenedSearchTabResults"
                defaultValue: false
                enabled: (root.rev, OptionsController.value("storeOpenedSearchTabs", false))
            }

            LabeledField {
                label: qsTr("Search history length:")
                Layout.fillWidth: true

                SpinBox {
                    from: 0
                    to: 500
                    editable: true
                    value: (root.rev, OptionsController.value("searchHistoryLength", 50))
                    onValueModified: OptionsController.setValue("searchHistoryLength", value)
                    Accessible.name: qsTr("Number of past searches to remember")
                }
            }
        }

        MaterialCard {
            title: qsTr("Python interpreter")
            titleIcon: Icons.build
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                text: qsTr("Search plugins run under Python. Leave this empty to detect an interpreter automatically.")
            }

            LabeledField {
                label: qsTr("Interpreter:")
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    TextField {
                        id: pythonPathField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Detected automatically")
                        selectByMouse: true
                        text: (root.rev, OptionsController.value("pythonExecutablePath", ""))
                        Accessible.name: qsTr("Path to the Python interpreter")
                        onEditingFinished: OptionsController.setValue("pythonExecutablePath", text)
                    }

                    IconButton {
                        symbol: Icons.folder_open
                        tooltip: qsTr("Choose an interpreter")
                        onClicked: pythonDialog.open()
                    }
                }
            }

            // A settings page that lets you point at an interpreter should say
            // whether the one in effect actually works.
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm

                MDIcon {
                    icon: SearchController.unavailableReason.length === 0
                        ? Icons.check_circle : Icons.error
                    size: Spacing.iconSizeSmall
                    color: SearchController.unavailableReason.length === 0
                        ? Theme.color("success") : Theme.color("error")
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font: Typography.bodyMedium
                    color: Theme.color("onSurface")
                    text: SearchController.unavailableReason.length > 0
                        ? SearchController.unavailableReason
                        : (SearchController.pluginsInstalled
                            ? qsTr("Search is ready.")
                            : qsTr("Search is ready; no plugins are installed yet."))
                    Accessible.name: text
                }

                Button {
                    text: qsTr("Check again")
                    flat: true
                    font: Typography.labelMedium
                    onClicked: {
                        Log.info("ui", "Re-checking search prerequisites from Options")
                        SearchController.refreshPythonDetection()
                    }
                }
            }
        }
    }

    Platform.FileDialog {
        id: pythonDialog
        title: qsTr("Select the Python interpreter")
        onAccepted: {
            const path = decodeURIComponent(("" + file).replace(/^file:\/\/\/?/, ""))
            pythonPathField.text = path
            OptionsController.setValue("pythonExecutablePath", path)
            Log.info("ui", "Python interpreter set from Options")
        }
    }
}
