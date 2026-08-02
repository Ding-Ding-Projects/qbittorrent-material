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
import QtQml.Models
import qBittorrent

/*!
    \qmltype TorrentContentTree
    \brief The torrent content view — a file/folder tree with DataTable-like
           columns (Name / Total Size / Progress / Download Priority / Remaining
           / Availability), tri-state checkboxes, a per-row priority combo, a
           filter field, header sorting, a right-click menu and batch rename.

    Bind \l contentModel to a \c TorrentContentModel (the Content tab passes the
    live torrent's model; the Add dialog passes the in-memory adaptor's model).
    The tree wraps it in a \c TorrentContentFilterModel for the "Filter files…"
    field and header sorting, and drives every mutation back through the source
    model's \c Q_INVOKABLE verbs (setChecked / setItemPriority / renameItem /
    applyPriorities / …), always translating proxy indexes to source indexes.

    \qml
    TorrentContentTree { contentModel: TorrentContentModel { contentHandler: torrent } }
    \endqml
*/
Rectangle {
    id: root

    /*! The \c TorrentContentModel to display (source model, not the proxy). */
    property var contentModel: null

    /*! The internal sort/filter proxy (exposed for advanced hosts). */
    property alias proxyModel: filterModel

    /*! Double-click behavior on a file: 0 = open, 1 = rename (mirrors the widget). */
    property int doubleClickAction: 0

    /*! Per-depth indentation of the tree column, in pixels. */
    property int indentation: 16

    // ---- Column geometry (Name flexes; the rest are fixed and right-aligned) --
    readonly property int rowHeight: 32
    readonly property int colSizeWidth: 96
    readonly property int colProgressWidth: 132
    readonly property int colPriorityWidth: 148
    readonly property int colRemainingWidth: 96
    readonly property int colAvailWidth: 96
    // Minimum content width: all fixed value columns + a legible Name minimum.
    readonly property int _minContentWidth: colSizeWidth + colProgressWidth + colPriorityWidth
                                            + colRemainingWidth + colAvailWidth + 180

    // ---- Sort state ---------------------------------------------------------
    property string _sortRole: "name"
    property int _sortOrder: Qt.AscendingOrder

    // ---- Selection anchor (for Shift range selection) -----------------------
    property int _anchorRow: -1

    // ---- Context-menu target (single-selection actions) ---------------------
    property var _ctxIndex: null
    property string _ctxName: ""

    color: Theme.color("surface")
    border.width: 1
    border.color: Theme.color("outlineVariant")
    radius: Spacing.radiusCard
    implicitWidth: Math.max(640, _minContentWidth)
    implicitHeight: 320

    Component.onCompleted: Log.debug("ui", "TorrentContentTree ready")

    // =========================================================================
    //  Models
    // =========================================================================

    TorrentContentFilterModel {
        id: filterModel
        sourceModel: root.contentModel
    }

    Connections {
        target: root.contentModel
        ignoreUnknownSignals: true

        function onRenameFailed(errorMessage) {
            Log.warning("ui", "Content rename failed: " + errorMessage)
            NotificationCenter.notify(errorMessage, "error")
        }

        // Show the top-level folder expanded once metadata arrives.
        function onMetadataReadyChanged() {
            Qt.callLater(() => contentTree.expand(0))
        }
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    function _proxyIndex(row) {
        return contentTree.index(row, 0)
    }

    function _sourceIndex(row) {
        return filterModel.sourceIndex(contentTree.index(row, 0))
    }

    function _selectedSourceIndexes() {
        const proxied = selectionModel.selectedIndexes
        const out = []
        for (let i = 0; i < proxied.length; ++i)
            out.push(filterModel.sourceIndex(proxied[i]))
        return out
    }

    function _selectRow(row, modifiers) {
        const proxyIndex = _proxyIndex(row)
        if (modifiers & Qt.ControlModifier) {
            selectionModel.select(proxyIndex, ItemSelectionModel.Toggle)
            _anchorRow = row
        } else if ((modifiers & Qt.ShiftModifier) && (_anchorRow >= 0)) {
            selectionModel.clearSelection()
            const lo = Math.min(_anchorRow, row)
            const hi = Math.max(_anchorRow, row)
            for (let r = lo; r <= hi; ++r)
                selectionModel.select(_proxyIndex(r), ItemSelectionModel.Select)
        } else {
            selectionModel.clearSelection()
            selectionModel.select(proxyIndex, ItemSelectionModel.Select)
            _anchorRow = row
        }
        selectionModel.setCurrentIndex(proxyIndex, ItemSelectionModel.NoUpdate)
        Log.trace("ui", "Content selection changed; count=" + selectionModel.selectedIndexes.length)
    }

    function _fileUrl(path) {
        return "file:///" + ("" + path).replace(/\\/g, "/")
    }

    function _parentDir(path) {
        const norm = ("" + path).replace(/\\/g, "/")
        const i = norm.lastIndexOf("/")
        return (i > 0) ? norm.substring(0, i) : norm
    }

    function _openIndex(sourceIndex) {
        if (!sourceIndex || !root.contentModel)
            return
        const full = root.contentModel.itemFullPath(sourceIndex)
        if (full.length === 0)
            return
        Log.info("ui", "Content: opening " + full)
        Qt.openUrlExternally(_fileUrl(full))
    }

    function _toggleSort(role) {
        if (_sortRole === role)
            _sortOrder = (_sortOrder === Qt.AscendingOrder) ? Qt.DescendingOrder : Qt.AscendingOrder
        else {
            _sortRole = role
            _sortOrder = Qt.AscendingOrder
        }
        Log.debug("ui", "Content sort: " + _sortRole + " order=" + _sortOrder)
        filterModel.sortByRole(_sortRole, _sortOrder)
    }

    function _copyToClipboard(text) {
        clipboardHelper.text = text
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
    }

    // QML-only clipboard bridge (no native widget needed).
    TextEdit {
        id: clipboardHelper
        visible: false
        width: 0
        height: 0
    }

    // A clickable column header with a sort-direction indicator. Declared at the
    // root level so it is visible to the header cells below.
    component HeaderCell: Item {
        id: cell
        property string title: ""
        property string role: ""
        property int align: Text.AlignRight

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.sm
            anchors.rightMargin: Spacing.sm
            spacing: 2
            layoutDirection: cell.align === Text.AlignRight ? Qt.RightToLeft : Qt.LeftToRight

            Label {
                Layout.fillWidth: true
                text: cell.title
                font: Typography.labelLarge
                color: Theme.color("onSurfaceVariant")
                elide: Text.ElideRight
                horizontalAlignment: cell.align
            }

            MDIcon {
                visible: root._sortRole === cell.role
                icon: root._sortOrder === Qt.AscendingOrder ? Icons.arrow_upward : Icons.arrow_downward
                size: 14
                color: Theme.color("primary")
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root._toggleSort(cell.role)
        }
    }

    // =========================================================================
    //  Layout
    // =========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        // ---- Filter row -----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Spacing.sm
            spacing: Spacing.sm

            FilterTextField {
                id: filterField
                Layout.fillWidth: true
                placeholder: qsTr("Filter files…")
                regexEnabled: filterModel.useRegex
                onTextChanged: {
                    filterModel.filterPattern = text
                    if (text.length > 0)
                        contentTree.expandRecursively()
                }
                onRegexEnabledChanged: filterModel.useRegex = regexEnabled
            }
        }

        // ---- Header row -----------------------------------------------------
        Item {
            id: header
            Layout.fillWidth: true
            implicitHeight: 36

            Rectangle {
                anchors.fill: parent
                color: Theme.color("surfaceVariant")
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.color("outlineVariant")
            }

            // Availability (rightmost) ← Remaining ← Priority ← Progress ← Size
            HeaderCell {
                id: availHeader
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.colAvailWidth
                title: qsTr("Availability")
                role: "availability"
            }
            HeaderCell {
                id: remainingHeader
                anchors.right: availHeader.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.colRemainingWidth
                title: qsTr("Remaining")
                role: "remaining"
            }
            HeaderCell {
                id: priorityHeader
                anchors.right: remainingHeader.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.colPriorityWidth
                title: qsTr("Download Priority")
                role: "priority"
                align: Text.AlignLeft
            }
            HeaderCell {
                id: progressHeader
                anchors.right: priorityHeader.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.colProgressWidth
                title: qsTr("Progress")
                role: "progress"
                align: Text.AlignHCenter
            }
            HeaderCell {
                id: sizeHeader
                anchors.right: progressHeader.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.colSizeWidth
                title: qsTr("Total Size")
                role: "size"
            }
            HeaderCell {
                anchors.left: parent.left
                anchors.right: sizeHeader.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                title: qsTr("Name")
                role: "name"
                align: Text.AlignLeft
            }
        }

        // ---- The tree -------------------------------------------------------
        TreeView {
            id: contentTree
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: filterModel

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            selectionModel: ItemSelectionModel { id: selectionModel }

            // Single logical column pinned to the viewport width: the value
            // columns anchor to the row's right edge, so keeping the column
            // exactly as wide as the view lines them up with the fixed header
            // (and avoids a horizontal scrollbar the header could not follow).
            columnWidthProvider: (column) => width
            onWidthChanged: Qt.callLater(forceLayout)

            delegate: Item {
                id: rowItem

                implicitWidth: contentTree.width
                implicitHeight: root.rowHeight

                // Tree-structure properties injected by TreeView.
                required property int row
                required property int depth
                required property bool expanded
                required property bool hasChildren

                // Model roles.
                required property string name
                required property bool isFolder
                required property int checkState
                required property real progress
                required property string progressText
                required property int priority
                required property string size
                required property string remaining
                required property string availability

                readonly property bool rowSelected: {
                    const dep = selectionModel.selectedIndexes.length // establish binding
                    return selectionModel.isSelected(root._proxyIndex(rowItem.row))
                }

                // -- Row background (selection / hover) --
                Rectangle {
                    anchors.fill: parent
                    color: rowItem.rowSelected
                           ? Qt.alpha(Theme.color("primary"), 0.12)
                           : (rowMouse.containsMouse ? Qt.alpha(Theme.color("onSurface"), 0.08) : "transparent")
                }

                // -- Interaction layer (below the interactive controls) --
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            const proxyIndex = root._proxyIndex(rowItem.row)
                            if (!selectionModel.isSelected(proxyIndex)) {
                                selectionModel.clearSelection()
                                selectionModel.select(proxyIndex, ItemSelectionModel.Select)
                                selectionModel.setCurrentIndex(proxyIndex, ItemSelectionModel.NoUpdate)
                                root._anchorRow = rowItem.row
                            }
                            root._ctxIndex = root._sourceIndex(rowItem.row)
                            root._ctxName = rowItem.name
                            contextMenu.single = (selectionModel.selectedIndexes.length <= 1)
                            contextMenu.hasStorage = root.contentModel ? root.contentModel.hasStorageLocation() : false
                            Log.debug("ui", "Content tree context menu for '" + rowItem.name + "'")
                            contextMenu.popup()
                        } else {
                            root._selectRow(rowItem.row, mouse.modifiers)
                        }
                    }

                    onDoubleClicked: (mouse) => {
                        if (mouse.button !== Qt.LeftButton)
                            return
                        if (rowItem.isFolder) {
                            contentTree.toggleExpanded(rowItem.row)
                            return
                        }
                        const src = root._sourceIndex(rowItem.row)
                        if (root.doubleClickAction === 1) {
                            root._ctxIndex = src
                            root._ctxName = rowItem.name
                            renameDialog.text = rowItem.name
                            renameDialog.open()
                        } else if (root.contentModel && root.contentModel.hasStorageLocation()) {
                            root._openIndex(src)
                        }
                    }
                }

                // -- Name column (indent + expander + checkbox + icon + name) --
                RowLayout {
                    id: nameColumn
                    anchors.left: parent.left
                    anchors.right: sizeCell.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Spacing.xs

                    Item { // depth indentation
                        Layout.preferredWidth: rowItem.depth * root.indentation
                        Layout.preferredHeight: 1
                    }

                    Item { // expander (always reserves space so columns align)
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20

                        MDIcon {
                            anchors.centerIn: parent
                            visible: rowItem.hasChildren
                            icon: Icons.chevron_right
                            size: 18
                            color: Theme.color("onSurfaceVariant")
                            rotation: rowItem.expanded ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: rowItem.hasChildren
                            onClicked: contentTree.toggleExpanded(rowItem.row)
                        }
                    }

                    CheckBox {
                        id: checkBox
                        Layout.preferredWidth: 32
                        tristate: true
                        checkState: rowItem.checkState
                        padding: 0

                        onClicked: {
                            const wantChecked = (rowItem.checkState !== Qt.Checked)
                            Log.debug("ui", "Content check toggled for '" + rowItem.name + "' -> " + wantChecked)
                            root.contentModel.setChecked(root._sourceIndex(rowItem.row), wantChecked)
                            // Re-assert the model as the source of truth.
                            checkState = Qt.binding(() => rowItem.checkState)
                        }
                    }

                    MDIcon {
                        icon: rowItem.isFolder ? Icons.folder : Icons.insert_drive_file
                        size: 18
                        color: Theme.color("onSurfaceVariant")
                    }

                    Label {
                        Layout.fillWidth: true
                        text: rowItem.name
                        font: Typography.bodyMedium
                        color: Theme.color("onSurface")
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                // -- Total Size --
                Label {
                    id: sizeCell
                    anchors.right: progressCell.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colSizeWidth
                    rightPadding: Spacing.sm
                    text: rowItem.size
                    font: Typography.mono
                    color: Theme.color("onSurface")
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }

                // -- Progress --
                ProgressCell {
                    id: progressCell
                    anchors.right: priorityCell.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colProgressWidth
                    height: 18
                    progress: rowItem.progress
                    active: rowItem.priority !== 0 // Ignored → disabled look
                    text: rowItem.progressText
                }

                // -- Download Priority --
                ContentPriorityDelegate {
                    id: priorityCell
                    anchors.right: remainingCell.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colPriorityWidth
                    priority: rowItem.priority
                    allowMixed: rowItem.priority === -1
                    onPriorityPicked: (value) => {
                        Log.info("ui", "Content priority combo -> " + value + " for '" + rowItem.name + "'")
                        root.contentModel.setItemPriority(root._sourceIndex(rowItem.row), value)
                    }
                }

                // -- Remaining --
                Label {
                    id: remainingCell
                    anchors.right: availCell.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colRemainingWidth
                    rightPadding: Spacing.sm
                    text: rowItem.remaining
                    font: Typography.mono
                    color: Theme.color("onSurfaceVariant")
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }

                // -- Availability --
                Label {
                    id: availCell
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.colAvailWidth
                    rightPadding: Spacing.sm
                    text: rowItem.availability
                    font: Typography.mono
                    color: Theme.color("onSurfaceVariant")
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- Empty / waiting-for-metadata overlay -------------------------------
    ColumnLayout {
        anchors.centerIn: parent
        spacing: Spacing.sm
        visible: !root.contentModel || !root.contentModel.metadataReady

        MDIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: Icons.folder_open
            size: 40
            color: Theme.color("onSurfaceVariant")
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Waiting for metadata…")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
        }
    }

    // =========================================================================
    //  Menus & dialogs
    // =========================================================================

    ContentTreeContextMenu {
        id: contextMenu

        onOpenTriggered: root._openIndex(root._ctxIndex)
        onOpenContainingFolderTriggered: {
            if (!root._ctxIndex || !root.contentModel)
                return
            const full = root.contentModel.itemFullPath(root._ctxIndex)
            if (full.length > 0)
                Qt.openUrlExternally(root._fileUrl(root._parentDir(full)))
        }
        onCopyPathTriggered: {
            if (root._ctxIndex && root.contentModel)
                root._copyToClipboard(root.contentModel.itemFullPath(root._ctxIndex))
        }
        onRenameTriggered: {
            renameDialog.text = root._ctxName
            renameDialog.open()
        }
        onBatchRenameTriggered: {
            batchRenameDialog.selectedFileIndexes = root.contentModel
                    ? root.contentModel.fileIndexesForItems(root._selectedSourceIndexes()) : []
            batchRenameDialog.open()
        }
        onPrioritySelected: (value) => {
            if (root.contentModel)
                root.contentModel.applyPriorities(root._selectedSourceIndexes(), value)
        }
        onPriorityByOrderTriggered: {
            if (root.contentModel)
                root.contentModel.applyPrioritiesByOrder(root._selectedSourceIndexes())
        }
    }

    TextInputDialog {
        id: renameDialog
        title: qsTr("Renaming")
        label: qsTr("New name:")
        onAccepted: (text) => {
            if (root._ctxIndex && root.contentModel)
                root.contentModel.renameItem(root._ctxIndex, text)
        }
    }

    BatchRenameDialog {
        id: batchRenameDialog
        sourceModel: root.contentModel
        onApplied: (count) => {
            Log.info("ui", "Content batch rename applied to " + count + " file(s)")
            NotificationCenter.notify(qsTr("Renamed %1 file(s)").arg(count), "success")
        }
    }
}
