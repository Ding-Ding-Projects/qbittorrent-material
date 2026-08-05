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
import qBittorrent

/*!
    \qmltype IconButton
    \brief Flat, round Material button wrapping an \l MDIcon with a tooltip.

    Standard \c enabled / \c checkable / \c checked semantics are inherited
    from \c ToolButton. The icon fills when the button is checked. Key
    interactions are logged through the \c Log singleton — user \c onClicked /
    \c onToggled handlers assigned at the call site remain free to run
    (logging is attached separately via \l Connections).
*/
ToolButton {
    id: root

    /*! Codepoint string for the glyph, from the \c Icons singleton.
        Named \c symbol (not \c icon) because AbstractButton::icon is FINAL. */
    property string symbol: ""

    /*! Icon size in pixels. */
    property int size: 24

    /*! Already-translated tooltip text; shown on hover when non-empty. */
    property string tooltip: ""

    /*! Base icon color (overridden to a muted tone when disabled). */
    property color color: Theme.color("onSurfaceVariant")

    display: AbstractButton.IconOnly
    flat: true
    padding: 0

    implicitWidth: Math.max(size + Spacing.sm * 2, Spacing.controlHeight)
    implicitHeight: Math.max(size + Spacing.sm * 2, Spacing.controlHeight)

    // Tooltips are already the visible label for icon-only controls; expose the
    // same label to assistive technology unless a caller supplies a richer one.
    // A glyph is not a meaningful fallback for a screen reader.
    Accessible.name: root.tooltip.length > 0 ? root.tooltip : qsTr("Icon action")

    background: Rectangle {
        radius: height / 2
        color: root.checked
            ? Theme.color("primaryContainer")
            : (root.down || root.hovered ? Theme.color("surfaceWarm") : "transparent")
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.color("primary")
        Behavior on color { ColorAnimation { duration: Spacing.motionFast } }
    }

    contentItem: MDIcon {
        icon: root.symbol
        size: root.size
        fill: root.checked
        color: root.enabled ? (root.checked ? Theme.color("primary") : root.color)
                            : Theme.color("outline")
    }

    ToolTip.visible: hovered && root.tooltip.length > 0
    ToolTip.text: root.tooltip
    ToolTip.delay: 500
    ToolTip.timeout: 5000

    // Attach logging without shadowing caller-supplied signal handlers.
    Connections {
        target: root
        function onClicked() {
            Log.debug("ui", "IconButton clicked: " + (root.tooltip.length ? root.tooltip : root.symbol))
        }
        function onToggled() {
            if (root.checkable)
                Log.debug("ui", "IconButton toggled -> " + root.checked + " (" + root.tooltip + ")")
        }
    }
}
