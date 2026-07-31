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
    \qmltype OptionsDialog
    \brief The Material Preferences dialog.

    A NavigationRail-style left list drives a \c StackLayout of the nine option
    pages (Behavior / Downloads / Connection / Speed / BitTorrent / Search / RSS /
    WebUI / Advanced). Every control on every page is bound to the
    \c OptionsController staging layer: reads go through
    \c OptionsController.value(key, default) (made reactive by the controller's
    \c revision counter) and edits stage through \c OptionsController.setValue(),
    which flips \c OptionsController.modified. The bottom button box mirrors the
    legacy OK / Cancel / Apply semantics: OK applies + closes, Apply applies and
    stays open, Cancel discards the staged changes.

    Language and color-scheme selectors bypass staging and drive \c I18n /
    \c ThemeManager live, exactly like the legacy immediate-apply behavior.
*/
Dialog {
    id: root

    title: qsTr("Options")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent

    // Cap to 90% of the window; the pages scroll internally.
    width: Math.min(1040, (parent ? parent.width : 1040) * 0.95)
    height: Math.min(760, (parent ? parent.height : 760) * 0.95)
    padding: 0

    Material.elevation: 0
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
        border.width: Spacing.outlineWidth
        border.color: Theme.color("outline")
    }

    // The rail entries; each maps 1:1 to a StackLayout page by index (mirrors the
    // legacy Tabs enum order TAB_UI..TAB_ADVANCED).
    readonly property var pages: [
        { icon: Icons.palette,          label: qsTr("Behavior") },
        { icon: Icons.download,         label: qsTr("Downloads") },
        { icon: Icons.lan,              label: qsTr("Connection") },
        { icon: Icons.speed,            label: qsTr("Speed") },
        { icon: Icons.swap_vert,        label: qsTr("BitTorrent") },
        { icon: Icons.search,           label: qsTr("Search") },
        { icon: Icons.rss_feed,         label: qsTr("RSS") },
        { icon: Icons.language,         label: qsTr("Web UI") },
        { icon: Icons.settings_suggest, label: qsTr("Advanced") }
    ]
    readonly property var pageSearchCorpus: [
        qsTr("Behavior language English Cantonese bilingual funny level warnings errors theme tray startup confirmation"),
        qsTr("Downloads save path incomplete files email notification watched folders external program"),
        qsTr("Connection port proxy IP filter protocol limits UPnP interface address"),
        qsTr("Speed upload download rate limits scheduler alternative limits bandwidth"),
        qsTr("BitTorrent privacy encryption queue seeding ratio DHT PeX trackers"),
        qsTr("Search plugins Python engine results"),
        qsTr("RSS feeds refresh interval auto download rules"),
        qsTr("Web UI API key HTTPS authentication address port dynamic DNS"),
        qsTr("Advanced libtorrent cache network disk Python recheck")
    ]
    property var tabSearchState: ["", "", "", "", "", "", "", "", ""]

    function searchMatches(index) {
        var query = optionsSearch.text.trim()
        if (!query.length)
            return false
        var text = pages[index].label + " " + pageSearchCorpus[index]
        if (optionsSearch.regexEnabled) {
            var evaluated = WorkspaceManager.evaluateRegularExpression(query,
                optionsSearch.regexFlags, text)
            return evaluated.valid && evaluated.count > 0
        }
        return text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) >= 0
    }

    function matchingPageIndexes() {
        var result = []
        for (var i = 0; i < pages.length; ++i)
            if (searchMatches(i)) result.push(i)
        return result
    }

    function open() {
        Log.info("ui", "OptionsDialog opening; reloading staged settings")
        OptionsController.load()
        rail.currentIndex = Preferences.value("GUI/Preferences/LastViewedPage", 0)
        visible = true
    }

    // Public slot (mirrors the legacy OptionsDialog::showConnectionTab): open the
    // dialog straight on the Connection page (TAB_CONNECTION == index 2). Used by
    // the status-bar connection indicator.
    function showConnectionTab() {
        Log.info("ui", "OptionsDialog: showConnectionTab()")
        open()
        rail.currentIndex = 2
    }

    onAccepted: {
        Log.info("ui", "OptionsDialog OK — applying settings")
        OptionsController.apply()
    }
    onRejected: {
        Log.info("ui", "OptionsDialog Cancel — discarding staged settings")
        OptionsController.reset()
    }

    header: Rectangle {
        implicitHeight: optionsHeading.implicitHeight + Spacing.xl * 2
        color: "transparent"

        ColumnLayout {
            id: optionsHeading
            anchors.fill: parent
            anchors.leftMargin: Spacing.pagePadding
            anchors.rightMargin: Spacing.pagePadding
            anchors.topMargin: Spacing.xl
            anchors.bottomMargin: Spacing.xl
            spacing: Spacing.xs

            Label {
                Layout.fillWidth: true
                text: root.title
                font: Typography.pageTitle
                color: Theme.color("onSurface")
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Application behavior, connection, download, BitTorrent, RSS, and advanced controls.")
                font: Typography.metadata
                color: Theme.color("muted")
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Spacing.outlineWidth
            color: Theme.color("outlineVariant")
        }
    }

    contentItem: RowLayout {
        spacing: 0

        // ---- NavigationRail-style left list -----------------------------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: Theme.color("surfaceWarm")

            // Right divider (rail elevation 0 + outline per DESIGN_SYSTEM §3).
            Rectangle {
                anchors.right: parent.right
                width: Spacing.outlineWidth
                height: parent.height
                color: Theme.color("outlineVariant")
            }

            ListView {
                id: rail
                anchors.fill: parent
                anchors.margins: Spacing.lg
                spacing: Spacing.sm
                clip: true
                currentIndex: 0
                model: root.pages
                boundsBehavior: Flickable.StopAtBounds

                onCurrentIndexChanged: {
                    Log.debug("ui", "Options page -> " + currentIndex
                              + " (" + (root.pages[currentIndex] ? root.pages[currentIndex].label : "?") + ")")
                    Preferences.setValue("GUI/Preferences/LastViewedPage", currentIndex)
                    optionsSearch.text = root.tabSearchState[currentIndex] || ""
                }

                delegate: ItemDelegate {
                    id: railItem
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: Spacing.controlHeight
                    highlighted: rail.currentIndex === index
                    onClicked: rail.currentIndex = index

                    background: Rectangle {
                        radius: Spacing.radiusControl
                        color: railItem.highlighted
                               ? Theme.color("primaryContainer")
                               : (railItem.hovered
                                  ? Theme.color("surface")
                                  : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: Spacing.motionFast }
                        }
                    }

                    contentItem: RowLayout {
                        spacing: Spacing.sm
                        MDIcon {
                            icon: railItem.modelData.icon
                            size: Spacing.iconSizeSmall
                            color: railItem.highlighted
                                   ? Theme.color("onPrimaryContainer")
                                   : Theme.color("onSurfaceVariant")
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: railItem.modelData.label
                            font: Typography.titleSmall
                            elide: Text.ElideRight
                            color: railItem.highlighted
                                   ? Theme.color("onPrimaryContainer")
                                   : Theme.color("onSurface")
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }

        // ---- Searchable page stack --------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Spacing.sm

            FilterTextField {
                id: optionsSearch
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.lg
                Layout.rightMargin: Spacing.lg
                Layout.topMargin: Spacing.md
                placeholder: qsTr("Search %1 settings…").arg(root.pages[rail.currentIndex].label)
                builderTitle: qsTr("%1 Settings Regex Builder").arg(root.pages[rail.currentIndex].label)
                builderSampleText: root.pageSearchCorpus[rail.currentIndex]
                onTextChanged: {
                    var next = root.tabSearchState.slice(0)
                    next[rail.currentIndex] = text
                    root.tabSearchState = next
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Spacing.lg
                Layout.rightMargin: Spacing.lg
                spacing: Spacing.xs
                visible: optionsSearch.text.trim().length > 0

                Label {
                    text: root.matchingPageIndexes().length === 0
                        ? qsTr("No option labels or descriptions match on any tab.")
                        : qsTr("Matches on:")
                    color: root.matchingPageIndexes().length === 0
                        ? Theme.color("error") : Theme.color("onSurfaceVariant")
                    font: Typography.bodySmall
                }
                Repeater {
                    model: root.matchingPageIndexes()
                    delegate: Button {
                        required property int modelData
                        text: modelData === rail.currentIndex
                            ? root.pages[modelData].label
                            : qsTr("%1 (different tab)").arg(root.pages[modelData].label)
                        flat: true
                        onClicked: rail.currentIndex = modelData
                    }
                }
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: rail.currentIndex

                BehaviorPage {}
                DownloadsPage {}
                ConnectionPage {}
                SpeedPage {}
                BitTorrentPage {}

            // Search — its settings are minimal in this build (the Python
            // executable path lives on the Advanced page); shown as an
            // informational placeholder so the rail order matches the legacy
            // Tabs enum. The full Search options screen is owned by the search
            // feature and can replace this page.
                Flickable {
                contentHeight: searchCol.implicitHeight + (2 * Spacing.lg)
                clip: true
                ColumnLayout {
                    id: searchCol
                    x: Spacing.lg
                    y: Spacing.lg
                    width: parent.width - (2 * Spacing.lg)
                    spacing: Spacing.lg
                    MaterialCard {
                        title: qsTr("Search")
                        titleIcon: Icons.search
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("Search engine settings are managed from the Search tab. The Python interpreter used by search plugins can be configured on the Advanced page.")
                            font: Typography.bodyMedium
                            color: Theme.color("onSurfaceVariant")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }

                RSSPage {}
                WebUIPage {}
                AdvancedPage {}
            }
        }
    }

    footer: DialogButtonBox {
        padding: Spacing.xl
        topPadding: Spacing.lg
        spacing: Spacing.sm

        background: Rectangle {
            color: "transparent"
            border.width: 0

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Spacing.outlineWidth
                color: Theme.color("outlineVariant")
            }
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.reject()
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("Apply")
            flat: true
            enabled: OptionsController.modified
            DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
            onClicked: {
                Log.info("ui", "OptionsDialog Apply")
                OptionsController.apply()
            }
        }

        Button {
            implicitHeight: Spacing.controlHeight
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: root.accept()
        }
    }

    Component.onCompleted: Log.debug("ui", "OptionsDialog constructed")
}
