/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype FilterTextField
    \brief Plain-text-first filter with an adjacent, anchored full regex builder.

    The builder deliberately validates and evaluates through WorkspaceManager's
    Qt QRegularExpression bridge. Search surfaces therefore share the desktop
    app's real PCRE2-backed dialect instead of silently using JavaScript RegExp.
*/
TextField {
    id: root

    property string placeholder: qsTr("Filter…")
    property bool regexEnabled: false
    property string regexFlags: "iu"
    property string builderTitle: qsTr("Regex Builder")
    property string builderSampleText: "alpha-2026\nbeta.txt\n蝦餃-1080p"
    property bool builderAvailable: true
    readonly property bool builderOpen: builderPopup.visible
    readonly property var patternStatus: WorkspaceManager.validatePattern(text, regexFlags)
    readonly property bool patternValid: !regexEnabled || patternStatus.valid

    signal regexApplied(string pattern, string flags)

    function setFlag(flag, enabled) {
        var next = regexFlags.replace(flag, "")
        if (enabled && next.indexOf(flag) < 0)
            next += flag
        var canonical = ""
        var order = "gimsu"
        for (var i = 0; i < order.length; ++i)
            if (next.indexOf(order[i]) >= 0) canonical += order[i]
        regexFlags = canonical
    }

    function openBuilder() {
        if (!builderAvailable)
            return
        builderPattern.text = root.text
        sampleEditor.text = root.builderSampleText
        builderPopup.open()
    }

    placeholderText: placeholder
    selectByMouse: true
    maximumLength: 4096
    implicitHeight: Spacing.controlHeight
    font: Typography.bodyLarge
    color: Theme.color("onSurface")
    placeholderTextColor: Theme.color("muted")
    Accessible.name: placeholder
    Accessible.description: regexEnabled
        ? qsTr("Regular expression using Qt QRegularExpression with flags %1").arg(regexFlags)
        : qsTr("Plain-text search")

    leftPadding: searchIcon.width + Spacing.md
    rightPadding: trailing.width + Spacing.sm

    background: Rectangle {
        radius: Spacing.radiusField
        color: Theme.color("surface")
        border.width: root.activeFocus ? 2 : 1
        border.color: !root.patternValid ? Theme.color("error")
            : (root.activeFocus ? Theme.color("primary") : Theme.color("outline"))
        Behavior on border.color { ColorAnimation { duration: Spacing.motionFast } }
    }

    onTextChanged: Log.trace("ui", "FilterTextField text changed")

    MDIcon {
        id: searchIcon
        icon: root.regexEnabled ? Icons.settings_suggest : Icons.search
        size: 18
        color: root.patternValid ? Theme.color("onSurfaceVariant") : Theme.color("error")
        anchors.left: parent.left
        anchors.leftMargin: Spacing.sm
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        id: trailing
        spacing: 0
        anchors.right: parent.right
        anchors.rightMargin: Spacing.xs
        anchors.verticalCenter: parent.verticalCenter

        IconButton {
            symbol: Icons.close
            size: 16
            visible: root.text.length > 0
            tooltip: qsTr("Clear")
            onClicked: root.clear()
        }

        IconButton {
            symbol: Icons.settings_suggest
            size: 16
            checked: root.regexEnabled
            tooltip: root.regexEnabled
                ? qsTr("Regex enabled · open builder") : qsTr("Open Regex Builder")
            onClicked: root.openBuilder()
            onPressAndHold: formatMenu.popup()
        }

        IconButton {
            symbol: Icons.more_vert
            size: 16
            tooltip: qsTr("Search mode and flags")
            onClicked: formatMenu.popup()
        }
    }

    FilterPatternFormatMenu {
        id: formatMenu
        regexEnabled: root.regexEnabled
        regexFlags: root.regexFlags
        onFormatChanged: root.regexEnabled = regexEnabled
        onFlagsChanged: function(flags) { root.regexFlags = flags }
        onBuilderRequested: root.openBuilder()
    }

    Popup {
        id: builderPopup
        parent: root
        x: Math.max(0, Math.min(root.width - width, 0))
        y: root.height + Spacing.xs
        width: Math.max(420, Math.min(620, root.Window.window
            ? root.Window.window.width - Spacing.xl * 2 : 620))
        height: Math.max(420, Math.min(620, root.Window.window
            ? root.Window.window.height - 140 : 620))
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        Material.elevation: 12

        readonly property var evaluation: WorkspaceManager.evaluateRegularExpression(
            builderPattern.text, root.regexFlags, sampleEditor.text)

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
            border.width: 1
            border.color: Theme.color("outlineVariant")
        }

        contentItem: ColumnLayout {
            spacing: 0
            Accessible.name: root.builderTitle
            Accessible.role: Accessible.Dialog

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Spacing.md
                spacing: Spacing.sm
                MDIcon { icon: Icons.settings_suggest; size: 20; color: Theme.color("primary") }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: root.builderTitle
                        font: Typography.titleLarge
                        color: Theme.color("onSurface")
                    }
                    Label {
                        text: qsTr("Qt QRegularExpression · PCRE2 dialect · local bounded evaluation")
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                    }
                }
                IconButton {
                    symbol: Icons.close
                    tooltip: qsTr("Close and return to search")
                    onClicked: {
                        builderPopup.close()
                        root.forceActiveFocus()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: Math.max(0, builderPopup.width - Spacing.xl * 2)
                    spacing: Spacing.md

                    Item { Layout.preferredHeight: 1 }

                    Label { text: qsTr("Raw pattern"); font: Typography.labelLarge }
                    TextArea {
                        id: builderPattern
                        Layout.fillWidth: true
                        Layout.preferredHeight: 78
                        Accessible.name: qsTr("Raw regular expression pattern")
                        font.family: Typography.monoFamily
                        wrapMode: TextEdit.WrapAnywhere
                        selectByMouse: true
                        placeholderText: qsTr("Type a PCRE2-compatible pattern")
                        onTextChanged: {
                            if (text.length > 4096)
                                text = text.substring(0, 4096)
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Repeater {
                            model: [
                                { key: "g", label: qsTr("All matches") },
                                { key: "i", label: qsTr("Ignore case") },
                                { key: "m", label: qsTr("Multiline") },
                                { key: "s", label: qsTr("Dotall") },
                                { key: "u", label: qsTr("Unicode properties") }
                            ]
                            delegate: CheckBox {
                                required property var modelData
                                text: modelData.key + " · " + modelData.label
                                checked: root.regexFlags.indexOf(modelData.key) >= 0
                                onToggled: root.setFlag(modelData.key, checked)
                            }
                        }
                    }

                    Label { text: qsTr("Guided construction"); font: Typography.labelLarge }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Repeater {
                            model: [
                                { label: qsTr("Literal"), token: "\\Qtext\\E" },
                                { label: qsTr("Character class"), token: "[A-Za-z0-9]" },
                                { label: qsTr("Start / end"), token: "^$" },
                                { label: qsTr("Capture group"), token: "()" },
                                { label: qsTr("Named group"), token: "(?<name>)" },
                                { label: qsTr("Alternation"), token: "(?:one|two)" },
                                { label: qsTr("Optional"), token: "?" },
                                { label: qsTr("One or more"), token: "+" },
                                { label: qsTr("Range"), token: "{1,3}" },
                                { label: qsTr("Unicode letters"), token: "\\p{L}+" }
                            ]
                            delegate: Button {
                                required property var modelData
                                text: modelData.label
                                flat: true
                                onClicked: builderPattern.insert(builderPattern.cursorPosition,
                                    modelData.token)
                            }
                        }
                    }

                    Label { text: qsTr("Editable sample text"); font: Typography.labelLarge }
                    TextArea {
                        id: sampleEditor
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        Accessible.name: qsTr("Regex sample text")
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        onTextChanged: {
                            if (text.length > 65536)
                                text = text.substring(0, 65536)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: evaluationColumn.implicitHeight + Spacing.md * 2
                        radius: Spacing.radiusCard
                        color: Theme.color("surfaceVariant")
                        border.width: 1
                        border.color: builderPopup.evaluation.valid
                            ? Theme.color("outlineVariant") : Theme.color("error")

                        ColumnLayout {
                            id: evaluationColumn
                            anchors.fill: parent
                            anchors.margins: Spacing.md
                            spacing: Spacing.xs
                            Label {
                                Layout.fillWidth: true
                                text: builderPopup.evaluation.valid
                                    ? qsTr("%1 match(es)%2").arg(builderPopup.evaluation.count)
                                        .arg(builderPopup.evaluation.truncated ? qsTr(" · first 200 shown") : "")
                                    : qsTr("Invalid pattern at %1: %2")
                                        .arg(builderPopup.evaluation.errorOffset)
                                        .arg(builderPopup.evaluation.error)
                                color: builderPopup.evaluation.valid
                                    ? Theme.color("onSurface") : Theme.color("error")
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: builderPopup.evaluation.matches || []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Label {
                                        Layout.fillWidth: true
                                        text: qsTr("Match %1–%2: %3")
                                            .arg(modelData.start)
                                            .arg(modelData.start + modelData.length)
                                            .arg(modelData.text.length ? modelData.text : qsTr("zero-width"))
                                        font.family: Typography.monoFamily
                                        elide: Text.ElideRight
                                    }
                                    Repeater {
                                        model: modelData.captures || []
                                        delegate: Label {
                                            required property var modelData
                                            Layout.leftMargin: Spacing.md
                                            Layout.fillWidth: true
                                            text: modelData.index === 0 ? "" : qsTr("Capture %1%2: %3")
                                                .arg(modelData.index)
                                                .arg(modelData.name ? " · " + modelData.name : "")
                                                .arg(modelData.text)
                                            visible: modelData.index > 0
                                            font: Typography.bodySmall
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Safety: patterns are limited to 4,096 characters, samples to 64 KiB, and results to 200. Zero-width matches are handled by Qt's iterator.")
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.preferredHeight: 1 }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Spacing.md
                spacing: Spacing.sm
                Button {
                    text: qsTr("Copy /pattern/flags")
                    flat: true
                    onClicked: {
                        clipboardHelper.text = "/" + builderPattern.text + "/" + root.regexFlags
                        clipboardHelper.selectAll()
                        clipboardHelper.copy()
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Apply to this search")
                    highlighted: true
                    enabled: builderPopup.evaluation.valid
                    onClicked: {
                        root.text = builderPattern.text
                        root.regexEnabled = true
                        root.regexApplied(root.text, root.regexFlags)
                        builderPopup.close()
                        root.forceActiveFocus()
                    }
                }
            }
        }
    }

    TextInput { id: clipboardHelper; visible: false; width: 0; height: 0 }
}
