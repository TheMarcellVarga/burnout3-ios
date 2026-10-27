#!/usr/bin/env bash
# scenery_crash.sh <rundir> [KEY=VALUE...]
#
# graphics.scenery_detail (BO-177) at Silver Lake (C3_V1), the one place the
# reference saves reach it: Single Event > Crash, junction 1 (Trailer Trash,
# as to_crash.sh). The pine woods are around the junction. The setting goes
# original > far > original (BO3_FX_AT "sdetail", as scenery_scene.sh):
#
#   - under the captions, which wait for A (the camera and the world stand);
#   - on the run-up after the GO (in motion: the counts);
#   - in the crash camera after the impact.
#
# tools/headless/scenery_report.py <rundir> --crops <dir> reads it.
#
#   HOME=/tmp/x STOP_AT_END=1 tools/headless/scenery_crash.sh runs/sc1
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; shift
export CAPTURE=1
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
scene_start "$rd" BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt" \
    RECOMP_TRACE="${RECOMP_TRACE:-metal_frame}" "$@"
: > "$D/fx.txt"; : > "$D/ab.tsv"

ab() {
    local f=$1 now; now=$(flip)
    [ "$f" -le $(( now + 3 )) ] && die "ab at $f asked for at flip $now"
    echo "$f sdetail 1" >> "$D/fx.txt"
    echo "$(( f + 6 )) sdetail 0" >> "$D/fx.txt"
    echo "$(( f - 1 ))-$(( f + 11 ))" >> "$D/dumpat.txt"
    printf '%s\t%s\n' "$f" "$2" >> "$D/ab.tsv"
}

to_main_menu
to_single_event
press down:200 20; press down:200 20; press down:200 20     # Crash
press a:400 90              # Junction Selection
press down:200 20           # 1. Trailer Trash
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: Crash Training video, loading
wait_log 'TrC_ENG[.]xmv' "Crash Training video (TrC_ENG.xmv)"
wait_log 'C3_V1.streamed[.]dat' "junction streamed in (C3_V1 streamed.dat)"
wait_log "$(track_re crash2)" "captions (crash2.rws)"
b=$(anchor "$(track_re crash2)")
for off in 100 160 220; do ab $(( b + off )) caption; done
wait_flip $(( b + 300 ))
press a:400 60              # the countdown, 3-2-1
press rt:600000 0           # held from the countdown
g=$(flip)
for off in 240 300 360 420; do ab $(( g + off )) runup; done
wait_log 'C3_v1.crash1[.]rws' "impact (C3_v1 crash1.rws)"
c=$(anchor 'C3_v1.crash1[.]rws')
for off in 120 240 360 480; do ab $(( c + off )) crashcam; done
wait_flip $(( c + 500 ))
mkdir -p "$D/frames"
mv "$D"/fb_flip_*.bmp "$D/frames/" 2>/dev/null
scene_end "scenery crash scene"
