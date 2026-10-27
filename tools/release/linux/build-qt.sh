#!/bin/sh
# build-qt.sh: Qt for the setup window, built inside the Steam Runtime sniper
# SDK container so that it runs wherever the game does (glibc 2.31 and the
# libstdc++ of GCC 10). The qt.io binaries of this Qt version cannot be used:
# they need glibc 2.34.
#
#   /qtsrc/qtbase.tar.xz   the pinned source archive (pins.env)
#   /qtout                 the prefix (a cache folder on the build machine)
#   /qtbuild               scratch
#
# qtbase only, and of it what a Widgets program needs: Core, Gui, Widgets,
# DBus, the xcb, Wayland and offscreen platform plugins. No OpenGL, no
# network, no SQL, no printing, no ICU; FreeType, fontconfig, zlib and the X11
# and Wayland libraries are the system's, the rest (HarfBuzz, libpng, PCRE2,
# double-conversion) is Qt's own bundled copy, so the window brings few
# libraries of its own. Qt's licence (LGPL-3.0) asks that its source be
# available: it is the archive this was built from, named in pins.env.
set -eu
JOBS="${JOBS:-8}"
rm -rf /qtbuild/src /qtbuild/build
mkdir -p /qtbuild/src /qtbuild/build
tar -xf /qtsrc/qtbase.tar.xz -C /qtbuild/src --strip-components 1
cmake -S /qtbuild/src -B /qtbuild/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=gcc-10 -DCMAKE_CXX_COMPILER=g++-10 \
    -DCMAKE_INSTALL_PREFIX=/qtout -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    -DINPUT_opengl=no -DFEATURE_sql=OFF -DFEATURE_network=OFF -DFEATURE_printsupport=OFF \
    -DFEATURE_concurrent=OFF -DFEATURE_xml=OFF -DFEATURE_testlib=OFF \
    -DFEATURE_icu=OFF -DFEATURE_glib=OFF -DFEATURE_zstd=OFF -DFEATURE_libudev=OFF \
    -DFEATURE_gtk3=OFF -DFEATURE_vulkan=OFF -DFEATURE_eglfs=OFF -DFEATURE_linuxfb=OFF -DFEATURE_vnc=OFF \
    -DFEATURE_xcb=ON -DFEATURE_wayland=ON -DFEATURE_dbus=ON \
    -DFEATURE_system_zlib=ON -DFEATURE_system_freetype=ON -DFEATURE_fontconfig=ON \
    -DFEATURE_system_harfbuzz=OFF -DFEATURE_system_png=OFF -DFEATURE_system_pcre2=OFF \
    -DFEATURE_system_doubleconversion=OFF -DFEATURE_system_jpeg=OFF \
    > /qtbuild/configure.log 2>&1 || { tail -40 /qtbuild/configure.log >&2; echo "Qt: configure failed" >&2; exit 1; }
for f in xcb wayland; do
    grep -q "^QT_FEATURE_$f:INTERNAL=ON" /qtbuild/build/CMakeCache.txt \
        || { grep -i -E "$f" /qtbuild/build/config.summary | head -20 >&2; echo "Qt: the $f platform plugin would not be built" >&2; exit 1; }
done
nice -n "${NICE:-10}" cmake --build /qtbuild/build -j"$JOBS" > /qtbuild/build.log 2>&1 \
    || { grep -B2 -A12 "error:" /qtbuild/build.log | head -60 >&2; tail -5 /qtbuild/build.log >&2; echo "Qt: build failed" >&2; exit 1; }
rm -rf /qtout/*
cmake --install /qtbuild/build > /qtbuild/install.log 2>&1
for p in platforms/libqxcb.so platforms/libqwayland.so platforms/libqoffscreen.so; do
    [ -f "/qtout/plugins/$p" ] || { echo "Qt: plugins/$p was not built" >&2; exit 1; }
done
rm -rf /qtbuild/src /qtbuild/build
echo "Qt built: $(ls /qtout/lib/libQt6*.so.6 | wc -l) libraries"
