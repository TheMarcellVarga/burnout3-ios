#!/usr/bin/env bash
# to_race.sh <rundir> [KEY=VALUE...]
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
press rt:$(( ${RACE_SECS:-120} * 1000 )) 0
scene_end "racing for ${RACE_SECS:-120} s"
