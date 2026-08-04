/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import qBittorrent

/*!
    \qmltype Sheet
    \brief Non-blocking right-anchored panel — the Material Redesign's
           replacement for modal dialogs.

    Anchors right:16 / top:78 / bottom:16 inside its parent, slides in with
    the design's panelIn motion (240ms translateX). The window behind stays
    fully interactive; the shell keeps at most one sheet open at a time.
*/
Item {
    id: root

    /*! Sheet content width (each design sheet specifies its own). */
    property int sheetWidth: 420

    /*! Accessible name announced for the non-modal sheet surface. */
    property string accessibleName: ""

    /*! Whether the sheet is open. Drive via the shell's panel state. */
    property bool open: false

    /*! When true the sheet grows only as tall as its content (addFeed style). */
    property bool compactHeight: false

    /*! Content area — children are reparented into the panel. */
    default property alias content: contentHolder.data

    anchors.fill: parent
    visible: panel.opacity > 0.001
    enabled: open

    Rectangle {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: parent.width >= Spacing.lg * 2 ? Spacing.lg : 0
        anchors.topMargin: 78 - Spacing.topBarHeight // parent starts below the header
        // A fixed requested width used to place part of the sheet off-screen at
        // narrow logical sizes (most visibly at 200% display scale). Keep the
        // normal width when it fits and otherwise consume the bounded viewport.
        width: Math.min(root.sheetWidth,
            Math.max(0, parent.width - anchors.rightMargin * 2))
        height: root.compactHeight
            ? Math.min(contentHolder.childrenRect.height,
                Math.max(0, parent.height - anchors.topMargin - Spacing.lg))
            : Math.max(0, parent.height - anchors.topMargin - Spacing.lg)

        radius: 24
        color: Theme.color("surface")
        border.width: 1
        border.color: Theme.color("outlineVariant")
        clip: true
        Accessible.role: Accessible.Pane
        Accessible.name: root.accessibleName
        Accessible.ignored: root.accessibleName.length === 0 || !root.open

        opacity: root.open ? 1 : 0
        transform: Translate {
            x: root.open ? 0 : 24
            Behavior on x {
                NumberAnimation {
                    duration: ThemeManager.reducedMotion ? 0 : 240
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Spacing.easeStandard
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: ThemeManager.reducedMotion ? 0 : 200 }
        }

        // Soft drop shadow substitute: a slightly larger translucent halo.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            z: -1
            radius: parent.radius + 1
            color: "transparent"
            border.width: 2
            border.color: Theme.color("shadow")
            opacity: 0.5
        }

        Item {
            id: contentHolder
            anchors.fill: parent
        }
    }
}
