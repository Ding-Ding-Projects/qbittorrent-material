/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype RegexBuilderSheet
    \brief Bounded Qt QRegularExpression builder with guided construction,
           raw editing, flags, samples, captures, presets and copy/export.

    Validation and matching always cross the WorkspaceManager C++ bridge, so
    this surface and workspace searches use Qt's PCRE2-backed dialect rather
    than the subtly different JavaScript RegExp implementation.
*/
Sheet {
    id: root
    sheetWidth: 620

    property var filterProxy: null
    property string pattern: "(19|20)\\d{2}"
    property string sampleText: "ubuntu-24.04.2-desktop-amd64.iso\nS02E08 · 蝦餃\nnotes.txt"
    property bool flagI: true
    property bool flagG: true
    property bool flagM: false
    property bool flagS: false
    property bool flagU: true
    property var library: []
    property string libraryName: ""

    readonly property string flagStr: (flagG ? "g" : "") + (flagI ? "i" : "")
        + (flagM ? "m" : "") + (flagS ? "s" : "") + (flagU ? "u" : "")
    readonly property var evaluation: WorkspaceManager.evaluateRegularExpression(
        pattern, flagStr, sampleText)
    readonly property bool patternValid: evaluation.valid

    signal closeRequested()
    signal applyRequested(string pattern, string flags)

    function insertToken(token, cursorDelta) {
        var position = patternEditor.cursorPosition
        patternEditor.insert(position, token)
        patternEditor.cursorPosition = position + (cursorDelta === undefined
            ? token.length : cursorDelta)
        patternEditor.forceActiveFocus()
    }

    function loadLibrary() {
        var stored = Preferences.value("RegexBuilder/LibraryV2", "")
        if (stored && ("" + stored).length > 0) {
            try {
                var parsed = JSON.parse("" + stored)
                if (Array.isArray(parsed)) {
                    library = parsed.slice(0, 32)
                    return
                }
            } catch (error) {
                Log.warning("ui", "Ignoring invalid saved regex library")
            }
        }
        library = [
            { name: qsTr("Episode"), pattern: "S\\d{2}E\\d{2}", flags: "iu" },
            { name: qsTr("Resolution"), pattern: "(?:1080|2160)p", flags: "iu" },
            { name: qsTr("Unicode words"), pattern: "\\p{L}+", flags: "gu" }
        ]
    }

    function saveLibrary() {
        Preferences.setValue("RegexBuilder/LibraryV2", JSON.stringify(library.slice(0, 32)))
        Preferences.apply()
    }

    function applyFlagString(flags) {
        flagG = flags.indexOf("g") >= 0
        flagI = flags.indexOf("i") >= 0
        flagM = flags.indexOf("m") >= 0
        flagS = flags.indexOf("s") >= 0
        flagU = flags.indexOf("u") >= 0
    }

    function copyValue(value) {
        clipboardHelper.text = value
        clipboardHelper.selectAll()
        clipboardHelper.copy()
    }

    Component.onCompleted: loadLibrary()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.lg
            spacing: Spacing.sm
            MDIcon { icon: Icons.settings_suggest; size: 22; color: Theme.color("primary") }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    text: qsTr("Regex Builder")
                    font: Typography.titleLarge
                    color: Theme.color("onSurface")
                }
                Label {
                    text: qsTr("Qt QRegularExpression · PCRE2 dialect")
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                }
            }
            HeaderIconButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                iconName: "close"
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.color("outlineVariant") }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(0, root.sheetWidth - Spacing.xl * 2)
                spacing: Spacing.md

                Item { Layout.preferredHeight: 1 }

                Label { text: qsTr("Raw pattern"); font: Typography.labelLarge }
                TextArea {
                    id: patternEditor
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    text: root.pattern
                    onTextChanged: {
                        if (text.length > 4096)
                            text = text.substring(0, 4096)
                        if (root.pattern !== text)
                            root.pattern = text
                    }
                    Accessible.name: qsTr("Raw regular expression")
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: Typography.monoFamily
                    placeholderText: qsTr("Compose a PCRE2-compatible pattern")
                }

                Label {
                    Layout.fillWidth: true
                    text: root.patternValid
                        ? qsTr("Valid · %1 match(es)%2").arg(root.evaluation.count)
                            .arg(root.evaluation.truncated ? qsTr(" · capped at 200") : "")
                        : qsTr("Invalid at %1: %2").arg(root.evaluation.errorOffset)
                            .arg(root.evaluation.error)
                    color: root.patternValid ? Theme.color("success") : Theme.color("error")
                    wrapMode: Text.WordWrap
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Spacing.xs
                    Repeater {
                        model: [
                            { key: "g", label: qsTr("all matches") },
                            { key: "i", label: qsTr("ignore case") },
                            { key: "m", label: qsTr("multiline") },
                            { key: "s", label: qsTr("dotall") },
                            { key: "u", label: qsTr("Unicode properties") }
                        ]
                        delegate: CheckBox {
                            required property var modelData
                            text: modelData.key + " · " + modelData.label
                            checked: root.flagStr.indexOf(modelData.key) >= 0
                            onToggled: {
                                if (modelData.key === "g") root.flagG = checked
                                else if (modelData.key === "i") root.flagI = checked
                                else if (modelData.key === "m") root.flagM = checked
                                else if (modelData.key === "s") root.flagS = checked
                                else root.flagU = checked
                            }
                        }
                    }
                }

                Label { text: qsTr("Guided construction"); font: Typography.labelLarge }
                Flow {
                    Layout.fillWidth: true
                    spacing: Spacing.xs
                    Repeater {
                        model: [
                            { label: qsTr("Literal"), token: "\\Qtext\\E", cursor: 2 },
                            { label: qsTr("Class"), token: "[A-Za-z0-9]", cursor: 1 },
                            { label: qsTr("Start"), token: "^" },
                            { label: qsTr("End"), token: "$" },
                            { label: qsTr("Capture"), token: "()", cursor: 1 },
                            { label: qsTr("Named capture"), token: "(?<name>)", cursor: 7 },
                            { label: qsTr("Alternation"), token: "(?:one|two)", cursor: 3 },
                            { label: qsTr("Optional"), token: "?" },
                            { label: qsTr("One or more"), token: "+" },
                            { label: qsTr("Zero or more"), token: "*" },
                            { label: qsTr("Count"), token: "{1,3}", cursor: 1 },
                            { label: qsTr("Unicode letter"), token: "\\p{L}" }
                        ]
                        delegate: Button {
                            required property var modelData
                            text: modelData.label
                            flat: true
                            onClicked: root.insertToken(modelData.token, modelData.cursor)
                        }
                    }
                }

                Label { text: qsTr("Editable sample text"); font: Typography.labelLarge }
                TextArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    text: root.sampleText
                    onTextChanged: {
                        if (text.length > 65536)
                            text = text.substring(0, 65536)
                        if (root.sampleText !== text)
                            root.sampleText = text
                    }
                    Accessible.name: qsTr("Regular-expression sample text")
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: matchesColumn.implicitHeight + Spacing.md * 2
                    radius: Spacing.radiusCard
                    color: Theme.color("surfaceVariant")

                    ColumnLayout {
                        id: matchesColumn
                        anchors.fill: parent
                        anchors.margins: Spacing.md
                        spacing: Spacing.xs
                        Label {
                            text: qsTr("Matches and capture groups")
                            font: Typography.labelLarge
                        }
                        Repeater {
                            model: root.evaluation.matches || []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("%1–%2 · %3")
                                        .arg(modelData.start)
                                        .arg(modelData.start + modelData.length)
                                        .arg(modelData.text.length ? modelData.text : qsTr("zero-width match"))
                                    font.family: Typography.monoFamily
                                    elide: Text.ElideRight
                                }
                                Repeater {
                                    model: modelData.captures || []
                                    delegate: Label {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: Spacing.md
                                        visible: modelData.index > 0
                                        text: modelData.index === 0 ? "" : qsTr("Capture %1%2: %3")
                                            .arg(modelData.index)
                                            .arg(modelData.name ? " · " + modelData.name : "")
                                            .arg(modelData.text)
                                        font: Typography.bodySmall
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Label {
                            visible: root.patternValid && root.evaluation.count === 0
                            text: qsTr("No matches in the sample.")
                            color: Theme.color("onSurfaceVariant")
                        }
                    }
                }

                Label { text: qsTr("Saved patterns"); font: Typography.labelLarge }
                Flow {
                    Layout.fillWidth: true
                    spacing: Spacing.xs
                    Repeater {
                        model: root.library
                        delegate: Button {
                            required property var modelData
                            required property int index
                            text: modelData.name
                            flat: true
                            onClicked: {
                                root.pattern = modelData.pattern
                                root.applyFlagString(modelData.flags || "gu")
                            }
                            onPressAndHold: {
                                root.library = root.library.filter(function(_, itemIndex) {
                                    return itemIndex !== index
                                })
                                root.saveLibrary()
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Click to load · press and hold to remove")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: qsTr("Preset name")
                        text: root.libraryName
                        onTextChanged: root.libraryName = text
                        maximumLength: 80
                    }
                    Button {
                        text: qsTr("Save preset")
                        enabled: root.patternValid && root.pattern.length > 0
                            && root.library.length < 32
                        onClicked: {
                            root.library = root.library.concat([{
                                name: root.libraryName.trim().length
                                    ? root.libraryName.trim()
                                    : qsTr("Pattern %1").arg(root.library.length + 1),
                                pattern: root.pattern,
                                flags: root.flagStr
                            }])
                            root.libraryName = ""
                            root.saveLibrary()
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Safety limits: 4,096 pattern characters, 64 KiB sample text, and 200 returned matches. Evaluation stays on this computer; zero-width matches are advanced safely by Qt.")
                    wrapMode: Text.WordWrap
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
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
                text: qsTr("Copy")
                flat: true
                onClicked: root.copyValue("/" + root.pattern + "/" + root.flagStr)
            }
            Button {
                text: qsTr("Copy JSON export")
                flat: true
                onClicked: root.copyValue(JSON.stringify({
                    dialect: "Qt QRegularExpression (PCRE2)",
                    pattern: root.pattern,
                    flags: root.flagStr,
                    sample: root.sampleText
                }, null, 2))
            }
            Item { Layout.fillWidth: true }
            Button {
                text: qsTr("Apply to search")
                highlighted: true
                enabled: root.patternValid
                onClicked: {
                    if (root.filterProxy) {
                        root.filterProxy.useRegex = true
                        root.filterProxy.textFilter = root.pattern
                    }
                    root.applyRequested(root.pattern, root.flagStr)
                    root.closeRequested()
                }
            }
        }
    }

    TextInput { id: clipboardHelper; visible: false; width: 0; height: 0 }
}
