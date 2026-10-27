#!/usr/bin/env bash
# Boot the game headless for SECS seconds (default 45: the intro movies and
# the attract menu) and dump every Nth flip as BMP, for frame checks without
# a window.
#
#   tools/headless/boot_frames.sh <rundir> [KEY=VALUE env...]
#   BIN=runs/ab/burnout3_fix SECS=60 EVERY=10 tools/headless/boot_frames.sh runs/x
set -u
D="$1"; shift
mkdir -p "$D"
# The checkout's saves/ and shader cache, not the per-user ones.
env RECOMP_FB_DUMP="$D/f" RECOMP_FB_DUMP_FLIPS="${EVERY:-15}" RECOMP_TRACE=pacing \
    RECOMP_SAVE_DIR="${RECOMP_SAVE_DIR:-$PWD/saves}" \
    RECOMP_RENDER_SHADER_CACHE="${RECOMP_RENDER_SHADER_CACHE:-$PWD/build/shader-cache}" "$@" \
    "${BIN:-./bin/burnout3}" --headless > "$D/log.txt" 2>&1 &
pid=$!
echo $pid > "$D/pid"
sleep "${SECS:-45}"
kill $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null
ls "$D"/f*.bmp 2>/dev/null | wc -l | tr -d ' '
