/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "preferencescontroller.h"

#include <QQmlEngine>

#include "base/logging.h"
#include "base/preferences.h"

PreferencesController *PreferencesController::create(QQmlEngine *, QJSEngine *)
{
    qCInfo(lcUi) << "Preferences QML singleton requested";
    return new PreferencesController;
}

PreferencesController::PreferencesController(QObject *parent)
    : QObject(parent)
    , m_preferences(Preferences::instance())
{
    Q_ASSERT_X(m_preferences, "PreferencesController",
        "Preferences must be initialized before the QML module is loaded");

    if (m_preferences)
    {
        connect(m_preferences, &Preferences::changed,
            this, &PreferencesController::changed);
        qCDebug(lcUi) << "PreferencesController subscribed to Preferences";
    }
    else
    {
        qCCritical(lcUi) << "PreferencesController created without native Preferences";
    }
}

QVariant PreferencesController::value(const QString &key, const QVariant &defaultValue) const
{
    return m_preferences ? m_preferences->value(key, defaultValue) : defaultValue;
}

void PreferencesController::setValue(const QString &key, const QVariant &value)
{
    if (m_preferences)
        m_preferences->setValue(key, value);
}

void PreferencesController::apply()
{
    if (m_preferences)
        m_preferences->apply();
}

bool PreferencesController::confirmOnExit() const
{
    return m_preferences ? m_preferences->confirmOnExit() : true;
}

void PreferencesController::setConfirmOnExit(const bool confirm)
{
    if (m_preferences)
        m_preferences->setConfirmOnExit(confirm);
}

bool PreferencesController::isToolbarDisplayed() const
{
    return m_preferences ? m_preferences->isToolbarDisplayed() : true;
}

void PreferencesController::setToolbarDisplayed(const bool displayed)
{
    if (m_preferences)
        m_preferences->setToolbarDisplayed(displayed);
}

bool PreferencesController::isStatusbarDisplayed() const
{
    return m_preferences ? m_preferences->isStatusbarDisplayed() : true;
}

void PreferencesController::setStatusbarDisplayed(const bool displayed)
{
    if (m_preferences)
        m_preferences->setStatusbarDisplayed(displayed);
}

bool PreferencesController::isStatusbarFreeDiskSpaceDisplayed() const
{
    return m_preferences ? m_preferences->isStatusbarFreeDiskSpaceDisplayed() : false;
}

void PreferencesController::setStatusbarFreeDiskSpaceDisplayed(const bool displayed)
{
    if (m_preferences)
        m_preferences->setStatusbarFreeDiskSpaceDisplayed(displayed);
}

bool PreferencesController::isStatusbarExternalIPDisplayed() const
{
    return m_preferences ? m_preferences->isStatusbarExternalIPDisplayed() : false;
}

void PreferencesController::setStatusbarExternalIPDisplayed(const bool displayed)
{
    if (m_preferences)
        m_preferences->setStatusbarExternalIPDisplayed(displayed);
}

bool PreferencesController::isFiltersSidebarVisible() const
{
    return m_preferences ? m_preferences->isFiltersSidebarVisible() : true;
}

void PreferencesController::setFiltersSidebarVisible(const bool visible)
{
    if (m_preferences)
        m_preferences->setFiltersSidebarVisible(visible);
}

bool PreferencesController::speedInTitleBar() const
{
    return m_preferences ? m_preferences->speedInTitleBar() : false;
}

void PreferencesController::showSpeedInTitleBar(const bool show)
{
    if (m_preferences)
        m_preferences->showSpeedInTitleBar(show);
}

bool PreferencesController::isSearchEnabled() const
{
    // Mirror Preferences' own default so there is one answer to "is search on".
    return m_preferences ? m_preferences->isSearchEnabled() : true;
}

void PreferencesController::setSearchEnabled(const bool enabled)
{
    if (m_preferences)
        m_preferences->setSearchEnabled(enabled);
}

bool PreferencesController::isRSSWidgetEnabled() const
{
    return m_preferences ? m_preferences->isRSSWidgetEnabled() : false;
}

void PreferencesController::setRSSWidgetVisible(const bool enabled)
{
    if (m_preferences)
        m_preferences->setRSSWidgetVisible(enabled);
}

bool PreferencesController::shutdownqBTWhenDownloadsComplete() const
{
    return m_preferences ? m_preferences->shutdownqBTWhenDownloadsComplete() : false;
}

void PreferencesController::setShutdownqBTWhenDownloadsComplete(const bool enabled)
{
    if (m_preferences)
        m_preferences->setShutdownqBTWhenDownloadsComplete(enabled);
}

bool PreferencesController::suspendWhenDownloadsComplete() const
{
    return m_preferences ? m_preferences->suspendWhenDownloadsComplete() : false;
}

void PreferencesController::setSuspendWhenDownloadsComplete(const bool enabled)
{
    if (m_preferences)
        m_preferences->setSuspendWhenDownloadsComplete(enabled);
}

bool PreferencesController::hibernateWhenDownloadsComplete() const
{
    return m_preferences ? m_preferences->hibernateWhenDownloadsComplete() : false;
}

void PreferencesController::setHibernateWhenDownloadsComplete(const bool enabled)
{
    if (m_preferences)
        m_preferences->setHibernateWhenDownloadsComplete(enabled);
}

bool PreferencesController::rebootWhenDownloadsComplete() const
{
    return m_preferences ? m_preferences->rebootWhenDownloadsComplete() : false;
}

void PreferencesController::setRebootWhenDownloadsComplete(const bool enabled)
{
    if (m_preferences)
        m_preferences->setRebootWhenDownloadsComplete(enabled);
}

bool PreferencesController::shutdownWhenDownloadsComplete() const
{
    return m_preferences ? m_preferences->shutdownWhenDownloadsComplete() : false;
}

void PreferencesController::setShutdownWhenDownloadsComplete(const bool enabled)
{
    if (m_preferences)
        m_preferences->setShutdownWhenDownloadsComplete(enabled);
}
