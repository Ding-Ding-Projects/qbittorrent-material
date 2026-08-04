/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "experiencecontroller.h"

#include <algorithm>
#include <memory>
#include <utility>

#include <QBuffer>
#include <QClipboard>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QQmlEngine>

#include "base/logging.h"

#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

using namespace Qt::Literals::StringLiterals;

namespace
{
    const QString kFirstRunCompleteKey = u"Experience/FirstRunCompleted"_s;
    const QString kRegexSafetyPrefix = u"(*LIMIT_MATCH=100000)(*LIMIT_DEPTH=1000)(?:"_s;
    const QString kCommitBaseUrl = u"https://github.com/Ding-Ding-Projects/qbittorrent-material/commit/"_s;
    const QString kCatalogSource = u"https://raw.githubusercontent.com/Ding-Ding-Projects/dim-sum-photos/main/catalog/index.json"_s;
    const QUrl kCatalogMetadataUrl {
        u"https://api.github.com/repos/Ding-Ding-Projects/dim-sum-photos/contents/catalog/index.json?ref=main"_s};
    const QString kPhotoReleasePrefix =
        u"https://github.com/Ding-Ding-Projects/dim-sum-photos/releases/download/catalog-v1/"_s;
    const QString kCacheDirectoryName = u"dim-sum-cache"_s;
    const QString kCacheMetadataName = u"metadata.json"_s;
    const QString kCacheImagesName = u"images"_s;
    constexpr int kCacheSchemaVersion = 1;
    constexpr int kMaximumCachedDishes = 4;
    constexpr int kMaximumCatalogDishes = 5000;
    constexpr qsizetype kMaximumMetadataBytes = 64 * 1024;
    constexpr qsizetype kMaximumCatalogBytes = 12 * 1024 * 1024;
    constexpr qsizetype kMaximumPhotoBytes = 8 * 1024 * 1024;
    constexpr int kMaximumRedirects = 4;
    constexpr int kMetadataTimeoutMs = 15000;
    constexpr int kCatalogTimeoutMs = 30000;
    constexpr int kPhotoTimeoutMs = 30000;
    constexpr int kCatalogRefreshDays = 7;

    bool hasProcessArgument(const QString &argument)
    {
        const QStringList arguments = QCoreApplication::arguments();
        return std::any_of(arguments.cbegin(), arguments.cend(), [&argument](const QString &candidate)
        {
            return candidate.compare(argument, Qt::CaseInsensitive) == 0;
        });
    }

    bool hasProcessArgumentPrefix(const QString &prefix)
    {
        const QStringList arguments = QCoreApplication::arguments();
        return std::any_of(arguments.cbegin(), arguments.cend(), [&prefix](const QString &candidate)
        {
            return candidate.startsWith(prefix, Qt::CaseInsensitive);
        });
    }

    bool isHex(const QString &value, const qsizetype length)
    {
        return (value.size() == length)
            && std::all_of(value.cbegin(), value.cend(), [](const QChar character)
            {
                return character.isDigit()
                    || ((character.toLower() >= u'a') && (character.toLower() <= u'f'));
            });
    }

    QDate parseUserDate(const QString &text)
    {
        const QString value = text.trimmed();
        if (value.isEmpty())
            return {};
        QDate date = QDate::fromString(value, Qt::ISODate);
        if (!date.isValid())
            date = QLocale().toDate(value, QLocale::ShortFormat);
        return date;
    }

    QRegularExpression::PatternOptions patternOptions(const QString &flags)
    {
        QRegularExpression::PatternOptions options = QRegularExpression::NoPatternOption;
        if (flags.contains(u'i')) options |= QRegularExpression::CaseInsensitiveOption;
        if (flags.contains(u'm')) options |= QRegularExpression::MultilineOption;
        if (flags.contains(u's')) options |= QRegularExpression::DotMatchesEverythingOption;
        if (flags.contains(u'u')) options |= QRegularExpression::UseUnicodePropertiesOption;
        return options;
    }
}

ExperienceController *ExperienceController::s_instance = nullptr;

ExperienceController *ExperienceController::create(QQmlEngine *, QJSEngine *)
{
    return instance();
}

ExperienceController *ExperienceController::instance()
{
    if (!s_instance)
    {
        s_instance = new ExperienceController(QCoreApplication::instance());
        QQmlEngine::setObjectOwnership(s_instance, QQmlEngine::CppOwnership);
    }
    return s_instance;
}

ExperienceController::ExperienceController(QObject *parent)
    : QObject(parent)
    , m_changelog(loadArrayResource(u":/experience/changelog.json"_s))
    , m_currentReleaseIdentity(loadObjectResource(u":/experience/release-identity.json"_s))
    , m_cantoneseCatalog(loadObjectResource(u":/i18n/cantonese.json"_s))
{
    m_network = new QNetworkAccessManager(this);

    const bool identityAvailable = m_currentReleaseIdentity.value(u"available"_s).toBool();
    const QString identityId = m_currentReleaseIdentity.value(u"id"_s).toString();
    const QString identityEnglish = m_currentReleaseIdentity.value(u"english"_s).toString();
    const QString identityChinese = m_currentReleaseIdentity.value(u"zhHant"_s).toString();
    const QString identityCodeName = m_currentReleaseIdentity.value(u"codeName"_s).toString();
    const QUrl identityPhotoUrl(m_currentReleaseIdentity.value(u"photoUrl"_s).toString());
    const QString identityPhotoAsset = m_currentReleaseIdentity.value(u"photoAssetName"_s).toString();
    const QString identityPhotoTag = m_currentReleaseIdentity.value(u"photoTag"_s).toString();
    const QString identityPhotoDigest =
        m_currentReleaseIdentity.value(u"photoDigest"_s).toString().toLower();
    const QString identityRevision = m_currentReleaseIdentity.value(u"catalogRevision"_s).toString();
    const QString identityBlobSha = m_currentReleaseIdentity.value(u"catalogBlobSha"_s).toString();
    if (identityAvailable
        && (!QRegularExpression(uR"(^hk-dish-[0-9]{4}$)"_s).match(identityId).hasMatch()
            || identityEnglish.trimmed().isEmpty() || (identityEnglish.size() > 200)
            || identityChinese.trimmed().isEmpty() || (identityChinese.size() > 200)
            || (identityCodeName != (identityEnglish + u" · "_s + identityChinese))
            || !QRegularExpression(uR"(^hk-dish-[0-9]{4}-[a-z0-9-]+\.png$)"_s)
                    .match(identityPhotoAsset).hasMatch()
            || !QRegularExpression(uR"(^catalog-v1(?:-part-[0-9]{3})?$)"_s)
                    .match(identityPhotoTag).hasMatch()
            || !QRegularExpression(uR"(^sha256:[0-9a-f]{64}$)"_s)
                    .match(identityPhotoDigest).hasMatch()
            || !isAllowedUrl(identityPhotoUrl, FetchPurpose::Photo)
            || !identityPhotoUrl.path().endsWith(u"/"_s + identityPhotoTag
                + u"/"_s + identityPhotoAsset)
            || (m_currentReleaseIdentity.value(u"catalogSourceUrl"_s).toString() != kCatalogSource)
            || !isHex(identityRevision, 40) || !isHex(identityBlobSha, 40)))
    {
        qCWarning(lcUi) << "Ignoring invalid bundled release identity metadata";
        m_currentReleaseIdentity[u"available"_s] = false;
        m_currentReleaseIdentity[u"reason"_s] =
            tr("This build's public dim-sum release identity is invalid.");
    }

    loadCachedDishes();
}

bool ExperienceController::startupDishVisible() const
{
    return m_startupDishVisible;
}

QVariantMap ExperienceController::startupDish() const
{
    return m_startupDish;
}

QVariantList ExperienceController::changelog() const
{
    return m_changelog;
}

QVariantMap ExperienceController::currentReleaseIdentity() const
{
    return m_currentReleaseIdentity;
}

QString ExperienceController::dimSumCacheStatus() const
{
    return m_dimSumCacheStatus;
}

void ExperienceController::considerStartupSurprise(const bool captureMode,
    const bool blockingFlow, const bool force)
{
    if (m_startupEvaluated && !force)
        return;
    m_startupEvaluated = true;
    scheduleCatalogRefresh();

#ifdef QBT_HAS_PREFERENCES
    const bool firstRunComplete = Preferences::instance()->value(kFirstRunCompleteKey, false).toBool();
    if (!firstRunComplete && !force)
    {
        Preferences::instance()->setValue(kFirstRunCompleteKey, true);
        Preferences::instance()->apply();
        qCInfo(lcUi) << "Dim-sum surprise skipped during first run";
        return;
    }
#endif
    if (blockingFlow)
        return;
    if (captureMode && !force)
        return;
    if (m_cachedDishes.isEmpty())
    {
        qCInfo(lcUi) << "Dim-sum startup surprise omitted: no verified public photo is cached";
        return;
    }
    if (!force && (QRandomGenerator::system()->bounded(10) != 0))
        return;

    const int index = QRandomGenerator::system()->bounded(static_cast<int>(m_cachedDishes.size()));
    m_startupDish = m_cachedDishes.at(index).toMap();
    m_startupDishVisible = !m_startupDish.value(u"image"_s).toString().isEmpty();
    emit startupDishChanged();
    qCInfo(lcUi) << "Dim-sum startup surprise selected" << m_startupDish.value(u"id"_s).toString();
}

void ExperienceController::dismissStartupDish()
{
    if (!m_startupDishVisible)
        return;
    m_startupDishVisible = false;
    emit startupDishChanged();
}

QString ExperienceController::cacheRoot() const
{
    const QString applicationData =
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return QDir(applicationData).filePath(kCacheDirectoryName);
}

QString ExperienceController::cacheMetadataPath() const
{
    return QDir(cacheRoot()).filePath(kCacheMetadataName);
}

QString ExperienceController::cacheImagesRoot() const
{
    return QDir(cacheRoot()).filePath(kCacheImagesName);
}

bool ExperienceController::isAllowedUrl(const QUrl &url, const FetchPurpose purpose,
    const bool redirectTarget) const
{
    if (!url.isValid() || (url.scheme().compare(u"https"_s, Qt::CaseInsensitive) != 0)
        || !url.userName().isEmpty() || !url.password().isEmpty() || url.hasFragment())
    {
        return false;
    }

    const int port = url.port(-1);
    if ((port != -1) && (port != 443))
        return false;

    const QString host = url.host().toLower();
    const QString path = url.path();
    switch (purpose)
    {
    case FetchPurpose::CatalogMetadata:
    {
        if (redirectTarget || (host != u"api.github.com"_s)
            || (path != u"/repos/Ding-Ding-Projects/dim-sum-photos/contents/catalog/index.json"_s))
        {
            return false;
        }
        const QUrlQuery query(url);
        return (query.queryItems().size() == 1)
            && (query.queryItemValue(u"ref"_s) == u"main"_s);
    }
    case FetchPurpose::CatalogDocument:
        return (host == u"raw.githubusercontent.com"_s)
            && (path == u"/Ding-Ding-Projects/dim-sum-photos/main/catalog/index.json"_s)
            && !url.hasQuery();
    case FetchPurpose::Photo:
        if (redirectTarget)
        {
            return (host == u"objects.githubusercontent.com"_s)
                || (host == u"release-assets.githubusercontent.com"_s);
        }
        return (host == u"github.com"_s)
            && QRegularExpression(
                uR"(^/Ding-Ding-Projects/dim-sum-photos/releases/download/catalog-v1(?:-part-[0-9]{3})?/[A-Za-z0-9][A-Za-z0-9._-]*\.png$)"_s)
                   .match(path).hasMatch()
            && !url.hasQuery();
    }
    return false;
}

bool ExperienceController::validatePng(const QByteArray &bytes, QString *errorMessage) const
{
    const QByteArray signature = QByteArray::fromHex("89504e470d0a1a0a");
    const auto fail = [errorMessage](const QString &message)
    {
        if (errorMessage)
            *errorMessage = message;
        return false;
    };

    if ((bytes.size() < signature.size()) || !bytes.startsWith(signature))
        return fail(tr("The cached public photo is not a PNG."));

    QBuffer buffer;
    buffer.setData(bytes);
    if (!buffer.open(QIODevice::ReadOnly))
        return fail(tr("The cached public photo could not be inspected."));

    QImageReader reader(&buffer, "png");
    reader.setDecideFormatFromContent(true);
    if (!reader.canRead())
        return fail(tr("The cached public photo is not decodable: %1").arg(reader.errorString()));

    const QSize dimensions = reader.size();
    const qint64 pixelCount = qint64(dimensions.width()) * qint64(dimensions.height());
    if (!dimensions.isValid() || (dimensions.width() > 4096) || (dimensions.height() > 4096)
        || (pixelCount <= 0) || (pixelCount > (16 * 1024 * 1024)))
    {
        return fail(tr("The cached public photo has unsafe dimensions."));
    }

    const QImage decoded = reader.read();
    if (decoded.isNull())
        return fail(tr("The cached public photo could not be decoded: %1").arg(reader.errorString()));
    return true;
}

QVariantMap ExperienceController::validatedCachedDish(const QVariantMap &stored,
    const QString &revision) const
{
    const QString id = stored.value(u"id"_s).toString();
    const QVariantMap name = stored.value(u"name"_s).toMap();
    const QVariantMap alt = stored.value(u"alt"_s).toMap();
    const QString imageFile = stored.value(u"imageFile"_s).toString();
    const QString photoAssetName = stored.value(u"photoAssetName"_s).toString();
    const QString photoTag = stored.value(u"photoTag"_s).toString();
    const QString digest = stored.value(u"photoDigest"_s).toString().toLower();
    const QUrl publicPhotoUrl(stored.value(u"publicPhotoUrl"_s).toString());

    if (!QRegularExpression(uR"(^hk-dish-[0-9]{4}$)"_s).match(id).hasMatch()
        || name.value(u"en"_s).toString().trimmed().isEmpty()
        || name.value(u"zhHant"_s).toString().trimmed().isEmpty()
        || (name.value(u"en"_s).toString().size() > 200)
        || (name.value(u"zhHant"_s).toString().size() > 200)
        || (QFileInfo(imageFile).fileName() != imageFile)
        || (imageFile != photoAssetName)
        || !QRegularExpression(uR"(^hk-dish-[0-9]{4}-[a-z0-9-]+\.png$)"_s)
                .match(imageFile).hasMatch()
        || !QRegularExpression(uR"(^catalog-v1(?:-part-[0-9]{3})?$)"_s)
                .match(photoTag).hasMatch()
        || !QRegularExpression(uR"(^sha256:[0-9a-f]{64}$)"_s).match(digest).hasMatch()
        || (stored.value(u"catalogRevision"_s).toString() != revision)
        || !isAllowedUrl(publicPhotoUrl, FetchPurpose::Photo))
    {
        return {};
    }

    QFile image(QDir(cacheImagesRoot()).filePath(imageFile));
    if (!image.open(QIODevice::ReadOnly) || (image.size() <= 0)
        || (image.size() > kMaximumPhotoBytes))
    {
        return {};
    }
    const QByteArray bytes = image.read(kMaximumPhotoBytes + 1);
    if ((bytes.size() > kMaximumPhotoBytes) || !validatePng(bytes))
        return {};
    const QString actualDigest = u"sha256:"_s
        + QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
    if (actualDigest != digest)
        return {};

    QVariantMap dish = stored;
    dish[u"name"_s] = name;
    dish[u"alt"_s] = alt;
    dish[u"image"_s] = QUrl::fromLocalFile(image.fileName()).toString();
    dish[u"publicPhotoUrl"_s] = publicPhotoUrl.toString();
    dish[u"catalogSourceUrl"_s] = kCatalogSource;
    return dish;
}

void ExperienceController::loadCachedDishes()
{
    QFile file(cacheMetadataPath());
    if (!file.open(QIODevice::ReadOnly) || (file.size() <= 0) || (file.size() > kMaximumMetadataBytes))
    {
        setDimSumCacheStatus(tr("No verified public dim-sum photo is cached; the startup surprise will be omitted."));
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = document.object();
    const QString source = root.value(u"catalogSourceUrl"_s).toString();
    const QString revision = root.value(u"catalogRevision"_s).toString();
    const QJsonArray dishes = root.value(u"dishes"_s).toArray();
    if (!document.isObject() || (root.value(u"schemaVersion"_s).toInt() != kCacheSchemaVersion)
        || (source != kCatalogSource) || !isHex(revision, 40)
        || (dishes.size() > kMaximumCachedDishes))
    {
        qCWarning(lcUi) << "Ignoring invalid public dim-sum cache metadata" << parseError.errorString();
        setDimSumCacheStatus(tr("The public dim-sum cache is invalid; the startup surprise will be omitted."));
        return;
    }

    m_cacheCheckedAt = QDateTime::fromString(root.value(u"checkedAt"_s).toString(), Qt::ISODate);
    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (m_cacheCheckedAt.isValid() && (m_cacheCheckedAt > now.addSecs(5 * 60)))
    {
        qCWarning(lcUi) << "Ignoring a future public dim-sum cache refresh timestamp";
        m_cacheCheckedAt = {};
    }
    for (const QJsonValue &value : dishes)
    {
        const QVariantMap dish = validatedCachedDish(value.toObject().toVariantMap(), revision);
        if (!dish.isEmpty())
            m_cachedDishes.append(dish);
    }

    if (m_cachedDishes.isEmpty())
    {
        setDimSumCacheStatus(tr("No verified public dim-sum photo is cached; the startup surprise will be omitted."));
        return;
    }
    setDimSumCacheStatus(tr("%1 verified public dim-sum photo(s) are ready in the application-data cache.")
        .arg(m_cachedDishes.size()));
}

void ExperienceController::setDimSumCacheStatus(const QString &status)
{
    if (m_dimSumCacheStatus == status)
        return;
    m_dimSumCacheStatus = status;
    emit dimSumCacheStatusChanged();
}

void ExperienceController::scheduleCatalogRefresh()
{
    if (m_refreshScheduled || m_refreshInProgress || QStandardPaths::isTestModeEnabled()
        || hasProcessArgument(u"--test-mode"_s)
        || hasProcessArgumentPrefix(u"--capture-ui"_s))
    {
        return;
    }
    if (m_cacheCheckedAt.isValid()
        && (m_cacheCheckedAt.daysTo(QDateTime::currentDateTimeUtc()) < kCatalogRefreshDays)
        && !m_cachedDishes.isEmpty())
    {
        return;
    }

    m_refreshScheduled = true;
    QTimer::singleShot(0, this, [this]
    {
        m_refreshScheduled = false;
        beginCatalogRefresh();
    });
}

void ExperienceController::fetchBounded(const QUrl &url, const FetchPurpose purpose,
    const qsizetype maximumBytes, const int timeoutMilliseconds, const int redirectCount,
    FetchCallback callback)
{
    const auto completion = std::make_shared<FetchCallback>(std::move(callback));
    if ((redirectCount > kMaximumRedirects)
        || !isAllowedUrl(url, purpose, redirectCount > 0))
    {
        (*completion)({}, {}, tr("The public dim-sum source URL was refused by the allowlist."));
        return;
    }

    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, u"qBittorrent-Material/1 public-dim-sum-cache"_s);
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Accept", purpose == FetchPurpose::CatalogMetadata
        ? "application/vnd.github+json" : "application/octet-stream");

    QNetworkReply *reply = m_network->get(request);
    const auto payload = std::make_shared<QByteArray>();
    const auto failure = std::make_shared<QString>();
    QTimer *timeout = new QTimer(reply);
    timeout->setSingleShot(true);
    timeout->setInterval(timeoutMilliseconds);
    connect(timeout, &QTimer::timeout, reply, [reply, failure, this]
    {
        *failure = tr("The public dim-sum request timed out.");
        reply->abort();
    });
    timeout->start();

    connect(reply, &QNetworkReply::metaDataChanged, reply,
        [reply, maximumBytes, failure, this]
    {
        const QVariant lengthHeader = reply->header(QNetworkRequest::ContentLengthHeader);
        if (lengthHeader.isValid() && (lengthHeader.toLongLong() > maximumBytes))
        {
            *failure = tr("The public dim-sum response exceeded its size limit.");
            reply->abort();
        }
    });
    connect(reply, &QIODevice::readyRead, reply,
        [reply, payload, failure, maximumBytes, this]
    {
        const QByteArray chunk = reply->readAll();
        if ((payload->size() + chunk.size()) > maximumBytes)
        {
            *failure = tr("The public dim-sum response exceeded its size limit.");
            reply->abort();
            return;
        }
        payload->append(chunk);
    });
    connect(reply, &QNetworkReply::finished, this,
        [this, reply, timeout, payload, failure, maximumBytes, timeoutMilliseconds,
            purpose, redirectCount, completion]
    {
        timeout->stop();
        const QByteArray remaining = reply->readAll();
        if ((payload->size() + remaining.size()) > maximumBytes)
            *failure = tr("The public dim-sum response exceeded its size limit.");
        else
            payload->append(remaining);

        const QUrl redirect = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
        if (failure->isEmpty() && redirect.isValid())
        {
            const QUrl target = reply->url().resolved(redirect);
            reply->deleteLater();
            fetchBounded(target, purpose, maximumBytes, timeoutMilliseconds,
                redirectCount + 1, *completion);
            return;
        }

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (failure->isEmpty() && (reply->error() != QNetworkReply::NoError))
            *failure = tr("The public dim-sum request failed: %1").arg(reply->errorString());
        if (failure->isEmpty() && (status != 200))
            *failure = tr("The public dim-sum source returned HTTP %1.").arg(status);

        const QUrl finalUrl = reply->url();
        const QByteArray result = failure->isEmpty() ? *payload : QByteArray {};
        const QString error = *failure;
        reply->deleteLater();
        (*completion)(result, finalUrl, error);
    });
}

void ExperienceController::beginCatalogRefresh()
{
    if (m_refreshInProgress)
        return;
    m_refreshInProgress = true;
    setDimSumCacheStatus(tr("Refreshing the verified public dim-sum cache in the background."));
    fetchBounded(kCatalogMetadataUrl, FetchPurpose::CatalogMetadata, kMaximumMetadataBytes,
        kMetadataTimeoutMs, 0, [this](QByteArray payload, QUrl, QString error)
    {
        if (!error.isEmpty())
        {
            finishCatalogRefresh(tr("Public dim-sum catalog refresh was skipped: %1").arg(error));
            return;
        }
        handleCatalogMetadata(payload);
    });
}

void ExperienceController::handleCatalogMetadata(const QByteArray &payload)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    const QJsonObject metadata = document.object();
    const QString revision = metadata.value(u"sha"_s).toString().toLower();
    const qint64 size = metadata.value(u"size"_s).toInteger(-1);
    const QUrl downloadUrl(metadata.value(u"download_url"_s).toString());
    if (!document.isObject() || !isHex(revision, 40) || (size <= 0)
        || (size > kMaximumCatalogBytes) || (downloadUrl.toString() != kCatalogSource)
        || !isAllowedUrl(downloadUrl, FetchPurpose::CatalogDocument))
    {
        finishCatalogRefresh(tr("The public dim-sum catalog metadata was invalid: %1")
            .arg(parseError.errorString()));
        return;
    }

    fetchBounded(downloadUrl, FetchPurpose::CatalogDocument, kMaximumCatalogBytes,
        kCatalogTimeoutMs, 0, [this, revision](QByteArray catalog, QUrl, QString error)
    {
        if (!error.isEmpty())
        {
            finishCatalogRefresh(tr("Public dim-sum catalog refresh was skipped: %1").arg(error));
            return;
        }
        handleCatalogDocument(catalog, revision);
    });
}

void ExperienceController::handleCatalogDocument(const QByteArray &payload,
    const QString &revision)
{
    QByteArray gitBlobInput = "blob " + QByteArray::number(payload.size()) + '\0';
    gitBlobInput.append(payload);
    const QString actualRevision = QString::fromLatin1(
        QCryptographicHash::hash(gitBlobInput, QCryptographicHash::Sha1).toHex());
    if (actualRevision != revision)
    {
        finishCatalogRefresh(tr("The public dim-sum catalog did not match its published revision."));
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    const QJsonObject catalog = document.object();
    const QJsonArray sourceDishes = catalog.value(u"dishes"_s).toArray();
    if (!document.isObject() || sourceDishes.isEmpty()
        || (sourceDishes.size() > kMaximumCatalogDishes))
    {
        finishCatalogRefresh(tr("The public dim-sum catalog was invalid: %1")
            .arg(parseError.errorString()));
        return;
    }

    QVariantList candidates;
    QHash<QString, QVariantMap> candidatesById;
    const QRegularExpression idPattern(uR"(^hk-dish-([0-9]{4})$)"_s);
    const QRegularExpression assetPattern(uR"(^hk-dish-[0-9]{4}-[a-z0-9-]+\.png$)"_s);
    for (const QJsonValue &value : sourceDishes)
    {
        const QJsonObject source = value.toObject();
        const QString id = source.value(u"id"_s).toString();
        const QRegularExpressionMatch idMatch = idPattern.match(id);
        const int number = idMatch.hasMatch() ? idMatch.captured(1).toInt() : 0;
        const QJsonObject nameObject = source.value(u"name"_s).toObject();
        const QJsonObject imageObject = source.value(u"image"_s).toObject();
        const QJsonObject altObject = imageObject.value(u"alt"_s).toObject();
        const QString english = nameObject.value(u"en"_s).toString().trimmed();
        const QString traditionalChinese = nameObject.value(u"zhHant"_s).toString().trimmed();
        const QString imagePath = imageObject.value(u"path"_s).toString();
        const QString assetName = QFileInfo(imagePath).fileName();
        if (!idMatch.hasMatch() || (number < 1) || (number > 995)
            || (imagePath != (u"images/"_s + assetName))
            || !assetPattern.match(assetName).hasMatch()
            || english.isEmpty() || traditionalChinese.isEmpty()
            || (english.size() > 200) || (traditionalChinese.size() > 200))
        {
            continue;
        }

        const QString encodedAsset = QString::fromLatin1(QUrl::toPercentEncoding(assetName));
        const QString publicPhotoUrl = kPhotoReleasePrefix + encodedAsset;
        QVariantMap candidate {
            {u"id"_s, id},
            {u"name"_s, QVariantMap {{u"en"_s, english}, {u"zhHant"_s, traditionalChinese}}},
            {u"alt"_s, QVariantMap {
                {u"en"_s, altObject.value(u"en"_s).toString().trimmed().left(300)},
                {u"yue"_s, altObject.value(u"yue"_s).toString().trimmed().left(300)}}},
            {u"photoAssetName"_s, assetName},
            {u"photoTag"_s, u"catalog-v1"_s},
            {u"publicPhotoUrl"_s, publicPhotoUrl},
            {u"catalogSourceUrl"_s, kCatalogSource},
            {u"catalogRevision"_s, revision}
        };
        candidates.append(candidate);
        candidatesById.insert(id, candidate);
    }

    if (candidates.isEmpty())
    {
        finishCatalogRefresh(tr("No published catalog-v1 dish could be resolved from the public catalog."));
        return;
    }

    QVariantList refreshedCachedDishes;
    QSet<QString> cachedIds;
    for (const QVariant &value : std::as_const(m_cachedDishes))
    {
        QVariantMap cached = value.toMap();
        const QString id = cached.value(u"id"_s).toString();
        if (!candidatesById.contains(id))
            continue;
        const QVariantMap authoritative = candidatesById.value(id);
        cached[u"name"_s] = authoritative.value(u"name"_s);
        cached[u"alt"_s] = authoritative.value(u"alt"_s);
        cached[u"publicPhotoUrl"_s] = authoritative.value(u"publicPhotoUrl"_s);
        cached[u"catalogSourceUrl"_s] = kCatalogSource;
        cached[u"catalogRevision"_s] = revision;
        refreshedCachedDishes.append(cached);
        cachedIds.insert(id);
    }
    m_cachedDishes = refreshedCachedDishes;

    if (m_cachedDishes.size() >= kMaximumCachedDishes)
    {
        if (saveCache(revision, m_cachedDishes))
            finishCatalogRefresh(tr("The verified public dim-sum cache is current."));
        else
            finishCatalogRefresh(tr("The refreshed public dim-sum cache metadata could not be saved."));
        return;
    }

    QVariantList missingCandidates;
    for (const QVariant &candidate : std::as_const(candidates))
    {
        if (!cachedIds.contains(candidate.toMap().value(u"id"_s).toString()))
            missingCandidates.append(candidate);
    }
    cacheCandidate(missingCandidates, revision);
}

void ExperienceController::cacheCandidate(QVariantList candidates, const QString &revision,
    const int attempt)
{
    if (candidates.isEmpty() || (attempt >= 3))
    {
        finishCatalogRefresh(tr("No additional verified public photo was available; %1 cached photo(s) were retained.")
            .arg(m_cachedDishes.size()));
        return;
    }

    const int index = QRandomGenerator::system()->bounded(static_cast<int>(candidates.size()));
    QVariantMap candidate = candidates.takeAt(index).toMap();
    const QUrl photoUrl(candidate.value(u"publicPhotoUrl"_s).toString());
    fetchBounded(photoUrl, FetchPurpose::Photo, kMaximumPhotoBytes, kPhotoTimeoutMs, 0,
        [this, candidates, candidate, revision, attempt, photoUrl]
        (QByteArray bytes, QUrl, QString error) mutable
    {
        QString imageError;
        if (error.isEmpty() && !validatePng(bytes, &imageError))
            error = imageError;
        if (!error.isEmpty())
        {
            qCWarning(lcUi) << "Public dim-sum photo was not cached" << photoUrl << error;
            cacheCandidate(candidates, revision, attempt + 1);
            return;
        }

        const QString imageFile = candidate.value(u"photoAssetName"_s).toString();
        QDir imagesDirectory(cacheImagesRoot());
        if (!imagesDirectory.mkpath(u"."_s))
        {
            finishCatalogRefresh(tr("The application-data dim-sum cache directory could not be created."));
            return;
        }
        const QString destination = imagesDirectory.filePath(imageFile);
        QSaveFile output(destination);
        if (!output.open(QIODevice::WriteOnly) || (output.write(bytes) != bytes.size())
            || !output.commit())
        {
            finishCatalogRefresh(tr("The verified public dim-sum photo could not be saved atomically."));
            return;
        }

        candidate[u"imageFile"_s] = imageFile;
        candidate[u"image"_s] = QUrl::fromLocalFile(destination).toString();
        candidate[u"photoDigest"_s] = QString(u"sha256:"_s
            + QString::fromLatin1(QCryptographicHash::hash(
                bytes, QCryptographicHash::Sha256).toHex()));
        candidate[u"cachedAt"_s] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
        m_cachedDishes.append(candidate);
        while (m_cachedDishes.size() > kMaximumCachedDishes)
            m_cachedDishes.removeFirst();

        if (!saveCache(revision, m_cachedDishes))
        {
            m_cachedDishes.removeLast();
            QFile::remove(destination);
            finishCatalogRefresh(tr("The verified public dim-sum cache metadata could not be saved atomically."));
            return;
        }
        finishCatalogRefresh(tr("%1 verified public dim-sum photo(s) are ready in the application-data cache.")
            .arg(m_cachedDishes.size()));
    });
}

bool ExperienceController::saveCache(const QString &revision, const QVariantList &dishes)
{
    QDir root(cacheRoot());
    if (!root.mkpath(u"."_s) || !QDir(cacheImagesRoot()).mkpath(u"."_s))
        return false;

    QVariantList storedDishes;
    QSet<QString> referencedImages;
    for (const QVariant &value : dishes)
    {
        QVariantMap dish = value.toMap();
        dish.remove(u"image"_s);
        const QString imageFile = dish.value(u"imageFile"_s).toString();
        if (QFileInfo(imageFile).fileName() != imageFile)
            return false;
        referencedImages.insert(imageFile);
        storedDishes.append(dish);
    }

    const QString checkedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    const QVariantMap envelope {
        {u"schemaVersion"_s, kCacheSchemaVersion},
        {u"catalogSourceUrl"_s, kCatalogSource},
        {u"catalogRevision"_s, revision},
        {u"checkedAt"_s, checkedAt},
        {u"dishes"_s, storedDishes}
    };
    const QByteArray bytes = QJsonDocument(QJsonObject::fromVariantMap(envelope))
        .toJson(QJsonDocument::Indented);
    if (bytes.size() > kMaximumMetadataBytes)
        return false;

    QSaveFile output(cacheMetadataPath());
    if (!output.open(QIODevice::WriteOnly) || (output.write(bytes) != bytes.size())
        || !output.commit())
    {
        return false;
    }

    m_cacheCheckedAt = QDateTime::fromString(checkedAt, Qt::ISODate);
    const QFileInfoList cachedFiles = QDir(cacheImagesRoot()).entryInfoList(
        {u"*.png"_s}, QDir::Files | QDir::NoSymLinks);
    for (const QFileInfo &cachedFile : cachedFiles)
    {
        if (!referencedImages.contains(cachedFile.fileName()))
            QFile::remove(cachedFile.absoluteFilePath());
    }
    return true;
}

void ExperienceController::finishCatalogRefresh(const QString &status)
{
    m_refreshInProgress = false;
    setDimSumCacheStatus(status);
    qCInfo(lcUi) << status;
}

QVariantMap ExperienceController::filterChangelog(const QString &query, const bool regex,
    const QString &flags, const QString &fromDate, const QString &toDate) const
{
    QVariantMap result {{u"valid"_s, true}, {u"error"_s, QString()}};
    if (query.size() > 4096)
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("Patterns are limited to 4,096 characters.");
        result[u"entries"_s] = QVariantList {};
        return result;
    }
    const QString boundedQuery = query;
    const QDate from = parseUserDate(fromDate);
    const QDate to = parseUserDate(toDate);
    if ((!fromDate.trimmed().isEmpty() && !from.isValid())
        || (!toDate.trimmed().isEmpty() && !to.isValid()))
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("Enter a locale-formatted date or ISO date (YYYY-MM-DD).");
        result[u"entries"_s] = QVariantList {};
        return result;
    }
    if (from.isValid() && to.isValid() && from > to)
    {
        result[u"valid"_s] = false;
        result[u"error"_s] = tr("The start date must not be after the end date.");
        result[u"entries"_s] = QVariantList {};
        return result;
    }

    QRegularExpression expression;
    if (regex && !boundedQuery.isEmpty())
    {
        const QString normalizedFlags = flags.toLower();
        for (const QChar flag : normalizedFlags)
        {
            if (!u"gimsu"_s.contains(flag))
            {
                result[u"valid"_s] = false;
                result[u"error"_s] = tr("Unsupported regular-expression flag: %1").arg(flag);
                result[u"entries"_s] = QVariantList {};
                return result;
            }
        }
        expression.setPattern(kRegexSafetyPrefix + boundedQuery + u')');
        expression.setPatternOptions(patternOptions(flags));
        if (!expression.isValid())
        {
            result[u"valid"_s] = false;
            result[u"error"_s] = tr("Invalid regular expression at %1: %2")
                .arg(qMax<qsizetype>(0, expression.patternErrorOffset()
                    - kRegexSafetyPrefix.size())).arg(expression.errorString());
            result[u"entries"_s] = QVariantList {};
            return result;
        }
    }

    QVariantList filtered;
    for (const QVariant &value : m_changelog)
    {
        const QVariantMap entry = value.toMap();
        const QDate date = QDate::fromString(entry.value(u"date"_s).toString(), Qt::ISODate);
        if (from.isValid() && date.isValid() && date < from)
            continue;
        if (to.isValid() && date.isValid() && date > to)
            continue;
        const QString title = entry.value(u"title"_s).toString();
        const QString commit = entry.value(u"commit"_s).toString();
        const QStringList changes = entry.value(u"changes"_s).toStringList();
        QStringList localizedChanges;
        for (const QString &change : changes)
            localizedChanges.append(m_cantoneseCatalog.value(change).toString());
        const QString searchable = entry.value(u"version"_s).toString() + u'\n'
            + title + u'\n' + commit + u'\n' + changes.join(u'\n') + u'\n'
            + m_cantoneseCatalog.value(title).toString() + u'\n'
            + localizedChanges.join(u'\n');
        if (!boundedQuery.isEmpty())
        {
            const bool match = regex
                ? expression.match(searchable).hasMatch()
                : searchable.contains(boundedQuery, flags.contains(u'i')
                    ? Qt::CaseInsensitive : Qt::CaseSensitive);
            if (!match)
                continue;
        }
        filtered.append(entry);
    }
    result[u"entries"_s] = filtered;
    return result;
}

void ExperienceController::copyChangelog(const QVariantList &entries)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(markdownFor(entries));
    emit operationFinished(true, tr("The filtered changelog was copied to the clipboard."));
}

bool ExperienceController::exportChangelog(const QUrl &destination, const QVariantList &entries)
{
    const QString path = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (path.trimmed().isEmpty())
    {
        emit operationFinished(false, tr("Choose a local Markdown file for the changelog export."));
        return false;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        emit operationFinished(false, tr("Could not open the changelog export file: %1").arg(file.errorString()));
        return false;
    }
    const QByteArray bytes = markdownFor(entries).toUtf8();
    if ((file.write(bytes) != bytes.size()) || !file.commit())
    {
        emit operationFinished(false, tr("Could not save the changelog export: %1").arg(file.errorString()));
        return false;
    }
    emit operationFinished(true, tr("Exported %1 changelog entries to %2.").arg(entries.size()).arg(path));
    return true;
}

QVariantList ExperienceController::loadArrayResource(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        qCWarning(lcUi) << "Could not open bundled experience data" << path << file.errorString();
        return {};
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (!document.isArray())
    {
        qCWarning(lcUi) << "Invalid bundled experience data" << path << error.errorString();
        return {};
    }
    return document.array().toVariantList();
}

QVariantMap ExperienceController::loadObjectResource(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap {};
}

QString ExperienceController::markdownFor(const QVariantList &entries)
{
    QString output = u"# qBittorrent Material changelog\n\n"_s;
    QDate earliest;
    QDate latest;
    for (const QVariant &value : entries)
    {
        const QDate date = QDate::fromString(value.toMap().value(u"date"_s).toString(), Qt::ISODate);
        if (!date.isValid()) continue;
        if (!earliest.isValid() || date < earliest) earliest = date;
        if (!latest.isValid() || date > latest) latest = date;
    }
    output += entries.isEmpty()
        ? u"> Exported filtered range: no matching releases.\n\n"_s
        : u"> Exported filtered range: %1 through %2 (%3 entries).\n\n"_s
            .arg(earliest.toString(Qt::ISODate), latest.toString(Qt::ISODate))
            .arg(entries.size());
    for (const QVariant &value : entries)
    {
        const QVariantMap entry = value.toMap();
        output += u"## %1 — %2\n\n"_s.arg(entry.value(u"version"_s).toString(),
            entry.value(u"date"_s).toString());
        const QString commit = entry.value(u"commit"_s).toString();
        if (!commit.isEmpty())
            output += u"Commit: [%1](%2%1)\n\n"_s.arg(commit, kCommitBaseUrl);
        const QString title = entry.value(u"title"_s).toString();
        if (!title.isEmpty()) output += title + u"\n\n"_s;
        const QStringList changes = entry.value(u"changes"_s).toStringList();
        for (const QString &change : changes) output += u"- "_s + change + u'\n';
        output += u'\n';
    }
    return output;
}
