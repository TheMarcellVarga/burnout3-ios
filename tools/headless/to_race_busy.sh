#!/usr/bin/env bash
# to_race_busy.sh <rundir> [KEY=VALUE...]   (to_race.sh with a player's driving)
#
# Reference scene "race": Single Event > Race, region USA, track Silver
# Lake Southbound (C3_V1; the defaults are Random), the first car. Once the
# track has streamed in and the start has run, hold the accelerator for
# RACE_SECS seconds (default 120). Leaves the game running (pid in
# <rundir>/pid); stop it with `kill $(cat <rundir>/pid)`, or STOP_AT_END=1.
#
# Shots (CAPTURE=1): race_start (before any input of ours, so the same at
# every run).
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
press a:400 90              # Race: Select Options (Region, Track, Rivals)
press right:200 25          # Region: Random > USA
press down:200 20
press right:200 25          # Track: Random > Silver Lake Southbound
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading screen
wait_log "${TRACK_RE:-C3_V1.streamed[.]dat}" "Silver Lake streamed in (C3_V1 streamed.dat; TRACK_RE overrides)"
# Then tracks\crash1.rws, 120 flips on, as the loading screen gives way to
# the intro camera; the shots count from it (streamed.dat comes while the
# loading screen, with its random tip, is still up).
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
# No shot of the intro camera: it cuts between views that differ from run
# to run (two runs at the same flip showed a close-up and a rear view).
shot race_start "$a" 300    # GO, the rolling start, before any input of ours
# Driving as a player does, not a cruise: steering into the traffic lanes,
# boost, the brake, as to_first_race.sh; RACE_SECS in steps of 40 s.
note "racing for ${RACE_SECS:-80} s (flip $(flip))"
n=$(( ${RACE_SECS:-80} / 40 )); [ "$n" -lt 1 ] && n=1
for (( k = 0; k < n; k++ )); do
    press rt:8000 500
    press rt+lright:1500 100
    press rt+a:6000 380
    press rt+lleft:2500 160
    press lt:1500 100
    press rt+a+lright:4000 260
    press rt+b:5000 320
    press rt+a:8000 500
done
scene_end "driven"
