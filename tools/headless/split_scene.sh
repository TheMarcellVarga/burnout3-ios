#!/usr/bin/env bash
# split_scene.sh <rundir> <mode> [KEY=VALUE...]
#
# Two-player split screen, for the two switches of BO-116
# (graphics.split_60fps, audio.split_music; docs/split-screen.md): main menu
# > Multiplayer > the mode, default options but the region and track (USA,
# the first), the first car for both players, then both pads drive for
# DRIVE_SECS seconds (default 60): the accelerator and the boost, each
# steering into the walls on its own list ("p2-" lines are the second pad's,
# toolkit src/usb/usb_gamepad.c). The title's pacing state goes to
# <rundir>/pace.txt per flip (BO3_PACE_LOG), with the player count and the
# music manager's state; tools/headless/pace_report.py reads it.
#
# Modes: race, roadrage, teamcrush, doubleimpact, partycrash (the title's
# five; the first two are races for two views, the crash modes are junctions
# where the players drive at once or, in Party Crash, one after the other).
#
# CAPTURE=1: a frame every SHOT_SECS seconds (default 5) of the drive,
# shots/t<seconds>.bmp, and the first one of the grid. With
# RECOMP_TRACE=apu after the mode the log has the APU's active voices
# ("[APU] voice N pos=", a batch every 60 voice processor frames, 0.32 s):
# tools/headless/voices_report.py counts them.
#
# Run it once as shipped and once with RECOMP_GFX_SPLIT_60FPS=1 and / or
# RECOMP_AUDIO_SPLIT_MUSIC=1 after the mode. Never with the player's HOME
# (docs/crash60.md, Running the checks).
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; mode=$2; shift 2
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
rm -f "$abs/pace.txt"
scene_start "$rd" BO3_PACE_LOG="${GAME_PATH_PREFIX:-}$abs/pace.txt" "$@"

to_main_menu
press down:200 20; press down:200 20    # Multiplayer
press a:400 90                          # Select Mode: Race, Road Rage, Team Crush, Double Impact, Party Crash
case "$mode" in
race)           ;;
roadrage)       press down:200 20 ;;
teamcrush)      press down:200 20; press down:200 20 ;;
doubleimpact)   press down:200 20; press down:200 20; press down:200 20 ;;
partycrash)     press down:200 20; press down:200 20; press down:200 20; press down:200 20 ;;
*)  die "unknown mode $mode" ;;
esac
press a:400 90                          # the mode's options
case "$mode" in
race|roadrage)
    press right:200 25                  # Region: Random > USA
    press down:200 20
    press right:200 25                  # Track: Random > the first
    ;;
*)  press down:200 20 ;;                # Junction: the first after Random
esac
[ -n "${MENU_EXTRA:-}" ] && for p in $MENU_EXTRA; do press "$p" 30; done
press a:400 90                          # P1 Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
wait_flips 60
press a:400 90                          # P1's car: P2 Select Car
press p2-a:400 0                        # P2's car: loading
wait_log 'streamed[.]dat' "stage streamed in"

shots() {   # a frame every SHOT_SECS seconds while the game runs, for <secs>
    local t0 k=0 f secs=$1
    t0=$(date +%s); mkdir -p "$D/shots"
    while [ $(( $(date +%s) - t0 )) -lt "$secs" ]; do
        alive
        if [ "${CAPTURE:-0}" = 1 ] && [ $(( $(date +%s) - t0 )) -ge $(( k * ${SHOT_SECS:-5} )) ]; then
            f=$(( $(flip) + 8 ))
            echo "$f-$f" >> "$D/dumpat.txt"
            printf '%s\t%s\n' "$(( k * ${SHOT_SECS:-5} ))" "$f" >> "$D/shots/shots.tsv"
            k=$(( k + 1 ))
        fi
        sleep 0.2
    done
    if [ "${CAPTURE:-0}" = 1 ]; then
        sleep 1
        while IFS=$'\t' read -r sec f; do
            mv "$(printf '%s/fb_flip_%05u.bmp' "$D" "$f")" \
               "$(printf '%s/shots/t%03u.bmp' "$D" "$sec")" 2>/dev/null
        done < "$D/shots/shots.tsv"
    fi
}

# Both pads from the load on: the intro and the countdown run by themselves
# (a crash mode's captions want A first).
case "$mode" in
race|roadrage) ;;
*)  wait_flips 600; press a:400 60; echo "p2-a:400" >> "$D/pad.txt" ;;
esac
for (( k = 0; k * 21 < ${DRIVE_SECS:-60} + 40; k++ )); do
    cat >> "$D/pad.txt" <<'EOF'
rt+a:7000
p2-rt+a:5000
rt+a+lleft:2200
p2-rt+a+lright:2600
rt+a:5000
p2-rt+a:7000
rt+a+lright:2600
p2-rt+a+lleft:2200
rt+a:3000
p2-rt+a:3000
rt+a+lleft:1200
p2-rt+a+lright:1200
EOF
done
shots $(( ${DRIVE_SECS:-60} + 30 ))
scene_end "split scene $mode"
