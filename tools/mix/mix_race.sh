#!/usr/bin/env bash
# mix_race.sh <rundir> [KEY=VALUE...]: to_race_busy.sh's route (any track), 80 s of
# a player's driving (boost, traffic lanes, brake), then the pause menu for 6 s and back.
set -u
source "$(dirname "$0")/../headless/scene_lib.sh"
scene_start "$@"
to_main_menu
note "PHASE menu"
wait_flips 300
to_single_event
press a:400 90
press right:200 25
press down:200 20
press right:200 25
press a:400 90
wait_log 'CAR1[.]bgv' "car select"
press a:400 0
note "PHASE loading"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
wait_flip $(( a + 300 ))
note "PHASE race"
for k in 0 1; do
    press rt:8000 500
    press rt+lright:1500 100
    press rt+a:6000 380
    press rt+lleft:2500 160
    press lt:1500 100
    press rt+a+lright:4000 260
    press rt+b:5000 320
    press rt+a:8000 500
done
note "PHASE pause"
press start:300 420
note "PHASE resumed"
press start:300 200
press rt:3000 200
scene_end "driven"
