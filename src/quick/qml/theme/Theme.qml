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
import QtQuick.Controls.Material
import qBittorrent

/*!
    \qmltype Theme
    \brief Application color facade.

    Thin QML facade over the C++ \c ThemeManager singleton. Every color in the
    app is resolved through \c Theme.color(id) / \c Theme.stateColor(state) so
    color policy lives in exactly one place. The light+dark hex tables are owned
    by \c ThemeManager (see thememanager.cpp) and mirrored here as documentation
    of the DESIGN_SYSTEM palette; call \c color() rather than the raw literals so
    user \c config.json overrides and the named-id map are honored.

    Root wiring (done once in Main.qml):
    \code
    Material.theme: Theme.materialTheme
    Material.accent: Theme.accent
    Material.primary: Theme.primary
    Material.background: Theme.surface
    Material.foreground: Theme.onSurface
    \endcode
*/
QtObject {
    id: theme

    // ---- Scheme state (driven by ThemeManager) --------------------------------

    //! True when the effective color scheme (resolving System) is dark.
    readonly property bool isDark: ThemeManager.isDark

    //! Changes whenever any palette input changes, even if the scheme does not.
    readonly property int paletteRevision: ThemeManager.paletteRevision

    //! Material.theme value for the current scheme.
    readonly property int materialTheme: isDark ? Material.Dark : Material.Light

    // ---- UI style (Material Redesign: Tonal Rail / Split Dock / Card Flow) ----

    //! Active UI style as a ThemeManager.UiStyle value (0=A, 1=B, 2=C).
    readonly property int uiStyle: ThemeManager.uiStyle

    //! Human name of the active style ("Tonal Rail" / "Split Dock" / "Card Flow").
    readonly property string styleName: ThemeManager.styleName

    //! Short style key: "A", "B" or "C".
    readonly property string styleLetter: ThemeManager.styleLetter

    //! Convenience flags for per-style layout branches.
    readonly property bool isTonalRail: uiStyle === 0
    readonly property bool isSplitDock: uiStyle === 1
    readonly property bool isCardFlow: uiStyle === 2

    // ---- Resolution -----------------------------------------------------------

    /*!
        Resolve a color \a id to a concrete color. Accepts Material/extended role
        names ("primary", "onSurfaceVariant", "success", ...), named ids
        ("StalledDownloading", "Log.Warning", "PiecesBar.Piece", ...) and literal
        "#rrggbb" strings. Delegates to ThemeManager so overrides + the named-id
        map are applied. Always returns a valid color.
    */
    function color(id) {
        // QML cannot discover changes hidden behind an invokable lookup. Read
        // the revision explicitly so seed, style, override, and scheme changes
        // all invalidate every binding that resolves a role through this facade.
        const revision = paletteRevision
        return ThemeManager.color(id);
    }

    /*!
        Row TEXT color for a BitTorrent::TorrentState \a state (the int value).
        Maps the state to its named id and resolves via ThemeManager, so the
        row-color policy stays data-driven and override-able.
    */
    function stateColor(state) {
        return color(_stateName(state));
    }

    // Map a TorrentState int to its named-id (kept in sync with TransferState
    // numeric values in CONTRACTS §6.3). Unknown -> "Unknown" -> muted.
    function _stateName(state) {
        switch (state) {
        case 0:  return "ForcedDownloading";
        case 1:  return "Downloading";
        case 2:  return "ForcedDownloadingMetadata";
        case 3:  return "DownloadingMetadata";
        case 4:  return "StalledDownloading";
        case 5:  return "ForcedUploading";
        case 6:  return "Uploading";
        case 7:  return "StalledUploading";
        case 8:  return "CheckingResumeData";
        case 9:  return "QueuedDownloading";
        case 10: return "QueuedUploading";
        case 11: return "CheckingUploading";
        case 12: return "CheckingDownloading";
        case 13: return "StoppedDownloading";
        case 14: return "StoppedUploading";
        case 15: return "Moving";
        case 16: return "MissingFiles";
        case 17: return "Error";
        default: return "Unknown";
        }
    }

    // ---- Convenience role properties (live-bound to the scheme) ----------------
    // Each is just color("<role>") so overrides still apply; exposed by name for
    // ergonomic bindings (e.g. `color: Theme.onSurface`).

    readonly property color primary: color("primary")
    readonly property color onPrimary: color("onPrimary")
    readonly property color primaryContainer: color("primaryContainer")
    readonly property color onPrimaryContainer: color("onPrimaryContainer")
    readonly property color primaryHover: color("primaryHover")
    readonly property color primaryPressed: color("primaryPressed")
    readonly property color primaryEmphasis: color("primaryEmphasis")

    readonly property color secondary: color("secondary")
    readonly property color onSecondary: color("onSecondary")
    readonly property color secondaryContainer: color("secondaryContainer")
    readonly property color onSecondaryContainer: color("onSecondaryContainer")
    readonly property color tertiary: color("tertiary")
    readonly property color onTertiary: color("onTertiary")
    readonly property color tertiaryContainer: color("tertiaryContainer")
    readonly property color onTertiaryContainer: color("onTertiaryContainer")

    readonly property color surface: color("surface")
    readonly property color surfaceVariant: color("surfaceVariant")
    readonly property color onSurface: color("onSurface")
    readonly property color onSurfaceVariant: color("onSurfaceVariant")
    readonly property color background: color("background")
    readonly property color onBackground: color("onBackground")

    readonly property color outline: color("outline")
    readonly property color outlineVariant: color("outlineVariant")
    readonly property color focusRing: color("focusRing")
    readonly property color scrim: color("scrim")

    readonly property color error: color("error")
    readonly property color onError: color("onError")
    readonly property color errorContainer: color("errorContainer")
    readonly property color onErrorContainer: color("onErrorContainer")

    // qBittorrent extended roles.
    readonly property color success: color("success")
    readonly property color successEmphasis: color("successEmphasis")
    readonly property color warning: color("warning")
    readonly property color done: color("done")
    readonly property color info: color("info")
    readonly property color muted: color("muted")
    readonly property color severe: color("severe")

    // Canonical design-system semantics. These resolve through named ids rather
    // than copying role values, so config.json may override either spelling.
    readonly property color canvas: color("canvas")
    readonly property color surfaceWarm: color("surfaceWarm")
    readonly property color selectedSurface: color("selectedSurface")
    readonly property color foreground: color("foreground")
    readonly property color foregroundSecondary: color("foregroundSecondary")
    readonly property color border: color("border")
    readonly property color borderSoft: color("borderSoft")
    readonly property color accent: color("accent")
    readonly property color accentOn: color("accentOn")
    readonly property color danger: color("danger")
    readonly property color onDanger: color("onDanger")
    readonly property color dangerContainer: color("dangerContainer")

    // ---- Interaction-state overlays (Material state layers) --------------------
    // Alpha overlays applied on hover/press/selection per DESIGN_SYSTEM §3.
    readonly property real hoverOpacity: 0.08
    readonly property real selectedOpacity: 0.12
    readonly property real pressedOpacity: 0.16
    //! Alternating-row tint = surfaceVariant @ 40%.
    readonly property color alternateRow: Qt.rgba(surfaceVariant.r, surfaceVariant.g,
                                                  surfaceVariant.b, 0.40)

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

    // Source-system elevation is border-led: panels are flat and only transient
    // layers use the restrained 3px/8px/18% shadow recipe.
    readonly property int elevationPanel: 0
    readonly property int elevationRaised: 3
    readonly property int raisedShadowBlur: 8
    readonly property real raisedShadowOpacity: 0.18

    Component.onCompleted: Log.debug("theme", "Theme singleton ready; isDark=" + isDark)

    // Re-log whenever the scheme flips so theme changes are traceable.
    onIsDarkChanged: Log.info("theme", "Effective color scheme changed; isDark=" + isDark)
}
