#!/usr/bin/env bash
# crashnav_scene.sh <rundir> [KEY=VALUE...]
#
# The front end's two 3D cameras (BO-215, GitHub #15). Main menu > Burnout 3
# World Tour: Crash Nav, Select Region (the globe); then Single Event > Race >
# Select Car (the garage). Shots (CAPTURE=1): crashnav_globe, crashnav_garage.
#
# As on the Xbox, the globe fills the left half of the picture, centred on
# North America with the green relief over it, and the selected car fills the
# middle of the garage. A globe about 130 columns wide in the middle of the
# frame and a garage seen from far back are the view windows built from 1.0
# instead of tan(fov/2): the lifter's ffree/fincstp after FPTAN (toolkit
# tools/recomp/lifter.py, test_lifter_x87_trig.py).
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
press a:400 0               # Burnout 3 World Tour: Crash Nav, Select Region
shot crashnav_globe "$(flip)" 240 2
# BO3_HUD_DUMP=<file> in the environment: a dump of the 2D scenes here.
if [ -n "${BO3_HUD_DUMP:-}" ]; then touch "$BO3_HUD_DUMP.req"; wait_flips 30; fi
press b:400 120             # back to the main menu
press down:200 20
press a:400 90              # Single Event: Select Mode
press a:400 90              # Race: Select Options
press a:400 0               # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
shot crashnav_garage "$(anchor 'CAR1[.]bgv')" 150 2
scene_end "at Select Car"
