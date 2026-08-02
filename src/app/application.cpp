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

#include "application.h"

#include <algorithm>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QTimer>
#include <QTranslator>
#include <QVariantMap>

#include "base/logging.h"
#include "base/logger.h"
#include "base/path.h"
#include "base/profile.h"
#include "base/settingsstorage.h"
#include "app/appcontroller.h"
#include "app/desktopintegration.h"
#include "quick/theme/iconprovider.h"

// --- Optional cross-team engine headers (tolerant coupling) ------------------
// Application depends on engine/i18n headers produced by other feature teams.
// Guarding with __has_include keeps the bootstrap compiling while those files
// are still landing, and lights up the real wiring the moment they exist.
#if __has_include("base/preferences.h")
#include "base/preferences.h"
#define QBT_HAS_PREFERENCES 1
#endif

#if __has_include("base/bittorrent/session.h")
#include "base/bittorrent/session.h"
#define QBT_HAS_SESSION 1
#endif

#if __has_include("base/rss/rss_session.h")
#include "base/rss/rss_session.h"
#define QBT_HAS_RSS 1
#endif

#if __has_include("base/torrentjournal/torrentjournal.h")
#include "base/torrentjournal/torrentjournal.h"
#include "base/torrentjournal/torrentundomanager.h"
#define QBT_HAS_TORRENT_JOURNAL 1
#endif

#if __has_include("base/net/proxyconfigurationmanager.h")
#include "base/net/proxyconfigurationmanager.h"
#define QBT_HAS_PROXY_MANAGER 1
#endif

#if __has_include("base/net/downloadmanager.h")
#include "base/net/downloadmanager.h"
#define QBT_HAS_DOWNLOAD_MANAGER 1
#endif

#if __has_include("base/net/geoipmanager.h")
#include "base/net/geoipmanager.h"
#define QBT_HAS_GEOIP 1
#endif

#if __has_include("base/torrentfileswatcher.h")
#include "base/torrentfileswatcher.h"
#define QBT_HAS_TORRENT_FILES_WATCHER 1
#endif

#if __has_include("base/utils/i18n/funnytranslator.h")
#include "base/utils/i18n/funnytranslator.h"
#define QBT_HAS_FUNNY_TRANSLATOR 1
#elif __has_include("quick/i18n/funnytranslator.h")
#include "quick/i18n/funnytranslator.h"
#define QBT_HAS_FUNNY_TRANSLATOR 1
#endif

using namespace Qt::StringLiterals;

namespace
{
    const QString kEnglishFunnyLevelKey = u"Appearance/EnglishFunnyLevel"_qs;
    const QString kCantoneseFunnyLevelKey = u"Appearance/CantoneseFunnyLevel"_qs;

    /// A stable, per-user single-instance identifier (so two different logins
    /// on the same host don't collide).
    QString computeInstanceId()
    {
        QString seed = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
            + u'|' + qEnvironmentVariable("USER", qEnvironmentVariable("USERNAME"));
        // Isolated profiles are independent instances. This keeps deterministic
        // documentation capture and test profiles from activating a user's
        // normal qBittorrent Material session.
        for (const QString &arg : QCoreApplication::arguments())
        {
            if (arg.startsWith(u"--profile-root="_s))
                seed += u'|' + arg;
        }
        const QByteArray digest =
            QCryptographicHash::hash(seed.toUtf8(), QCryptographicHash::Sha1).toHex().left(16);
        return u"qbittorrent-material-"_qs + QString::fromLatin1(digest);
    }

    QString bundledLicenseNotice()
    {
        QFile licenseFile(u":/html/gpl.html"_qs);
        if (!licenseFile.open(QIODevice::ReadOnly | QIODevice::Text))
        {
            qCWarning(lcApp) << "Unable to read bundled GPL notice:" << licenseFile.errorString();
            return {};
        }

        return QString::fromUtf8(licenseFile.readAll());
    }
}

Application::Application(int &argc, char **argv)
    : QApplication(argc, argv)
    , m_launchTimeSecsSinceEpoch(QDateTime::currentSecsSinceEpoch())
{
    setApplicationName(u"qBittorrent"_qs);
    setOrganizationName(u"qBittorrent"_qs);
    setOrganizationDomain(u"qbittorrent.org"_qs);
    setApplicationVersion(QCoreApplication::applicationVersion().isEmpty()
            ? u"5.3.0-material"_qs : QCoreApplication::applicationVersion());
    setApplicationDisplayName(u"qBittorrent"_qs);
    const QIcon brandIcon(u":/branding/logo-mark.png"_qs);
    if (!brandIcon.isNull())
        setWindowIcon(brandIcon);
    else
        qCWarning(lcApp) << "Brand icon resource is unavailable";
    setQuitOnLastWindowClosed(false);  // closing the window may just hide to tray

    qCInfo(lcApp) << "Application constructed:" << applicationName()
                  << applicationVersion() << "pid" << applicationPid();

    setupSingleInstance();
}

Application::~Application()
{
    qCDebug(lcApp) << "Application destructor";
    cleanup();

    if (m_instanceServer)
    {
        m_instanceServer->close();
        delete m_instanceServer;
        m_instanceServer = nullptr;
    }
}

Application *Application::instance()
{
    return qobject_cast<Application *>(QCoreApplication::instance());
}

// ---------------------------------------------------------------------------
// Single-instance guard
// ---------------------------------------------------------------------------
void Application::setupSingleInstance()
{
    m_instanceId = computeInstanceId();
    qCDebug(lcApp) << "Single-instance id:" << m_instanceId;

    // Probe for an existing primary by trying to connect to its local server.
    QLocalSocket probe;
    probe.connectToServer(m_instanceId);
    if (probe.waitForConnected(300))
    {
        qCInfo(lcApp) << "Detected an existing primary instance";
        probe.disconnectFromServer();
        m_isPrimaryInstance = false;
        return;
    }

    // Become the primary: (re)create the local server.
    m_instanceServer = new QLocalServer(this);
    QLocalServer::removeServer(m_instanceId);  // clear a stale socket from a crash
    if (!m_instanceServer->listen(m_instanceId))
    {
        qCWarning(lcApp) << "Failed to listen on single-instance socket:"
                         << m_instanceServer->errorString()
                         << "— continuing as primary anyway";
    }

    connect(m_instanceServer, &QLocalServer::newConnection, this, [this]
    {
        qCInfo(lcApp) << "Received activation request from a secondary instance";
        while (QLocalSocket *conn = m_instanceServer->nextPendingConnection())
        {
            conn->waitForReadyRead(200);
            const QByteArray payload = conn->readAll();
            conn->deleteLater();
            if (m_appController)
                m_appController->handleActivationRequest(QString::fromUtf8(payload));
        }
    });

    m_isPrimaryInstance = true;
    qCInfo(lcApp) << "This process is the primary instance";
}

bool Application::isPrimaryInstance() const
{
    return m_isPrimaryInstance;
}

void Application::notifyPrimaryInstance()
{
    qCDebug(lcApp) << "Notifying primary instance of our launch";
    QLocalSocket socket;
    socket.connectToServer(m_instanceId);
    if (socket.waitForConnected(500))
    {
        const QStringList args = QCoreApplication::arguments();
        const QByteArray payload = (args.size() > 1) ? args.at(1).toUtf8() : QByteArray("activate");
        socket.write(payload);
        socket.flush();
        socket.waitForBytesWritten(500);
        socket.disconnectFromServer();
        qCInfo(lcApp) << "Handoff to primary complete";
    }
    else
    {
        qCWarning(lcApp) << "Could not reach primary instance:" << socket.errorString();
    }
}

// ---------------------------------------------------------------------------
// Boot sequence
// ---------------------------------------------------------------------------
int Application::run()
{
    qCInfo(lcApp) << "Application::run() — beginning boot sequence";

    // Engine singletons must be constructed before anything (translation,
    // controllers, QML) touches Preferences/Session.
    initEngine();
    setupTranslation();

    // App-owned QML singleton instances must exist before Main.qml loads,
    // because their create() factories hand back these very objects.
    m_appController = new AppController(this);
    m_desktopIntegration = new DesktopIntegration(this);
    qCDebug(lcApp) << "Created AppController and DesktopIntegration";

    m_engine = new QQmlApplicationEngine(this);
    // Let the engine find QML modules deployed next to the executable (e.g.
    // Qt.labs.platform, copied there by windeployqt) so file-picker dialogs work.
    m_engine->addImportPath(applicationDirPath() + u"/qml"_qs);
    // The peer list resolves country flags through image://flags/<iso>. The
    // engine owns the provider after registration; it returns a transparent
    // placeholder when an optional flag asset is not bundled.
    m_engine->addImageProvider(u"flags"_qs, new FlagImageProvider);
    registerContext();
    loadMainQml();

    // Documentation captures are intentionally self-terminating. QML performs
    // the page/theme/dialog setup and normally captures after the scene has
    // settled; this C++ timer is a fail-safe so a QML handler error can never
    // leave a headless capture process running indefinitely.
    QString captureOutput;
    for (const QString &arg : QCoreApplication::arguments())
    {
        if (arg.startsWith(u"--capture-ui="_s))
        {
            captureOutput = arg.sliced(13);
            break;
        }
    }
    if (!captureOutput.isEmpty())
    {
        QTimer::singleShot(4000, this, [this, captureOutput]
        {
            const bool saved = m_appController && m_appController->captureMainWindow(captureOutput);
            qCInfo(lcApp) << "Documentation capture fail-safe finished; saved =" << saved;
            QCoreApplication::exit(saved ? 0 : 2);
        });
    }

    connect(this, &QCoreApplication::aboutToQuit, this, &Application::cleanup);

    // Cold-start torrent/magnet argument: when the OS launches us for a
    // double-clicked .torrent or a magnet: link (file associations registered
    // by the installer), the source arrives as argv[1] on THIS (primary)
    // process — the single-instance handoff only covers later launches. Add it
    // once the session has settled. Skipped in capture mode.
    if (captureOutput.isEmpty())
    {
        const QStringList args = QCoreApplication::arguments();
        for (qsizetype i = 1; i < args.size(); ++i)
        {
            const QString &arg = args.at(i);
            if (arg.startsWith(u"--"_s))
                continue;
            QTimer::singleShot(0, this, [this, arg]
            {
                if (m_appController)
                    m_appController->handleActivationRequest(arg);
            });
            break;
        }
    }

    qCInfo(lcApp) << "Entering Qt event loop";
    const int rc = QApplication::exec();
    qCInfo(lcApp) << "Qt event loop exited with code" << rc;
    return rc;
}

void Application::setupTranslation()
{
    int langValue = 0;  // 0 == English (default)
    int englishFunnyLevel = 1;
    int cantoneseFunnyLevel = 3;
#ifdef QBT_HAS_PREFERENCES
    langValue = Preferences::instance()->getLanguageMode();
    englishFunnyLevel = Preferences::instance()->value(kEnglishFunnyLevelKey, 1).toInt();
    cantoneseFunnyLevel = Preferences::instance()->value(kCantoneseFunnyLevelKey, 3).toInt();
    qCInfo(lcI18n) << "Loaded persisted language settings:"
                   << langValue << englishFunnyLevel << cantoneseFunnyLevel;
#else
    qCWarning(lcI18n) << "Preferences unavailable at startup; using language defaults";
#endif

#ifdef QBT_HAS_FUNNY_TRANSLATOR
    using Utils::I18n::FunnyTranslator;
    auto *funny = new FunnyTranslator(this);
    if (funny->entryCount() == 0)
        qCWarning(lcI18n) << "Cantonese catalog missing — Cantonese/Bilingual will fall back to English";
    langValue = std::clamp(langValue, int(FunnyTranslator::Mode::English),
                           int(FunnyTranslator::Mode::Bilingual));
    funny->setMode(static_cast<FunnyTranslator::Mode>(langValue));
    funny->setFunnyLevels(englishFunnyLevel, cantoneseFunnyLevel);
    m_translator = funny;
    if (installTranslator(m_translator))
        qCInfo(lcI18n) << "Sole FunnyTranslator installed before QML load";
    else
    {
        qCWarning(lcI18n) << "FunnyTranslator installation failed; UI will use English";
        delete m_translator;
        m_translator = nullptr;
    }
#else
    Q_UNUSED(langValue)
    Q_UNUSED(englishFunnyLevel)
    Q_UNUSED(cantoneseFunnyLevel)
    qCWarning(lcI18n) << "FunnyTranslator not available yet; UI will render raw English literals";
#endif
}

void Application::initEngine()
{
    qCInfo(lcEngine) << "Initializing engine singletons";

    // Order matters: Logger and Profile first, then the settings store, then
    // Preferences (reads the store), then the BitTorrent session (reads prefs).
    Logger::initInstance();
    Path profileRoot;
    QString configurationName;
    for (const QString &arg : QCoreApplication::arguments())
    {
        if (arg.startsWith(u"--profile-root="_s))
            profileRoot = Path(arg.sliced(15));
        else if (arg.startsWith(u"--configuration="_s))
            configurationName = arg.sliced(16);
    }
    Profile::initInstance(profileRoot, configurationName, false);
    SettingsStorage::initInstance();
    qCDebug(lcEngine) << "Profile + SettingsStorage ready";

#ifdef QBT_HAS_PREFERENCES
    Preferences::initInstance();
    qCDebug(lcEngine) << "Preferences instance ready";
#else
    qCWarning(lcEngine) << "Preferences header not present at build time";
#endif

#ifdef QBT_HAS_PROXY_MANAGER
    // Network proxy manager: an app-owned singleton read by several controllers
    // (e.g. the Options "Connection" tab). It only reads settings, so it is safe
    // to bring up here, after the settings store is ready.
    Net::ProxyConfigurationManager::initInstance();
    qCDebug(lcEngine) << "Net::ProxyConfigurationManager ready";
#endif

#ifdef QBT_HAS_DOWNLOAD_MANAGER
    // The network download manager (also the cookie store used by CookiesModel /
    // URL & RSS downloads). Its constructor wires up the proxy manager, so it
    // must be created after ProxyConfigurationManager above.
    Net::DownloadManager::initInstance();
    qCDebug(lcEngine) << "Net::DownloadManager ready";
#endif

#ifdef QBT_HAS_GEOIP
    // Peer-country resolution (PeerInfo::country()). Depends on DownloadManager
    // above for its database-update fetches; must exist before any torrent's
    // peer list is queried, or PeerInfo::country() dereferences a null instance.
    Net::GeoIPManager::initInstance();
    qCDebug(lcEngine) << "Net::GeoIPManager ready";
#endif

#ifdef QBT_HAS_SESSION
    // Brings up the concrete libtorrent session on its own IO thread.
    BitTorrent::Session::initInstance();
    qCInfo(lcEngine) << "BitTorrent::Session initialized";
#else
    qCWarning(lcEngine) << "BitTorrent::Session header not present at build time";
#endif

#if defined(QBT_HAS_TORRENT_JOURNAL) && defined(QBT_HAS_SESSION)
    // The git-backed journal observes Session signals, so it must come up
    // right after the session and BEFORE the RSS session below so RSS
    // auto-downloads are captured from the first one.
    TorrentJournal::initInstance();
    TorrentUndoManager::initInstance();
    qCInfo(lcEngine) << "TorrentJournal + TorrentUndoManager initialized";
#endif

#ifdef QBT_HAS_TORRENT_FILES_WATCHER
    // Options owns the watched-folders model, so the backing engine singleton
    // must exist before the QML module instantiates OptionsController.
    TorrentFilesWatcher::initInstance();
    qCDebug(lcEngine) << "TorrentFilesWatcher ready";
#endif

#ifdef QBT_HAS_RSS
    // The RSS session is an app-owned singleton (private ctor; Application is a
    // friend). It must exist before any RSS bridge object (e.g. RSSController)
    // is touched by QML, otherwise RSS::Session::instance() is null and the
    // controller dereferences it. Depends on Profile/SettingsStorage/Preferences
    // (already up) so it is created here, after the BitTorrent session.
    if (!RSS::Session::instance())
        new RSS::Session;
    qCInfo(lcEngine) << "RSS::Session initialized";
#endif
}

void Application::registerContext()
{
    Q_ASSERT(m_engine);

    // A tiny read-only context object with build info (About dialog, logs).
    QVariantMap appInfo;
    appInfo.insert(u"name"_qs, applicationName());
    appInfo.insert(u"displayName"_qs, applicationDisplayName());
    appInfo.insert(u"version"_qs, applicationVersion());
    appInfo.insert(u"qtVersion"_qs, QString::fromLatin1(qVersion()));
    appInfo.insert(u"launchTime"_qs, m_launchTimeSecsSinceEpoch);
    // Load the About-dialog notice through QFile rather than QML XHR. This is
    // synchronous, works for every QRC deployment mode, and leaves a visible
    // fallback in QML when a packaging regression omits the resource.
    appInfo.insert(u"licenseText"_qs, bundledLicenseNotice());
    m_engine->rootContext()->setContextProperty(u"ApplicationInfo"_qs, appInfo);

    qCDebug(lcApp) << "Registered ApplicationInfo context property";
}

void Application::loadMainQml()
{
    Q_ASSERT(m_engine);

    connect(m_engine, &QQmlApplicationEngine::objectCreationFailed, this, []
    {
        qCCritical(lcApp) << "Failed to create Main.qml root object — aborting";
        QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);

    connect(m_engine, &QQmlApplicationEngine::objectCreated, this,
        [](QObject *obj, const QUrl &url)
        {
            if (obj)
                qCInfo(lcApp) << "Main QML object created:" << url.toString();
        });

    qCInfo(lcApp) << "Loading qBittorrent QML module entry point (Main)";
    m_engine->loadFromModule(u"qBittorrent"_qs, u"Main"_qs);

    if (m_engine->rootObjects().isEmpty())
        qCCritical(lcApp) << "No root QML objects were created";
}

void Application::cleanup()
{
    if (m_cleanupDone)
        return;
    m_cleanupDone = true;

    qCInfo(lcApp) << "Application cleanup started";
    emit aboutToShutDown();

#if defined(QBT_HAS_TORRENT_JOURNAL) && defined(QBT_HAS_SESSION)
    // Flush the journal while the session's torrents are still alive.
    if (TorrentJournal *journal = TorrentJournal::instance())
        journal->shutdownFlush();
#endif

    // Drop the QML engine first -- synchronously, so no QML binding or
    // delegate can outlive the engine singletons torn down below.
    if (m_engine)
    {
        delete m_engine;
        m_engine = nullptr;
        qCDebug(lcApp) << "QML engine destroyed";
    }

    if (m_translator)
    {
        removeTranslator(m_translator);
        delete m_translator;
        m_translator = nullptr;
        qCDebug(lcI18n) << "Runtime translator removed";
    }

#ifdef QBT_HAS_SESSION
    // Tear the session down for real: ~SessionImpl requests a final resume-data
    // save for every torrent and drains the alerts (bounded by the shutdown
    // timeout) so the persisted torrent list reflects the state at exit.
    BitTorrent::Session::freeInstance();
    qCDebug(lcApp) << "BitTorrent session torn down";
#endif

    qCInfo(lcApp) << "Application cleanup finished";
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------
AppController *Application::appController() const
{
    return m_appController.data();
}

DesktopIntegration *Application::desktopIntegration() const
{
    return m_desktopIntegration.data();
}

QQmlApplicationEngine *Application::qmlEngine() const
{
    return m_engine;
}

QTranslator *Application::runtimeTranslator() const
{
    return m_translator;
}

qint64 Application::launchTimeSecsSinceEpoch() const
{
    return m_launchTimeSecsSinceEpoch;
}
