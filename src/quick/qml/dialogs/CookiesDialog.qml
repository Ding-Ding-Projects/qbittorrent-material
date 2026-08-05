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
    \qmltype CookiesDialog
    \brief Material rebuild of the legacy \c CookiesDialog ("Manage Cookies").

    An editable \l DataTable over a \c CookiesModel (one role per column: domain /
    path / name / value / expiration). Rows are appended / removed with the
    Add / Remove buttons; every cell is edited inline and written straight back
    into the model via \c CookiesModel.setCell(). \c OK commits the edited list to
    the network stack (\c CookiesModel.save()); \c Cancel discards it.
*/
Dialog {
    id: root

    title: qsTr("Manage Cookies")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(760, (parent ? parent.width : 760) * 0.9)
    height: Math.min(520, (parent ? parent.height : 520) * 0.9)
    padding: Spacing.lg

    Material.elevation: 24
    Material.roundedScale: Material.MediumScale

    background: Rectangle {
        radius: Spacing.radiusDialog
        color: Theme.color("surface")
    }

    onOpened: {
        Log.debug("ui", "CookiesDialog opened")
        cookiesModel.reload()
        const hasRows = cookiesModel.rowCount() > 0
        table.currentRow = hasRows ? 0 : -1
        table.selectedRows = hasRows ? [0] : []
    }
    onClosed: Log.debug("ui", "CookiesDialog closed")

    // The dialog owns its own model instance (CookiesModel is a plain element).
    CookiesModel {
        id: cookiesModel
    }

    // Inline-editable text cell that writes edits straight back to the model.
    Component {
        id: editableCell
        TextField {
            id: cellField
            anchors.fill: parent
            leftPadding: Spacing.sm
            rightPadding: Spacing.sm
            font: Typography.bodyMedium
            color: Theme.color("onSurface")
            selectByMouse: true
            verticalAlignment: Text.AlignVCenter
            background: null

            // Restorable binding: reflects external/model changes (incl. row
            // recycling) without fighting the user's keystrokes mid-edit.
            Binding on text {
                value: (cellField.parent.value !== undefined && cellField.parent.value !== null)
                       ? ("" + cellField.parent.value) : ""
            }

            onEditingFinished: cookiesModel.setCell(parent.cellRow, parent.cellRole, text)
        }
    }

    header: Label {
        text: root.title
        font: Typography.headlineSmall
        color: Theme.color("onSurface")
        elide: Text.ElideRight
        padding: Spacing.lg
        bottomPadding: Spacing.sm
    }

    contentItem: RowLayout {
        spacing: Spacing.md

        DataTable {
            id: table
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: cookiesModel
            persistKey: "CookiesDialog"
            alternatingRows: true
            delegateFor: (col) => editableCell
            columns: [
                { role: "domain", title: qsTr("Domain"), width: 180, align: Qt.AlignLeft, visible: true, resizable: true },
                { role: "path", title: qsTr("Path"), width: 90, align: Qt.AlignLeft, visible: true, resizable: true },
                { role: "name", title: qsTr("Name"), width: 140, align: Qt.AlignLeft, visible: true, resizable: true },
                { role: "value", title: qsTr("Value"), width: 200, align: Qt.AlignLeft, visible: true, resizable: true },
                { role: "expiration", title: qsTr("Expiration date"), width: 180, align: Qt.AlignLeft, visible: true, resizable: true }
            ]
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: Spacing.sm

            Button {
                text: qsTr("Add")
                Layout.fillWidth: true
                onClicked: {
                    const row = cookiesModel.addCookie(table.currentRow)
                    table.currentRow = row
                    table.selectedRows = [row]
                    Log.info("ui", "CookiesDialog added cookie at row " + row)
                }

                contentItem: RowLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.add; size: 18; color: Theme.color("onSurface") }
                    Label { text: qsTr("Add"); font: Typography.labelLarge; color: Theme.color("onSurface") }
                }
            }

            Button {
                text: qsTr("Remove")
                Layout.fillWidth: true
                enabled: (table.selectedRows && table.selectedRows.length > 0) || (table.currentRow >= 0)
                onClicked: {
                    const rows = (table.selectedRows && table.selectedRows.length > 0)
                            ? table.selectedRows
                            : (table.currentRow >= 0 ? [table.currentRow] : [])
                    if (rows.length === 0) {
                        NotificationCenter.notify(qsTr("Select a cookie to remove."), "warning")
                        return
                    }
                    cookiesModel.removeRows(rows)
                    table.selectedRows = []
                    table.currentRow = -1
                    Log.info("ui", "CookiesDialog removed " + rows.length + " cookie(s)")
                }

                contentItem: RowLayout {
                    spacing: Spacing.xs
                    MDIcon { icon: Icons.remove; size: 18; color: Theme.color("onSurface") }
                    Label { text: qsTr("Remove"); font: Typography.labelLarge; color: Theme.color("onSurface") }
                }
            }
        }
    }

    footer: DialogButtonBox {
        spacing: Spacing.sm
        padding: Spacing.lg
        topPadding: Spacing.sm

        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }

        Button {
            text: qsTr("OK")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        Log.info("ui", "CookiesDialog accepted; saving cookies")
        cookiesModel.save()
    }
    onRejected: Log.debug("ui", "CookiesDialog cancelled")
}
