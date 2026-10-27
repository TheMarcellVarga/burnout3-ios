#!/usr/bin/env bash
# to_garage.sh <rundir> [KEY=VALUE...]
#
# Reference scene "garage": the main menu's Driver Details (the profile's
# stats over the menu video), then back, Single Event > Race > Select Car:
# the 3D garage with the cars on their stands. Leaves the game running at
# Select Car (pid in <rundir>/pid), or STOP_AT_END=1.
#
# Shots (CAPTURE=1): garage_details, garage_car.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
press down:200 20; press down:200 20; press down:200 20; press down:200 20
press a:400 0               # Driver Details
# Over the attract movie, as the main menu: anchored on _FEMain.xmv.
shot garage_details "$(anchor '_FEMain[.]xmv')" 1100 12
press b:400 60              # back to the main menu, cursor on Driver Details
press up:200 20; press up:200 20; press up:200 20       # Single Event
press a:400 90              # Select Mode
press a:400 90              # Race: Select Options
press a:400 0               # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
shot garage_car "$(anchor 'CAR1[.]bgv')" 150
scene_end "at Select Car"
