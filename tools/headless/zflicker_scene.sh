#!/usr/bin/env bash
# zflicker_scene.sh <rundir> [KEY=VALUE...]   (BO-204: decal flicker, counted)
#
# Single Event > Race (REGION_RIGHTS / TRACK_RIGHTS as zprobe_scene.sh), the
# title's AI driving, never paused. The decal textures in ZTINT (texrep_dump
# hashes, "+" between) are uploaded magenta (RECOMP_DEBUG=ztint) and the
# registered depth offsets alternate every flip (zbias_ab=1), so neighbouring
# flips are the same moment with and without them. Every flip of the ranges
# in SPANS ("<from>-<to> ...", flips after the GO) is dumped; then
# tools/headless/zflicker_report.py <rundir> counts the frames where the
# magenta pixels dip against the same arm's neighbours (counted as the run
# goes; frames with magenta kept as .seen). ZADD=<hash>+...: candidates given
# the -512 offset as if registered (RECOMP_DEBUG=zbias_add).
set -u
source "$(dirname "$0")/scene_lib.sh"
rd="$(cd "$(dirname "$0")/../.." && mkdir -p "$1" && cd "$1" && pwd)"
dbg="autopilot=1,zbias_ab=1,ztint=${ZTINT:?ZTINT=<hash>+<hash>}${ZADD:+,zbias_add=$ZADD}"
[ -n "${ZF_EXTRA:-}" ] && dbg="$dbg,$ZF_EXTRA"
CAPTURE=1 scene_start "$@" RECOMP_DEBUG="$dbg"

to_main_menu
to_single_event
press a:400 90
for (( k = 0; k < ${REGION_RIGHTS:-1}; k++ )); do press right:200 25; done
press down:200 20
for (( k = 0; k < ${TRACK_RIGHTS:-1}; k++ )); do press right:200 25; done
press a:400 90
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0
wait_log "${TRACK_RE:-streamed[.]dat}" "track streamed in"
grep -aoE '[Tt]racks[\\/][^ ]*streamed[.]dat' "$D/events.txt" | tail -1 > "$D/track.txt"
note "track: $(cat "$D/track.txt")"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
echo "$a" > "$D/anchor.txt"
last=0
for s in ${SPANS:?SPANS=\"<from>-<to> ...\"}; do
    f=${s%-*}; t=${s#*-}
    echo "$(( a + 300 + f ))-$(( a + 300 + t ))" >> "$D/dumpat.txt"
    [ "$t" -gt "$last" ] && last=$t
done
# Count as the dumps come (a whole drive's frames would not fit on a disk).
t0=$(date +%s)
while [ "$(flip)" -lt $(( a + 300 + last + 30 )) ]; do
    alive
    [ $(( $(date +%s) - t0 )) -gt "${SCENE_TIMEOUT:-900}" ] && die "drive did not end"
    ${ZF_PY:-python3} "$(dirname "$0")/zflicker_report.py" "$D" --consume
    sleep 3
done
sleep 3
${ZF_PY:-python3} "$(dirname "$0")/zflicker_report.py" "$D" --consume
scene_end "zflicker done"
