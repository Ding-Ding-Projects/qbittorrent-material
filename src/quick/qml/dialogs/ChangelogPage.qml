/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.platform as Platform
import qBittorrent

/*! Complete offline release history with composed date + text/regex filtering. */
Item {
    id: root

    readonly property string commitBaseUrl: "https://github.com/Ding-Ding-Projects/qbittorrent-material/commit/"
    readonly property var releaseIdentity: Experience.currentReleaseIdentity || ({})
    readonly property string releaseCodeName: String(releaseIdentity.codeName || "")
    readonly property string releasePhotoUrl: String(releaseIdentity.photoUrl || "")
    readonly property string releaseCatalogRevision: String(releaseIdentity.catalogRevision || "")
    readonly property string releaseIdentityReason: String(releaseIdentity.reason || "")
    readonly property bool releaseIdentityAvailable: releaseIdentity.available === true
        && releaseCodeName.length > 0 && releasePhotoUrl.length > 0
    readonly property string applicationVersion: Qt.application.version.length > 0
        ? Qt.application.version : qsTr("unknown")

    readonly property var filterResult: Experience.filterChangelog(
        changelogSearch.text, changelogSearch.regexEnabled, changelogSearch.regexFlags,
        fromDate.text, toDate.text)
    readonly property var filteredEntries: filterResult.entries || []

    function isoDate(date) { return Qt.formatDate(date, "yyyy-MM-dd") }
    function setLastDays(days) {
        var to = new Date()
        var from = new Date(to.getFullYear(), to.getMonth(), to.getDate() - days + 1)
        fromDate.text = isoDate(from)
        toDate.text = isoDate(to)
    }
    function localizedEntries() {
        var localized = []
        for (var i = 0; i < root.filteredEntries.length; ++i) {
            var entry = root.filteredEntries[i]
            var changes = []
            for (var j = 0; j < (entry.changes || []).length; ++j)
                changes.push(I18n.t(entry.changes[j]))
            localized.push({
                "version": entry.version,
                "date": entry.date,
                "commit": entry.commit,
                "title": I18n.t(entry.title),
                "changes": changes
            })
        }
        return localized
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Spacing.sm

        FilterTextField {
            id: changelogSearch
            Layout.fillWidth: true
            placeholder: qsTr("Search every released version…")
            builderTitle: qsTr("Changelog Regex Builder")
            builderSampleText: "build-48\nnavigation buttons\n2026-07-21"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Spacing.sm

            TextField {
                id: fromDate
                Layout.fillWidth: true
                placeholderText: qsTr("From date")
                Accessible.name: qsTr("Changelog start date")
                selectByMouse: true
                maximumLength: 32
            }
            ToolButton {
                text: qsTr("Choose changelog start date")
                display: AbstractButton.IconOnly
                contentItem: MDIcon {
                    name: "calendar_month"
                    size: 19
                    color: Theme.color("primary")
                }
                Accessible.name: qsTr("Choose changelog start date")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: {
                    calendarPopup.selectingStart = true
                    calendarPopup.open()
                }
            }
            TextField {
                id: toDate
                Layout.fillWidth: true
                placeholderText: qsTr("To date")
                Accessible.name: qsTr("Changelog end date")
                selectByMouse: true
                maximumLength: 32
            }
            ToolButton {
                text: qsTr("Choose changelog end date")
                display: AbstractButton.IconOnly
                contentItem: MDIcon {
                    name: "calendar_month"
                    size: 19
                    color: Theme.color("primary")
                }
                Accessible.name: qsTr("Choose changelog end date")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: {
                    calendarPopup.selectingStart = false
                    calendarPopup.open()
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Spacing.xs
            Button {
                text: qsTr("All time")
                flat: true
                onClicked: { fromDate.clear(); toDate.clear() }
            }
            Button { text: qsTr("Last 30 days"); flat: true; onClicked: root.setLastDays(30) }
            Button { text: qsTr("Last year"); flat: true; onClicked: root.setLastDays(365) }
            Button {
                text: qsTr("This month")
                flat: true
                onClicked: {
                    var now = new Date()
                    fromDate.text = root.isoDate(new Date(now.getFullYear(), now.getMonth(), 1))
                    toDate.text = root.isoDate(now)
                }
            }
            Button {
                text: qsTr("Copy filtered")
                flat: true
                enabled: root.filterResult.valid && root.filteredEntries.length > 0
                onClicked: Experience.copyChangelog(root.localizedEntries())
            }
            Button {
                text: qsTr("Export Markdown…")
                flat: true
                enabled: root.filterResult.valid && root.filteredEntries.length > 0
                onClicked: exportDialog.open()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !root.filterResult.valid
            text: root.filterResult.error || ""
            color: Theme.color("error")
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.AlertMessage
        }

        Label {
            Layout.fillWidth: true
            visible: root.filterResult.valid
            text: qsTr("%1 of %2 released versions").arg(root.filteredEntries.length)
                .arg(Experience.changelog.length)
            font: Typography.bodySmall
            color: Theme.color("onSurfaceVariant")
        }

        MaterialCard {
            Layout.fillWidth: true
            title: qsTr("Installed release identity")
            Accessible.name: title
            Accessible.description: root.releaseIdentityAvailable
                ? root.releaseCodeName : qsTr("Version-only release")

            Label {
                Layout.fillWidth: true
                text: root.releaseIdentityAvailable
                    ? qsTr("Version %1 · %2").arg(root.applicationVersion)
                        .arg(root.releaseCodeName)
                    : qsTr("Version %1 · version-only release")
                        .arg(root.applicationVersion)
                font: Typography.titleMedium
                color: Theme.color("onSurface")
                wrapMode: Text.WordWrap
            }

            Button {
                id: changelogPhotoLink
                Layout.fillWidth: true
                visible: root.releaseIdentityAvailable
                text: qsTr("Open public dim sum photo")
                flat: true
                focusPolicy: Qt.StrongFocus
                implicitHeight: Math.max(40,
                    changelogPhotoLinkLabel.implicitHeight + topPadding + bottomPadding)
                Accessible.name: text
                Accessible.description: qsTr("Open the public catalog photo for %1")
                    .arg(root.releaseCodeName)
                contentItem: Label {
                    id: changelogPhotoLinkLabel
                    text: changelogPhotoLink.text
                    font: changelogPhotoLink.font
                    color: changelogPhotoLink.enabled
                        ? Theme.color("primary") : Theme.color("onSurfaceVariant")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
                onClicked: Qt.openUrlExternally(root.releasePhotoUrl)
            }

            Label {
                Layout.fillWidth: true
                visible: root.releaseIdentityAvailable
                    && root.releaseCatalogRevision.length > 0
                text: qsTr("Catalog revision %1").arg(root.releaseCatalogRevision)
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WrapAnywhere
            }

            Label {
                Layout.fillWidth: true
                visible: !root.releaseIdentityAvailable
                text: qsTr("No public dim sum code name is available for this release. Version %1 remains the release identity.")
                    .arg(root.applicationVersion)
                font: Typography.bodyMedium
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                visible: !root.releaseIdentityAvailable
                    && root.releaseIdentityReason.length > 0
                text: qsTr("Reason: %1").arg(root.releaseIdentityReason)
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
            }
        }

        ListView {
            id: releaseList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Spacing.sm
            model: root.filterResult.valid ? root.filteredEntries : []
            ScrollBar.vertical: ScrollBar { }
            Accessible.name: qsTr("Filtered changelog releases")

            delegate: Rectangle {
                id: releaseCard
                required property var modelData
                width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible
                    ? ListView.view.ScrollBar.vertical.width + Spacing.xs : 0)
                height: releaseColumn.implicitHeight + Spacing.md * 2
                radius: Spacing.radiusCard
                color: Theme.color("surfaceVariant")
                border.width: 1
                border.color: Theme.color("outlineVariant")
                Accessible.name: modelData.version + ", " + modelData.date
                Accessible.description: (modelData.changes || []).map(function(change) {
                    return I18n.t(change)
                }).join(". ")

                ColumnLayout {
                    id: releaseColumn
                    anchors.fill: parent
                    anchors.margins: Spacing.md
                    spacing: Spacing.xs
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: releaseCard.modelData.version
                            font: Typography.titleMedium
                            color: Theme.color("onSurface")
                            elide: Text.ElideRight
                        }
                        Button {
                            readonly property string commitId: releaseCard.modelData.commit || ""
                            visible: commitId.length === 40
                            text: commitId.substring(0, 8)
                            flat: true
                            font: Typography.labelMedium
                            Accessible.name: qsTr("Open commit %1").arg(commitId)
                            Accessible.description: qsTr("Opens the source commit for this changelog entry")
                            onClicked: Qt.openUrlExternally(root.commitBaseUrl + commitId)
                        }
                        Label {
                            text: releaseCard.modelData.date
                            font: Typography.labelMedium
                            color: Theme.color("onSurfaceVariant")
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: I18n.t(releaseCard.modelData.title)
                        font: Typography.bodySmall
                        color: Theme.color("onSurfaceVariant")
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: releaseCard.modelData.changes || []
                        delegate: Label {
                            required property string modelData
                            Layout.fillWidth: true
                            text: "• " + I18n.t(modelData)
                            font: Typography.bodyMedium
                            color: Theme.color("onSurface")
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                width: Math.min(parent.width - Spacing.xl * 2, 420)
                visible: root.filterResult.valid && releaseList.count === 0
                text: qsTr("No released version matches both the search and date range.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Theme.color("onSurfaceVariant")
            }
        }
    }

    Popup {
        id: calendarPopup
        parent: root
        anchors.centerIn: parent
        width: Math.min(390, root.width - Spacing.lg * 2)
        height: 430
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property bool selectingStart: true
        property int shownMonth: new Date().getMonth()
        property int shownYear: new Date().getFullYear()
        Material.elevation: 12

        background: Rectangle {
            radius: Spacing.radiusDialog
            color: Theme.color("surface")
            border.width: 1
            border.color: Theme.color("outlineVariant")
        }

        contentItem: ColumnLayout {
            spacing: Spacing.sm
            Label {
                Layout.fillWidth: true
                text: calendarPopup.selectingStart ? qsTr("Choose start date") : qsTr("Choose end date")
                font: Typography.titleLarge
            }
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: monthPicker
                    Layout.fillWidth: true
                    model: [qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"),
                        qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"),
                        qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")]
                    currentIndex: calendarPopup.shownMonth
                    onActivated: (index) => calendarPopup.shownMonth = index
                }
                SpinBox {
                    from: 2000
                    to: new Date().getFullYear() + 2
                    value: calendarPopup.shownYear
                    editable: true
                    onValueModified: calendarPopup.shownYear = value
                }
            }
            DayOfWeekRow {
                Layout.fillWidth: true
                locale: monthGrid.locale
            }
            MonthGrid {
                id: monthGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                month: calendarPopup.shownMonth
                year: calendarPopup.shownYear
                onClicked: (date) => {
                    if (calendarPopup.selectingStart) fromDate.text = root.isoDate(date)
                    else toDate.text = root.isoDate(date)
                    calendarPopup.close()
                }
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Typed dates accept your locale format or YYYY-MM-DD.")
                font: Typography.bodySmall
                color: Theme.color("onSurfaceVariant")
                wrapMode: Text.WordWrap
            }
        }
    }

    Platform.FileDialog {
        id: exportDialog
        title: qsTr("Export filtered changelog")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "md"
        nameFilters: [qsTr("Markdown files (*.md)"), qsTr("Text files (*.txt)")]
        onAccepted: Experience.exportChangelog(file, root.localizedEntries())
    }
}
