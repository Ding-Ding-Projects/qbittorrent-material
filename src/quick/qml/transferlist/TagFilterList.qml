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
    \qmltype TagFilterList
    \brief The "Tags" sidebar sub-panel.

    Bound to a \c TagFilterModel instance (row 0 "All", row 1 "Untagged", then one
    row per session tag). Roles: \c label ("Name (count)"), \c value (tag string;
    empty for All/Untagged), \c type (0 = All, 1 = Untagged, 2 = real tag).
    Selecting a row applies the tag criterion to the shared \l proxy: All →
    \c clearTagFilter, Untagged → \c setTagFilter(""), real → \c setTagFilter(value).
*/
Column {
    id: root

    /*! The shared \c TorrentFilterProxyModel. */
    property var proxy: null

    width: parent ? parent.width : implicitWidth
    spacing: 0

    // Local selection state (proxy.tagFilter is ambiguous for All vs. "").
    property string selectedTag: ""
    property int selectedType: 0   // 0 == All (default)

    function _apply(type, value) {
        root.selectedType = type;
        root.selectedTag = value;
        if (!root.proxy)
            return;
        if (type === 0) {
            Log.info("ui", "Tag filter -> All");
            root.proxy.clearTagFilter();
        } else if (type === 1) {
            Log.info("ui", "Tag filter -> Untagged");
            root.proxy.tagFilter = "";
        } else {
            Log.info("ui", "Tag filter -> '" + value + "'");
            root.proxy.tagFilter = value;
        }
    }

    TagFilterModel { id: tagModel }

    TagFilterMenu {
        id: contextMenu
        proxy: root.proxy
        onAddTagRequested: { addTagDialog.open() }
        onRemoveTagRequested: (tag) => {
            if (typeof Session.removeTag === "function") {
                Log.info("ui", "Removing tag '" + tag + "'");
                Session.removeTag(tag);
            } else {
                Log.warning("ui", "Remove tag: Session.removeTag is not available");
            }
        }
        onRemoveUnusedTagsRequested: {
            if (typeof Session.removeUnusedTags === "function") {
                Log.info("ui", "Removing unused tags");
                Session.removeUnusedTags();
            } else {
                Log.warning("ui", "Remove unused tags: Session.removeUnusedTags is not available");
            }
        }
    }

    Repeater {
        model: tagModel
        delegate: ItemDelegate {
            id: rowItem
            required property int index
            required property var model
            readonly property bool selected: (rowItem.model.type === root.selectedType)
                && ((rowItem.model.type !== 2) || (rowItem.model.value === root.selectedTag))
            width: root.width
            height: Spacing.controlHeight
            padding: Spacing.xs
            hoverEnabled: true
            activeFocusOnTab: true

            background: Rectangle {
                color: rowItem.selected ? Theme.color("surfaceWarm")
                                        : (rowPointer.containsMouse ? Theme.color("surfaceWarm") : "transparent")
                radius: Spacing.radiusControl
            }

            contentItem: RowLayout {
                spacing: Spacing.sm
                MDIcon {
                    icon: rowItem.model.type === 0 ? Icons.apps : Icons.sell
                    size: 18
                    color: rowItem.selected ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                    Layout.leftMargin: Spacing.sm
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: rowItem.model.label
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    font: Typography.bodyMedium
                    color: rowItem.selected ? Theme.color("primary") : Theme.color("onSurface")
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            onClicked: root._apply(rowItem.model.type, rowItem.model.value)

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root._apply(rowItem.model.type, rowItem.model.value);
                    } else {
                        contextMenu.tag = (rowItem.model.type === 2) ? rowItem.model.value : "";
                        contextMenu.isReal = (rowItem.model.type === 2);
                        Log.debug("ui", "Tag filter context menu for '" + contextMenu.tag + "'");
                        contextMenu.popup();
                    }
                }
            }
        }
    }

    // Shared tag creator (persists via Session).
    AddTagDialog {
        id: addTagDialog
        onTagCreated: (tag) => {
            if (typeof Session.addTag === "function") {
                Log.info("ui", "Creating tag '" + tag + "'");
                Session.addTag(tag);
            } else {
                Log.warning("ui", "Create tag but Session.addTag is not available");
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "TagFilterList ready")
}
