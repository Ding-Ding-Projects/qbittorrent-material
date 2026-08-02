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
    \qmltype ContentTab
    \brief The properties "Content" tab: the torrent's file/folder tree.

    A filter row (Select All / Select None + a files filter) over a Material
    \c TreeView bound to a \c TorrentContentFilterModel wrapping a
    \c TorrentContentModel. The content model is single-column with named roles
    (\c name / \c size / \c progress / \c priority / \c remaining / \c availability
    / \c checkState / \c isFolder), so the tree column's row delegate lays out all
    fields horizontally, indented by \c TreeView.depth. Mutations go through the
    model's own \c Q_INVOKABLE verbs operating on source \c QModelIndex values
    (translated with \c TorrentContentFilterModel.sourceIndex()).

    The model is fed by the current torrent's content handler, exposed by the
    controller as \c PropertiesController.contentHandler.
*/
Item {
    id: root

    // BitTorrent::DownloadPriority tokens.
    readonly property int prioIgnored: 0
    readonly property int prioNormal: 1
    readonly property int prioHigh: 6
    readonly property int prioMaximum: 7
    readonly property int prioMixed: -1

    // Fixed metric columns (the Name column takes the remaining width).
    readonly property int colSize: 100
    readonly property int colProgress: 120
    readonly property int colPriority: 150
    readonly property int colRemaining: 100
    readonly property int colAvailability: 100
    readonly property int fixedCols: colSize + colProgress + colPriority + colRemaining + colAvailability

    // ---- Bridge models --------------------------------------------------------
    TorrentContentModel {
        id: contentModel
        contentHandler: PropertiesController.contentHandler

        onRenameFailed: (message) => {
            Log.warning("ui", "ContentTab rename failed: " + message)
        }
    }

    TorrentContentFilterModel {
        id: contentFilter
        sourceModel: contentModel
    }

    // Minimal QML-only clipboard (hidden, off-screen TextEdit).
    TextEdit { id: clip; visible: false; width: 0; height: 0 }
    function _copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        Log.info("ui", "ContentTab copied path to clipboard")
    }

    // Translate a visual (proxy) row into a source-model index for the actions.
    function _srcIndex(row) {
        return contentFilter.sourceIndex(tree.index(row, 0))
    }

    function _rowSelected(row) {
        return tree.selectedRows.indexOf(row) >= 0
    }

    function _selectRow(row, modifiers) {
        let rows = tree.selectedRows.slice()
        const pos = rows.indexOf(row)
        if (modifiers & Qt.ControlModifier) {
            if (pos >= 0)
                rows.splice(pos, 1)
            else
                rows.push(row)
            tree.anchorRow = row
        } else if ((modifiers & Qt.ShiftModifier) && tree.anchorRow >= 0) {
            rows = []
            const lo = Math.min(tree.anchorRow, row)
            const hi = Math.max(tree.anchorRow, row)
            for (let i = lo; i <= hi; ++i)
                rows.push(i)
        } else {
            rows = [row]
            tree.anchorRow = row
        }
        tree.selectedRows = rows
        tree.selectedRow = rows.length > 0 ? row : -1
    }

    function _selectedSourceIndexes() {
        const result = []
        for (let i = 0; i < tree.selectedRows.length; ++i)
            result.push(_srcIndex(tree.selectedRows[i]))
        return result
    }

    function _priorityLabel(prio) {
        switch (prio) {
        case prioIgnored: return qsTr("Do not download")
        case prioNormal:  return qsTr("Normal")
        case prioHigh:    return qsTr("High")
        case prioMaximum: return qsTr("Maximum")
        default:          return qsTr("Mixed")
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.sm
        spacing: Spacing.sm

        // ---- Filter row -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.sm

            Button {
                text: qsTr("Select All")
                flat: true
                onClicked: {
                    Log.info("ui", "ContentTab select all")
                    contentModel.checkAll()
                }
            }
            Button {
                text: qsTr("Select None")
                flat: true
                onClicked: {
                    Log.info("ui", "ContentTab select none")
                    contentModel.checkNone()
                }
            }

            Item { Layout.fillWidth: true }

            FilterTextField {
                id: filterField
                Layout.preferredWidth: 300
                placeholder: qsTr("Filter files...")
                onTextChanged: contentFilter.filterPattern = text
                onRegexEnabledChanged: contentFilter.useRegex = regexEnabled
            }
        }

        // ---- Header row -------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            height: 32
            color: Theme.color("surfaceVariant")

            Row {
                anchors.fill: parent

                component HeaderCell: Label {
                    property int cellWidth: 100
                    property int cellAlign: Qt.AlignLeft
                    width: cellWidth
                    height: parent.height
                    leftPadding: Spacing.sm
                    rightPadding: Spacing.sm
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: cellAlign
                    elide: Text.ElideRight
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }

                HeaderCell {
                    cellWidth: Math.max(120, tree.width - root.fixedCols)
                    text: qsTr("Name")
                }
                HeaderCell { cellWidth: root.colSize; cellAlign: Qt.AlignRight; text: qsTr("Total Size") }
                HeaderCell { cellWidth: root.colProgress; cellAlign: Qt.AlignHCenter; text: qsTr("Progress") }
                HeaderCell { cellWidth: root.colPriority; text: qsTr("Download Priority") }
                HeaderCell { cellWidth: root.colRemaining; cellAlign: Qt.AlignRight; text: qsTr("Remaining") }
                HeaderCell { cellWidth: root.colAvailability; cellAlign: Qt.AlignRight; text: qsTr("Availability") }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.color("outline")
            }
        }

        // ---- File tree --------------------------------------------------------
        TreeView {
            id: tree
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: contentFilter
            boundsBehavior: Flickable.StopAtBounds

            property int selectedRow: -1
            property var selectedRows: []
            property int anchorRow: -1

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Single tree column that spans the full width.
            columnWidthProvider: () => tree.width
            rowHeightProvider: () => 40

            delegate: Item {
                id: rowItem

                required property int row
                required property var model
                // TreeView attached data.
                readonly property int depth: TreeView.depth
                readonly property bool hasChildren: TreeView.hasChildren
                readonly property bool expanded: TreeView.expanded

                implicitWidth: tree.width
                implicitHeight: 40

                readonly property bool selected: root._rowSelected(row)
                readonly property int nameWidth: Math.max(120, tree.width - root.fixedCols)

                Rectangle {
                    anchors.fill: parent
                    color: rowItem.selected
                           ? Qt.alpha(Theme.color("primary"), 0.12)
                           : (hover.hovered ? Qt.alpha(Theme.color("onSurface"), 0.08) : "transparent")

                    HoverHandler { id: hover }

                    Row {
                        anchors.fill: parent

                        // ---- Name cell: indent + chevron + checkbox + icon ----
                        Item {
                            width: rowItem.nameWidth
                            height: parent.height

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Spacing.sm + rowItem.depth * Spacing.lg
                                spacing: Spacing.xs

                                MDIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: rowItem.hasChildren
                                    icon: rowItem.expanded ? Icons.expand_more : Icons.chevron_right
                                    size: 18
                                    color: Theme.color("onSurfaceVariant")

                                    TapHandler {
                                        onTapped: {
                                            Log.debug("ui", "ContentTab toggle expand row " + rowItem.row)
                                            tree.toggleExpanded(rowItem.row)
                                        }
                                    }
                                }
                                // Spacer keeping alignment for leaf files.
                                Item {
                                    visible: !rowItem.hasChildren
                                    width: 18; height: 1
                                }

                                CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    padding: 0
                                    tristate: true
                                    checkState: rowItem.model.checkState
                                    // Derive the target from the CURRENT model state
                                    // so the bound checkState stays authoritative.
                                    onClicked: {
                                        const nowChecked = rowItem.model.checkState !== Qt.Checked
                                        Log.info("ui", "ContentTab set checked row " + rowItem.row + " -> " + nowChecked)
                                        contentModel.setChecked(root._srcIndex(rowItem.row), nowChecked)
                                    }
                                }

                                MDIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: rowItem.model.isFolder ? Icons.folder : Icons.insert_drive_file
                                    size: 18
                                    color: Theme.color("onSurfaceVariant")
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.model.name !== undefined ? ("" + rowItem.model.name) : ""
                                    font: Typography.bodyMedium
                                    color: Theme.color("onSurface")
                                    elide: Text.ElideRight
                                    width: Math.max(0, rowItem.nameWidth - (Spacing.sm + rowItem.depth * Spacing.lg) - 18 - 24 - 24 - Spacing.xs * 3)
                                }
                            }
                        }

                        // ---- Total size ----
                        Label {
                            width: root.colSize
                            height: parent.height
                            leftPadding: Spacing.sm
                            rightPadding: Spacing.sm
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: rowItem.model.size !== undefined ? ("" + rowItem.model.size) : ""
                            font: Typography.mono
                            color: Theme.color("onSurface")
                            elide: Text.ElideRight
                        }

                        // ---- Progress ----
                        Item {
                            width: root.colProgress
                            height: parent.height
                            ProgressCell {
                                anchors.fill: parent
                                anchors.margins: Spacing.xs
                                progress: {
                                    const v = rowItem.model.progress
                                    return (typeof v === "number") ? v : 0.0
                                }
                            }
                        }

                        // ---- Download priority combo ----
                        Item {
                            width: root.colPriority
                            height: parent.height

                            property int prioValue: {
                                const v = rowItem.model.priority
                                return (typeof v === "number") ? v : root.prioNormal
                            }

                            ComboBox {
                                id: prioCombo
                                anchors.fill: parent
                                anchors.margins: Spacing.xs
                                font: Typography.bodyMedium

                                readonly property bool isMixed: parent.prioValue === root.prioMixed
                                model: isMixed
                                       ? [qsTr("Do not download"), qsTr("Normal"), qsTr("High"), qsTr("Maximum"), qsTr("Mixed")]
                                       : [qsTr("Do not download"), qsTr("Normal"), qsTr("High"), qsTr("Maximum")]

                                currentIndex: {
                                    switch (parent.prioValue) {
                                    case root.prioIgnored: return 0
                                    case root.prioNormal:  return 1
                                    case root.prioHigh:    return 2
                                    case root.prioMaximum: return 3
                                    default:               return isMixed ? 4 : 1
                                    }
                                }

                                onActivated: (index) => {
                                    var prio = root.prioNormal
                                    switch (index) {
                                    case 0: prio = root.prioIgnored; break
                                    case 1: prio = root.prioNormal;  break
                                    case 2: prio = root.prioHigh;    break
                                    case 3: prio = root.prioMaximum; break
                                    default: return   // "Mixed" is not user-selectable
                                    }
                                    Log.info("ui", "ContentTab set priority row " + rowItem.row + " -> " + prio)
                                    contentModel.setItemPriority(root._srcIndex(rowItem.row), prio)
                                }
                            }
                        }

                        // ---- Remaining ----
                        Label {
                            width: root.colRemaining
                            height: parent.height
                            leftPadding: Spacing.sm
                            rightPadding: Spacing.sm
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: rowItem.model.remaining !== undefined ? ("" + rowItem.model.remaining) : ""
                            font: Typography.mono
                            color: Theme.color("onSurface")
                            elide: Text.ElideRight
                        }

                        // ---- Availability ----
                        Label {
                            width: root.colAvailability
                            height: parent.height
                            leftPadding: Spacing.sm
                            rightPadding: Spacing.sm
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: rowItem.model.availability !== undefined ? ("" + rowItem.model.availability) : ""
                            font: Typography.mono
                            color: Theme.color("onSurface")
                            elide: Text.ElideRight
                        }
                    }

                    // Row divider.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.color("outlineVariant"), 0.5)
                    }

                    // Behind the interactive controls (checkbox / combo / chevron)
                    // so they receive their own clicks; this only catches clicks
                    // on the label / empty areas for row selection + context menu.
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton && !root._rowSelected(rowItem.row))
                                root._selectRow(rowItem.row, Qt.NoModifier)
                            else if (mouse.button === Qt.LeftButton)
                                root._selectRow(rowItem.row, mouse.modifiers)
                            if (mouse.button === Qt.RightButton) {
                                const p = mapToItem(root, mouse.x, mouse.y)
                                contentMenu.x = p.x
                                contentMenu.y = p.y
                                contentMenu.open()
                            }
                        }
                        onDoubleClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton && rowItem.hasChildren)
                                tree.toggleExpanded(rowItem.row)
                        }
                    }
                }
            }
        }
    }

    // ---- Context menu ---------------------------------------------------------
    Menu {
        id: contentMenu
        Material.elevation: Spacing.elevationMenu

        readonly property int currentRow: tree.selectedRow
        readonly property bool hasRow: currentRow >= 0
        readonly property bool hasStorage: contentModel.hasStorageLocation()

        MenuItem {
            text: qsTr("Open")
            visible: contentMenu.hasRow && contentMenu.hasStorage
            height: visible ? implicitHeight : 0
            onTriggered: {
                const path = contentModel.itemFullPath(root._srcIndex(contentMenu.currentRow))
                Log.info("ui", "ContentTab open " + path)
                Qt.openUrlExternally("file:///" + path)
            }
        }
        MenuItem {
            text: qsTr("Open containing folder")
            visible: contentMenu.hasRow && contentMenu.hasStorage
            height: visible ? implicitHeight : 0
            onTriggered: {
                const path = contentModel.itemFullPath(root._srcIndex(contentMenu.currentRow))
                const dir = path.substring(0, Math.max(0, path.lastIndexOf("/")))
                Log.info("ui", "ContentTab open folder " + dir)
                Qt.openUrlExternally("file:///" + dir)
            }
        }
        MenuItem {
            text: qsTr("Copy path")
            visible: contentMenu.hasRow
            height: visible ? implicitHeight : 0
            onTriggered: root._copy(contentModel.itemRelativePath(root._srcIndex(contentMenu.currentRow)))
        }
        MenuItem {
            text: qsTr("Rename...")
            visible: contentMenu.hasRow && tree.selectedRows.length === 1
            height: visible ? implicitHeight : 0
            onTriggered: root._openRename(contentMenu.currentRow)
        }
        MenuItem {
            text: qsTr("Batch rename...")
            enabled: tree.selectedRows.length > 0
            Accessible.name: qsTr("Batch rename selected files")
            onTriggered: {
                batchRenameDialog.selectedFileIndexes = contentModel.fileIndexesForItems(root._selectedSourceIndexes())
                batchRenameDialog.open()
            }
        }

        MenuSeparator {}

        Menu {
            title: qsTr("Priority")
            enabled: contentMenu.hasRow

            MenuItem {
                text: qsTr("Do not download")
                onTriggered: contentModel.setItemPriority(root._srcIndex(contentMenu.currentRow), root.prioIgnored)
            }
            MenuItem {
                text: qsTr("Normal")
                onTriggered: contentModel.setItemPriority(root._srcIndex(contentMenu.currentRow), root.prioNormal)
            }
            MenuItem {
                text: qsTr("High")
                onTriggered: contentModel.setItemPriority(root._srcIndex(contentMenu.currentRow), root.prioHigh)
            }
            MenuItem {
                text: qsTr("Maximum")
                onTriggered: contentModel.setItemPriority(root._srcIndex(contentMenu.currentRow), root.prioMaximum)
            }
        }
    }

    function _openRename(row) {
        if (row < 0)
            return
        const idx = _srcIndex(row)
        // Derive the current name from the item's relative path (last segment).
        const rel = contentModel.itemRelativePath(idx)
        renameDialog.row = row
        renameDialog.originalName = rel.length ? rel.substring(rel.lastIndexOf("/") + 1) : ""
        renameDialog.open()
    }

    RenameFileDialog {
        id: renameDialog
        onFileRenamed: (row, newName) => {
            Log.info("ui", "ContentTab rename row " + row + " -> " + newName)
            contentModel.renameItem(root._srcIndex(row), newName)
        }
    }

    BatchRenameDialog {
        id: batchRenameDialog
        sourceModel: contentModel
        onApplied: (count) => NotificationCenter.notify(qsTr("Renamed %1 file(s)").arg(count), "success")
    }

    Component.onCompleted: Log.debug("ui", "ContentTab loaded")
}
