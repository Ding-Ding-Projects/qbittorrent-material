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
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import qBittorrent

/*!
    \qmltype CategoryFilterTree
    \brief The "Categories" sidebar sub-panel.

    A \c TreeView bound to a \c CategoryFilterModel instance (a category tree
    whose row 0 is "All", row 1 "Uncategorized", and deeper rows the nested
    `/`-separated categories). Roles: \c label (already "Name (count)"),
    \c value (full category path), \c type (0 = All, 1 = Uncategorized,
    2 = real category), \c count.

    Selecting a node applies the matching category criterion to the shared
    \l proxy: All → \c clearCategoryFilter, Uncategorized → \c setCategoryFilter("")
    real → \c setCategoryFilter(value). Because the proxy cannot distinguish
    "cleared" from "empty", the highlighted row is tracked locally.
*/
Column {
    id: root

    /*! The shared \c TorrentFilterProxyModel. */
    property var proxy: null

    width: parent ? parent.width : implicitWidth
    spacing: 0

    // Local selection state (proxy.categoryFilter is ambiguous for All vs. "").
    property string selectedValue: ""
    property int selectedType: 0   // 0 == All (default)

    property string _pendingParent: ""
    property string _editTarget: ""
    property string _editMode: "add"

    function _apply(type, value) {
        root.selectedType = type;
        root.selectedValue = value;
        if (!root.proxy)
            return;
        if (type === 0) {
            Log.info("ui", "Category filter -> All");
            root.proxy.clearCategoryFilter();
        } else if (type === 1) {
            Log.info("ui", "Category filter -> Uncategorized");
            root.proxy.categoryFilter = "";
        } else {
            Log.info("ui", "Category filter -> '" + value + "'");
            root.proxy.categoryFilter = value;
        }
    }

    CategoryFilterModel { id: categoryModel }

    CategoryFilterMenu {
        id: contextMenu
        proxy: root.proxy
        onAddCategoryRequested: {
            root._editMode = "add"; root._pendingParent = ""; root._editTarget = "";
            categoryDialog.mode = "add"; categoryDialog.parentCategory = "";
            categoryDialog.categoryName = ""; categoryDialog.open();
        }
        onAddSubcategoryRequested: (parentCategory) => {
            root._editMode = "add"; root._pendingParent = parentCategory;
            categoryDialog.mode = "add"; categoryDialog.parentCategory = parentCategory;
            categoryDialog.categoryName = ""; categoryDialog.open();
        }
        onEditCategoryRequested: (category) => {
            root._editMode = "edit"; root._editTarget = category;
            categoryDialog.mode = "edit"; categoryDialog.categoryName = category;
            categoryDialog.parentCategory = ""; categoryDialog.open();
        }
        onRemoveCategoryRequested: (category) => {
            if (typeof Session.removeCategory === "function") {
                Log.info("ui", "Removing category '" + category + "'");
                Session.removeCategory(category);
            } else {
                Log.warning("ui", "Remove category: Session.removeCategory is not available");
            }
        }
    }

    TreeView {
        id: tree
        width: root.width
        height: contentHeight
        interactive: false
        clip: true
        model: categoryModel

        delegate: TreeViewDelegate {
            id: del
            required property int type
            required property string value
            required property string label
            implicitWidth: root.width
            implicitHeight: Spacing.controlHeight
            indentation: Spacing.md
            hoverEnabled: true
            activeFocusOnTab: true

            readonly property bool filterActive: (del.type === root.selectedType)
                && ((del.type !== 2) || (del.value === root.selectedValue))

            background: Rectangle {
                color: del.filterActive ? Theme.color("surfaceWarm")
                                    : (rowPointer.containsMouse ? Theme.color("surfaceWarm") : "transparent")
                radius: Spacing.radiusControl
            }

            contentItem: RowLayout {
                spacing: Spacing.sm
                MDIcon {
                    icon: del.type === 0 ? Icons.apps : Icons.category
                    size: 18
                    color: del.filterActive ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: del.label
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    font: Typography.bodyMedium
                    color: del.filterActive ? Theme.color("primary") : Theme.color("onSurface")
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            onClicked: root._apply(del.type, del.value)

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root._apply(del.type, del.value);
                    } else {
                        contextMenu.category = (del.type === 2) ? del.value : "";
                        contextMenu.isReal = (del.type === 2);
                        Log.debug("ui", "Category filter context menu for '" + contextMenu.category + "'");
                        contextMenu.popup();
                    }
                }
            }
        }
    }

    // Shared category editor (owns add / edit; persists via Session).
    CategoryDialog {
        id: categoryDialog
        onCategoryAccepted: (name, options) => {
            const full = (root._editMode === "add" && root._pendingParent.length > 0)
                    ? (root._pendingParent + "/" + name) : name;
            if (typeof Session.addCategory === "function") {
                Log.info("ui", "Category '" + full + "' saved");
                Session.addCategory(full);
                if (typeof Session.setCategoryOptions === "function")
                    Session.setCategoryOptions(full, options);
            } else {
                Log.warning("ui", "Category saved but Session.addCategory is not available");
            }
        }
    }

    Component.onCompleted: Log.debug("ui", "CategoryFilterTree ready")
}
