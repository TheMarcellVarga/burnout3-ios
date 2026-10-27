#!/bin/sh
# build-sdl.sh: SDL for the Linux package, built inside the Steam Runtime
# sniper SDK container from the same pinned source archives as the Mac's
# (pins.env: SDL 3 and sdl2-compat).
#
#   /sdlsrc/SDL3.tar.gz, /sdlsrc/sdl2-compat.tar.gz
#   /sdlsrc/patches/sdl3-*.patch   applied to SDL 3
#   /sdlout                the prefix (a cache folder on the build machine)
#   /sdlbuild              scratch
#
# Why not the image's own SDL: that one is linked for use inside the Steam
# Runtime and names libasound, libpulse, libdecor-0, libXss, libXtst and
# others outright, so it does not load on a system that lacks any of them.
# Built here SDL opens its audio and video back ends at run time instead and
# needs nothing but the C library to load; the script fails if that is not so.
set -eu
JOBS="${JOBS:-8}"
rm -rf /sdlbuild/* /sdlout/*
mkdir -p /sdlbuild/SDL3 /sdlbuild/compat
tar -xf /sdlsrc/SDL3.tar.gz -C /sdlbuild/SDL3 --strip-components 1
tar -xf /sdlsrc/sdl2-compat.tar.gz -C /sdlbuild/compat --strip-components 1
# Our changes to SDL 3 (patches/sdl3-*.patch; each says why at its top).
for p in /sdlsrc/patches/sdl3-*.patch; do
    [ -f "$p" ] || continue
    patch -d /sdlbuild/SDL3 -p1 --no-backup-if-mismatch < "$p" > /dev/null \
        || { echo "SDL3: $(basename "$p") does not apply" >&2; exit 1; }
    echo "SDL3: applied $(basename "$p")"
done
common="-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc-10 -DCMAKE_CXX_COMPILER=g++-10 -DCMAKE_INSTALL_PREFIX=/sdlout -DCMAKE_INSTALL_LIBDIR=lib"
cmake -S /sdlbuild/SDL3 -B /sdlbuild/SDL3-build $common -DSDL_SHARED=ON -DSDL_STATIC=OFF \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_RPATH=OFF > /sdlbuild/SDL3.log 2>&1 \
    || { tail -30 /sdlbuild/SDL3.log >&2; echo "SDL3: configure failed" >&2; exit 1; }
nice -n "${NICE:-10}" cmake --build /sdlbuild/SDL3-build -j"$JOBS" >> /sdlbuild/SDL3.log 2>&1 \
    || { grep -B2 -A8 "error:" /sdlbuild/SDL3.log | head -40 >&2; echo "SDL3: build failed" >&2; exit 1; }
cmake --install /sdlbuild/SDL3-build >> /sdlbuild/SDL3.log 2>&1
cmake -S /sdlbuild/compat -B /sdlbuild/compat-build $common -DCMAKE_PREFIX_PATH=/sdlout \
    -DSDL2COMPAT_TESTS=OFF -DSDL2COMPAT_STATIC=OFF > /sdlbuild/compat.log 2>&1 \
    || { tail -30 /sdlbuild/compat.log >&2; echo "sdl2-compat: configure failed" >&2; exit 1; }
nice -n "${NICE:-10}" cmake --build /sdlbuild/compat-build -j"$JOBS" >> /sdlbuild/compat.log 2>&1 \
    || { grep -B2 -A8 "error:" /sdlbuild/compat.log | head -40 >&2; echo "sdl2-compat: build failed" >&2; exit 1; }
cmake --install /sdlbuild/compat-build >> /sdlbuild/compat.log 2>&1
for lib in libSDL3.so.0 libSDL2-2.0.so.0; do
    bad=$(objdump -p "/sdlout/lib/$lib" | sed -n 's/^ *NEEDED *//p' | grep -v -E '^(libc|libm|libdl|libpthread|librt)\.so' || true)
    [ -z "$bad" ] || { echo "$lib would not load without: $bad" >&2; exit 1; }
done
# What SDL can open at run time, for the record.
grep -E "^-- +SDL_(ALSA|PULSEAUDIO|PIPEWIRE|X11|WAYLAND|KMSDRM|VULKAN|HIDAPI|LIBUDEV|DBUS|IBUS)[A-Z_]* " /sdlbuild/SDL3.log | tr -s ' ' | sed 's/^-- //' | tr '\n' ';' ; echo
rm -rf /sdlbuild/SDL3 /sdlbuild/compat /sdlbuild/SDL3-build /sdlbuild/compat-build
echo "SDL built: $(ls /sdlout/lib/libSDL3.so.0.* /sdlout/lib/libSDL2-2.0.so.0.* | xargs -n1 basename | tr '\n' ' ')"
