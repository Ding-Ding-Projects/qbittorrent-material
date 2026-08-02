/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;
class QUrl;

/**
 * Offline experience data shared by the startup delight and changelog viewer.
 *
 * The controller deliberately loads only bundled resources. No query, sample
 * text, release data, or dim-sum selection is transmitted over the network.
 */
class ExperienceController final : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Experience)
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(ExperienceController)

    Q_PROPERTY(bool startupDishVisible READ startupDishVisible NOTIFY startupDishChanged)
    Q_PROPERTY(QVariantMap startupDish READ startupDish NOTIFY startupDishChanged)
    Q_PROPERTY(QVariantList changelog READ changelog CONSTANT)

public:
    static ExperienceController *create(QQmlEngine *, QJSEngine *);
    static ExperienceController *instance();

    [[nodiscard]] bool startupDishVisible() const;
    [[nodiscard]] QVariantMap startupDish() const;
    [[nodiscard]] QVariantList changelog() const;

    /** Perform the single startup draw. First run and blocking/capture flows
     * are excluded. `force` exists only for the repository capture harness. */
    Q_INVOKABLE void considerStartupSurprise(bool captureMode, bool blockingFlow, bool force = false);
    Q_INVOKABLE void dismissStartupDish();

    /** Search and date-filter the bundled changelog as one composed predicate. */
    Q_INVOKABLE QVariantMap filterChangelog(const QString &query, bool regex,
        const QString &flags, const QString &fromDate, const QString &toDate) const;
    Q_INVOKABLE void copyChangelog(const QVariantList &entries);
    Q_INVOKABLE bool exportChangelog(const QUrl &destination, const QVariantList &entries);

signals:
    void startupDishChanged();
    void operationFinished(bool success, const QString &message);

private:
    explicit ExperienceController(QObject *parent = nullptr);
    static QVariantList loadArrayResource(const QString &path);
    static QVariantMap loadObjectResource(const QString &path);
    static QString markdownFor(const QVariantList &entries);

    static ExperienceController *s_instance;
    bool m_startupEvaluated = false;
    bool m_startupDishVisible = false;
    QVariantMap m_startupDish;
    QVariantList m_dishes;
    QVariantList m_changelog;
    QVariantMap m_cantoneseCatalog;
};
