#!/bin/sh
# Builds the installer and packs it into an AppImage with its Qt libraries and
# the payload it installs from (see make-macos-app.sh: a snapshot of this source
# tree and, with XBOXRECOMP_DIR, of the toolkit; no game data). Steps after
# Xerenge's make-appimage.sh: linuxdeploy with its Qt plugin.
#
#   [XBOXRECOMP_DIR=<toolkit checkout>] tools/install/gui/packaging/make-appimage.sh
#       ->   tools/install/gui/Burnout3_Takedown_Installer-x86_64.AppImage
#
# Needs linuxdeploy and linuxdeploy-plugin-qt on PATH (or in a Distrobox / the
# Steam Runtime SDK container) and the Qt 6 development files. The AppImage does
# not carry Python: the installer runs the driver with the system's python3
# (SteamOS and Bazzite have one; the installer says so when it is missing).
# The Steam Deck builds the game in the podman SDK container, see
# docs/installer.md.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gui=$(cd "$here/.." && pwd)
repo=$(git -C "$gui" rev-parse --show-toplevel)
build="$gui/build-appimage"
appdir="$build/AppDir"

cmake -S "$gui" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$build" -j"$(nproc)"

rm -rf "$appdir"
# Where the installer looks for it (LocateDriver): ../share/burnout3-installer/payload
# from usr/bin. linuxdeploy leaves usr/share alone.
. "$here/payload.sh"
assemble_payload "$appdir/usr/share/burnout3-installer/payload" "$appdir/usr/share/burnout3-installer/licenses"

# The icon comes from the installer itself.
icon="$build/burnout3-installer.png"
QT_QPA_PLATFORM=offscreen "$build/burnout3-installer" --write-icon "$icon" --icon-size 256

# linuxdeploy's own strip is too old for .relr.dyn sections in current libraries.
export NO_STRIP=1
export QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake)}
# Wayland as well as X11 (the Deck's Desktop Mode is either), and offscreen for
# the test mode. The Wayland platform plugin is libqwayland.so in current Qt,
# libqwayland-generic.so in older releases (Ubuntu 24.04's 6.4).
export EXTRA_QT_MODULES="waylandcompositor"
platforms="$("$QMAKE" -query QT_INSTALL_PLUGINS)/platforms"
wayland=libqwayland.so
[ -f "$platforms/$wayland" ] || wayland=libqwayland-generic.so
export EXTRA_PLATFORM_PLUGINS="$wayland;libqoffscreen.so"
export OUTPUT="$gui/Burnout3_Takedown_Installer-x86_64.AppImage"
cd "$build"
linuxdeploy --appdir "$appdir" \
    --executable "$build/burnout3-installer" \
    --desktop-file "$here/burnout3-installer.desktop" \
    --icon-file "$icon" \
    --plugin qt \
    --output appimage
echo "built: $OUTPUT"
