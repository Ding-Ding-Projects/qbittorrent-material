/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026 qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QByteArray>
#include <QString>

namespace SquirrelReleaseValidator
{
struct ReleaseEntry
{
    QByteArray rawLine;
    QByteArray sha1Hex;
    QString fileName;
    qint64 size = -1;
};

[[nodiscard]] bool isStrictVersion(const QString &version);

/** Find exactly one full-package row for packageId/version in RELEASES. */
[[nodiscard]] bool findFullRelease(const QByteArray &manifest, const QString &packageId,
        const QString &version, ReleaseEntry *entry, QString *error);

/**
 * Verify a raw RSA PKCS#1 v1.5/SHA-256 signature using the pinned public-key
 * resource. The fingerprint is compiled into the application as a second,
 * independent identity check; replacing only the JSON resource cannot change
 * update authority.
 */
[[nodiscard]] bool verifyManifestSignature(const QByteArray &manifest,
        const QByteArray &signature, const QByteArray &publicKeyJson, QString *error);

/** Verify the exact byte length and SHA-1 recorded by the signed manifest. */
[[nodiscard]] bool verifyPackageFile(const QString &path, const ReleaseEntry &entry,
        QString *error);
}
