/*
 * qBittorrent (Material rewrite) — Squirrel.Windows lifecycle integration
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <QStringList>

#include <optional>

namespace SquirrelLifecycle
{
    // Returns an exit code when a Squirrel lifecycle command was handled.
    // std::nullopt means this is an ordinary application launch.
    std::optional<int> handle(const QStringList &arguments);
}
