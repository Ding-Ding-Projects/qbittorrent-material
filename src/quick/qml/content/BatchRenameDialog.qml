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
    \qmltype BatchRenameDialog
    \brief Regex-driven bulk file rename for the torrent content tree.

    Reads the flat file list from \l sourceModel (a \c TorrentContentModel via
    \c fileEntries()), applies a find/replace — plain substring or regular
    expression, optionally case-sensitive — to each file's relative path, shows a
    live before/after preview, and on accept commits the changes through
    \c sourceModel.renameFileByIndex(index, newPath).

    \qml
    BatchRenameDialog { sourceModel: contentSource; onApplied: (n) => NotificationCenter.notify(qsTr("Renamed %1 file(s)").arg(n), "success") }
    \endqml
*/
Popup {
    id: root

    /*! The \c TorrentContentModel providing \c fileEntries() / \c renameFileByIndex(). */
    property var sourceModel: null

    /*! Optional file indexes selected by the caller; empty means every file. */
    property var selectedFileIndexes: []

    /*! Emitted after the user confirms; \c count is the number of files renamed. */
    signal applied(int count)

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Spacing.lg

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(680, (parent ? parent.width : 680) * 0.9)
    height: Math.min(560, (parent ? parent.height : 560) * 0.9)

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    // ---- State --------------------------------------------------------------
    property var _entries: []
    property bool _regexValid: true
    property string _validationError: ""
    property int _changedCount: 0
    property string _originalCommonPath: ""

    ListModel { id: previewModel }

    onOpened: {
        Log.debug("ui", "BatchRenameDialog opened")
        const allEntries = (sourceModel && sourceModel.fileEntries) ? sourceModel.fileEntries() : [];
        const selected = {};
        for (let i = 0; i < selectedFileIndexes.length; ++i)
            selected["" + selectedFileIndexes[i]] = true;
        _entries = selectedFileIndexes.length > 0
                ? allEntries.filter((entry) => selected["" + entry.index] === true)
                : allEntries;
        _originalCommonPath = _commonPath(_entries);
        commonPathField.text = _originalCommonPath;
        _updatePreview();
        commonPathField.forceActiveFocus();
    }

    function _normalizePath(path) {
        return ("" + path).replace(/\\/g, "/").replace(/^\.\//, "").replace(/\/{2,}/g, "/")
    }

    function _commonPath(entries) {
        if (entries.length === 0)
            return ""
        let common = _normalizePath(entries[0].path).split("/")
        for (let i = 1; i < entries.length && common.length > 0; ++i) {
            const parts = _normalizePath(entries[i].path).split("/")
            let count = 0
            while (count < common.length && count < parts.length
                   && common[count].toLocaleLowerCase() === parts[count].toLocaleLowerCase())
                ++count
            common = common.slice(0, count)
        }
        return common.join("/")
    }

    function _validRelativePath(path) {
        const normalized = _normalizePath(path)
        if (normalized.length === 0 || normalized.startsWith("/")
                || /^[A-Za-z]:\//.test(normalized))
            return false
        const parts = normalized.split("/")
        return parts.indexOf("") < 0 && parts.indexOf(".") < 0 && parts.indexOf("..") < 0
    }

    function _makeRegex() {
        if (findField.text.length === 0)
            return null;
        const flags = "g" + (caseSensitiveSwitch.checked ? "" : "i");
        const pattern = useRegexSwitch.checked
            ? findField.text
            : findField.text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        try {
            return new RegExp(pattern, flags);
        } catch (e) {
            return undefined; // signals an invalid pattern
        }
    }

    function _updatePreview() {
        previewModel.clear();
        _changedCount = 0;
        _validationError = "";

        const re = _makeRegex();
        _regexValid = (re !== undefined);
        if (!_regexValid)
            return;

        const replacementCommon = _normalizePath(commonPathField.text.trim())
        if (!_validRelativePath(replacementCommon)) {
            _validationError = qsTr("Enter a valid relative common path without '..'.")
            return
        }

        const occupied = {}
        const allEntries = sourceModel ? sourceModel.fileEntries() : []
        for (let j = 0; j < allEntries.length; ++j)
            occupied[_normalizePath(allEntries[j].path).toLocaleLowerCase()] = allEntries[j].index
        for (let j = 0; j < _entries.length; ++j)
            delete occupied[_normalizePath(_entries[j].path).toLocaleLowerCase()]

        for (let i = 0; i < _entries.length; ++i) {
            const entry = _entries[i];
            const oldPath = "" + entry.path;
            const normalizedOld = _normalizePath(oldPath)
            const suffix = _originalCommonPath.length > 0
                    ? normalizedOld.substring(_originalCommonPath.length).replace(/^\//, "")
                    : normalizedOld
            let newPath = suffix.length > 0 ? replacementCommon + "/" + suffix : replacementCommon
            if (re !== null)
                newPath = newPath.replace(re, replaceField.text)
            newPath = _normalizePath(newPath)
            if (!_validRelativePath(newPath)) {
                _validationError = qsTr("A resulting path is invalid or leaves the torrent root.")
                previewModel.clear()
                _changedCount = 0
                return
            }
            const key = newPath.toLocaleLowerCase()
            if (occupied[key] !== undefined && occupied[key] !== entry.index) {
                _validationError = qsTr("Two files would have the same destination path.")
                previewModel.clear()
                _changedCount = 0
                return
            }
            occupied[key] = entry.index
            if (newPath !== normalizedOld) {
                previewModel.append({ "fileIndex": entry.index, "oldPath": oldPath, "newPath": newPath });
                ++_changedCount;
            }
        }
    }

    function _apply() {
        if (!_regexValid || (_changedCount === 0) || !sourceModel)
            return;

        Log.info("ui", "BatchRenameDialog: applying " + _changedCount + " rename(s)");
        let done = 0;
        for (let i = 0; i < previewModel.count; ++i) {
            const item = previewModel.get(i);
            if (sourceModel.renameFileByIndex(item.fileIndex, item.newPath))
                ++done;
        }
        root.applied(done);
        root.close();
    }

    contentItem: ColumnLayout {
        spacing: Spacing.md

        Label {
            text: qsTr("Batch rename")
            font: Typography.headlineSmall
            color: Theme.color("onSurface")
            Layout.fillWidth: true
        }

        Label {
            text: qsTr("Edit the shared path of the selected files, with optional find and replace.")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("Common path:")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
            }
            TextField {
                id: commonPathField
                Layout.fillWidth: true
                selectByMouse: true
                Accessible.name: qsTr("Common path")
                onTextChanged: root._updatePreview()
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: Spacing.md
            rowSpacing: Spacing.sm
            Layout.fillWidth: true

            Label {
                text: qsTr("Find:")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
            }
            TextField {
                id: findField
                Layout.fillWidth: true
                placeholderText: qsTr("Text or pattern to match")
                selectByMouse: true
                onTextChanged: root._updatePreview()
            }

            Label {
                text: qsTr("Replace with:")
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
            }
            TextField {
                id: replaceField
                Layout.fillWidth: true
                placeholderText: qsTr("Replacement text")
                selectByMouse: true
                onTextChanged: root._updatePreview()
            }
        }

        RowLayout {
            spacing: Spacing.lg
            Layout.fillWidth: true

            Switch {
                id: useRegexSwitch
                text: qsTr("Use regular expression")
                onToggled: {
                    Log.debug("ui", "BatchRenameDialog: regex " + checked)
                    root._updatePreview()
                }
            }
            Switch {
                id: caseSensitiveSwitch
                text: qsTr("Case sensitive")
                onToggled: {
                    Log.debug("ui", "BatchRenameDialog: caseSensitive " + checked)
                    root._updatePreview()
                }
            }
            Item { Layout.fillWidth: true }
        }

        Label {
            visible: !root._regexValid
            text: qsTr("Invalid regular expression.")
            font: Typography.labelLarge
            color: StateColors.error
            Layout.fillWidth: true
        }

        Label {
            visible: root._validationError.length > 0
            text: root._validationError
            font: Typography.labelLarge
            color: StateColors.error
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Label {
            text: root._changedCount > 0
                  ? qsTr("%1 of %2 file(s) will be renamed:").arg(root._changedCount).arg(root._entries.length)
                  : qsTr("No files match — nothing to rename.")
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            Layout.fillWidth: true
        }

        // Before/after preview.
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 0

            background: Rectangle {
                radius: Spacing.radiusField
                color: Theme.color("surfaceVariant")
                border.color: Theme.color("outlineVariant")
                border.width: 1
            }

            ListView {
                id: previewList
                anchors.fill: parent
                anchors.margins: Spacing.xs
                clip: true
                model: previewModel
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Column {
                    width: previewList.width
                    spacing: 0
                    padding: Spacing.xs

                    required property string oldPath
                    required property string newPath

                    Label {
                        width: parent.width - (Spacing.xs * 2)
                        text: parent.oldPath
                        font: Typography.labelSmall
                        color: Theme.color("onSurfaceVariant")
                        elide: Text.ElideMiddle
                    }
                    Label {
                        width: parent.width - (Spacing.xs * 2)
                        text: "→ " + parent.newPath
                        font: Typography.bodyMedium
                        color: Theme.color("primary")
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        DialogButtonBox {
            Layout.fillWidth: true
            spacing: Spacing.sm
            padding: 0
            topPadding: Spacing.sm
            background: null

            Button {
                text: qsTr("Cancel")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: {
                    Log.debug("ui", "BatchRenameDialog cancelled")
                    root.close()
                }
            }

            Button {
                text: qsTr("Rename")
                highlighted: true
                enabled: root._regexValid && root._validationError.length === 0 && (root._changedCount > 0)
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: root._apply()
            }
        }
    }
}
