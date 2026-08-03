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
    \qmltype SearchResultsTab
    \brief One results page: a live filter row over a \l DataTable of results.

    Bound to a single \c SearchResultsProxyModel (\l proxyModel) owned by the
    \c SearchController for tab \l tabId. Every filter control feeds the proxy
    live; downloaded ("visited") rows are muted.
*/
Item {
    id: root

    /*! The owning SearchController tab id. */
    property int tabId: -1

    /*! The per-tab sort/filter proxy model to display. */
    property var proxyModel: null

    // Size-unit multipliers (1024^index): B, KiB, MiB, GiB, TiB, PiB, EiB.
    readonly property var _unitMultipliers: [
        1, 1024, 1048576, 1073741824, 1099511627776, 1125899906842624, 1152921504606846976
    ]
    readonly property var _unitLabels: [
        qsTr("B"), qsTr("KiB"), qsTr("MiB"), qsTr("GiB"), qsTr("TiB"), qsTr("PiB"), qsTr("EiB")
    ]

    function _num(text) {
        var v = parseFloat(text)
        return isNaN(v) ? 0 : v
    }

    function _applySeedsFilter() {
        var minV = minSeeds.value
        var maxV = maxSeeds.value === 0 ? -1 : maxSeeds.value
        proxyModel.setSeedsFilter(minV, maxV)
    }

    function _applySizeFilter() {
        var minBytes = _num(minSize.text) * root._unitMultipliers[minSizeUnit.currentIndex]
        var maxRaw = _num(maxSize.text)
        var maxBytes = maxRaw <= 0 ? -1 : (maxRaw * root._unitMultipliers[maxSizeUnit.currentIndex])
        proxyModel.setSizeFilter(Math.round(minBytes), maxBytes < 0 ? -1 : Math.round(maxBytes))
    }

    Component.onCompleted: {
        Log.debug("search", "SearchResultsTab ready for tab " + tabId)
        if (proxyModel)
            filterMode.currentIndex = proxyModel.nameFilteringMode === SearchController.Everywhere ? 1 : 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Spacing.sm
        spacing: Spacing.sm

        // ---- Filter row ---------------------------------------------------
        Flow {
            Layout.fillWidth: true
            spacing: Spacing.md

            FilterTextField {
                id: resultsFilter
                width: 260
                placeholder: qsTr("Filter search results…")
                regexEnabled: root.proxyModel ? root.proxyModel.regexEnabled : false
                regexFlags: root.proxyModel ? root.proxyModel.regexFlags : "iu"
                onTextChanged: if (root.proxyModel) root.proxyModel.setResultsFilter(text)
                onRegexEnabledChanged: {
                    if (root.proxyModel) root.proxyModel.setRegexEnabled(regexEnabled)
                    SearchController.setResultsFilterUsesRegex(regexEnabled)
                }
                onRegexFlagsChanged: {
                    if (root.proxyModel) root.proxyModel.setRegexFlags(regexFlags)
                    SearchController.setResultsFilterRegexFlags(regexFlags)
                }
            }

            Label {
                height: 40
                verticalAlignment: Text.AlignVCenter
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                text: root.proxyModel
                      ? qsTr("Results (showing %1 out of %2):")
                          .arg(root.proxyModel.visibleCount).arg(root.proxyModel.totalCount)
                      : ""
            }

            Row {
                spacing: Spacing.xs
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search in:")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                ComboBox {
                    id: filterMode
                    width: 170
                    model: [ qsTr("Torrent names only"), qsTr("Everywhere") ]
                    onActivated: {
                        var mode = currentIndex === 1 ? SearchController.Everywhere : SearchController.OnlyNames
                        Log.debug("search", "Search-in mode -> " + mode)
                        SearchController.setNameFilteringMode(mode)
                        if (root.proxyModel) root.proxyModel.setNameFilteringMode(mode)
                    }
                }
            }

            Row {
                spacing: Spacing.xs
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Seeds:")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                SpinBox {
                    id: minSeeds
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 1000; value: 0
                    ToolTip.text: qsTr("Minimum number of seeds")
                    onValueModified: root._applySeedsFilter()
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("to")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                SpinBox {
                    id: maxSeeds
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 1000; value: 0
                    ToolTip.text: qsTr("Maximum number of seeds (0 = ∞)")
                    textFromValue: function(value, locale) {
                        return value === 0 ? qsTr("∞") : Number(value).toLocaleString(locale, 'f', 0)
                    }
                    onValueModified: root._applySeedsFilter()
                }
            }

            Row {
                spacing: Spacing.xs
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Size:")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                TextField {
                    id: minSize
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    text: "0"
                    horizontalAlignment: Text.AlignRight
                    validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
                    onEditingFinished: root._applySizeFilter()
                }
                ComboBox {
                    id: minSizeUnit
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80
                    model: root._unitLabels
                    currentIndex: 2 // MiB
                    onActivated: root._applySizeFilter()
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("to")
                    font: Typography.bodyMedium
                    color: Theme.color("onSurfaceVariant")
                }
                TextField {
                    id: maxSize
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    text: "0"
                    horizontalAlignment: Text.AlignRight
                    placeholderText: qsTr("∞")
                    ToolTip.text: qsTr("0 = ∞")
                    validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
                    onEditingFinished: root._applySizeFilter()
                }
                ComboBox {
                    id: maxSizeUnit
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80
                    model: root._unitLabels
                    currentIndex: 3 // GiB
                    onActivated: root._applySizeFilter()
                }
            }
        }

        // ---- Results table ------------------------------------------------
        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.proxyModel
            persistKey: "SearchResults"
            columns: [
                { role: "name",      title: qsTr("Name"),        width: 320, align: Qt.AlignLeft,  visible: true, resizable: true },
                { role: "size",      title: qsTr("Size"),        width: 100, align: Qt.AlignRight, visible: true, resizable: true },
                { role: "seeders",   title: qsTr("Seeders"),     width: 80,  align: Qt.AlignRight, visible: true, resizable: true },
                { role: "leechers",  title: qsTr("Leechers"),    width: 80,  align: Qt.AlignRight, visible: true, resizable: true },
                { role: "engine",    title: qsTr("Engine"),      width: 120, align: Qt.AlignLeft,  visible: true, resizable: true },
                { role: "engineUrl", title: qsTr("Engine URL"),  width: 200, align: Qt.AlignLeft,  visible: true, resizable: true },
                { role: "published", title: qsTr("Published On"),width: 150, align: Qt.AlignLeft,  visible: true, resizable: true }
            ]
            delegateFor: (col) => visitedCell

            onActivated: (row) => {
                Log.info("search", "Result activated (download) row " + row)
                SearchController.downloadTorrent(root.tabId, row, SearchController.DefaultOption)
            }
            onContextRequested: (row, pos) => {
                resultsMenu.tabId = root.tabId
                resultsMenu.rows = table.selectedRows.length > 0 ? table.selectedRows : [row]
                resultsMenu.x = pos.x
                resultsMenu.y = pos.y
                resultsMenu.open()
            }
        }
    }

    // Cell delegate that mutes downloaded (visited) rows.
    Component {
        id: visitedCell
        Label {
            text: (parent.value !== undefined && parent.value !== null) ? ("" + parent.value) : ""
            font: Typography.bodyMedium
            elide: Text.ElideRight
            leftPadding: Spacing.sm
            rightPadding: Spacing.sm
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: parent.cellAlign
            anchors.fill: parent
            color: (root.proxyModel && root.proxyModel.isVisited(parent.cellRow))
                   ? Theme.color("outline")
                   : Theme.color("onSurface")
        }
    }

    SearchResultsContextMenu {
        id: resultsMenu
    }
}
