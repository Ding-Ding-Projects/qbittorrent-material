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

#include "narratorcontroller.h"

#include <QAudioOutput>
#include <QJSEngine>
#include <QMediaPlayer>
#include <QProcess>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#include "base/logging.h"
#include "base/preferences.h"
#include "base/utils/foreignapps.h"
#include "base/utils/fs.h"

using namespace Qt::StringLiterals;

namespace
{
    const QString kEnabledKey = u"Preferences/Narrator/Enabled"_s;
    const QString kLanguageKey = u"Preferences/Narrator/LanguageMode"_s;
    const QString kEnglishVoiceKey = u"Preferences/Narrator/EnglishVoice"_s;
    const QString kCantoneseVoiceKey = u"Preferences/Narrator/CantoneseVoice"_s;
    const QString kVolumeKey = u"Preferences/Narrator/Volume"_s;
    const QString kQuietKey = u"Preferences/Narrator/QuietHours"_s;

    const QString kDefaultEnglishVoice = u"en-US-AriaNeural"_s;
    // A Hong Kong voice for the Cantonese track, per the language requirement —
    // a Mandarin voice reading Cantonese text is not the same feature.
    const QString kDefaultCantoneseVoice = u"zh-HK-HiuMaanNeural"_s;

    /// Narration stays infrequent: nothing repeats within its category's
    /// cooldown, and nothing at all follows another line too closely.
    constexpr int CategoryCooldownMs = 15000;
    constexpr int GlobalDebounceMs = 1200;

    /// A line longer than this is truncated before synthesis: narration is a
    /// notification, not a document reader, and an unbounded line would hold
    /// the single player for minutes.
    constexpr int MaxSpokenChars = 300;

    /// Synthesis is a network round trip; give it a bound so a hung request
    /// cannot wedge the queue forever.
    constexpr int SynthesisTimeoutMs = 20000;
}

NarratorController *NarratorController::s_instance = nullptr;

NarratorController::NarratorController(QObject *parent)
    : QObject(parent)
    , m_englishVoice(kDefaultEnglishVoice)
    , m_cantoneseVoice(kDefaultCantoneseVoice)
{
    loadSettings();
    qCInfo(lcUi) << "NarratorController constructed; enabled =" << m_enabled;
}

NarratorController::~NarratorController()
{
    stop();
    delete m_mediaDir;
}

NarratorController *NarratorController::create(QQmlEngine *, QJSEngine *)
{
    NarratorController *controller = instance();
    QJSEngine::setObjectOwnership(controller, QJSEngine::CppOwnership);
    return controller;
}

NarratorController *NarratorController::instance()
{
    if (!s_instance)
        s_instance = new NarratorController;
    return s_instance;
}

void NarratorController::loadSettings()
{
    auto *pref = Preferences::instance();
    // Off by default. The narrator is opt-in, so a fresh profile is silent.
    m_enabled = pref->value(kEnabledKey, false).toBool();
    m_languageMode = qBound(static_cast<int>(English),
        pref->value(kLanguageKey, static_cast<int>(English)).toInt(),
        static_cast<int>(Both));
    m_englishVoice = pref->value(kEnglishVoiceKey, kDefaultEnglishVoice).toString();
    m_cantoneseVoice = pref->value(kCantoneseVoiceKey, kDefaultCantoneseVoice).toString();
    m_volume = qBound<qreal>(0.0, pref->value(kVolumeKey, 0.7).toDouble(), 1.0);
    m_quietHours = pref->value(kQuietKey, false).toBool();
}

void NarratorController::persist(const QString &key, const QVariant &value)
{
    Preferences::instance()->setValue(key, value);
    Preferences::instance()->apply();
}

void NarratorController::setEnabled(const bool enabled)
{
    if (m_enabled == enabled)
        return;

    m_enabled = enabled;
    persist(kEnabledKey, enabled);
    qCInfo(lcUi) << "Narrator enabled ->" << enabled;

    if (!enabled)
        stop();

    emit settingsChanged();
    emit availabilityChanged();
}

void NarratorController::setLanguageMode(const int mode)
{
    if ((m_languageMode == mode) || (mode < English) || (mode > Both))
        return;
    m_languageMode = mode;
    persist(kLanguageKey, mode);
    emit settingsChanged();
}

void NarratorController::setEnglishVoice(const QString &voice)
{
    if (m_englishVoice == voice)
        return;
    m_englishVoice = voice;
    persist(kEnglishVoiceKey, voice);
    emit settingsChanged();
}

void NarratorController::setCantoneseVoice(const QString &voice)
{
    if (m_cantoneseVoice == voice)
        return;
    m_cantoneseVoice = voice;
    persist(kCantoneseVoiceKey, voice);
    emit settingsChanged();
}

void NarratorController::setVolume(const qreal volume)
{
    const qreal clamped = qBound(0.0, volume, 1.0);
    if (qFuzzyCompare(m_volume, clamped))
        return;
    m_volume = clamped;
    persist(kVolumeKey, clamped);
    if (m_audioOutput)
        m_audioOutput->setVolume(static_cast<float>(clamped));
    emit settingsChanged();
}

void NarratorController::setQuietHours(const bool quiet)
{
    if (m_quietHours == quiet)
        return;
    m_quietHours = quiet;
    persist(kQuietKey, quiet);
    if (quiet)
        stop();
    emit settingsChanged();
}

QVariantList NarratorController::englishVoices() const
{
    return {
        QVariantMap {{u"id"_s, u"en-US-AriaNeural"_s}, {u"name"_s, tr("Aria (US, female)")}},
        QVariantMap {{u"id"_s, u"en-US-GuyNeural"_s}, {u"name"_s, tr("Guy (US, male)")}},
        QVariantMap {{u"id"_s, u"en-GB-SoniaNeural"_s}, {u"name"_s, tr("Sonia (UK, female)")}},
        QVariantMap {{u"id"_s, u"en-GB-RyanNeural"_s}, {u"name"_s, tr("Ryan (UK, male)")}},
        QVariantMap {{u"id"_s, u"en-AU-NatashaNeural"_s}, {u"name"_s, tr("Natasha (AU, female)")}}
    };
}

QVariantList NarratorController::cantoneseVoices() const
{
    // Hong Kong Cantonese only. A Mandarin voice reading Cantonese copy would
    // be a different language spoken over the user's text.
    return {
        QVariantMap {{u"id"_s, u"zh-HK-HiuMaanNeural"_s}, {u"name"_s, tr("HiuMaan 曉曼 (female)")}},
        QVariantMap {{u"id"_s, u"zh-HK-HiuGaaiNeural"_s}, {u"name"_s, tr("HiuGaai 曉佳 (female)")}},
        QVariantMap {{u"id"_s, u"zh-HK-WanLungNeural"_s}, {u"name"_s, tr("WanLung 雲龍 (male)")}}
    };
}

bool NarratorController::yieldingToAssistiveTech() const
{
    // A screen reader is already speaking the interface; narrating over it
    // leaves both unintelligible, so the narrator yields rather than competes.
#ifdef Q_OS_WIN
    BOOL screenReaderRunning = FALSE;
    if (::SystemParametersInfoW(SPI_GETSCREENREADER, 0, &screenReaderRunning, 0)
        && screenReaderRunning)
    {
        return true;
    }
#endif
    return false;
}

bool NarratorController::cooldownBlocks(const QString &category) const
{
    const QDateTime now = QDateTime::currentDateTimeUtc();

    if (m_lastSpokenAt.isValid()
        && (m_lastSpokenAt.msecsTo(now) < GlobalDebounceMs))
    {
        return true;
    }

    const auto it = m_lastSpokenByCategory.constFind(category);
    return (it != m_lastSpokenByCategory.cend())
        && (it.value().msecsTo(now) < CategoryCooldownMs);
}

void NarratorController::narrate(const QString &category, const QString &englishText,
    const QString &cantoneseText)
{
    if (!m_enabled || m_quietHours || yieldingToAssistiveTech())
        return;

    const bool isError = category.startsWith(u"error"_s, Qt::CaseInsensitive);

    // Rate limits shape how often ordinary events speak. They never silence an
    // error: a failure the user needs to act on is exactly the line that must
    // not be dropped for being too soon after another one.
    if (!isError && cooldownBlocks(category))
    {
        qCDebug(lcUi) << "Narrator: suppressed by cooldown:" << category;
        return;
    }

    const bool wantsEnglish = (m_languageMode == English) || (m_languageMode == Both);
    const bool wantsCantonese = (m_languageMode == Cantonese) || (m_languageMode == Both);

    if (wantsEnglish && !englishText.isEmpty())
        enqueue({category, englishText.left(MaxSpokenChars), m_englishVoice, isError});

    // Both speaks English then Cantonese, strictly one after the other.
    if (wantsCantonese && !cantoneseText.isEmpty())
        enqueue({category, cantoneseText.left(MaxSpokenChars), m_cantoneseVoice, isError});

    m_lastSpokenByCategory.insert(category, QDateTime::currentDateTimeUtc());
    m_lastSpokenAt = QDateTime::currentDateTimeUtc();

    pumpQueue();
}

void NarratorController::enqueue(const Utterance &utterance)
{
    // A newer line in the same category replaces the older queued one instead
    // of stacking behind it, so a burst of events does not become a backlog the
    // user has to sit through.
    for (int i = 0; i < m_queue.size(); ++i)
    {
        if ((m_queue.at(i).category == utterance.category)
            && (m_queue.at(i).voice == utterance.voice))
        {
            m_queue[i] = utterance;
            return;
        }
    }

    // An error jumps the queue rather than waiting behind routine chatter.
    if (utterance.isError)
        m_queue.prepend(utterance);
    else
        m_queue.enqueue(utterance);
}

void NarratorController::previewVoice(const QString &voice, const QString &text)
{
    if (voice.isEmpty() || text.isEmpty())
        return;

    // A preview is explicitly requested, so it bypasses the rate limits — but
    // still goes through the same single player, never overlapping.
    m_queue.clear();
    m_queue.enqueue({u"preview"_s, text.left(MaxSpokenChars), voice, false});
    pumpQueue();
}

void NarratorController::pumpQueue()
{
    // One utterance at a time: never start a second while one is in flight.
    if (m_speaking || m_queue.isEmpty())
        return;

    synthesize(m_queue.dequeue());
}

void NarratorController::synthesize(const Utterance &utterance)
{
    const Utils::ForeignApps::PythonInfo pyInfo = Utils::ForeignApps::pythonInfo();
    if (!pyInfo.isValid())
    {
        setUnavailableReason(tr("Narration needs Python, which was not found."));
        m_queue.clear();
        return;
    }

    if (!m_mediaDir)
    {
        m_mediaDir = new QTemporaryDir;
        if (!m_mediaDir->isValid())
        {
            setUnavailableReason(tr("Could not create a temporary directory for narration audio."));
            m_queue.clear();
            return;
        }
    }

    setSpeaking(true);

    m_currentMedia = Path(m_mediaDir->filePath(u"utterance.mp3"_s));
    Utils::Fs::removeFile(m_currentMedia);

    if (!m_synth)
    {
        m_synth = new QProcess(this);
        connect(m_synth, &QProcess::finished, this,
            [this](const int exitCode, QProcess::ExitStatus) { onSynthesisFinished(exitCode); });
        connect(m_synth, &QProcess::errorOccurred, this,
            [this](const QProcess::ProcessError error)
        {
            if (error != QProcess::FailedToStart)
                return;
            const QString detail = m_synth ? m_synth->errorString() : QString();
            qCWarning(lcUi) << "Narrator synthesis process could not start:" << detail;
            setUnavailableReason(tr("Narration could not start. %1")
                .arg(detail.isEmpty() ? tr("The configured Python interpreter was unavailable.") : detail));
            setSpeaking(false);
            pumpQueue();
        });
    }

    const QStringList args {
        u"-m"_s, u"edge_tts"_s,
        u"--voice"_s, utterance.voice,
        u"--text"_s, utterance.text,
        u"--write-media"_s, m_currentMedia.toString()
    };

    qCDebug(lcUi) << "Narrator synthesizing with" << utterance.voice;
    m_synth->start(pyInfo.executablePath.data(), args, QIODevice::ReadOnly);

    // A hung network request must not wedge the queue permanently.
    QTimer::singleShot(SynthesisTimeoutMs, this, [this]
    {
        if (m_synth && (m_synth->state() != QProcess::NotRunning))
        {
            qCWarning(lcUi) << "Narrator synthesis timed out; killing";
            m_synth->kill();
        }
    });
}

void NarratorController::onSynthesisFinished(const int exitCode)
{
    if ((exitCode != 0) || !m_currentMedia.exists())
    {
        const QString stdErr = m_synth
            ? QString::fromUtf8(m_synth->readAllStandardError()).trimmed() : QString();
        qCWarning(lcUi) << "Narrator synthesis failed:" << exitCode << stdErr;
        setUnavailableReason(tr("Narration could not be synthesized. %1")
            .arg(stdErr.isEmpty() ? tr("The speech service did not respond.") : stdErr));
        setSpeaking(false);
        pumpQueue();
        return;
    }

    setUnavailableReason({});

    if (!m_player)
    {
        m_player = new QMediaPlayer(this);
        m_audioOutput = new QAudioOutput(this);
        m_player->setAudioOutput(m_audioOutput);
        connect(m_player, &QMediaPlayer::errorOccurred, this,
            [this](const QMediaPlayer::Error error, const QString &errorString)
        {
            qCWarning(lcUi) << "Narrator playback failed:" << error << errorString;
            setUnavailableReason(tr("Narration audio could not be played. %1")
                .arg(errorString.isEmpty() ? tr("The audio device rejected the utterance.")
                                            : errorString));
            setSpeaking(false);
            pumpQueue();
        });
        connect(m_player, &QMediaPlayer::mediaStatusChanged, this,
            [this](const QMediaPlayer::MediaStatus status)
        {
            if (status != QMediaPlayer::EndOfMedia)
                return;
            setSpeaking(false);
            pumpQueue();
        });
    }

    m_audioOutput->setVolume(static_cast<float>(m_volume));
    m_player->setSource(QUrl::fromLocalFile(m_currentMedia.toString()));
    m_player->play();
}

void NarratorController::stop()
{
    m_queue.clear();

    if (m_synth && (m_synth->state() != QProcess::NotRunning))
        m_synth->kill();
    if (m_player)
        m_player->stop();

    setSpeaking(false);
}

void NarratorController::setSpeaking(const bool speaking)
{
    if (m_speaking == speaking)
        return;
    m_speaking = speaking;
    emit speakingChanged();
}

void NarratorController::setUnavailableReason(const QString &reason)
{
    if (m_unavailableReason == reason)
        return;
    m_unavailableReason = reason;
    emit availabilityChanged();
}
