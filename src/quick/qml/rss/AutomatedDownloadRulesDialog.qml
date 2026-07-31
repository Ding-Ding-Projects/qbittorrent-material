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
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype AutomatedDownloadRulesDialog
    \brief The "RSS Downloader" dialog — manage auto-download rules, edit the
           selected rule's definition, preview matching articles, and import /
           export the rule set.

    A three-pane split (Rules list | \c RuleDefinitionPanel | \c
    MatchingArticlesPreview) over a shared \c RuleEditorController and
    \c AutoDownloadRulesModel. A warning banner appears while the auto-downloader
    is disabled.
*/
Dialog {
    id: root

    title: qsTr("RSS Downloader")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(1000, (parent ? parent.width : 1000) * 0.95)
    height: Math.min(680, (parent ? parent.height : 680) * 0.95)
    padding: Spacing.md

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    RuleEditorController { id: editor }
    AutoDownloadRulesModel { id: rulesModel }

    property string selectedName: ""
    property int selectionCount: selectedName.length > 0 ? 1 : 0

    onOpened: {
        Log.info("rss", "AutomatedDownloadRulesDialog opened")
        editor.clearSelection()
        selectedName = ""
        rulesList.currentIndex = -1
    }
    onClosed: Log.debug("rss", "AutomatedDownloadRulesDialog closed")

    function _select(index) {
        const name = rulesModel.ruleName(index)
        selectedName = name
        Log.info("rss", "Rule selected: '" + name + "'")
        editor.selectRule(name)
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: ColumnLayout {
        spacing: Spacing.sm

        // ---- Warning banner ------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: !editor.autoDownloadEnabled
            implicitHeight: visible ? banner.implicitHeight + Spacing.sm : 0
            color: Qt.alpha(Theme.color("warning"), 0.15)

            Label {
                id: banner
                anchors.fill: parent
                anchors.margins: Spacing.xs
                text: qsTr("Auto downloading of RSS torrents is currently disabled. You can enable it in application settings.")
                color: Theme.color("warning")
                font: Qt.font({
                    family: Typography.bodyMedium.family,
                    pixelSize: Typography.bodyMedium.pixelSize,
                    weight: Typography.bodyMedium.weight,
                    letterSpacing: Typography.bodyMedium.letterSpacing,
                    italic: true
                })
                wrapMode: Text.WordWrap
            }
        }

        // ---- Three-pane split ---------------------------------------------
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            // Pane 0 — rules list column.
            ColumnLayout {
                SplitView.preferredWidth: 240
                SplitView.minimumWidth: 160
                spacing: Spacing.xs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.xs

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Download Rules")
                        font: Typography.titleMedium
                        color: Theme.color("onSurface")
                    }

                    IconButton {
                        symbol: Icons.content_copy
                        size: 18
                        tooltip: qsTr("Clone selected rule to a new rule.\nThe cloned rule will be set as disabled and the downloaded episodes history will be cleared.")
                        enabled: root.selectionCount === 1
                        onClicked: cloneRuleDialog.openFor(root.selectedName)
                    }
                    IconButton {
                        symbol: Icons.edit
                        size: 18
                        tooltip: qsTr("Rename selected rule. You can also use the F2 hotkey to rename.")
                        enabled: root.selectionCount === 1
                        onClicked: renameRuleDialog.openFor(root.selectedName)
                    }
                    IconButton {
                        symbol: Icons.deleteIcon
                        size: 18
                        tooltip: qsTr("Delete selected rule")
                        enabled: root.selectionCount >= 1
                        onClicked: deleteRuleConfirm.open()
                    }
                    IconButton {
                        symbol: Icons.add
                        size: 18
                        tooltip: qsTr("Add new rule")
                        onClicked: addRuleDialog.open()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.color("surface")
                    border.width: 1
                    border.color: Theme.color("outlineVariant")
                    radius: Spacing.radiusField

                    ListView {
                        id: rulesList
                        anchors.fill: parent
                        anchors.margins: Spacing.xs
                        clip: true
                        model: rulesModel
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: ItemDelegate {
                            id: ruleDel
                            width: ListView.view.width
                            implicitHeight: 32

                            required property int index
                            required property string name
                            required property bool enabled

                            highlighted: rulesList.currentIndex === index

                            background: Rectangle {
                                color: ruleDel.highlighted
                                       ? Qt.alpha(Theme.color("primary"), 0.12)
                                       : (ruleDel.hovered ? Qt.alpha(Theme.color("onSurface"), 0.08) : "transparent")
                            }

                            contentItem: RowLayout {
                                spacing: Spacing.xs
                                CheckBox {
                                    checked: ruleDel.enabled
                                    onToggled: {
                                        Log.info("rss", "Rule '" + ruleDel.name + "' enabled -> " + checked)
                                        editor.setRuleEnabled(ruleDel.name, checked)
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: ruleDel.name
                                    elide: Text.ElideRight
                                    font: Typography.bodyMedium
                                    color: Theme.color("onSurface")
                                }
                            }

                            onClicked: {
                                rulesList.currentIndex = index
                                root._select(index)
                            }
                            onDoubleClicked: renameRuleDialog.openFor(ruleDel.name)

                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: {
                                    rulesList.currentIndex = ruleDel.index
                                    root._select(ruleDel.index)
                                    rulesMenu.selectionCount = root.selectionCount
                                    rulesMenu.popup()
                                }
                            }
                        }
                    }
                }
            }

            // Pane 1 — rule definition.
            RuleDefinitionPanel {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 320
                editor: editor
            }

            // Pane 2 — matching articles preview.
            MatchingArticlesPreview {
                SplitView.preferredWidth: 260
                SplitView.minimumWidth: 160
                editor: editor
            }
        }

        // ---- Bottom buttons ------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.sm

            Button {
                text: qsTr("Import...")
                flat: true
                onClicked: {
                    Log.info("rss", "Import rules clicked")
                    importDialog.open()
                }
            }
            Button {
                text: qsTr("Export...")
                flat: true
                onClicked: {
                    Log.info("rss", "Export rules clicked")
                    exportDialog.open()
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Close")
                highlighted: true
                onClicked: root.close()
            }
        }
    }

    // ---- Rules list context menu ------------------------------------------

    RulesListContextMenu {
        id: rulesMenu
        onRequestAdd: addRuleDialog.open()
        onRequestDelete: deleteRuleConfirm.open()
        onRequestRename: renameRuleDialog.openFor(root.selectedName)
        onRequestClone: cloneRuleDialog.openFor(root.selectedName)
        onRequestClearEpisodes: clearEpisodesConfirm.open()
    }

    // ---- Rule CRUD dialogs -------------------------------------------------

    TextInputDialog {
        id: addRuleDialog
        title: qsTr("New rule name")
        label: qsTr("Please type the name of the new download rule.")
        onAccepted: (name) => {
            const err = editor.addRule(name)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    TextInputDialog {
        id: renameRuleDialog
        property string oldName: ""
        title: qsTr("Rule renaming")
        label: qsTr("Please type the new rule name")
        function openFor(n) { oldName = n; text = n; open() }
        onAccepted: (newName) => {
            const err = editor.renameRule(oldName, newName)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    TextInputDialog {
        id: cloneRuleDialog
        property string srcName: ""
        title: qsTr("Rule cloning")
        label: qsTr("Please type the name for the clone of the download rule.")
        function openFor(n) { srcName = n; text = n; open() }
        onAccepted: (cloneName) => {
            const err = editor.cloneRule(srcName, cloneName)
            if (err && err.length > 0)
                NotificationCenter.notify(err, "error")
        }
    }

    ConfirmDialog {
        id: deleteRuleConfirm
        title: qsTr("Rule deletion confirmation")
        text: qsTr("Are you sure you want to remove the download rule named '%1'?").arg(root.selectedName)
        destructive: true
        onAccepted: {
            editor.removeRules([root.selectedName])
            editor.clearSelection()
            root.selectedName = ""
            rulesList.currentIndex = -1
        }
    }

    ConfirmDialog {
        id: clearEpisodesConfirm
        title: qsTr("Clear downloaded episodes")
        text: qsTr("Are you sure you want to clear the list of downloaded episodes for the selected rule?")
        onAccepted: editor.clearDownloadedEpisodes([root.selectedName])
    }

    // ---- Import / export file dialogs -------------------------------------

    Platform.FileDialog {
        id: importDialog
        title: qsTr("Import RSS rules")
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: [ qsTr("Rules (*.json)"), qsTr("Rules (legacy) (*.rssrules)") ]
        onAccepted: {
            const err = editor.importRules(file.toString())
            if (err && err.length > 0)
                NotificationCenter.notify(qsTr("Import error") + ": " + err, "error")
        }
    }

    Platform.FileDialog {
        id: exportDialog
        title: qsTr("Export RSS rules")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [ qsTr("Rules (*.json)"), qsTr("Rules (legacy) (*.rssrules)") ]
        onAccepted: {
            const path = file.toString()
            const legacy = path.toLowerCase().endsWith(".rssrules")
            const err = editor.exportRules(path, legacy)
            if (err && err.length > 0)
                NotificationCenter.notify(qsTr("Export error") + ": " + err, "error")
        }
    }
}
