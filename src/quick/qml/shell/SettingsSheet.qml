/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype SettingsSheet
    \brief The redesigned quick-settings sheet: theme segmented control, the
           three UI-style cards (each change committed to the settings
           journal), History retention chips + open-history shortcut, and a
           link to the full Options dialog.
*/
Sheet {
    id: root
    sheetWidth: 430
    accessibleName: qsTr("Settings")

    signal closeRequested()
    signal openHistoryRequested()
    signal openFullOptionsRequested()

    readonly property var styleCards: [
        { style: 0, name: qsTr("Tonal Rail"), desc: qsTr("Nav rail + chips, comfortable rows") },
        { style: 1, name: qsTr("Split Dock"), desc: qsTr("Classic sidebar, dense table, dock") },
        { style: 2, name: qsTr("Card Flow"), desc: qsTr("Cards + persistent detail panel") }
    ]
    readonly property var retentionOptions: ["30 days", "1 year", "Forever"]
    property var pendingSeedColor: ThemeManager.seedColor
    property string paletteRevealSection: ""
    property string highlightedPaletteSetting: ""
    property real paletteHighlightX: 0
    property real paletteHighlightY: 0
    property real paletteHighlightWidth: 0
    property real paletteHighlightHeight: 0

    function paletteEntries() {
        return [
            { id: "settings.appearance.colorScheme", title: qsTr("Theme"), section: "appearance", keywords: "light dark color scheme", targetId: "settingsThemeSegments", controlKind: "select" },
            { id: "settings.appearance.uiStyle", title: qsTr("UI style"), section: "appearance", keywords: "Tonal Rail Split Dock Card Flow", targetId: "settingsUiStyleChoices", controlKind: "select" },
            { id: "settings.appearance.densityScale", title: qsTr("Density"), section: "appearance", keywords: "compact comfortable scale", targetId: "settingsDensity", controlKind: "slider", minimum: 0.8, maximum: 1.35, step: 0.05 },
            { id: "settings.appearance.seedColor", title: qsTr("Accent / seed color"), section: "appearance", keywords: "Material color named HEX picker translator contrast", targetId: "settingsSeedColorField", controlKind: "color" },
            { id: "settings.appearance.seedColorPicker", title: qsTr("Open Material seed color picker"), section: "appearance", keywords: "continuous spectrum wheel RGB HSL OKLCH CMYK", targetId: "settingsSeedColorPickerButton", controlKind: "action" },
            { id: "settings.appearance.uiFontFamily", title: qsTr("UI font family"), section: "appearance", keywords: "typeface installed fonts", targetId: "settingsFontFamily", controlKind: "select" },
            { id: "settings.appearance.uiFontScale", title: qsTr("Font scale"), section: "appearance", keywords: "text size", targetId: "settingsFontScale", controlKind: "slider", minimum: 0.8, maximum: 1.6, step: 0.05 },
            { id: "settings.appearance.uiFontWeight", title: qsTr("Font weight"), section: "appearance", keywords: "bold thickness", targetId: "settingsFontWeight", controlKind: "spin", minimum: 100, maximum: 900, step: 50 },
            { id: "settings.appearance.reducedMotion", title: qsTr("Reduce motion"), section: "appearance", keywords: "animation accessibility", targetId: "settingsReducedMotion", controlKind: "toggle" },
            { id: "settings.appearance.reset", title: qsTr("Reset global appearance"), section: "appearance", keywords: "defaults reset theme", targetId: "settingsAppearanceReset", controlKind: "action" },
            { id: "settings.startup.dimSumSurprise", title: qsTr("10% dim sum surprise"), section: "startup", keywords: "10% public catalog cached photo offline unavailable cannot disable", targetId: "settingsDimSumSurprise", controlKind: "readonly", readOnly: true },
            { id: "settings.narrator.enabled", title: qsTr("Speak app events aloud"), section: "narrator", keywords: "narrator speech Edge online service", targetId: "settingsNarratorEnabled", controlKind: "toggle" },
            { id: "settings.narrator.languageMode", title: qsTr("Narration language"), section: "narrator", keywords: "English Cantonese Both", targetId: "settingsNarratorLanguage", controlKind: "select" },
            { id: "settings.narrator.englishVoice", title: qsTr("English voice"), section: "narrator", keywords: "voice preview", targetId: "settingsEnglishVoice", controlKind: "select" },
            { id: "settings.narrator.previewEnglish", title: qsTr("Preview English voice"), section: "narrator", keywords: "speak sample", targetId: "settingsEnglishVoicePreview", controlKind: "action" },
            { id: "settings.narrator.cantoneseVoice", title: qsTr("Cantonese voice"), section: "narrator", keywords: "Hong Kong voice preview", targetId: "settingsCantoneseVoice", controlKind: "select" },
            { id: "settings.narrator.previewCantonese", title: qsTr("Preview Cantonese voice"), section: "narrator", keywords: "speak sample", targetId: "settingsCantoneseVoicePreview", controlKind: "action" },
            { id: "settings.narrator.volume", title: qsTr("Narration volume"), section: "narrator", keywords: "speaker level", targetId: "settingsNarratorVolume", controlKind: "slider", minimum: 0, maximum: 1, step: 0.05 },
            { id: "settings.narrator.quietHours", title: qsTr("Quiet — keep the settings but stay silent"), section: "narrator", keywords: "mute quiet", targetId: "settingsNarratorQuiet", controlKind: "toggle" },
            { id: "settings.editor.selected", title: qsTr("External editor"), section: "editor", keywords: "Visual Studio Code VSCodium Cursor Sublime Notepad", targetId: "settingsExternalEditor", controlKind: "select" },
            { id: "settings.editor.customPath", title: qsTr("Custom editor executable"), section: "editor", keywords: "path application", targetId: "settingsCustomEditorPath", controlKind: "path", sensitive: true },
            { id: "settings.editor.browse", title: qsTr("Browse for an external editor"), section: "editor", keywords: "file picker executable", targetId: "settingsEditorBrowse", controlKind: "action" },
            { id: "settings.editor.refresh", title: qsTr("Refresh detected editors"), section: "editor", keywords: "detect rescan", targetId: "settingsEditorRefresh", controlKind: "action" },
            { id: "settings.editor.openWorkspace", title: qsTr("Open workspace in external editor"), section: "editor", keywords: "project folder workspace root", targetId: "settingsEditorOpenWorkspace", controlKind: "action" },
            { id: "settings.history.retention", title: qsTr("History retention"), section: "history", keywords: "30 days 1 year Forever commits", targetId: "settingsHistoryRetention", controlKind: "select" },
            { id: "settings.history.open", title: qsTr("Open history manager"), section: "history", keywords: "versions undo journal", targetId: "settingsOpenHistory", controlKind: "action" },
            { id: "settings.options.open", title: qsTr("All qBittorrent options…"), section: "options", keywords: "advanced full preferences", targetId: "settingsOpenFullOptions", controlKind: "action" }
        ]
    }

    function paletteTarget(settingId) {
        switch (settingId) {
        case "settings.appearance.colorScheme": return themeSegmentContainer
        case "settings.appearance.uiStyle": return uiStyleChoices.itemAt(Math.max(0, ThemeManager.uiStyle)) || uiStyleLabel
        case "settings.appearance.densityScale": return densitySlider
        case "settings.appearance.seedColor": return seedColorField
        case "settings.appearance.seedColorPicker": return seedColorPickerButton
        case "settings.appearance.uiFontFamily": return fontFamilyCombo
        case "settings.appearance.uiFontScale": return fontScaleSlider
        case "settings.appearance.uiFontWeight": return fontWeightSpin
        case "settings.appearance.reducedMotion": return reducedMotionSwitch
        case "settings.appearance.reset": return appearanceResetButton
        case "settings.startup.dimSumSurprise": return dimSumSurpriseCard
        case "settings.narrator.enabled": return narratorEnabledSwitch
        case "settings.narrator.languageMode": return narratorLanguageBox
        case "settings.narrator.englishVoice": return englishVoiceBox
        case "settings.narrator.previewEnglish": return englishVoicePreviewButton
        case "settings.narrator.cantoneseVoice": return cantoneseVoiceBox
        case "settings.narrator.previewCantonese": return cantoneseVoicePreviewButton
        case "settings.narrator.volume": return narratorVolumeSlider
        case "settings.narrator.quietHours": return narratorQuietSwitch
        case "settings.editor.selected": return editorCombo
        case "settings.editor.customPath": return customEditorPath
        case "settings.editor.browse": return editorBrowseButton
        case "settings.editor.refresh": return editorRefreshButton
        case "settings.editor.openWorkspace": return editorOpenWorkspaceButton
        case "settings.history.retention": return retentionChoices.itemAt(0) || historyRetentionLabel
        case "settings.history.open": return openHistoryCard
        case "settings.options.open": return fullOptionsCard
        default: return null
        }
    }

    function paletteValue(settingId) {
        switch (settingId) {
        case "settings.appearance.colorScheme": return Theme.isDark ? qsTr("Dark") : qsTr("Light")
        case "settings.appearance.uiStyle":
            return (ThemeManager.uiStyle >= 0 && ThemeManager.uiStyle < root.styleCards.length)
                ? root.styleCards[ThemeManager.uiStyle].name : qsTr("Unknown")
        case "settings.appearance.densityScale": return Number(ThemeManager.densityScale).toFixed(2) + "×"
        case "settings.appearance.seedColor": return String(ThemeManager.seedColor)
        case "settings.appearance.uiFontFamily": return ThemeManager.uiFontFamily || qsTr("Default")
        case "settings.appearance.uiFontScale": return Number(ThemeManager.uiFontScale).toFixed(2) + "×"
        case "settings.appearance.uiFontWeight": return ThemeManager.uiFontWeight
        case "settings.appearance.reducedMotion": return ThemeManager.reducedMotion
        case "settings.narrator.enabled": return NarratorController.enabled
        case "settings.narrator.languageMode": return [qsTr("English"), qsTr("Cantonese"), qsTr("Both")][NarratorController.languageMode]
        case "settings.narrator.englishVoice": return NarratorController.englishVoice
        case "settings.narrator.cantoneseVoice": return NarratorController.cantoneseVoice
        case "settings.narrator.volume": return Math.round(NarratorController.volume * 100) + "%"
        case "settings.narrator.quietHours": return NarratorController.quietHours
        case "settings.editor.selected": return DesktopIntegration.selectedEditor
        case "settings.editor.customPath": return DesktopIntegration.customEditorPath
        case "settings.history.retention": return JournalController.retention
        default: return qsTr("Open control")
        }
    }

    function paletteControlValue(settingId) {
        switch (settingId) {
        case "settings.appearance.colorScheme": return Theme.isDark ? 1 : 0
        case "settings.appearance.uiStyle": return ThemeManager.uiStyle
        case "settings.appearance.densityScale": return ThemeManager.densityScale
        case "settings.appearance.seedColor": return String(ThemeManager.seedColor)
        case "settings.appearance.uiFontFamily": return fontFamilyCombo.currentIndex
        case "settings.appearance.uiFontScale": return ThemeManager.uiFontScale
        case "settings.appearance.uiFontWeight": return ThemeManager.uiFontWeight
        case "settings.appearance.reducedMotion": return ThemeManager.reducedMotion
        case "settings.narrator.enabled": return NarratorController.enabled
        case "settings.narrator.languageMode": return NarratorController.languageMode
        case "settings.narrator.englishVoice": return englishVoiceBox.currentIndex
        case "settings.narrator.cantoneseVoice": return cantoneseVoiceBox.currentIndex
        case "settings.narrator.volume": return NarratorController.volume
        case "settings.narrator.quietHours": return NarratorController.quietHours
        case "settings.editor.selected": return editorCombo.currentIndex
        case "settings.editor.customPath": return ""
        case "settings.history.retention": return root.retentionOptions.indexOf(JournalController.retention)
        default: return undefined
        }
    }

    function paletteChoices(settingId) {
        switch (settingId) {
        case "settings.appearance.colorScheme":
            return [qsTr("Light"), qsTr("Dark")]
        case "settings.appearance.uiStyle":
            return root.styleCards.map(function(item) { return item.name })
        case "settings.appearance.uiFontFamily":
            return ThemeManager.installedFontFamilies()
        case "settings.narrator.languageMode":
            return [qsTr("English"), qsTr("Cantonese"), qsTr("Both")]
        case "settings.narrator.englishVoice":
            return comboTextChoices(englishVoiceBox)
        case "settings.narrator.cantoneseVoice":
            return comboTextChoices(cantoneseVoiceBox)
        case "settings.editor.selected":
            return comboTextChoices(editorCombo)
        case "settings.history.retention":
            return root.retentionOptions
        default:
            return []
        }
    }

    function comboTextChoices(combo) {
        var choices = []
        if (!combo)
            return choices
        for (var index = 0; index < combo.count; ++index)
            choices.push(combo.textAt(index))
        return choices
    }

    function paletteCommands() {
        var entries = root.paletteEntries()
        var commands = []
        for (var index = 0; index < entries.length; ++index) {
            var entry = entries[index]
            var target = root.paletteTarget(entry.id)
            var value = root.paletteValue(entry.id)
            var inlineToggle = entry.controlKind === "toggle"
            var controlValue = root.paletteControlValue(entry.id)
            var inlineControl = entry.sensitive ? "password"
                : (entry.controlKind || "readonly")
            commands.push({
                id: "setting." + entry.id,
                kind: "setting",
                settingId: entry.id,
                settingScope: "quick",
                title: entry.title,
                group: qsTr("Quick setting"),
                destination: qsTr("Settings · %1").arg(entry.section),
                context: entry.sensitive ? qsTr("Sensitive value hidden")
                    : (inlineToggle ? (value ? qsTr("Enabled") : qsTr("Disabled"))
                        : qsTr("Current: %1").arg(String(value).slice(0, 160))),
                keywords: entry.keywords + (entry.sensitive ? "" : (" " + String(value))),
                targetId: entry.targetId,
                inlineControl: inlineControl,
                inlineEditable: entry.controlKind !== "readonly"
                    && !entry.sensitive && target && target.enabled !== false,
                checked: inlineToggle ? !!value : false,
                value: controlValue,
                valueText: entry.sensitive ? "" : String(controlValue === undefined ? value : controlValue),
                choices: entry.controlKind === "select"
                    ? root.paletteChoices(entry.id) : [],
                minimum: entry.minimum === undefined ? 0 : entry.minimum,
                maximum: entry.maximum === undefined ? 100 : entry.maximum,
                step: entry.step === undefined ? 1 : entry.step,
                actionLabel: entry.controlKind === "action" ? entry.title : "",
                sensitive: entry.sensitive === true,
                enabled: true
            })
        }
        return commands
    }

    function finishPaletteReveal(settingId) {
        var target = root.paletteTarget(settingId)
        if (!target)
            return false
        var mappedContent = target.mapToItem(settingsFlickable.contentItem, 0, 0)
        var margin = Spacing.lg
        var targetTop = Math.max(0, mappedContent.y - margin)
        var targetBottom = mappedContent.y + Math.max(target.height, Spacing.controlHeight) + margin
        if (targetTop < settingsFlickable.contentY)
            settingsFlickable.contentY = targetTop
        else if (targetBottom > settingsFlickable.contentY + settingsFlickable.height)
            settingsFlickable.contentY = Math.min(
                Math.max(0, settingsFlickable.contentHeight - settingsFlickable.height),
                targetBottom - settingsFlickable.height)

        var mapped = target.mapToItem(root, 0, 0)
        root.paletteHighlightX = mapped.x - Spacing.xs
        root.paletteHighlightY = mapped.y - Spacing.xs
        root.paletteHighlightWidth = target.width + (2 * Spacing.xs)
        root.paletteHighlightHeight = Math.max(target.height, Spacing.controlHeight)
            + (2 * Spacing.xs)
        root.highlightedPaletteSetting = settingId
        paletteHighlightTimer.restart()
        if (target.enabled !== false)
            target.forceActiveFocus(Qt.ShortcutFocusReason)
        return true
    }

    function revealPaletteSetting(settingId) {
        var entries = root.paletteEntries()
        for (var index = 0; index < entries.length; ++index) {
            if (entries[index].id !== settingId)
                continue
            root.paletteRevealSection = entries[index].section
            Qt.callLater(function() { root.finishPaletteReveal(settingId) })
            return true
        }
        Log.warning("ui", "Quick-settings palette target not found: " + settingId)
        return false
    }

    function setPaletteSetting(settingId, value) {
        switch (settingId) {
        case "settings.appearance.colorScheme":
            ThemeManager.colorScheme = Number(value) === 1
                ? ThemeManager.Dark : ThemeManager.Light
            break
        case "settings.appearance.uiStyle":
            ThemeManager.uiStyle = Number(value)
            break
        case "settings.appearance.densityScale":
            ThemeManager.densityScale = Number(value)
            break
        case "settings.appearance.seedColor":
        case "settings.appearance.seedColorPicker":
            seedColorPickerButton.clicked()
            return true
        case "settings.appearance.uiFontFamily": {
            var families = ThemeManager.installedFontFamilies()
            if (Number(value) >= 0 && Number(value) < families.length)
                ThemeManager.uiFontFamily = families[Number(value)]
            break
        }
        case "settings.appearance.uiFontScale":
            ThemeManager.uiFontScale = Number(value)
            break
        case "settings.appearance.uiFontWeight":
            ThemeManager.uiFontWeight = Number(value)
            break
        case "settings.appearance.reducedMotion":
            ThemeManager.reducedMotion = !!value
            break
        case "settings.appearance.reset":
            appearanceResetButton.clicked()
            break
        case "settings.narrator.enabled":
            NarratorController.enabled = !!value
            break
        case "settings.narrator.languageMode":
            NarratorController.languageMode = Number(value)
            break
        case "settings.narrator.englishVoice":
            if (Number(value) >= 0 && Number(value) < englishVoiceBox.count)
                NarratorController.englishVoice = englishVoiceBox.valueAt(Number(value))
            break
        case "settings.narrator.previewEnglish":
            englishVoicePreviewButton.clicked()
            break
        case "settings.narrator.cantoneseVoice":
            if (Number(value) >= 0 && Number(value) < cantoneseVoiceBox.count)
                NarratorController.cantoneseVoice = cantoneseVoiceBox.valueAt(Number(value))
            break
        case "settings.narrator.previewCantonese":
            cantoneseVoicePreviewButton.clicked()
            break
        case "settings.narrator.volume":
            NarratorController.volume = Number(value)
            break
        case "settings.narrator.quietHours":
            NarratorController.quietHours = !!value
            break
        case "settings.editor.selected":
            if (Number(value) >= 0 && Number(value) < DesktopIntegration.availableEditors.length)
                DesktopIntegration.selectedEditor = DesktopIntegration.availableEditors[Number(value)].id
            break
        case "settings.editor.browse":
            editorBrowseButton.clicked()
            return true
        case "settings.editor.refresh":
            editorRefreshButton.clicked()
            break
        case "settings.editor.openWorkspace":
            editorOpenWorkspaceButton.clicked()
            break
        case "settings.history.retention":
            if (Number(value) >= 0 && Number(value) < root.retentionOptions.length)
                JournalController.retention = root.retentionOptions[Number(value)]
            break
        case "settings.history.open":
            root.openHistoryRequested()
            return true
        case "settings.options.open":
            root.openFullOptionsRequested()
            return true
        case "settings.startup.dimSumSurprise":
        case "settings.editor.customPath":
            return root.revealPaletteSetting(settingId)
        default:
            return root.revealPaletteSetting(settingId)
        }
        return root.revealPaletteSetting(settingId)
    }

    function settingsMatch(text) {
        var query = settingsSearch.text
        if (!query.length)
            return true
        if (settingsSearch.regexEnabled) {
            var result = WorkspaceManager.evaluateRegularExpression(query,
                settingsSearch.regexFlags, text)
            return result.valid && result.count > 0
        }
        return text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
    }

    function editorIndex() {
        for (var i = 0; i < DesktopIntegration.availableEditors.length; ++i)
            if (DesktopIntegration.availableEditors[i].id === DesktopIntegration.selectedEditor)
                return i
        return -1
    }

    function applySeedColor(value) {
        seedColorPreviewDebounce.stop()
        if (!ThemeManager.isValidColor(String(value))) {
            seedColorField.userEdited = true
            seedColorField.forceActiveFocus(Qt.ShortcutFocusReason)
            return false
        }
        ThemeManager.seedColor = value
        seedColorField.text = String(ThemeManager.seedColor)
        seedColorField.userEdited = false
        return true
    }

    function previewSeedColor(value) {
        if (!ThemeManager.isValidColor(String(value)))
            return false
        ThemeManager.seedColor = value
        return true
    }

    function queueSeedColorPreview(value) {
        pendingSeedColor = value
        seedColorPreviewDebounce.restart()
    }

    function syncSeedColorField() {
        if (!seedColorField.userEdited)
            seedColorField.text = String(ThemeManager.seedColor)
    }

    Connections {
        target: ThemeManager
        function onAppearanceChanged() { root.syncSeedColorField() }
        function onThemeChanged() { root.syncSeedColorField() }
    }

    Timer {
        id: seedColorPreviewDebounce
        interval: 160
        repeat: false
        onTriggered: root.previewSeedColor(root.pendingSeedColor)
    }

    Timer {
        id: paletteHighlightTimer
        interval: 1800
        repeat: false
        onTriggered: root.highlightedPaletteSetting = ""
    }

    Rectangle {
        x: root.paletteHighlightX
        y: root.paletteHighlightY
        width: root.paletteHighlightWidth
        height: root.paletteHighlightHeight
        z: 1000
        visible: root.highlightedPaletteSetting.length > 0
        color: "transparent"
        border.width: Math.max(2, Spacing.outlineWidth)
        border.color: Theme.color("primary")
        radius: Spacing.radiusControl
        opacity: visible ? 1 : 0
        Accessible.ignored: true

        Behavior on opacity {
            enabled: !ThemeManager.reducedMotion
            NumberAnimation { duration: Spacing.motionMedium }
        }
    }

    AdvancedColorPicker {
        id: seedColorPicker
        objectName: "advancedSeedColorPicker"
        title: qsTr("Material seed color studio")
        forceOpaque: true
        onColorPreviewed: (value) => root.queueSeedColorPreview(value)
        onColorAccepted: (value) => root.applySeedColor(value)
        onColorCanceled: (originalValue) => {
            seedColorPreviewDebounce.stop()
            ThemeManager.seedColor = originalValue
            root.syncSeedColorField()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.leftMargin: 20
            Layout.rightMargin: 16
            Layout.bottomMargin: 6
            spacing: 8
            Text {
                text: qsTr("Settings")
                font.family: Typography.family
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Theme.color("onSurface")
            }
            Text {
                text: qsTr("every change becomes a commit")
                font.family: Typography.family
                font.pixelSize: 12
                color: Theme.color("onSurfaceVariant")
            }
            Item { Layout.fillWidth: true }
            HeaderIconButton {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                iconName: "close"; iconSize: 19; iconColor: Theme.color("onSurfaceVariant")
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }

        FilterTextField {
            id: settingsSearch
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 8
            placeholder: qsTr("Search these settings…")
            builderTitle: qsTr("Settings Regex Builder")
            builderSampleText: qsTr("Theme\nDensity\nDim sum surprise\nExternal editor\nHistory retention")
        }

        Flickable {
            id: settingsFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            ColumnLayout {
                id: settingsColumn
                width: parent.width
                spacing: 18

                // --- Appearance ---
                ColumnLayout {
                    id: appearanceSection
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 8
                    spacing: 10
                    visible: root.paletteRevealSection === "appearance"
                        || root.settingsMatch(qsTr("Appearance theme light dark UI style density accent seed color font family size weight reduced motion reset"))

                    Text {
                        text: qsTr("APPEARANCE")
                        font.family: Typography.family
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.color("primary")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: qsTr("Theme")
                            font.family: Typography.family
                            font.pixelSize: 14
                            color: Theme.color("onSurface")
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: themeSegmentContainer
                            objectName: "settingsThemeSegments"
                            Layout.preferredHeight: 36
                            width: themeRow.implicitWidth + 6
                            radius: 18
                            color: Theme.color("surfaceVariant")
                            Row {
                                id: themeRow
                                anchors.centerIn: parent
                                spacing: 0
                                Repeater {
                                    model: [
                                        { dark: false, icon: "light_mode", label: qsTr("Light") },
                                        { dark: true, icon: "dark_mode", label: qsTr("Dark") }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: Theme.isDark === modelData.dark
                                        focus: true
                                        activeFocusOnTab: true
                                        height: 30
                                        width: segItemRow.implicitWidth + 24
                                        radius: 15
                                        color: active ? Theme.color("primary") : "transparent"
                                        border.width: activeFocus ? 2 : 0
                                        border.color: Theme.color("focusRing")
                                        Accessible.role: Accessible.RadioButton
                                        Accessible.name: modelData.label
                                        Accessible.checked: active
                                        Keys.onSpacePressed: ThemeManager.colorScheme = modelData.dark ? ThemeManager.Dark : ThemeManager.Light
                                        Keys.onReturnPressed: ThemeManager.colorScheme = modelData.dark ? ThemeManager.Dark : ThemeManager.Light
                                        Row {
                                            id: segItemRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: modelData.icon; size: 15
                                                color: parent.parent.active ? Theme.color("onPrimary") : Theme.color("onSurfaceVariant")
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.label
                                                font.family: Typography.family; font.pixelSize: 13; font.weight: Font.DemiBold
                                                color: parent.parent.active ? Theme.color("onPrimary") : Theme.color("onSurfaceVariant")
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ThemeManager.colorScheme = modelData.dark ? ThemeManager.Dark : ThemeManager.Light
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: uiStyleLabel
                        objectName: "settingsUiStyleChoices"
                        text: qsTr("UI style")
                        font.family: Typography.family
                        font.pixelSize: 14
                        color: Theme.color("onSurface")
                    }

                    Repeater {
                        id: uiStyleChoices
                        model: root.styleCards
                        delegate: Rectangle {
                            id: styleCard
                            objectName: "settingsUiStyleChoice." + modelData.style
                            required property var modelData
                            readonly property bool active: Theme.uiStyle === modelData.style
                            focus: true
                            activeFocusOnTab: true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 68
                            radius: 16
                            color: active ? Qt.alpha(Theme.color("primary"), Theme.isDark ? 0.10 : 0.06)
                                          : (cardMouse.containsMouse ? Theme.color("hover") : "transparent")
                            border.width: active || activeFocus ? 2 : 1
                            border.color: active || activeFocus ? Theme.color("primary") : Theme.color("outlineVariant")
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.name + ". " + modelData.desc
                            Accessible.checked: active
                            Keys.onSpacePressed: ThemeManager.uiStyle = modelData.style
                            Keys.onReturnPressed: ThemeManager.uiStyle = modelData.style

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 14

                                // Mini thumbnail.
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 44
                                    radius: 10
                                    color: Theme.color("background")
                                    border.width: 1
                                    border.color: Theme.color("outlineVariant")
                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 3
                                        Rectangle {
                                            width: modelData.style === 1 ? 14 : (modelData.style === 2 ? 6 : 8)
                                            height: parent.height
                                            radius: 3
                                            color: Theme.color("primary")
                                        }
                                        Column {
                                            width: parent.width - (modelData.style === 1 ? 17 : (modelData.style === 2 ? 9 : 11))
                                            height: parent.height
                                            spacing: 3
                                            Rectangle { width: parent.width * 0.7; height: 5; radius: 2; color: Theme.color("primary"); opacity: 0.5 }
                                            Rectangle { width: parent.width; height: modelData.style === 0 ? parent.height - 8 : 8; radius: 3; color: Theme.color("primary"); opacity: 0.22 }
                                            Rectangle { visible: modelData.style !== 0; width: parent.width; height: 8; radius: 3; color: Theme.color("primary"); opacity: 0.22 }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        font.family: Typography.family
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        color: Theme.color("onSurface")
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.desc
                                        elide: Text.ElideRight
                                        font.family: Typography.family
                                        font.pixelSize: 12
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                }

                                MDIcon {
                                    name: styleCard.active ? "radio_button_checked" : "radio_button_unchecked"
                                    size: 20
                                    color: styleCard.active ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ThemeManager.uiStyle = modelData.style
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Density"); color: Theme.color("onSurface") }
                        Slider {
                            id: densitySlider
                            objectName: "settingsDensity"
                            Layout.fillWidth: true
                            from: 0.8; to: 1.35; stepSize: 0.05
                            value: ThemeManager.densityScale
                            Accessible.name: qsTr("Interface density")
                            onMoved: ThemeManager.densityScale = value
                        }
                        Label { text: Number(ThemeManager.densityScale).toFixed(2) + "×"; font.family: Typography.monoFamily }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Accent / seed color")
                            color: Theme.color("onSurface")
                            wrapMode: Text.WordWrap
                        }
                        GridLayout {
                            id: seedColorLayout
                            Layout.fillWidth: true
                            columns: width >= 300 ? 3 : 1
                            columnSpacing: Spacing.sm
                            rowSpacing: Spacing.xs

                            TextField {
                                id: seedColorField
                                objectName: "settingsSeedColorField"
                                property bool userEdited: false
                                readonly property bool validColor: ThemeManager.isValidColor(text)
                                Layout.fillWidth: true
                                text: ThemeManager.seedColor
                                maximumLength: 32
                                Accessible.name: qsTr("Material seed color")
                                Accessible.description: validColor
                                    ? qsTr("Valid color")
                                    : qsTr("Enter a valid named color or HEX value")
                                onTextEdited: {
                                    userEdited = true
                                    seedColorPreviewDebounce.stop()
                                    if (validColor)
                                        root.queueSeedColorPreview(text)
                                }
                                onAccepted: root.applySeedColor(text)
                            }
                            Button {
                                id: seedColorPickerButton
                                objectName: "settingsSeedColorPickerButton"
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 40
                                Layout.fillWidth: seedColorLayout.columns === 1
                                padding: 8
                                Accessible.name: qsTr("Open Material seed color picker")
                                Accessible.description: qsTr("Current color %1").arg(String(ThemeManager.seedColor))
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Choose color")
                                ToolTip.delay: 500
                                onClicked: {
                                    seedColorPreviewDebounce.stop()
                                    if (seedColorField.validColor)
                                        root.previewSeedColor(seedColorField.text)
                                    seedColorPicker.openFor(seedColorPickerButton,
                                        ThemeManager.seedColor, Theme.color("surface"))
                                }
                                contentItem: Item { }
                                background: Rectangle {
                                    radius: 12
                                    color: ThemeManager.seedColor
                                    border.width: seedColorPickerButton.visualFocus ? 3 : 1
                                    border.color: seedColorPickerButton.visualFocus
                                        ? Theme.color("onSurface") : Theme.color("outline")
                                }
                            }
                            Button {
                                Layout.fillWidth: seedColorLayout.columns === 1
                                text: qsTr("Apply")
                                enabled: seedColorField.validColor
                                onClicked: root.applySeedColor(seedColorField.text)
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Type a named color or HEX value. Valid input previews after a short pause; Material seed colors are applied as opaque.")
                            color: Theme.color("onSurfaceVariant")
                            font: Typography.bodySmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: seedColorField.userEdited && !seedColorField.validColor
                        text: qsTr("Enter a valid named color or HEX value (for example #6750A4).")
                        color: Theme.color("error")
                        font: Typography.bodySmall
                        wrapMode: Text.WordWrap
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: text
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Label { text: qsTr("UI font family"); color: Theme.color("onSurface") }
                        ComboBox {
                            id: fontFamilyCombo
                            objectName: "settingsFontFamily"
                            Layout.fillWidth: true
                            model: ThemeManager.installedFontFamilies()
                            editable: true
                            currentIndex: ThemeManager.uiFontFamily.length > 0
                                ? model.indexOf(ThemeManager.uiFontFamily) : -1
                            displayText: currentIndex >= 0 ? currentText : qsTr("Default (bundled Roboto)")
                            Accessible.name: qsTr("Search and select the interface font")
                            onActivated: (index) => ThemeManager.uiFontFamily = model[index]
                            onAccepted: ThemeManager.uiFontFamily = editText
                            delegate: ItemDelegate {
                                required property string modelData
                                width: ListView.view.width
                                text: modelData
                                font.family: modelData
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Font scale"); color: Theme.color("onSurface") }
                        Slider {
                            id: fontScaleSlider
                            objectName: "settingsFontScale"
                            Layout.fillWidth: true
                            from: 0.8; to: 1.6; stepSize: 0.05
                            value: ThemeManager.uiFontScale
                            Accessible.name: qsTr("Interface font size scale")
                            onMoved: ThemeManager.uiFontScale = value
                        }
                        Label { text: Number(ThemeManager.uiFontScale).toFixed(2) + "×"; font.family: Typography.monoFamily }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Font weight"); color: Theme.color("onSurface") }
                        Item { Layout.fillWidth: true }
                        SpinBox {
                            id: fontWeightSpin
                            objectName: "settingsFontWeight"
                            from: 100; to: 900; stepSize: 50
                            value: ThemeManager.uiFontWeight
                            editable: true
                            Accessible.name: qsTr("Interface font weight")
                            onValueModified: ThemeManager.uiFontWeight = value
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Reduce motion")
                            color: Theme.color("onSurface")
                        }
                        Switch {
                            id: reducedMotionSwitch
                            objectName: "settingsReducedMotion"
                            checked: ThemeManager.reducedMotion
                            Accessible.name: qsTr("Reduce interface motion")
                            onToggled: ThemeManager.reducedMotion = checked
                        }
                    }

                    Button {
                        id: appearanceResetButton
                        objectName: "settingsAppearanceReset"
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Reset global appearance")
                        flat: true
                        onClicked: {
                            ThemeManager.resetAppearance()
                            seedColorField.text = String(ThemeManager.seedColor)
                            seedColorField.userEdited = false
                        }
                    }
                }

                // --- Startup delight ----------------------------------------
                ColumnLayout {
                    id: dimSumSurpriseCard
                    objectName: "settingsDimSumSurprise"
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8
                    visible: root.paletteRevealSection === "startup"
                        || root.settingsMatch(qsTr("Dim sum startup surprise 10% public catalog cached photo offline unavailable cannot disable"))

                    Text {
                        text: qsTr("STARTUP DELIGHT")
                        font.family: Typography.family
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.color("primary")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { text: qsTr("10% dim sum surprise"); color: Theme.color("onSurface") }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Uses a fresh 10% launch draw from verified public catalog-v1 photos cached in app data. It never waits for the network; when no verified cached photo is available, the surprise is omitted. It cannot be disabled.")
                            font: Typography.bodySmall
                            color: Theme.color("onSurfaceVariant")
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // --- Spoken narrator ----------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8
                    visible: root.paletteRevealSection === "narrator"
                        || root.settingsMatch(qsTr("Narrator speech voice spoken text to speech English Cantonese Hong Kong volume quiet edge tts"))

                    Text {
                        text: qsTr("SPOKEN NARRATOR")
                        font.family: Typography.family
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.color("primary")
                    }

                    Switch {
                        id: narratorEnabledSwitch
                        objectName: "settingsNarratorEnabled"
                        text: qsTr("Speak app events aloud")
                        checked: NarratorController.enabled
                        onToggled: NarratorController.enabled = checked
                        Accessible.name: qsTr("Spoken narrator, %1")
                            .arg(checked ? qsTr("on") : qsTr("off"))
                    }

                    // Enabling a voice is not consent to a network round trip
                    // nobody mentioned, so say where the audio comes from.
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Off by default. Voices are synthesized by Microsoft Edge's online speech service, so while the narrator is on, the text it speaks is sent to that service. Nothing is sent while it is off.")
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: NarratorController.unavailableReason.length > 0
                        text: NarratorController.unavailableReason
                        font: Typography.bodySmall
                        color: Theme.color("error")
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        enabled: NarratorController.enabled

                        LabeledField {
                            label: qsTr("Speak in:")
                            Layout.fillWidth: true
                            ComboBox {
                                id: narratorLanguageBox
                                objectName: "settingsNarratorLanguage"
                                Layout.fillWidth: true
                                model: [qsTr("English"), qsTr("Cantonese"), qsTr("Both")]
                                currentIndex: NarratorController.languageMode
                                onActivated: NarratorController.languageMode = currentIndex
                                Accessible.name: qsTr("Narration language")
                            }
                        }

                        LabeledField {
                            label: qsTr("English voice:")
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ComboBox {
                                    id: englishVoiceBox
                                    objectName: "settingsEnglishVoice"
                                    Layout.fillWidth: true
                                    textRole: "name"
                                    valueRole: "id"
                                    model: NarratorController.englishVoices()
                                    currentIndex: indexOfValue(NarratorController.englishVoice)
                                    onActivated: NarratorController.englishVoice = currentValue
                                }
                                Button {
                                    id: englishVoicePreviewButton
                                    objectName: "settingsEnglishVoicePreview"
                                    text: qsTr("Preview")
                                    flat: true
                                    onClicked: NarratorController.previewVoice(
                                        englishVoiceBox.currentValue,
                                        qsTr("Download finished. One basket of shrimp dumplings."))
                                }
                            }
                        }

                        LabeledField {
                            label: qsTr("Cantonese voice:")
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ComboBox {
                                    id: cantoneseVoiceBox
                                    objectName: "settingsCantoneseVoice"
                                    Layout.fillWidth: true
                                    textRole: "name"
                                    valueRole: "id"
                                    model: NarratorController.cantoneseVoices()
                                    currentIndex: indexOfValue(NarratorController.cantoneseVoice)
                                    onActivated: NarratorController.cantoneseVoice = currentValue
                                }
                                Button {
                                    id: cantoneseVoicePreviewButton
                                    objectName: "settingsCantoneseVoicePreview"
                                    text: qsTr("Preview")
                                    flat: true
                                    onClicked: NarratorController.previewVoice(
                                        cantoneseVoiceBox.currentValue, "下載完成，蝦餃一籠。")
                                }
                            }
                        }

                        LabeledField {
                            label: qsTr("Volume:")
                            Layout.fillWidth: true
                            Slider {
                                id: narratorVolumeSlider
                                objectName: "settingsNarratorVolume"
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: NarratorController.volume
                                onMoved: NarratorController.volume = value
                                Accessible.name: qsTr("Narration volume")
                            }
                        }

                        Switch {
                            id: narratorQuietSwitch
                            objectName: "settingsNarratorQuiet"
                            text: qsTr("Quiet — keep the settings but stay silent")
                            checked: NarratorController.quietHours
                            onToggled: NarratorController.quietHours = checked
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("The narrator speaks one line at a time, never overlapping, and stays quiet while a screen reader is running.")
                            font: Typography.bodySmall
                            color: Theme.color("onSurfaceVariant")
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // --- External editor ----------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8
                    visible: root.paletteRevealSection === "editor"
                        || root.settingsMatch(qsTr("External editor Visual Studio Code VSCodium Cursor Sublime Notepad custom project folder"))

                    Text {
                        text: qsTr("EXTERNAL EDITOR")
                        font.family: Typography.family
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.color("primary")
                    }
                    ComboBox {
                        id: editorCombo
                        objectName: "settingsExternalEditor"
                        Layout.fillWidth: true
                        model: DesktopIntegration.availableEditors
                        textRole: "name"
                        currentIndex: root.editorIndex()
                        Accessible.name: qsTr("External editor")
                        displayText: currentIndex >= 0 ? currentText : qsTr("No editor detected")
                        onActivated: (index) => DesktopIntegration.selectedEditor = model[index].id
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: customEditorPath
                            objectName: "settingsCustomEditorPath"
                            Layout.fillWidth: true
                            text: DesktopIntegration.customEditorPath
                            placeholderText: qsTr("Custom editor executable")
                            Accessible.name: placeholderText
                            onEditingFinished: DesktopIntegration.customEditorPath = text
                        }
                        Button {
                            id: editorBrowseButton
                            objectName: "settingsEditorBrowse"
                            text: qsTr("Browse…")
                            onClicked: editorFileDialog.open()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            id: editorRefreshButton
                            objectName: "settingsEditorRefresh"
                            text: qsTr("Refresh detected editors")
                            flat: true
                            onClicked: DesktopIntegration.refreshEditors()
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            id: editorOpenWorkspaceButton
                            objectName: "settingsEditorOpenWorkspace"
                            text: qsTr("Open workspace")
                            enabled: DesktopIntegration.externalEditorAvailable
                                && WorkspaceManager.repositoryPath.length > 0
                            onClicked: DesktopIntegration.openInExternalEditor(WorkspaceManager.repositoryPath)
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: !DesktopIntegration.externalEditorAvailable
                        text: qsTr("No supported editor is currently available. Add a custom executable above.")
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }
                }

                // --- History ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8
                    visible: root.paletteRevealSection === "history"
                        || root.settingsMatch(qsTr("History retention commits open history manager 30 days 1 year forever"))

                    Text {
                        text: qsTr("HISTORY")
                        font.family: Typography.family
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: Theme.color("primary")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            id: historyRetentionLabel
                            objectName: "settingsHistoryRetention"
                            text: qsTr("Retention")
                            font.family: Typography.family
                            font.pixelSize: 14
                            color: Theme.color("onSurface")
                        }
                        Item { Layout.fillWidth: true }
                        Row {
                            spacing: 6
                            Repeater {
                                id: retentionChoices
                                model: root.retentionOptions
                                delegate: Rectangle {
                                    objectName: "settingsHistoryRetentionChoice." + index
                                    required property string modelData
                                    readonly property bool active: JournalController.retention === modelData
                                    focus: true
                                    activeFocusOnTab: true
                                    height: 30
                                    width: retLabel.implicitWidth + 26
                                    radius: 15
                                    color: active ? Theme.color("primaryContainer") : "transparent"
                                    border.width: activeFocus ? 2 : 1
                                    border.color: active || activeFocus ? Theme.color("primaryContainer") : Theme.color("outline")
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: qsTr("History retention: %1").arg(modelData)
                                    Accessible.checked: active
                                    Keys.onSpacePressed: JournalController.retention = modelData
                                    Keys.onReturnPressed: JournalController.retention = modelData
                                    Text {
                                        id: retLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: Typography.family; font.pixelSize: 13; font.weight: Font.DemiBold
                                        color: parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: JournalController.retention = modelData
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: openHistoryCard
                        objectName: "settingsOpenHistory"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 12
                        focus: true
                        activeFocusOnTab: true
                        color: openHistMouse.containsMouse ? Theme.color("surfaceContainerHigh") : Theme.color("surfaceVariant")
                        border.width: activeFocus ? 2 : 0
                        border.color: Theme.color("focusRing")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Open history manager")
                        Keys.onSpacePressed: root.openHistoryRequested()
                        Keys.onReturnPressed: root.openHistoryRequested()
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            MDIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "history"; size: 17; color: Theme.color("primary")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Open history manager")
                                font.family: Typography.family; font.pixelSize: 13; font.weight: Font.DemiBold
                                color: Theme.color("primary")
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("%1 commits").arg(JournalController.settingsCount)
                            font.family: Typography.monoFamily; font.pixelSize: 11
                            color: Theme.color("onSurfaceVariant")
                        }
                        MouseArea {
                            id: openHistMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openHistoryRequested()
                        }
                    }
                }

                // --- Full options link ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.bottomMargin: 20
                    spacing: 8
                    visible: root.paletteRevealSection === "options"
                        || root.settingsMatch(qsTr("All qBittorrent options advanced full settings"))

                    Rectangle {
                        id: fullOptionsCard
                        objectName: "settingsOpenFullOptions"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 12
                        focus: true
                        activeFocusOnTab: true
                        color: fullOptMouse.containsMouse ? Theme.color("surfaceContainerHigh") : Theme.color("surfaceVariant")
                        border.width: activeFocus ? 2 : 0
                        border.color: Theme.color("focusRing")
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("All qBittorrent options…")
                        Keys.onSpacePressed: root.openFullOptionsRequested()
                        Keys.onReturnPressed: root.openFullOptionsRequested()
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 8
                            MDIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "tune"; size: 17; color: Theme.color("onSurfaceVariant")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("All qBittorrent options…")
                                font.family: Typography.family; font.pixelSize: 13; font.weight: Font.DemiBold
                                color: Theme.color("onSurface")
                            }
                        }
                        MouseArea {
                            id: fullOptMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openFullOptionsRequested()
                        }
                    }
                }
            }
        }
    }

    Platform.FileDialog {
        id: editorFileDialog
        title: qsTr("Choose an external editor executable")
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: [qsTr("Applications (*.exe)"), qsTr("All files (*)")]
        onAccepted: DesktopIntegration.customEditorPath = file
    }

    onVisibleChanged: {
        if (!visible) {
            paletteRevealSection = ""
            highlightedPaletteSetting = ""
        }
    }
}
