#!/usr/bin/env bash
# zprobe_scene.sh <rundir> [KEY=VALUE...]   (BO-204: decals that lose depth tests)
#
# Single Event > Race (REGION_RIGHTS / TRACK_RIGHTS as hdr_scene.sh; with
# BO3_UNLOCK_ALL=1 every region), the title's AI driving (autopilot=1). At
# each of PAUSES (flips after the GO, default "700 1600 2600 3600 4600") the
# pause menu freezes the world, and the toolkit's zbias_probe pushes the
# depth-tested draws of one texture at a time 512 depth units back, then 4,
# four flips a texture (RECOMP_DEBUG=zbias_probe=@file; the registered offsets off,
# zbias=0, so the US LED words are the positive control). A texture drawn
# just in front of another surface (LED words, a poster, lettering on a sign)
# vanishes in its flip; anything else changes only along its seams. Every flip
# of a window is dumped; ZP_HOOK=<cmd> runs after each window as
# "<cmd> <rundir> <window flip>" (zprobe_report.py, which can delete the
# frames it has read).
set -u
source "$(dirname "$0")/scene_lib.sh"
rd="$(cd "$(dirname "$0")/../.." && mkdir -p "$1" && cd "$1" && pwd)"
: > "$rd/zp.txt"
dbg="autopilot=1,zbias=0,zbias_probe=@${GAME_PATH_PREFIX:-}$rd/zp.txt"
[ -n "${ZP_EXTRA:-}" ] && dbg="$dbg,$ZP_EXTRA"
CAPTURE=1 scene_start "$@" RECOMP_DEBUG="$dbg"
: > "$D/zp.txt"

to_main_menu
to_single_event
press a:400 90              # Race: Select Options (Region, Track, Rivals)
for (( k = 0; k < ${REGION_RIGHTS:-1}; k++ )); do
    press right:200 25      # Region: Random > USA (> Europe > Far East with BO3_UNLOCK_ALL=1)
done
press down:200 20
for (( k = 0; k < ${TRACK_RIGHTS:-1}; k++ )); do
    press right:200 25      # Track: Random > the first, and on
done
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading screen
wait_log "${TRACK_RE:-streamed[.]dat}" "track streamed in"
grep -aoE '[Tt]racks[\\/][^ ]*streamed[.]dat' "$D/events.txt" | tail -1 > "$D/track.txt"
note "track: $(cat "$D/track.txt")"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
n=0
for off in ${PAUSES:-700 1600 2600 3600 4600}; do
    n=$(( n + 1 ))
    wait_flip $(( a + 300 + off ))
    press start:300 90          # PAUSED: the world stands still, still drawn
    w=$(( $(flip) + 20 ))
    echo "$(( w - 3 ))-$(( w + ${ZP_FLIPS:-1200} ))" >> "$D/dumpat.txt"
    echo "$w" >> "$D/zp.txt"
    note "window $n from flip $w"
    t=$(date +%s)
    until [ "$(grep -ac 'zprobe done' "$D/log.txt")" -ge "$n" ] || [ "$(flip)" -ge $(( w + ${ZP_FLIPS:-1200} )) ]; do
        alive
        [ $(( $(date +%s) - t )) -gt 300 ] && die "window $n did not finish"
        sleep 1
    done
    wait_flips 6
    # The next windows' dumps: as many flips as this one took, and a margin.
    nt=$(grep -a 'zprobe done' "$D/log.txt" | tail -1 | sed -E 's/.*: ([0-9]+) textures.*/\1/')
    [ -n "$nt" ] && ZP_FLIPS=$(( nt * 4 + nt / 2 + 40 ))
    [ -n "${ZP_HOOK:-}" ] && $ZP_HOOK "$D" "$w"
    press start:300 60          # resume
done
wait_flips 60
[ -n "${ZP_HOOK:-}" ] && rm -f "$D"/fb_flip_*.bmp
scene_end "zprobe done"
