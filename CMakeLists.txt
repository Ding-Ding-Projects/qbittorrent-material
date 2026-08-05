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

# A per-build identifier compiled into release identity checks. CI supplies a
# unique value; local builds retain the fork marker used by src/base/version.h.
set(QBT_BUILD_ID "material" CACHE STRING
    "Release build identifier (for example build.42.a1b2c3d4)")

# Squirrel.Windows accepts a three-component SemVer package version. CI replaces
# the patch component with GITHUB_RUN_NUMBER so every update feed entry is newer
# than the preceding run while the human-facing project version stays 5.3.0.
set(QBT_PACKAGE_VERSION
    "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}"
    CACHE STRING "Three-component Squirrel.Windows package version")
if (NOT QBT_PACKAGE_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR
        "QBT_PACKAGE_VERSION must contain exactly three numeric components (received '${QBT_PACKAGE_VERSION}').")
endif()

# Windows VERSIONINFO requires a four-part numeric tuple while Squirrel uses a
# three-part package identity. Generate the resource from the same source of
# truth so Explorer metadata, Qt.application.version, and the update feed never
# disagree about a shipped build.
string(REPLACE "." "," QBT_PACKAGE_VERSION_RC_COMPONENTS "${QBT_PACKAGE_VERSION}")
set(QBT_PACKAGE_VERSION_RC_NUMERIC "${QBT_PACKAGE_VERSION_RC_COMPONENTS},0")
set(QBT_PACKAGE_VERSION_RC_STRING "${QBT_PACKAGE_VERSION}.0")
set(QBT_BRANDING_ICON_RC_PATH "${CMAKE_SOURCE_DIR}/resources/branding/qbittorrent-material.ico")
file(TO_CMAKE_PATH "${QBT_BRANDING_ICON_RC_PATH}" QBT_BRANDING_ICON_RC_PATH)
set(QBT_WINDOWS_VERSION_RESOURCE "${CMAKE_BINARY_DIR}/generated/qbittorrent-material.rc")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/generated")
configure_file(
    "${CMAKE_SOURCE_DIR}/resources/branding/qbittorrent-material.rc.in"
    "${QBT_WINDOWS_VERSION_RESOURCE}"
    @ONLY
)

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
option(QBT_BUILD_NOTIFICATION_TESTS
    "Build the opt-in non-GUI notification controller regression" OFF)

if (QBT_BUILD_NOTIFICATION_TESTS)
    enable_testing()
endif()

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
