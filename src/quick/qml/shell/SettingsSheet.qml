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

    signal closeRequested()
    signal openHistoryRequested()
    signal openFullOptionsRequested()

    readonly property var styleCards: [
        { style: 0, name: qsTr("Tonal Rail"), desc: qsTr("Nav rail + chips, comfortable rows") },
        { style: 1, name: qsTr("Split Dock"), desc: qsTr("Classic sidebar, dense table, dock") },
        { style: 2, name: qsTr("Card Flow"), desc: qsTr("Cards + persistent detail panel") }
    ]
    readonly property var retentionOptions: ["30 days", "1 year", "Forever"]

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
                    visible: root.settingsMatch(qsTr("Appearance theme light dark UI style density accent seed color font family size weight reduced motion reset"))

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
                        text: qsTr("UI style")
                        font.family: Typography.family
                        font.pixelSize: 14
                        color: Theme.color("onSurface")
                    }

                    Repeater {
                        model: root.styleCards
                        delegate: Rectangle {
                            id: styleCard
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
                            Layout.fillWidth: true
                            from: 0.8; to: 1.35; stepSize: 0.05
                            value: ThemeManager.densityScale
                            Accessible.name: qsTr("Interface density")
                            onMoved: ThemeManager.densityScale = value
                        }
                        Label { text: Number(ThemeManager.densityScale).toFixed(2) + "×"; font.family: Typography.monoFamily }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: qsTr("Accent / seed color"); color: Theme.color("onSurface") }
                        TextField {
                            id: seedColorField
                            Layout.fillWidth: true
                            text: ThemeManager.seedColor
                            placeholderText: "#6750A4"
                            maximumLength: 32
                            Accessible.name: qsTr("Material seed color")
                        }
                        Button {
                            text: qsTr("Apply")
                            enabled: seedColorField.text.length > 0
                            onClicked: ThemeManager.seedColor = seedColorField.text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.xs
                        Label { text: qsTr("UI font family"); color: Theme.color("onSurface") }
                        ComboBox {
                            id: fontFamilyCombo
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
                            checked: ThemeManager.reducedMotion
                            Accessible.name: qsTr("Reduce interface motion")
                            onToggled: ThemeManager.reducedMotion = checked
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Reset global appearance")
                        flat: true
                        onClicked: ThemeManager.resetAppearance()
                    }
                }

                // --- Startup delight ----------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8
                    visible: root.settingsMatch(qsTr("Dim sum startup surprise 10% local picture quiet reduced motion"))

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
                            text: qsTr("Uses one fresh launch draw and bundled local images. It never appears on first run or while a blocking flow is active, and it cannot be disabled.")
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
                    visible: root.settingsMatch(qsTr("External editor Visual Studio Code VSCodium Cursor Sublime Notepad custom project folder"))

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
                            Layout.fillWidth: true
                            text: DesktopIntegration.customEditorPath
                            placeholderText: qsTr("Custom editor executable")
                            Accessible.name: placeholderText
                            onEditingFinished: DesktopIntegration.customEditorPath = text
                        }
                        Button { text: qsTr("Browse…"); onClicked: editorFileDialog.open() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: qsTr("Refresh detected editors")
                            flat: true
                            onClicked: DesktopIntegration.refreshEditors()
                        }
                        Item { Layout.fillWidth: true }
                        Button {
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
                    visible: root.settingsMatch(qsTr("History retention commits open history manager 30 days 1 year forever"))

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
                            text: qsTr("Retention")
                            font.family: Typography.family
                            font.pixelSize: 14
                            color: Theme.color("onSurface")
                        }
                        Item { Layout.fillWidth: true }
                        Row {
                            spacing: 6
                            Repeater {
                                model: root.retentionOptions
                                delegate: Rectangle {
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
                    visible: root.settingsMatch(qsTr("All qBittorrent options advanced full settings"))

                    Rectangle {
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
}
