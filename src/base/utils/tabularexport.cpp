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

#include "tabularexport.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QMetaType>
#include <QRegularExpression>

#include <cmath>

using namespace Qt::StringLiterals;

namespace
{
    /// A cell rendered as plain text, without any format's quoting applied.
    QString plainText(const QVariant &value)
    {
        if (!value.isValid() || value.isNull())
            return {};

        switch (value.typeId())
        {
        case QMetaType::Bool:
            return value.toBool() ? u"true"_s : u"false"_s;
        case QMetaType::QDateTime:
            // UTC ISO-8601 makes exports stable across Windows time zones.
            return value.toDateTime().toUTC().toString(Qt::ISODateWithMs);
        case QMetaType::QDate:
            return value.toDate().toString(Qt::ISODate);
        default:
            return value.toString();
        }
    }

    bool isNumeric(const QVariant &value)
    {
        switch (value.typeId())
        {
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
        case QMetaType::ULongLong:
        case QMetaType::Double:
        case QMetaType::Float:
            return true;
        default:
            return false;
        }
    }

    bool isBoolean(const QVariant &value)
    {
        return (value.typeId() == QMetaType::Bool);
    }

    bool isFiniteNumeric(const QVariant &value)
    {
        return isNumeric(value) && std::isfinite(value.toDouble());
    }

    QString scalarText(const QVariant &value)
    {
        if (isNumeric(value) && !isFiniteNumeric(value))
        {
            const double number = value.toDouble();
            if (std::isnan(number))
                return u"NaN"_s;
            return (number < 0) ? u"-Infinity"_s : u"Infinity"_s;
        }
        return plainText(value);
    }

    QJsonValue jsonValue(const QVariant &value)
    {
        if (value.typeId() == QMetaType::QDateTime)
            return scalarText(value);
        if (value.typeId() == QMetaType::QDate)
            return scalarText(value);
        if (isNumeric(value) && !isFiniteNumeric(value))
            return scalarText(value);
        return QJsonValue::fromVariant(value);
    }

    /// A header turned into an identifier usable as a key in keyed formats.
    QString identifier(const QString &header)
    {
        static const QRegularExpression invalid {u"[^A-Za-z0-9_]+"_s};
        QString key = header.simplified().replace(invalid, u"_"_s).toLower();
        while (key.endsWith(u'_'))
            key.chop(1);
        while (key.startsWith(u'_'))
            key.remove(0, 1);
        if (!key.isEmpty() && key.front().isDigit())
            key.prepend(u"field_"_s);
        if (key.startsWith(u"xml"_s, Qt::CaseInsensitive))
            key.prepend(u"field_"_s);
        return key.isEmpty() ? u"field"_s : key;
    }

    QStringList identifiers(const QStringList &headers)
    {
        QStringList keys;
        keys.reserve(headers.size());
        for (const QString &header : headers)
        {
            QString key = identifier(header);
            // Two headers can normalize to the same key; keep them distinct so
            // a keyed format cannot silently drop one of the columns.
            int suffix = 2;
            const QString base = key;
            while (keys.contains(key))
                key = base + QString::number(suffix++);
            keys.append(key);
        }
        return keys;
    }

    QString escapeXml(const QString &text)
    {
        // XML 1.0 permits only tab, LF, CR, and printable Unicode ranges.
        // Torrent metadata is user-controlled, so omit forbidden controls
        // instead of emitting a document consumers cannot parse.
        QString out;
        out.reserve(text.size());
        for (qsizetype i = 0; i < text.size(); ++i)
        {
            const ushort first = text.at(i).unicode();
            uint codePoint = first;
            qsizetype width = 1;
            if ((first >= 0xD800) && (first <= 0xDBFF))
            {
                if ((i + 1) >= text.size())
                    continue;
                const ushort second = text.at(i + 1).unicode();
                if ((second < 0xDC00) || (second > 0xDFFF))
                    continue;
                codePoint = 0x10000u + ((static_cast<uint>(first) - 0xD800u) << 10)
                    + (static_cast<uint>(second) - 0xDC00u);
                width = 2;
            }
            else if ((first >= 0xDC00) && (first <= 0xDFFF))
            {
                continue;
            }

            const bool valid = (codePoint == 0x9) || (codePoint == 0xA)
                || (codePoint == 0xD) || ((codePoint >= 0x20) && (codePoint <= 0xD7FF))
                || ((codePoint >= 0xE000) && (codePoint <= 0xFFFD))
                || ((codePoint >= 0x10000) && (codePoint <= 0x10FFFF));
            if (valid)
            {
                const QString character = text.mid(i, width);
                switch (codePoint)
                {
                case '&': out += u"&amp;"_s; break;
                case '<': out += u"&lt;"_s; break;
                case '>': out += u"&gt;"_s; break;
                case '"': out += u"&quot;"_s; break;
                case '\'': out += u"&apos;"_s; break;
                default: out += character; break;
                }
            }
            if (width == 2)
                ++i;
        }
        return out;
    }

    /// RFC 4180: quote when the field holds the delimiter, a quote, or a line
    /// break, and double any embedded quote.
    QString escapeDelimited(const QString &text, const QChar delimiter)
    {
        const bool needsQuoting = text.contains(delimiter) || text.contains(u'"')
            || text.contains(u'\n') || text.contains(u'\r');
        if (!needsQuoting)
            return text;

        QString quoted = text;
        quoted.replace(u"\""_s, u"\"\""_s);
        return u'"' + quoted + u'"';
    }

    QString escapeQuotedScalar(const QString &text)
    {
        QString quoted;
        quoted.reserve(text.size());
        for (const QChar character : text)
        {
            const uint codePoint = character.unicode();
            switch (codePoint)
            {
            case '\\': quoted += u"\\\\"_s; break;
            case '"': quoted += u"\\\""_s; break;
            case '\b': quoted += u"\\b"_s; break;
            case '\f': quoted += u"\\f"_s; break;
            case '\n': quoted += u"\\n"_s; break;
            case '\r': quoted += u"\\r"_s; break;
            case '\t': quoted += u"\\t"_s; break;
            default:
                if ((codePoint < 0x20) || (codePoint == 0x7F))
                    quoted += u"\\u%1"_s.arg(static_cast<int>(codePoint), 4, 16, QChar(u'0'));
                else
                    quoted += character;
                break;
            }
        }
        return u'"' + quoted + u'"';
    }

    QString escapeYaml(const QString &text)
    {
        // Always quote: it is valid for every scalar and removes any chance of
        // a bare value being reinterpreted as a bool, a number, or null.
        return escapeQuotedScalar(text);
    }

    QString escapeToml(const QString &text)
    {
        // TOML basic strings and YAML double-quoted scalars share these safe
        // JSON-style escapes for the values exported here.
        return escapeQuotedScalar(text);
    }

    QString escapeSql(const QString &text)
    {
        QString escaped = text;
        escaped.replace(u"'"_s, u"''"_s);
        return u'\'' + escaped + u'\'';
    }

    QString quoteSqlIdentifier(const QString &text)
    {
        QString quoted = text;
        quoted.replace(u'"', u"\"\""_s);
        return u'"' + quoted + u'"';
    }

    QString escapeMarkdown(const QString &text)
    {
        // Keep metadata literal inside a Markdown table. Escape table
        // delimiters and common inline-markup punctuation, and flatten line
        // breaks because a newline would end the row.
        QString escaped;
        escaped.reserve(text.size());
        for (const QChar character : text)
        {
            if ((character == u'\n') || (character == u'\r'))
            {
                escaped += u' ';
                continue;
            }
            const ushort codePoint = character.unicode();
            const bool punctuation = (codePoint == '\\') || (codePoint == '|')
                || (codePoint == '*') || (codePoint == '_') || (codePoint == 0x60)
                || (codePoint == '[') || (codePoint == ']') || (codePoint == '<')
                || (codePoint == '>') || (codePoint == '~');
            if (punctuation)
                escaped += u'\\';
            escaped += character;
        }
        return escaped;
    }

    QString delimitedText(const QVariant &value)
    {
        QString text = scalarText(value);
        // CSV/TSV are frequently opened directly in spreadsheet software.
        // Prefix formula-looking strings so torrent metadata cannot be
        // interpreted as formulas on open. Numeric QVariant values remain
        // numeric-looking text and are not altered.
        if ((value.typeId() == QMetaType::QString) && !text.isEmpty()
            && u"=+-@"_s.contains(text.front()))
        {
            text.prepend(u'\'');
        }
        return text;
    }

    /// Pads a short row so every format emits the full column count.
    QVariantList normalizedRow(const QVariantList &row, const int columns)
    {
        QVariantList padded = row;
        while (padded.size() < columns)
            padded.append(QVariant {});
        if (padded.size() > columns)
            padded = padded.mid(0, columns);
        return padded;
    }
}

QString Utils::TabularExport::extension(const Format format)
{
    switch (format)
    {
    case Format::Json: return u"json"_s;
    case Format::JsonLines: return u"jsonl"_s;
    case Format::Yaml: return u"yaml"_s;
    case Format::Toml: return u"toml"_s;
    case Format::Xml: return u"xml"_s;
    case Format::Csv: return u"csv"_s;
    case Format::Tsv: return u"tsv"_s;
    case Format::Markdown: return u"md"_s;
    case Format::Html: return u"html"_s;
    case Format::Sql: return u"sql"_s;
    }
    return u"txt"_s;
}

QString Utils::TabularExport::token(const Format format)
{
    return extension(format);
}

std::optional<Utils::TabularExport::Format> Utils::TabularExport::fromToken(const QString &value)
{
    const QString needle = value.trimmed().toLower();
    for (const Format format : allFormats())
    {
        if (token(format) == needle)
            return format;
    }
    return std::nullopt;
}

QString Utils::TabularExport::displayName(const Format format)
{
    switch (format)
    {
    case Format::Json: return QCoreApplication::translate("TabularExport", "JSON");
    case Format::JsonLines: return QCoreApplication::translate("TabularExport", "JSON Lines");
    case Format::Yaml: return QCoreApplication::translate("TabularExport", "YAML");
    case Format::Toml: return QCoreApplication::translate("TabularExport", "TOML");
    case Format::Xml: return QCoreApplication::translate("TabularExport", "XML");
    case Format::Csv: return QCoreApplication::translate("TabularExport", "CSV");
    case Format::Tsv: return QCoreApplication::translate("TabularExport", "TSV");
    case Format::Markdown: return QCoreApplication::translate("TabularExport", "Markdown");
    case Format::Html: return QCoreApplication::translate("TabularExport", "HTML");
    case Format::Sql: return QCoreApplication::translate("TabularExport", "SQL");
    }
    return {};
}

QString Utils::TabularExport::lossNote(const Format format)
{
    switch (format)
    {
    case Format::Json:
    case Format::JsonLines:
        return QCoreApplication::translate("TabularExport",
            "Object keys are normalized from the displayed column labels. Date/time values use UTC ISO-8601 text, and non-finite numbers are represented as strings.");
    case Format::Yaml:
    case Format::Toml:
        return QCoreApplication::translate("TabularExport",
            "Values without a native scalar representation, such as date/time or non-finite numeric values, are exported as quoted text; null and empty values become the same quoted empty text.");
    case Format::Markdown:
        return QCoreApplication::translate("TabularExport",
            "Values become text, Markdown punctuation is escaped, and line breaks inside a cell become spaces because a newline would end the table row.");
    case Format::Csv:
    case Format::Tsv:
        return QCoreApplication::translate("TabularExport",
            "Every value becomes text; number/string/empty distinctions are not preserved, and formula-looking text is prefixed with an apostrophe for spreadsheet safety.");
    case Format::Xml:
    case Format::Html:
        return QCoreApplication::translate("TabularExport",
            "Every value becomes escaped text; numeric, boolean, date/time, and empty-value distinctions are not preserved, and invalid XML 1.0 control characters are omitted.");
    case Format::Sql:
        return QCoreApplication::translate("TabularExport",
            "Null values remain NULL; non-null values are stored as TEXT, so the original scalar types are not preserved. Apostrophes are escaped using standard SQL string-literal rules; backslashes remain literal data.");
    }
    return {};
}

QList<Utils::TabularExport::Format> Utils::TabularExport::allFormats()
{
    return {Format::Json, Format::JsonLines, Format::Yaml, Format::Toml, Format::Xml,
        Format::Csv, Format::Tsv, Format::Markdown, Format::Html, Format::Sql};
}

QByteArray Utils::TabularExport::serialize(const Table &table, const Format format)
{
    const int columns = static_cast<int>(table.headers.size());
    const QStringList keys = identifiers(table.headers);
    const QString tableName = identifier(table.name);
    QString out;

    const auto appendDelimited = [&](const QChar delimiter)
    {
        QStringList header;
        for (const QString &title : table.headers)
            header.append(escapeDelimited(title, delimiter));
        out += header.join(delimiter) + u'\n';

        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            QStringList line;
            for (const QVariant &cell : cells)
                line.append(escapeDelimited(delimitedText(cell), delimiter));
            out += line.join(delimiter) + u'\n';
        }
    };

    switch (format)
    {
    case Format::Json:
    {
        QJsonArray array;
        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            QJsonObject object;
            for (int i = 0; i < columns; ++i)
                object.insert(keys.at(i), jsonValue(cells.at(i)));
            array.append(object);
        }
        return QJsonDocument(array).toJson(QJsonDocument::Indented);
    }

    case Format::JsonLines:
    {
        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            QJsonObject object;
            for (int i = 0; i < columns; ++i)
                object.insert(keys.at(i), jsonValue(cells.at(i)));
            out += QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact)) + u'\n';
        }
        break;
    }

    case Format::Yaml:
    {
        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            for (int i = 0; i < columns; ++i)
            {
                out += (i == 0) ? u"- "_s : u"  "_s;
                out += keys.at(i) + u": "_s
                    + ((isFiniteNumeric(cells.at(i)) || isBoolean(cells.at(i)))
                        ? scalarText(cells.at(i))
                        : escapeYaml(scalarText(cells.at(i))))
                    + u'\n';
            }
        }
        break;
    }

    case Format::Toml:
    {
        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            out += u"[["_s + tableName + u"]]\n"_s;
            for (int i = 0; i < columns; ++i)
            {
                out += keys.at(i) + u" = "_s
                    + ((isFiniteNumeric(cells.at(i)) || isBoolean(cells.at(i)))
                        ? scalarText(cells.at(i))
                        : escapeToml(scalarText(cells.at(i))))
                    + u'\n';
            }
            out += u'\n';
        }
        break;
    }

    case Format::Xml:
    {
        out += u"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"_s;
        out += u'<' + tableName + u">\n"_s;
        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            out += u"  <row>\n"_s;
            for (int i = 0; i < columns; ++i)
            {
                out += u"    <"_s + keys.at(i) + u'>'
                    + escapeXml(scalarText(cells.at(i)))
                    + u"</"_s + keys.at(i) + u">\n"_s;
            }
            out += u"  </row>\n"_s;
        }
        out += u"</"_s + tableName + u">\n"_s;
        break;
    }

    case Format::Csv:
        appendDelimited(u',');
        break;

    case Format::Tsv:
        appendDelimited(u'\t');
        break;

    case Format::Markdown:
    {
        QStringList header;
        QStringList rule;
        for (const QString &title : table.headers)
        {
            header.append(escapeMarkdown(title));
            rule.append(u"---"_s);
        }
        out += u"| "_s + header.join(u" | "_s) + u" |\n"_s;
        out += u"| "_s + rule.join(u" | "_s) + u" |\n"_s;

        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            QStringList line;
            for (const QVariant &cell : cells)
                line.append(escapeMarkdown(scalarText(cell)));
            out += u"| "_s + line.join(u" | "_s) + u" |\n"_s;
        }
        break;
    }

    case Format::Html:
    {
        out += u"<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"_s;
        out += u"<meta charset=\"utf-8\">\n<title>"_s + escapeXml(table.name) + u"</title>\n"_s;
        out += u"</head>\n<body>\n<table>\n<thead>\n<tr>"_s;
        for (const QString &title : table.headers)
            out += u"<th>"_s + escapeXml(title) + u"</th>"_s;
        out += u"</tr>\n</thead>\n<tbody>\n"_s;

        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            out += u"<tr>"_s;
            for (const QVariant &cell : cells)
                out += u"<td>"_s + escapeXml(scalarText(cell)) + u"</td>"_s;
            out += u"</tr>\n"_s;
        }
        out += u"</tbody>\n</table>\n</body>\n</html>\n"_s;
        break;
    }

    case Format::Sql:
    {
        const QString sqlTableName = quoteSqlIdentifier(tableName);
        QStringList sqlKeys;
        sqlKeys.reserve(keys.size());
        for (const QString &key : keys)
            sqlKeys.append(quoteSqlIdentifier(key));

        out += u"CREATE TABLE IF NOT EXISTS "_s + sqlTableName + u" (\n"_s;
        QStringList columnDefs;
        for (const QString &key : sqlKeys)
            columnDefs.append(u"  "_s + key + u" TEXT"_s);
        out += columnDefs.join(u",\n"_s) + u"\n);\n"_s;

        for (const QVariantList &row : table.rows)
        {
            const QVariantList cells = normalizedRow(row, columns);
            QStringList values;
            for (const QVariant &cell : cells)
            {
                values.append(cell.isValid() && !cell.isNull()
                    ? escapeSql(scalarText(cell)) : u"NULL"_s);
            }
            out += u"INSERT INTO "_s + sqlTableName + u" ("_s + sqlKeys.join(u", "_s)
                + u") VALUES ("_s + values.join(u", "_s) + u");\n"_s;
        }
        break;
    }
    }

    return out.toUtf8();
}
