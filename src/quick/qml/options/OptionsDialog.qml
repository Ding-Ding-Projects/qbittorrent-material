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
import qBittorrent

/*!
    \qmltype OptionsDialog
    \brief The Material Preferences dialog.

    A NavigationRail-style left list drives a \c StackLayout of the nine option
    pages (Behavior / Downloads / Connection / Speed / BitTorrent / Search / RSS /
    WebUI / Advanced). Every control on every page is bound to the
    \c OptionsController staging layer: reads go through
    \c OptionsController.value(key, default) (made reactive by the controller's
    \c revision counter) and edits stage through \c OptionsController.setValue(),
    which flips \c OptionsController.modified. The bottom button box mirrors the
    legacy OK / Cancel / Apply semantics: OK applies + closes, Apply applies and
    stays open, Cancel discards the staged changes.

    Language and color-scheme selectors bypass staging and drive \c I18n /
    \c ThemeManager live, exactly like the legacy immediate-apply behavior.
*/
Dialog {
    id: root

    title: qsTr("Options")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent

    // Cap to 90% of the window; the pages scroll internally.
    width: Math.min(1040, (parent ? parent.width : 1040) * 0.95)
    height: Math.min(760, (parent ? parent.height : 760) * 0.95)
    padding: 0

    Material.elevation: 0
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: Spacing.outlineWidth
        border.color: Theme.color("outline")
    }

    // The rail entries; each maps 1:1 to a StackLayout page by index (mirrors the
    // legacy Tabs enum order TAB_UI..TAB_ADVANCED).
    readonly property var pages: [
        { icon: Icons.palette,          label: qsTr("Behavior") },
        { icon: Icons.download,         label: qsTr("Downloads") },
        { icon: Icons.lan,              label: qsTr("Connection") },
        { icon: Icons.speed,            label: qsTr("Speed") },
        { icon: Icons.swap_vert,        label: qsTr("BitTorrent") },
        { icon: Icons.search,           label: qsTr("Search") },
        { icon: Icons.rss_feed,         label: qsTr("RSS") },
        { icon: Icons.language,         label: qsTr("Web UI") },
        { icon: Icons.settings_suggest, label: qsTr("Advanced") }
    ]
    readonly property var pageSearchCorpus: [
        qsTr("Behavior language English Cantonese bilingual funny level warnings errors theme tray startup confirmation"),
        qsTr("Downloads save path incomplete files email notification watched folders external program"),
        qsTr("Connection port proxy IP filter protocol limits UPnP interface address"),
        qsTr("Speed upload download rate limits scheduler alternative limits bandwidth"),
        qsTr("BitTorrent privacy encryption queue seeding ratio DHT PeX trackers"),
        qsTr("Search plugins Python engine results"),
        qsTr("RSS feeds refresh interval auto download rules"),
        qsTr("Web UI API key HTTPS authentication address port dynamic DNS"),
        qsTr("Advanced libtorrent cache network disk Python recheck")
    ]
    property var tabSearchState: ["", "", "", "", "", "", "", "", ""]
    property var paletteSettingEntries: []
    property var paletteSettingTargets: ({})
    property string highlightedPaletteSetting: ""
    property real paletteHighlightX: 0
    property real paletteHighlightY: 0
    property real paletteHighlightWidth: 0
    property real paletteHighlightHeight: 0
    readonly property int paletteRevision: OptionsController.revision

    function paletteSettingId(pageIndex, settingKey) {
        return "options." + pageIndex + "." + encodeURIComponent(settingKey)
    }

    function humanizePaletteKey(settingKey) {
        var parts = String(settingKey).split("/")
        var leaf = parts.length ? parts[parts.length - 1] : String(settingKey)
        return leaf.replace(/([a-z0-9])([A-Z])/g, "$1 $2")
            .replace(/[_-]+/g, " ").trim()
    }

    function inferPaletteControlKind(item, declaredKind, sensitive) {
        if (sensitive)
            return "password"
        if (declaredKind === "toggle")
            return "toggle"
        if (item.currentIndex !== undefined && item.model !== undefined)
            return "select"
        if (item.path !== undefined)
            return "path"
        if (item.value !== undefined && item.from !== undefined
                && item.to !== undefined) {
            return item.editable !== undefined ? "spin" : "slider"
        }
        if (item.text !== undefined)
            return "text"
        return declaredKind === "action" ? "action" : "readonly"
    }

    function paletteChoices(item) {
        var choices = []
        if (!item || item.count === undefined || item.textAt === undefined)
            return choices
        for (var index = 0; index < item.count; ++index)
            choices.push(item.textAt(index))
        return choices
    }

    function paletteTargetValue(item, controlKind, fallback) {
        if (!item)
            return fallback
        switch (controlKind) {
        case "toggle": return item.checked
        case "select": return item.currentIndex
        case "slider":
        case "spin": return item.value
        case "path": return item.path
        case "text": return item.text
        default: return fallback
        }
    }

    function collectPaletteSettings(item, pageIndex, entries, targets, seen) {
        if (!item)
            return

        var settingKey = item.paletteSettingKey === undefined
            ? "" : String(item.paletteSettingKey)
        if (settingKey.length > 0) {
            var settingId = root.paletteSettingId(pageIndex, settingKey)
            if (!seen[settingId]) {
                var title = item.paletteSettingTitle === undefined
                    ? "" : String(item.paletteSettingTitle)
                if (!title.length)
                    title = root.humanizePaletteKey(settingKey)
                var declaredKind = item.paletteSettingKind === undefined
                    ? "destination" : String(item.paletteSettingKind)
                var sensitive = item.paletteSettingSensitive === true
                var controlKind = root.inferPaletteControlKind(
                    item, declaredKind, sensitive)
                var defaultValue = item.paletteSettingDefault === undefined
                    ? undefined : item.paletteSettingDefault
                item.objectName = "paletteTarget." + settingId
                entries.push({
                    settingId: settingId,
                    settingKey: settingKey,
                    pageIndex: pageIndex,
                    title: title,
                    description: item.paletteSettingDescription === undefined
                        ? "" : String(item.paletteSettingDescription),
                    controlKind: controlKind,
                    defaultValue: defaultValue,
                    sensitive: sensitive,
                    targetId: item.objectName
                })
                targets[settingId] = item
                seen[settingId] = true
            }
        }

        // Page actions without a backing scalar setting still belong in the
        // palette. Their explicit, language-independent keys keep command IDs
        // stable across locale changes. Calling the existing clicked signal
        // preserves native file pickers, confirmation dialogs, validation, and
        // collection editors rather than duplicating those flows here.
        var paletteActionKey = item.paletteActionKey === undefined
            ? "" : String(item.paletteActionKey)
        if (!settingKey.length && paletteActionKey.length > 0
                && item.clicked !== undefined) {
            var actionId = "options.action." + pageIndex + "."
                + encodeURIComponent(paletteActionKey)
            var actionTitle = item.paletteActionTitle === undefined
                ? "" : String(item.paletteActionTitle)
            if (!actionTitle.length && item.text !== undefined)
                actionTitle = String(item.text)
            if (!actionTitle.length && item.tooltip !== undefined)
                actionTitle = String(item.tooltip)
            if (!actionTitle.length)
                actionTitle = root.humanizePaletteKey(paletteActionKey)
            if (seen[actionId]) {
                Log.warning("ui", "Duplicate Options palette action id: " + actionId)
                return
            }
            item.objectName = "paletteTarget." + actionId
            entries.push({
                settingId: actionId,
                settingKey: "",
                pageIndex: pageIndex,
                title: actionTitle,
                description: item.paletteActionDescription === undefined
                    ? "" : String(item.paletteActionDescription),
                keywords: item.paletteActionKeywords === undefined
                    ? "" : String(item.paletteActionKeywords),
                controlKind: "action",
                defaultValue: undefined,
                sensitive: false,
                targetId: item.objectName
            })
            targets[actionId] = item
            seen[actionId] = true
        }

        var children = item.children
        if (!children)
            return
        for (var childIndex = 0; childIndex < children.length; ++childIndex)
            root.collectPaletteSettings(children[childIndex], pageIndex,
                entries, targets, seen)
    }

    function rebuildPaletteRegistry() {
        var entries = []
        var targets = ({})
        var seen = ({})
        var pageItems = stack.children
        for (var pageIndex = 0; pageIndex < root.pages.length
                && pageIndex < pageItems.length; ++pageIndex) {
            root.collectPaletteSettings(pageItems[pageIndex], pageIndex,
                entries, targets, seen)
        }
        entries.sort(function(left, right) {
            if (left.pageIndex !== right.pageIndex)
                return left.pageIndex - right.pageIndex
            return left.title.localeCompare(right.title)
        })
        root.paletteSettingTargets = targets
        root.paletteSettingEntries = entries
    }

    function paletteCommands() {
        // Explicit reads keep the palette binding reactive as staged values and
        // its safe-inline-edit state change.
        var revision = root.paletteRevision
        var hasPendingEdits = OptionsController.modified
        if (!root.paletteSettingEntries.length)
            root.rebuildPaletteRegistry()

        var commands = []
        for (var index = 0; index < root.paletteSettingEntries.length; ++index) {
            var entry = root.paletteSettingEntries[index]
            var target = root.paletteSettingTargets[entry.settingId]
            var fallbackValue = entry.settingKey.length
                ? OptionsController.value(entry.settingKey, entry.defaultValue)
                : undefined
            var value = root.paletteTargetValue(target, entry.controlKind, fallbackValue)
            var inlineToggle = entry.controlKind === "toggle" && !entry.sensitive
            var editableControl = entry.controlKind !== "readonly"
                && entry.controlKind !== "password"
            var currentText = entry.sensitive
                ? qsTr("Sensitive value hidden")
                : (entry.controlKind === "action" ? qsTr("Action") : (inlineToggle
                    ? (value ? qsTr("Enabled") : qsTr("Disabled"))
                    : qsTr("Current: %1").arg(String(value).slice(0, 160))))
            commands.push({
                id: "setting." + entry.settingId,
                kind: "setting",
                settingId: entry.settingId,
                settingScope: "options",
                title: entry.title,
                group: qsTr("Option setting"),
                destination: qsTr("Options · %1").arg(root.pages[entry.pageIndex].label),
                context: currentText,
                keywords: entry.settingKey + " " + entry.description
                    + " " + (entry.keywords || "")
                    + (entry.sensitive ? "" : (" " + String(value))),
                targetId: entry.targetId,
                inlineControl: entry.controlKind,
                inlineEditable: editableControl && !hasPendingEdits
                    && target && target.enabled !== false,
                checked: inlineToggle ? !!value : false,
                value: value,
                valueText: entry.sensitive ? "" : String(value),
                choices: entry.controlKind === "select"
                    ? root.paletteChoices(target) : [],
                minimum: target && target.from !== undefined ? target.from : 0,
                maximum: target && target.to !== undefined ? target.to : 100,
                step: target && target.stepSize !== undefined ? target.stepSize : 1,
                actionLabel: entry.controlKind === "action" ? entry.title : "",
                sensitive: entry.sensitive,
                enabled: entry.controlKind === "action"
                    ? !!target && target.enabled !== false : true
            })
        }
        return commands
    }

    function ensureOpenForPalette() {
        if (root.visible)
            return
        Log.info("ui", "OptionsDialog opening from command palette")
        OptionsController.load()
        rail.currentIndex = Preferences.value("GUI/Preferences/LastViewedPage", 0)
        root.visible = true
    }

    function revealThroughFlickables(target) {
        var ancestor = target ? target.parent : null
        while (ancestor) {
            if (ancestor.contentY !== undefined
                    && ancestor.contentHeight !== undefined
                    && ancestor.contentItem !== undefined
                    && ancestor.height > 0) {
                var mapped = target.mapToItem(ancestor.contentItem, 0, 0)
                var margin = Spacing.lg
                var targetTop = Math.max(0, mapped.y - margin)
                var targetBottom = mapped.y + Math.max(target.height, Spacing.controlHeight) + margin
                if (targetTop < ancestor.contentY)
                    ancestor.contentY = targetTop
                else if (targetBottom > ancestor.contentY + ancestor.height)
                    ancestor.contentY = Math.min(
                        Math.max(0, ancestor.contentHeight - ancestor.height),
                        targetBottom - ancestor.height)
            }
            ancestor = ancestor.parent
        }
    }

    function finishPaletteReveal(settingId) {
        var target = root.paletteSettingTargets[settingId]
        if (!target)
            return false
        root.revealThroughFlickables(target)
        var mapped = target.mapToItem(root.contentItem, 0, 0)
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

    function showSetting(settingId) {
        root.ensureOpenForPalette()
        if (!root.paletteSettingTargets[settingId])
            root.rebuildPaletteRegistry()
        for (var index = 0; index < root.paletteSettingEntries.length; ++index) {
            var entry = root.paletteSettingEntries[index]
            if (entry.settingId !== settingId)
                continue
            rail.currentIndex = entry.pageIndex
            Qt.callLater(function() { root.finishPaletteReveal(settingId) })
            return true
        }
        Log.warning("ui", "Options palette target not found: " + settingId)
        return false
    }

    function setPaletteSetting(settingId, value) {
        root.ensureOpenForPalette()
        if (!root.paletteSettingTargets[settingId])
            root.rebuildPaletteRegistry()
        for (var index = 0; index < root.paletteSettingEntries.length; ++index) {
            var entry = root.paletteSettingEntries[index]
            if (entry.settingId !== settingId)
                continue
            var target = root.paletteSettingTargets[settingId]
            if (!target || entry.controlKind === "readonly"
                    || entry.controlKind === "password" || entry.sensitive)
                return root.showSetting(settingId)
            if (entry.controlKind === "action") {
                target.clicked()
                return true
            }
            if (entry.controlKind === "select" && target.activated !== undefined) {
                // Emit the original control signal so non-linear display-index
                // mappings (proxy type, share-limit action, and similar) stay
                // in one source of truth.
                target.activated(Number(value))
            }
            else if (entry.settingKey.length) {
                var stagedValue = entry.controlKind === "toggle" ? !!value : value
                if (entry.settingKey === "BitTorrent/Session/GlobalMaxRatio")
                    stagedValue = Number(value) / 100
                OptionsController.setValue(entry.settingKey, stagedValue)
            }
            return root.showSetting(settingId)
        }
        return false
    }

    function searchMatches(index) {
        var query = optionsSearch.text.trim()
        if (!query.length)
            return false
        var text = pages[index].label + " " + pageSearchCorpus[index]
        if (optionsSearch.regexEnabled) {
            var evaluated = WorkspaceManager.evaluateRegularExpression(query,
                optionsSearch.regexFlags, text)
            return evaluated.valid && evaluated.count > 0
        }
        return text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
    }

    function matchingPageIndexes() {
        var result = []
        for (var i = 0; i < pages.length; ++i)
            if (searchMatches(i)) result.push(i)
        return result
    }

    function open() {
        if (!visible) {
            Log.info("ui", "OptionsDialog opening; reloading staged settings")
            OptionsController.load()
            rail.currentIndex = Preferences.value("GUI/Preferences/LastViewedPage", 0)
            visible = true
        }
    }

    // Public slot (mirrors the legacy OptionsDialog::showConnectionTab): open the
    // dialog straight on the Connection page (TAB_CONNECTION == index 2). Used by
    // the status-bar connection indicator.
    function showConnectionTab() {
        Log.info("ui", "OptionsDialog: showConnectionTab()")
        open()
        rail.currentIndex = 2
    }

    function showPage(index) {
        Log.info("ui", "OptionsDialog: showPage(" + index + ")")
        open()
        rail.currentIndex = Math.max(0, Math.min(index, pages.length - 1))
    }

    Timer {
        id: paletteHighlightTimer
        interval: 1800
        repeat: false
        onTriggered: root.highlightedPaletteSetting = ""
    }

    Rectangle {
        parent: root.contentItem
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

    onAccepted: {
        Log.info("ui", "OptionsDialog OK — applying settings")
        OptionsController.apply()
    }
    onRejected: {
        Log.info("ui", "OptionsDialog Cancel — discarding staged settings")
        OptionsController.reset()
    }

    header: Rectangle {
        implicitHeight: optionsHeading.implicitHeight + Spacing.xl * 2
        color: "transparent"

        ColumnLayout {
            id: optionsHeading
            anchors.fill: parent
            anchors.leftMargin: Spacing.pagePadding
            anchors.rightMargin: Spacing.pagePadding
            anchors.topMargin: Spacing.xl
            anchors.bottomMargin: Spacing.xl
            spacing: Spacing.xs

            Label {
                Layout.fillWidth: true
                text: root.title
                font: Typography.pageTitle
                color: Theme.color("onSurface")
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Application behavior, connection, download, BitTorrent, RSS, and advanced controls.")
                font: Typography.metadata
                color: Theme.color("muted")
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Spacing.outlineWidth
            color: Theme.color("outlineVariant")
        }
    }

    contentItem: RowLayout {
        spacing: 0

        // ---- NavigationRail-style left list -----------------------------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: Theme.color("surfaceWarm")

            // Right divider (rail elevation 0 + outline per DESIGN_SYSTEM §3).
            Rectangle {
                anchors.right: parent.right
                width: Spacing.outlineWidth
                height: parent.height
                color: Theme.color("outlineVariant")
            }

            ListView {
                id: rail
                anchors.fill: parent
                anchors.margins: Spacing.lg
                spacing: Spacing.sm
                clip: true
                currentIndex: 0
                model: root.pages
                boundsBehavior: Flickable.StopAtBounds

                onCurrentIndexChanged: {
                    Log.debug("ui", "Options page -> " + currentIndex
                              + " (" + (root.pages[currentIndex] ? root.pages[currentIndex].label : "?") + ")")
                    Preferences.setValue("GUI/Preferences/LastViewedPage", currentIndex)
                    optionsSearch.text = root.tabSearchState[currentIndex] || ""
                }

                delegate: ItemDelegate {
                    id: railItem
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: Spacing.controlHeight
                    highlighted: rail.currentIndex === index
                    onClicked: rail.currentIndex = index

                    background: Rectangle {
                        radius: Spacing.radiusControl
                        color: railItem.highlighted
                               ? Theme.color("primaryContainer")
                               : (railItem.hovered
                                  ? Theme.color("surface")
                                  : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: Spacing.motionFast }
                        }
                    }

                    contentItem: RowLayout {
                        spacing: Spacing.sm
                        MDIcon {
                            icon: railItem.modelData.icon
                            size: Spacing.iconSizeSmall
                            color: railItem.highlighted
                                   ? Theme.color("onPrimaryContainer")
                                   : Theme.color("onSurfaceVariant")
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: railItem.modelData.label
                            font: Typography.titleSmall
                            elide: Text.ElideRight
                            color: railItem.highlighted
                                   ? Theme.color("onPrimaryContainer")
                                   : Theme.color("onSurface")
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }

        // ---- Searchable page stack --------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Spacing.sm

            FilterTextField {
                id: optionsSearch
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.lg
                Layout.rightMargin: Spacing.lg
                Layout.topMargin: Spacing.md
                placeholder: qsTr("Search %1 settings…").arg(root.pages[rail.currentIndex].label)
                builderTitle: qsTr("%1 Settings Regex Builder").arg(root.pages[rail.currentIndex].label)
                builderSampleText: root.pageSearchCorpus[rail.currentIndex]
                onTextChanged: {
                    var next = root.tabSearchState.slice(0)
                    next[rail.currentIndex] = text
                    root.tabSearchState = next
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.lg
                Layout.rightMargin: Spacing.lg
                spacing: Spacing.xs
                visible: optionsSearch.text.trim().length > 0

                Label {
                    text: root.matchingPageIndexes().length === 0
                        ? qsTr("No option labels or descriptions match on any tab.")
                        : qsTr("Matches on:")
                    color: root.matchingPageIndexes().length === 0
                        ? Theme.color("error") : Theme.color("onSurfaceVariant")
                    font: Typography.bodySmall
                }
                Repeater {
                    model: root.matchingPageIndexes()
                    delegate: Button {
                        required property int modelData
                        text: modelData === rail.currentIndex
                            ? root.pages[modelData].label
                            : qsTr("%1 (different tab)").arg(root.pages[modelData].label)
                        flat: true
                        onClicked: rail.currentIndex = modelData
                    }
                }
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: rail.currentIndex

                BehaviorPage {}
                DownloadsPage {}
                ConnectionPage {}
                SpeedPage {}
                BitTorrentPage {}

                SearchPage {}
                RSSPage {}
                WebUIPage {}
                AdvancedPage {}
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.xl
        topPadding: Spacing.lg
        spacing: Spacing.sm

        background: Rectangle {
            color: "transparent"
            border.width: 0

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Spacing.outlineWidth
                color: Theme.color("outlineVariant")
            }
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("Apply")
            flat: true
            enabled: OptionsController.modified
            DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
            onClicked: {
                Log.info("ui", "OptionsDialog Apply")
                OptionsController.apply()
            }
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onClosed: highlightedPaletteSetting = ""

    Component.onCompleted: {
        Log.debug("ui", "OptionsDialog constructed")
        Qt.callLater(root.rebuildPaletteRegistry)
    }
}
