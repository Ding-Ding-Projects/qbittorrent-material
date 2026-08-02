/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

Popup {
    id: root

    required property var commands
    signal commandInvoked(string commandId)

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: fullWindow ? parent.width : Math.min(680, parent.width - Spacing.xl * 2)
    height: fullWindow ? parent.height : Math.min(560, parent.height - Spacing.xl * 2)
    Material.elevation: 12

    property bool fullWindow: false

    function filteredCommands() {
        var query = search.text.trim()
        if (!query.length)
            return commands
        var matches = []
        for (var i = 0; i < commands.length; ++i) {
            var command = commands[i]
            var corpus = command.title + " " + command.group + " " + command.destination
                + " " + (command.keywords || "")
            if (search.regexEnabled) {
                var result = WorkspaceManager.evaluateRegularExpression(
                    query, search.regexFlags, corpus)
                if (result.valid && result.count > 0)
                    matches.push(command)
            }
            else if (corpus.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0) {
                matches.push(command)
            }
        }
        return matches
    }

    function openPalette() {
        fullWindow = !!Preferences.value("GUI/CommandPalette/FullWindow", false)
        search.text = ""
        open()
        search.forceActiveFocus(Qt.ShortcutFocusReason)
    }

    function activateCurrent() {
        var rows = filteredCommands()
        if (!rows.length)
            return
        var index = Math.max(0, Math.min(results.currentIndex, rows.length - 1))
        close()
        commandInvoked(rows[index].id)
    }

    onOpened: results.currentIndex = 0

    background: Rectangle {
        radius: root.fullWindow ? 0 : Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: root.fullWindow ? 0 : Spacing.outlineWidth
        border.color: Theme.color("outline")
    }

    contentItem: ColumnLayout {
        spacing: 0
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Command palette")
        Accessible.description: qsTr("Search commands, destinations, and settings. Use Up and Down to navigate and Enter to run a command.")

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.lg
            spacing: Spacing.sm

            Label {
                Layout.fillWidth: true
                text: qsTr("Command palette")
                font: Typography.titleLarge
                color: Theme.color("onSurface")
            }
            Button {
                text: root.fullWindow ? qsTr("Card view") : qsTr("Full-window view")
                Accessible.name: text
                onClicked: {
                    root.fullWindow = !root.fullWindow
                    Preferences.setValue("GUI/CommandPalette/FullWindow", root.fullWindow)
                    Preferences.apply()
                }
            }
        }

        FilterTextField {
            id: search
            Layout.fillWidth: true
            Layout.leftMargin: Spacing.lg
            Layout.rightMargin: Spacing.lg
            Layout.bottomMargin: Spacing.md
            placeholder: qsTr("Search commands, settings, and destinations…")
            builderTitle: qsTr("Command Palette Regex Builder")
            builderSampleText: qsTr("Transfers\nOptions: Connection\nAdd torrent link\nStatistics")
            Accessible.name: qsTr("Search command palette")
            Keys.onDownPressed: (event) => {
                results.incrementCurrentIndex()
                event.accepted = true
            }
            Keys.onUpPressed: (event) => {
                results.decrementCurrentIndex()
                event.accepted = true
            }
            Keys.onReturnPressed: (event) => {
                root.activateCurrent()
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                root.activateCurrent()
                event.accepted = true
            }
            onTextChanged: results.currentIndex = 0
        }

        Rectangle { Layout.fillWidth: true; height: Spacing.outlineWidth; color: Theme.color("outlineVariant") }

        ListView {
            id: results
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Spacing.sm
            clip: true
            spacing: Spacing.xs
            model: root.filteredCommands()
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            Accessible.name: qsTr("Command results")

            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: ListView.view.width
                highlighted: ListView.isCurrentItem
                hoverEnabled: true
                Accessible.name: modelData.title
                Accessible.description: modelData.destination
                    ? qsTr("Destination: %1").arg(modelData.destination)
                    : qsTr("Action in %1").arg(modelData.group)
                onHoveredChanged: if (hovered) results.currentIndex = index
                onClicked: {
                    results.currentIndex = index
                    root.activateCurrent()
                }

                contentItem: ColumnLayout {
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        text: modelData.title
                        color: Theme.color("onSurface")
                        font: Typography.bodyLarge
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.destination || modelData.group
                        color: Theme.color("onSurfaceVariant")
                        font: Typography.bodySmall
                        elide: Text.ElideRight
                    }
                }
            }

            footer: Label {
                width: results.width
                visible: results.count === 0
                padding: Spacing.xl
                horizontalAlignment: Text.AlignHCenter
                text: search.patternValid ? qsTr("No matching commands") : qsTr("Fix the regular expression to search")
                color: Theme.color("onSurfaceVariant")
                Accessible.name: text
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            text: qsTr("↑/↓ Navigate   Enter Run   Esc Close   Ctrl+Shift+P Open")
            horizontalAlignment: Text.AlignHCenter
            font: Typography.bodySmall
            color: Theme.color("onSurfaceVariant")
        }
    }
}
