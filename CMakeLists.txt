# qBittorrent (Material rewrite) — root CMake project
# Copyright (C) 2026  qBittorrent-Material contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Qt6 / C++20 build. Produces a static engine library (qbt_base) and the
# `qbittorrent` Qt Quick (Material) executable with a single QML module
# (URI qBittorrent). See docs/ARCHITECTURE.md and docs/CONTRACTS.md.

cmake_minimum_required(VERSION 3.21 FATAL_ERROR)

project(qbittorrent-material
    VERSION 5.3.0
    DESCRIPTION "qBittorrent — Material (Qt Quick) rewrite"
    HOMEPAGE_URL "https://www.qbittorrent.org/"
    LANGUAGES CXX
)

# A per-build identifier used only for package/release filenames. CI supplies a
# unique value; local packages retain the fork marker used by src/base/version.h.
set(QBT_BUILD_ID "material" CACHE STRING
    "Build identifier appended to installer filenames (for example build.42.a1b2c3d4)")

# --- Global language settings -------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        "Debug" "Release" "RelWithDebInfo" "MinSizeRel")
endif()

# Where our custom Find modules (FindLibtorrentRasterbar) live.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")

# --- Minimum dependency versions (mirrors upstream qBittorrent) ---------------
set(minQt6Version 6.6.0)
set(minBoostVersion 1.76)
set(minOpenSSLVersion 3.0.0)
set(minLibtorrentVersion 2.0.7)
set(minLibtorrent1Version 1.2.19)
set(minZlibVersion 1.2.11)

# --- Feature toggles ----------------------------------------------------------
option(QBT_DBUS "Enable D-Bus desktop notifications/power-management (Linux/BSD)" OFF)
option(QBT_STACKTRACE "Enable stacktrace support" OFF)
option(QBT_BUNDLE_QRC
    "Compile the hand-authored resources/resources.qrc verbatim instead of the \
tolerant globbed asset set (only enable once every listed asset exists)" OFF)

if ((CMAKE_SYSTEM_NAME STREQUAL "Linux") OR (CMAKE_SYSTEM_NAME STREQUAL "FreeBSD"))
    set(QBT_DBUS ON CACHE BOOL "" FORCE)
endif()

# --- Qt -----------------------------------------------------------------------
# Widgets is required because we host a QApplication (system tray + native OS
# file pickers), even though the entire UI surface is QML/Material.
find_package(Qt6 ${minQt6Version} REQUIRED
    COMPONENTS
        Core
        Gui
        Qml
        Quick
        QuickControls2
        Network
        Svg
        Sql
        Widgets
)

if (QBT_DBUS)
    find_package(Qt6 ${minQt6Version} QUIET COMPONENTS DBus)
    if (NOT Qt6DBus_FOUND)
        message(WARNING "Qt6::DBus not found — disabling QBT_DBUS.")
        set(QBT_DBUS OFF)
    endif()
endif()

qt_standard_project_setup(REQUIRES ${minQt6Version})

# Keep generated MOC/UIC/RCC artifacts out of the source tree.
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# --- Third-party engine dependencies ------------------------------------------
find_package(OpenSSL ${minOpenSSLVersion} REQUIRED)
find_package(Boost ${minBoostVersion} REQUIRED)
find_package(ZLIB ${minZlibVersion} REQUIRED)
find_package(LibtorrentRasterbar ${minLibtorrentVersion} REQUIRED)
find_package(libgit2 CONFIG REQUIRED)

message(STATUS "qbittorrent-material: Qt ${Qt6_VERSION}, "
    "libtorrent ${LibtorrentRasterbar_VERSION}, DBus=${QBT_DBUS}")

# --- Global compile definitions (mirrors upstream qBittorrent CommonConfig) ----
# QT_USE_QSTRINGBUILDER is REQUIRED: the engine (mirrored from upstream) relies on
# `u"..." + QString` concatenation which only compiles with QStringBuilder.
# The strict QT_NO_CAST_* defines are intentionally omitted so generated bridge
# code using implicit string conversions still builds.
add_compile_definitions(
    QT_USE_QSTRINGBUILDER
    QT_DISABLE_DEPRECATED_UP_TO=0x060500
)
if (WIN32)
    add_compile_definitions(
        NTDDI_VERSION=0x0A000006
        _WIN32_WINNT=0x0A00
        _WIN32_IE=0x0A00
        WIN32_LEAN_AND_MEAN
        NOMINMAX
        UNICODE
        _UNICODE
    )
endif()

add_subdirectory(src)

# --- Packaging ---------------------------------------------------------------
# Keep the numeric package version aligned with PROJECT_VERSION and the engine
# version header. QBT_BUILD_ID differentiates continuous installers without
# pretending each build is a new semantic version.
set(_qbt_package_build_id "${QBT_BUILD_ID}")
if (_qbt_package_build_id STREQUAL "")
    set(_qbt_package_build_id "material")
endif()
string(REGEX REPLACE "[^A-Za-z0-9._-]+" "-"
    _qbt_package_build_id "${_qbt_package_build_id}")

set(CPACK_PACKAGE_NAME "qBittorrent Material")
set(CPACK_PACKAGE_VENDOR "qBittorrent Material contributors")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "A Qt Quick Material desktop BitTorrent client")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/Ding-Ding-Projects/qbittorrent-material")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(CPACK_PACKAGE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(CPACK_PACKAGE_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "qBittorrent Material")
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_BINARY_DIR}/packages")
set(CPACK_PACKAGE_CHECKSUM "SHA256")
set(CPACK_MONOLITHIC_INSTALL ON)

if (WIN32)
    set(CPACK_GENERATOR "NSIS")
    set(CPACK_PACKAGE_FILE_NAME
        "qBittorrent-Material-${PROJECT_VERSION}-${_qbt_package_build_id}-windows-x64")
    set(CPACK_PACKAGE_EXECUTABLES "qbittorrent" "qBittorrent Material")
    set(CPACK_CREATE_DESKTOP_LINKS "qbittorrent")
    set(CPACK_NSIS_EXECUTABLES_DIRECTORY "bin")
    set(CPACK_NSIS_DISPLAY_NAME "qBittorrent Material ${PROJECT_VERSION}")
    set(CPACK_NSIS_PACKAGE_NAME "qBittorrent Material")
    set(CPACK_NSIS_INSTALLED_ICON_NAME "bin\\\\qbittorrent.exe")
    set(CPACK_NSIS_MUI_FINISHPAGE_RUN "bin\\\\qbittorrent.exe")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    set(CPACK_NSIS_MODIFY_PATH OFF)
    set(CPACK_NSIS_MANIFEST_DPI_AWARE ON)
    set(CPACK_NSIS_BRANDING_TEXT "qBittorrent Material")
    set(CPACK_NSIS_URL_INFO_ABOUT "${CPACK_PACKAGE_HOMEPAGE_URL}")
    set(CPACK_NSIS_CONTACT "qBittorrent Material contributors")
    # The repository currently has no distributable LICENSE file. Do not show
    # CPack's generic placeholder as if it were the application's license.
    set(CPACK_NSIS_IGNORE_LICENSE_PAGE ON)

    # Register the app as the handler for .torrent files and magnet: links so
    # double-clicking a .torrent or clicking a magnet link launches it with the
    # source as argv[1] (Application::run() adds it on cold start).
    #
    # The actual WriteRegStr/DeleteRegKey commands live in installer/*.nsh and
    # are pulled in with a single !include line. The !include argument must be
    # single-quoted: CPack pastes this variable verbatim between double quotes
    # in CPackConfig.cmake, so an embedded double quote splits the value into
    # several CMake arguments and the NSIS generator then emits `!include`
    # with no parameter at all ("!include expects 1-3 parameters, got 0").
    # The path must use backslashes (makensis does not resolve forward-slash
    # absolute paths), doubled here because cpack re-parses CPackConfig.cmake
    # and collapses each \\ back to \.
    file(TO_NATIVE_PATH "${CMAKE_SOURCE_DIR}/installer/file_associations_install.nsh" _qbt_nsis_install_nsh)
    file(TO_NATIVE_PATH "${CMAKE_SOURCE_DIR}/installer/file_associations_uninstall.nsh" _qbt_nsis_uninstall_nsh)
    string(REPLACE "\\" "\\\\" _qbt_nsis_install_nsh "${_qbt_nsis_install_nsh}")
    string(REPLACE "\\" "\\\\" _qbt_nsis_uninstall_nsh "${_qbt_nsis_uninstall_nsh}")
    set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "!include '${_qbt_nsis_install_nsh}'")
    set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS "!include '${_qbt_nsis_uninstall_nsh}'")
endif()

include(CPack)
