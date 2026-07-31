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

pragma Singleton

import QtQuick
import qBittorrent

/*!
    \qmltype Spacing
    \brief Numeric spacing / radius / elevation tokens (DESIGN_SYSTEM §3).

    Use these instead of magic numbers, e.g.:
    \code
    ColumnLayout { spacing: Spacing.md }
    Rectangle { radius: Spacing.radiusCard }
    \endcode
*/
QtObject {
    id: spacing

    // ---- Spacing scale (px) ----------------------------------------------------
    // Canonical 4px rhythm. The legacy short names remain source-compatible;
    // explicit spaceNN aliases make the complete 4/8/12/16/20/24/32/48 scale
    // available to new shell and component work.
    readonly property real density: ThemeManager.densityScale
    readonly property int xs: Math.round(4 * density)
    readonly property int sm: Math.round(8 * density)
    readonly property int md: Math.round(12 * density)
    readonly property int lg: Math.round(16 * density)
    readonly property int space20: Math.round(20 * density)
    readonly property int xl: Math.round(24 * density)
    readonly property int xxl: Math.round(32 * density)
    readonly property int space48: Math.round(48 * density)

    readonly property int xs4: xs
    readonly property int sm8: sm
    readonly property int md12: md
    readonly property int lg16: lg
    readonly property int space4: xs
    readonly property int space8: sm
    readonly property int space12: md
    readonly property int space16: lg
    readonly property int xl24: xl
    readonly property int xxl32: xxl
    readonly property int space24: xl
    readonly property int space32: xxl

    // ---- Corner radii ----------------------------------------------------------
    //! Legacy nested-card radius; dominant workspace panels use radiusPanel.
    readonly property int radiusCard: 12
    readonly property int radiusControl: 12
    readonly property int radiusPanel: 24
    readonly property int radiusDialog: 24
    readonly property int radiusChip: 8
    readonly property int radiusField: 4
    readonly property int radiusPill: 9999

    // ---- Elevation tokens (Material `elevation`) ------------------------------
    readonly property int elevationPage: 0
    readonly property int elevationRail: 0
    readonly property int elevationCard: 0
    readonly property int elevationCardExpanded: 0
    readonly property int elevationToolbar: 0
    readonly property int elevationMenu: 3
    readonly property int elevationSnackbar: 3
    readonly property int elevationDialog: 3
    readonly property int elevationFab: 3

    // ---- Shell geometry -------------------------------------------------------
    readonly property int topBarHeight: 64
    readonly property int navigationWidth: 248
    readonly property int statusBarHeight: 32
    readonly property int controlHeight: Math.round(40 * density)
    readonly property int pagePadding: Math.round(24 * density)
    readonly property int panelHeaderPaddingVertical: 16
    readonly property int panelHeaderPaddingHorizontal: 20
    readonly property int tableCellPaddingVertical: 14
    readonly property int tableCellPaddingHorizontal: 20
    readonly property int dialogWidth: 520
    readonly property int progressHeight: 6
    readonly property int outlineWidth: 1
    readonly property int focusRingWidth: 4
    readonly property int raisedShadowOffsetY: 3
    readonly property int raisedShadowBlur: 8
    readonly property real raisedShadowOpacity: 0.18

    // ---- Motion ---------------------------------------------------------------
    readonly property int motionFast: ThemeManager.reducedMotion ? 0 : 150
    readonly property int motionBase: ThemeManager.reducedMotion ? 0 : 250
    readonly property int motionProgress: ThemeManager.reducedMotion ? 0 : 480
    readonly property int motionRowStagger: ThemeManager.reducedMotion ? 0 : 45
    //! Easing.BezierSpline control points for cubic-bezier(.2, 0, 0, 1).
    readonly property var easeStandard: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]

    // ---- Common component metrics ---------------------------------------------
    //! Standard touch target / row height for list & toolbar controls.
    readonly property int touchTarget: controlHeight
    //! Source table row: 14px type with 14px vertical cell padding.
    readonly property int rowHeight: 48
    //! Standard icon size.
    readonly property int iconSize: 24
    //! Compact icon size (dense toolbars / cells).
    readonly property int iconSizeSmall: 20
    //! Source-backed outline symbol size.
    readonly property int iconSizeOutline: 18

    Component.onCompleted: Log.debug("theme", "Spacing singleton ready")
}
