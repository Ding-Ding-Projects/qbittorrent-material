/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "squirrelreleasevalidator.h"

#include <memory>

#include <QCryptographicHash>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>

using namespace Qt::StringLiterals;

namespace
{
constexpr qsizetype kMaximumManifestBytes = 1024 * 1024;
constexpr qsizetype kMaximumSignatureBytes = 1024;
constexpr qsizetype kHashBufferBytes = 1024 * 1024;
constexpr auto kPackageId = "qBittorrentMaterial";
constexpr auto kAlgorithm = "RSASSA-PKCS1-v1_5-SHA256";
constexpr auto kPinnedSpkiSha256 =
        "4479439dfb5bce538ab92e492dd677628060c8558d4c49ac7b253f3eeb4f36e8";

QString opensslError(const QString &fallback)
{
    const unsigned long code = ERR_peek_last_error();
    if (code == 0)
        return fallback;
    char buffer[256] = {};
    ERR_error_string_n(code, buffer, sizeof(buffer));
    return fallback + u": "_s + QString::fromLatin1(buffer);
}
}

namespace SquirrelReleaseValidator
{
bool isStrictVersion(const QString &version)
{
    static const QRegularExpression expression(
            uR"(^[0-9]+\.[0-9]+\.[0-9]+$)"_s,
            QRegularExpression::UseUnicodePropertiesOption);
    return version.size() <= 64 && expression.match(version).hasMatch();
}

bool findFullRelease(const QByteArray &manifest, const QString &packageId,
        const QString &version, ReleaseEntry *entry, QString *error)
{
    if (manifest.isEmpty() || manifest.size() > kMaximumManifestBytes)
    {
        if (error)
            *error = u"RELEASES is empty or exceeds the 1 MiB limit"_s;
        return false;
    }
    if (packageId != QString::fromLatin1(kPackageId) || !isStrictVersion(version))
    {
        if (error)
            *error = u"Unexpected package identity or non-canonical version"_s;
        return false;
    }

    const QString expectedName = packageId + u'-' + version + u"-full.nupkg"_s;
    static const QRegularExpression lineExpression(
            uR"(^([0-9A-Fa-f]{40})[ \t]+([^\s]+)[ \t]+([0-9]+)$)"_s);

    ReleaseEntry match;
    int matches = 0;
    const QList<QByteArray> lines = manifest.split('\n');
    for (QByteArray rawLine : lines)
    {
        if (rawLine.endsWith('\r'))
            rawLine.chop(1);
        const QString line = QString::fromLatin1(rawLine);
        const QRegularExpressionMatch parsed = lineExpression.match(line);
        if (!parsed.hasMatch() || parsed.captured(2) != expectedName)
            continue;

        bool sizeOk = false;
        const qint64 size = parsed.captured(3).toLongLong(&sizeOk);
        if (!sizeOk || size <= 0)
        {
            if (error)
                *error = u"The target full-package row has an invalid byte length"_s;
            return false;
        }

        ++matches;
        match.rawLine = rawLine;
        match.sha1Hex = parsed.captured(1).toLatin1().toLower();
        match.fileName = parsed.captured(2);
        match.size = size;
    }

    if (matches != 1)
    {
        if (error)
        {
            *error = (matches == 0)
                    ? u"The signed manifest does not contain the expected full package"_s
                    : u"The signed manifest contains duplicate target full-package rows"_s;
        }
        return false;
    }

    if (entry)
        *entry = match;
    return true;
}

bool verifyManifestSignature(const QByteArray &manifest, const QByteArray &signature,
        const QByteArray &publicKeyJson, QString *error)
{
    if (manifest.isEmpty() || manifest.size() > kMaximumManifestBytes
            || signature.isEmpty() || signature.size() > kMaximumSignatureBytes)
    {
        if (error)
            *error = u"Signed update metadata is empty or exceeds its safety limit"_s;
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(publicKeyJson, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
    {
        if (error)
            *error = u"The pinned update public-key resource is not valid JSON"_s;
        return false;
    }

    const QJsonObject object = document.object();
    if (object.value(u"schemaVersion"_s).toInt(-1) != 1
            || object.value(u"algorithm"_s).toString() != QString::fromLatin1(kAlgorithm)
            || object.value(u"spkiSha256"_s).toString() != QString::fromLatin1(kPinnedSpkiSha256))
    {
        if (error)
            *error = u"The pinned update public-key identity or algorithm is unexpected"_s;
        return false;
    }

    const QByteArray spki = QByteArray::fromBase64(
            object.value(u"spkiDerBase64"_s).toString().toLatin1(),
            QByteArray::AbortOnBase64DecodingErrors);
    const QByteArray fingerprint = QCryptographicHash::hash(spki, QCryptographicHash::Sha256)
                                           .toHex().toLower();
    if (spki.isEmpty() || fingerprint != QByteArray(kPinnedSpkiSha256))
    {
        if (error)
            *error = u"The update public key does not match the compiled fingerprint"_s;
        return false;
    }

    const unsigned char *cursor = reinterpret_cast<const unsigned char *>(spki.constData());
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> key(
            d2i_PUBKEY(nullptr, &cursor, spki.size()), EVP_PKEY_free);
    if (!key || (cursor != reinterpret_cast<const unsigned char *>(spki.constData()) + spki.size())
            || !EVP_PKEY_is_a(key.get(), "RSA") || EVP_PKEY_get_bits(key.get()) < 3072)
    {
        if (error)
            *error = opensslError(u"The pinned update public key is not a valid RSA-3072 SPKI"_s);
        return false;
    }
    if (signature.size() != EVP_PKEY_get_size(key.get()))
    {
        if (error)
            *error = u"The update signature length does not match the pinned key"_s;
        return false;
    }

    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(
            EVP_MD_CTX_new(), EVP_MD_CTX_free);
    EVP_PKEY_CTX *keyContext = nullptr;
    if (!context
            || EVP_DigestVerifyInit(context.get(), &keyContext, EVP_sha256(), nullptr,
                       key.get()) != 1
            || !keyContext || EVP_PKEY_CTX_set_rsa_padding(keyContext, RSA_PKCS1_PADDING) <= 0
            || EVP_DigestVerifyUpdate(context.get(), manifest.constData(), manifest.size()) != 1
            || EVP_DigestVerifyFinal(context.get(),
                       reinterpret_cast<const unsigned char *>(signature.constData()),
                       signature.size()) != 1)
    {
        if (error)
            *error = opensslError(u"The RELEASES signature is invalid"_s);
        return false;
    }
    return true;
}

bool verifyPackageFile(const QString &path, const ReleaseEntry &entry, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        if (error)
            *error = u"Could not open the package for verification: "_s + file.errorString();
        return false;
    }
    if (file.size() != entry.size)
    {
        if (error)
            *error = u"The package byte length does not match signed RELEASES metadata"_s;
        return false;
    }

    QCryptographicHash hash(QCryptographicHash::Sha1);
    QByteArray buffer;
    buffer.resize(kHashBufferBytes);
    while (!file.atEnd())
    {
        const qint64 count = file.read(buffer.data(), buffer.size());
        if (count <= 0)
        {
            if (error)
                *error = u"Could not read the complete package during verification"_s;
            return false;
        }
        hash.addData(QByteArrayView(buffer.constData(), count));
    }

    if (hash.result().toHex().toLower() != entry.sha1Hex.toLower())
    {
        if (error)
            *error = u"The package SHA-1 does not match signed RELEASES metadata"_s;
        return false;
    }
    return true;
}
}
