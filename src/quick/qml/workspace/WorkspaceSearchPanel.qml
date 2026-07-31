/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

Popup {
    id: root

    property Item returnFocusItem: null
    property string lastActivated: ""
    property var groupSearchState: ({})

    property string stripQuery: ""
    property bool stripRegex: false
    property string stripFlags: "iu"
    property string groupNameQuery: ""
    property bool groupNameRegex: false
    property string groupNameFlags: "iu"
    property string masterQuery: ""
    property bool masterRegex: false
    property string masterFlags: "iu"
    property string closeQuery: ""
    property bool closeRegex: false
    property string closeFlags: "iu"
    property bool closeInverse: false
    property bool closeIncludePinned: false
    property string closeGroupId: ""

    readonly property var stripResult: WorkspaceManager.searchTabs(
        stripQuery, stripRegex, stripFlags, "")
    readonly property var groupNameResult: WorkspaceManager.searchGroups(
        groupNameQuery, groupNameRegex, groupNameFlags)
    readonly property var masterResult: WorkspaceManager.searchTabs(
        masterQuery, masterRegex, masterFlags, "")
    readonly property var closePreview: WorkspaceManager.previewCloseTabs(
        closeQuery, closeRegex, closeFlags, closeInverse,
        closeIncludePinned, closeGroupId)

    signal revealTab(string tabId)
    signal editGroupAppearance(string groupId, Item anchorItem)

    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(760, parent ? parent.width - Spacing.xl * 2 : 760)
    height: Math.min(680, parent ? parent.height - Spacing.xl * 2 : 680)
    padding: 0
    Material.elevation: 16

    function openFrom(item, groupId) {
        returnFocusItem = item
        modes.currentIndex = groupId && groupId.length ? 1 : 0
        open()
        stripSearch.forceActiveFocus()
    }

    function activateResult(item, field) {
        if (!item || item.index === undefined)
            return
        WorkspaceManager.activeIndex = item.index
        root.revealTab(item.tabId)
        lastActivated = qsTr("Activated %1 in %2 · %3%4")
            .arg(item.name).arg(item.location)
            .arg(item.pinned ? qsTr("Pinned") : qsTr("Ordinary"))
            .arg(item.groupCollapsed ? qsTr(" · group remains collapsed") : "")
        field.forceActiveFocus()
    }

    function stateForGroup(groupId) {
        if (!groupSearchState[groupId])
            groupSearchState[groupId] = { query: "", regex: false, flags: "iu" }
        return groupSearchState[groupId]
    }

    function storeGroupState(groupId, query, regex, flags) {
        var clone = Object.assign({}, groupSearchState)
        clone[groupId] = { query: query, regex: regex, flags: flags }
        groupSearchState = clone
        Preferences.setValue("Workspace/GroupSearchState", JSON.stringify(clone))
        Preferences.apply()
    }

    function persistSearchState() {
        Preferences.setValue("Workspace/StripSearchQuery", stripQuery)
        Preferences.setValue("Workspace/StripSearchRegex", stripRegex)
        Preferences.setValue("Workspace/StripSearchFlags", stripFlags)
        Preferences.setValue("Workspace/GroupNameSearchQuery", groupNameQuery)
        Preferences.setValue("Workspace/GroupNameSearchRegex", groupNameRegex)
        Preferences.setValue("Workspace/GroupNameSearchFlags", groupNameFlags)
        Preferences.setValue("Workspace/MasterSearchQuery", masterQuery)
        Preferences.setValue("Workspace/MasterSearchRegex", masterRegex)
        Preferences.setValue("Workspace/MasterSearchFlags", masterFlags)
        Preferences.apply()
    }

    Component.onCompleted: {
        stripQuery = "" + Preferences.value("Workspace/StripSearchQuery", "")
        stripRegex = !!Preferences.value("Workspace/StripSearchRegex", false)
        stripFlags = "" + Preferences.value("Workspace/StripSearchFlags", "iu")
        groupNameQuery = "" + Preferences.value("Workspace/GroupNameSearchQuery", "")
        groupNameRegex = !!Preferences.value("Workspace/GroupNameSearchRegex", false)
        groupNameFlags = "" + Preferences.value("Workspace/GroupNameSearchFlags", "iu")
        masterQuery = "" + Preferences.value("Workspace/MasterSearchQuery", "")
        masterRegex = !!Preferences.value("Workspace/MasterSearchRegex", false)
        masterFlags = "" + Preferences.value("Workspace/MasterSearchFlags", "iu")
        var storedGroups = "" + Preferences.value("Workspace/GroupSearchState", "")
        if (storedGroups.length) {
            try { groupSearchState = JSON.parse(storedGroups) }
            catch (error) { groupSearchState = ({}) }
        }
    }

    onClosed: {
        persistSearchState()
        if (returnFocusItem)
            returnFocusItem.forceActiveFocus()
    }

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outlineVariant")
    }

    component SearchResults: ListView {
        id: resultList
        required property var searchResult
        required property Item searchField
        signal activateRequested(var item, Item field)

        clip: true
        spacing: Spacing.xs
        model: searchResult.items || []
        Accessible.name: qsTr("Tab search results")
        Accessible.role: Accessible.List
        boundsBehavior: Flickable.StopAtBounds

        delegate: ItemDelegate {
            required property var modelData
            width: ListView.view.width
            height: Math.max(54, resultContent.implicitHeight + Spacing.sm * 2)
            Accessible.name: qsTr("%1, %2, %3, %4")
                .arg(modelData.name)
                .arg(modelData.location)
                .arg(modelData.pinned ? qsTr("pinned") : qsTr("not pinned"))
                .arg(modelData.groupCollapsed ? qsTr("collapsed group") : qsTr("visible group"))
            onClicked: resultList.activateRequested(modelData, resultList.searchField)
            contentItem: RowLayout {
                id: resultContent
                spacing: Spacing.sm
                MDIcon {
                    icon: modelData.pinned ? Icons.lock : Icons.article
                    size: 18
                    color: modelData.groupColor && modelData.groupColor !== "#00000000"
                        ? modelData.groupColor : Theme.color("primary")
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        textFormat: Text.PlainText
                        font: Typography.titleSmall
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("%1 · %2 · %3%4")
                            .arg(modelData.window).arg(modelData.strip)
                            .arg(modelData.location)
                            .arg(modelData.pinned ? qsTr(" · Pinned") : "")
                        textFormat: Text.PlainText
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        elide: Text.ElideRight
                    }
                }
                MDIcon { icon: Icons.chevron_right; size: 18; color: Theme.color("onSurfaceVariant") }
            }
        }

        Label {
            anchors.centerIn: parent
            visible: resultList.count === 0
            text: resultList.searchResult.valid
                ? qsTr("No matching tabs") : resultList.searchResult.error
            color: resultList.searchResult.valid
                ? Theme.color("onSurfaceVariant") : Theme.color("error")
            wrapMode: Text.WordWrap
            width: Math.min(360, parent.width * 0.8)
            horizontalAlignment: Text.AlignHCenter
        }
    }

    contentItem: ColumnLayout {
        spacing: 0
        Accessible.name: qsTr("Workspace tab search and management")
        Accessible.role: Accessible.Dialog

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.md
            spacing: Spacing.sm
            MDIcon { icon: Icons.search; size: 22; color: Theme.color("primary") }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: qsTr("Find and manage workspace tabs"); font: Typography.titleLarge }
                Label {
                    text: qsTr("Every search has independent plain-text/regex state and its own adjacent builder.")
                    font: Typography.bodySmall
                    color: Theme.color("onSurfaceVariant")
                }
            }
            IconButton {
                symbol: Icons.close
                tooltip: qsTr("Close and return to tab strip")
                onClicked: root.close()
            }
        }

        TabBar {
            id: modes
            Layout.fillWidth: true
            Accessible.name: qsTr("Workspace search modes")
            TabButton { text: qsTr("Current strip") }
            TabButton { text: qsTr("Groups") }
            TabButton { text: qsTr("All tabs") }
            TabButton { text: qsTr("Bulk close") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: modes.currentIndex

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Spacing.md
                    spacing: Spacing.sm
                    FilterTextField {
                        id: stripSearch
                        Layout.fillWidth: true
                        placeholder: qsTr("Search this workspace tab strip")
                        builderTitle: qsTr("Current-strip Regex Builder")
                        text: root.stripQuery
                        regexEnabled: root.stripRegex
                        regexFlags: root.stripFlags
                        builderSampleText: WorkspaceManager.tabItems.map(function(tab) {
                            return tab.name
                        }).join("\n")
                        onTextChanged: root.stripQuery = text
                        onRegexEnabledChanged: root.stripRegex = regexEnabled
                        onRegexFlagsChanged: root.stripFlags = regexFlags
                    }
                    Label {
                        text: qsTr("%1 result(s) · Workspace window · current strip")
                            .arg(root.stripResult.count)
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                    }
                    SearchResults {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        searchResult: root.stripResult
                        searchField: stripSearch
                        onActivateRequested: function(item, field) { root.activateResult(item, field) }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Spacing.md
                    spacing: Spacing.sm

                    FilterTextField {
                        id: groupNameSearch
                        Layout.fillWidth: true
                        placeholder: qsTr("Search tab groups by visible name")
                        builderTitle: qsTr("Group-name Regex Builder")
                        text: root.groupNameQuery
                        regexEnabled: root.groupNameRegex
                        regexFlags: root.groupNameFlags
                        builderSampleText: WorkspaceManager.groups.map(function(group) {
                            return group.name
                        }).join("\n")
                        onTextChanged: root.groupNameQuery = text
                        onRegexEnabledChanged: root.groupNameRegex = regexEnabled
                        onRegexFlagsChanged: root.groupNameFlags = regexFlags
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: newGroupName
                            Layout.fillWidth: true
                            placeholderText: qsTr("New group name")
                            maximumLength: 80
                        }
                        TextField {
                            id: newGroupColor
                            Layout.preferredWidth: 130
                            text: "#6750A4"
                            placeholderText: qsTr("#RRGGBB")
                            maximumLength: 9
                        }
                        Button {
                            text: qsTr("Create group")
                            enabled: newGroupName.text.trim().length > 0
                            onClicked: {
                                var id = WorkspaceManager.createGroup(newGroupName.text,
                                    newGroupColor.text)
                                if (id.length)
                                    newGroupName.clear()
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ColumnLayout {
                            width: Math.max(0, parent.width)
                            spacing: Spacing.sm

                            Repeater {
                                model: root.groupNameResult.items || []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: groupColumn.implicitHeight + Spacing.md * 2
                                    radius: Spacing.radiusCard
                                    color: Theme.color("surfaceVariant")
                                    border.width: 1
                                    border.color: modelData.color

                                    ColumnLayout {
                                        id: groupColumn
                                        anchors.fill: parent
                                        anchors.margins: Spacing.md
                                        spacing: Spacing.xs

                                        RowLayout {
                                            Layout.fillWidth: true
                                            IconButton {
                                                symbol: modelData.collapsed ? Icons.chevron_right : Icons.expand_more
                                                tooltip: modelData.collapsed ? qsTr("Expand group") : qsTr("Collapse group")
                                                onClicked: WorkspaceManager.setGroupCollapsed(
                                                    modelData.groupId, !modelData.collapsed)
                                            }
                                            TextField {
                                                id: groupNameEditor
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                maximumLength: 80
                                                Accessible.name: qsTr("Group name")
                                                onEditingFinished: WorkspaceManager.updateGroup(
                                                    modelData.groupId, text, groupColorEditor.text)
                                            }
                                            TextField {
                                                id: groupColorEditor
                                                Layout.preferredWidth: 130
                                                text: modelData.color
                                                maximumLength: 9
                                                Accessible.name: qsTr("Group color")
                                                onEditingFinished: WorkspaceManager.updateGroup(
                                                    modelData.groupId, groupNameEditor.text, text)
                                            }
                                            IconButton {
                                                id: editGroupButton
                                                symbol: Icons.palette
                                                tooltip: qsTr("Edit group appearance…")
                                                onClicked: root.editGroupAppearance(modelData.groupId,
                                                    editGroupButton)
                                            }
                                            IconButton {
                                                symbol: Icons.deleteIcon
                                                tooltip: qsTr("Remove group; keep its tabs")
                                                onClicked: WorkspaceManager.removeGroup(modelData.groupId)
                                            }
                                        }

                                        FilterTextField {
                                            id: perGroupSearch
                                            Layout.fillWidth: true
                                            property var stored: root.stateForGroup(modelData.groupId)
                                            property var groupResult: WorkspaceManager.searchTabs(
                                                text, regexEnabled, regexFlags, modelData.groupId)
                                            placeholder: qsTr("Search only %1").arg(modelData.name)
                                            builderTitle: qsTr("Regex Builder for %1").arg(modelData.name)
                                            text: stored.query || ""
                                            regexEnabled: !!stored.regex
                                            regexFlags: stored.flags || "iu"
                                            builderSampleText: WorkspaceManager.tabItems.filter(function(tab) {
                                                return tab.groupId === modelData.groupId
                                            }).map(function(tab) { return tab.name }).join("\n")
                                            onTextChanged: root.storeGroupState(modelData.groupId,
                                                text, regexEnabled, regexFlags)
                                            onRegexEnabledChanged: root.storeGroupState(modelData.groupId,
                                                text, regexEnabled, regexFlags)
                                            onRegexFlagsChanged: root.storeGroupState(modelData.groupId,
                                                text, regexEnabled, regexFlags)
                                        }

                                        Repeater {
                                            model: perGroupSearch.groupResult.items || []
                                            delegate: ItemDelegate {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                text: qsTr("%1 · %2%3")
                                                    .arg(modelData.name)
                                                    .arg(modelData.pinned ? qsTr("Pinned") : qsTr("Ordinary"))
                                                    .arg(modelData.groupCollapsed ? qsTr(" · collapsed group") : "")
                                                onClicked: root.activateResult(modelData, perGroupSearch)
                                            }
                                        }
                                        Label {
                                            visible: perGroupSearch.groupResult.count === 0
                                            text: qsTr("No tabs in this group match.")
                                            color: Theme.color("onSurfaceVariant")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Spacing.md
                    spacing: Spacing.sm
                    FilterTextField {
                        id: masterSearch
                        Layout.fillWidth: true
                        placeholder: qsTr("Search every workspace tab in every app-owned strip")
                        builderTitle: qsTr("Master tab-search Regex Builder")
                        text: root.masterQuery
                        regexEnabled: root.masterRegex
                        regexFlags: root.masterFlags
                        builderSampleText: WorkspaceManager.tabItems.map(function(tab) {
                            return tab.name
                        }).join("\n")
                        onTextChanged: root.masterQuery = text
                        onRegexEnabledChanged: root.masterRegex = regexEnabled
                        onRegexFlagsChanged: root.masterFlags = regexFlags
                    }
                    Label {
                        text: qsTr("%1 result(s); each result identifies window, strip, group, pin, and collapsed state.")
                            .arg(root.masterResult.count)
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }
                    SearchResults {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        searchResult: root.masterResult
                        searchField: masterSearch
                        onActivateRequested: function(item, field) { root.activateResult(item, field) }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Spacing.md
                    spacing: Spacing.md

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Both actions use the same visible-label predicate. Plain text is the default; regex and flags are optional and synchronized with this field's builder.")
                        wrapMode: Text.WordWrap
                        color: Theme.color("onSurfaceVariant")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        RadioButton {
                            text: qsTr("Close tabs containing text")
                            checked: !root.closeInverse
                            onToggled: if (checked) root.closeInverse = false
                        }
                        RadioButton {
                            text: qsTr("Close tabs not containing text")
                            checked: root.closeInverse
                            onToggled: if (checked) root.closeInverse = true
                        }
                    }

                    FilterTextField {
                        id: closeSearch
                        Layout.fillWidth: true
                        placeholder: qsTr("Visible tab label to match")
                        builderTitle: root.closeInverse
                            ? qsTr("Inverse bulk-close Regex Builder")
                            : qsTr("Bulk-close Regex Builder")
                        text: root.closeQuery
                        regexEnabled: root.closeRegex
                        regexFlags: root.closeFlags
                        builderSampleText: WorkspaceManager.tabItems.map(function(tab) {
                            return tab.name
                        }).join("\n")
                        onTextChanged: root.closeQuery = text
                        onRegexEnabledChanged: root.closeRegex = regexEnabled
                        onRegexFlagsChanged: root.closeFlags = regexFlags
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CheckBox {
                            text: qsTr("Include pinned tabs")
                            checked: root.closeIncludePinned
                            onToggled: root.closeIncludePinned = checked
                        }
                        ComboBox {
                            id: closeScope
                            Layout.fillWidth: true
                            textRole: "name"
                            valueRole: "groupId"
                            model: [{ name: qsTr("All groups and ungrouped tabs"), groupId: "" }]
                                .concat(WorkspaceManager.groups)
                            onActivated: root.closeGroupId = currentValue || ""
                            Accessible.name: qsTr("Bulk-close group scope")
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: previewColumn.implicitHeight + Spacing.lg * 2
                        radius: Spacing.radiusCard
                        color: Theme.color("surfaceVariant")
                        border.width: 1
                        border.color: root.closePreview.valid
                            ? Theme.color("outlineVariant") : Theme.color("error")

                        ColumnLayout {
                            id: previewColumn
                            anchors.fill: parent
                            anchors.margins: Spacing.lg
                            spacing: Spacing.xs
                            Label {
                                Layout.fillWidth: true
                                text: root.closePreview.valid
                                    ? qsTr("Review: %1 tab(s) will close; %2 pinned tab(s) remain protected.")
                                        .arg(root.closePreview.count)
                                        .arg(root.closePreview.excludedPinned)
                                    : root.closePreview.error
                                color: root.closePreview.valid
                                    ? Theme.color("onSurface") : Theme.color("error")
                                wrapMode: Text.WordWrap
                            }
                            Label {
                                visible: !!root.closePreview.willCheckpoint
                                text: qsTr("Current edits will be committed to local history before any tab closes.")
                                color: Theme.color("primary")
                                wrapMode: Text.WordWrap
                            }
                            Repeater {
                                model: root.closePreview.items || []
                                delegate: Label {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: "• " + modelData.name + " · " + modelData.location
                                        + (modelData.pinned ? qsTr(" · PINNED") : "")
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Button {
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Review and confirm closing %1 tab(s)…")
                            .arg(root.closePreview.count)
                        highlighted: true
                        enabled: root.closePreview.valid && root.closePreview.count > 0
                        onClicked: closeConfirmation.open()
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Spacing.md
            Layout.rightMargin: Spacing.md
            Layout.bottomMargin: lastActivated.length ? Spacing.sm : 0
            visible: lastActivated.length > 0
            text: lastActivated
            font: Typography.bodySmall
            color: Theme.color("primary")
            wrapMode: Text.WordWrap
            Accessible.name: lastActivated
        }
    }

    Dialog {
        id: closeConfirmation
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(520, parent ? parent.width - Spacing.xl * 2 : 520)
        modal: true
        title: root.closeInverse
            ? qsTr("Close tabs not containing this text?")
            : qsTr("Close tabs containing this text?")
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            WorkspaceManager.closeTabsByText(root.closeQuery, root.closeRegex,
                root.closeFlags, root.closeInverse, root.closeIncludePinned,
                root.closeGroupId)
            root.closeQuery = ""
        }
        contentItem: Label {
            width: 420
            text: qsTr("This will close %1 reviewed tab(s). Pinned tabs are %2. Existing unsaved-work safeguards and the pre-close Git checkpoint remain active.")
                .arg(root.closePreview.count)
                .arg(root.closeIncludePinned ? qsTr("included explicitly") : qsTr("excluded"))
            wrapMode: Text.WordWrap
        }
    }
}
