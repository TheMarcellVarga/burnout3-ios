#!/usr/bin/env bash
# to_menu.sh <rundir> [KEY=VALUE...]
#
# Reference scene "menu": start the game headless and drive it, by its own
# log, through the attract loop and the profile screen to the main menu,
# then into Single Event (Select Mode, cursor on Race). Leaves the game
# running; its pid is in <rundir>/pid. KEY=VALUE arguments go to the game's
# environment.
#
#   BIN=build/mac-asan/bin/burnout3 tools/headless/to_menu.sh runs/x RECOMP_TRACE=pacing
#
# Shots (CAPTURE=1): menu_attract, menu_main. See scene_lib.sh for the
# waits, and docs/running.md for the log lines each step waits on.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
scene_end "at Single Event: Select Mode"
