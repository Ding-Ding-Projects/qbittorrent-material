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
    signal pluginEnabledChanged(string pluginId, bool enabled)
    signal catalogRetryRequested()
    signal pluginTrustRequested(string pluginId)
    signal pluginManageRequested(string pluginId)
    signal pluginSourceRequested(string pluginId, string sourceUrl)
    signal settingValueChanged(string settingId, var value)

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
    property string pendingCommandId: ""
    property string pendingPluginManageId: ""
    // Trust validation is asynchronous. Keep an immutable-looking list rather
    // than one global id so two different quarantined plugins can validate at
    // once while a duplicate click on either stays a no-op.
    property var pendingPluginTrustIds: []
    property string pendingSettingId: ""
    property var pendingSettingValue

    function isPluginTrustPending(pluginId) {
        return pendingPluginTrustIds.indexOf(pluginId) !== -1
    }

    function finishPluginTrust(pluginId) {
        var next = []
        for (var i = 0; i < pendingPluginTrustIds.length; ++i) {
            if (pendingPluginTrustIds[i] !== pluginId)
                next.push(pendingPluginTrustIds[i])
        }
        if (next.length !== pendingPluginTrustIds.length)
            pendingPluginTrustIds = next
    }

    function requestPluginTrust(pluginId) {
        if (!pluginId.length || isPluginTrustPending(pluginId))
            return false
        pendingPluginTrustIds = pendingPluginTrustIds.concat([pluginId])
        pluginTrustRequested(pluginId)
        return true
    }

    function filteredCommands() {
        var query = search.text.trim()
        if (!query.length)
            return commands
        var matches = []
        for (var i = 0; i < commands.length; ++i) {
            var command = commands[i]
            var corpus = command.title + " " + command.group + " " + command.destination
                + " " + (command.context || "") + " " + (command.keywords || "")
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
        // Ctrl+Shift+F is also a refocus shortcut. Only reset a fresh palette
        // session; a second chord while this popup is visible must retain its
        // current query and keyboard selection.
        if (!root.visible) {
            fullWindow = !!Preferences.value("GUI/CommandPalette/FullWindow", false)
            search.text = ""
            open()
        }
        search.forceActiveFocus(Qt.ShortcutFocusReason)
    }

    function queueSettingValue(settingId, value) {
        pendingSettingId = settingId
        pendingSettingValue = value
        close()
    }

    function activateCurrent() {
        var rows = filteredCommands()
        if (!rows.length)
            return
        var index = Math.max(0, Math.min(results.currentIndex, rows.length - 1))
        if (rows[index].enabled === false)
            return
        pendingCommandId = rows[index].id
        close()
    }

    onOpened: results.currentIndex = 0
    onClosed: {
        var commandId = pendingCommandId
        var pluginId = pendingPluginManageId
        var settingId = pendingSettingId
        var settingValue = pendingSettingValue
        pendingCommandId = ""
        pendingPluginManageId = ""
        pendingSettingId = ""
        pendingSettingValue = undefined
        Qt.callLater(function() {
            if (commandId.length)
                root.commandInvoked(commandId)
            else if (pluginId.length)
                root.pluginManageRequested(pluginId)
            else if (settingId.length)
                root.settingValueChanged(settingId, settingValue)
        })
    }

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
            Label {
                text: qsTr("%1 commands").arg(root.commands.length)
                font: Typography.labelMedium
                color: Theme.color("onSurfaceVariant")
                Accessible.name: text
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
                enabled: modelData.enabled !== false
                highlighted: ListView.isCurrentItem
                hoverEnabled: true
                Accessible.name: modelData.title
                Accessible.description: modelData.accessibleDescription
                    || (modelData.destination
                        ? qsTr("Destination: %1").arg(modelData.destination)
                        : qsTr("Action in %1").arg(modelData.group))
                onHoveredChanged: if (hovered) results.currentIndex = index
                onClicked: {
                    results.currentIndex = index
                    root.activateCurrent()
                }

                contentItem: RowLayout {
                    spacing: Spacing.sm

                    MDIcon {
                        visible: modelData.pluginId !== undefined
                        icon: Icons.extension
                        size: 20
                        color: Theme.color("primary")
                        Accessible.ignored: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
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
                        Label {
                            Layout.fillWidth: true
                            visible: (modelData.context || "").length > 0
                            text: modelData.context || ""
                            color: Theme.color("onSurfaceVariant")
                            font: Typography.labelSmall
                            elide: Text.ElideRight
                            Accessible.name: visible ? text : ""
                        }
                    }

                    Switch {
                        visible: modelData.kind === "action" && modelData.checkable === true
                        checked: modelData.checked === true
                        enabled: modelData.enabled !== false
                        Accessible.name: modelData.title
                        Accessible.description: modelData.destination || modelData.group
                        onClicked: {
                            results.currentIndex = index
                            root.activateCurrent()
                        }
                    }

                    Switch {
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "toggle"
                        checked: modelData.checked === true
                        enabled: modelData.inlineEditable !== false
                        Accessible.name: qsTr("Change %1").arg(modelData.title)
                        Accessible.description: modelData.inlineEditable === false
                            ? qsTr("Open the setting to edit it because Options has unapplied changes.")
                            : (modelData.destination || modelData.group)
                        onClicked: {
                            results.currentIndex = index
                            root.queueSettingValue(modelData.settingId, checked)
                        }
                    }

                    ComboBox {
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "select"
                        Layout.preferredWidth: 180
                        model: modelData.choices || []
                        currentIndex: Number(modelData.value)
                        enabled: modelData.inlineEditable !== false
                        Accessible.name: qsTr("Change %1").arg(modelData.title)
                        onActivated: (choiceIndex) =>
                            root.queueSettingValue(modelData.settingId, choiceIndex)
                    }

                    Slider {
                        property bool changedByUser: false
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "slider"
                        Layout.preferredWidth: 150
                        from: Number(modelData.minimum)
                        to: Number(modelData.maximum)
                        stepSize: Number(modelData.step) || 1
                        value: Number(modelData.value)
                        enabled: modelData.inlineEditable !== false
                        Accessible.name: qsTr("Change %1").arg(modelData.title)
                        onMoved: changedByUser = true
                        onPressedChanged: {
                            if (!pressed && changedByUser) {
                                changedByUser = false
                                root.queueSettingValue(modelData.settingId, value)
                            }
                        }
                    }

                    SpinBox {
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "spin"
                        Layout.preferredWidth: 140
                        from: Number(modelData.minimum)
                        to: Number(modelData.maximum)
                        stepSize: Number(modelData.step) || 1
                        value: Number(modelData.value)
                        editable: true
                        enabled: modelData.inlineEditable !== false
                        Accessible.name: qsTr("Change %1").arg(modelData.title)
                        onValueModified: root.queueSettingValue(modelData.settingId, value)
                    }

                    TextField {
                        visible: modelData.kind === "setting"
                            && (modelData.inlineControl === "text"
                                || modelData.inlineControl === "path")
                            && modelData.sensitive !== true
                        Layout.preferredWidth: 190
                        text: modelData.valueText || ""
                        enabled: modelData.inlineEditable !== false
                        selectByMouse: true
                        placeholderText: modelData.inlineControl === "path"
                            ? qsTr("Enter a path") : qsTr("Enter a value")
                        Accessible.name: qsTr("Change %1").arg(modelData.title)
                        onAccepted: root.queueSettingValue(modelData.settingId, text)
                    }

                    Button {
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "password"
                        text: qsTr("Edit securely…")
                        flat: true
                        Accessible.name: qsTr("Open %1 without showing its value").arg(modelData.title)
                        onClicked: {
                            root.pendingCommandId = modelData.id
                            root.close()
                        }
                    }

                    Button {
                        visible: modelData.kind === "setting"
                            && (modelData.inlineControl === "action"
                                || modelData.inlineControl === "color")
                        text: modelData.inlineControl === "color"
                            ? qsTr("Choose…") : (modelData.actionLabel || qsTr("Open…"))
                        flat: true
                        enabled: modelData.inlineEditable !== false
                        Accessible.name: modelData.title
                        onClicked: root.queueSettingValue(modelData.settingId, true)
                    }

                    Label {
                        visible: modelData.kind === "setting"
                            && modelData.inlineControl === "readonly"
                        text: qsTr("Read only")
                        color: Theme.color("onSurfaceVariant")
                        font: Typography.labelMedium
                        Accessible.name: qsTr("%1 is read only").arg(modelData.title)
                    }

                    Switch {
                        visible: modelData.kind === "plugin" && modelData.registered === true
                        checked: modelData.pluginEnabled === true
                        enabled: modelData.runtimeWaiting !== true
                            && modelData.trusted !== false
                            && (modelData.integrityState === undefined
                                || String(modelData.integrityState).indexOf("verified-") === 0
                                || modelData.integrityState === "user-managed")
                            && modelData.enabled !== false
                        Accessible.name: qsTr("Enable %1 search plugin").arg(modelData.title)
                        Accessible.description: modelData.runtimeWaiting === true
                            ? qsTr("Python is not ready; the registered plugin cannot be changed yet.")
                            : (modelData.destination || modelData.group)
                        onClicked: {
                            results.currentIndex = index
                            root.pluginEnabledChanged(modelData.pluginId, checked)
                        }
                    }

                    Button {
                        visible: modelData.kind === "plugin" && modelData.canRetry === true
                        text: qsTr("Retry catalog setup")
                        flat: true
                        Accessible.name: qsTr("Retry shared search-plugin catalog setup")
                        Accessible.description: qsTr("Retries verified catalog downloads and runtime validation for all catalog plugins, not only %1.")
                            .arg(modelData.title)
                        onClicked: {
                            results.currentIndex = index
                            root.catalogRetryRequested()
                        }
                    }

                    Button {
                        readonly property bool trustPending:
                            root.isPluginTrustPending(modelData.pluginId)
                        // The backend switches a queued plugin out of canTrust
                        // while it validates. Keep that row visible so each
                        // outstanding request remains truthfully disabled.
                        visible: modelData.kind === "plugin"
                            && (modelData.canTrust === true || trustPending)
                        text: trustPending
                            ? qsTr("Trusting…") : qsTr("Trust")
                        flat: true
                        enabled: !trustPending
                        Accessible.name: qsTr("Review and trust %1 search plugin").arg(modelData.title)
                        Accessible.description: trustPending
                            ? qsTr("Plugin trust validation is in progress.")
                            : qsTr("Validate this quarantined plugin before allowing the search runtime to use it.")
                        onClicked: {
                            results.currentIndex = index
                            root.requestPluginTrust(modelData.pluginId)
                        }
                    }

                    Button {
                        visible: modelData.kind === "plugin" && modelData.canManage === true
                        text: qsTr("Manage")
                        flat: true
                        Accessible.name: qsTr("Manage %1 search plugin").arg(modelData.title)
                        onClicked: {
                            results.currentIndex = index
                            root.pendingPluginManageId = modelData.pluginId
                            root.close()
                        }
                    }

                    IconButton {
                        visible: modelData.kind === "plugin"
                            && (modelData.pluginSource || "").length > 0
                        symbol: Icons.open_in_new
                        tooltip: qsTr("Open plugin source")
                        Accessible.name: qsTr("Open source for %1").arg(modelData.title)
                        onClicked: root.pluginSourceRequested(
                            modelData.pluginId, modelData.pluginSource)
                    }

                    Label {
                        visible: modelData.kind !== "plugin"
                            && modelData.kind !== "setting"
                            && !modelData.checkable
                            && (modelData.shortcut || "").length > 0
                        text: modelData.shortcut || ""
                        color: Theme.color("onSurfaceVariant")
                        font: Typography.labelMedium
                        Accessible.name: visible ? qsTr("Keyboard shortcut %1").arg(text) : ""
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
            text: qsTr("↑/↓ Navigate   Enter Run   Esc Close   Ctrl+Shift+F Open")
            horizontalAlignment: Text.AlignHCenter
            font: Typography.bodySmall
            color: Theme.color("onSurfaceVariant")
        }
    }
}
