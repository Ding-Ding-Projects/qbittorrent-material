#!/usr/bin/env bash
# qBittorrent Material — one-click build & run (Linux / macOS).
# Installs dependencies via the system package manager, configures, builds, runs.
#
#   ./run.sh            # install deps (if needed) + build + run
#   ./run.sh --no-run   # build only
#   ./run.sh --clean    # wipe build/ first
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BUILD="$REPO/build"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
RUN=1
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --no-run) RUN=0 ;;
        --clean)  CLEAN=1 ;;
    esac
done

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

clean_build() {
    [ "$BUILD" = "$REPO/build" ] || die "Refusing to clean unexpected build path: $BUILD"
    [ ! -e "$BUILD" ] || rm -rf -- "$BUILD"
}

cmake_cache_value() {
    [ -f "$BUILD/CMakeCache.txt" ] || return 0
    sed -n "s/^$1:[^=]*=//p" "$BUILD/CMakeCache.txt" | head -n1
}

if [ "$CLEAN" -eq 1 ]; then
    info "Cleaning build/"
    clean_build
elif [ -f "$BUILD/CMakeCache.txt" ]; then
    CACHED_SOURCE="$(cmake_cache_value CMAKE_HOME_DIRECTORY)"
    CACHED_BUILD="$(cmake_cache_value CMAKE_CACHEFILE_DIR)"
    if { [ -n "$CACHED_SOURCE" ] && [ "${CACHED_SOURCE%/}" != "${REPO%/}" ]; } ||
       { [ -n "$CACHED_BUILD" ] && [ "${CACHED_BUILD%/}" != "${BUILD%/}" ]; }; then
        warn "The build cache belongs to another checkout ($CACHED_SOURCE); regenerating build/."
        clean_build
    fi
fi

install_deps() {
    if have apt-get; then
        info "Installing dependencies via apt..."
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends \
            build-essential cmake ninja-build pkg-config \
            qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
            libqt6svg6-dev qml6-module-qtquick-controls qml6-module-qtquick-layouts \
            qml6-module-qtquick-window qml6-module-qtqml-workerscript \
            libtorrent-rasterbar-dev libgit2-dev libboost-all-dev libssl-dev zlib1g-dev
    elif have dnf; then
        info "Installing dependencies via dnf..."
        sudo dnf install -y gcc-c++ cmake ninja-build \
            qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
            rb_libtorrent-devel libgit2-devel boost-devel openssl-devel zlib-devel
    elif have pacman; then
        info "Installing dependencies via pacman..."
        sudo pacman -S --needed --noconfirm \
            base-devel cmake ninja qt6-base qt6-declarative qt6-svg \
            libtorrent-rasterbar libgit2 boost openssl zlib
    elif have brew; then
        info "Installing dependencies via Homebrew..."
        brew install cmake ninja qt libtorrent-rasterbar libgit2 boost openssl@3 zlib
        export CMAKE_PREFIX_PATH="$(brew --prefix qt):$(brew --prefix openssl@3):${CMAKE_PREFIX_PATH:-}"
    else
        die "No supported package manager found (apt/dnf/pacman/brew). Install Qt6, libtorrent-rasterbar, libgit2, Boost, OpenSSL, zlib, CMake and Ninja manually, then re-run."
    fi
}

# Only install if a key dependency is missing.
if ! have cmake || ! have ninja || ! (pkg-config --exists Qt6Core 2>/dev/null || [ -n "${CMAKE_PREFIX_PATH:-}" ] || [ -d /usr/lib/qt6 ] || [ -d /usr/lib64/qt6 ]); then
    install_deps
fi

info "Configuring (CMake + Ninja)..."
cmake -B "$BUILD" -S "$REPO" -G Ninja -DCMAKE_BUILD_TYPE=Release ${CMAKE_PREFIX_PATH:+-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"}

info "Building (-j $JOBS)..."
cmake --build "$BUILD" --parallel "$JOBS"

EXE="$(find "$BUILD" -name qbittorrent -type f -perm -u+x 2>/dev/null | head -n1)"
[ -z "$EXE" ] && EXE="$(find "$BUILD" -name 'qbittorrent*' -type f 2>/dev/null | head -n1)"
[ -z "$EXE" ] && die "Build succeeded but the qbittorrent binary was not found."
info "Build OK: $EXE"

if [ "$RUN" -eq 1 ]; then
    info "Launching qBittorrent Material..."
    exec "$EXE"
else
    info "Done (build only). Run it with: $EXE"
fi
