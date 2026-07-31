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

#include "thememanager.h"

#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStyleHints>

#include "base/logging.h"
#include "base/preferences.h"

using namespace Qt::StringLiterals;

namespace
{
    const QString kColorSchemeKey = u"Appearance/ColorScheme"_s;
    const QString kTrayIconStyleKey = u"Appearance/TrayIconStyle"_s;
    const QString kUiStyleKey = u"Appearance/UiStyle"_s;
    const QString kDensityKey = u"Appearance/DensityScale"_s;
    const QString kSeedKey = u"Appearance/SeedColor"_s;
    const QString kFontFamilyKey = u"Appearance/FontFamily"_s;
    const QString kFontScaleKey = u"Appearance/FontScale"_s;
    const QString kFontWeightKey = u"Appearance/FontWeight"_s;
    const QString kReducedMotionKey = u"Appearance/ReducedMotion"_s;

    QColor parseColor(const QString &hex)
    {
        const QColor c(hex);
        return c;
    }

    QColor withAlpha(const QColor &base, const qreal alpha)
    {
        QColor c = base;
        c.setAlphaF(alpha);
        return c;
    }

    // One UI style's 13 Material Redesign palette roles (per scheme).
    struct StylePalette
    {
        QString bg, surf, sc, sc2, on, onv, ol, olv, pr, onPr, pc, onPc;
        QColor shadow;
    };

    // Status colors shared by all styles (per scheme) — the design's ST table.
    struct StatusPalette
    {
        QString success, error, warning, done, muted, info;
    };
}

ThemeManager *ThemeManager::m_instance = nullptr;

ThemeManager::ThemeManager(QObject *parent)
    : QObject(parent)
{
    qCDebug(lcTheme) << "ThemeManager constructing";

    // Restore persisted user choices (legacy setting keys preserved verbatim).
    auto *prefs = Preferences::instance();
    if (prefs)
    {
        m_colorScheme = static_cast<ColorScheme>(
            prefs->value(kColorSchemeKey, static_cast<int>(System)).toInt());
        m_trayIconStyle = static_cast<TrayIconStyle>(
            prefs->value(kTrayIconStyleKey, static_cast<int>(Normal)).toInt());
        const QString style = prefs->value(kUiStyleKey, u"TonalRail"_s).toString();
        m_uiStyle = (style == u"SplitDock"_s) ? SplitDock
            : (style == u"CardFlow"_s) ? CardFlow : TonalRail;
        m_densityScale = qBound<qreal>(0.75, prefs->value(kDensityKey, 1.0).toReal(), 1.5);
        const QColor seed(prefs->value(kSeedKey).toString());
        if (seed.isValid())
            m_seedColor = seed;
        m_uiFontFamily = prefs->value(kFontFamilyKey).toString();
        m_uiFontScale = qBound<qreal>(0.75, prefs->value(kFontScaleKey, 1.0).toReal(), 1.75);
        m_uiFontWeight = qBound(100, prefs->value(kFontWeightKey, 400).toInt(), 900);
        m_reducedMotion = prefs->value(kReducedMotionKey, false).toBool();
    }

    buildPalette();
    buildStylePalette();
    buildNamedIdMap();
    qCInfo(lcTheme) << "ThemeManager initialized; colorScheme=" << m_colorScheme
                    << "trayIconStyle=" << m_trayIconStyle << "isDark=" << isDark();

    // Follow the OS when the scheme is `System`.
    if (const QStyleHints *hints = QGuiApplication::styleHints())
    {
        connect(hints, &QStyleHints::colorSchemeChanged, this,
            [this](Qt::ColorScheme) { onSystemColorSchemeChanged(); });
    }
}

ThemeManager *ThemeManager::create(QQmlEngine *engine, QJSEngine *jsEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(jsEngine)
    return instance();
}

ThemeManager *ThemeManager::instance()
{
    if (!m_instance)
        m_instance = new ThemeManager;
    return m_instance;
}

ThemeManager::ColorScheme ThemeManager::colorScheme() const
{
    return m_colorScheme;
}

void ThemeManager::setColorScheme(ColorScheme value)
{
    if (m_colorScheme == value)
        return;

    qCInfo(lcTheme) << "Color scheme changed" << m_colorScheme << "->" << value;
    m_colorScheme = value;

    if (auto *prefs = Preferences::instance())
    {
        prefs->setValue(kColorSchemeKey, static_cast<int>(value));
        prefs->apply();
    }
    emit themeChanged();
}

ThemeManager::TrayIconStyle ThemeManager::trayIconStyle() const
{
    return m_trayIconStyle;
}

void ThemeManager::setTrayIconStyle(TrayIconStyle value)
{
    if (m_trayIconStyle == value)
        return;

    qCInfo(lcTheme) << "Tray icon style changed" << m_trayIconStyle << "->" << value;
    m_trayIconStyle = value;

    if (auto *prefs = Preferences::instance())
    {
        prefs->setValue(kTrayIconStyleKey, static_cast<int>(value));
        prefs->apply();
    }
    emit trayIconStyleChanged();
}

ThemeManager::UiStyle ThemeManager::uiStyle() const
{
    return m_uiStyle;
}

void ThemeManager::setUiStyle(const UiStyle value)
{
    if (m_uiStyle == value)
        return;

    qCInfo(lcTheme) << "UI style changed" << m_uiStyle << "->" << value;
    m_uiStyle = value;
    buildStylePalette();

    if (auto *prefs = Preferences::instance())
    {
        const QString name = (value == SplitDock) ? u"SplitDock"_s
            : (value == CardFlow) ? u"CardFlow"_s : u"TonalRail"_s;
        prefs->setValue(kUiStyleKey, name);
        prefs->apply();
    }
    emit themeChanged();
}

QString ThemeManager::styleName() const
{
    switch (m_uiStyle)
    {
    case SplitDock: return u"Split Dock"_s;
    case CardFlow: return u"Card Flow"_s;
    case TonalRail:
    default: return u"Tonal Rail"_s;
    }
}

QString ThemeManager::styleLetter() const
{
    switch (m_uiStyle)
    {
    case SplitDock: return u"B"_s;
    case CardFlow: return u"C"_s;
    case TonalRail:
    default: return u"A"_s;
    }
}

qreal ThemeManager::densityScale() const
{
    return m_densityScale;
}

void ThemeManager::setDensityScale(const qreal value)
{
    const qreal bounded = qBound<qreal>(0.75, value, 1.5);
    if (qFuzzyCompare(m_densityScale, bounded))
        return;
    m_densityScale = bounded;
    persistAppearance();
    emit appearanceChanged();
}

QColor ThemeManager::seedColor() const
{
    return m_seedColor.isValid() ? m_seedColor : color(u"primary"_s);
}

void ThemeManager::setSeedColor(const QColor &value)
{
    if (!value.isValid() || m_seedColor == value)
        return;
    m_seedColor = value;
    buildStylePalette();
    persistAppearance();
    emit appearanceChanged();
    emit themeChanged();
}

QString ThemeManager::uiFontFamily() const
{
    return m_uiFontFamily;
}

void ThemeManager::setUiFontFamily(const QString &value)
{
    const QString trimmed = value.trimmed();
    if (m_uiFontFamily == trimmed)
        return;
    m_uiFontFamily = trimmed;
    persistAppearance();
    emit appearanceChanged();
}

qreal ThemeManager::uiFontScale() const
{
    return m_uiFontScale;
}

void ThemeManager::setUiFontScale(const qreal value)
{
    const qreal bounded = qBound<qreal>(0.75, value, 1.75);
    if (qFuzzyCompare(m_uiFontScale, bounded))
        return;
    m_uiFontScale = bounded;
    persistAppearance();
    emit appearanceChanged();
}

int ThemeManager::uiFontWeight() const
{
    return m_uiFontWeight;
}

void ThemeManager::setUiFontWeight(const int value)
{
    const int bounded = qBound(100, value, 900);
    if (m_uiFontWeight == bounded)
        return;
    m_uiFontWeight = bounded;
    persistAppearance();
    emit appearanceChanged();
}

bool ThemeManager::reducedMotion() const
{
    return m_reducedMotion;
}

void ThemeManager::setReducedMotion(const bool value)
{
    if (m_reducedMotion == value)
        return;
    m_reducedMotion = value;
    persistAppearance();
    emit appearanceChanged();
}

QStringList ThemeManager::installedFontFamilies() const
{
    return QFontDatabase::families();
}

void ThemeManager::resetAppearance()
{
    m_densityScale = 1.0;
    m_seedColor = {};
    m_uiFontFamily.clear();
    m_uiFontScale = 1.0;
    m_uiFontWeight = 400;
    m_reducedMotion = false;
    buildStylePalette();
    persistAppearance();
    emit appearanceChanged();
    emit themeChanged();
}

void ThemeManager::persistAppearance() const
{
    if (auto *prefs = Preferences::instance())
    {
        prefs->setValue(kDensityKey, m_densityScale);
        prefs->setValue(kSeedKey, m_seedColor.isValid() ? m_seedColor.name(QColor::HexArgb) : QString());
        prefs->setValue(kFontFamilyKey, m_uiFontFamily);
        prefs->setValue(kFontScaleKey, m_uiFontScale);
        prefs->setValue(kFontWeightKey, m_uiFontWeight);
        prefs->setValue(kReducedMotionKey, m_reducedMotion);
        prefs->apply();
    }
}

bool ThemeManager::isDark() const
{
    switch (m_colorScheme)
    {
    case Light:
        return false;
    case Dark:
        return true;
    case System:
    default:
        if (const QStyleHints *hints = QGuiApplication::styleHints())
            return hints->colorScheme() == Qt::ColorScheme::Dark;
        return false;
    }
}

void ThemeManager::onSystemColorSchemeChanged()
{
    if (m_colorScheme != System)
        return; // only relevant while following the OS

    qCInfo(lcTheme) << "System color scheme changed; effective isDark=" << isDark();
    emit themeChanged();
}

QColor ThemeManager::color(const QString &id) const
{
    const bool dark = isDark();

    // 1. User config.json overrides (scheme-specific first, then generic-light).
    if (dark)
    {
        if (const auto it = m_darkOverrides.constFind(id); it != m_darkOverrides.cend())
            return it.value();
    }
    if (const auto it = m_lightOverrides.constFind(id);
        (!dark || !m_darkOverrides.contains(id)) && (it != m_lightOverrides.cend()))
    {
        return it.value();
    }

    // 2. Named-id -> role indirection (resolved recursively).
    if (const auto it = m_namedIdMap.constFind(id); it != m_namedIdMap.cend())
    {
        if (it.value() != id) // guard against a self-referential map entry
            return color(it.value());
    }

    // 3. Base Material / extended role for the active scheme.
    const QHash<QString, QColor> &palette = dark ? m_darkPalette : m_lightPalette;
    if (const auto it = palette.constFind(id); it != palette.cend())
        return it.value();

    // 4. A literal color (`#rrggbb`, `#aarrggbb`, or SVG name).
    if (QColor::isValidColorName(id))
        return QColor::fromString(id);

    // 5. Never return an invalid color.
    qCWarning(lcTheme) << "Unknown color id" << id << "- falling back to onSurface";
    return palette.value(u"onSurface"_s, dark ? QColor(0xe8, 0xea, 0xed) : QColor(0x20, 0x21, 0x24));
}

QString ThemeManager::trayIconName() const
{
    if (m_trayIconStyle == Monochrome)
        return isDark() ? u"qbittorrent-tray-light"_s : u"qbittorrent-tray-dark"_s;
    return u"qbittorrent-tray"_s;
}

bool ThemeManager::loadColorOverrides(const QString &jsonPath)
{
    qCDebug(lcTheme) << "Loading color overrides from" << jsonPath;

    QFile file(jsonPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        qCDebug(lcTheme) << "No color override file at" << jsonPath;
        return false;
    }

    QJsonParseError parseError {};
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject())
    {
        qCWarning(lcTheme) << "Invalid color override JSON:" << parseError.errorString();
        return false;
    }

    const QJsonObject root = doc.object();
    const auto ingest = [](const QJsonObject &obj, QHash<QString, QColor> &target)
    {
        int count = 0;
        for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
        {
            const QColor c = parseColor(it.value().toString());
            if (c.isValid())
            {
                target.insert(it.key(), c);
                ++count;
            }
            else
            {
                qCWarning(lcTheme) << "Ignoring invalid override color for" << it.key();
            }
        }
        return count;
    };

    m_lightOverrides.clear();
    m_darkOverrides.clear();
    const int light = ingest(root.value(u"colors"_s).toObject(), m_lightOverrides);
    const int dark = ingest(root.value(u"colors.dark"_s).toObject(), m_darkOverrides);

    qCInfo(lcTheme) << "Loaded color overrides:" << light << "light," << dark << "dark";
    emit themeChanged();
    return (light + dark) > 0;
}

void ThemeManager::buildPalette()
{
    // ---- Base Material roles -------------------------------------------------
    // Light values are the canonical qBittorrent Material design-system tokens.
    // Dark values are their Google Material dark counterparts: neutral chrome,
    // a single blue action accent, and the Google dark status palette.
    const auto put = [this](const QString &id, const QString &light, const QString &dark)
    {
        m_lightPalette.insert(id, parseColor(light));
        m_darkPalette.insert(id, parseColor(dark));
    };

    // Primary family.
    put(u"primary"_s, u"#1a73e8"_s, u"#8ab4f8"_s);
    put(u"onPrimary"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"primaryContainer"_s, u"#e8f0fe"_s, u"#394457"_s);
    put(u"onPrimaryContainer"_s, u"#1a73e8"_s, u"#aecbfa"_s);
    // Oklab mixes from the source contract: accent + 8%/14% black.
    put(u"primaryHover"_s, u"#1666d0"_s, u"#9bbdf8"_s);
    put(u"primaryPressed"_s, u"#135dbe"_s, u"#aecbfa"_s);
    put(u"primaryEmphasis"_s, u"#135dbe"_s, u"#aecbfa"_s);

    // The system has one decorative accent. Secondary stays neutral and
    // tertiary carries the semantic success family rather than adding purple.
    put(u"secondary"_s, u"#3c4043"_s, u"#bdc1c6"_s);
    put(u"onSecondary"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"secondaryContainer"_s, u"#f8fafd"_s, u"#303134"_s);
    put(u"onSecondaryContainer"_s, u"#3c4043"_s, u"#bdc1c6"_s);
    put(u"tertiary"_s, u"#188038"_s, u"#81c995"_s);
    put(u"onTertiary"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"tertiaryContainer"_s, u"#e6f4ea"_s, u"#1e3a2a"_s);
    put(u"onTertiaryContainer"_s, u"#188038"_s, u"#81c995"_s);

    // Surfaces / text.
    put(u"surface"_s, u"#ffffff"_s, u"#292a2d"_s);
    put(u"surfaceVariant"_s, u"#f8fafd"_s, u"#303134"_s);
    put(u"onSurface"_s, u"#202124"_s, u"#e8eaed"_s);
    put(u"onSurfaceVariant"_s, u"#5f6368"_s, u"#9aa0a6"_s);
    put(u"secondaryText"_s, u"#3c4043"_s, u"#bdc1c6"_s);
    put(u"background"_s, u"#f8fafd"_s, u"#202124"_s);
    put(u"onBackground"_s, u"#202124"_s, u"#e8eaed"_s);

    // Lines.
    put(u"outline"_s, u"#dadce0"_s, u"#5f6368"_s);
    put(u"outlineVariant"_s, u"#edf0f2"_s, u"#3c4043"_s);
    put(u"focusRing"_s, u"#3d1a73e8"_s, u"#528ab4f8"_s);
    put(u"scrim"_s, u"#59202124"_s, u"#99000000"_s);

    // Error.
    put(u"error"_s, u"#d93025"_s, u"#f28b82"_s);
    put(u"onError"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"errorContainer"_s, u"#fce8e6"_s, u"#4a2525"_s);
    put(u"onErrorContainer"_s, u"#d93025"_s, u"#f28b82"_s);

    // ---- qBittorrent extended roles. ----
    put(u"success"_s, u"#188038"_s, u"#81c995"_s);
    put(u"onSuccess"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"successContainer"_s, u"#e6f4ea"_s, u"#1e3a2a"_s);
    put(u"onSuccessContainer"_s, u"#188038"_s, u"#81c995"_s);

    put(u"successEmphasis"_s, u"#188038"_s, u"#81c995"_s);
    put(u"onSuccessEmphasis"_s, u"#ffffff"_s, u"#202124"_s);

    put(u"warning"_s, u"#f9ab00"_s, u"#fdd663"_s);
    put(u"onWarning"_s, u"#202124"_s, u"#202124"_s);
    put(u"warningContainer"_s, u"#fef7e0"_s, u"#4a3f1d"_s);
    put(u"onWarningContainer"_s, u"#b06000"_s, u"#fdd663"_s);

    // Completed/done is success in this system; purple is intentionally absent.
    put(u"done"_s, u"#188038"_s, u"#81c995"_s);
    put(u"onDone"_s, u"#ffffff"_s, u"#202124"_s);
    put(u"doneContainer"_s, u"#e6f4ea"_s, u"#1e3a2a"_s);
    put(u"onDoneContainer"_s, u"#188038"_s, u"#81c995"_s);

    put(u"info"_s, u"#1a73e8"_s, u"#8ab4f8"_s); // == primary
    put(u"onInfo"_s, u"#ffffff"_s, u"#202124"_s);

    put(u"muted"_s, u"#5f6368"_s, u"#9aa0a6"_s); // == onSurfaceVariant

    put(u"severe"_s, u"#f9ab00"_s, u"#fdd663"_s); // == warning
    put(u"onSevere"_s, u"#202124"_s, u"#202124"_s);

    qCDebug(lcTheme) << "Legacy palette built:" << m_lightPalette.size() << "roles";
}

void ThemeManager::buildStylePalette()
{
    // ---- Material Redesign palettes -----------------------------------------
    // Verbatim from the design handoff (design/incoming/2026-07-11-claude,
    // PAL/ST tables): one M3 palette per UI style, plus a shared status set.
    // Overwrites the legacy roles built above so every existing Theme.color()
    // consumer restyles automatically.
    static const StylePalette styleLight[3] = {
        // A — Tonal Rail (purple)
        {u"#fbfaff"_s, u"#ffffff"_s, u"#f1eff9"_s, u"#e6e2f1"_s, u"#1b1b21"_s, u"#47464f"_s,
         u"#c7c5d4"_s, u"#e2e0ec"_s, u"#5646d6"_s, u"#ffffff"_s, u"#e3dfff"_s, u"#17106b"_s,
         QColor(27, 27, 33, 41)},
        // B — Split Dock (teal)
        {u"#f4f9f9"_s, u"#ffffff"_s, u"#e9efef"_s, u"#dee7e7"_s, u"#161d1d"_s, u"#3f4948"_s,
         u"#bec8c8"_s, u"#dbe4e4"_s, u"#00696d"_s, u"#ffffff"_s, u"#9cf0f5"_s, u"#002021"_s,
         QColor(22, 29, 29, 41)},
        // C — Card Flow (pink)
        {u"#fff8f8"_s, u"#ffffff"_s, u"#f8eef0"_s, u"#f0e2e6"_s, u"#22191c"_s, u"#514347"_s,
         u"#d6c2c6"_s, u"#ecdce0"_s, u"#8c4a60"_s, u"#ffffff"_s, u"#ffd9e2"_s, u"#3a071d"_s,
         QColor(34, 25, 28, 41)}
    };
    static const StylePalette styleDark[3] = {
        {u"#131318"_s, u"#1b1b21"_s, u"#23222b"_s, u"#2b2a35"_s, u"#e5e1ec"_s, u"#c7c5d4"_s,
         u"#47464f"_s, u"#31303a"_s, u"#c4c0ff"_s, u"#2a2380"_s, u"#433caf"_s, u"#e3dfff"_s,
         QColor(0, 0, 0, 140)},
        {u"#0e1414"_s, u"#161d1d"_s, u"#1e2626"_s, u"#263030"_s, u"#dde4e3"_s, u"#bec8c8"_s,
         u"#3f4948"_s, u"#2c3636"_s, u"#80d4d9"_s, u"#003739"_s, u"#005054"_s, u"#9cf0f5"_s,
         QColor(0, 0, 0, 140)},
        {u"#171114"_s, u"#211a1d"_s, u"#2b2225"_s, u"#352b2e"_s, u"#efdfe2"_s, u"#d6c2c6"_s,
         u"#5d4f53"_s, u"#3a3033"_s, u"#ffb1c8"_s, u"#541d32"_s, u"#713349"_s, u"#ffd9e2"_s,
         QColor(0, 0, 0, 140)}
    };
    static const StatusPalette statusLight
        {u"#1a7f37"_s, u"#cf222e"_s, u"#9a6700"_s, u"#8250df"_s, u"#6e7781"_s, u"#0969da"_s};
    static const StatusPalette statusDark
        {u"#3fb950"_s, u"#f85149"_s, u"#d29922"_s, u"#a371f7"_s, u"#8b949e"_s, u"#58a6ff"_s};

    const int style = static_cast<int>(m_uiStyle);
    const auto fill = [](QHash<QString, QColor> &palette, const StylePalette &p,
        const StatusPalette &st, const bool dark)
    {
        const auto put = [&palette](const QString &id, const QColor &color)
        {
            palette.insert(id, color);
        };
        const QColor pr = parseColor(p.pr);
        const QColor on = parseColor(p.on);
        const QColor success = parseColor(st.success);
        const QColor error = parseColor(st.error);
        const QColor warning = parseColor(st.warning);
        const QColor done = parseColor(st.done);
        const QColor info = parseColor(st.info);
        const qreal container = dark ? 0.18 : 0.12;

        // Primary family.
        put(u"primary"_s, pr);
        put(u"onPrimary"_s, parseColor(p.onPr));
        put(u"primaryContainer"_s, parseColor(p.pc));
        put(u"onPrimaryContainer"_s, parseColor(p.onPc));
        put(u"primaryHover"_s, pr);
        put(u"primaryPressed"_s, pr);
        put(u"primaryEmphasis"_s, pr);

        // Neutral secondary; tertiary carries the success family.
        put(u"secondary"_s, parseColor(p.onv));
        put(u"onSecondary"_s, parseColor(p.surf));
        put(u"secondaryContainer"_s, parseColor(p.sc));
        put(u"onSecondaryContainer"_s, parseColor(p.onv));
        put(u"tertiary"_s, success);
        put(u"onTertiary"_s, QColor(Qt::white));
        put(u"tertiaryContainer"_s, withAlpha(success, container));
        put(u"onTertiaryContainer"_s, success);

        // Surfaces / text.
        put(u"surface"_s, parseColor(p.surf));
        put(u"surfaceVariant"_s, parseColor(p.sc));
        put(u"surfaceContainerHigh"_s, parseColor(p.sc2));
        put(u"onSurface"_s, on);
        put(u"onSurfaceVariant"_s, parseColor(p.onv));
        put(u"secondaryText"_s, parseColor(p.onv));
        put(u"background"_s, parseColor(p.bg));
        put(u"onBackground"_s, on);

        // Lines / focus / depth.
        put(u"outline"_s, parseColor(p.ol));
        put(u"outlineVariant"_s, parseColor(p.olv));
        put(u"focusRing"_s, withAlpha(pr, dark ? 0.32 : 0.24));
        put(u"scrim"_s, QColor(0, 0, 0, dark ? 153 : 89));
        put(u"shadow"_s, p.shadow);

        // Hover overlays (the design's hov8/hov6).
        put(u"hoverStrong"_s, dark ? QColor(230, 225, 240, 26) : QColor(27, 27, 33, 20));
        put(u"hover"_s, dark ? QColor(230, 225, 240, 18) : QColor(27, 27, 33, 15));

        // Inverse (snackbar) surface.
        put(u"inverseSurface"_s, dark ? parseColor(u"#e5e1ec"_s) : parseColor(u"#313036"_s));
        put(u"inverseOnSurface"_s, dark ? parseColor(u"#1b1b21"_s) : parseColor(u"#f3eff4"_s));
        put(u"inversePrimary"_s, dark ? parseColor(u"#5646d6"_s) : parseColor(p.pc));

        // Status families (shared across styles).
        put(u"error"_s, error);
        put(u"onError"_s, QColor(Qt::white));
        put(u"errorContainer"_s, withAlpha(error, dark ? 0.18 : 0.10));
        put(u"onErrorContainer"_s, error);

        put(u"success"_s, success);
        put(u"onSuccess"_s, QColor(Qt::white));
        put(u"successContainer"_s, withAlpha(success, container));
        put(u"onSuccessContainer"_s, success);
        put(u"successEmphasis"_s, success);
        put(u"onSuccessEmphasis"_s, QColor(Qt::white));

        put(u"warning"_s, warning);
        put(u"onWarning"_s, QColor(Qt::white));
        put(u"warningContainer"_s, withAlpha(warning, container));
        put(u"onWarningContainer"_s, warning);

        put(u"done"_s, done);
        put(u"onDone"_s, QColor(Qt::white));
        put(u"doneContainer"_s, withAlpha(done, container));
        put(u"onDoneContainer"_s, done);

        put(u"info"_s, info);
        put(u"onInfo"_s, QColor(Qt::white));

        put(u"muted"_s, parseColor(p.onv));
        put(u"stateStopped"_s, parseColor(st.muted));
        put(u"severe"_s, warning);
        put(u"onSevere"_s, QColor(Qt::white));
    };

    fill(m_lightPalette, styleLight[style], statusLight, false);
    fill(m_darkPalette, styleDark[style], statusDark, true);
    applySeedColor();

    qCDebug(lcTheme) << "Style palette built for style" << m_uiStyle << ":"
        << m_lightPalette.size() << "roles";
}

void ThemeManager::applySeedColor()
{
    if (!m_seedColor.isValid())
        return;

    const auto apply = [this](QHash<QString, QColor> &palette, const bool dark)
    {
        QColor primary = dark ? m_seedColor.lighter(135) : m_seedColor;
        primary.setAlpha(255);
        const QColor onPrimary = qGray(primary.rgb()) < 145 ? QColor(Qt::white) : QColor(0x20, 0x21, 0x24);
        QColor container = dark ? primary.darker(210) : primary.lighter(185);
        container.setAlpha(255);
        palette.insert(u"primary"_s, primary);
        palette.insert(u"onPrimary"_s, onPrimary);
        palette.insert(u"primaryContainer"_s, container);
        palette.insert(u"onPrimaryContainer"_s,
            qGray(container.rgb()) < 145 ? QColor(Qt::white) : QColor(0x20, 0x21, 0x24));
        palette.insert(u"primaryHover"_s, dark ? primary.lighter(110) : primary.darker(110));
        palette.insert(u"primaryPressed"_s, dark ? primary.lighter(120) : primary.darker(120));
        palette.insert(u"primaryEmphasis"_s, primary);
        palette.insert(u"focusRing"_s, withAlpha(primary, dark ? 0.32 : 0.24));
    };
    apply(m_lightPalette, false);
    apply(m_darkPalette, true);
}

void ThemeManager::buildNamedIdMap()
{
    // Canonical design-token aliases. Resolution remains recursive so a user
    // override on either the semantic name (surfaceWarm) or its Material role
    // (primaryContainer) is honored without duplicating palette state.
    m_namedIdMap.insert(u"canvas"_s, u"background"_s);
    m_namedIdMap.insert(u"surfaceWarm"_s, u"primaryContainer"_s);
    m_namedIdMap.insert(u"selectedSurface"_s, u"primaryContainer"_s);
    m_namedIdMap.insert(u"foreground"_s, u"onSurface"_s);
    m_namedIdMap.insert(u"foregroundSecondary"_s, u"secondaryText"_s);
    m_namedIdMap.insert(u"border"_s, u"outline"_s);
    m_namedIdMap.insert(u"borderSoft"_s, u"outlineVariant"_s);
    m_namedIdMap.insert(u"accent"_s, u"primary"_s);
    m_namedIdMap.insert(u"accentOn"_s, u"onPrimary"_s);
    m_namedIdMap.insert(u"danger"_s, u"error"_s);
    m_namedIdMap.insert(u"onDanger"_s, u"onError"_s);
    m_namedIdMap.insert(u"dangerContainer"_s, u"errorContainer"_s);

    // Transfer-list row TEXT color per TorrentState (DESIGN_SYSTEM §1).
    m_namedIdMap.insert(u"ForcedDownloading"_s, u"success"_s);
    m_namedIdMap.insert(u"Downloading"_s, u"success"_s);
    m_namedIdMap.insert(u"ForcedDownloadingMetadata"_s, u"success"_s);
    m_namedIdMap.insert(u"DownloadingMetadata"_s, u"success"_s);
    m_namedIdMap.insert(u"StalledDownloading"_s, u"successEmphasis"_s);
    m_namedIdMap.insert(u"ForcedUploading"_s, u"primary"_s);
    m_namedIdMap.insert(u"Uploading"_s, u"primary"_s);
    m_namedIdMap.insert(u"StalledUploading"_s, u"primaryEmphasis"_s);
    m_namedIdMap.insert(u"CheckingResumeData"_s, u"success"_s);
    m_namedIdMap.insert(u"QueuedDownloading"_s, u"warning"_s);
    m_namedIdMap.insert(u"QueuedUploading"_s, u"warning"_s);
    m_namedIdMap.insert(u"CheckingUploading"_s, u"success"_s);
    m_namedIdMap.insert(u"CheckingDownloading"_s, u"success"_s);
    m_namedIdMap.insert(u"StoppedDownloading"_s, u"stateStopped"_s);
    m_namedIdMap.insert(u"StoppedUploading"_s, u"done"_s);
    m_namedIdMap.insert(u"Moving"_s, u"success"_s);
    m_namedIdMap.insert(u"MissingFiles"_s, u"error"_s);
    m_namedIdMap.insert(u"Error"_s, u"error"_s);
    m_namedIdMap.insert(u"Unknown"_s, u"muted"_s);

    // Execution-log line colors.
    m_namedIdMap.insert(u"Log.TimeStamp"_s, u"muted"_s);
    m_namedIdMap.insert(u"Log.Info"_s, u"info"_s);
    m_namedIdMap.insert(u"Log.Normal"_s, u"onSurface"_s);
    m_namedIdMap.insert(u"Log.Warning"_s, u"severe"_s);
    m_namedIdMap.insert(u"Log.Critical"_s, u"error"_s);
    m_namedIdMap.insert(u"Log.BannedPeer"_s, u"error"_s);

    // RSS article colors.
    m_namedIdMap.insert(u"RSS.UnreadArticle"_s, u"primary"_s);
    m_namedIdMap.insert(u"RSS.ReadArticle"_s, u"muted"_s);

    // Pieces bar.
    m_namedIdMap.insert(u"PiecesBar.Piece"_s, u"primary"_s);
    m_namedIdMap.insert(u"PiecesBar.PartialPiece"_s, u"primaryContainer"_s);
    m_namedIdMap.insert(u"PiecesBar.MissingPiece"_s, u"surfaceVariant"_s);
    m_namedIdMap.insert(u"PiecesBar.Border"_s, u"outlineVariant"_s);

    qCDebug(lcTheme) << "Named-id map built:" << m_namedIdMap.size() << "entries";
}
