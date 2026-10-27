#!/usr/bin/env bash
# custom_level_scene.sh <rundir> [KEY=VALUE...]
#
# The custom-music loudness check (BO-132): the player's own songs as a
# soundtrack, chosen in the title's EA GAMES TRAX screen, then a stretch of
# the menu (the music alone) and a race, with the output kept as a WAV
# (RECOMP_AUDIO_WAV) for tools/headless/level_report.py.
#
#   SONGS=<folder of songs>      copied (never touched) into <rundir>/music/<name>
#   MODE=custom|eatrax           custom: the songs are the soundtrack; eatrax:
#                                the title's own EA GAMES TRAX, no custom music
#   LEVEL=off|quieter|match|louder   audio.custom_music_level (default: the shipped one)
#   SPEAKERS=stereo|5.1          (default stereo)
#   MENU_SECS=60  RACE_SECS=60
#   REC_TRIGGER=<file>           touched 10 s into the race (for RECOMP_MIX_TRACE_REC_START=@<file>)
#
# As every scene: a scratch HOME, no settings file, the saves copied from
# SAVES, headless. The WAV is <rundir>/out.wav; the phase times (seconds into
# the WAV) are in <rundir>/phases.txt.
set -u
source "$(dirname "$0")/scene_lib.sh"
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RD="$(cd "$REPO" && mkdir -p "$1" && cd "$1" && pwd)"
HOME_DIR="${SCENE_HOME:-$RD/home}"
MODE="${MODE:-custom}"
mkdir -p "$HOME_DIR"
extra=()
if [ "$MODE" = custom ]; then
    [ -d "${SONGS:-}" ] || { echo "SONGS=<folder> needed" >&2; exit 2; }
    rm -rf "$RD/music"; mkdir -p "$RD/music/Test songs"
    cp "$SONGS"/* "$RD/music/Test songs/"
    extra+=(RECOMP_AUDIO_MUSIC_DIR="$RD/music")
fi
[ -n "${LEVEL:-}" ] && extra+=(RECOMP_AUDIO_CUSTOM_LEVEL="$LEVEL")

scene_start "$@" HOME="$HOME_DIR" RECOMP_SETTINGS=none RECOMP_AUDIO_WAV="$RD/out.wav" \
    RECOMP_AUDIO_LEVEL_LOG=1 RECOMP_AUDIO_SPEAKERS="${SPEAKERS:-stereo}" ${extra[@]+"${extra[@]}"}
songs() { grep -ac '\[SOUNDTRACK\] song ' "$D/log.txt" 2>/dev/null || true; }
fail=0
bad() { note "FAIL: $*"; fail=1; }
# Where in the WAV a phase starts: the runtime marks the log once a second of
# audio ("[AUDIO-WAV] t=N"), the audio runs at the guest's pace, not the wall's.
aud() { tail -c 8192 "$D/events.txt" | grep -ao '\[AUDIO-WAV\] t=[0-9]*' | tail -n 1 | sed 's/.*=//'; }
mark() { echo "$1 $(aud)" >> "$RD/phases.txt"; }
: > "$RD/phases.txt"

to_main_menu
if [ "$MODE" = custom ]; then
    # Driver Details > Settings > EA GAMES TRAX, X: the soundtrack list,
    # A: that soundtrack; random play off (Y toggles it in the screen).
    press down:200 20; press down:200 20; press down:200 20; press down:200 20
    press a:400 90
    press down:200 20; press down:200 20; press down:200 20; press down:200 20
    press a:400 90
    press down:200 20; press down:200 20; press down:200 20
    press a:400 120
    press x:300 200
    [ "$(songs)" -ge 1 ] || bad "the soundtrack's first song was not opened"
    press a:400 200
fi
mark menu_start
t=$(date +%s); until [ $(( $(date +%s) - t )) -ge "${MENU_SECS:-60}" ]; do alive; sleep 1; done
mark menu_end
if [ "$MODE" = custom ]; then
    press b:300 90; press b:300 120            # Driver Details, the main menu
    press up:200 20; press up:200 20; press up:200 20
else
    press down:200 20                          # the main menu's second row
fi
press a:400 90                              # Single Event
press a:400 90                              # Race
press right:200 25; press down:200 20; press right:200 25
press a:400 150
wait_log 'CAR1[.]bgv' "car select"
press a:400 0
wait_log "$(track_re crash1)" "race begins"
mark race_start
# RECOMP_MIX_TRACE_REC_START=@<file>: the recorder (a replay for tests/apu_bus) starts now.
[ -n "${REC_TRIGGER:-}" ] && { wait_flips 600; touch "$REC_TRIGGER"; }
press rt:$(( ${RACE_SECS:-60} * 1000 )) 0
t=$(date +%s); until [ $(( $(date +%s) - t )) -ge "${RACE_SECS:-60}" ]; do alive; sleep 1; done
mark race_end
kill -0 "$(cat "$D/pid")" 2>/dev/null || bad "the game is gone"
if grep -aqE '\[FAULT\]|SIGSEGV|SIGBUS|imgui-error' "$D/log.txt"; then
    bad "a fault in the log"
fi
note "songs opened: $(songs)"
STOP_AT_END=1 scene_end "custom level: $([ $fail = 0 ] && echo ok || echo FAILED) (mode $MODE, level ${LEVEL:-default})"
exit $fail
