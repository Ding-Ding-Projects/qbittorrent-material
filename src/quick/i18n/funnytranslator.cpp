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

#include "funnytranslator.h"

#include <algorithm>

#include <QByteArray>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLatin1String>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>

#include "base/logging.h"

namespace
{
    /// Thin separator between the English and Cantonese halves in Bilingual mode.
    const QString kBilingualSeparator = QStringLiteral(" · "); // " · "

    /// Candidate resource/file locations for the catalog, tried in order. The
    /// exact resource prefix depends on how qt_add_qml_module packaged it.
    const QStringList kCatalogCandidates = {
        QStringLiteral(":/i18n/cantonese.json"),
        QStringLiteral(":/qt/qml/qBittorrent/i18n/cantonese.json"),
        QStringLiteral(":/resources/i18n/cantonese.json"),
        QStringLiteral(":/qbittorrent/i18n/cantonese.json")
    };

    /// Qt placeholders (%1, %L1, %n) and qBittorrent's documented one-letter
    /// external-program placeholders (%N, %F, ...). A translation which drops
    /// or adds one is unsafe, so it is excluded and falls back to English.
    QStringList placeholderTokens(const QString &text)
    {
        static const QRegularExpression placeholder(
            QStringLiteral("%(?:L?\\d+|n|[A-Z])"));

        QStringList result;
        auto match = placeholder.globalMatch(text);
        while (match.hasNext())
            result.append(match.next().captured());
        std::sort(result.begin(), result.end());
        return result;
    }

    /// The bundled catalog intentionally uses lively Hong Kong colloquialisms.
    /// Level 1 applies a conservative terminology pass so the same factual
    /// translation reads professionally without maintaining a second catalog.
    /// Replacements never touch numbers, URLs, or placeholder tokens.
    QString professionalCantonese(const QString &text)
    {
        static const QList<QPair<QString, QString>> replacements = {
            {QString::fromUtf8("求其揀"), QString::fromUtf8("隨機選擇")},
            {QString::fromUtf8("剷晒"), QString::fromUtf8("全部移除")},
            {QString::fromUtf8("剷咗"), QString::fromUtf8("移除")},
            {QString::fromUtf8("搞掂"), QString::fromUtf8("完成")},
            {QString::fromUtf8("落嘢"), QString::fromUtf8("下載")},
            {QString::fromUtf8("上嘢"), QString::fromUtf8("上載")},
            {QString::fromUtf8("閃人"), QString::fromUtf8("退出")},
            {QString::fromUtf8("開波"), QString::fromUtf8("開始")},
            {QString::fromUtf8("街坊"), QString::fromUtf8("節點")},
            {QString::fromUtf8("求其"), QString::fromUtf8("任意")},
            {QString::fromUtf8("搵"), QString::fromUtf8("搜尋")},
            {QString::fromUtf8("睇"), QString::fromUtf8("查看")},
            {QString::fromUtf8("剷"), QString::fromUtf8("移除")},
            {QString::fromUtf8("嘥"), QString::fromUtf8("浪費")},
            {QString::fromUtf8("冇"), QString::fromUtf8("沒有")},
            {QString::fromUtf8("唔"), QString::fromUtf8("不")},
            {QString::fromUtf8("喺"), QString::fromUtf8("在")},
            {QString::fromUtf8("嘅"), QString::fromUtf8("的")},
            {QString::fromUtf8("咗"), QString::fromUtf8("了")},
            {QString::fromUtf8("佢"), QString::fromUtf8("它")},
            {QString::fromUtf8("㗎"), QString()},
            {QString::fromUtf8("喇"), QString()},
            {QString::fromUtf8("喎"), QString()}
        };

        QString result = text;
        for (const auto &[colloquial, professional] : replacements)
            result.replace(colloquial, professional);
        return result;
    }
}

namespace Utils::I18n
{
    FunnyTranslator::FunnyTranslator(QObject *parent)
        : QTranslator(parent)
    {
        qCDebug(lcI18n) << "FunnyTranslator constructing; probing catalog locations";
        bool loaded = false;
        for (const QString &path : kCatalogCandidates)
        {
            if (QFile::exists(path) && loadCatalog(path))
            {
                loaded = true;
                break;
            }
        }
        if (!loaded)
            qCWarning(lcI18n) << "FunnyTranslator: no Cantonese catalog found; "
                                 "Cantonese/Bilingual modes will fall back to English";
    }

    void FunnyTranslator::setMode(const Mode mode)
    {
        if (m_mode == mode)
        {
            qCDebug(lcI18n) << "FunnyTranslator::setMode no-op; already in mode" << int(mode);
            return;
        }
        qCInfo(lcI18n) << "FunnyTranslator mode changed:" << int(m_mode) << "->" << int(mode);
        m_mode = mode;
    }

    int FunnyTranslator::clampFunnyLevel(const int level)
    {
        return std::clamp(level, MinFunnyLevel, MaxFunnyLevel);
    }

    void FunnyTranslator::setEnglishFunnyLevel(const int level)
    {
        const int clamped = clampFunnyLevel(level);
        if (m_englishFunnyLevel == clamped)
            return;

        qCInfo(lcI18n) << "English funny level changed:"
                       << m_englishFunnyLevel << "->" << clamped;
        m_englishFunnyLevel = clamped;
    }

    void FunnyTranslator::setCantoneseFunnyLevel(const int level)
    {
        const int clamped = clampFunnyLevel(level);
        if (m_cantoneseFunnyLevel == clamped)
            return;

        qCInfo(lcI18n) << "Cantonese funny level changed:"
                       << m_cantoneseFunnyLevel << "->" << clamped;
        m_cantoneseFunnyLevel = clamped;
    }

    void FunnyTranslator::setFunnyLevels(const int englishLevel, const int cantoneseLevel)
    {
        setEnglishFunnyLevel(englishLevel);
        setCantoneseFunnyLevel(cantoneseLevel);
    }

    bool FunnyTranslator::loadCatalog(const QString &jsonPath)
    {
        QFile file(jsonPath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        {
            qCWarning(lcI18n) << "Cannot open Cantonese catalog:" << jsonPath << file.errorString();
            return false;
        }

        const QByteArray raw = file.readAll();
        file.close();

        QJsonParseError parseError {};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &parseError);
        if (parseError.error != QJsonParseError::NoError || !doc.isObject())
        {
            qCWarning(lcI18n) << "Malformed Cantonese catalog:" << jsonPath
                              << parseError.errorString();
            return false;
        }

        m_enToYue.clear();
        m_placeholderMismatchKeys.clear();
        const QJsonObject obj = doc.object();
        for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
        {
            // Underscore-prefixed entries are catalog metadata, not literals.
            if (it.key().startsWith(QLatin1Char('_')) || !it.value().isString())
                continue;

            const QString translated = it.value().toString();
            if (it.key().isEmpty() || translated.isEmpty())
                continue;

            if (placeholderTokens(it.key()) != placeholderTokens(translated))
            {
                m_placeholderMismatchKeys.append(it.key());
                qCWarning(lcI18n) << "Ignoring unsafe Cantonese catalog entry with "
                                     "placeholder mismatch:" << it.key();
                continue;
            }

            m_enToYue.insert(it.key(), translated);
        }

        std::sort(m_placeholderMismatchKeys.begin(), m_placeholderMismatchKeys.end());

        qCInfo(lcI18n) << "Loaded Cantonese catalog:" << jsonPath
                       << "with" << m_enToYue.size() << "entries and"
                       << m_placeholderMismatchKeys.size() << "placeholder mismatch(es)";
        return true;
    }

    bool FunnyTranslator::hasCatalogEntry(const QString &english) const
    {
        return m_enToYue.contains(english);
    }

    QStringList FunnyTranslator::catalogKeys() const
    {
        QStringList keys = m_enToYue.keys();
        std::sort(keys.begin(), keys.end());
        return keys;
    }

    QStringList FunnyTranslator::missingCatalogEntries(
        const QStringList &englishSourceTexts) const
    {
        QSet<QString> missing;
        for (const QString &sourceText : englishSourceTexts)
        {
            if (!sourceText.isEmpty() && !sourceText.startsWith(QLatin1Char('_'))
                    && !m_enToYue.contains(sourceText))
            {
                missing.insert(sourceText);
            }
        }

        QStringList result(missing.begin(), missing.end());
        std::sort(result.begin(), result.end());
        return result;
    }

    QString FunnyTranslator::styledText(const QString &text, const int level,
                                        const bool cantonese)
    {
        if (text.isEmpty())
            return text;

        if (clampFunnyLevel(level) == MinFunnyLevel)
            return cantonese ? professionalCantonese(text) : text;

        // Compact, language-specific voice markers make every message category
        // respond to the user's level without changing facts, placeholders, or
        // actions. This is deliberately suffix-only so labels and bilingual
        // strings remain readable at narrow widths.
        switch (clampFunnyLevel(level))
        {
        case 2: return text + QString::fromUtf8(" 🙂");
        case 3: return text + QString::fromUtf8(" ✨");
        case 4: return text + (cantonese
            ? QString::fromUtf8(" 😄✨") : QString::fromUtf8(" 🎉"));
        case 5: return text + (cantonese
            ? QString::fromUtf8(" 🥟✨") : QString::fromUtf8(" 🥟🎉"));
        default: break;
        }
        return text;
    }

    QString FunnyTranslator::translate(const char *context, const char *sourceText,
                                       const char *disambiguation, int n) const
    {
        Q_UNUSED(context)
        Q_UNUSED(disambiguation)
        Q_UNUSED(n)

        if (sourceText == nullptr)
            return {};

        const QString en = QString::fromUtf8(sourceText);
        switch (m_mode)
        {
        case Mode::English:
            // At level 1, empty lets Qt use the untouched source literal.
            return (m_englishFunnyLevel == MinFunnyLevel)
                ? QString() : styledText(en, m_englishFunnyLevel, false);

        case Mode::Cantonese:
        {
            const auto it = m_enToYue.constFind(en);
            // Missing/unsafe catalog entries fall back to factual English.
            return (it == m_enToYue.constEnd())
                ? QString() : styledText(it.value(), m_cantoneseFunnyLevel, true);
        }

        case Mode::Bilingual:
        {
            const auto it = m_enToYue.constFind(en);
            if (it == m_enToYue.constEnd())
            {
                return (m_englishFunnyLevel == MinFunnyLevel)
                    ? QString() : styledText(en, m_englishFunnyLevel, false);
            }
            return styledText(en, m_englishFunnyLevel, false)
                + kBilingualSeparator
                + styledText(it.value(), m_cantoneseFunnyLevel, true);
        }
        }

        return {};
    }
}
