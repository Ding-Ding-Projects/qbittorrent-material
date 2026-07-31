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

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantMap>

QT_BEGIN_NAMESPACE
class QJSEngine;
QT_END_NAMESPACE

namespace Utils::I18n
{
    class FunnyTranslator;
}

/**
 * @file i18ncontroller.h
 * @brief The @c I18n QML singleton — runtime language state + live retranslate.
 *
 * QML reads/writes the language and two independent voice levels. A change
 * updates the app-owned FunnyTranslator, calls @c QQmlEngine::retranslate()
 * (so every live @c qsTr binding updates with no restart), and persists all
 * three bounded settings.
 *
 * @code
 *   ComboBox {
 *       model: [ I18n.displayName(0), I18n.displayName(1), I18n.displayName(2) ]
 *       onActivated: (i) => OptionsController.setValue("language", i)
 *   }
 * @endcode
 */
class I18n : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(Language language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString languageName READ languageName NOTIFY languageChanged)
    Q_PROPERTY(int englishFunnyLevel READ englishFunnyLevel WRITE setEnglishFunnyLevel
               NOTIFY englishFunnyLevelChanged)
    Q_PROPERTY(int cantoneseFunnyLevel READ cantoneseFunnyLevel WRITE setCantoneseFunnyLevel
               NOTIFY cantoneseFunnyLevelChanged)
    Q_PROPERTY(int catalogEntryCount READ catalogEntryCount CONSTANT)
    Q_PROPERTY(QStringList catalogPlaceholderMismatchKeys
               READ catalogPlaceholderMismatchKeys CONSTANT)

public:
    /// Enum values are stable and mirror FunnyTranslator::Mode / the persisted
    /// @c Appearance/Language integer.
    enum Language
    {
        English = 0,
        Cantonese = 1,
        Bilingual = 2
    };
    Q_ENUM(Language)

    /// QML singleton factory. Adopts Application's already-installed translator,
    /// restores persisted settings, and remembers @p engine for live retranslate.
    static I18n *create(QQmlEngine *engine, QJSEngine *scriptEngine);

    explicit I18n(QQmlEngine *engine = nullptr, QObject *parent = nullptr);
    ~I18n() override;

    Language language() const { return m_language; }
    int englishFunnyLevel() const { return m_englishFunnyLevel; }
    int cantoneseFunnyLevel() const { return m_cantoneseFunnyLevel; }
    int catalogEntryCount() const;
    QStringList catalogPlaceholderMismatchKeys() const;
    /// Localized (endonym) display name of the *current* language.
    QString languageName() const;

    /// Switch language: log, flip translator mode, retranslate, persist, notify.
    Q_INVOKABLE void setLanguage(Language lang);

    /// Independently tune each language's voice from 1 (professional) through
    /// 5 (maximum playfulness). Invalid values are clamped safely.
    Q_INVOKABLE void setEnglishFunnyLevel(int level);
    Q_INVOKABLE void setCantoneseFunnyLevel(int level);
    Q_INVOKABLE void setFunnyLevels(int englishLevel, int cantoneseLevel);
    Q_INVOKABLE void resetFunnyLevels();

    /// Atomically apply all three controls with one live QML retranslation.
    /// This is the Options dialog's Apply/OK bridge.
    Q_INVOKABLE void setLanguageSettings(int language, int englishFunnyLevel,
                                         int cantoneseFunnyLevel);

    /// Endonym display name for an arbitrary language (used by the selector).
    Q_INVOKABLE QString displayName(Language lang) const;

    /// Programmatic translate — same result as @c qsTr for the given English.
    Q_INVOKABLE QString t(const QString &english) const;

    /// Build/test hook for comparing extracted source literals with the bundled
    /// catalog. The map includes counts, missing keys and placeholder failures.
    Q_INVOKABLE QVariantMap catalogParity(const QStringList &englishSourceTexts) const;

signals:
    void languageChanged();
    void englishFunnyLevelChanged();
    void cantoneseFunnyLevelChanged();

private:
    void applyTranslatorState(bool retranslate);

    QQmlEngine *m_engine = nullptr;
    QPointer<Utils::I18n::FunnyTranslator> m_translator; ///< shared app translator
    bool m_ownsTranslator = false; ///< fallback for non-Application test hosts
    Language m_language = English;
    int m_englishFunnyLevel = 1;
    int m_cantoneseFunnyLevel = 3;

    static I18n *s_instance;
};
