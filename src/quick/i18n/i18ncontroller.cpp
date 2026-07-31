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

#include "i18ncontroller.h"

#include <QCoreApplication>
#include <QSet>

#include "app/application.h"
#include "base/logging.h"
#include "base/preferences.h"
#include "funnytranslator.h"

using Utils::I18n::FunnyTranslator;

namespace
{
    const QString kEnglishFunnyLevelKey = QStringLiteral("Appearance/EnglishFunnyLevel");
    const QString kCantoneseFunnyLevelKey = QStringLiteral("Appearance/CantoneseFunnyLevel");

    FunnyTranslator::Mode toMode(const I18n::Language lang)
    {
        switch (lang)
        {
        case I18n::Cantonese: return FunnyTranslator::Mode::Cantonese;
        case I18n::Bilingual: return FunnyTranslator::Mode::Bilingual;
        case I18n::English:   break;
        }
        return FunnyTranslator::Mode::English;
    }

    I18n::Language clampLanguage(const int raw)
    {
        if ((raw >= I18n::English) && (raw <= I18n::Bilingual))
            return static_cast<I18n::Language>(raw);
        return I18n::English;
    }
}

I18n *I18n::s_instance = nullptr;

I18n *I18n::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(scriptEngine)

    if (s_instance != nullptr)
    {
        qCDebug(lcI18n) << "I18n::create returning existing instance";
        return s_instance;
    }

    // CppOwnership prevents JavaScript GC from deleting the singleton, while
    // the engine parent gives it a deterministic shutdown before Application
    // removes the shared translator.
    s_instance = new I18n(engine, engine);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

I18n::I18n(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    qCInfo(lcI18n) << "I18n controller initializing";

    // Application installs the translator before Main.qml loads. Adopt that
    // exact instance so a stale second translator can never participate in Qt's
    // fallback chain. Standalone tests still get a safe owned fallback.
    if (Application *app = Application::instance())
        m_translator = qobject_cast<FunnyTranslator *>(app->runtimeTranslator());

    if (m_translator != nullptr)
    {
        qCInfo(lcI18n) << "I18n adopted Application's pre-QML FunnyTranslator";
    }
    else
    {
        qCWarning(lcI18n) << "Application translator unavailable; installing I18n fallback";
        m_translator = new FunnyTranslator(this);
        m_ownsTranslator = true;
        QCoreApplication::installTranslator(m_translator);
    }

    // Restore the three bounded, persisted controls.
    if (Preferences *preferences = Preferences::instance())
    {
        m_language = clampLanguage(preferences->getLanguageMode());
        m_englishFunnyLevel = FunnyTranslator::clampFunnyLevel(
            preferences->value(kEnglishFunnyLevelKey,
                FunnyTranslator::DefaultEnglishFunnyLevel).toInt());
        m_cantoneseFunnyLevel = FunnyTranslator::clampFunnyLevel(
            preferences->value(kCantoneseFunnyLevelKey,
                FunnyTranslator::DefaultCantoneseFunnyLevel).toInt());
    }

    applyTranslatorState(false);

    qCInfo(lcI18n) << "I18n ready; language:" << displayName(m_language)
                   << "funny levels:" << m_englishFunnyLevel << m_cantoneseFunnyLevel
                   << "catalog entries:" << catalogEntryCount();
}

I18n::~I18n()
{
    if (m_ownsTranslator && (m_translator != nullptr))
        QCoreApplication::removeTranslator(m_translator);
    if (s_instance == this)
        s_instance = nullptr;
}

QString I18n::languageName() const
{
    return displayName(m_language);
}

QString I18n::displayName(const Language lang) const
{
    // Endonyms — always shown in their own script so all three are legible
    // regardless of the currently active language.
    switch (lang)
    {
    case Cantonese: return QString::fromUtf8("廣東話");
    case Bilingual: return QString::fromUtf8("English · 廣東話");
    case English:   break;
    }
    return QStringLiteral("English");
}

void I18n::setLanguage(const Language lang)
{
    setLanguageSettings(int(lang), m_englishFunnyLevel, m_cantoneseFunnyLevel);
}

void I18n::setEnglishFunnyLevel(const int level)
{
    setLanguageSettings(int(m_language), level, m_cantoneseFunnyLevel);
}

void I18n::setCantoneseFunnyLevel(const int level)
{
    setLanguageSettings(int(m_language), m_englishFunnyLevel, level);
}

void I18n::setFunnyLevels(const int englishLevel, const int cantoneseLevel)
{
    setLanguageSettings(int(m_language), englishLevel, cantoneseLevel);
}

void I18n::resetFunnyLevels()
{
    setFunnyLevels(FunnyTranslator::DefaultEnglishFunnyLevel,
                   FunnyTranslator::DefaultCantoneseFunnyLevel);
}

void I18n::setLanguageSettings(const int language, const int englishFunnyLevel,
                               const int cantoneseFunnyLevel)
{
    const Language safeLanguage = clampLanguage(language);
    const int safeEnglishLevel = FunnyTranslator::clampFunnyLevel(englishFunnyLevel);
    const int safeCantoneseLevel = FunnyTranslator::clampFunnyLevel(cantoneseFunnyLevel);

    const bool didLanguageChange = (m_language != safeLanguage);
    const bool didEnglishLevelChange = (m_englishFunnyLevel != safeEnglishLevel);
    const bool didCantoneseLevelChange = (m_cantoneseFunnyLevel != safeCantoneseLevel);
    if (!didLanguageChange && !didEnglishLevelChange && !didCantoneseLevelChange)
        return;

    qCInfo(lcI18n) << "Language settings change:"
                   << int(m_language) << m_englishFunnyLevel << m_cantoneseFunnyLevel
                   << "->" << int(safeLanguage) << safeEnglishLevel << safeCantoneseLevel;

    m_language = safeLanguage;
    m_englishFunnyLevel = safeEnglishLevel;
    m_cantoneseFunnyLevel = safeCantoneseLevel;
    applyTranslatorState(true);

    if (Preferences *preferences = Preferences::instance())
    {
        preferences->setLanguageMode(int(m_language));
        preferences->setValue(kEnglishFunnyLevelKey, m_englishFunnyLevel);
        preferences->setValue(kCantoneseFunnyLevelKey, m_cantoneseFunnyLevel);
    }
    else
    {
        qCWarning(lcI18n) << "Preferences unavailable; language settings not persisted";
    }

    if (didLanguageChange)
        emit languageChanged();
    if (didEnglishLevelChange)
        emit englishFunnyLevelChanged();
    if (didCantoneseLevelChange)
        emit cantoneseFunnyLevelChanged();
}

void I18n::applyTranslatorState(const bool retranslate)
{
    if (m_translator == nullptr)
    {
        qCWarning(lcI18n) << "Cannot apply language settings without a translator";
        return;
    }

    m_translator->setMode(toMode(m_language));
    m_translator->setFunnyLevels(m_englishFunnyLevel, m_cantoneseFunnyLevel);

    // Re-evaluate every live qsTr binding without an application restart.
    if (retranslate && (m_engine != nullptr))
        m_engine->retranslate();
    else if (retranslate)
        qCWarning(lcI18n) << "No QQmlEngine stored; cannot retranslate live bindings";
}

QString I18n::t(const QString &english) const
{
    if (m_translator != nullptr)
    {
        const QString translated =
            m_translator->translate(nullptr, english.toUtf8().constData(), nullptr, -1);
        if (!translated.isEmpty())
            return translated;
    }
    return english;
}

int I18n::catalogEntryCount() const
{
    return (m_translator != nullptr) ? m_translator->entryCount() : 0;
}

QStringList I18n::catalogPlaceholderMismatchKeys() const
{
    return (m_translator != nullptr)
        ? m_translator->placeholderMismatchKeys() : QStringList();
}

QVariantMap I18n::catalogParity(const QStringList &englishSourceTexts) const
{
    QStringList missing;
    QStringList placeholderMismatches;
    if (m_translator != nullptr)
    {
        missing = m_translator->missingCatalogEntries(englishSourceTexts);
        placeholderMismatches = m_translator->placeholderMismatchKeys();
    }

    QSet<QString> uniqueExpected;
    for (const QString &sourceText : englishSourceTexts)
    {
        if (!sourceText.isEmpty() && !sourceText.startsWith(QLatin1Char('_')))
            uniqueExpected.insert(sourceText);
    }

    return {
        {QStringLiteral("expectedCount"), uniqueExpected.size()},
        {QStringLiteral("catalogEntryCount"), catalogEntryCount()},
        {QStringLiteral("missingCount"), missing.size()},
        {QStringLiteral("missing"), missing},
        {QStringLiteral("placeholderMismatchCount"), placeholderMismatches.size()},
        {QStringLiteral("placeholderMismatches"), placeholderMismatches},
        {QStringLiteral("complete"), missing.isEmpty() && placeholderMismatches.isEmpty()}
    };
}
