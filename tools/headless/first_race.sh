#!/usr/bin/env bash
# first_race.sh <rundir> [KEY=VALUE...]   (BO-208 acceptance)
#
# The first race of a cold cache, on a track the shipped manifest was made
# without: Single Event > Race, region RACE_REGION (default 2, Europe), the
# RACE_TRACK-th track (default 15: Europe P2_V1, held out of the acceptance
# manifest), the first car, then the accelerator for RACE_SECS seconds
# (default 45). Unlocked in memory (BO3_UNLOCK_ALL) with a diagnostic log
# and the cache trace on, so that the log has what the render thread
# compiled and when (acc_report.py reads it). Leaves the game running unless
# STOP_AT_END=1. The same variables as every scene (scene_lib.sh); on
# Android through tools/android/scene-launch.sh as LAUNCH.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@" BO3_UNLOCK_ALL=1 RECOMP_LOG_DIAG=1 RECOMP_TRACE=pcache
to_main_menu
to_single_event
press a:400 90              # Race: Select Options
for (( k = 0; k < ${RACE_REGION:-2}; k++ )); do press right:200 25; done   # Region
press down:200 20
for (( k = 0; k < ${RACE_TRACK:-15}; k++ )); do press right:200 25; done   # Track
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading screen
wait_log "[\\\\/]streamed[.]dat" "the track streams in"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
wait_flips 300
press rt:$(( ${RACE_SECS:-45} * 1000 )) 0
sleep "${RACE_SECS:-45}"
scene_end "first race: ${RACE_SECS:-45} s of driving"
