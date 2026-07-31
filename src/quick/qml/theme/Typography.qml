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
    \qmltype Typography
    \brief qBittorrent Material type-scale tokens (DESIGN_SYSTEM §2).

    Each token is a ready-to-assign \c font group, e.g.:
    \code
    Label { font: Typography.titleMedium; text: qsTr("Transfer") }
    Label { font: Typography.mono; text: speedText }   // tabular numerics
    \endcode

    Sizes are given in pixels (\c pixelSize) so they match the Material spec
    regardless of screen DPI scaling handled by Qt.
*/
QtObject {
    id: typography

    // The app-assets resource collection is mounted at qrc:/, so fonts under
    // resources/fonts are available at qrc:/fonts/<file>. FontLoader registers
    // each bundled face with the application and exposes its canonical family
    // name; the literal fallbacks keep the UI usable if a package is damaged.
    readonly property FontLoader robotoLoader: FontLoader {
        source: "qrc:/fonts/Roboto.ttf"
    }
    readonly property FontLoader robotoMonoLoader: FontLoader {
        source: "qrc:/fonts/RobotoMono.ttf"
    }

    //! Primary UI font family.
    readonly property string family: ThemeManager.uiFontFamily.length > 0
        ? ThemeManager.uiFontFamily
        : (robotoLoader.status === FontLoader.Ready ? robotoLoader.name : "Roboto")
    readonly property real scale: ThemeManager.uiFontScale
    readonly property int normalWeight: ThemeManager.uiFontWeight
    readonly property int strongWeight: Math.max(Font.DemiBold, ThemeManager.uiFontWeight)
    //! Google Sans is not bundled; Roboto is the verified display fallback.
    readonly property string displayFamily: family
    //! Monospaced family for tabular numerics (speeds/sizes/ratios).
    readonly property string monoFamily: robotoMonoLoader.status === FontLoader.Ready
        ? robotoMonoLoader.name : "Roboto Mono"

    // ---- Source-system type roles --------------------------------------------

    //! Large display specimen retained by the source scale.
    readonly property font displayXLarge: Qt.font({
        family: displayFamily, pixelSize: 64 * scale, weight: strongWeight,
        letterSpacing: -1.28
    })

    //! Compact display specimen retained by the source scale.
    readonly property font displayLarge: Qt.font({
        family: displayFamily, pixelSize: 48 * scale, weight: strongWeight,
        letterSpacing: -0.96
    })

    //! Page heading: 32/600, -0.02em tracking.
    readonly property font pageTitle: Qt.font({
        family: displayFamily, pixelSize: 32 * scale, weight: strongWeight,
        letterSpacing: -0.64
    })

    //! Section and dialog heading: 24/600, restrained -0.01em tracking.
    readonly property font sectionTitle: Qt.font({
        family: displayFamily, pixelSize: 24 * scale, weight: strongWeight,
        letterSpacing: -0.24
    })

    //! Product lockup: 20/600, -0.01em tracking.
    readonly property font brand: Qt.font({
        family: displayFamily, pixelSize: 20 * scale, weight: strongWeight,
        letterSpacing: -0.20
    })

    //! Default desktop UI copy: 14/400.
    readonly property font body: Qt.font({
        family: family, pixelSize: 14 * scale, weight: normalWeight, letterSpacing: 0
    })

    //! Uppercase-compatible table label: 11/600, 0.07em tracking.
    readonly property font tableHeader: Qt.font({
        family: family, pixelSize: 11 * scale, weight: strongWeight,
        letterSpacing: 0.77, capitalization: Font.AllUppercase
    })

    //! Grouped navigation label; intentionally shares the table-header rhythm.
    readonly property font navLabel: tableHeader

    //! Operational metric: 18/600 monospace.
    readonly property font metric: Qt.font({
        family: monoFamily, pixelSize: 18 * scale, weight: strongWeight,
        letterSpacing: 0
    })

    //! Muted labels and metadata: 12/400.
    readonly property font metadata: Qt.font({
        family: family, pixelSize: 12 * scale, weight: normalWeight, letterSpacing: 0
    })

    //! Tabular metadata: 12/400 monospace.
    readonly property font metadataMono: Qt.font({
        family: monoFamily, pixelSize: 12 * scale, weight: normalWeight,
        letterSpacing: 0
    })

    // ---- Display / headline / title -------------------------------------------

    //! Compatibility name for section/dialog titles.
    readonly property font headlineSmall: sectionTitle

    //! 22 — About header and other large titles.
    readonly property font titleLarge: Qt.font({
        family: family, pixelSize: 22 * scale, weight: normalWeight, letterSpacing: 0
    })

    //! 16 SemiBold — card / group-box headers.
    readonly property font titleMedium: Qt.font({
        family: family, pixelSize: 16 * scale, weight: strongWeight, letterSpacing: 0
    })

    //! 14 SemiBold — tab labels.
    readonly property font titleSmall: Qt.font({
        family: family, pixelSize: 14 * scale, weight: strongWeight, letterSpacing: 0
    })

    // ---- Body -----------------------------------------------------------------

    //! Compatibility name for default body copy.
    readonly property font bodyLarge: body

    //! Compatibility name; table cells and form labels use the 14px body role.
    readonly property font bodyMedium: body

    //! Compatibility role used by supporting copy.
    readonly property font bodySmall: metadata

    // ---- Label ----------------------------------------------------------------

    //! 14 Medium — buttons.
    readonly property font labelLarge: Qt.font({
        family: family, pixelSize: 14 * scale, weight: Math.max(Font.Medium, normalWeight), letterSpacing: 0.28
    })

    //! Compact visible field label.
    readonly property font labelMedium: Qt.font({
        family: family, pixelSize: 12 * scale, weight: strongWeight, letterSpacing: 0.12
    })

    //! 11 — captions / counts.
    readonly property font labelSmall: Qt.font({
        family: family, pixelSize: 11 * scale, weight: Math.max(Font.Medium, normalWeight), letterSpacing: 0.5
    })

    // ---- Monospaced (tabular) -------------------------------------------------

    //! Default mono, matches bodyMedium size — for numeric table cells.
    readonly property font mono: Qt.font({
        family: monoFamily, pixelSize: 14 * scale, weight: normalWeight,
        letterSpacing: 0
    })

    //! Larger mono for prominent numeric values (e.g. statistics figures).
    readonly property font monoLarge: Qt.font({
        family: monoFamily, pixelSize: 18 * scale, weight: strongWeight,
        letterSpacing: 0
    })

    Component.onCompleted: Log.debug("theme", "Typography singleton ready; family=" + family)
}
