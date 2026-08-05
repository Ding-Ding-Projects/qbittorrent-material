/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

Item {
    id: root

    required property string tabId
    required property string tabName
    required property string tabContent
    required property string fontFamily
    required property string fontStyle
    required property real fontPointSize
    required property bool bold
    required property bool italic
    required property string fontColor
    required property string groupId
    required property var appearance
    required property string updatedAt

    property bool initialized: false
    readonly property var effectiveAppearance: {
        // Reading these properties makes the binding refresh when a group or
        // global sparse override changes.
        var groupsRevision = WorkspaceManager.groups
        var globalValues = WorkspaceManager.globalAppearance || ({})
        var groupValues = groupId ? (WorkspaceManager.groupById(groupId).appearance || ({})) : ({})
        return Object.assign({}, globalValues, groupValues, appearance || ({}))
    }

    function capitalization(value) {
        // The appearance editor persists the Qt-facing AllUppercase and
        // AllLowercase names. Keep the shorter legacy spellings readable so
        // imported older workspace manifests remain compatible.
        if (value === "AllUppercase" || value === "Uppercase") return Font.AllUppercase
        if (value === "AllLowercase" || value === "Lowercase") return Font.AllLowercase
        if (value === "SmallCaps") return Font.SmallCaps
        if (value === "Capitalize") return Font.Capitalize
        return Font.MixedCase
    }

    function appearanceNumber(key, fallback) {
        var value = effectiveAppearance[key]
        if (value === undefined || value === null)
            return fallback
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : fallback
    }

    function alignment(value) {
        if (value === "Center") return Text.AlignHCenter
        if (value === "Right") return Text.AlignRight
        if (value === "Justify") return Text.AlignJustify
        return Text.AlignLeft
    }
    objectName: "workspacePage_" + tabId

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.lg
        spacing: Spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.md

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: root.tabName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font: Typography.headlineSmall
                    color: Theme.color("onSurface")
                    Layout.fillWidth: true
                }
                Label {
                    text: qsTr("%1 · %2 pt · %3%4")
                        .arg(root.fontFamily)
                        .arg(root.fontPointSize)
                        .arg(root.fontStyle)
                        .arg(root.bold ? qsTr(" · Bold") : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                radius: 7
                color: root.effectiveAppearance.textColor || root.fontColor
                border.width: 1
                border.color: Theme.color("outline")
                Accessible.name: qsTr("Page font color")
            }

            Label {
                text: !WorkspaceManager.writable
                    ? qsTr("Read only")
                    : (WorkspaceManager.dirty ? qsTr("Saving…") : qsTr("Saved"))
                font: Typography.labelSmall
                color: !WorkspaceManager.writable
                    ? Theme.color("error")
                    : (WorkspaceManager.dirty
                        ? Theme.color("primary") : Theme.color("onSurfaceVariant"))
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.effectiveAppearance.radius !== undefined
                ? root.effectiveAppearance.radius : Spacing.radiusDialog
            color: root.effectiveAppearance.backgroundColor || Theme.color("surface")
            opacity: root.effectiveAppearance.opacity !== undefined
                ? root.effectiveAppearance.opacity : 1
            border.width: root.effectiveAppearance.borderWidth !== undefined
                ? root.effectiveAppearance.borderWidth : 1
            border.color: editor.activeFocus
                ? (root.effectiveAppearance.focusColor || Theme.color("primary"))
                : (root.effectiveAppearance.borderColor || Theme.color("outlineVariant"))

            ScrollView {
                anchors.fill: parent
                anchors.margins: 1
                clip: true

                TextArea {
                    id: editor
                    objectName: "workspaceEditor_" + root.tabId
                    Accessible.name: qsTr("Page editor for %1").arg(root.tabName)
                    text: root.tabContent
                    textFormat: TextEdit.PlainText
                    readOnly: !WorkspaceManager.writable
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    // A sparse override may intentionally be zero. Do not use
                    // truthiness here, or an explicit zero padding silently
                    // turns back into the default spacing.
                    leftPadding: root.appearanceNumber("padding", Spacing.xl)
                    rightPadding: root.appearanceNumber("padding", Spacing.xl)
                    topPadding: root.appearanceNumber("padding", Spacing.lg)
                        + root.appearanceNumber("baselineOffset", 0)
                    bottomPadding: root.appearanceNumber("padding", Spacing.lg)
                    placeholderText: WorkspaceManager.writable
                        ? qsTr("Write anything on this page. Changes save automatically to local Git.")
                        : qsTr("Workspace recovery is required before this page can be edited.")
                    color: root.effectiveAppearance.textColor || root.fontColor
                    selectionColor: root.effectiveAppearance.highlightColor
                        || Theme.color("primaryContainer")
                    selectedTextColor: Theme.color("onPrimaryContainer")
                    readonly property font resolvedEditorFont: WorkspaceManager.resolvedFont(
                        root.effectiveAppearance.fontFamily || root.fontFamily,
                        root.effectiveAppearance.fontStyle || root.fontStyle,
                        root.effectiveAppearance.fontPointSize || root.fontPointSize,
                        root.effectiveAppearance.bold !== undefined
                            ? root.effectiveAppearance.bold : root.bold,
                        root.effectiveAppearance.italic !== undefined
                            ? root.effectiveAppearance.italic : root.italic)
                    font.family: resolvedEditorFont.family
                    font.styleName: resolvedEditorFont.styleName
                    font.pointSize: resolvedEditorFont.pointSize
                    font.italic: resolvedEditorFont.italic
                    font.weight: root.effectiveAppearance.fontWeight
                        || ((root.effectiveAppearance.bold !== undefined
                            ? root.effectiveAppearance.bold : root.bold)
                            ? Font.Bold : Font.Normal)
                    font.underline: !!root.effectiveAppearance.underline
                    font.strikeout: !!root.effectiveAppearance.strikeout
                        || !!root.effectiveAppearance.doubleStrike
                    font.overline: !!root.effectiveAppearance.overline
                    font.capitalization: root.capitalization(
                        root.effectiveAppearance.capitalization)
                    font.letterSpacing: root.effectiveAppearance.letterSpacing || 0
                    font.wordSpacing: root.effectiveAppearance.wordSpacing || 0
                    // Qt Quick Controls TextArea does not expose TextEdit's
                    // lineHeight properties on this Qt build. The editor keeps
                    // the saved value and explains the platform limitation in
                    // the appearance panel instead of crashing page creation.
                    horizontalAlignment: root.alignment(root.effectiveAppearance.alignment)
                    LayoutMirroring.enabled: root.effectiveAppearance.direction === "RightToLeft"
                    background: null

                    onTextChanged: {
                        if (!root.initialized)
                            return
                        if (text.length > 4 * 1024 * 1024) {
                            var preservedCursor = Math.min(cursorPosition, 4 * 1024 * 1024)
                            WorkspaceManager.setTabContent(root.tabId, text)
                            text = text.substring(0, 4 * 1024 * 1024)
                            cursorPosition = preservedCursor
                        }
                        if (text !== root.tabContent)
                            WorkspaceManager.setTabContent(root.tabId, text)
                    }
                    Component.onCompleted: root.initialized = true
                }
            }
        }
    }
}
