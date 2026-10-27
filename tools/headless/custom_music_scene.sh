#!/usr/bin/env bash
# custom_music_scene.sh <rundir> [KEY=VALUE...]
#
# The custom-music check (BO-108, BO-120): a made folder of 142 songs (more
# than EA GAMES TRAX's 44, which is what the title's own track table cannot
# take an index of) as one soundtrack, then in the title:
#
#   1. Driver Details > Settings > EA GAMES TRAX, X: the soundtrack, its
#      first song previewed
#   2. 59 rows down the list (each previews its song), B: cancel, back to
#      EA GAMES TRAX with the custom list's next row, 60
#   3. the screen again, Y (random play), X to the soundtrack, A: chosen
#   4. MENU_SECS (30) in the menu, then a race for RACE_SECS (30), the Black
#      button twice (next song)
#
# and at the end: the game still runs, the log has no fault, songs of the
# folder were opened in the menu and in the race. Exit status 0 when all of
# that holds. The game is stopped at the end.
#
#   SPEAKERS=5.1|stereo      (default 5.1: RECOMP_AUDIO_SPEAKERS)
#   SPLIT_MUSIC=1|0          (default 1: RECOMP_AUDIO_SPLIT_MUSIC)
#   tools/headless/custom_music_scene.sh runs/cm_51_split
#   SPEAKERS=stereo SPLIT_MUSIC=0 tools/headless/custom_music_scene.sh runs/cm_st
#
# As every scene: a scratch HOME (SCENE_HOME, default <rundir>/home), no
# settings file, the saves copied from SAVES; headless, so no sound is
# heard (RECOMP_AUDIO_WAV=<file> as an extra argument keeps it).
set -u
source "$(dirname "$0")/scene_lib.sh"
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RD="$(cd "$REPO" && mkdir -p "$1" && cd "$1" && pwd)"
HOME_DIR="${SCENE_HOME:-$RD/home}"
MUSIC="$RD/music"
mkdir -p "$HOME_DIR"

# The folder: one 20 s tone (8 kHz, 8 bit, mono: 160 KB) under 142 names.
rm -rf "$MUSIC"; mkdir -p "$MUSIC/Made 142"
"${PYTHON:-python3}" - "$MUSIC/Made 142" <<'PY'
import math, os, struct, sys
d = sys.argv[1]
rate, secs = 8000, 20
pcm = bytes(128 + int(60 * math.sin(2 * math.pi * 440 * i / rate)) for i in range(rate * secs))
hdr = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate, 1, 8) \
      + b"data" + struct.pack("<I", len(pcm))
first = os.path.join(d, "001 tone.wav")
open(first, "wb").write(hdr + pcm)
for i in range(2, 143):
    os.link(first, os.path.join(d, "%03d tone.wav" % i))
PY

scene_start "$@" HOME="$HOME_DIR" RECOMP_SETTINGS=none \
    RECOMP_AUDIO_MUSIC_DIR="$MUSIC" \
    RECOMP_AUDIO_SPEAKERS="${SPEAKERS:-5.1}" RECOMP_AUDIO_SPLIT_MUSIC="${SPLIT_MUSIC:-1}"
songs() { grep -ac '\[SOUNDTRACK\] song ' "$D/log.txt" 2>/dev/null || true; }
fail=0
bad() { note "FAIL: $*"; fail=1; }

to_main_menu
# Driver Details > Settings > EA GAMES TRAX.
press down:200 20; press down:200 20; press down:200 20; press down:200 20
press a:400 90
press down:200 20; press down:200 20; press down:200 20; press down:200 20
press a:400 90
press down:200 20; press down:200 20; press down:200 20
press a:400 120

# 1. X: the soundtrack.
press x:300 200
[ "$(songs)" -ge 1 ] || bad "the soundtrack's first song was not opened"
# 2. Far down its list, then cancel: EA GAMES TRAX with that row.
# 59 rows: the cancel then asks EA GAMES TRAX for track 60, whose "record"
# past its 44-entry table is one that faults in the pop-up (BO-120); other
# rows give garbage that happens to be readable.
for _ in $(seq 1 "${ROWS:-59}"); do press down:120 6; done
wait_flips 120
press b:300 400
wait_flips 300                              # the EA track starts, its pop-up shows
# 3. The screen again, random play, the soundtrack, confirm.
# (the cancel left the Settings list on its first row)
press down:200 20; press down:200 20; press down:200 20
press a:400 150
press y:300 120
chosen_before=$(songs)
press x:300 200
press a:400 200
menu_songs=$(( $(songs) - chosen_before ))
# 4. In the menu, then a race.
t=$(date +%s); until [ $(( $(date +%s) - t )) -ge "${MENU_SECS:-30}" ]; do alive; sleep 1; done
press b:300 90; press b:300 120            # Driver Details, the main menu
press up:200 20; press up:200 20; press up:200 20
press a:400 90                              # Single Event
press a:400 90                              # Race
press right:200 25; press down:200 20; press right:200 25
press a:400 150
wait_log 'CAR1[.]bgv' "car select"
press a:400 0
wait_log "$(track_re crash1)" "race begins"
before=$(songs)
press rt:$(( ${RACE_SECS:-30} * 1000 )) 0
press black:200 120; press black:200 120
wait_flips 120
[ "$(songs)" -gt "$before" ] || bad "no song of the folder was opened in the race"
[ "$menu_songs" -ge 1 ] || bad "no song when the soundtrack was chosen again"
kill -0 "$(cat "$D/pid")" 2>/dev/null || bad "the game is gone"
if grep -aqE '\[FAULT\]|SIGSEGV|SIGBUS|imgui-error' "$D/log.txt"; then
    bad "a fault in the log: $(grep -aE '\[FAULT\]|= guest|#1 ' "$D/log.txt" | head -3 | tr '\n' ' ')"
fi
note "songs opened: $(songs); guarded starts: $(grep -ac 'EA GAMES TRAX was asked for track' "$D/log.txt" || true)"
STOP_AT_END=1 scene_end "custom music: $([ $fail = 0 ] && echo ok || echo FAILED) (speakers ${SPEAKERS:-5.1}, split_music ${SPLIT_MUSIC:-1})"
exit $fail
