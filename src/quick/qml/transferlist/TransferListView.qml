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
import Qt.labs.platform as Platform
import qBittorrent

/*!
    \qmltype TransferListView
    \brief The main torrent table.

    Wraps \c DataTable over the shared \l proxy (a \c TorrentFilterProxyModel
    around the \c TransferListModel singleton). Renders the full column inventory
    (\c TransferListModel::Column), draws the progress column with \c ProgressCell,
    colors row text per \c TorrentState via \c StateColors (when the
    \c GUI/TransferList/UseTorrentStatesColors preference is on) and hosts the row
    context menu (\l TransferRowContextMenu), the column-visibility menu
    (\l TransferColumnMenu) and every Material dialog those actions require.

    Selection is pushed to \c TransferController.selectedIds (mapped from the
    proxy via \c idAt), which the bridge wires to \c PropertiesController — no
    polling. Header clicks re-sort through \c proxy.sortByColumn.
*/
Item {
    id: view

    clip: true

    /*! The shared sort/filter proxy (set by \l TransfersTab). */
    property var proxy: null

    /*! Name of the current (focused) torrent — published by the Name cell. */
    property string currentName: ""

    function focusFilter() { filterField.forceActiveFocus() }

    Rectangle {
        anchors.fill: parent
        z: -1
        radius: Spacing.radiusPanel
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outline")
    }

    // ---- Column inventory (matches TransferListModel::Column order) --------
    // `role` == the model role name (must match TransferListModel::roleNames);
    // `title` is translated here (the English literal is the i18n key).
    property var columns: [
        { role: "queuePosition", title: qsTr("#"),                   width: 44,  align: Qt.AlignRight,   visible: true },
        { role: "name",          title: qsTr("Name"),                width: 320, align: Qt.AlignLeft,    visible: true },
        { role: "size",          title: qsTr("Size"),                width: 90,  align: Qt.AlignRight,   visible: true },
        { role: "totalSize",     title: qsTr("Total Size"),          width: 90,  align: Qt.AlignRight,   visible: false },
        { role: "progress",      title: qsTr("Progress"),            width: 120, align: Qt.AlignHCenter, visible: true },
        { role: "status",        title: qsTr("Status"),              width: 130, align: Qt.AlignLeft,    visible: true },
        { role: "seeds",         title: qsTr("Seeds"),               width: 80,  align: Qt.AlignRight,   visible: true },
        { role: "peers",         title: qsTr("Peers"),               width: 80,  align: Qt.AlignRight,   visible: true },
        { role: "downSpeed",     title: qsTr("Down Speed"),          width: 100, align: Qt.AlignRight,   visible: true },
        { role: "upSpeed",       title: qsTr("Up Speed"),            width: 100, align: Qt.AlignRight,   visible: true },
        { role: "eta",           title: qsTr("ETA"),                 width: 90,  align: Qt.AlignRight,   visible: true },
        { role: "ratio",         title: qsTr("Ratio"),               width: 70,  align: Qt.AlignRight,   visible: true },
        { role: "popularity",    title: qsTr("Popularity"),          width: 90,  align: Qt.AlignRight,   visible: false,
          tooltip: qsTr("Ratio / Time Active (in months), indicates how popular the torrent is") },
        { role: "category",      title: qsTr("Category"),            width: 120, align: Qt.AlignLeft,    visible: true },
        { role: "tags",          title: qsTr("Tags"),                width: 120, align: Qt.AlignLeft,    visible: true },
        { role: "addedOn",       title: qsTr("Added On"),            width: 140, align: Qt.AlignLeft,    visible: false },
        { role: "completedOn",   title: qsTr("Completed On"),        width: 140, align: Qt.AlignLeft,    visible: false },
        { role: "tracker",       title: qsTr("Tracker"),             width: 180, align: Qt.AlignLeft,    visible: false },
        { role: "downLimit",     title: qsTr("Down Limit"),          width: 100, align: Qt.AlignRight,   visible: false },
        { role: "upLimit",       title: qsTr("Up Limit"),            width: 100, align: Qt.AlignRight,   visible: false },
        { role: "downloaded",    title: qsTr("Downloaded"),          width: 100, align: Qt.AlignRight,   visible: false },
        { role: "uploaded",      title: qsTr("Uploaded"),            width: 100, align: Qt.AlignRight,   visible: false },
        { role: "sessionDownloaded", title: qsTr("Session Downloaded"), width: 130, align: Qt.AlignRight, visible: false },
        { role: "sessionUploaded",   title: qsTr("Session Uploaded"),   width: 130, align: Qt.AlignRight, visible: false },
        { role: "remaining",     title: qsTr("Remaining"),           width: 100, align: Qt.AlignRight,   visible: false },
        { role: "timeActive",    title: qsTr("Time Active"),         width: 130, align: Qt.AlignLeft,    visible: false },
        { role: "savePath",      title: qsTr("Save Path"),           width: 220, align: Qt.AlignLeft,    visible: false },
        { role: "completed",     title: qsTr("Completed"),           width: 100, align: Qt.AlignRight,   visible: false },
        { role: "ratioLimit",    title: qsTr("Ratio Limit"),         width: 90,  align: Qt.AlignRight,   visible: false },
        { role: "lastSeenComplete", title: qsTr("Last Seen Complete"), width: 150, align: Qt.AlignLeft,  visible: false },
        { role: "lastActivity",  title: qsTr("Last Activity"),       width: 130, align: Qt.AlignRight,   visible: false },
        { role: "availability",  title: qsTr("Availability"),        width: 100, align: Qt.AlignRight,   visible: false },
        { role: "downloadPath",  title: qsTr("Incomplete Save Path"), width: 220, align: Qt.AlignLeft,   visible: false },
        { role: "infoHashV1",    title: qsTr("Info Hash v1"),        width: 260, align: Qt.AlignLeft,    visible: false },
        { role: "infoHashV2",    title: qsTr("Info Hash v2"),        width: 260, align: Qt.AlignLeft,    visible: false },
        { role: "reannounce",    title: qsTr("Reannounce In"),       width: 110, align: Qt.AlignRight,   visible: false },
        { role: "private",       title: qsTr("Private"),             width: 70,  align: Qt.AlignLeft,    visible: false },
        { role: "createdOn",     title: qsTr("Created On"),          width: 140, align: Qt.AlignLeft,    visible: false }
    ]

    // Immutable role order (== TransferListModel::Column). Used to map a sort
    // role back to a column index for proxy.sortByColumn (visibility toggles
    // never renumber this).
    readonly property var columnRoles: [
        "queuePosition", "name", "size", "totalSize", "progress", "status",
        "seeds", "peers", "downSpeed", "upSpeed", "eta", "ratio", "popularity",
        "category", "tags", "addedOn", "completedOn", "tracker", "downLimit",
        "upLimit", "downloaded", "uploaded", "sessionDownloaded",
        "sessionUploaded", "remaining", "timeActive", "savePath", "completed",
        "ratioLimit", "lastSeenComplete", "lastActivity", "availability",
        "downloadPath", "infoHashV1", "infoHashV2", "reannounce", "private",
        "createdOn"
    ]

    // ---- Preference-gated visual policy ------------------------------------

    function useStateColors() {
        return Preferences.value("GUI/TransferList/UseTorrentStatesColors", true) === true;
    }
    function progressFollowsText() {
        return Preferences.value("GUI/TransferList/ProgressBarFollowsTextColor", false) === true;
    }

    // Walk up from a cell delegate instance to the DataTable row's model object.
    function findRowModel(item) {
        var p = item;
        while (p) {
            if (p.rowModel !== undefined && p.rowModel !== null)
                return p.rowModel;
            p = p.parent;
        }
        return null;
    }

    // Row text color: the per-state color (when enabled) else the default.
    function textColor(rm) {
        if (rm && useStateColors()) {
            var s = rm.state;
            if (s !== undefined && s !== null && s !== -1)
                return StateColors.forState(s);
        }
        return Theme.color("onSurface");
    }

    // Progress bar is drawn "disabled" for Error(17) / StoppedDownloading(13) / Unknown(-1).
    function progressActive(state) {
        return !(state === 17 || state === 13 || state === -1 || state === undefined);
    }

    // TorrentState int -> the Name-column state glyph.
    function stateIconId(state) {
        switch (state) {
        case 0: case 1: case 2: case 3: return Icons.download;       // (Forced)Downloading(Metadata)
        case 4:  return Icons.hourglass_empty;                       // StalledDownloading
        case 5: case 6: return Icons.upload;                         // (Forced)Uploading
        case 7:  return Icons.hourglass_empty;                       // StalledUploading
        case 8: case 11: case 12: return Icons.fact_check;           // Checking*
        case 9: case 10: return Icons.low_priority;                  // Queued*
        case 13: return Icons.pause;                                 // StoppedDownloading
        case 14: return Icons.check_circle;                          // StoppedUploading (completed)
        case 15: return Icons.drive_file_move;                       // Moving
        case 16: case 17: return Icons.error;                        // MissingFiles / Error
        default: return Icons.insert_drive_file;
        }
    }

    function _localPath(u) {
        var s = "" + u;
        return s.replace(/^file:\/\/\//, "").replace(/^file:\/\//, "");
    }

    // ---- Selection & sort wiring ------------------------------------------

    // Translate the DataTable's selected proxy rows into TorrentID strings.
    function _syncSelection() {
        if (!view.proxy)
            return;
        var ids = [];
        var rows = table.selectedRows;
        for (var i = 0; i < rows.length; ++i) {
            var id = view.proxy.idAt(rows[i]);
            if (id && id.length > 0)
                ids.push(id);
        }
        TransferController.selectedIds = ids;
        Log.debug("ui", "Transfer selection -> " + ids.length + " torrent(s)");
    }

    function _applySort() {
        if (!view.proxy || table.sortRole.length === 0)
            return;
        var col = view.columnRoles.indexOf(table.sortRole);
        if (col < 0)
            return;
        Log.debug("ui", "Transfer sort -> column " + col + " (" + table.sortRole + ")");
        view.proxy.sortByColumn(col, table.sortOrder);
    }

    function requestDelete() {
        if (TransferController.selectionCount === 0)
            return;
        deleteDialog.open();
    }

    // Apply a TorrentOptionsDialog result to the selection through the controller.
    function _applyTorrentOptions(r) {
        if (!r)
            return;
        if ((r.autoTMM !== undefined) && (r.autoTMM !== Qt.PartiallyChecked))
            TransferController.setAutoTMM(r.autoTMM === Qt.Checked);
        if (r.category !== undefined)
            TransferController.setCategory(r.category);
        if ((r.savePath !== undefined) && (("" + r.savePath).length > 0))
            TransferController.setLocation(r.savePath);
        if (r.upLimit !== undefined)
            TransferController.setUploadLimit(r.upLimit * 1024);
        if (r.downLimit !== undefined)
            TransferController.setDownloadLimit(r.downLimit * 1024);
        if ((r.sequential !== undefined) && (r.sequential !== Qt.PartiallyChecked))
            TransferController.setSequential(r.sequential === Qt.Checked);
        if ((r.firstLastPieces !== undefined) && (r.firstLastPieces !== Qt.PartiallyChecked))
            TransferController.setFirstLastPiece(r.firstLastPieces === Qt.Checked);
        if ((r.superSeeding !== undefined) && (r.superSeeding !== Qt.PartiallyChecked))
            TransferController.setSuperSeeding(r.superSeeding === Qt.Checked);
        if ((r.ratioLimit !== undefined) || (r.seedingTimeLimit !== undefined)
                || (r.inactiveSeedingTimeLimit !== undefined)) {
            TransferController.setShareLimits(
                r.ratioLimit !== undefined ? r.ratioLimit : -2,
                r.seedingTimeLimit !== undefined ? r.seedingTimeLimit : -2,
                r.inactiveSeedingTimeLimit !== undefined ? r.inactiveSeedingTimeLimit : -2);
        }
        Log.info("ui", "Applied torrent options to selection");
    }

    // ---- Cell delegates ----------------------------------------------------

    // Default text cell (state-colored, alignment-aware).
    Component {
        id: textCellComp
        Label {
            readonly property var rm: view.findRowModel(this)
            text: (parent.value !== undefined && parent.value !== null) ? ("" + parent.value) : ""
            color: view.textColor(rm)
            font: Typography.bodyMedium
            elide: Text.ElideRight
            leftPadding: Spacing.sm
            rightPadding: Spacing.sm
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: parent.cellAlign
            anchors.fill: parent
        }
    }

    // Name cell: state icon + name text. Publishes the focused row's name.
    Component {
        id: nameCellComp
        Item {
            id: nameCell
            readonly property var rm: view.findRowModel(this)
            readonly property string cellText:
                (parent.value !== undefined && parent.value !== null) ? ("" + parent.value) : ""
            readonly property bool isCurrent: parent.cellRow === table.currentRow

            onIsCurrentChanged: if (isCurrent) view.currentName = cellText
            onCellTextChanged:  if (isCurrent) view.currentName = cellText

            Row {
                anchors.fill: parent
                anchors.leftMargin: Spacing.sm
                spacing: Spacing.xs
                MDIcon {
                    icon: nameCell.rm ? view.stateIconId(nameCell.rm.state) : Icons.insert_drive_file
                    size: 18
                    color: view.textColor(nameCell.rm)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: nameCell.cellText
                    color: view.textColor(nameCell.rm)
                    font: Typography.bodyMedium
                    elide: Text.ElideRight
                    width: Math.max(0, parent.width - Spacing.lg)
                    verticalAlignment: Text.AlignVCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Progress cell.
    Component {
        id: progressCellComp
        ProgressCell {
            readonly property var rm: view.findRowModel(this)
            anchors.fill: parent
            progress: (parent.value !== undefined && parent.value !== null) ? parent.value : 0
            active: rm ? view.progressActive(rm.state) : true
            barColor: (rm && view.progressFollowsText())
                      ? StateColors.forState(rm.state)
                      : Theme.color("primary")
        }
    }

    // ---- Layout ------------------------------------------------------------

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Panel header: filtering and column controls stay aligned to the table.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Spacing.controlHeight + (2 * Spacing.lg)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Spacing.xl
                anchors.rightMargin: Spacing.xl
                spacing: Spacing.md

                FilterTextField {
                    id: filterField
                    Layout.fillWidth: true
                    Layout.preferredWidth: 300
                    Layout.maximumWidth: 480
                    placeholder: qsTr("Filter torrent list")
                    Component.onCompleted: {
                        if (view.proxy) {
                            text = view.proxy.textFilter;
                            regexEnabled = view.proxy.useRegex;
                        }
                    }
                    onTextChanged: {
                        if (!view.proxy)
                            return;
                        Log.debug("ui", "Transfer column filter -> '" + text + "'");
                        view.proxy.textFilter = text;
                    }
                    onRegexEnabledChanged: {
                        if (!view.proxy)
                            return;
                        Log.debug("ui", "Transfer name filter regex -> " + regexEnabled);
                        view.proxy.useRegex = regexEnabled;
                    }
                }

                Label {
                    text: qsTr("Filter by:")
                    font: Typography.labelLarge
                    color: Theme.color("onSurfaceVariant")
                }

                ComboBox {
                    id: filterColumnCombo
                    Layout.preferredWidth: 150
                    implicitHeight: Spacing.controlHeight
                    textRole: "label"
                    valueRole: "column"
                    model: [
                        { label: qsTr("Name"), column: TransferListModel.TR_NAME },
                        { label: qsTr("Save path"), column: TransferListModel.TR_SAVE_PATH },
                        { label: qsTr("Info hash v1"), column: TransferListModel.TR_INFOHASH_V1 },
                        { label: qsTr("Info hash v2"), column: TransferListModel.TR_INFOHASH_V2 }
                    ]
                    Component.onCompleted: {
                        if (!view.proxy)
                            return
                        for (let index = 0; index < model.length; ++index) {
                            if (model[index].column === view.proxy.textFilterColumn) {
                                currentIndex = index
                                break
                            }
                        }
                    }
                    onActivated: (index) => {
                        if (!view.proxy || index < 0)
                            return
                        view.proxy.textFilterColumn = model[index].column
                        Log.debug("ui", "Transfer filter column -> " + model[index].label)
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    id: columnsButton
                    text: qsTr("Columns")
                    implicitHeight: Spacing.controlHeight
                    leftPadding: Spacing.lg
                    rightPadding: Spacing.lg
                    contentItem: RowLayout {
                        spacing: Spacing.sm
                        MDIcon {
                            icon: Icons.more_vert
                            size: 18
                            color: Theme.color("onSurfaceVariant")
                        }
                        Label {
                            text: columnsButton.text
                            font: Typography.labelLarge
                            color: Theme.color("onSurface")
                        }
                    }
                    onClicked: {
                        Log.debug("ui", "Opening column visibility menu");
                        columnMenu.columns = view.columns;
                        columnMenu.popup();
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.color("outlineVariant")
            }
        }

        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true

            model: view.proxy
            columns: view.columns
            persistKey: "TransferList"
            rowHeight: Spacing.rowHeight
            headerHeight: Spacing.controlHeight

            delegateFor: (col) => {
                if (col.role === "progress")
                    return progressCellComp;
                if (col.role === "name")
                    return nameCellComp;
                return textCellComp;
            }

            onSelectionChanged: view._syncSelection()
            onSortRoleChanged: view._applySort()
            onSortOrderChanged: view._applySort()
            onActivated: (row) => {
                Log.info("ui", "Transfer row activated (double-click/Enter): " + row);
                view._syncSelection();
                TransferController.openDestination();
            }
            onContextRequested: (row, pos) => {
                view._syncSelection();
                Log.debug("ui", "Transfer context requested for row " + row);
                rowMenu.popup(pos.x, pos.y);
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Spacing.xl
        spacing: Spacing.sm
        visible: view.proxy && view.proxy.count === 0
        z: 2

        MDIcon {
            icon: Icons.download
            size: 36
            color: Theme.color("outline")
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            text: qsTr("No torrents match this view")
            font: Typography.titleMedium
            color: Theme.color("onSurfaceVariant")
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            text: qsTr("Add a torrent or clear the active filters to continue.")
            font: Typography.metadata
            color: Theme.color("muted")
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // ---- Menus -------------------------------------------------------------

    TransferRowContextMenu {
        id: rowMenu
        onRenameRequested: renameDialog.open()
        onSetLocationRequested: setLocationDialog.open()
        onManageContentRequested: Log.warning("ui", "Manage content: no content dialog wired for the transfer row menu yet")
        onEditTrackersRequested: trackersDialog.open()
        onTorrentOptionsRequested: {
            optionsDialog.torrentIds = TransferController.selectedIds;
            optionsDialog.initialValues = ({});
            optionsDialog.open();
        }
        onPreviewRequested: TransferController.preview()
        onExportRequested: exportDialog.open()
        onDeleteRequested: view.requestDelete()
        onNewCategoryRequested: newCategoryDialog.open()
        onAddTagRequested: addTagDialog.open()
        onRemoveAllTagsRequested: {
            if (Preferences.value("Preferences/Advanced/confirmRemoveAllTags", true) === true)
                removeAllTagsDialog.open();
            else
                TransferController.removeAllTags();
        }
    }

    TransferColumnMenu {
        id: columnMenu
        onVisibilityChanged: (role, visible) => {
            var cols = view.columns.slice();
            for (var i = 0; i < cols.length; ++i) {
                if (cols[i].role === role) {
                    cols[i] = Object.assign({}, cols[i], { "visible": visible });
                    break;
                }
            }
            view.columns = cols;   // triggers DataTable rebuild
        }
        onResizeRequested: table.resizeColumns()
    }

    // ---- Dialogs -----------------------------------------------------------

    TextInputDialog {
        id: renameDialog
        title: qsTr("Rename")
        label: qsTr("New name")
        text: view.currentName
        onAccepted: (t) => {
            Log.info("ui", "Rename accepted");
            TransferController.rename(t);
        }
    }

    TextInputDialog {
        id: newCategoryDialog
        title: qsTr("New Category")
        label: qsTr("Category name")
        text: ""
        onAccepted: (name) => {
            Log.info("ui", "New category '" + name + "' assigned to selection");
            TransferController.setCategory(name);
        }
    }

    TextInputDialog {
        id: addTagDialog
        title: qsTr("Add Tags")
        label: qsTr("Comma-separated tags:")
        placeholder: qsTr("tag1, tag2, …")
        text: ""
        onAccepted: (raw) => {
            var parts = ("" + raw).split(",");
            var tags = [];
            for (var i = 0; i < parts.length; ++i) {
                var t = parts[i].trim();
                if (t.length > 0)
                    tags.push(t);
            }
            Log.info("ui", "Adding tags to selection: " + JSON.stringify(tags));
            if (tags.length > 0)
                TransferController.addTags(tags);
        }
    }

    ConfirmDialog {
        id: removeAllTagsDialog
        title: qsTr("Remove all tags")
        text: qsTr("Are you sure you want to remove all tags from the selected torrents?")
        rememberKey: "Preferences/Advanced/confirmRemoveAllTags"
        rememberValue: false
        onAccepted: TransferController.removeAllTags()
    }

    // Edit trackers: delegated to the shared dialog. Applying the edited list
    // needs a bulk-tracker verb the controller does not yet expose.
    TrackerEntriesDialog {
        id: trackersDialog
        onTrackersAccepted: (text) => {
            if (typeof TransferController.setTrackers === "function") {
                Log.info("ui", "Applying edited trackers to selection");
                TransferController.setTrackers(text);
            } else {
                Log.warning("ui", "Edit trackers accepted but TransferController.setTrackers is not available");
            }
        }
    }

    // Per-torrent options: the dialog returns only changed fields; we route them
    // to the corresponding controller verbs.
    TorrentOptionsDialog {
        id: optionsDialog
        onOptionsAccepted: (result) => {
            Log.info("ui", "Torrent options accepted");
            view._applyTorrentOptions(result);
        }
    }

    // Custom deletion dialog (needs the "also delete files" affordance that the
    // generic ConfirmDialog does not carry).
    Dialog {
        id: deleteDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(implicitWidth, (parent ? parent.width : 480) * 0.9)
        padding: Spacing.lg
        Material.elevation: Spacing.elevationDialog
        Material.roundedScale: Material.MediumScale

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
        }

        header: Label {
            text: qsTr("Remove torrent(s)?")
            font: Typography.headlineSmall
            color: Theme.color("onSurface")
            padding: Spacing.lg
            bottomPadding: Spacing.sm
        }

        contentItem: ColumnLayout {
            spacing: Spacing.md
            RowLayout {
                spacing: Spacing.md
                Layout.fillWidth: true
                MDIcon {
                    icon: Icons.warning
                    size: 28
                    color: Theme.color("error")
                    Layout.alignment: Qt.AlignTop
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                    text: TransferController.selectionCount === 1
                          ? qsTr("Are you sure you want to remove '%1' from the transfer list?")
                            .arg(view.currentName)
                          : qsTr("Are you sure you want to remove these %1 torrents from the transfer list?")
                            .arg(TransferController.selectionCount)
                }
            }
            CheckBox {
                id: deleteFilesCheck
                text: qsTr("Also delete the files on disk")
                font: Typography.bodyMedium
            }
        }

        footer: DialogButtonBox {
            padding: Spacing.lg
            topPadding: Spacing.sm
            Button {
                text: qsTr("Cancel")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: deleteDialog.reject()
            }
            Button {
                text: qsTr("Remove")
                highlighted: true
                Material.accent: Theme.color("error")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: deleteDialog.accept()
            }
        }

        onOpened: {
            deleteFilesCheck.checked = false;
            Log.debug("ui", "Delete dialog opened for " + TransferController.selectionCount + " torrent(s)");
        }
        onAccepted: {
            Log.info("ui", "Delete confirmed (deleteFiles=" + deleteFilesCheck.checked + ")");
            TransferController.deleteSelected(deleteFilesCheck.checked);
        }
        onRejected: Log.debug("ui", "Delete cancelled")
    }

    Platform.FolderDialog {
        id: setLocationDialog
        title: qsTr("Choose save path")
        onAccepted: {
            var p = view._localPath(folder);
            Log.info("ui", "Set location -> " + p);
            TransferController.setLocation(p);
        }
    }

    Platform.FolderDialog {
        id: exportDialog
        title: qsTr("Choose export directory")
        onAccepted: {
            var p = view._localPath(folder);
            if (typeof TransferController.exportTorrent === "function") {
                Log.info("ui", "Export .torrent -> " + p);
                TransferController.exportTorrent(p);
            } else {
                Log.warning("ui", "Export .torrent chosen but TransferController.exportTorrent is not available");
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "TransferListView ready")
}
