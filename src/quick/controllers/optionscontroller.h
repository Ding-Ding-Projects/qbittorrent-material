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

#include <QObject>
#include <QString>
#include <QStringList>
#include <QSet>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <qqmlintegration.h>

class QQmlEngine;
class QJSEngine;
class AdvancedSettingsModel;
class WatchedFoldersModel;

/**
 * @file optionscontroller.h
 * @brief The @c OptionsController QML singleton — bridges the whole Options dialog
 *        (all 9 tabs) to the engine.
 *
 * The Options dialog is a staged editor: every control reads its value from this
 * controller's in-memory staging map (via @ref value) and writes edits back (via
 * @ref setValue) without touching the engine. Only when the user presses OK/Apply
 * does @ref apply commit the entire staging map to
 * @c Preferences / @c BitTorrent::Session / @c Net::ProxyConfigurationManager /
 * @c Net::PortForwarder / @c ThemeManager / @c TorrentFileGuard, then call
 * @c Preferences::apply(). Cancel simply drops the staging map (@ref reset).
 *
 * Values are addressed by stable camelCase string keys (see the loaders in the
 * .cpp). The controller is intentionally engine-typed on write so setting keys and
 * enum numeric values stay identical to legacy qBittorrent.
 *
 * The Advanced tab and watched-folders view are backed by dedicated models
 * (@c AdvancedSettingsModel, @c WatchedFoldersModel) owned by this controller.
 * Their staged state participates in this controller's `modified`, `apply()` and
 * `reset()` contract, so QML has one atomic transaction for the entire dialog.
 *
 * Language and its two funny levels are staged like every other option. On
 * @ref apply, the controller persists all three and emits one atomic bridge
 * signal so the QML layer can live-retranslate without stale OK/Cancel state.
 */
class OptionsController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_DISABLE_COPY_MOVE(OptionsController)

    /// True when the staging map differs from the last-loaded engine state
    /// (drives the Apply button's enabled state).
    Q_PROPERTY(bool modified READ isModified NOTIFY modifiedChanged)
    /// True when a staged change requires an application restart to take effect.
    Q_PROPERTY(bool restartRequired READ isRestartRequired NOTIFY restartRequiredChanged)
    /// Persisted index of the last-viewed tab (`GUI/Preferences/LastViewedPage`).
    Q_PROPERTY(int lastViewedTab READ lastViewedTab WRITE setLastViewedTab NOTIFY lastViewedTabChanged)
    /// Monotonic cursor used to make value(key) QML bindings reactive.
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    /// Staged watched-folders list used by the Downloads page.
    Q_PROPERTY(QObject *watchedFoldersModel READ watchedFoldersModel CONSTANT)
    /// Whether the staged Web UI API key is non-empty.
    Q_PROPERTY(bool apiKeyValid READ apiKeyValid NOTIFY apiKeyValidChanged)
    /// Whether this platform exposes the Windows Default Apps settings action.
    Q_PROPERTY(bool windowsDefaultAppsAvailable READ windowsDefaultAppsAvailable CONSTANT)

public:
    /// Tab order — mirrors the legacy `OptionsDialog::Tabs` enum exactly.
    enum Tab
    {
        BehaviorTab = 0,
        DownloadsTab = 1,
        ConnectionTab = 2,
        SpeedTab = 3,
        BitTorrentTab = 4,
        SearchTab = 5,
        RSSTab = 6,
        WebUITab = 7,
        AdvancedTab = 8
    };
    Q_ENUM(Tab)

    /// QML singleton factory — returns the shared instance.
    static OptionsController *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    /// Return the live singleton for native restart preflight checks.
    static OptionsController *existingInstance();

    explicit OptionsController(QObject *parent = nullptr);
    ~OptionsController() override;

    bool isModified() const;
    bool isRestartRequired() const { return m_restartRequired; }
    int revision() const { return m_revision; }
    QObject *watchedFoldersModel() const;
    bool apiKeyValid() const;
    bool windowsDefaultAppsAvailable() const;

    int lastViewedTab() const;
    void setLastViewedTab(int tab);

    // --- QML staging API ---------------------------------------------------

    /// The staged value for @p key (or @p defaultValue if unknown).
    Q_INVOKABLE QVariant value(const QString &key, const QVariant &defaultValue = {}) const;

    /// Stage a new value for @p key. Marks the dialog modified (and flags a
    /// restart requirement for restart-only keys).
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);

    /// (Re)load the staging map for every tab from the engine, discarding edits.
    Q_INVOKABLE void load();

    /// Commit the staging map to the engine. Returns false if cross-tab validation
    /// fails (the offending tab is reported via @ref validationFailed).
    Q_INVOKABLE bool apply();

    /// Discard staged edits and reload from the engine (Cancel / Reset).
    Q_INVOKABLE void reset();

    /// Helper for the Connection tab "Random" port button.
    Q_INVOKABLE int randomPort() const;

    /// Network choices for the Advanced page. Each item has `text` and `value`.
    Q_INVOKABLE QVariantList networkInterfaces() const;
    Q_INVOKABLE QVariantList networkInterfaceAddresses() const;

    // Watched-folder staging facade. The view deliberately talks only to this
    // controller so its Apply/OK/Cancel semantics cannot diverge from the rest
    // of the dialog.
    Q_INVOKABLE QVariantMap watchedFolderOptions(int row) const;
    Q_INVOKABLE bool addWatchedFolder(const QString &path, const QVariantMap &options = {});
    Q_INVOKABLE void setWatchedFolderOptions(int row, const QVariantMap &options);
    Q_INVOKABLE void removeWatchedFolder(int row);

    // Web UI API-key actions are staged until Apply/OK.
    Q_INVOKABLE QString maskedApiKey() const;
    Q_INVOKABLE void rotateApiKey();
    Q_INVOKABLE void deleteApiKey();
    Q_INVOKABLE bool copyApiKeyToClipboard() const;

    /// Validate an exact IPv4 or IPv6 address using the same libtorrent parser
    /// that filters the staged manual-ban list during Session apply.
    Q_INVOKABLE bool isValidBannedIPAddress(const QString &address) const;
    /// Validate an IPv4 or IPv6 subnet using the same parser Preferences uses
    /// before persisting the Web UI authentication-subnet whitelist.
    Q_INVOKABLE bool isValidWebUISubnet(const QString &subnet) const;

    // Best-effort actions exposed by option pages.
    Q_INVOKABLE void reloadIPFilter();
    Q_INVOKABLE void sendTestEmail();
    Q_INVOKABLE void openDynDNSRegistration();
    /// Open Windows' per-user Default Apps settings through the system Explorer.
    Q_INVOKABLE void openWindowsDefaultApps();

signals:
    void modifiedChanged();
    void restartRequiredChanged();
    void lastViewedTabChanged();
    void revisionChanged();
    void apiKeyValidChanged();

    /// Result of validating/reloading the staged IP-filter file.
    void ipFilterParsed(bool error, int ruleCount);
    /// Human-readable feedback for best-effort actions (`testEmail`, `dynDNS`).
    void actionFeedback(const QString &action, bool success, const QString &message);

    /// Emitted by @ref apply after a successful commit.
    void applied();
    /// Compatibility notification emitted when Apply changes the language mode.
    void languageChangeRequested(int mode);
    /// Atomic language + voice bridge used by the desktop Options page.
    void languageSettingsChangeRequested(int mode, int englishFunnyLevel,
                                         int cantoneseFunnyLevel);
    /// Emitted when @ref apply cannot proceed; @p tab is the offending @ref Tab.
    void validationFailed(int tab, const QString &message);

private:
    // Per-tab loaders (engine -> staging map).
    void loadBehavior();
    void loadDownloads();
    void loadConnection();
    void loadSpeed();
    void loadBitTorrent();
    void loadSearch();
    void loadRSS();
    void loadWebUI();

    // Per-tab appliers (staging map -> engine).
    void applyBehavior();
    void applyDownloads();
    void applyConnection();
    void applySpeed();
    void applyBitTorrent();
    void applySearch();
    void applyRSS();
    void applyWebUI();
    void applyPassthroughValues();

    // Cross-tab validation run before any writes (mirrors `applySettings()`).
    bool validate();

    // Staging helpers.
    QVariant staged(const QString &key, const QVariant &def = {}) const;
    void stage(const QString &key, const QVariant &value);
    void markModified();
    void markRestartRequired();
    void bumpRevision();
    int advancedRowForKey(const QString &key) const;

    QVariantMap m_values;   ///< the staging map (all tabs)
    QSet<QString> m_passthroughKeys; ///< exact config keys staged generically
    WatchedFoldersModel *m_watchedFoldersModel = nullptr;
    AdvancedSettingsModel *m_advancedSettingsModel = nullptr;
    bool m_modified = false;
    bool m_restartRequired = false;
    int m_revision = 0;

    static OptionsController *s_instance;
};
