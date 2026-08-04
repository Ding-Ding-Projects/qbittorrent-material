/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <functional>

#include <QByteArray>
#include <QDateTime>
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;
class QNetworkAccessManager;

/**
 * Experience data shared by the startup delight and changelog viewer.
 *
 * Changelog and release-identity metadata are bundled. Dim-sum photos are
 * never bundled: a bounded background refresh obtains authoritative names from
 * the public catalog and stores verified public catalog-v1 photos in the
 * application's local-data cache for a later launch. Startup never waits for
 * that refresh and omits the surprise when no verified cached photo exists.
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
    Q_PROPERTY(QVariantMap currentReleaseIdentity READ currentReleaseIdentity CONSTANT)
    Q_PROPERTY(QString dimSumCacheStatus READ dimSumCacheStatus NOTIFY dimSumCacheStatusChanged)

public:
    static ExperienceController *create(QQmlEngine *, QJSEngine *);
    static ExperienceController *instance();

    [[nodiscard]] bool startupDishVisible() const;
    [[nodiscard]] QVariantMap startupDish() const;
    [[nodiscard]] QVariantList changelog() const;
    [[nodiscard]] QVariantMap currentReleaseIdentity() const;
    [[nodiscard]] QString dimSumCacheStatus() const;

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
    void dimSumCacheStatusChanged();
    void operationFinished(bool success, const QString &message);

private:
    enum class FetchPurpose
    {
        CatalogMetadata,
        CatalogDocument,
        Photo
    };

    using FetchCallback = std::function<void(QByteArray, QUrl, QString)>;

    explicit ExperienceController(QObject *parent = nullptr);
    static QVariantList loadArrayResource(const QString &path);
    static QVariantMap loadObjectResource(const QString &path);
    static QString markdownFor(const QVariantList &entries);

    void loadCachedDishes();
    void scheduleCatalogRefresh();
    void beginCatalogRefresh();
    void handleCatalogMetadata(const QByteArray &payload);
    void handleCatalogDocument(const QByteArray &payload, const QString &revision);
    void cacheCandidate(QVariantList candidates, const QString &revision, int attempt = 0);
    void fetchBounded(const QUrl &url, FetchPurpose purpose, qsizetype maximumBytes,
        int timeoutMilliseconds, int redirectCount, FetchCallback callback);
    [[nodiscard]] bool isAllowedUrl(const QUrl &url, FetchPurpose purpose,
        bool redirectTarget = false) const;
    [[nodiscard]] bool validatePng(const QByteArray &bytes, QString *errorMessage = nullptr) const;
    [[nodiscard]] QVariantMap validatedCachedDish(const QVariantMap &stored,
        const QString &revision) const;
    [[nodiscard]] QString cacheRoot() const;
    [[nodiscard]] QString cacheMetadataPath() const;
    [[nodiscard]] QString cacheImagesRoot() const;
    [[nodiscard]] bool saveCache(const QString &revision, const QVariantList &dishes);
    void setDimSumCacheStatus(const QString &status);
    void finishCatalogRefresh(const QString &status);

    static ExperienceController *s_instance;
    bool m_startupEvaluated = false;
    bool m_startupDishVisible = false;
    bool m_refreshScheduled = false;
    bool m_refreshInProgress = false;
    QVariantMap m_startupDish;
    QVariantList m_cachedDishes;
    QVariantList m_changelog;
    QVariantMap m_currentReleaseIdentity;
    QVariantMap m_cantoneseCatalog;
    QString m_dimSumCacheStatus;
    QDateTime m_cacheCheckedAt;
    QNetworkAccessManager *m_network = nullptr;
};
