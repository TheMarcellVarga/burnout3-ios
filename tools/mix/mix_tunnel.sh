#!/usr/bin/env bash
# mix_tunnel.sh <rundir> [KEY=VALUE...]: a single race on another region's
# track, full throttle with boost for DRIVE_SECS (default 60): for scenes
# with covered sections (the title opens its reverb there, BO-119).
#   REGION_RIGHTS (default 3)  presses of right on the region row from
#                              "Random" (1 = the first region)
#   TRACK_RIGHTS  (default 1)  the same on the track row
# The track that loaded is in the log (Tracks\<region>\<folder>).
set -u
source "$(dirname "$0")/../headless/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
press a:400 90
for (( k = 0; k < ${REGION_RIGHTS:-3}; k++ )); do press right:200 25; done
press down:200 20
for (( k = 0; k < ${TRACK_RIGHTS:-1}; k++ )); do press right:200 25; done
press a:400 90
wait_log 'CAR1[.]bgv' "car select"
press a:400 0
wait_log 'streamed[.]dat' "track streamed in"
a=$(anchor 'streamed[.]dat'); wait_flip $(( a + 900 ))
note "PHASE race"
n=$(( ${DRIVE_SECS:-60} / 10 ))
for (( k = 0; k < n; k++ )); do press rt+a:9500 600; done
scene_end "driven"
