/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype HistorySheet
    \brief The git History manager: Action log / Settings repo tabs, commit
           search (plain or regex), a day-grouped commit timeline with
           expandable diffs, per-entry Restore/Undo and Copy-sha — backed by
           JournalHistoryModel + JournalController.
*/
Sheet {
    id: root
    sheetWidth: 460
    accessibleName: qsTr("History")

    property string repo: "actions"
    property string expandedCommit: ""

    JournalHistoryModel {
        id: historyModel
        repo: root.repo
        filterText: searchField.text
        filterRegex: histRegex
        filterRegexFlags: searchField.regexFlags
        fromDate: fromDateField.text
        toDate: toDateField.text
    }
    // Owned by the search field's own regex toggle, so the panel and the field
    // can never disagree about which mode is active.
    readonly property bool histRegex: searchField.regexEnabled

    function toggleAction(actionId) {
        var next = historyModel.actionFilter.slice()
        var index = next.indexOf(actionId)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(actionId)
        historyModel.actionFilter = next
    }

    function clearFilters() {
        fromDateField.clear()
        toDateField.clear()
        historyModel.actionFilter = []
    }

    function isoDate(date) {
        return Qt.formatDate(date, "yyyy-MM-dd")
    }

    function setLastDays(days) {
        var to = new Date()
        var from = new Date(to.getFullYear(), to.getMonth(), to.getDate() - days + 1)
        fromDateField.text = isoDate(from)
        toDateField.text = isoDate(to)
    }

    function setThisMonth() {
        var now = new Date()
        fromDateField.text = isoDate(new Date(now.getFullYear(), now.getMonth(), 1))
        toDateField.text = isoDate(now)
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
            Layout.bottomMargin: 10
            spacing: 10

            Text {
                text: qsTr("History")
                font.family: Typography.family
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Theme.color("onSurface")
            }
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: branchRow.implicitWidth + 20
                radius: 12
                color: Theme.color("surfaceVariant")
                Row {
                    id: branchRow
                    anchors.centerIn: parent
                    spacing: 5
                    MDIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "account_tree"; size: 14; color: Theme.color("onSurfaceVariant")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "main"
                        font.family: Typography.monoFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.color("onSurfaceVariant")
                    }
                }
            }
            Item { Layout.fillWidth: true }
            HeaderIconButton {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                iconName: "save_alt"; iconSize: 19; iconColor: Theme.color("onSurfaceVariant")
                tooltip: qsTr("Export repo as JSON")
                onClicked: {
                    var n = JournalController.exportHistoryJson(root.repo)
                    root.shellNotify(qsTr("Copied %1 commits as JSON to the clipboard").arg(n))
                }
            }
            HeaderIconButton {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                iconName: "close"; iconSize: 19; iconColor: Theme.color("onSurfaceVariant")
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }

        // Repo tabs + auto-commit toggle.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 10
            spacing: 6

            Repeater {
                model: [
                    { key: "actions", label: qsTr("Action log"), icon: "bolt" },
                    { key: "settings", label: qsTr("Settings repo"), icon: "settings" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.repo === modelData.key
                    Layout.preferredHeight: 34
                    implicitWidth: tabRow.implicitWidth + 28
                    radius: 17
                    color: active ? Theme.color("primaryContainer") : "transparent"
                    border.width: 1
                    border.color: active ? Theme.color("primaryContainer") : Theme.color("outline")
                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 6
                        MDIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon; size: 16
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Typography.family
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.key === "actions"
                                ? String(JournalController.actionsCount) : String(JournalController.settingsCount)
                            font.family: Typography.monoFamily
                            font.pixelSize: 11
                            opacity: 0.7
                            color: parent.parent.active ? Theme.color("onPrimaryContainer") : Theme.color("onSurfaceVariant")
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.repo = modelData.key; root.expandedCommit = "" }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: qsTr("auto-commit · always on")
                font.family: Typography.family
                font.pixelSize: 12
                color: Theme.color("onSurfaceVariant")
            }
            Rectangle {
                Layout.preferredWidth: 34; Layout.preferredHeight: 20
                radius: 10
                color: JournalController.autoCommit ? Theme.color("primary") : Theme.color("surfaceContainerHigh")
                Behavior on color { ColorAnimation { duration: 200 } }
                Rectangle {
                    width: 14; height: 14; radius: 7
                    y: 3
                    x: JournalController.autoCommit ? 17 : 3
                    color: JournalController.autoCommit ? Theme.color("onPrimary") : Theme.color("onSurfaceVariant")
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Spacing.easeStandard } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.ArrowCursor
                    Accessible.name: qsTr("Settings history is always recorded locally")
                }
            }
        }

        // Search. A FilterTextField so the history panel carries the same
        // anchored regex builder as every other search surface, instead of the
        // hand-rolled ".*" toggle it used to own.
        FilterTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 10
            placeholder: qsTr("Search commits (message, sha)")
            builderTitle: qsTr("Regex Builder")
            builderSampleText: "Fix the tracker list\nAdd search plugins\n蝦餃 1080p"
            Accessible.name: qsTr("Search local history commits")
        }

        // Date and action filters compose with the text/regex search. Dates
        // remain editable so invalid or partial input is reported without
        // throwing away what the user typed.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 4
            spacing: 6

            TextField {
                id: fromDateField
                Layout.fillWidth: true
                placeholderText: qsTr("From date")
                Accessible.name: qsTr("History start date")
                selectByMouse: true
                maximumLength: 32
            }
            ToolButton {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                text: qsTr("Choose history start date")
                display: AbstractButton.IconOnly
                contentItem: MDIcon {
                    name: "calendar_month"
                    size: 18
                    color: Theme.color("primary")
                }
                Accessible.name: qsTr("Choose history start date")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: {
                    calendarPopup.selectingStart = true
                    calendarPopup.open()
                }
            }
            TextField {
                id: toDateField
                Layout.fillWidth: true
                placeholderText: qsTr("To date")
                Accessible.name: qsTr("History end date")
                selectByMouse: true
                maximumLength: 32
            }
            ToolButton {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                text: qsTr("Choose history end date")
                display: AbstractButton.IconOnly
                contentItem: MDIcon {
                    name: "calendar_month"
                    size: 18
                    color: Theme.color("primary")
                }
                Accessible.name: qsTr("Choose history end date")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: {
                    calendarPopup.selectingStart = false
                    calendarPopup.open()
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 4

            Button {
                text: qsTr("All time")
                flat: true
                onClicked: root.clearFilters()
            }
            Button {
                text: qsTr("Last 30 days")
                flat: true
                onClicked: root.setLastDays(30)
            }
            Button {
                text: qsTr("Last year")
                flat: true
                onClicked: root.setLastDays(365)
            }
            Button {
                text: qsTr("This month")
                flat: true
                onClicked: root.setThisMonth()
            }
            Button {
                text: historyModel.actionFilter.length > 0
                    ? qsTr("Actions · %1").arg(historyModel.actionFilter.length)
                    : qsTr("Actions")
                flat: true
                Accessible.name: qsTr("Filter history by action")
                onClicked: actionMenu.open()
            }
            Button {
                text: qsTr("Clear filters")
                flat: true
                visible: fromDateField.text.length > 0 || toDateField.text.length > 0
                    || historyModel.actionFilter.length > 0
                onClicked: root.clearFilters()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            visible: !historyModel.filterValid
            text: historyModel.filterError
            color: Theme.color("error")
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.AlertMessage
        }

        // Commit timeline.
        ListView {
            id: timeline
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 16
            clip: true
            model: historyModel
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            section.property: "dateKey"
            section.delegate: Text {
                text: section.toUpperCase()
                font.family: Typography.family
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: Theme.color("onSurfaceVariant")
                topPadding: 10
                bottomPadding: 6
                leftPadding: 30
            }

            delegate: Item {
                id: commitItem
                required property int index
                required property string commitId
                required property string sha
                required property string message
                required property string timeText
                required property var diffLines
                required property bool undoable
                required property bool canRestore
                required property string origin

                readonly property bool expanded: root.expandedCommit === commitId

                width: timeline.width
                height: commitColumn.implicitHeight

                Row {
                    anchors.fill: parent
                    spacing: 12

                    // Timeline dot + line.
                    Column {
                        width: 18
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 10; height: 10; radius: 5
                            color: (commitItem.index === 0) ? Theme.color("primary") : Theme.color("outline")
                            border.width: 2
                            border.color: Theme.color("surface")
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 2
                            height: commitColumn.implicitHeight - 8
                            color: Theme.color("outlineVariant")
                        }
                    }

                    Column {
                        id: commitColumn
                        width: parent.width - 30
                        bottomPadding: 10

                        // Row header.
                        Rectangle {
                            width: parent.width
                            height: 34
                            radius: 12
                            color: headerMouse.containsMouse ? Theme.color("hover") : "transparent"
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: shaText.implicitWidth + 14
                                    height: 20
                                    radius: 8
                                    color: Theme.color("surfaceVariant")
                                    Text {
                                        id: shaText
                                        anchors.centerIn: parent
                                        text: commitItem.sha
                                        font.family: Typography.monoFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.color("primary")
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - shaText.implicitWidth - 130
                                    text: commitItem.message
                                    elide: Text.ElideRight
                                    font.family: Typography.family
                                    font.pixelSize: 13
                                    color: Theme.color("onSurface")
                                }
                                Item { width: 1; height: 1 }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: commitItem.timeText
                                    font.family: Typography.family
                                    font.pixelSize: 11
                                    color: Theme.color("onSurfaceVariant")
                                }
                                MDIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand_more"
                                    size: 17
                                    color: Theme.color("onSurfaceVariant")
                                    rotation: commitItem.expanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 200 } }
                                }
                            }
                            MouseArea {
                                id: headerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.expandedCommit = commitItem.expanded ? "" : commitItem.commitId
                            }
                        }

                        // Expanded diff + actions.
                        Rectangle {
                            visible: commitItem.expanded
                            width: parent.width - 6
                            x: 6
                            height: diffColumn.implicitHeight + 20
                            radius: 12
                            color: Theme.color("surfaceVariant")

                            Column {
                                id: diffColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                Repeater {
                                    model: commitItem.diffLines
                                    delegate: Column {
                                        required property var modelData
                                        width: parent.width
                                        spacing: 2
                                        Row {
                                            spacing: 8
                                            Text { text: "−"; color: Theme.color("error"); font.family: Typography.monoFamily; font.pixelSize: 12 }
                                            Text {
                                                width: diffColumn.width - 20
                                                text: modelData.from
                                                elide: Text.ElideRight
                                                color: Theme.color("error")
                                                font.family: Typography.monoFamily
                                                font.pixelSize: 12
                                            }
                                        }
                                        Row {
                                            spacing: 8
                                            Text { text: "+"; color: Theme.color("success"); font.family: Typography.monoFamily; font.pixelSize: 12 }
                                            Text {
                                                width: diffColumn.width - 20
                                                text: modelData.to
                                                elide: Text.ElideRight
                                                color: Theme.color("success")
                                                font.family: Typography.monoFamily
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                }

                                Row {
                                    spacing: 8
                                    topPadding: 6

                                    Rectangle {
                                        visible: commitItem.undoable
                                        height: 28
                                        width: undoRow.implicitWidth + 24
                                        radius: 14
                                        color: Theme.color("primaryContainer")
                                        enabled: !JournalController.busy
                                        opacity: JournalController.busy ? 0.6 : 1
                                        Row {
                                            id: undoRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "undo"; size: 15; color: Theme.color("onPrimaryContainer") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Undo")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onPrimaryContainer")
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.repo === "settings")
                                                    JournalController.undoSettingsEntry(commitItem.commitId)
                                                else
                                                    JournalController.undoEntry(commitItem.commitId)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: commitItem.canRestore && root.repo === "actions"
                                        height: 28
                                        width: restoreRow.implicitWidth + 24
                                        radius: 14
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.color("outline")
                                        enabled: !JournalController.busy
                                        opacity: JournalController.busy ? 0.6 : 1
                                        Row {
                                            id: restoreRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "settings_backup_restore"; size: 15; color: Theme.color("onSurfaceVariant") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Restore")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onSurfaceVariant")
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.restoreConfirm(commitItem.commitId, commitItem.index)
                                        }
                                    }

                                    Rectangle {
                                        height: 28
                                        width: copyRow.implicitWidth + 24
                                        radius: 14
                                        color: copyMouse.containsMouse ? Theme.color("hoverStrong") : "transparent"
                                        Row {
                                            id: copyRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            MDIcon { anchors.verticalCenter: parent.verticalCenter; name: "content_copy"; size: 15; color: Theme.color("onSurfaceVariant") }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("Copy sha")
                                                font.family: Typography.family; font.pixelSize: 12; font.weight: Font.DemiBold
                                                color: Theme.color("onSurfaceVariant")
                                            }
                                        }
                                        MouseArea {
                                            id: copyMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                JournalController.copyToClipboard(commitItem.commitId)
                                                root.shellNotify(qsTr("Copied %1").arg(commitItem.sha))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state.
            Column {
                visible: timeline.count === 0
                anchors.centerIn: parent
                spacing: 8
                MDIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "history"; size: 44; color: Theme.color("outline")
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !historyModel.filterValid
                        ? qsTr("History filter is invalid")
                        : ((searchField.text.length > 0 || fromDateField.text.length > 0
                            || toDateField.text.length > 0
                            || historyModel.actionFilter.length > 0)
                            ? qsTr("No commits match") : qsTr("No history yet"))
                    font.family: Typography.family
                    font.pixelSize: 13
                    color: Theme.color("onSurfaceVariant")
                }
            }
        }
    }

    SearchableMenu {
        id: actionMenu
        searchPlaceholder: qsTr("Search history actions")
        searchAccessibleName: qsTr("Search history actions")
        minimumMenuWidth: 300

        Repeater {
            model: historyModel.actionFacets
            delegate: MenuItem {
                required property var modelData
                readonly property string actionId: modelData.id || ""
                text: qsTr("%1 (%2)").arg(modelData.label).arg(modelData.count)
                visible: actionMenu.matches(text)
                height: visible ? implicitHeight : 0
                checkable: true
                checked: historyModel.actionFilter.indexOf(actionId) >= 0
                onTriggered: root.toggleAction(actionId)
            }
        }

        MenuSeparator { visible: historyModel.actionFacets.length > 0 }
        MenuItem {
            text: qsTr("Clear action filters")
            visible: actionMenu.matches(text)
            height: visible ? implicitHeight : 0
            enabled: historyModel.actionFilter.length > 0
            onTriggered: historyModel.actionFilter = []
        }
    }

    Popup {
        id: calendarPopup
        parent: root
        anchors.centerIn: parent
        width: Math.min(390, root.width - Spacing.lg * 2)
        height: 430
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property bool selectingStart: true
        property int shownMonth: new Date().getMonth()
        property int shownYear: new Date().getFullYear()
        Material.elevation: 12

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
            border.width: 1
            border.color: Theme.color("outlineVariant")
        }

        contentItem: ColumnLayout {
            spacing: Spacing.sm
            Label {
                Layout.fillWidth: true
                text: calendarPopup.selectingStart
                    ? qsTr("Choose history start date")
                    : qsTr("Choose history end date")
                font: Typography.titleLarge
            }
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: monthPicker
                    Layout.fillWidth: true
                    model: [qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"),
                        qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"),
                        qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")]
                    currentIndex: calendarPopup.shownMonth
                    onActivated: (index) => calendarPopup.shownMonth = index
                }
                SpinBox {
                    from: 2000
                    to: new Date().getFullYear() + 2
                    value: calendarPopup.shownYear
                    editable: true
                    onValueModified: calendarPopup.shownYear = value
                }
            }
            DayOfWeekRow {
                Layout.fillWidth: true
                locale: monthGrid.locale
            }
            MonthGrid {
                id: monthGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                month: calendarPopup.shownMonth
                year: calendarPopup.shownYear
                onClicked: (date) => {
                    if (calendarPopup.selectingStart)
                        fromDateField.text = root.isoDate(date)
                    else
                        toDateField.text = root.isoDate(date)
                    calendarPopup.close()
                }
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Typed dates accept your locale format or YYYY-MM-DD.")
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
            }
        }
    }

    // Wired by the shell.
    signal closeRequested()
    signal restoreConfirm(string commitId, int laterCount)
    function shellNotify(message) { root.notifyRequested(message) }
    signal notifyRequested(string message)
}
