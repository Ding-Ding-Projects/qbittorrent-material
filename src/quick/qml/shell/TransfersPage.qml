/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype TransfersPage
    \brief The redesigned Transfers experience, per UI style:
           A "Tonal Rail" — status chips + comfortable table;
           B "Split Dock" — classic filter sidebar + dense table + properties dock;
           C "Card Flow"  — status chips + card list + persistent detail panel.

    Selection flows to TransferController.selectedIds; row context menus and
    their dialogs are hosted here (same wiring as the legacy TransferListView).
*/
Item {
    id: root

    required property var shell
    required property var filterProxy

    /*! Display name of the focused torrent (drives the A selection bar). */
    property string currentName: ""
    property int currentRow: -1
    /*! TorrentState int of the focused row (drives the C detail panel icon/bar). */
    property int currentState: 0

    signal deleteRequested()

    // ---- State helpers (design stColorOf / stIconOf) ------------------------
    function stateIcon(state) {
        switch (state) {
        case 0: case 1: case 2: case 3: return "download"
        case 4: return "hourglass_empty"
        case 5: case 6: return "upload"
        case 7: return "hourglass_empty"
        case 8: case 11: case 12: return "fact_check"
        case 9: case 10: return "low_priority"
        case 13: return "pause"
        case 14: return "check_circle"
        case 15: return "drive_file_move"
        case 16: case 17: return "error"
        default: return "insert_drive_file"
        }
    }

    function barColor(state) {
        if (state === 16 || state === 17 || state === 13)
            return Theme.color("outline")
        if (state === 14)
            return Theme.color("done")
        if (state === 5 || state === 6 || state === 7)
            return Theme.color("primary")
        return Theme.color("success")
    }

    function progressLabel(progress) {
        const pct = progress * 100
        return (pct >= 100 ? "100" : pct.toFixed(1)) + "%"
    }

    function speedColor(text, seeding) {
        if (!text || text.indexOf("0 B/s") === 0)
            return Theme.color("onSurfaceVariant")
        return seeding ? Theme.color("primary") : Theme.color("success")
    }

    function localPath(url) {
        return decodeURIComponent(("" + url).replace(/^file:\/\/\/?/, ""))
    }

    // ---- Selection -----------------------------------------------------------
    property var selectedRows: []
    // Proxy rows are transient: sorting and filtering can move a torrent to a
    // different row without changing the row count. Keep the actual selection
    // identity separately so model layout changes can remap the highlights.
    property var selectedTorrentIds: []
    property string currentTorrentId: ""

    function rowClicked(row, modifiers) {
        if (modifiers & Qt.ControlModifier) {
            var rows = root.selectedRows.slice()
            const at = rows.indexOf(row)
            if (at >= 0)
                rows.splice(at, 1)
            else
                rows.push(row)
            root.selectedRows = rows
        } else if ((modifiers & Qt.ShiftModifier) && (root.currentRow >= 0)) {
            var range = []
            const lo = Math.min(root.currentRow, row)
            const hi = Math.max(root.currentRow, row)
            for (var i = lo; i <= hi; ++i)
                range.push(i)
            root.selectedRows = range
        } else {
            root.selectedRows = [row]
        }
        root.currentRow = row
        root.syncSelection()
    }

    function syncSelection() {
        var ids = []
        for (var i = 0; i < root.selectedRows.length; ++i) {
            const id = root.filterProxy.idAt(root.selectedRows[i])
            if (id && id.length > 0 && ids.indexOf(id) < 0)
                ids.push(id)
        }
        root.selectedTorrentIds = ids
        root.currentTorrentId = root.currentRow >= 0
            ? root.filterProxy.idAt(root.currentRow) : ""
        root.publishSelection()
    }

    function publishSelection() {
        TransferController.selectedIds = root.selectedTorrentIds
        if (root.currentRow >= 0 && root.currentTorrentId.length > 0) {
            const idx = root.filterProxy.index(root.currentRow, 0)
            root.currentName = String(root.filterProxy.data(idx, TransferListModel.NameRole) || "")
            root.currentState = Number(root.filterProxy.data(idx, TransferListModel.StateRole) || 0)
            PropertiesController.currentTorrentId = root.currentTorrentId
        } else {
            root.currentName = ""
            root.currentState = 0
            PropertiesController.currentTorrentId = ""
        }
    }

    function remapSelection() {
        if (!root.filterProxy || typeof root.filterProxy.visibleIds !== "function") {
            root.clearSelection()
            return
        }

        const visibleIds = root.filterProxy.visibleIds()
        var rows = []
        var ids = []
        for (var i = 0; i < root.selectedTorrentIds.length; ++i) {
            const id = root.selectedTorrentIds[i]
            const row = visibleIds.indexOf(id)
            if (row >= 0) {
                rows.push(row)
                ids.push(id)
            }
        }

        var focusedId = root.currentTorrentId
        var focusedRow = focusedId.length > 0 ? visibleIds.indexOf(focusedId) : -1
        if (focusedRow < 0 && rows.length > 0) {
            focusedRow = rows[0]
            focusedId = ids[0]
        } else if (focusedRow < 0) {
            focusedId = ""
        }

        root.selectedRows = rows
        root.selectedTorrentIds = ids
        root.currentRow = focusedRow
        root.currentTorrentId = focusedId
        root.publishSelection()
    }

    // A: floating selection bar (Tonal Rail only, when a torrent is focused).
    property alias selectionBarVisible: selectionBar.visible
    Rectangle {
        id: selectionBar
        visible: Theme.isTonalRail && (root.currentRow >= 0) && (TransferController.selectionCount > 0)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        height: 52
        width: selBarRow.implicitWidth + 26
        radius: 26
        color: Theme.color("surfaceContainerHigh")
        border.width: 1
        border.color: Theme.color("outlineVariant")

        Row {
            id: selBarRow
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 280)
                rightPadding: 8
                text: (TransferController.selectionCount > 1)
                    ? qsTr("%1 selected").arg(TransferController.selectionCount)
                    : root.currentName
                elide: Text.ElideRight
                font.family: Typography.family
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Theme.color("onSurface")
            }
            Repeater {
                model: [
                    { icon: "play_arrow", tip: qsTr("Start"), act: function() { TransferController.start() } },
                    { icon: "pause", tip: qsTr("Stop"), act: function() { TransferController.stop() } },
                    { icon: "fact_check", tip: qsTr("Force recheck"), act: function() { TransferController.forceRecheck() } },
                    { icon: "folder_open", tip: qsTr("Open folder"), act: function() { TransferController.openDestination() } },
                    { icon: "delete", danger: true, tip: qsTr("Remove"), act: function() { root.deleteRequested() } }
                ]
                delegate: AbstractButton {
                    id: selectionActionButton
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    padding: 0
                    hoverEnabled: true
                    activeFocusOnTab: true
                    Accessible.name: modelData.tip
                    Accessible.description: qsTr("Action for the selected torrent")

                    background: Rectangle {
                        radius: 19
                        color: selectionActionButton.hovered
                            ? (selectionActionButton.modelData.danger ? Theme.color("errorContainer") : Theme.color("hoverStrong"))
                            : "transparent"
                        border.width: selectionActionButton.visualFocus ? 2 : 0
                        border.color: selectionActionButton.modelData.danger
                            ? Theme.color("error") : Theme.color("primary")
                    }
                    contentItem: MDIcon {
                        anchors.centerIn: parent
                        name: selectionActionButton.modelData.icon
                        size: 20
                        color: selectionActionButton.modelData.danger
                            ? Theme.color("error") : Theme.color("onSurface")
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    ToolTip.visible: selectionActionButton.hovered
                    ToolTip.text: modelData.tip
                    onClicked: modelData.act()
                }
            }
        }
    }

    function clearSelection() {
        root.selectedRows = []
        root.currentRow = -1
        root.syncSelection()
    }

    Connections {
        target: root.filterProxy
        function onCountChanged() {
            root.remapSelection()
        }
        function onFilterChanged() { root.remapSelection() }
        function onLayoutChanged() { root.remapSelection() }
    }

    // ---- Table geometry per style (the design's tbl config) -----------------
    readonly property bool dense: Theme.isSplitDock
    readonly property var tbl: dense
        ? ({ radius: 12, headH: 34, rowH: 34, q: true, sub: false, status: true, ratio: true,
             nameMin: 260, nameFs: 13, nameWt: Font.Normal, iconBox: 20, iconRad: 6, iconSz: 16,
             progW: 170, barH: 4 })
        : ({ radius: 16, headH: 40, rowH: 56, q: false, sub: true, status: false, ratio: false,
             nameMin: 300, nameFs: 14, nameWt: Font.Medium, iconBox: 34, iconRad: 10, iconSz: 18,
             progW: 210, barH: 8 })

    // Fixed column parts (name flexes): [role, title, width, alignRight, sortColumn]
    readonly property var fixedColumns: {
        var cols = []
        cols.push({ key: "size", title: qsTr("Size"), width: 90, right: true, sort: 2 })
        cols.push({ key: "progress", title: qsTr("Progress"), width: tbl.progW, right: false, sort: 4 })
        if (tbl.status)
            cols.push({ key: "status", title: qsTr("Status"), width: 110, right: false, sort: 5 })
        cols.push({ key: "down", title: qsTr("Down"), width: 100, right: true, sort: 8 })
        cols.push({ key: "up", title: qsTr("Up"), width: 100, right: true, sort: 9 })
        cols.push({ key: "eta", title: qsTr("ETA"), width: 92, right: true, sort: 10 })
        if (tbl.ratio)
            cols.push({ key: "ratio", title: qsTr("Ratio"), width: 64, right: true, sort: 11 })
        cols.push({ key: "category", title: qsTr("Category"), width: 116, right: false, sort: 13 })
        return cols
    }

    property int sortColumn: 1
    property bool sortAscending: true

    function headerClicked(sortCol) {
        if (root.sortColumn === sortCol)
            root.sortAscending = !root.sortAscending
        else {
            root.sortColumn = sortCol
            root.sortAscending = true
        }
        root.filterProxy.sortByColumn(root.sortColumn,
            root.sortAscending ? Qt.AscendingOrder : Qt.DescendingOrder)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- B: classic filter sidebar --------------------------------------
        Rectangle {
            visible: Theme.isSplitDock
            Layout.preferredWidth: 232
            Layout.fillHeight: true
            color: Theme.color("surface")

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.color("outlineVariant")
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.rightMargin: 1
                spacing: 0

                Row {
                    Layout.margins: 8
                    spacing: 2

                    AbstractButton {
                        id: splitDockAddButton
                        width: 36
                        height: 36
                        padding: 0
                        hoverEnabled: true
                        activeFocusOnTab: true
                        Accessible.name: qsTr("Add torrent")
                        Accessible.description: qsTr("Add a torrent file")
                        background: Rectangle {
                            radius: 8
                            color: Theme.color("primaryContainer")
                            border.width: splitDockAddButton.visualFocus ? 2 : 0
                            border.color: Theme.color("primary")
                        }
                        contentItem: MDIcon {
                            anchors.centerIn: parent
                            name: "note_add"
                            size: 20
                            color: Theme.color("onPrimaryContainer")
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        ToolTip.visible: splitDockAddButton.hovered
                        ToolTip.text: qsTr("Add torrent")
                        onClicked: root.shell.addTorrentFile()
                    }
                    Repeater {
                        model: [
                            { icon: "play_arrow", tip: qsTr("Start"), act: function() { TransferController.start() } },
                            { icon: "pause", tip: qsTr("Stop"), act: function() { TransferController.stop() } },
                            { icon: "delete", tip: qsTr("Remove"), act: function() { root.deleteRequested() } }
                        ]
                        delegate: AbstractButton {
                            id: splitDockActionButton
                            required property var modelData
                            width: 36
                            height: 36
                            padding: 0
                            hoverEnabled: true
                            activeFocusOnTab: true
                            enabled: TransferController.selectionCount > 0
                            Accessible.name: modelData.tip
                            Accessible.description: qsTr("Action for the selected torrent")
                            background: Rectangle {
                                radius: 8
                                color: splitDockActionButton.hovered ? Theme.color("hoverStrong") : "transparent"
                                border.width: splitDockActionButton.visualFocus ? 2 : 0
                                border.color: splitDockActionButton.modelData.icon === "delete"
                                    ? Theme.color("error") : Theme.color("primary")
                            }
                            contentItem: MDIcon {
                                anchors.centerIn: parent
                                name: splitDockActionButton.modelData.icon
                                size: 20
                                color: splitDockActionButton.modelData.icon === "delete"
                                    ? Theme.color("error") : Theme.color("onSurface")
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            ToolTip.visible: splitDockActionButton.hovered
                            ToolTip.text: modelData.tip
                            onClicked: modelData.act()
                        }
                    }
                }

                FilterSidebar {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    proxy: root.filterProxy
                }
            }
        }

        // ---- Main column ------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: Theme.isCardFlow ? 0 : 20
            Layout.bottomMargin: 16
            spacing: 12

            // A/C: status chips.
            FilterChips {
                visible: !Theme.isSplitDock
                Layout.fillWidth: true
                Layout.leftMargin: 4
                filterProxy: root.filterProxy
            }

            // A/B: the table.
            Rectangle {
                visible: !Theme.isCardFlow
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.tbl.radius
                color: Theme.color("surface")
                border.width: 1
                border.color: Theme.color("outlineVariant")
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 0

                    // Header row.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.tbl.headH
                        color: Theme.color("surfaceVariant")

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Queue # (B only).
                            Item {
                                visible: root.tbl.q
                                Layout.preferredWidth: 40
                                Layout.fillHeight: true
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "#"
                                    font.family: Typography.family
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: Theme.color("onSurfaceVariant")
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.headerClicked(0) }
                            }

                            // Name (flexes).
                            Item {
                                Layout.fillWidth: true
                                Layout.minimumWidth: root.tbl.nameMin
                                Layout.fillHeight: true
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text {
                                        text: qsTr("Name")
                                        font.family: Typography.family
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.4
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                    MDIcon {
                                        visible: root.sortColumn === 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: root.sortAscending ? "arrow_upward" : "arrow_downward"
                                        size: 14
                                        color: Theme.color("primary")
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.headerClicked(1)
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            Repeater {
                                model: root.fixedColumns
                                delegate: Item {
                                    required property var modelData
                                    Layout.preferredWidth: modelData.width
                                    Layout.fillHeight: true
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: modelData.right
                                            ? parent.width - implicitWidth - 12 : 12
                                        spacing: 4
                                        Text {
                                            text: modelData.title
                                            font.family: Typography.family
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 0.4
                                            color: Theme.color("onSurfaceVariant")
                                        }
                                        MDIcon {
                                            visible: root.sortColumn === modelData.sort
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: root.sortAscending ? "arrow_upward" : "arrow_downward"
                                            size: 14
                                            color: Theme.color("primary")
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.headerClicked(modelData.sort)
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 1
                            color: Theme.color("outlineVariant")
                        }
                    }

                    // Rows.
                    ListView {
                        id: tableView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.filterProxy
                        reuseItems: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            id: rowDelegate
                            required property int index
                            required property var model
                            readonly property bool selected: root.selectedRows.indexOf(index) >= 0
                            readonly property color stColor: Theme.stateColor(model.state)

                            width: tableView.width
                            height: root.tbl.rowH
                            color: selected
                                ? Qt.alpha(Theme.color("primary"), Theme.isDark ? 0.16 : 0.10)
                                : (rowMouse.containsMouse ? Theme.color("hover") : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                Item {
                                    visible: root.tbl.q
                                    Layout.preferredWidth: 40
                                    Layout.fillHeight: true
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rowDelegate.model.queuePosition > 0
                                            ? String(rowDelegate.model.queuePosition) : "–"
                                        font.family: Typography.monoFamily
                                        font.pixelSize: 12
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                }

                                // Name cell with state icon box (+ status subtitle in A).
                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.tbl.nameMin
                                    Layout.fillHeight: true

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: root.tbl.iconBox
                                            height: root.tbl.iconBox
                                            radius: root.tbl.iconRad
                                            color: Qt.alpha(rowDelegate.stColor, Theme.isDark ? 0.16 : 0.12)
                                            MDIcon {
                                                anchors.centerIn: parent
                                                name: root.stateIcon(rowDelegate.model.state)
                                                size: root.tbl.iconSz
                                                color: rowDelegate.stColor
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - root.tbl.iconBox - 10
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: rowDelegate.model.name || ""
                                                elide: Text.ElideRight
                                                font.family: Typography.family
                                                font.pixelSize: root.tbl.nameFs
                                                font.weight: root.tbl.nameWt
                                                color: Theme.color("onSurface")
                                            }
                                            Text {
                                                visible: root.tbl.sub
                                                width: parent.width
                                                text: rowDelegate.model.status || ""
                                                elide: Text.ElideRight
                                                font.family: Typography.family
                                                font.pixelSize: 12
                                                color: rowDelegate.stColor
                                            }
                                        }
                                    }
                                }

                                // Size.
                                Text {
                                    Layout.preferredWidth: 90
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 12
                                    text: rowDelegate.model.size || ""
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: Theme.color("onSurfaceVariant")
                                    elide: Text.ElideRight
                                }

                                // Progress bar + label.
                                Item {
                                    Layout.preferredWidth: root.tbl.progW
                                    Layout.fillHeight: true
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 52
                                            height: root.tbl.barH
                                            radius: height / 2
                                            color: Theme.color("surfaceContainerHigh")
                                            Rectangle {
                                                width: parent.width * Math.min(1, rowDelegate.model.progress || 0)
                                                height: parent.height
                                                radius: parent.radius
                                                color: root.barColor(rowDelegate.model.state)
                                                Behavior on width { NumberAnimation { duration: 400 } }
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 42
                                            horizontalAlignment: Text.AlignRight
                                            text: root.progressLabel(rowDelegate.model.progress || 0)
                                            font.family: Typography.monoFamily
                                            font.pixelSize: 12
                                            color: Theme.color("onSurface")
                                        }
                                    }
                                }

                                // Status (B).
                                Text {
                                    visible: root.tbl.status
                                    Layout.preferredWidth: 110
                                    leftPadding: 12
                                    text: rowDelegate.model.status || ""
                                    font.family: Typography.family
                                    font.pixelSize: 13
                                    color: rowDelegate.stColor
                                    elide: Text.ElideRight
                                }

                                // Down / Up / ETA (+ Ratio for B).
                                Text {
                                    Layout.preferredWidth: 100
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 12
                                    text: rowDelegate.model.downSpeed || ""
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: root.speedColor(rowDelegate.model.downSpeed, false)
                                }
                                Text {
                                    Layout.preferredWidth: 100
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 12
                                    text: rowDelegate.model.upSpeed || ""
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: root.speedColor(rowDelegate.model.upSpeed, true)
                                }
                                Text {
                                    Layout.preferredWidth: 92
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 12
                                    text: rowDelegate.model.eta || ""
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: Theme.color("onSurfaceVariant")
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: root.tbl.ratio
                                    Layout.preferredWidth: 64
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 12
                                    text: rowDelegate.model.ratio || ""
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: Theme.color("onSurfaceVariant")
                                }

                                // Category chip.
                                Item {
                                    Layout.preferredWidth: 116
                                    Layout.fillHeight: true
                                    Rectangle {
                                        visible: (rowDelegate.model.category || "").length > 0
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(92, catLabel.implicitWidth + 20)
                                        height: 22
                                        radius: 11
                                        color: Theme.color("surfaceVariant")
                                        Text {
                                            id: catLabel
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, 80)
                                            text: rowDelegate.model.category || ""
                                            elide: Text.ElideRight
                                            font.family: Typography.family
                                            font.pixelSize: 12
                                            color: Theme.color("onSurfaceVariant")
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1
                                color: Theme.color("outlineVariant")
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (event) => {
                                    if (event.button === Qt.RightButton) {
                                        if (!rowDelegate.selected)
                                            root.rowClicked(rowDelegate.index, 0)
                                        rowMenu.popup()
                                    } else {
                                        root.rowClicked(rowDelegate.index, event.modifiers)
                                    }
                                }
                                onDoubleClicked: TransferController.start()
                            }
                        }

                        // Empty state.
                        Column {
                            visible: tableView.count === 0
                            anchors.centerIn: parent
                            spacing: 8
                            MDIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: "search_off"; size: 40; color: Theme.color("outline")
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("No torrents match the current filter")
                                font.family: Typography.family
                                font.pixelSize: 13
                                color: Theme.color("onSurfaceVariant")
                            }
                        }
                    }
                }
            }

            // C: card flow.
            ListView {
                visible: Theme.isCardFlow
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 4
                clip: true
                spacing: 10
                model: Theme.isCardFlow ? root.filterProxy : null
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }

                delegate: Rectangle {
                    id: card
                    required property int index
                    required property var model
                    readonly property bool selected: root.selectedRows.indexOf(index) >= 0
                    readonly property color stColor: Theme.stateColor(model.state)

                    width: ListView.view.width - 8
                    height: cardColumn.implicitHeight + 28
                    radius: 20
                    color: Theme.color("surface")
                    border.width: selected ? 2 : 1
                    border.color: selected ? Theme.color("primary") : Theme.color("outlineVariant")

                    ColumnLayout {
                        id: cardColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                radius: 14
                                color: Qt.alpha(card.stColor, Theme.isDark ? 0.16 : 0.12)
                                MDIcon {
                                    anchors.centerIn: parent
                                    name: root.stateIcon(card.model.state)
                                    size: 22
                                    color: card.stColor
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text: card.model.name || ""
                                    elide: Text.ElideRight
                                    font.family: Typography.family
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    color: Theme.color("onSurface")
                                }
                                Row {
                                    spacing: 6
                                    Rectangle {
                                        height: 20
                                        width: stChip.implicitWidth + 18
                                        radius: 10
                                        color: Qt.alpha(card.stColor, Theme.isDark ? 0.18 : 0.12)
                                        Text {
                                            id: stChip
                                            anchors.centerIn: parent
                                            text: card.model.status || ""
                                            font.family: Typography.family
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: card.stColor
                                        }
                                    }
                                    Rectangle {
                                        visible: (card.model.category || "").length > 0
                                        height: 20
                                        width: catChip.implicitWidth + 18
                                        radius: 10
                                        color: Theme.color("surfaceVariant")
                                        Text {
                                            id: catChip
                                            anchors.centerIn: parent
                                            text: card.model.category || ""
                                            font.family: Typography.family
                                            font.pixelSize: 12
                                            color: Theme.color("onSurfaceVariant")
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: card.model.size || ""
                                        font.family: Typography.monoFamily
                                        font.pixelSize: 12
                                        color: Theme.color("onSurfaceVariant")
                                    }
                                }
                            }

                            Column {
                                spacing: 3
                                Text {
                                    anchors.right: parent.right
                                    text: "↓ " + (card.model.downSpeed || "")
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: root.speedColor(card.model.downSpeed, false)
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: "↑ " + (card.model.upSpeed || "")
                                    font.family: Typography.monoFamily
                                    font.pixelSize: 13
                                    color: root.speedColor(card.model.upSpeed, true)
                                }
                            }

                            Text {
                                Layout.preferredWidth: 72
                                horizontalAlignment: Text.AlignRight
                                text: root.progressLabel(card.model.progress || 0)
                                font.family: Typography.monoFamily
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                color: Theme.color("onSurface")
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            radius: 3
                            color: Theme.color("surfaceContainerHigh")
                            Rectangle {
                                width: parent.width * Math.min(1, card.model.progress || 0)
                                height: parent.height
                                radius: 3
                                color: root.barColor(card.model.state)
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (event) => {
                            if (event.button === Qt.RightButton) {
                                if (!card.selected)
                                    root.rowClicked(card.index, 0)
                                rowMenu.popup()
                            } else {
                                root.rowClicked(card.index, event.modifiers)
                            }
                        }
                    }
                }

                Column {
                    visible: parent.count === 0
                    anchors.centerIn: parent
                    spacing: 8
                    MDIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "search_off"; size: 40; color: Theme.color("outline")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("No torrents match the current filter")
                        font.family: Typography.family
                        font.pixelSize: 13
                        color: Theme.color("onSurfaceVariant")
                    }
                }
            }

            // B: properties dock.
            PropertiesDockB {
                visible: Theme.isSplitDock
                Layout.fillWidth: true
                Layout.preferredHeight: 210
            }
        }

        // C: persistent detail panel.
        DetailPanelC {
            visible: Theme.isCardFlow
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            page: root
            onDeleteRequested: root.deleteRequested()
        }
    }

    // ---- Context menu + dialogs (same wiring as the legacy view) ------------
    TransferRowContextMenu {
        id: rowMenu
        startAction: root.shell.actionStart
        stopAction: root.shell.actionStop
        removeAction: root.shell.actionDelete
        onRenameRequested: renameDialog.open()
        onSetLocationRequested: setLocationDialog.open()
        onManageContentRequested: {
            if (TransferController.selectionCount !== 1)
                return
            PropertiesController.currentTab = PropertiesController.Content
            contentDialog.open()
        }
        onEditTrackersRequested: {
            if (TransferController.selectionCount <= 0)
                return
            trackersDialog.trackersText = TransferController.trackersText()
            trackersDialog.open()
        }
        onTorrentOptionsRequested: {
            torrentOptionsDialog.torrentIds = TransferController.selectedIds
            torrentOptionsDialog.initialValues = ({})
            torrentOptionsDialog.open()
        }
        onPreviewRequested: TransferController.preview()
        onExportRequested: {
            if (TransferController.selectionCount > 0)
                exportDialog.open()
        }
        onDeleteRequested: root.deleteRequested()
        onNewCategoryRequested: newCategoryDialog.open()
        onAddTagRequested: addTagDialog.open()
        onRemoveAllTagsRequested: TransferController.removeAllTags()
    }

    TextInputDialog {
        id: renameDialog
        parent: Overlay.overlay
        title: qsTr("Rename")
        label: qsTr("New name")
        text: root.currentName
        onAccepted: (t) => TransferController.rename(t)
    }
    TextInputDialog {
        id: setLocationDialog
        parent: Overlay.overlay
        title: qsTr("Set location")
        label: qsTr("New save path")
        text: ""
        onAccepted: (t) => TransferController.setLocation(t)
    }
    TextInputDialog {
        id: newCategoryDialog
        parent: Overlay.overlay
        title: qsTr("New Category")
        label: qsTr("Category name")
        text: ""
        onAccepted: (name) => TransferController.setCategory(name)
    }
    TextInputDialog {
        id: addTagDialog
        parent: Overlay.overlay
        title: qsTr("Add Tags")
        label: qsTr("Comma-separated tags:")
        text: ""
        onAccepted: (raw) => {
            var tags = ("" + raw).split(",").map(s => s.trim()).filter(s => s.length > 0)
            if (tags.length > 0)
                TransferController.addTags(tags)
        }
    }
    TrackerEntriesDialog {
        id: trackersDialog
        parent: Overlay.overlay
        onTrackersAccepted: (text) => TransferController.setTrackers(text)
    }
    Dialog {
        id: contentDialog
        parent: Overlay.overlay
        modal: true
        anchors.centerIn: parent
        width: Math.min(1040, (parent ? parent.width : 1040) * 0.95)
        height: Math.min(700, (parent ? parent.height : 700) * 0.9)
        padding: 0
        Material.elevation: Spacing.elevationDialog
        Material.roundedScale: Material.MediumScale

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
        }
        header: Label {
            text: qsTr("Manage content")
            font: Typography.headlineSmall
            color: Theme.color("onSurface")
            padding: Spacing.lg
        }
        contentItem: ContentTab {
            width: contentDialog.availableWidth
            height: contentDialog.availableHeight
        }
        footer: DialogButtonBox {
            padding: Spacing.lg
            Button {
                text: qsTr("Close")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: contentDialog.close()
            }
        }
    }
    Platform.FolderDialog {
        id: exportDialog
        title: qsTr("Choose export directory")
        onAccepted: {
            const directory = root.localPath(folder)
            if (TransferController.exportTorrent(directory))
                actionSnackbar.show(qsTr("Torrent file(s) exported."))
            else
                actionSnackbar.show(qsTr("Could not export the selected torrent file(s)."))
        }
    }
    Snackbar {
        id: actionSnackbar
        parent: Overlay.overlay
    }
    TorrentOptionsDialog {
        id: torrentOptionsDialog
        parent: Overlay.overlay
    }
}
