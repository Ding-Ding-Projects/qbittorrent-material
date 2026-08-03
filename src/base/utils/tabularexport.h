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

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariant>

#include <optional>

/// Serialization of any tabular view the application owns into every text
/// format that can faithfully carry it.
///
/// A format is offered only where it can represent the rows without silently
/// dropping a field, and where one loses something the caller can state that
/// before the export runs rather than after (see @ref lossNote).
namespace Utils::TabularExport
{
    enum class Format
    {
        Json = 0,
        JsonLines,
        Yaml,
        Toml,
        Xml,
        Csv,
        Tsv,
        Markdown,
        Html,
        Sql
    };

    /// One exportable table: a header row and the rows beneath it.
    struct Table
    {
        /// Column titles in order; also the field names in keyed formats.
        QStringList headers;
        /// Row-major cells. A short row is padded with empty values.
        QList<QVariantList> rows;
        /// Identifier used where a format needs one (XML element, SQL table).
        QString name = QStringLiteral("export");
    };

    /// The conventional file-name extension for @a format.
    [[nodiscard]] QString extension(Format format);

    /// The display name of @a format, for a format picker.
    [[nodiscard]] QString displayName(Format format);

    /// What @a format cannot carry for this shape, or an empty string when it
    /// is lossless. Shown to the user before the export runs.
    [[nodiscard]] QString lossNote(Format format);

    /// Every format, in presentation order.
    [[nodiscard]] QList<Format> allFormats();

    /// Parses a format from its lower-case token ("json", "csv", …).
    [[nodiscard]] std::optional<Format> fromToken(const QString &token);

    /// The lower-case token for @a format.
    [[nodiscard]] QString token(Format format);

    /// Serializes @a table as @a format. Always UTF-8, always LF line endings,
    /// so the file is readable by something other than the app that wrote it.
    [[nodiscard]] QByteArray serialize(const Table &table, Format format);
}
