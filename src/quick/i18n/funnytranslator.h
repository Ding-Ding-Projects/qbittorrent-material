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

#include <QHash>
#include <QString>
#include <QStringList>
#include <QTranslator>

namespace Utils::I18n
{
    /**
     * @brief A non-.ts custom translator implementing the three funny modes.
     *
     * Translation is driven by a flat English->Cantonese JSON catalog
     * (@c :/i18n/cantonese.json) instead of Qt @c .qm files. The English
     * literal passed to @c qsTr()/tr() *is* the lookup key.
     *
     * Modes (see translate()):
     *  - English   : original literal at level 1; compact voice styling at 2..5.
     *  - Cantonese : 港式口語 catalog with level-1 professional normalization.
     *  - Bilingual : compact @c "English · Cantonese" runtime composition.
     * Missing or placeholder-unsafe entries always fall back to factual English.
     */
    class FunnyTranslator final : public QTranslator
    {
        Q_OBJECT

    public:
        enum class Mode
        {
            English = 0,
            Cantonese = 1,
            Bilingual = 2
        };
        Q_ENUM(Mode)

        static constexpr int MinFunnyLevel = 1;
        static constexpr int MaxFunnyLevel = 5;
        static constexpr int DefaultEnglishFunnyLevel = 1;
        static constexpr int DefaultCantoneseFunnyLevel = 3;

        explicit FunnyTranslator(QObject *parent = nullptr);

        /// Switch active mode. The caller triggers QQmlEngine::retranslate()
        /// after applying mode and voice levels as one atomic state change.
        void setMode(Mode mode);
        Mode mode() const { return m_mode; }

        /// Set the independently persisted voice levels. Values outside the
        /// public 1..5 range are clamped so corrupt settings remain harmless.
        void setEnglishFunnyLevel(int level);
        void setCantoneseFunnyLevel(int level);
        void setFunnyLevels(int englishLevel, int cantoneseLevel);
        int englishFunnyLevel() const { return m_englishFunnyLevel; }
        int cantoneseFunnyLevel() const { return m_cantoneseFunnyLevel; }
        static int clampFunnyLevel(int level);

        /// (Re)load the English->Cantonese catalog from a JSON file/resource.
        /// Returns true on success. Multiple candidate paths are tried by the
        /// constructor; call this only to point at a custom catalog.
        bool loadCatalog(const QString &jsonPath);

        /// Number of loaded catalog entries (diagnostics/logging).
        int entryCount() const { return m_enToYue.size(); }

        /// Programmatic catalog-parity hooks used by build/tests. Metadata keys
        /// (leading underscore) are deliberately excluded from the catalog.
        bool hasCatalogEntry(const QString &english) const;
        QStringList catalogKeys() const;
        QStringList missingCatalogEntries(const QStringList &englishSourceTexts) const;
        QStringList placeholderMismatchKeys() const { return m_placeholderMismatchKeys; }

        /// MUST be false so Qt actually calls translate() for every string.
        bool isEmpty() const override { return false; }

        /// Qt calls this for every qsTr()/tr(). @p sourceText is the English key.
        QString translate(const char *context, const char *sourceText,
                          const char *disambiguation = nullptr, int n = -1) const override;

    private:
        static QString styledText(const QString &text, int level, bool cantonese);

        QHash<QString, QString> m_enToYue; ///< English literal -> Cantonese
        QStringList m_placeholderMismatchKeys;
        Mode m_mode = Mode::English;
        int m_englishFunnyLevel = DefaultEnglishFunnyLevel;
        int m_cantoneseFunnyLevel = DefaultCantoneseFunnyLevel;
    };
}
