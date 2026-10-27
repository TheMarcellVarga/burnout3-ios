#!/bin/sh
# Runs INSIDE an Ubuntu 24.04 container (called by make-appimage-container.sh):
# installs Qt 6 and the build tools, builds the installer and packs the AppImage.
# /work holds gui/ (the sources), payload/ and licenses/ (already assembled) and
# receives out/. Ubuntu 24.04 is old enough for SteamOS and Bazzite (their glibc
# is newer) and has Qt 6.4, which the code builds with.
set -e
export DEBIAN_FRONTEND=noninteractive
if ! command -v qmake6 >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends build-essential cmake ninja-build qt6-base-dev \
        qt6-wayland libgl1-mesa-dev libxkbcommon-dev libxkbcommon-x11-0 libxcb-cursor0 wget file patchelf \
        desktop-file-utils ca-certificates xz-utils
fi
cd /work
tools=/work/tools
mkdir -p "$tools"
# Build-time helpers (not shipped, not used at run time).
for f in linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage; do
    if [ ! -x "$tools/$f" ]; then
        case "$f" in
            linuxdeploy-x86_64.AppImage) url=https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/$f ;;
            *) url=https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/$f ;;
        esac
        wget -q -O "$tools/$f" "$url"
        chmod +x "$tools/$f"
    fi
done
export APPIMAGE_EXTRACT_AND_RUN=1      # no FUSE in the container
export PATH="$tools:$PATH"
ln -sf "$tools/linuxdeploy-plugin-qt-x86_64.AppImage" "$tools/linuxdeploy-plugin-qt"

build=/work/build
cmake -S gui -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$build" -j"${JOBS:-4}"

appdir=/work/AppDir
rm -rf "$appdir"
mkdir -p "$appdir/usr/share/burnout3-installer"
cp -a payload "$appdir/usr/share/burnout3-installer/payload"
cp -a licenses "$appdir/usr/share/burnout3-installer/licenses"
sed -i "s/@QT_VERSION@/$(qmake6 -query QT_VERSION)/" "$appdir/usr/share/burnout3-installer/licenses/Qt-NOTICE.txt"
icon="$build/burnout3-installer.png"
QT_QPA_PLATFORM=offscreen "$build/burnout3-installer" --write-icon "$icon" --icon-size 256

export NO_STRIP=1
export QMAKE=$(command -v qmake6)
export EXTRA_QT_MODULES="waylandcompositor"
platforms="$($QMAKE -query QT_INSTALL_PLUGINS)/platforms"
wayland=libqwayland-generic.so
[ -f "$platforms/libqwayland.so" ] && wayland=libqwayland.so
export EXTRA_PLATFORM_PLUGINS="$wayland;libqoffscreen.so"
mkdir -p out
export OUTPUT=/work/out/Burnout3_Takedown_Installer-x86_64.AppImage
cd "$build"
linuxdeploy-x86_64.AppImage --appdir "$appdir" \
    --executable "$build/burnout3-installer" \
    --desktop-file /work/gui/packaging/burnout3-installer.desktop \
    --icon-file "$icon" \
    --plugin qt \
    --output appimage
ls -la /work/out
