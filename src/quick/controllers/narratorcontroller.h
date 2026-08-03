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

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QQueue>
#include <QString>
#include <qqmlintegration.h>

#include "base/path.h"

class QAudioOutput;
class QJSEngine;
class QMediaPlayer;
class QProcess;
class QQmlEngine;
class QTemporaryDir;

/*!
    Optional spoken narration of application events.

    \section2 It is off until the user turns it on

    The narrator ships disabled and is enabled only by the user. Nothing is
    synthesized, no audio device is opened, and no text leaves the machine until
    that happens.

    \section2 Voices

    Synthesis runs through Microsoft Edge's online neural voices (the
    \c edge-tts Python package), which is what gives the Cantonese track a real
    Hong Kong voice rather than a robotic one. That means **narration text is
    sent to Microsoft's speech service while the narrator is enabled** — stated
    plainly in the settings surface, because a user enabling a voice is not
    thereby consenting to a network round trip they were never told about.

    \section2 One utterance at a time

    Lines are spoken through a strictly serialized queue: one player, one
    utterance, never overlapping. A queued line that a newer line of the same
    category supersedes is replaced rather than stacked, so a burst of torrent
    completions does not become a backlog the user waits out. A per-category
    cooldown plus a global debounce keeps narration infrequent.

    \section2 Yielding

    Narration is suppressed while a screen reader is active — the reader is
    already speaking, and talking over it helps nobody — and while the app's own
    quiet setting is on. Errors are never silently dropped by the rate limits:
    an error line preempts the queue.
*/
class NarratorController final : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(NarratorController)

    /// Whether the narrator speaks at all. Persisted; false by default.
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY settingsChanged)
    /// Which language track(s) to speak: English, Cantonese, or Both.
    Q_PROPERTY(int languageMode READ languageMode WRITE setLanguageMode NOTIFY settingsChanged)
    /// Edge voice used for the English track.
    Q_PROPERTY(QString englishVoice READ englishVoice WRITE setEnglishVoice NOTIFY settingsChanged)
    /// Edge voice used for the Cantonese track.
    Q_PROPERTY(QString cantoneseVoice READ cantoneseVoice WRITE setCantoneseVoice NOTIFY settingsChanged)
    /// Playback volume, 0.0 - 1.0.
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY settingsChanged)
    /// Suppresses narration without forgetting the user's other settings.
    Q_PROPERTY(bool quietHours READ quietHours WRITE setQuietHours NOTIFY settingsChanged)
    /// True while an utterance is being synthesized or played.
    Q_PROPERTY(bool speaking READ isSpeaking NOTIFY speakingChanged)
    /// Empty when the narrator can speak; otherwise why it cannot.
    Q_PROPERTY(QString unavailableReason READ unavailableReason NOTIFY availabilityChanged)

public:
    /// Which language track(s) are spoken. Both speaks English then Cantonese,
    /// strictly serialized, never together.
    enum LanguageMode
    {
        English = 0,
        Cantonese = 1,
        Both = 2
    };
    Q_ENUM(LanguageMode)

    static NarratorController *create(QQmlEngine *engine, QJSEngine *jsEngine);
    static NarratorController *instance();

    ~NarratorController() override;

    [[nodiscard]] bool isEnabled() const { return m_enabled; }
    void setEnabled(bool enabled);

    [[nodiscard]] int languageMode() const { return m_languageMode; }
    void setLanguageMode(int mode);

    [[nodiscard]] QString englishVoice() const { return m_englishVoice; }
    void setEnglishVoice(const QString &voice);

    [[nodiscard]] QString cantoneseVoice() const { return m_cantoneseVoice; }
    void setCantoneseVoice(const QString &voice);

    [[nodiscard]] qreal volume() const { return m_volume; }
    void setVolume(qreal volume);

    [[nodiscard]] bool quietHours() const { return m_quietHours; }
    void setQuietHours(bool quiet);

    [[nodiscard]] bool isSpeaking() const { return m_speaking; }
    [[nodiscard]] QString unavailableReason() const { return m_unavailableReason; }

    /// The Edge voices available for each track, for the settings pickers.
    [[nodiscard]] Q_INVOKABLE QVariantList englishVoices() const;
    [[nodiscard]] Q_INVOKABLE QVariantList cantoneseVoices() const;

    /*!
        Queues @a englishText (and @a cantoneseText when the mode includes it)
        for narration.

        @a category drives the cooldown and supersession: a newer line in the
        same category replaces an older queued one instead of stacking behind
        it. Pass a distinct category per event kind.

        Silently does nothing when the narrator is disabled, quiet, or yielding.
    */
    Q_INVOKABLE void narrate(const QString &category, const QString &englishText,
        const QString &cantoneseText = {});

    /// Speaks a one-off sample so the user can hear a voice before committing.
    Q_INVOKABLE void previewVoice(const QString &voice, const QString &text);

    /// Drops everything queued and stops the current utterance.
    Q_INVOKABLE void stop();

signals:
    void settingsChanged();
    void speakingChanged();
    void availabilityChanged();

private:
    explicit NarratorController(QObject *parent = nullptr);

    struct Utterance
    {
        QString category;
        QString text;
        QString voice;
        bool isError = false;
    };

    void loadSettings();
    void persist(const QString &key, const QVariant &value);
    void enqueue(const Utterance &utterance);
    void pumpQueue();
    void synthesize(const Utterance &utterance);
    void onSynthesisFinished(int exitCode);
    void setSpeaking(bool speaking);
    void setUnavailableReason(const QString &reason);
    [[nodiscard]] bool yieldingToAssistiveTech() const;
    [[nodiscard]] bool cooldownBlocks(const QString &category) const;

    static NarratorController *s_instance;

    bool m_enabled = false;
    int m_languageMode = English;
    QString m_englishVoice;
    QString m_cantoneseVoice;
    qreal m_volume = 0.7;
    bool m_quietHours = false;

    bool m_speaking = false;
    QString m_unavailableReason;

    QQueue<Utterance> m_queue;
    QHash<QString, QDateTime> m_lastSpokenByCategory;
    QDateTime m_lastSpokenAt;

    QProcess *m_synth = nullptr;
    QMediaPlayer *m_player = nullptr;
    QAudioOutput *m_audioOutput = nullptr;
    QTemporaryDir *m_mediaDir = nullptr;
    Path m_currentMedia;
};
