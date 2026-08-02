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
    \qmltype SearchNoPluginsPage
    \brief The empty state shown when search has nothing to offer.

    Two distinct states, because they need different actions from the user:
    \list
        \li \e{blocked} — \c SearchController.unavailableReason is non-empty, so
            search cannot run at all (no Python interpreter, or the bundled nova
            runtime could not be started). Installing plugins would fail too, so
            the install shortcut is withheld and the real cause is shown.
        \li \e{empty} — search works, there simply are no plugins yet.
    \endlist
*/
Item {
    id: root

    /*! Emitted when the user clicks the install shortcut. */
    signal installRequested()

    /*! Why search cannot run, or "" when it can. */
    readonly property string reason: SearchController.unavailableReason
    readonly property bool blocked: root.reason.length > 0

    Component.onCompleted: Log.debug("search", "SearchNoPluginsPage shown; blocked=" + root.blocked)

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Spacing.xl * 2, 480)
        spacing: Spacing.lg

        MDIcon {
            icon: root.blocked ? Icons.error : Icons.extension
            size: 64
            color: root.blocked ? Theme.color("error") : Theme.color("onSurfaceVariant")
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font: Typography.titleMedium
            color: Theme.color("onSurface")
            text: root.blocked
                ? qsTr("Search is unavailable.")
                : qsTr("There aren't any search plugins installed.")
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font: Typography.bodyMedium
            color: Theme.color("onSurfaceVariant")
            text: root.blocked
                ? root.reason
                : qsTr("Click the \"Search plugins…\" button at the bottom right of the window to install some.")
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            highlighted: true
            visible: !root.blocked
            text: qsTr("Install search plugins")
            onClicked: {
                Log.info("search", "Install plugins requested from empty page")
                root.installRequested()
            }
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            visible: root.blocked
            text: qsTr("Check again")
            onClicked: {
                Log.info("search", "Re-checking search prerequisites")
                SearchController.refreshPythonDetection()
            }
        }
    }
}
