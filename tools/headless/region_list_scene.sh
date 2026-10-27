#!/usr/bin/env bash
# region_list_scene.sh <rundir> [KEY=VALUE...]
#
# Single Event > Race > Select Options with the Region and Track rows walked
# (BO-139: BO3_UNLOCK_ALL=1 must offer every region and track, not only USA).
# Shots (CAPTURE=1): region_0 (Random), region_1 .. region_3 (the regions
# the title lists after it, with the Track row on the region's first track)
# and, for each region, track_<r>_<k> for the first TRACKS (default 3) tracks.
# Region/Track values are read off the shots.
#
# The same variables as every scene (scene_lib.sh). Run it with
# BO3_UNLOCK_ALL=1 for the unlocked lists, without for the profile's own.
set -u
source "$(dirname "$0")/scene_lib.sh"
scene_start "$@"
to_main_menu
to_single_event
press a:400 90              # Race: Select Options (Region, Track, Rivals)
shot region_0 "$(flip)" 5 0
for r in 1 2 3; do
    press right:200 25      # Region: next (stops at the last one)
    shot "region_$r" "$(flip)" 5 0
    press down:200 20       # Track row
    for (( k = 1; k <= ${TRACKS:-3}; k++ )); do
        press right:200 25  # Track: next
        shot "track_${r}_$k" "$(flip)" 5 0
    done
    press up:200 20         # back to the Region row
done
scene_end "region/track lists walked"
