/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import QtQuick.Window
import qBittorrent

/*!
    \qmltype WorkspaceTabSettingsDialog
    \brief Anchored, non-modal appearance editor for workspace tabs and groups.

    The editor deliberately keeps target appearance maps sparse. The preview
    resolves global, group, and target values, while only controls the user
    touches become target overrides. This keeps inheritance useful and makes a
    per-property reset a real removal rather than another disguised default.
*/
Popup {
    id: root

    property int tabIndex: -1
    property string tabId: ""
    property string groupId: ""
    property string targetKind: "tab"
    property string targetName: ""
    property var targetData: ({})
    property var workingAppearance: ({})
    property Item anchorItem: null
    property Item returnFocusItem: null
    property bool loadingControls: false
    property var fontFamilyModel: []
    property string errorText: ""

    property string colorProperty: "textColor"
    property color selectedColor: "#FF6750A4"
    property real pickerHue: 0.75
    property real pickerSaturation: 0.55
    property real pickerValue: 0.65
    property real pickerAlpha: 1.0
    property bool updatingColor: false
    property bool parsingClipped: false
    property bool pendingClip: false
    property color pendingClippedColor: "transparent"
    property var recentColors: []

    readonly property var appearancePropertyModel: [
        { key: "fontFamily", label: qsTr("Font family") },
        { key: "fontStyle", label: qsTr("Font style") },
        { key: "fontPointSize", label: qsTr("Font size") },
        { key: "fontWeight", label: qsTr("Font weight") },
        { key: "bold", label: qsTr("Bold") },
        { key: "italic", label: qsTr("Italic") },
        { key: "underline", label: qsTr("Underline") },
        { key: "underlineStyle", label: qsTr("Underline style") },
        { key: "underlineColor", label: qsTr("Underline color") },
        { key: "strikeout", label: qsTr("Strikethrough") },
        { key: "doubleStrike", label: qsTr("Double strikethrough") },
        { key: "overline", label: qsTr("Overline") },
        { key: "capitalization", label: qsTr("Capitalization") },
        { key: "smallCaps", label: qsTr("Small caps") },
        { key: "superscript", label: qsTr("Superscript") },
        { key: "subscript", label: qsTr("Subscript") },
        { key: "textColor", label: qsTr("Text color") },
        { key: "highlightColor", label: qsTr("Highlight color") },
        { key: "outlineColor", label: qsTr("Outline color") },
        { key: "shadowColor", label: qsTr("Shadow color") },
        { key: "glowColor", label: qsTr("Glow color") },
        { key: "letterSpacing", label: qsTr("Character spacing") },
        { key: "wordSpacing", label: qsTr("Word spacing") },
        { key: "lineHeight", label: qsTr("Line height") },
        { key: "baselineOffset", label: qsTr("Baseline offset") },
        { key: "direction", label: qsTr("Text direction") },
        { key: "alignment", label: qsTr("Alignment") },
        { key: "backgroundColor", label: qsTr("Background color") },
        { key: "borderColor", label: qsTr("Border color") },
        { key: "borderWidth", label: qsTr("Border width") },
        { key: "radius", label: qsTr("Corner radius") },
        { key: "padding", label: qsTr("Padding") },
        { key: "spacing", label: qsTr("Spacing") },
        { key: "opacity", label: qsTr("Opacity") },
        { key: "icon", label: qsTr("Icon or emoji") },
        { key: "badge", label: qsTr("Badge") },
        { key: "separatorColor", label: qsTr("Separator color") },
        { key: "hoverColor", label: qsTr("Hover color") },
        { key: "focusColor", label: qsTr("Focus color") },
        { key: "checkedColor", label: qsTr("Checked color") },
        { key: "disabledColor", label: qsTr("Disabled color") }
    ]

    readonly property var colorPropertyModel: [
        { key: "textColor", label: qsTr("Text") },
        { key: "highlightColor", label: qsTr("Highlight") },
        { key: "underlineColor", label: qsTr("Underline") },
        { key: "outlineColor", label: qsTr("Outline") },
        { key: "shadowColor", label: qsTr("Shadow") },
        { key: "glowColor", label: qsTr("Glow") },
        { key: "backgroundColor", label: qsTr("Background") },
        { key: "borderColor", label: qsTr("Border") },
        { key: "separatorColor", label: qsTr("Separator") },
        { key: "hoverColor", label: qsTr("Hover state") },
        { key: "focusColor", label: qsTr("Focus state") },
        { key: "checkedColor", label: qsTr("Checked state") },
        { key: "disabledColor", label: qsTr("Disabled state") }
    ]

    readonly property var colorSpaceModel: [
        qsTr("HEX / HEX8"), qsTr("RGB / RGBA"), qsTr("HSL / HSLA"),
        qsTr("HSV / HSB"), qsTr("HWB"), qsTr("CIELAB"), qsTr("LCH"),
        qsTr("OKLab"), qsTr("OKLCH"), qsTr("CMYK"), qsTr("Named color")
    ]

    objectName: "workspaceTabSettingsDialog"
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: 0
    parent: Overlay.overlay
    width: Math.min(1040, Math.max(620, (parent ? parent.width : 1040) - Spacing.xl * 2))
    height: Math.min(820, Math.max(520, (parent ? parent.height : 820) - Spacing.xl * 2))
    Material.elevation: 16
    onClosed: {
        if (returnFocusItem)
            returnFocusItem.forceActiveFocus()
    }
    onWidthChanged: Qt.callLater(positionBesideAnchor)
    onHeightChanged: Qt.callLater(positionBesideAnchor)

    Timer {
        interval: 80
        running: root.visible && root.anchorItem !== null
        repeat: true
        onTriggered: root.positionBesideAnchor()
    }

    component SettingsCard: Rectangle {
        id: card
        default property alias contents: cardColumn.data
        property string title: ""
        property string subtitle: ""

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + Spacing.lg * 2
        radius: Spacing.radiusCard
        color: Theme.color("surfaceVariant")
        border.width: 1
        border.color: Theme.color("outlineVariant")

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Spacing.lg
            spacing: Spacing.sm

            Label {
                Layout.fillWidth: true
                text: card.title
                font: Typography.titleMedium
                color: Theme.color("onSurface")
            }
            Label {
                Layout.fillWidth: true
                visible: card.subtitle.length > 0
                text: card.subtitle
                wrapMode: Text.WordWrap
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
            }
        }
    }

    component SettingRow: RowLayout {
        id: settingRow
        default property alias controls: controlSlot.data
        property string title: ""
        property string description: ""
        property string searchTerms: title + " " + description

        Layout.fillWidth: true
        visible: root.matchesEditorSearch(searchTerms)
        spacing: Spacing.md

        ColumnLayout {
            Layout.preferredWidth: Math.min(240, root.width * 0.29)
            Layout.maximumWidth: 260
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: settingRow.title
                wrapMode: Text.WordWrap
                font: Typography.labelLarge
                color: Theme.color("onSurface")
            }
            Label {
                Layout.fillWidth: true
                visible: settingRow.description.length > 0
                text: settingRow.description
                wrapMode: Text.WordWrap
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
            }
        }
        RowLayout {
            id: controlSlot
            Layout.fillWidth: true
            spacing: Spacing.sm
        }
    }

    background: Rectangle {
        radius: root.numberValue(root.effectiveValue("radius"), Spacing.radiusDialog)
        color: Theme.color("surface")
        border.width: Math.max(1, root.numberValue(root.effectiveValue("borderWidth"), 1))
        border.color: root.colorValue(root.effectiveValue("borderColor"),
            Theme.color("outlineVariant"))
    }

    function copyMap(source) {
        var result = ({})
        if (!source)
            return result
        var keys = Object.keys(source)
        for (var i = 0; i < keys.length; ++i)
            result[keys[i]] = source[keys[i]]
        return result
    }

    function hasValue(map, key) {
        return map && map[key] !== undefined && map[key] !== null
    }

    function defaultAppearance() {
        var result = {
            fontFamily: Typography.family,
            fontStyle: "Regular",
            fontPointSize: 12,
            fontWeight: Font.Normal,
            bold: false,
            italic: false,
            underline: false,
            underlineStyle: "Single",
            underlineColor: Theme.color("onSurface"),
            strikeout: false,
            doubleStrike: false,
            overline: false,
            capitalization: "MixedCase",
            smallCaps: false,
            superscript: false,
            subscript: false,
            textColor: Theme.color("onSurface"),
            highlightColor: Theme.color("primaryContainer"),
            outlineColor: Theme.color("outline"),
            shadowColor: "#66000000",
            glowColor: "#006750A4",
            letterSpacing: 0,
            wordSpacing: 0,
            lineHeight: 1,
            baselineOffset: 0,
            direction: "Auto",
            alignment: "Left",
            backgroundColor: Theme.color("surface"),
            borderColor: Theme.color("outlineVariant"),
            borderWidth: 1,
            radius: Spacing.radiusCard,
            padding: Spacing.lg,
            spacing: Spacing.sm,
            opacity: 1,
            icon: "",
            badge: "",
            separatorColor: Theme.color("outlineVariant"),
            hoverColor: Theme.color("surfaceVariant"),
            focusColor: Theme.color("primary"),
            checkedColor: Theme.color("primaryContainer"),
            disabledColor: Theme.color("onSurfaceVariant")
        }
        if (targetKind === "tab" && targetData) {
            result.fontFamily = targetData.fontFamily || result.fontFamily
            result.fontStyle = targetData.fontStyle || result.fontStyle
            result.fontPointSize = targetData.fontPointSize || result.fontPointSize
            result.bold = !!targetData.bold
            result.italic = !!targetData.italic
            result.textColor = targetData.fontColor || result.textColor
        }
        return result
    }

    function inheritedAppearance() {
        var result = defaultAppearance()
        var globalValues = WorkspaceManager.globalAppearance || ({})
        var keys = Object.keys(globalValues)
        for (var i = 0; i < keys.length; ++i)
            result[keys[i]] = globalValues[keys[i]]
        if (targetKind === "tab" && targetData && targetData.groupId) {
            var group = WorkspaceManager.groupById(targetData.groupId)
            var groupValues = group && group.appearance ? group.appearance : ({})
            keys = Object.keys(groupValues)
            for (i = 0; i < keys.length; ++i)
                result[keys[i]] = groupValues[keys[i]]
        }
        return result
    }

    function effectiveAppearance() {
        var result = inheritedAppearance()
        var keys = Object.keys(workingAppearance || ({}))
        for (var i = 0; i < keys.length; ++i)
            result[keys[i]] = workingAppearance[keys[i]]
        return result
    }

    function effectiveValue(key) {
        var values = effectiveAppearance()
        return values[key]
    }

    function numberValue(value, fallback) {
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : fallback
    }

    function boolValue(value) {
        return value === true || value === "true" || value === 1
    }

    function setOverride(key, value) {
        if (loadingControls)
            return
        var next = copyMap(workingAppearance)
        next[key] = value
        workingAppearance = next
        errorText = ""
    }

    function removeOverride(key) {
        var next = copyMap(workingAppearance)
        delete next[key]
        workingAppearance = next
        refreshControls()
    }

    function overriddenCount() {
        return Object.keys(workingAppearance || ({})).length
    }

    function matchesEditorSearch(haystack) {
        var query = editorSearch ? editorSearch.text.trim() : ""
        if (!query.length)
            return true
        if (!editorSearch.regexEnabled)
            return String(haystack).toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
        if (!editorSearch.patternValid)
            return false
        var result = WorkspaceManager.evaluateRegularExpression(query,
            editorSearch.regexFlags, String(haystack))
        return result.valid && result.count > 0
    }

    function setComboText(combo, value) {
        var text = value === undefined || value === null ? "" : String(value)
        var index = combo.find(text)
        combo.currentIndex = index
        if (combo.editable && index < 0)
            combo.editText = text
    }

    function refreshControls() {
        loadingControls = true
        fontFamilyModel = WorkspaceManager.fontFamilies()
        setComboText(fontFamilyCombo, effectiveValue("fontFamily"))
        fontStyleCombo.model = WorkspaceManager.fontStyles(fontFamilyCombo.currentText)
        setComboText(fontStyleCombo, effectiveValue("fontStyle"))
        fontSizeSpin.value = Math.round(numberValue(effectiveValue("fontPointSize"), 12) * 10)
        fontWeightSpin.value = Math.round(numberValue(effectiveValue("fontWeight"), Font.Normal))
        boldCheck.checked = boolValue(effectiveValue("bold"))
        italicCheck.checked = boolValue(effectiveValue("italic"))
        underlineCheck.checked = boolValue(effectiveValue("underline"))
        setComboText(underlineStyleCombo, effectiveValue("underlineStyle"))
        strikeCheck.checked = boolValue(effectiveValue("strikeout"))
        doubleStrikeCheck.checked = boolValue(effectiveValue("doubleStrike"))
        overlineCheck.checked = boolValue(effectiveValue("overline"))
        setComboText(capitalizationCombo, effectiveValue("capitalization"))
        smallCapsCheck.checked = boolValue(effectiveValue("smallCaps"))
        superscriptCheck.checked = boolValue(effectiveValue("superscript"))
        subscriptCheck.checked = boolValue(effectiveValue("subscript"))
        letterSpacingSpin.value = Math.round(numberValue(effectiveValue("letterSpacing"), 0) * 100)
        wordSpacingSpin.value = Math.round(numberValue(effectiveValue("wordSpacing"), 0) * 100)
        lineHeightSpin.value = Math.round(numberValue(effectiveValue("lineHeight"), 1) * 100)
        baselineSpin.value = Math.round(numberValue(effectiveValue("baselineOffset"), 0) * 10)
        setComboText(directionCombo, effectiveValue("direction"))
        setComboText(alignmentCombo, effectiveValue("alignment"))
        borderWidthSpin.value = Math.round(numberValue(effectiveValue("borderWidth"), 1) * 10)
        radiusSpin.value = Math.round(numberValue(effectiveValue("radius"), Spacing.radiusCard) * 10)
        paddingSpin.value = Math.round(numberValue(effectiveValue("padding"), Spacing.lg) * 10)
        spacingSpin.value = Math.round(numberValue(effectiveValue("spacing"), Spacing.sm) * 10)
        opacitySpin.value = Math.round(numberValue(effectiveValue("opacity"), 1) * 100)
        iconField.text = String(effectiveValue("icon") || "")
        badgeField.text = String(effectiveValue("badge") || "")
        loadingControls = false
        loadColorProperty()
    }

    function reloadTarget() {
        if (targetKind === "tab") {
            targetData = WorkspaceManager.tabAt(tabIndex)
            workingAppearance = copyMap(targetData.appearance || ({}))
            tabNameField.text = targetData.name || ""
        }
        else if (targetKind === "group") {
            targetData = WorkspaceManager.groupById(groupId)
            workingAppearance = copyMap(targetData.appearance || ({}))
        }
        else {
            targetData = ({})
            workingAppearance = copyMap(WorkspaceManager.globalAppearance || ({}))
        }
        refreshControls()
    }

    function openForIndex(index, anchor) {
        if (!WorkspaceManager.writable)
            return
        var tab = WorkspaceManager.tabAt(index)
        if (!tab || !tab.tabId)
            return
        tabIndex = index
        tabId = tab.tabId
        groupId = ""
        targetKind = "tab"
        targetName = tab.name
        targetData = tab
        anchorItem = anchor || null
        returnFocusItem = anchor || null
        workingAppearance = copyMap(tab.appearance || ({}))
        tabNameField.text = tab.name
        editorSearch.clear()
        errorText = ""
        refreshControls()
        open()
        Qt.callLater(positionBesideAnchor)
    }

    function openForGroup(id, anchor) {
        if (!WorkspaceManager.writable)
            return
        var group = WorkspaceManager.groupById(id)
        if (!group || !group.groupId)
            return
        tabIndex = -1
        tabId = ""
        groupId = group.groupId
        targetKind = "group"
        targetName = group.name
        targetData = group
        anchorItem = anchor || null
        returnFocusItem = anchor || null
        workingAppearance = copyMap(group.appearance || ({}))
        editorSearch.clear()
        errorText = ""
        refreshControls()
        open()
        Qt.callLater(positionBesideAnchor)
    }

    function openForGlobal(anchor) {
        if (!WorkspaceManager.writable)
            return
        tabIndex = -1
        tabId = ""
        groupId = ""
        targetKind = "global"
        targetName = qsTr("Global workspace defaults")
        targetData = ({})
        anchorItem = anchor || null
        returnFocusItem = anchor || null
        workingAppearance = copyMap(WorkspaceManager.globalAppearance || ({}))
        editorSearch.clear()
        errorText = ""
        refreshControls()
        open()
        Qt.callLater(positionBesideAnchor)
    }

    function positionBesideAnchor() {
        if (!parent || !visible)
            return
        var margin = Spacing.md
        if (!anchorItem || !anchorItem.visible || !anchorItem.Window.window) {
            x = Math.max(margin, (parent.width - width) / 2)
            y = Math.max(margin, (parent.height - height) / 2)
            return
        }
        var right = anchorItem.mapToItem(parent, anchorItem.width + Spacing.sm, 0)
        var left = anchorItem.mapToItem(parent, -width - Spacing.sm, 0)
        var candidateX = right.x + width <= parent.width - margin ? right.x : left.x
        x = Math.max(margin, Math.min(parent.width - width - margin, candidateX))
        y = Math.max(margin, Math.min(parent.height - height - margin, right.y))
    }

    function persistAppearance() {
        if (targetKind === "tab")
            return WorkspaceManager.updateTabAppearance(tabId, workingAppearance)
        if (targetKind === "group")
            return WorkspaceManager.updateGroupAppearance(groupId, workingAppearance)
        return WorkspaceManager.updateGlobalAppearance(workingAppearance)
    }

    function applyChanges() {
        if (!WorkspaceManager.writable)
            return
        if (targetKind === "tab") {
            var name = tabNameField.text.trim()
            if (!name.length) {
                errorText = qsTr("Give the tab a name before applying.")
                tabNameField.forceActiveFocus()
                return
            }
            var effective = effectiveAppearance()
            var basicOk = WorkspaceManager.updateTab(tabId, name,
                String(effective.fontFamily), String(effective.fontStyle),
                numberValue(effective.fontPointSize, 12), boolValue(effective.bold),
                boolValue(effective.italic), colorHex(colorValue(effective.textColor,
                    Theme.color("onSurface"))))
            if (!basicOk) {
                errorText = qsTr("Check the tab name, font size, and text color.")
                return
            }
        }
        if (!persistAppearance()) {
            errorText = qsTr("The appearance could not be saved. The workspace may be read-only.")
            return
        }
        close()
    }

    function requestReset(scope) {
        resetConfirm.resetScope = scope
        resetConfirm.open()
    }

    function performReset(scope) {
        var ok = false
        if (scope === "global")
            ok = WorkspaceManager.resetGlobalAppearance()
        else if (targetKind === "tab")
            ok = WorkspaceManager.resetTabAppearance(tabId)
        else if (targetKind === "group")
            ok = WorkspaceManager.resetGroupAppearance(groupId)
        else
            ok = WorkspaceManager.resetGlobalAppearance()
        if (!ok) {
            errorText = qsTr("The reset could not be saved.")
            return
        }
        reloadTarget()
    }

    function resetSelectedProperty() {
        if (propertyResetCombo.currentIndex < 0)
            return
        removeOverride(appearancePropertyModel[propertyResetCombo.currentIndex].key)
    }

    function applySelectedPreset() {
        if (presetCombo.currentIndex < 0)
            return
        var preset = WorkspaceManager.appearancePresets[presetCombo.currentIndex]
        if (!preset || !preset.appearance)
            return
        workingAppearance = copyMap(preset.appearance)
        refreshControls()
    }

    function selectedPresetName() {
        if (presetCombo.currentIndex < 0)
            return ""
        var preset = WorkspaceManager.appearancePresets[presetCombo.currentIndex]
        return preset ? String(preset.name) : ""
    }

    function savePreset() {
        var name = presetNameField.text.trim()
        if (!name.length) {
            errorText = qsTr("Enter a name for the appearance preset.")
            presetNameField.forceActiveFocus()
            return
        }
        if (!WorkspaceManager.saveAppearancePreset(name, workingAppearance)) {
            errorText = qsTr("The preset could not be saved. At most 32 presets are supported.")
            return
        }
        errorText = ""
        presetNameField.text = ""
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function twoHex(value) {
        var result = Math.round(clamp(value, 0, 1) * 255).toString(16).toUpperCase()
        return result.length < 2 ? "0" + result : result
    }

    function colorHex(colorValue) {
        var color = colorValue || selectedColor
        return "#" + twoHex(color.a) + twoHex(color.r) + twoHex(color.g) + twoHex(color.b)
    }

    function parseHex(value) {
        var text = String(value).trim().toUpperCase()
        if (/^#[0-9A-F]{3}$/.test(text)) {
            return Qt.rgba(parseInt(text[1] + text[1], 16) / 255,
                parseInt(text[2] + text[2], 16) / 255,
                parseInt(text[3] + text[3], 16) / 255, 1)
        }
        if (/^#[0-9A-F]{6}$/.test(text))
            text = "#FF" + text.substring(1)
        if (!/^#[0-9A-F]{8}$/.test(text))
            return null
        return Qt.rgba(parseInt(text.substring(3, 5), 16) / 255,
            parseInt(text.substring(5, 7), 16) / 255,
            parseInt(text.substring(7, 9), 16) / 255,
            parseInt(text.substring(1, 3), 16) / 255)
    }

    function namedColors() {
        return {
            transparent: "#00000000", black: "#FF000000", white: "#FFFFFFFF",
            red: "#FFFF0000", lime: "#FF00FF00", blue: "#FF0000FF",
            yellow: "#FFFFFF00", cyan: "#FF00FFFF", aqua: "#FF00FFFF",
            magenta: "#FFFF00FF", fuchsia: "#FFFF00FF", gray: "#FF808080",
            grey: "#FF808080", orange: "#FFFFA500", purple: "#FF800080",
            pink: "#FFFFC0CB", brown: "#FFA52A2A", navy: "#FF000080",
            teal: "#FF008080", olive: "#FF808000", maroon: "#FF800000",
            silver: "#FFC0C0C0"
        }
    }

    function colorValue(value, fallback) {
        if (value && value.r !== undefined)
            return value
        var parsed = parseHex(value)
        if (parsed !== null)
            return parsed
        var names = namedColors()
        var named = names[String(value).trim().toLocaleLowerCase()]
        parsed = named ? parseHex(named) : null
        if (parsed !== null)
            return parsed
        if (fallback && fallback.r !== undefined)
            return fallback
        parsed = parseHex(fallback)
        return parsed !== null ? parsed : Qt.rgba(0, 0, 0, 1)
    }

    function rgbToHsv(color) {
        var maximum = Math.max(color.r, color.g, color.b)
        var minimum = Math.min(color.r, color.g, color.b)
        var delta = maximum - minimum
        var hue = 0
        if (delta > 0) {
            if (maximum === color.r)
                hue = ((color.g - color.b) / delta) % 6
            else if (maximum === color.g)
                hue = (color.b - color.r) / delta + 2
            else
                hue = (color.r - color.g) / delta + 4
            hue = ((hue * 60) + 360) % 360
        }
        return { h: hue, s: maximum === 0 ? 0 : delta / maximum,
            v: maximum, a: color.a }
    }

    function rgbToHsl(color) {
        var maximum = Math.max(color.r, color.g, color.b)
        var minimum = Math.min(color.r, color.g, color.b)
        var delta = maximum - minimum
        var lightness = (maximum + minimum) / 2
        var hue = 0
        if (delta > 0) {
            if (maximum === color.r)
                hue = ((color.g - color.b) / delta) % 6
            else if (maximum === color.g)
                hue = (color.b - color.r) / delta + 2
            else
                hue = (color.r - color.g) / delta + 4
            hue = ((hue * 60) + 360) % 360
        }
        var saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1))
        return { h: hue, s: saturation, l: lightness, a: color.a }
    }

    function srgbToLinear(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }

    function linearToSrgb(value) {
        return value <= 0.0031308 ? value * 12.92 : 1.055 * Math.pow(value, 1 / 2.4) - 0.055
    }

    function rgbToLab(color) {
        var r = srgbToLinear(color.r)
        var g = srgbToLinear(color.g)
        var b = srgbToLinear(color.b)
        var x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        var y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        var z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        var epsilon = 216 / 24389
        var kappa = 24389 / 27
        function f(t) { return t > epsilon ? Math.pow(t, 1 / 3) : (kappa * t + 16) / 116 }
        var fx = f(x), fy = f(y), fz = f(z)
        return { l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz), alpha: color.a }
    }

    function signedCubeRoot(value) {
        return value < 0 ? -Math.pow(-value, 1 / 3) : Math.pow(value, 1 / 3)
    }

    function rgbToOklab(color) {
        var r = srgbToLinear(color.r), g = srgbToLinear(color.g), b = srgbToLinear(color.b)
        var l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        var m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        var s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        l = signedCubeRoot(l); m = signedCubeRoot(m); s = signedCubeRoot(s)
        return {
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            alpha: color.a
        }
    }

    function makeRgb(red, green, blue, alpha) {
        if (red < 0 || red > 1 || green < 0 || green > 1 || blue < 0 || blue > 1
                || alpha < 0 || alpha > 1)
            parsingClipped = true
        return Qt.rgba(clamp(red, 0, 1), clamp(green, 0, 1), clamp(blue, 0, 1),
            clamp(alpha, 0, 1))
    }

    function labToRgb(lightness, greenRed, blueYellow, alpha) {
        var fy = (lightness + 16) / 116
        var fx = greenRed / 500 + fy
        var fz = fy - blueYellow / 200
        var epsilon = 216 / 24389
        var kappa = 24389 / 27
        function finv(t) {
            var cube = t * t * t
            return cube > epsilon ? cube : (116 * t - 16) / kappa
        }
        var x = 0.95047 * finv(fx)
        var y = finv(fy)
        var z = 1.08883 * finv(fz)
        var r = linearToSrgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
        var g = linearToSrgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
        var b = linearToSrgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
        return makeRgb(r, g, b, alpha)
    }

    function oklabToRgb(lightness, greenRed, blueYellow, alpha) {
        var l = lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow
        var m = lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow
        var s = lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow
        l = l * l * l; m = m * m * m; s = s * s * s
        var r = linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        var g = linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        var b = linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        return makeRgb(r, g, b, alpha)
    }

    function numbersIn(value) {
        var matches = String(value).match(/[-+]?(?:\d*\.?\d+)(?:[eE][-+]?\d+)?/g)
        if (!matches)
            return []
        var result = []
        for (var i = 0; i < matches.length; ++i)
            result.push(Number(matches[i]))
        return result
    }

    function fixed(value, digits) {
        var result = Number(value).toFixed(digits)
        return result.replace(/\.0+$|(?:(\.\d*?[1-9]))0+$/, "$1")
    }

    function nameForColor(color) {
        var hex = colorHex(color)
        var names = namedColors()
        var keys = Object.keys(names)
        for (var i = 0; i < keys.length; ++i) {
            if (names[keys[i]] === hex)
                return keys[i]
        }
        return ""
    }

    function formattedColor(index, color) {
        var hsv = rgbToHsv(color)
        var hsl = rgbToHsl(color)
        if (index === 0)
            return colorHex(color)
        if (index === 1)
            return "rgba(" + Math.round(color.r * 255) + ", " + Math.round(color.g * 255)
                + ", " + Math.round(color.b * 255) + ", " + fixed(color.a, 3) + ")"
        if (index === 2)
            return "hsla(" + fixed(hsl.h, 2) + ", " + fixed(hsl.s * 100, 2) + "%, "
                + fixed(hsl.l * 100, 2) + "%, " + fixed(color.a, 3) + ")"
        if (index === 3)
            return "hsva(" + fixed(hsv.h, 2) + ", " + fixed(hsv.s * 100, 2) + "%, "
                + fixed(hsv.v * 100, 2) + "%, " + fixed(color.a, 3) + ")"
        if (index === 4) {
            var white = Math.min(color.r, color.g, color.b)
            var black = 1 - Math.max(color.r, color.g, color.b)
            return "hwb(" + fixed(hsv.h, 2) + " " + fixed(white * 100, 2) + "% "
                + fixed(black * 100, 2) + "% / " + fixed(color.a, 3) + ")"
        }
        if (index === 5) {
            var lab = rgbToLab(color)
            return "lab(" + fixed(lab.l, 3) + " " + fixed(lab.a, 3) + " "
                + fixed(lab.b, 3) + " / " + fixed(color.a, 3) + ")"
        }
        if (index === 6) {
            lab = rgbToLab(color)
            var chroma = Math.sqrt(lab.a * lab.a + lab.b * lab.b)
            var angle = (Math.atan2(lab.b, lab.a) * 180 / Math.PI + 360) % 360
            return "lch(" + fixed(lab.l, 3) + " " + fixed(chroma, 3) + " "
                + fixed(angle, 3) + " / " + fixed(color.a, 3) + ")"
        }
        var oklab = rgbToOklab(color)
        if (index === 7)
            return "oklab(" + fixed(oklab.l, 5) + " " + fixed(oklab.a, 5) + " "
                + fixed(oklab.b, 5) + " / " + fixed(color.a, 3) + ")"
        if (index === 8) {
            chroma = Math.sqrt(oklab.a * oklab.a + oklab.b * oklab.b)
            angle = (Math.atan2(oklab.b, oklab.a) * 180 / Math.PI + 360) % 360
            return "oklch(" + fixed(oklab.l, 5) + " " + fixed(chroma, 5) + " "
                + fixed(angle, 3) + " / " + fixed(color.a, 3) + ")"
        }
        if (index === 9) {
            var k = 1 - Math.max(color.r, color.g, color.b)
            var c = k >= 0.999999 ? 0 : (1 - color.r - k) / (1 - k)
            var m = k >= 0.999999 ? 0 : (1 - color.g - k) / (1 - k)
            var y = k >= 0.999999 ? 0 : (1 - color.b - k) / (1 - k)
            return "cmyka(" + fixed(c * 100, 2) + "%, " + fixed(m * 100, 2) + "%, "
                + fixed(y * 100, 2) + "%, " + fixed(k * 100, 2) + "%, "
                + fixed(color.a, 3) + ")"
        }
        var name = nameForColor(color)
        return name.length ? name : qsTr("custom (%1)").arg(colorHex(color))
    }

    function parsedFormattedColor(index, value) {
        parsingClipped = false
        var values = numbersIn(value)
        if (index === 0)
            return parseHex(value)
        if (index === 10) {
            var name = String(value).trim().toLocaleLowerCase()
            var names = namedColors()
            return names[name] ? parseHex(names[name]) : null
        }
        if (index === 1 && values.length >= 3)
            return makeRgb(values[0] / 255, values[1] / 255, values[2] / 255,
                values.length >= 4 ? values[3] : 1)
        if (index === 2 && values.length >= 3)
            return Qt.hsla(((values[0] % 360) + 360) % 360 / 360,
                clamp(values[1] / 100, 0, 1), clamp(values[2] / 100, 0, 1),
                clamp(values.length >= 4 ? values[3] : 1, 0, 1))
        if (index === 3 && values.length >= 3)
            return Qt.hsva(((values[0] % 360) + 360) % 360 / 360,
                clamp(values[1] / 100, 0, 1), clamp(values[2] / 100, 0, 1),
                clamp(values.length >= 4 ? values[3] : 1, 0, 1))
        if (index === 4 && values.length >= 3) {
            var hue = ((values[0] % 360) + 360) % 360 / 360
            var white = Math.max(0, values[1] / 100)
            var black = Math.max(0, values[2] / 100)
            var sum = white + black
            if (sum > 1) { white /= sum; black /= sum; parsingClipped = true }
            var pure = Qt.hsva(hue, 1, 1, 1)
            var factor = 1 - white - black
            return makeRgb(pure.r * factor + white, pure.g * factor + white,
                pure.b * factor + white, values.length >= 4 ? values[3] : 1)
        }
        if (index === 5 && values.length >= 3)
            return labToRgb(values[0], values[1], values[2], values.length >= 4 ? values[3] : 1)
        if (index === 6 && values.length >= 3) {
            var radians = values[2] * Math.PI / 180
            return labToRgb(values[0], values[1] * Math.cos(radians),
                values[1] * Math.sin(radians), values.length >= 4 ? values[3] : 1)
        }
        if (index === 7 && values.length >= 3)
            return oklabToRgb(values[0], values[1], values[2], values.length >= 4 ? values[3] : 1)
        if (index === 8 && values.length >= 3) {
            radians = values[2] * Math.PI / 180
            return oklabToRgb(values[0], values[1] * Math.cos(radians),
                values[1] * Math.sin(radians), values.length >= 4 ? values[3] : 1)
        }
        if (index === 9 && values.length >= 4) {
            var c = values[0] / 100, m = values[1] / 100
            var y = values[2] / 100, k = values[3] / 100
            return makeRgb((1 - c) * (1 - k), (1 - m) * (1 - k),
                (1 - y) * (1 - k), values.length >= 5 ? values[4] : 1)
        }
        return null
    }

    function updateColorText() {
        if (!colorFormatField)
            return
        updatingColor = true
        colorFormatField.text = formattedColor(colorSpaceCombo.currentIndex, selectedColor)
        colorHexField.text = colorHex(selectedColor)
        updatingColor = false
    }

    function setPickerColor(color, createOverride) {
        updatingColor = true
        selectedColor = color
        var hsv = rgbToHsv(color)
        if (hsv.s > 0)
            pickerHue = hsv.h / 360
        pickerSaturation = hsv.s
        pickerValue = hsv.v
        pickerAlpha = color.a
        updatingColor = false
        updateColorText()
        if (createOverride)
            setOverride(colorProperty, colorHex(color))
    }

    function setPickerHsva(hue, saturation, value, alpha, createOverride) {
        pickerHue = ((hue % 1) + 1) % 1
        pickerSaturation = clamp(saturation, 0, 1)
        pickerValue = clamp(value, 0, 1)
        pickerAlpha = clamp(alpha, 0, 1)
        setPickerColor(Qt.hsva(pickerHue, pickerSaturation, pickerValue, pickerAlpha),
            createOverride)
    }

    function loadColorProperty() {
        var value = effectiveValue(colorProperty)
        setPickerColor(colorValue(value, Theme.color("primary")), false)
        pendingClip = false
        colorError.text = ""
    }

    function acceptFormattedColor() {
        if (updatingColor)
            return
        var parsed = parsedFormattedColor(colorSpaceCombo.currentIndex, colorFormatField.text)
        if (parsed === null) {
            colorError.text = qsTr("That value is not valid in the selected color space.")
            return
        }
        if (parsingClipped) {
            pendingClippedColor = parsed
            pendingClip = true
            colorError.text = qsTr("This value is outside sRGB. Review it, then choose Clip and apply.")
            return
        }
        pendingClip = false
        colorError.text = ""
        setPickerColor(parsed, true)
        addRecentColor(parsed)
    }

    function acceptClippedColor() {
        pendingClip = false
        colorError.text = qsTr("The out-of-gamut channels were clipped to sRGB.")
        setPickerColor(pendingClippedColor, true)
        addRecentColor(pendingClippedColor)
    }

    function addRecentColor(color) {
        var hex = colorHex(color)
        var next = []
        next.push(hex)
        for (var i = 0; i < recentColors.length && next.length < 8; ++i)
            if (recentColors[i] !== hex) next.push(recentColors[i])
        recentColors = next
    }

    function relativeLuminance(color) {
        return 0.2126 * srgbToLinear(color.r) + 0.7152 * srgbToLinear(color.g)
            + 0.0722 * srgbToLinear(color.b)
    }

    function contrastBackground() {
        if (colorProperty === "backgroundColor")
            return colorValue(Theme.color("surface"), Qt.rgba(1, 1, 1, 1))
        return colorValue(effectiveValue("backgroundColor"), Theme.color("surface"))
    }

    function contrastRatio() {
        var background = contrastBackground()
        var foreground = selectedColor
        var composite = Qt.rgba(foreground.r * foreground.a + background.r * (1 - foreground.a),
            foreground.g * foreground.a + background.g * (1 - foreground.a),
            foreground.b * foreground.a + background.b * (1 - foreground.a), 1)
        var first = relativeLuminance(composite)
        var second = relativeLuminance(background)
        return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
    }

    function capitalizationValue(value) {
        if (value === "AllUppercase") return Font.AllUppercase
        if (value === "AllLowercase") return Font.AllLowercase
        if (value === "SmallCaps") return Font.SmallCaps
        if (value === "Capitalize") return Font.Capitalize
        return Font.MixedCase
    }

    function alignmentValue(value) {
        if (value === "Center") return Text.AlignHCenter
        if (value === "Right") return Text.AlignRight
        if (value === "Justify") return Text.AlignJustify
        return Text.AlignLeft
    }

    contentItem: ColumnLayout {
        spacing: 0
        Accessible.name: root.targetKind === "group"
            ? qsTr("Appearance editor for tab group %1").arg(root.targetName)
            : qsTr("Appearance editor for tab %1").arg(root.targetName)
        Accessible.role: Accessible.Dialog

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Spacing.xl
            Layout.rightMargin: Spacing.sm
            Layout.topMargin: Spacing.md
            Layout.bottomMargin: Spacing.md
            spacing: Spacing.md

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 21
                color: Theme.color("primaryContainer")
                MDIcon {
                    anchors.centerIn: parent
                    icon: Icons.palette
                    size: 22
                    color: Theme.color("onPrimaryContainer")
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: root.targetKind === "group"
                        ? qsTr("Edit group appearance · %1").arg(root.targetName)
                        : (root.targetKind === "global" ? root.targetName
                            : qsTr("Edit tab appearance · %1").arg(root.targetName))
                    elide: Text.ElideRight
                    font: Typography.titleLarge
                    color: Theme.color("onSurface")
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("%1 explicit override(s) · inherited values remain live")
                        .arg(root.overriddenCount())
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                }
            }
            IconButton {
                symbol: Icons.close
                tooltip: qsTr("Close and return to the edited element")
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.color("outlineVariant")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            spacing: Spacing.sm

            FilterTextField {
                id: editorSearch
                objectName: "workspaceAppearanceSearchField"
                Layout.fillWidth: true
                placeholder: qsTr("Search appearance properties")
                builderTitle: qsTr("Appearance-editor Regex Builder")
                builderSampleText: root.appearancePropertyModel.map(function(item) {
                    return item.label + " · " + item.key
                }).join("\n")
            }
            Button {
                text: qsTr("Global defaults")
                flat: true
                visible: root.targetKind !== "global"
                Accessible.description: qsTr("Open the global appearance editor without closing this workspace")
                onClicked: root.openForGlobal(this)
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.max(0, root.width - Spacing.xl * 2)
                spacing: Spacing.lg

                Item { Layout.preferredHeight: 1 }

                SettingsCard {
                    title: qsTr("Target and overrides")
                    subtitle: qsTr("Only changed properties are stored on this %1. Resetting one property reveals its inherited value again.")
                        .arg(root.targetKind)
                    visible: root.matchesEditorSearch("target tab group name overrides reset property inherited global")

                    SettingRow {
                        title: qsTr("Tab name")
                        description: qsTr("The visible label; this is content metadata, not an appearance override.")
                        searchTerms: "tab name title label rename"
                        visible: root.targetKind === "tab" && root.matchesEditorSearch(searchTerms)
                        TextField {
                            id: tabNameField
                            objectName: "workspaceTabNameField"
                            Layout.fillWidth: true
                            Accessible.name: qsTr("Tab name")
                            placeholderText: qsTr("Tab name")
                            maximumLength: 120
                            selectByMouse: true
                        }
                    }
                    SettingRow {
                        title: qsTr("Per-property reset")
                        description: qsTr("Remove one explicit override without touching the others.")
                        searchTerms: "property reset inherit override"
                        ComboBox {
                            id: propertyResetCombo
                            Layout.fillWidth: true
                            model: root.appearancePropertyModel
                            textRole: "label"
                            Accessible.name: qsTr("Appearance property to reset")
                        }
                        Button {
                            text: qsTr("Reset property")
                            enabled: propertyResetCombo.currentIndex >= 0
                                && root.hasValue(root.workingAppearance,
                                    root.appearancePropertyModel[propertyResetCombo.currentIndex].key)
                            onClicked: root.resetSelectedProperty()
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Typeface and emphasis")
                    subtitle: qsTr("Installed families are previewed in their own face. Family, style, free-entry size, weight, and emphasis remain independently adjustable.")
                    visible: root.matchesEditorSearch("typeface typography font family style size weight bold italic")

                    SettingRow {
                        title: qsTr("Font family")
                        description: qsTr("Installed and bundled fonts; CJK fallback is retained by Qt.")
                        searchTerms: "font family installed bundled CJK typeface"
                        ComboBox {
                            id: fontFamilyCombo
                            objectName: "workspaceFontFamilyCombo"
                            Layout.fillWidth: true
                            model: root.fontFamilyModel
                            editable: true
                            Accessible.name: qsTr("Font family")
                            delegate: ItemDelegate {
                                required property var modelData
                                width: ListView.view ? ListView.view.width : fontFamilyCombo.width
                                text: String(modelData)
                                font.family: String(modelData)
                            }
                            onActivated: {
                                if (root.loadingControls) return
                                root.setOverride("fontFamily", currentText.trim())
                                fontStyleCombo.model = WorkspaceManager.fontStyles(currentText)
                                fontStyleCombo.currentIndex = 0
                                root.setOverride("fontStyle", fontStyleCombo.currentText)
                            }
                            onAccepted: {
                                if (root.loadingControls) return
                                root.setOverride("fontFamily", currentText.trim())
                                fontStyleCombo.model = WorkspaceManager.fontStyles(currentText)
                                fontStyleCombo.currentIndex = 0
                                root.setOverride("fontStyle", fontStyleCombo.currentText)
                            }
                        }
                    }
                    SettingRow {
                        title: qsTr("Font style")
                        description: qsTr("Styles reported by the selected font family.")
                        searchTerms: "font style regular oblique italic family"
                        ComboBox {
                            id: fontStyleCombo
                            objectName: "workspaceFontStyleCombo"
                            Layout.fillWidth: true
                            Accessible.name: qsTr("Font style")
                            onActivated: root.setOverride("fontStyle", currentText)
                        }
                    }
                    SettingRow {
                        title: qsTr("Font size")
                        description: qsTr("Free entry plus 0.5 pt steps, from 6 to 144 pt.")
                        searchTerms: "font size point pt free entry stepper"
                        SpinBox {
                            id: fontSizeSpin
                            objectName: "workspaceFontSizeSpinBox"
                            Layout.fillWidth: true
                            from: 60
                            to: 1440
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Font size in points")
                            textFromValue: function(value, locale) {
                                return Number(value / 10).toLocaleString(locale, "f", 1) + " pt"
                            }
                            valueFromText: function(text, locale) {
                                return Math.round(Number.fromLocaleString(locale,
                                    text.replace(/[^0-9.,-]/g, "")) * 10)
                            }
                            onValueModified: root.setOverride("fontPointSize", value / 10)
                        }
                    }
                    SettingRow {
                        title: qsTr("Weight and emphasis")
                        description: qsTr("Numeric OpenType weight remains separate from bold and italic switches.")
                        searchTerms: "font weight bold italic emphasis variable axis OpenType"
                        SpinBox {
                            id: fontWeightSpin
                            Layout.fillWidth: true
                            from: 1
                            to: 1000
                            stepSize: 10
                            editable: true
                            Accessible.name: qsTr("Numeric font weight")
                            onValueModified: root.setOverride("fontWeight", value)
                        }
                        CheckBox {
                            id: boldCheck
                            objectName: "workspaceBoldButton"
                            text: qsTr("Bold")
                            font.bold: true
                            onToggled: root.setOverride("bold", checked)
                        }
                        CheckBox {
                            id: italicCheck
                            objectName: "workspaceItalicButton"
                            text: qsTr("Italic")
                            font.italic: true
                            onToggled: root.setOverride("italic", checked)
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Lines, case, and script")
                    subtitle: qsTr("Every property stays visible. The capability note below identifies effects Qt Quick approximates on this surface.")
                    visible: root.matchesEditorSearch("underline strikethrough overline capitalization caps superscript subscript")

                    SettingRow {
                        title: qsTr("Underline")
                        description: qsTr("Enable it and choose a stored line style; color is edited in the color studio.")
                        searchTerms: "underline single double dash dot wave color style"
                        CheckBox {
                            id: underlineCheck
                            text: qsTr("Underline")
                            onToggled: root.setOverride("underline", checked)
                        }
                        ComboBox {
                            id: underlineStyleCombo
                            Layout.fillWidth: true
                            model: ["Single", "Double", "Dash", "Dot", "DashDot", "Wave"]
                            Accessible.name: qsTr("Underline style")
                            onActivated: root.setOverride("underlineStyle", currentText)
                        }
                    }
                    SettingRow {
                        title: qsTr("Strikethrough and overline")
                        description: qsTr("Single, double, and overline values are stored independently.")
                        searchTerms: "strike strikethrough double overline line"
                        CheckBox {
                            id: strikeCheck
                            text: qsTr("Strike")
                            onToggled: root.setOverride("strikeout", checked)
                        }
                        CheckBox {
                            id: doubleStrikeCheck
                            text: qsTr("Double strike")
                            onToggled: root.setOverride("doubleStrike", checked)
                        }
                        CheckBox {
                            id: overlineCheck
                            text: qsTr("Overline")
                            onToggled: root.setOverride("overline", checked)
                        }
                    }
                    SettingRow {
                        title: qsTr("Capitalization")
                        description: qsTr("Mixed case, uppercase, lowercase, title capitalization, or small caps.")
                        searchTerms: "capitalization uppercase lowercase title small caps case"
                        ComboBox {
                            id: capitalizationCombo
                            Layout.fillWidth: true
                            model: ["MixedCase", "AllUppercase", "AllLowercase", "Capitalize", "SmallCaps"]
                            Accessible.name: qsTr("Capitalization")
                            onActivated: root.setOverride("capitalization", currentText)
                        }
                        CheckBox {
                            id: smallCapsCheck
                            text: qsTr("Small caps feature")
                            onToggled: root.setOverride("smallCaps", checked)
                        }
                    }
                    SettingRow {
                        title: qsTr("Script position")
                        description: qsTr("Superscript and subscript are mutually exclusive.")
                        searchTerms: "superscript subscript baseline script position"
                        CheckBox {
                            id: superscriptCheck
                            text: qsTr("Superscript")
                            onToggled: {
                                if (root.loadingControls) return
                                if (checked && subscriptCheck.checked) {
                                    subscriptCheck.checked = false
                                    root.setOverride("subscript", false)
                                }
                                root.setOverride("superscript", checked)
                            }
                        }
                        CheckBox {
                            id: subscriptCheck
                            text: qsTr("Subscript")
                            onToggled: {
                                if (root.loadingControls) return
                                if (checked && superscriptCheck.checked) {
                                    superscriptCheck.checked = false
                                    root.setOverride("superscript", false)
                                }
                                root.setOverride("subscript", checked)
                            }
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Spacing, direction, and alignment")
                    subtitle: qsTr("Character, word, and line metrics are independent; direction and alignment are explicit and persisted.")
                    visible: root.matchesEditorSearch("spacing character word line height baseline direction alignment left right justify")

                    SettingRow {
                        title: qsTr("Character and word spacing")
                        description: qsTr("Values are pixels and accept hundredth-pixel steps.")
                        searchTerms: "character letter word spacing tracking kerning"
                        SpinBox {
                            id: letterSpacingSpin
                            Layout.fillWidth: true
                            from: -10000
                            to: 10000
                            stepSize: 10
                            editable: true
                            Accessible.name: qsTr("Character spacing in pixels")
                            textFromValue: function(value) { return root.fixed(value / 100, 2) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 100) }
                            onValueModified: root.setOverride("letterSpacing", value / 100)
                        }
                        SpinBox {
                            id: wordSpacingSpin
                            Layout.fillWidth: true
                            from: -10000
                            to: 10000
                            stepSize: 10
                            editable: true
                            Accessible.name: qsTr("Word spacing in pixels")
                            textFromValue: function(value) { return root.fixed(value / 100, 2) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 100) }
                            onValueModified: root.setOverride("wordSpacing", value / 100)
                        }
                    }
                    SettingRow {
                        title: qsTr("Line height and baseline")
                        description: qsTr("Line height is proportional; baseline offset is measured in pixels.")
                        searchTerms: "line height leading baseline offset vertical"
                        SpinBox {
                            id: lineHeightSpin
                            Layout.fillWidth: true
                            from: 50
                            to: 500
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Proportional line height")
                            textFromValue: function(value) { return root.fixed(value / 100, 2) + "×" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 100) }
                            onValueModified: root.setOverride("lineHeight", value / 100)
                        }
                        SpinBox {
                            id: baselineSpin
                            Layout.fillWidth: true
                            from: -500
                            to: 500
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Baseline offset in pixels")
                            textFromValue: function(value) { return root.fixed(value / 10, 1) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 10) }
                            onValueModified: root.setOverride("baselineOffset", value / 10)
                        }
                    }
                    SettingRow {
                        title: qsTr("Direction and alignment")
                        description: qsTr("Auto, left-to-right, or right-to-left; align left, center, right, or justify.")
                        searchTerms: "direction LTR RTL auto alignment left center right justify"
                        ComboBox {
                            id: directionCombo
                            Layout.fillWidth: true
                            model: ["Auto", "LeftToRight", "RightToLeft"]
                            Accessible.name: qsTr("Text direction")
                            onActivated: root.setOverride("direction", currentText)
                        }
                        ComboBox {
                            id: alignmentCombo
                            Layout.fillWidth: true
                            model: ["Left", "Center", "Right", "Justify"]
                            Accessible.name: qsTr("Text alignment")
                            onActivated: root.setOverride("alignment", currentText)
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Infinite color studio")
                    subtitle: qsTr("A continuous sRGB picker with alpha, bidirectional color-space translation, contrast evidence, clipping review, swatches, and recent colors.")
                    visible: root.matchesEditorSearch("color palette spectrum hue saturation value alpha HEX RGB HSL HSV HWB Lab LCH OKLab OKLCH CMYK contrast gamut clipping")

                    SettingRow {
                        title: qsTr("Appearance color")
                        description: qsTr("Choose which foreground, surface, effect, or interaction-state color to edit.")
                        searchTerms: "text highlight underline outline shadow glow background border separator hover focus checked disabled color"
                        ComboBox {
                            id: colorTargetCombo
                            Layout.fillWidth: true
                            model: root.colorPropertyModel
                            textRole: "label"
                            Accessible.name: qsTr("Appearance color property")
                            onActivated: {
                                root.colorProperty = root.colorPropertyModel[currentIndex].key
                                root.loadColorProperty()
                            }
                        }
                        Button {
                            text: qsTr("Reset this color")
                            enabled: root.hasValue(root.workingAppearance, root.colorProperty)
                            onClicked: root.removeOverride(root.colorProperty)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumHeight: 250
                        spacing: Spacing.md

                        ColumnLayout {
                            Layout.preferredWidth: 390
                            Layout.fillHeight: true
                            spacing: Spacing.sm

                            Rectangle {
                                id: saturationValueField
                                objectName: "workspaceColorButton"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 210
                                color: Qt.hsva(root.pickerHue, 1, 1, 1)
                                radius: Spacing.radiusControl
                                clip: true
                                border.width: 1
                                border.color: Theme.color("outline")
                                Accessible.name: qsTr("Two-dimensional saturation and value picker")
                                Accessible.description: qsTr("Horizontal axis controls saturation; vertical axis controls brightness")

                                Rectangle {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "white" }
                                        GradientStop { position: 1; color: "transparent" }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "transparent" }
                                        GradientStop { position: 1; color: "black" }
                                    }
                                }
                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    x: root.pickerSaturation * saturationValueField.width - width / 2
                                    y: (1 - root.pickerValue) * saturationValueField.height - height / 2
                                    color: "transparent"
                                    border.width: 3
                                    border.color: root.contrastRatio() >= 3 ? "white" : "black"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    function selectAt(mouse) {
                                        root.setPickerHsva(root.pickerHue,
                                            root.clamp(mouse.x / width, 0, 1),
                                            1 - root.clamp(mouse.y / height, 0, 1),
                                            root.pickerAlpha, true)
                                    }
                                    onPressed: function(mouse) { selectAt(mouse) }
                                    onPositionChanged: function(mouse) { if (pressed) selectAt(mouse) }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: qsTr("Hue"); font: Typography.labelMedium }
                                Slider {
                                    id: hueSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 360
                                    value: root.pickerHue * 360
                                    Accessible.name: qsTr("Hue in degrees")
                                    onMoved: root.setPickerHsva(value / 360, root.pickerSaturation,
                                        root.pickerValue, root.pickerAlpha, true)
                                    background: Rectangle {
                                        x: hueSlider.leftPadding
                                        y: hueSlider.topPadding + hueSlider.availableHeight / 2 - height / 2
                                        width: hueSlider.availableWidth
                                        height: 8
                                        radius: 4
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.00; color: "#FFFF0000" }
                                            GradientStop { position: 0.17; color: "#FFFFFF00" }
                                            GradientStop { position: 0.33; color: "#FF00FF00" }
                                            GradientStop { position: 0.50; color: "#FF00FFFF" }
                                            GradientStop { position: 0.67; color: "#FF0000FF" }
                                            GradientStop { position: 0.83; color: "#FFFF00FF" }
                                            GradientStop { position: 1.00; color: "#FFFF0000" }
                                        }
                                    }
                                }
                                Label { text: Math.round(hueSlider.value) + "°"; font: Typography.labelMedium }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: qsTr("Alpha"); font: Typography.labelMedium }
                                Slider {
                                    id: alphaSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 100
                                    value: root.pickerAlpha * 100
                                    Accessible.name: qsTr("Alpha opacity percentage")
                                    onMoved: root.setPickerHsva(root.pickerHue, root.pickerSaturation,
                                        root.pickerValue, value / 100, true)
                                }
                                Label { text: Math.round(alphaSlider.value) + "%"; font: Typography.labelMedium }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Spacing.sm

                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 46
                                    radius: Spacing.radiusChip
                                    color: root.selectedColor
                                    border.width: 1
                                    border.color: Theme.color("outline")
                                    Accessible.name: qsTr("Selected color %1").arg(root.colorHex(root.selectedColor))
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        text: root.colorPropertyModel[colorTargetCombo.currentIndex]
                                            ? root.colorPropertyModel[colorTargetCombo.currentIndex].label : ""
                                        font: Typography.titleSmall
                                    }
                                    Label {
                                        text: qsTr("sRGB gamut · alpha preserved")
                                        font: Typography.bodySmall
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                }
                            }

                            ComboBox {
                                id: colorSpaceCombo
                                Layout.fillWidth: true
                                model: root.colorSpaceModel
                                Accessible.name: qsTr("Color translation space")
                                onActivated: root.updateColorText()
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                TextField {
                                    id: colorFormatField
                                    objectName: "workspaceColorHexField"
                                    Layout.fillWidth: true
                                    selectByMouse: true
                                    maximumLength: 160
                                    Accessible.name: qsTr("Editable color value in the selected color space")
                                    onAccepted: root.acceptFormattedColor()
                                }
                                IconButton {
                                    symbol: Icons.content_copy
                                    tooltip: qsTr("Copy this color representation")
                                    onClicked: {
                                        clipboardHelper.text = colorFormatField.text
                                        clipboardHelper.selectAll()
                                        clipboardHelper.copy()
                                    }
                                }
                            }
                            TextField {
                                id: colorHexField
                                visible: false
                                maximumLength: 9
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Button {
                                    text: root.pendingClip ? qsTr("Review value") : qsTr("Apply translated value")
                                    enabled: !root.pendingClip
                                    onClicked: root.acceptFormattedColor()
                                }
                                Button {
                                    visible: root.pendingClip
                                    text: qsTr("Clip and apply")
                                    highlighted: true
                                    onClicked: root.acceptClippedColor()
                                }
                            }
                            Label {
                                id: colorError
                                Layout.fillWidth: true
                                visible: text.length > 0
                                wrapMode: Text.WordWrap
                                color: root.pendingClip ? Theme.color("error") : Theme.color("onSurfaceVariant")
                                font: Typography.bodySmall
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: contrastColumn.implicitHeight + Spacing.md * 2
                                radius: Spacing.radiusControl
                                color: Theme.color("surface")
                                border.width: 1
                                border.color: root.contrastRatio() >= 4.5
                                    ? Theme.color("primary") : Theme.color("error")
                                ColumnLayout {
                                    id: contrastColumn
                                    anchors.fill: parent
                                    anchors.margins: Spacing.md
                                    Label {
                                        text: qsTr("Contrast %1:1 · %2")
                                            .arg(root.fixed(root.contrastRatio(), 2))
                                            .arg(root.contrastRatio() >= 7 ? qsTr("AAA")
                                                : (root.contrastRatio() >= 4.5 ? qsTr("AA")
                                                    : qsTr("below AA for normal text")))
                                        font: Typography.labelLarge
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: qsTr("Measured against the current background after alpha compositing. Wide-gamut input is reviewed before sRGB clipping.")
                                        wrapMode: Text.WordWrap
                                        font: Typography.bodySmall
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Repeater {
                            model: ["#FF000000", "#FFFFFFFF", "#FF6750A4", "#FFFF0000",
                                "#FFFFA500", "#FFFFFF00", "#FF00AA55", "#FF0088FF",
                                "#FF0000FF", "#FF800080", "#FFFF00FF", "#00000000"]
                            delegate: Rectangle {
                                required property string modelData
                                width: 34
                                height: 34
                                radius: 17
                                color: modelData
                                border.width: 1
                                border.color: Theme.color("outline")
                                Accessible.name: qsTr("Color swatch %1").arg(modelData)
                                TapHandler {
                                    onTapped: {
                                        var parsed = root.parseHex(parent.modelData)
                                        root.setPickerColor(parsed, true)
                                        root.addRecentColor(parsed)
                                    }
                                }
                            }
                        }
                        Repeater {
                            model: root.recentColors
                            delegate: Rectangle {
                                required property string modelData
                                width: 34
                                height: 34
                                radius: 6
                                color: modelData
                                border.width: 2
                                border.color: Theme.color("primary")
                                Accessible.name: qsTr("Recent color %1").arg(modelData)
                                TapHandler {
                                    onTapped: root.setPickerColor(root.parseHex(parent.modelData), true)
                                }
                            }
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Surface, shape, icon, and badge")
                    subtitle: qsTr("Geometry and identity values apply to tabs, groups, pages, and the editor preview where the target supports them.")
                    visible: root.matchesEditorSearch("surface shape border radius corner padding spacing opacity icon emoji badge")

                    SettingRow {
                        title: qsTr("Border and corner radius")
                        description: qsTr("Widths and radii use tenth-pixel storage; their colors live in the color studio.")
                        searchTerms: "border width corner radius shape outline"
                        SpinBox {
                            id: borderWidthSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 240
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Border width in pixels")
                            textFromValue: function(value) { return root.fixed(value / 10, 1) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 10) }
                            onValueModified: root.setOverride("borderWidth", value / 10)
                        }
                        SpinBox {
                            id: radiusSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 960
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Corner radius in pixels")
                            textFromValue: function(value) { return root.fixed(value / 10, 1) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 10) }
                            onValueModified: root.setOverride("radius", value / 10)
                        }
                    }
                    SettingRow {
                        title: qsTr("Padding and spacing")
                        description: qsTr("Internal padding and sibling spacing are independent.")
                        searchTerms: "padding spacing gap inset geometry"
                        SpinBox {
                            id: paddingSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 960
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Padding in pixels")
                            textFromValue: function(value) { return root.fixed(value / 10, 1) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 10) }
                            onValueModified: root.setOverride("padding", value / 10)
                        }
                        SpinBox {
                            id: spacingSpin
                            Layout.fillWidth: true
                            from: 0
                            to: 960
                            stepSize: 5
                            editable: true
                            Accessible.name: qsTr("Spacing in pixels")
                            textFromValue: function(value) { return root.fixed(value / 10, 1) + " px" }
                            valueFromText: function(text) { return Math.round(Number(text.replace(/[^0-9.-]/g, "")) * 10) }
                            onValueModified: root.setOverride("spacing", value / 10)
                        }
                    }
                    SettingRow {
                        title: qsTr("Opacity")
                        description: qsTr("The target surface opacity from fully transparent to fully opaque.")
                        searchTerms: "opacity transparency alpha surface"
                        SpinBox {
                            id: opacitySpin
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            stepSize: 1
                            editable: true
                            Accessible.name: qsTr("Surface opacity percentage")
                            textFromValue: function(value) { return value + "%" }
                            valueFromText: function(text) { return Number(text.replace(/[^0-9.-]/g, "")) }
                            onValueModified: root.setOverride("opacity", value / 100)
                        }
                    }
                    SettingRow {
                        title: qsTr("Icon or emoji")
                        description: qsTr("A visible decoration; it never replaces the accessible target name.")
                        searchTerms: "icon emoji glyph symbol decoration"
                        TextField {
                            id: iconField
                            Layout.fillWidth: true
                            maximumLength: 32
                            selectByMouse: true
                            Accessible.name: qsTr("Icon or emoji")
                            onEditingFinished: root.setOverride("icon", text)
                        }
                    }
                    SettingRow {
                        title: qsTr("Badge")
                        description: qsTr("A short visible badge; the target name and state remain exposed separately.")
                        searchTerms: "badge label status decoration"
                        TextField {
                            id: badgeField
                            Layout.fillWidth: true
                            maximumLength: 48
                            selectByMouse: true
                            Accessible.name: qsTr("Appearance badge")
                            onEditingFinished: root.setOverride("badge", text)
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Live preview")
                    subtitle: qsTr("The sample uses the resolved installed font and the current inherited-plus-override appearance.")
                    visible: root.matchesEditorSearch("preview sample quick brown fox live resolved appearance")

                    Rectangle {
                        id: previewSurface
                        Layout.fillWidth: true
                        implicitHeight: 190
                        radius: root.numberValue(root.effectiveValue("radius"), Spacing.radiusCard)
                        color: root.colorValue(root.effectiveValue("backgroundColor"), Theme.color("surface"))
                        opacity: root.numberValue(root.effectiveValue("opacity"), 1)
                        border.width: root.numberValue(root.effectiveValue("borderWidth"), 1)
                        border.color: root.colorValue(root.effectiveValue("borderColor"), Theme.color("outlineVariant"))
                        clip: true

                        Label {
                            id: previewShadow
                            anchors.fill: parent
                            anchors.leftMargin: root.numberValue(root.effectiveValue("padding"), Spacing.lg) + 2
                            anchors.rightMargin: root.numberValue(root.effectiveValue("padding"), Spacing.lg) - 2
                            anchors.topMargin: root.numberValue(root.effectiveValue("padding"), Spacing.lg) + 2
                            anchors.bottomMargin: root.numberValue(root.effectiveValue("padding"), Spacing.lg) - 2
                            text: preview.text
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            horizontalAlignment: preview.horizontalAlignment
                            verticalAlignment: Text.AlignVCenter
                            color: root.colorValue(root.effectiveValue("shadowColor"), "#66000000")
                            font: preview.font
                        }
                        Label {
                            id: preview
                            anchors.fill: parent
                            anchors.margins: root.numberValue(root.effectiveValue("padding"), Spacing.lg)
                            anchors.verticalCenterOffset: root.numberValue(root.effectiveValue("baselineOffset"), 0)
                                + (root.boolValue(root.effectiveValue("superscript")) ? -6
                                    : (root.boolValue(root.effectiveValue("subscript")) ? 6 : 0))
                            text: (root.effectiveValue("icon") ? root.effectiveValue("icon") + "  " : "")
                                + qsTr("The quick brown fox jumps over 0123456789 · 蝦餃")
                                + (root.effectiveValue("badge") ? "  [" + root.effectiveValue("badge") + "]" : "")
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: root.alignmentValue(root.effectiveValue("alignment"))
                            LayoutMirroring.enabled: root.effectiveValue("direction") === "RightToLeft"
                            color: root.colorValue(root.effectiveValue("textColor"), Theme.color("onSurface"))
                            readonly property font resolvedPreviewFont: WorkspaceManager.resolvedFont(String(root.effectiveValue("fontFamily")),
                                String(root.effectiveValue("fontStyle")),
                                root.numberValue(root.effectiveValue("fontPointSize"), 12),
                                root.boolValue(root.effectiveValue("bold")),
                                root.boolValue(root.effectiveValue("italic")))
                            font.family: resolvedPreviewFont.family
                            font.styleName: resolvedPreviewFont.styleName
                            font.pointSize: resolvedPreviewFont.pointSize
                            font.italic: resolvedPreviewFont.italic
                            font.weight: root.numberValue(root.effectiveValue("fontWeight"), Font.Normal)
                            font.underline: root.boolValue(root.effectiveValue("underline"))
                            font.strikeout: root.boolValue(root.effectiveValue("strikeout"))
                                || root.boolValue(root.effectiveValue("doubleStrike"))
                            font.overline: root.boolValue(root.effectiveValue("overline"))
                            font.capitalization: root.capitalizationValue(root.effectiveValue("capitalization"))
                            font.letterSpacing: root.numberValue(root.effectiveValue("letterSpacing"), 0)
                            font.wordSpacing: root.numberValue(root.effectiveValue("wordSpacing"), 0)
                            lineHeightMode: Text.ProportionalHeight
                            lineHeight: root.numberValue(root.effectiveValue("lineHeight"), 1)
                        }
                    }
                }

                SettingsCard {
                    title: qsTr("Capability notes")
                    subtitle: qsTr("Saved values are never silently discarded when the current Qt Quick element cannot render them.")
                    visible: root.matchesEditorSearch("capability unsupported platform approximation underline double strike outline glow shadow small caps variable font")

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("• Qt Quick renders underline as a single line; underline style and underline color remain stored for compatible targets.\n"
                            + "• Double strikethrough is approximated as one strike in this preview; the doubleStrike value remains intact.\n"
                            + "• Outline and glow colors are retained as effect metadata; the lightweight desktop preview renders only a shadow offset.\n"
                            + "• Variable-font axes beyond numeric weight depend on the selected font and Qt platform backend. Unsupported axes remain represented by the chosen family, style, and weight rather than being invented.")
                        wrapMode: Text.WordWrap
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                }

                SettingsCard {
                    title: qsTr("Named appearance presets")
                    subtitle: qsTr("Presets contain sparse appearance values only. Import and export use the versioned qBittorrent Material JSON format.")
                    visible: root.matchesEditorSearch("preset named save remove import export JSON theme")

                    SettingRow {
                        title: qsTr("Use a preset")
                        description: qsTr("Replace the working overrides, then review them before applying.")
                        searchTerms: "preset apply use named theme"
                        ComboBox {
                            id: presetCombo
                            Layout.fillWidth: true
                            model: WorkspaceManager.appearancePresets
                            textRole: "name"
                            Accessible.name: qsTr("Saved appearance preset")
                        }
                        Button {
                            text: qsTr("Use")
                            enabled: presetCombo.currentIndex >= 0
                            onClicked: root.applySelectedPreset()
                        }
                        Button {
                            text: qsTr("Remove")
                            enabled: presetCombo.currentIndex >= 0
                            onClicked: presetRemoveConfirm.open()
                        }
                    }
                    SettingRow {
                        title: qsTr("Save current overrides")
                        description: qsTr("Existing names are updated; at most 32 presets are retained.")
                        searchTerms: "preset save name current overrides update"
                        TextField {
                            id: presetNameField
                            Layout.fillWidth: true
                            placeholderText: qsTr("Preset name")
                            maximumLength: 80
                            selectByMouse: true
                            Accessible.name: qsTr("New appearance preset name")
                            onAccepted: root.savePreset()
                        }
                        Button {
                            text: qsTr("Save preset")
                            enabled: presetNameField.text.trim().length > 0
                            onClicked: root.savePreset()
                        }
                    }
                    SettingRow {
                        title: qsTr("Portable preset file")
                        description: qsTr("Import a JSON preset or export the selected named preset.")
                        searchTerms: "preset JSON file import export portable share"
                        Button {
                            text: qsTr("Import…")
                            onClicked: importPresetDialog.open()
                        }
                        Button {
                            text: qsTr("Export…")
                            enabled: presetCombo.currentIndex >= 0
                            onClicked: {
                                var safeName = root.selectedPresetName().replace(/[^A-Za-z0-9._-]+/g, "-")
                                exportPresetDialog.selectedFile = WorkspaceManager.suggestedExportUrl(
                                    (safeName.length ? safeName : "appearance-preset") + ".json")
                                exportPresetDialog.open()
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.errorText.length > 0
                    text: root.errorText
                    wrapMode: Text.WordWrap
                    color: Theme.color("error")
                    font: Typography.bodySmall
                }

                Item { Layout.preferredHeight: 1 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.color("outlineVariant")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            spacing: Spacing.sm

            Button {
                text: qsTr("Reset target…")
                flat: true
                enabled: WorkspaceManager.writable && root.overriddenCount() > 0
                onClicked: root.requestReset("target")
            }
            Button {
                text: qsTr("Reset global…")
                flat: true
                enabled: WorkspaceManager.writable
                onClicked: root.requestReset("global")
            }
            Item { Layout.fillWidth: true }
            Button {
                text: qsTr("Cancel")
                flat: true
                onClicked: root.close()
            }
            Button {
                id: applyButton
                objectName: "workspaceSettingsApplyButton"
                text: qsTr("Apply")
                highlighted: true
                enabled: WorkspaceManager.writable
                onClicked: root.applyChanges()
            }
        }
    }

    Dialog {
        id: resetConfirm
        property string resetScope: "target"
        parent: Overlay.overlay
        width: Math.min(520, Math.max(320, root.width - (Spacing.xl * 2)))
        anchors.centerIn: parent
        modal: true
        focus: true
        title: resetScope === "global" ? qsTr("Reset global appearance?")
            : qsTr("Reset this %1 appearance?").arg(root.targetKind)
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label {
            text: resetConfirm.resetScope === "global"
                ? qsTr("Removes every global appearance override. Target overrides remain.")
                : qsTr("Removes every appearance override from the current target.")
            wrapMode: Text.WordWrap
            Accessible.name: text
        }
        onAccepted: root.performReset(resetScope)
    }

    Dialog {
        id: presetRemoveConfirm
        parent: Overlay.overlay
        width: Math.min(520, Math.max(320, root.width - (Spacing.xl * 2)))
        anchors.centerIn: parent
        modal: true
        focus: true
        title: qsTr("Remove appearance preset?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label {
            text: qsTr("Removes the selected named preset. Applied target appearances are not changed.")
            wrapMode: Text.WordWrap
            Accessible.name: text
        }
        onAccepted: {
            if (!WorkspaceManager.removeAppearancePreset(root.selectedPresetName()))
                root.errorText = qsTr("The selected preset could not be removed.")
        }
    }

    Dialogs.FileDialog {
        id: importPresetDialog
        title: qsTr("Import appearance preset")
        fileMode: Dialogs.FileDialog.OpenFile
        nameFilters: [qsTr("Appearance preset JSON (*.json)"), qsTr("All files (*)")]
        onAccepted: {
            if (!WorkspaceManager.importAppearancePreset(selectedFile))
                root.errorText = qsTr("That file is not a valid appearance preset.")
        }
    }

    Dialogs.FileDialog {
        id: exportPresetDialog
        title: qsTr("Export appearance preset")
        fileMode: Dialogs.FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("Appearance preset JSON (*.json)"), qsTr("All files (*)")]
        onAccepted: {
            if (!WorkspaceManager.exportAppearancePreset(root.selectedPresetName(), selectedFile))
                root.errorText = qsTr("The appearance preset could not be exported.")
        }
    }

    TextInput {
        id: clipboardHelper
        visible: false
        width: 0
        height: 0
    }
}
