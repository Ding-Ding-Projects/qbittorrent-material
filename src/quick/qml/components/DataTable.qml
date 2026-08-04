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
import QtCore
import qBittorrent

/*!
    \qmltype DataTable
    \brief The application's core data table: a sticky, sortable, resizable,
           reorderable header over a virtualized, row-per-record body.

    Because the bridge list models expose \e one role per column (a single model
    column with many named roles, per CONTRACTS §7.1), DataTable renders each
    row as a strip of cells, one per visible column descriptor, reading the
    row's role by name. Columns can be resized (drag the right edge), reordered
    (drag the header), hidden/shown and sorted; the header state is persisted
    under \l persistKey.

    Cell delegate contract — a component returned by \l delegateFor (or the
    built-in default) is loaded into a cell \c Loader and may read these
    properties from its immediate \c parent:
    \list
      \li \c parent.value    — the row's value for this column's role
      \li \c parent.cellRole — the role name
      \li \c parent.cellRow  — the row index
      \li \c parent.cellColumn — the visual column index
      \li \c parent.cellAlign  — Qt alignment flag for the column
    \endlist

    \qml
    DataTable {
        model: transferProxy
        persistKey: "TransferList"
        columns: [
            { role: "name",     title: qsTr("Name"),  width: 240, align: Qt.AlignLeft,  visible: true, resizable: true },
            { role: "progress", title: qsTr("Progress"), width: 140, align: Qt.AlignHCenter, visible: true, resizable: true }
        ]
        delegateFor: (col) => col.role === "progress" ? progressCellComp : null
    }
    \endqml
*/
Item {
    id: root

    // ---- Public API --------------------------------------------------------

    /*! The data model — usually a sort/filter proxy over a bridge list model. */
    property var model: null

    /*!
        Column descriptors: array of objects
        \c {{ role, title, width, align, visible, resizable }}. \c title is
        already translated by the caller; \c role matches the model role name.
    */
    property var columns: []

    /*! Optional \c function(colDescriptor) -> Component returning a cell delegate. */
    property var delegateFor: null

    /*! Header-state persistence id (order / width / visibility / sort). */
    property string persistKey: ""

    /*! Optional QItemSelectionModel to mirror selection into (best-effort). */
    property var selectionModel: null

    /*! The focused row index (-1 = none). */
    property int currentRow: -1

    /*! The set of currently-selected row indices. */
    property var selectedRows: []

    /*! Draw alternating row backgrounds. */
    property bool alternatingRows: false

    /*! Role the table is currently sorted by ("" = unsorted). */
    property string sortRole: ""

    /*! Current sort order (Qt.AscendingOrder / Qt.DescendingOrder). */
    property int sortOrder: Qt.AscendingOrder

    /*! Visual metrics. */
    property int headerHeight: Spacing.controlHeight
    property int rowHeight: Spacing.rowHeight
    property int minColumnWidth: 40

    /*! Emitted on double-click / Enter over a row. */
    signal activated(int row)

    /*! Emitted on right-click over a row; \c pos is in table coordinates. */
    signal contextRequested(int row, point pos)

    /*! Emitted whenever the selection changes. */
    signal selectionChanged()

    // ---- Internal state ----------------------------------------------------

    // Bumped whenever a column geometry/visibility mutation happens, so
    // width-derived bindings (like _totalWidth) re-evaluate.
    property int _rev: 0
    property int _dragCol: -1
    property real _dragStartX: 0

    property real _totalWidth: {
        _rev // dependency
        var w = 0
        for (var i = 0; i < colModel.count; ++i) {
            var c = colModel.get(i)
            if (c.visible)
                w += c.width
        }
        return Math.max(w, width)
    }

    function _bumpRev() { _rev = _rev + 1 }

    // Column state model driving both the header and every row.
    ListModel { id: colModel }

    // Persisted header state (only meaningful when persistKey is set).
    Settings {
        id: persist
        category: "DataTable/" + (root.persistKey.length ? root.persistKey : "_unkeyed")
        property string columnState: ""
    }

    // ---- Column building / persistence ------------------------------------

    Component.onCompleted: _rebuildColumns()
    onColumnsChanged: _rebuildColumns()

    function _rebuildColumns() {
        colModel.clear()
        if (!columns || columns.length === 0)
            return

        var saved = _readPersisted()
        // Establish order: saved order first (for known roles), then any new roles.
        var ordered = columns.slice()
        if (saved && saved.order && saved.order.length) {
            ordered.sort(function(a, b) {
                var ia = saved.order.indexOf(a.role)
                var ib = saved.order.indexOf(b.role)
                if (ia < 0) ia = 1000
                if (ib < 0) ib = 1000
                return ia - ib
            })
        }

        for (var i = 0; i < ordered.length; ++i) {
            var c = ordered[i]
            var width = c.width !== undefined ? c.width : 120
            var visible = c.visible !== undefined ? c.visible : true
            if (saved) {
                if (saved.widths && saved.widths[c.role] !== undefined)
                    width = saved.widths[c.role]
                if (saved.visible && saved.visible[c.role] !== undefined)
                    visible = saved.visible[c.role]
            }
            colModel.append({
                "role": c.role,
                "title": c.title !== undefined ? c.title : c.role,
                "width": width,
                "align": c.align !== undefined ? c.align : Qt.AlignLeft,
                "visible": visible,
                "resizable": c.resizable !== undefined ? c.resizable : true
            })
        }

        if (saved && saved.sortRole) {
            sortRole = saved.sortRole
            sortOrder = saved.sortOrder !== undefined ? saved.sortOrder : Qt.AscendingOrder
            _applySort()
        }
        _bumpRev()
        Log.debug("ui", "DataTable[" + persistKey + "] built " + colModel.count + " columns")
    }

    function _readPersisted() {
        if (!persistKey.length || persist.columnState.length === 0)
            return null
        try {
            return JSON.parse(persist.columnState)
        } catch (e) {
            Log.warning("ui", "DataTable[" + persistKey + "] failed to parse persisted state")
            return null
        }
    }

    function _persist() {
        if (!persistKey.length)
            return
        var order = []
        var widths = ({})
        var visible = ({})
        for (var i = 0; i < colModel.count; ++i) {
            var c = colModel.get(i)
            order.push(c.role)
            widths[c.role] = c.width
            visible[c.role] = c.visible
        }
        persist.columnState = JSON.stringify({
            "order": order, "widths": widths, "visible": visible,
            "sortRole": sortRole, "sortOrder": sortOrder
        })
    }

    // ---- Sorting -----------------------------------------------------------

    function _toggleSort(role) {
        if (sortRole === role)
            sortOrder = (sortOrder === Qt.AscendingOrder) ? Qt.DescendingOrder : Qt.AscendingOrder
        else {
            sortRole = role
            sortOrder = Qt.AscendingOrder
        }
        Log.debug("ui", "DataTable[" + persistKey + "] sort by '" + role + "' " +
                  (sortOrder === Qt.AscendingOrder ? "asc" : "desc"))
        _applySort()
        _persist()
    }

    // Prefer a proxy convenience method; otherwise the proxy is expected to
    // bind to root.sortRole / root.sortOrder.
    function _applySort() {
        if (model && typeof model.sortByRole === "function")
            model.sortByRole(sortRole, sortOrder)
    }

    // ---- Column geometry helpers ------------------------------------------

    function _columnIndexAtX(x) {
        var acc = 0
        for (var i = 0; i < colModel.count; ++i) {
            var c = colModel.get(i)
            if (!c.visible)
                continue
            acc += c.width
            if (x < acc)
                return i
        }
        return colModel.count - 1
    }

    function resizeColumns() {
        // Reset every visible column to its descriptor default width.
        for (var i = 0; i < colModel.count; ++i) {
            var role = colModel.get(i).role
            for (var j = 0; j < columns.length; ++j) {
                if (columns[j].role === role) {
                    colModel.setProperty(i, "width", columns[j].width !== undefined ? columns[j].width : 120)
                    break
                }
            }
        }
        _bumpRev()
        _persist()
        Log.debug("ui", "DataTable[" + persistKey + "] columns reset to default widths")
    }

    function _columnsSnapshot() {
        var arr = []
        for (var i = 0; i < colModel.count; ++i) {
            var c = colModel.get(i)
            arr.push({ "role": c.role, "title": c.title, "visible": c.visible })
        }
        return arr
    }

    function _setColumnVisible(role, vis) {
        for (var i = 0; i < colModel.count; ++i) {
            if (colModel.get(i).role === role) {
                colModel.setProperty(i, "visible", vis)
                break
            }
        }
        _bumpRev()
        _persist()
    }

    // ---- Selection ---------------------------------------------------------

    function _selectRow(row, modifiers) {
        var sel = selectedRows.slice()
        if (modifiers & Qt.ControlModifier) {
            var idx = sel.indexOf(row)
            if (idx >= 0) sel.splice(idx, 1)
            else sel.push(row)
        } else if ((modifiers & Qt.ShiftModifier) && currentRow >= 0) {
            sel = []
            var lo = Math.min(currentRow, row)
            var hi = Math.max(currentRow, row)
            for (var r = lo; r <= hi; ++r)
                sel.push(r)
        } else {
            sel = [row]
            currentRow = row
        }
        if (!(modifiers & Qt.ShiftModifier))
            currentRow = row
        selectedRows = sel
        Log.trace("ui", "DataTable[" + persistKey + "] selection -> " + JSON.stringify(sel))
        selectionChanged()
    }

    function isRowSelected(row) {
        return selectedRows.indexOf(row) >= 0
    }

    /*! Select, scroll to, and focus one row for deep-link navigation. */
    function revealRow(row) {
        if (row < 0 || !model || row >= bodyView.count)
            return false
        currentRow = row
        selectedRows = [row]
        bodyView.positionViewAtIndex(row, ListView.Contain)
        bodyView.forceActiveFocus(Qt.ShortcutFocusReason)
        selectionChanged()
        return true
    }

    // ---- Visuals -----------------------------------------------------------

    ColumnHeaderMenu {
        id: headerMenu
        onResizeRequested: root.resizeColumns()
        onVisibilityChanged: (role, vis) => root._setColumnVisible(role, vis)
    }

    // Default (plain text) cell delegate.
    Component {
        id: defaultCellComponent
        Label {
            text: (parent.value !== undefined && parent.value !== null) ? ("" + parent.value) : ""
            color: Theme.color("onSurface")
            font: Typography.bodyMedium
            elide: Text.ElideRight
            leftPadding: Spacing.sm
            rightPadding: Spacing.sm
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: parent.cellAlign
            anchors.fill: parent
        }
    }

    Flickable {
        id: hFlick
        anchors.fill: parent
        contentWidth: root._totalWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            width: root._totalWidth

            // ---- Header row ------------------------------------------------
            Rectangle {
                id: headerBar
                width: root._totalWidth
                height: root.headerHeight
                color: Theme.color("surface")

                Row {
                    anchors.fill: parent

                    Repeater {
                        model: colModel
                        delegate: Rectangle {
                            id: headerCell
                            width: model.visible ? model.width : 0
                            visible: model.visible
                            height: root.headerHeight
                            color: "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.right: resizeHandle.left
                                anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Spacing.lg
                                spacing: Spacing.xs

                                Label {
                                    text: String(model.title).toUpperCase()
                                    font: Typography.tableHeader
                                    color: Theme.color("muted")
                                    elide: Text.ElideRight
                                    width: Math.max(0, headerCell.width - Spacing.sm - resizeHandle.width -
                                                    (sortIndicator.visible ? sortIndicator.width + Spacing.xs : 0))
                                    horizontalAlignment: model.align
                                    verticalAlignment: Text.AlignVCenter
                                }

                                MDIcon {
                                    id: sortIndicator
                                    visible: root.sortRole === model.role
                                    icon: root.sortOrder === Qt.AscendingOrder ? Icons.arrow_upward : Icons.arrow_downward
                                    size: 16
                                    color: Theme.color("primary")
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Click to sort / drag to reorder.
                            MouseArea {
                                anchors.left: parent.left
                                anchors.right: resizeHandle.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: (mouse) => {
                                    if (mouse.button === Qt.LeftButton) {
                                        root._dragCol = index
                                        root._dragStartX = mapToItem(root, mouse.x, 0).x
                                    }
                                }
                                onReleased: (mouse) => {
                                    if (mouse.button !== Qt.LeftButton)
                                        return
                                    var x = mapToItem(root, mouse.x, 0).x
                                    if (Math.abs(x - root._dragStartX) < 8) {
                                        root._toggleSort(model.role)
                                    } else {
                                        var target = root._columnIndexAtX(x)
                                        if (target >= 0 && target !== root._dragCol) {
                                            colModel.move(root._dragCol, target, 1)
                                            root._bumpRev()
                                            root._persist()
                                            Log.debug("ui", "DataTable[" + root.persistKey +
                                                      "] moved column " + root._dragCol + " -> " + target)
                                        }
                                    }
                                    root._dragCol = -1
                                }
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        headerMenu.columns = root._columnsSnapshot()
                                        headerMenu.popup()
                                    }
                                }
                            }

                            // Right-edge resize grip.
                            MouseArea {
                                id: resizeHandle
                                width: 6
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                enabled: model.resizable
                                cursorShape: Qt.SplitHCursor
                                property real pressX: 0
                                property real startW: 0
                                onPressed: (mouse) => {
                                    pressX = mapToItem(root, mouse.x, 0).x
                                    startW = model.width
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed)
                                        return
                                    var cur = mapToItem(root, mouse.x, 0).x
                                    var nw = Math.max(root.minColumnWidth, startW + (cur - pressX))
                                    colModel.setProperty(index, "width", nw)
                                    root._bumpRev()
                                }
                                onReleased: root._persist()
                            }

                            // Column divider.
                            Rectangle {
                                anchors.right: parent.right
                                width: 1
                                height: parent.height
                                color: Theme.color("outlineVariant")
                            }
                        }
                    }
                }

                // Bottom divider under the whole header.
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.color("outline")
                }
            }

            // ---- Body rows -------------------------------------------------
            ListView {
                id: bodyView
                width: root._totalWidth
                height: hFlick.height - root.headerHeight
                clip: true
                model: root.model
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: rowDelegate
                    width: root._totalWidth
                    height: root.rowHeight

                    property var rowModel: model
                    property int rowIndex: index

                    color: root.isRowSelected(index)
                           ? Theme.color("surfaceWarm")
                           : (rowHover.hovered
                              ? Theme.color("surfaceWarm")
                              : (root.alternatingRows && (index % 2 === 1)
                                 ? Qt.alpha(Theme.color("surfaceVariant"), 0.4)
                                 : "transparent"))

                    HoverHandler { id: rowHover }

                    Row {
                        anchors.fill: parent

                        Repeater {
                            model: colModel
                            delegate: Loader {
                                id: cell
                                width: model.visible ? model.width : 0
                                visible: model.visible
                                height: root.rowHeight

                                property string cellRole: model.role
                                property int cellAlign: model.align
                                property int cellRow: rowDelegate.rowIndex
                                property int cellColumn: index
                                property var value: rowDelegate.rowModel
                                                    ? rowDelegate.rowModel[cellRole]
                                                    : undefined

                                sourceComponent: {
                                    if (root.delegateFor) {
                                        var comp = root.delegateFor({
                                            "role": cellRole, "column": index,
                                            "align": cellAlign, "title": model.title
                                        })
                                        if (comp)
                                            return comp
                                    }
                                    return defaultCellComponent
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                if (!root.isRowSelected(index))
                                    root._selectRow(index, Qt.NoModifier)
                                var p = mapToItem(root, mouse.x, mouse.y)
                                Log.debug("ui", "DataTable[" + root.persistKey + "] context for row " + index)
                                root.contextRequested(index, Qt.point(p.x, p.y))
                            } else {
                                root._selectRow(index, mouse.modifiers)
                            }
                        }
                        onDoubleClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                Log.debug("ui", "DataTable[" + root.persistKey + "] activated row " + index)
                                root.activated(index)
                            }
                        }
                    }

                    // Row bottom divider.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.color("outlineVariant"), 0.5)
                    }
                }

                focus: true
                Keys.onReturnPressed: if (root.currentRow >= 0) root.activated(root.currentRow)
                Keys.onSpacePressed: {
                    if (root.currentRow >= 0)
                        root._selectRow(root.currentRow, Qt.NoModifier)
                }
            }
        }
    }
}
