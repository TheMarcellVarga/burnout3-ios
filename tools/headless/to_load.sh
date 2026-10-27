#!/usr/bin/env bash
# to_load.sh <rundir> [KEY=VALUE...]: to_race.sh's menu path up to the race
# loading screen, then stop once the race has begun (tracks\crash1.rws) and
# LOAD_TAIL flips (default 300) more have run. Whichever track the menu lands
# on is fine: this times the load, not the track.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
press a:400 90
press right:200 25
press down:200 20
press right:200 25
press a:400 90
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0
# CAPTURE=1: frames of the loading screen, LOAD_SHOTS flips after the press.
if [ "${CAPTURE:-0}" = 1 ]; then
    a=$(anchor 'PAD: live "' "$PADN")
    for o in ${LOAD_SHOTS:-40 120 200 260 300 330 360}; do shot "load_$o" "$a" "$o" 0; done
fi
wait_log 'LoadScrn[.]bin' "loading screen (LoadScrn.bin)"
wait_log 'streamed[.]dat' "track streamed in (streamed.dat)"
# LOAD_SAMPLE=1: a host stack sample of the load's last stretch.
if [ "${LOAD_SAMPLE:-0}" = 1 ]; then
    sleep 0.3
    sample "$(cat "$D/pid")" 1.5 -file "$D/sample.txt" > /dev/null 2>&1
    note "sampled ($D/sample.txt)"
fi
wait_log 'tracks.crash1[.]rws' "race begins (tracks crash1.rws)"
wait_flips "${LOAD_TAIL:-300}"
scene_stop
