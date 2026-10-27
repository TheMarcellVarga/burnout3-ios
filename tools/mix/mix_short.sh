#!/usr/bin/env bash
# mix_short.sh <rundir> [KEY=VALUE...]: into a race, RACE_SECS (default 24) of driving with boost.
set -u
source "$(dirname "$0")/../headless/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
press a:400 90; press right:200 25; press down:200 20; press right:200 25; press a:400 90
wait_log 'CAR1[.]bgv' "car select"
press a:400 0
wait_log "$(track_re crash1)" "race begins"
a=$(anchor "$(track_re crash1)"); wait_flip $(( a + 300 ))
note "PHASE race"
n=$(( ${RACE_SECS:-24} / 12 ))
for (( k = 0; k < n; k++ )); do press rt:6000 380; press rt+a+lright:3000 200; press rt+a+lleft:3000 200; done
scene_end "driven"
