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

#pragma once

#include <QColor>
#include <QHash>
#include <QObject>
#include <QString>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;

/// Backend for the QML `Theme` singleton.
///
/// ThemeManager owns the authoritative Material 3 + qBittorrent-extended color
/// palette (light and dark hex tables), the named-id -> role resolution map
/// (e.g. `StalledDownloading` -> `successEmphasis`, `Log.Warning` -> `severe`),
/// an optional user `config.json` override table, the active color scheme
/// (System/Light/Dark — `System` follows `Qt.styleHints.colorScheme`) and the
/// tray icon style. It is exposed to QML as a singleton so both C++ and QML
/// resolve colors through the exact same instance.
///
/// The QML `Theme` singleton is a thin facade that delegates `color(id)` here.
class ThemeManager final : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(ThemeManager)

    Q_PROPERTY(ColorScheme colorScheme READ colorScheme WRITE setColorScheme NOTIFY themeChanged)
    Q_PROPERTY(int paletteRevision READ paletteRevision NOTIFY themeChanged)
    Q_PROPERTY(TrayIconStyle trayIconStyle READ trayIconStyle WRITE setTrayIconStyle NOTIFY trayIconStyleChanged)
    Q_PROPERTY(bool isDark READ isDark NOTIFY themeChanged)
    Q_PROPERTY(UiStyle uiStyle READ uiStyle WRITE setUiStyle NOTIFY themeChanged)
    Q_PROPERTY(QString styleName READ styleName NOTIFY themeChanged)
    Q_PROPERTY(QString styleLetter READ styleLetter NOTIFY themeChanged)
    Q_PROPERTY(qreal densityScale READ densityScale WRITE setDensityScale NOTIFY appearanceChanged)
    Q_PROPERTY(QColor seedColor READ seedColor WRITE setSeedColor NOTIFY themeChanged)
    Q_PROPERTY(QString uiFontFamily READ uiFontFamily WRITE setUiFontFamily NOTIFY appearanceChanged)
    Q_PROPERTY(qreal uiFontScale READ uiFontScale WRITE setUiFontScale NOTIFY appearanceChanged)
    Q_PROPERTY(int uiFontWeight READ uiFontWeight WRITE setUiFontWeight NOTIFY appearanceChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion WRITE setReducedMotion NOTIFY appearanceChanged)

public:
    /// Preserved verbatim from legacy qBittorrent (setting `Appearance/ColorScheme`).
    enum ColorScheme
    {
        System = 0,
        Light = 1,
        Dark = 2
    };
    Q_ENUM(ColorScheme)

    /// The Material Redesign's three switchable UI directions
    /// (setting `Appearance/UiStyle`; each carries its own M3 palette).
    enum UiStyle
    {
        TonalRail = 0, // "A" — nav rail + chips, comfortable rows (purple)
        SplitDock = 1, // "B" — classic sidebar, dense table, dock (teal)
        CardFlow = 2   // "C" — cards + persistent detail panel (pink)
    };
    Q_ENUM(UiStyle)

    /// Preserved verbatim from legacy qBittorrent (setting `Appearance/TrayIconStyle`).
    enum TrayIconStyle
    {
        Normal = 0,
        Monochrome = 1
    };
    Q_ENUM(TrayIconStyle)

    /// QML singleton factory — returns the single app-owned instance.
    static ThemeManager *create(QQmlEngine *engine, QJSEngine *jsEngine);
    /// The one shared instance (also usable from pure C++).
    static ThemeManager *instance();

    ColorScheme colorScheme() const;
    void setColorScheme(ColorScheme value);
    /// Monotonic invalidation token for QML bindings that resolve palette roles
    /// through the invokable color() function.
    int paletteRevision() const;

    TrayIconStyle trayIconStyle() const;
    void setTrayIconStyle(TrayIconStyle value);

    UiStyle uiStyle() const;
    void setUiStyle(UiStyle value);
    /// Human name of the active style ("Tonal Rail" / "Split Dock" / "Card Flow").
    QString styleName() const;
    /// Short key of the active style ("A" / "B" / "C").
    QString styleLetter() const;

    qreal densityScale() const;
    void setDensityScale(qreal value);
    QColor seedColor() const;
    void setSeedColor(const QColor &value);
    Q_INVOKABLE bool isValidColor(const QString &value) const;
    Q_INVOKABLE QColor parseColorValue(const QString &value) const;
    Q_INVOKABLE QString nameForColor(const QColor &value) const;
    QString uiFontFamily() const;
    void setUiFontFamily(const QString &value);
    qreal uiFontScale() const;
    void setUiFontScale(qreal value);
    int uiFontWeight() const;
    void setUiFontWeight(int value);
    bool reducedMotion() const;
    void setReducedMotion(bool value);

    Q_INVOKABLE QStringList installedFontFamilies() const;
    Q_INVOKABLE void resetAppearance();

    /// True when the effective scheme (resolving `System`) is dark.
    bool isDark() const;

    /// Resolve a color id to a concrete color. Resolution order:
    ///  1. user `config.json` override table (light or dark, then generic);
    ///  2. named-id -> role map (recursively resolved);
    ///  3. the base Material/extended role for the active scheme;
    ///  4. a literal `#rrggbb` / SVG color name;
    ///  5. fallback `onSurface` (with a warning) so it never returns invalid.
    Q_INVOKABLE QColor color(const QString &id) const;

    /// Base resource id of the systray icon for the active tray style + scheme,
    /// e.g. `qbittorrent-tray`, `qbittorrent-tray-mono`, `qbittorrent-tray-dark`.
    Q_INVOKABLE QString trayIconName() const;

    /// Load a user color-override file (`config.json`) shaped as
    /// `{ "colors": { id: "#hex" }, "colors.dark": { id: "#hex" } }`.
    /// Missing/invalid files are ignored. Returns true if anything was loaded.
    Q_INVOKABLE bool loadColorOverrides(const QString &jsonPath);

signals:
    void themeChanged();
    void trayIconStyleChanged();
    void appearanceChanged();

private:
    explicit ThemeManager(QObject *parent = nullptr);

    void buildPalette();
    void buildStylePalette();
    void buildNamedIdMap();
    void applySeedColor();
    void persistAppearance() const;
    void onSystemColorSchemeChanged();
    void notifyThemeChanged();

    static ThemeManager *m_instance;

    ColorScheme m_colorScheme = System;
    int m_paletteRevision = 0;
    TrayIconStyle m_trayIconStyle = Normal;
    UiStyle m_uiStyle = TonalRail;
    qreal m_densityScale = 1.0;
    QColor m_seedColor;
    QString m_uiFontFamily;
    qreal m_uiFontScale = 1.0;
    int m_uiFontWeight = 400;
    bool m_reducedMotion = false;

    QHash<QString, QColor> m_lightPalette;   ///< role/id -> light color (active style)
    QHash<QString, QColor> m_darkPalette;    ///< role/id -> dark color (active style)
    QHash<QString, QString> m_namedIdMap;    ///< named id -> role (or another named id)

    QHash<QString, QColor> m_lightOverrides; ///< config.json "colors"
    QHash<QString, QColor> m_darkOverrides;  ///< config.json "colors.dark"
};
