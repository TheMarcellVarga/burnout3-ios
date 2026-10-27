#!/usr/bin/env bash
# hdr_scene.sh <rundir> [KEY=VALUE...]   (BO-110, HDR prototype)
#
# Single Event > Race (TRACK as to_race.sh: Silver Lake Southbound unless
# TRACK_RE and the presses are changed), with RECOMP_DEBUG=hdr,hdr_ab=1:
# the targets switch between half float (scene light past 1.0 kept) and
# BGRA8 at every flip, so neighbouring flips are the same moment with HDR on
# and off. Float frames (hdr_dump, <rundir>/hdr/flip_NNNNN.rgbaf) and the
# usual BMPs (fb_dump_at) of:
#
#   grid     the rolling start, before any input of ours
#   drive    driving, then boosting (rt+a), several moments
#   paused   the pause menu over the frozen race (Start), HUD/menu check
#
# HDR=0 runs the same without the switch (the SDR build path); HDR_AB=0
# keeps HDR on. REGION_RIGHTS/TRACK_RIGHTS pick the track (with
# BO3_UNLOCK_ALL=1 every region); EXPLORE_SECS drives and dumps along the
# way (EXPLORE_RUN, EXPLORE_STEP: neighbouring flips for hdr_gains_ab). Then: tools/headless/hdr_report.py <out> <rundir>/hdr/*.rgbaf
set -u
source "$(dirname "$0")/scene_lib.sh"
rd="$(cd "$(dirname "$0")/../.." && mkdir -p "$1" && cd "$1" && pwd)"
mkdir -p "$rd/hdr"
rm -f "$rd"/hdr/*.rgbaf
dbg="hdr_dump=$rd/hdr/"
[ "${HDR:-1}" = 1 ] && dbg="hdr=1,hdr_ab=${HDR_AB:-1},$dbg"
[ -n "${HDR_EXTRA:-}" ] && dbg="$dbg,$HDR_EXTRA"
CAPTURE=1 scene_start "$@" RECOMP_DEBUG="$dbg"

dump() {   # dump <first> <count>: those flips, as fb_dump_at ranges
    echo "$1-$(( $1 + $2 - 1 ))" >> "$D/dumpat.txt"
    note "dump flips $1..$(( $1 + $2 - 1 )) ($3)"
}

to_main_menu
to_single_event
press a:400 90              # Race: Select Options (Region, Track, Rivals)
for (( k = 0; k < ${REGION_RIGHTS:-1}; k++ )); do
    press right:200 25      # Region: Random > USA (> Europe > Far East with BO3_UNLOCK_ALL=1)
done
press down:200 20
for (( k = 0; k < ${TRACK_RIGHTS:-1}; k++ )); do
    press right:200 25      # Track: Random > the first, and on (TRACK_RIGHTS)
done
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
dump "$(( $(flip) + 30 ))" 4 garage
press a:400 0               # the first car: loading screen
wait_log "${TRACK_RE:-streamed[.]dat}" "track streamed in"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
dump $(( a + 300 )) 4 grid
wait_flip $(( a + 290 ))
if [ -n "${EXPLORE_SECS:-}" ]; then
    # Exploration: hold the accelerator (boost now and then) and dump one
    # flip every 30 for EXPLORE_SECS seconds (look for the sun, lights);
    # EXPLORE_RUN=k: k neighbouring flips at each (hdr_gains_ab pairs, BO-195),
    # every EXPLORE_STEP flips (fb_dump_at takes up to 64 ranges).
    st=${EXPLORE_STEP:-30} n=${EXPLORE_RUN:-1}
    for (( f = a + 330; f <= a + 300 + EXPLORE_SECS * 60; f += st )); do
        echo "$f-$(( f + n - 1 ))" >> "$D/dumpat.txt"
    done
    for (( k = 0; k * 10 < EXPLORE_SECS; k++ )); do
        printf 'rt:7000\nrt+a:3000\n' >> "$D/pad.txt"
    done
    wait_flip $(( a + 300 + EXPLORE_SECS * 60 ))
    scene_end "explore done"
    exit 0
fi
# Accelerate 8 s, then boost 4 s, then accelerate; dumps along the way.
cat >> "$D/pad.txt" <<'EOF'
rt:8000
rt+a:4000
rt:6000
EOF
PADN=$(( PADN + 3 ))
dump $(( a + 300 + 360 )) 4 drive
dump $(( a + 300 + 540 )) 4 drive2
dump $(( a + 300 + 740 )) 4 boost
dump $(( a + 300 + 900 )) 4 boost2
wait_flip $(( a + 300 + 1100 ))
press start:300 120         # the pause menu over the frozen race
dump "$(( $(flip) + 60 ))" 6 paused
wait_flip $(( $(flip) + 80 ))
scene_end "hdr scene done"
