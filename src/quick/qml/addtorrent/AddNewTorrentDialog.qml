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
    \qmltype AddNewTorrentDialog
    \brief The Material "Add New Torrent" dialog.

    Backed entirely by \c AddTorrentController (C++). It opens automatically when
    \c AddTorrentController.dialogRequested fires, binds every field to the
    controller's resolved \c initialValues, renders the content tree from
    \c AddTorrentController.contentModel, and on accept hands a plain value map
    back to \c AddTorrentController.accept(). It also owns the global tracker-
    merge confirmation requested by \c GuiAddTorrentManager.
*/
Dialog {
    id: root

    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    padding: Spacing.lg
    Material.elevation: 24
    Material.roundedScale: Material.LargeScale

    // Responsive: cap to the parent window and let the body scroll.
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    width: Math.min(880, (parent ? parent.width : 880) * 0.92)
    height: Math.min(760, (parent ? parent.height : 760) * 0.92)

    title: AddTorrentController.torrentName

    // ---- Local field state (populated from the controller on open) ---------
    property bool _loading: false
    readonly property bool _manualMode: tmmCombo.currentIndex === 0
    readonly property bool _hasMetadata: AddTorrentController.hasMetadata

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !mergeTrackersDialog.visible
        onActivated: root.reject()
        onActivatedAmbiguously: root.reject()
    }

    // ---- Open / load lifecycle ---------------------------------------------

    Connections {
        target: AddTorrentController
        function onDialogRequested() {
            root.loadFromController()
            root.open()
        }
        function onContextChanged() {
            // Keep the size label fresh when metadata arrives.
            if (root.visible)
                AddTorrentController.updateSizeText(savePathField.path)
        }
    }

    // This component exists for the lifetime of the application shell, even
    // while the add dialog itself is hidden, so it can safely own the global
    // merge-trackers confirmation.
    Connections {
        target: GuiAddTorrentManager
        function onTorrentAdded(source) {
            NotificationCenter.notify(qsTr("Torrent added"), "success", "")
        }
        function onAddTorrentFailed(source, reason) {
            NotificationCenter.notify(qsTr("Could not add torrent"), "error", reason)
        }
        function onDuplicateTorrent(source, name) {
            NotificationCenter.notify(qsTr("Torrent already exists"), "warning", name)
        }
        function onMergeTrackersRequested(source, name, isPrivate) {
            if (isPrivate) {
                // Defensive only: the manager never requests a merge for a
                // private torrent.
                GuiAddTorrentManager.respondMergeTrackers(source, false)
                return
            }

            mergeTrackersDialog.torrentSource = source
            mergeTrackersDialog.torrentName = name
            mergeTrackersDialog.open()
        }
    }

    ConfirmDialog {
        id: mergeTrackersDialog
        property string torrentSource: ""
        property string torrentName: ""

        closePolicy: Popup.NoAutoClose
        title: qsTr("Merge trackers?")
        text: qsTr("The torrent \"%1\" already exists. Merge trackers and web seeds from the new source?").arg(torrentName)
        acceptText: qsTr("Merge")

        onAccepted: {
            const source = torrentSource
            torrentSource = ""
            GuiAddTorrentManager.respondMergeTrackers(source, true)
        }
        onRejected: {
            const source = torrentSource
            torrentSource = ""
            GuiAddTorrentManager.respondMergeTrackers(source, false)
        }

        Shortcut {
            sequence: "Escape"
            enabled: mergeTrackersDialog.visible
            onActivated: mergeTrackersDialog.reject()
            onActivatedAmbiguously: mergeTrackersDialog.reject()
        }
    }

    function loadFromController() {
        _loading = true
        Log.debug("ui", "AddNewTorrentDialog: loading fields from controller")

        var v = AddTorrentController.initialValues

        tmmCombo.currentIndex = (v.useAutoTMM === true) ? 1 : 0
        renameField.text = ""
        savePathField.path = v.savePath !== undefined ? v.savePath : ""
        savePathField.model = AddTorrentController.savePathHistory
        useDownloadPathCheck.checked = v.useDownloadPath === true
        downloadPathField.path = v.downloadPath !== undefined ? v.downloadPath : ""
        downloadPathField.model = AddTorrentController.downloadPathHistory
        rememberPathCheck.checked = v.rememberSavePath === true

        categoryCombo.model = AddTorrentController.categories
        categoryCombo.editText = v.category !== undefined ? v.category : ""
        defaultCategoryCheck.checked = false
        tagsField.text = (v.tags && v.tags.length) ? v.tags.join(", ") : ""

        startCheck.checked = v.startTorrent === true
        stopConditionCombo.selectValue(v.stopCondition !== undefined ? v.stopCondition : 0)
        addToTopCheck.checked = v.addToQueueTop === true
        skipCheck.checked = v.skipChecking === true
        sequentialCheck.checked = v.sequential === true
        firstLastCheck.checked = v.firstLastPiece === true
        contentLayoutCombo.currentIndex = v.contentLayout !== undefined ? v.contentLayout : 0

        neverShowCheck.checked = false
        doNotDeleteCheck.checked = false

        _loading = false
        AddTorrentController.updateSizeText(savePathField.path)
    }

    function _buildValues() {
        return {
            "useAutoTMM": tmmCombo.currentIndex === 1,
            "name": renameField.text,
            "savePath": savePathField.path,
            "useDownloadPath": useDownloadPathCheck.checked,
            "downloadPath": downloadPathField.path,
            "category": categoryCombo.editText,
            "setDefaultCategory": defaultCategoryCheck.checked,
            "tags": tagsField.text.length
                    ? tagsField.text.split(",").map(function(t) { return t.trim() })
                                    .filter(function(t) { return t.length > 0 })
                    : [],
            "startTorrent": startCheck.checked,
            "stopCondition": stopConditionCombo.currentValue,
            "addToQueueTop": addToTopCheck.checked,
            "skipChecking": skipCheck.checked,
            "sequential": sequentialCheck.checked,
            "firstLastPiece": firstLastCheck.checked,
            "contentLayout": contentLayoutCombo.currentIndex,
            "rememberSavePath": rememberPathCheck.checked,
            "neverShowAgain": neverShowCheck.checked,
            "doNotDelete": doNotDeleteCheck.checked
        }
    }

    // Update the AutoTMM category-driven paths.
    function _applyCategoryPaths() {
        if (_manualMode)
            return
        var paths = AddTorrentController.categoryPaths(categoryCombo.editText)
        savePathField.path = paths.savePath !== undefined ? paths.savePath : ""
        downloadPathField.path = paths.downloadPath !== undefined ? paths.downloadPath : ""
        useDownloadPathCheck.checked = paths.useDownloadPath === true
        AddTorrentController.updateSizeText(savePathField.path)
    }

    onAccepted: {
        Log.info("ui", "AddNewTorrentDialog accepted")
        AddTorrentController.accept(_buildValues())
    }
    onRejected: {
        Log.info("ui", "AddNewTorrentDialog rejected")
        AddTorrentController.reject()
    }

    // ---- Content -----------------------------------------------------------

    contentItem: Flickable {
        id: bodyFlick
        clip: true
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: bodyColumn
            width: bodyFlick.width
            spacing: Spacing.md

            // ---- Torrent info header ---------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Information")

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Spacing.lg
                    rowSpacing: Spacing.xs

                    Label {
                        text: qsTr("Size:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: AddTorrentController.sizeText
                        font: Typography.bodyMedium
                        color: Theme.color("onSurface")
                        elide: Text.ElideRight
                    }

                    Label {
                        text: qsTr("Comment:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: AddTorrentController.comment
                        font: Typography.bodyMedium
                        color: Theme.color("onSurface")
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        text: qsTr("Date:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: AddTorrentController.creationDate
                        font: Typography.bodyMedium
                        color: Theme.color("onSurface")
                    }

                    Label {
                        text: qsTr("Info hash v1:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: AddTorrentController.infoHashV1
                        font: Typography.mono
                        color: Theme.color("onSurface")
                        elide: Text.ElideRight
                    }

                    Label {
                        text: qsTr("Info hash v2:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: AddTorrentController.infoHashV2
                        font: Typography.mono
                        color: Theme.color("onSurface")
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- Metadata progress (magnet links) --------------------------
            RowLayout {
                Layout.fillWidth: true
                visible: AddTorrentController.metadataStatusText.length > 0
                spacing: Spacing.sm

                BusyIndicator {
                    running: AddTorrentController.metadataInProgress
                    visible: AddTorrentController.metadataInProgress
                    implicitWidth: 20
                    implicitHeight: 20
                }
                Label {
                    Layout.fillWidth: true
                    text: AddTorrentController.metadataStatusText
                    font: Typography.labelSmall
                    color: Theme.color("onSurfaceVariant")
                }
            }

            // ---- Torrent management mode -----------------------------------
            LabeledField {
                Layout.fillWidth: true
                labelWidth: 200
                label: qsTr("Torrent Management Mode:")
                ComboBox {
                    id: tmmCombo
                    Layout.fillWidth: true
                    model: [ qsTr("Manual"), qsTr("Automatic") ]
                    onActivated: {
                        if (root._loading)
                            return
                        Log.debug("ui", "AddNewTorrentDialog: TMM -> " + currentText)
                        root._applyCategoryPaths()
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Automatic mode decides the save path from the associated category")
                }
            }

            // ---- Save paths ------------------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                title: qsTr("Save at")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    PathComboField {
                        id: savePathField
                        Layout.fillWidth: true
                        enabled: root._manualMode
                        placeholder: qsTr("Default save path")
                        title: qsTr("Choose save path")
                        onPathChanged: {
                            if (!root._loading)
                                AddTorrentController.updateSizeText(path)
                        }
                    }

                    CheckBox {
                        id: useDownloadPathCheck
                        text: qsTr("Use another path for incomplete torrents")
                        font: Typography.bodyMedium
                        enabled: root._manualMode
                        onToggled: Log.debug("ui", "AddNewTorrentDialog: useDownloadPath=" + checked)
                    }

                    PathComboField {
                        id: downloadPathField
                        Layout.fillWidth: true
                        enabled: root._manualMode && useDownloadPathCheck.checked
                        placeholder: qsTr("Incomplete-torrent path")
                        title: qsTr("Choose incomplete path")
                    }

                    CheckBox {
                        id: rememberPathCheck
                        text: qsTr("Remember last used save path")
                        font: Typography.bodyMedium
                        enabled: root._manualMode
                    }
                }
            }

            // ---- Rename / category / tags ----------------------------------
            LabeledField {
                Layout.fillWidth: true
                labelWidth: 200
                label: qsTr("Rename torrent:")
                TextField {
                    id: renameField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Leave empty to keep the original name")
                    selectByMouse: true
                }
            }

            LabeledField {
                Layout.fillWidth: true
                labelWidth: 200
                label: qsTr("Category:")
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm
                    ComboBox {
                        id: categoryCombo
                        Layout.fillWidth: true
                        editable: true
                        onActivated: {
                            if (!root._loading)
                                root._applyCategoryPaths()
                        }
                    }
                    CheckBox {
                        id: defaultCategoryCheck
                        text: qsTr("Default")
                        font: Typography.bodyMedium
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Remember this category as the default for new torrents")
                    }
                }
            }

            LabeledField {
                Layout.fillWidth: true
                labelWidth: 200
                label: qsTr("Tags:")
                TextField {
                    id: tagsField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Comma-separated tags")
                    selectByMouse: true
                }
            }

            // ---- Options grid ----------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Spacing.lg
                rowSpacing: Spacing.sm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    spacing: Spacing.sm

                    CheckBox {
                        id: startCheck
                        text: qsTr("Start torrent")
                        font: Typography.bodyMedium
                        onToggled: Log.debug("ui", "AddNewTorrentDialog: start=" + checked)
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: qsTr("Stop condition:")
                        font: Typography.bodyMedium
                        color: Theme.color("onSurfaceVariant")
                        enabled: startCheck.checked
                    }
                    ComboBox {
                        id: stopConditionCombo
                        Layout.preferredWidth: 200
                        enabled: startCheck.checked
                        textRole: "text"
                        valueRole: "value"
                        model: ListModel {
                            Component.onCompleted: {
                                append({ "text": qsTr("None"), "value": 0 })
                                if (!root._hasMetadata)
                                    append({ "text": qsTr("Metadata received"), "value": 1 })
                                append({ "text": qsTr("Files checked"), "value": 2 })
                            }
                        }
                        function selectValue(val) {
                            for (var i = 0; i < count; ++i) {
                                if (model.get(i).value === val) {
                                    currentIndex = i
                                    return
                                }
                            }
                            currentIndex = 0
                        }
                    }
                }

                CheckBox {
                    id: addToTopCheck
                    text: qsTr("Add to top of queue")
                    font: Typography.bodyMedium
                }
                CheckBox {
                    id: skipCheck
                    text: qsTr("Skip hash check")
                    font: Typography.bodyMedium
                }
                CheckBox {
                    id: sequentialCheck
                    text: qsTr("Download in sequential order")
                    font: Typography.bodyMedium
                }
                CheckBox {
                    id: firstLastCheck
                    text: qsTr("Download first and last pieces first")
                    font: Typography.bodyMedium
                }

                LabeledField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    labelWidth: 200
                    label: qsTr("Content layout:")
                    ComboBox {
                        id: contentLayoutCombo
                        Layout.fillWidth: true
                        model: [
                            qsTr("Original"),
                            qsTr("Create subfolder"),
                            qsTr("Don't create subfolder")
                        ]
                        onActivated: {
                            if (root._loading)
                                return
                            Log.debug("ui", "AddNewTorrentDialog: content layout -> " + currentText)
                            AddTorrentController.applyContentLayout(currentIndex)
                        }
                    }
                }
            }

            // ---- Content tree ----------------------------------------------
            MaterialCard {
                Layout.fillWidth: true
                visible: root._hasMetadata
                title: qsTr("Content")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.sm

                        Button {
                            text: qsTr("Select All")
                            flat: true
                            onClicked: {
                                Log.debug("ui", "AddNewTorrentDialog: select all files")
                                AddTorrentController.contentModel.checkAll()
                            }
                        }
                        Button {
                            text: qsTr("Select None")
                            flat: true
                            onClicked: {
                                Log.debug("ui", "AddNewTorrentDialog: select no files")
                                AddTorrentController.contentModel.checkNone()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        FilterTextField {
                            id: contentFilter
                            Layout.preferredWidth: 220
                            placeholder: qsTr("Filter files...")
                            onTextChanged: Log.debug("ui", "AddNewTorrentDialog: file filter '" + text + "'")
                        }
                    }

                    DataTable {
                        id: contentTable
                        Layout.fillWidth: true
                        Layout.preferredHeight: 240
                        persistKey: "AddTorrentContent"
                        alternatingRows: true
                        model: AddTorrentController.contentModel
                        columns: [
                            { role: "wanted",   title: qsTr("Download"), width: 90,  align: Qt.AlignHCenter, resizable: false },
                            { role: "fileName", title: qsTr("Name"),     width: 320, align: Qt.AlignLeft },
                            { role: "sizeText", title: qsTr("Size"),     width: 110, align: Qt.AlignRight },
                            { role: "priority", title: qsTr("Priority"), width: 130, align: Qt.AlignLeft, resizable: false }
                        ]
                        delegateFor: function(col) {
                            if (col.role === "wanted")
                                return wantedCell
                            if (col.role === "priority")
                                return priorityCell
                            return null
                        }
                    }
                }
            }

            // ---- Save / never-show / do-not-delete -------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Spacing.sm

                Button {
                    text: qsTr("Save as .torrent file...")
                    flat: true
                    visible: AddTorrentController.canSaveTorrentFile
                    onClicked: {
                        Log.debug("ui", "AddNewTorrentDialog: export .torrent")
                        saveTorrentDialog.open()
                    }
                }

                Item { Layout.fillWidth: true }

                CheckBox {
                    id: doNotDeleteCheck
                    text: qsTr("Don't delete source .torrent file")
                    font: Typography.bodyMedium
                    visible: AddTorrentController.doNotDeleteVisible
                }
            }

            CheckBox {
                id: neverShowCheck
                Layout.fillWidth: true
                text: qsTr("Do not ask me again")
                font: Typography.bodyMedium
            }
        }
    }

    // ---- Footer buttons ----------------------------------------------------
    footer: DialogButtonBox {
        Button {
            text: qsTr("Add")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }

    // ---- Cell delegates for the content tree -------------------------------
    Component {
        id: wantedCell
        Item {
            id: wantedRoot
            // Snapshot the Loader-provided cell context (see DataTable contract).
            property var cellValue: parent ? parent.value : false
            property int rowIndex: parent ? parent.cellRow : -1
            CheckBox {
                anchors.centerIn: parent
                checked: wantedRoot.cellValue === true
                onToggled: AddTorrentController.contentModel.setWanted(wantedRoot.rowIndex, checked)
            }
        }
    }

    Component {
        id: priorityCell
        Item {
            id: priorityRoot
            property var cellValue: parent ? parent.value : 1
            property int rowIndex: parent ? parent.cellRow : -1
            ComboBox {
                anchors.fill: parent
                anchors.margins: 2
                font: Typography.bodyMedium
                textRole: "text"
                valueRole: "value"
                model: ListModel {
                    Component.onCompleted: {
                        append({ "text": qsTr("Do not download"), "value": 0 })
                        append({ "text": qsTr("Normal"), "value": 1 })
                        append({ "text": qsTr("High"), "value": 6 })
                        append({ "text": qsTr("Maximum"), "value": 7 })
                    }
                }
                Component.onCompleted: {
                    for (var i = 0; i < count; ++i) {
                        if (model.get(i).value === priorityRoot.cellValue) {
                            currentIndex = i
                            break
                        }
                    }
                }
                onActivated: AddTorrentController.contentModel.setPriority(priorityRoot.rowIndex, currentValue)
            }
        }
    }

    // ---- Auxiliary dialogs -------------------------------------------------
    Platform.FileDialog {
        id: saveTorrentDialog
        title: qsTr("Save as torrent file")
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: [ qsTr("Torrent files (*.torrent)") ]
        defaultSuffix: "torrent"
        onAccepted: {
            var path = decodeURIComponent(("" + file).replace(/^file:\/\/\//, ""))
            if (AddTorrentController.saveTorrentFile(path))
                NotificationCenter.notify(qsTr("Torrent file exported."), "success")
            else
                NotificationCenter.notify(qsTr("Could not export the torrent file."), "error")
        }
    }
}
