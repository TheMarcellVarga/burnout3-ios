#!/usr/bin/env bash
# to_intro.sh <rundir> [KEY=VALUE...]
#
# Reference scene "intro video": boot to the attract loop, nothing pressed.
# The title plays englis30.xmv (EA / legal), cri_rw30.xmv (Criterion,
# RenderWare) and Titles30.xmv (the intro film, 57 s), then the attract
# loop (_FEMain.xmv). The movies are WMV2 in XMV, so ffmpeg decodes the
# reference frames (golden.py xmvref). Leaves the game running on the
# attract loop, or STOP_AT_END=1.
#
# Shots (CAPTURE=1): intro_ea, intro_criterion, intro_titles_a/b/c.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
wait_log 'englis30[.]xmv' "englis30.xmv"
shot intro_ea "$(anchor 'englis30[.]xmv')" 90
wait_log 'cri_rw30[.]xmv' "cri_rw30.xmv"
shot intro_criterion "$(anchor 'cri_rw30[.]xmv')" 180
wait_log 'Titles30[.]xmv' "Titles30.xmv"
a=$(anchor 'Titles30[.]xmv')
shot intro_titles_a "$a" 300
shot intro_titles_b "$a" 1200
shot intro_titles_c "$a" 2400
wait_log '_FEMain[.]xmv' "attract (_FEMain.xmv)"
scene_end "at the attract loop"
