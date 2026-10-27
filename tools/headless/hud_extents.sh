#!/usr/bin/env bash
# hud_extents.sh <outdir> [scene...]
#
# The widescreen HUD's cut-off check (BO-89): every scene of hud_scene.sh
# (default: race roadrage burninglap crash) once in 4:3 and once in 16:9 with
# display.hud_fix on, headless, one game at a time, with the extent monitor
# (BO3_HUD_MON) writing every drawn 2D box an edge of the visible picture
# cuts. Then hud_extents.py compares the two: a kind of box cut only in 16:9
# is the fix's defect, one cut in both is the title's own use of the overscan.
#
#   <outdir>/<scene>_43/      4:3, the title as shipped
#   <outdir>/<scene>_169on/   16:9, display.hud_fix on
#   <outdir>/<scene>.diff.txt hud_extents.py diff of the two
#   <outdir>/report.txt       all the diffs
#
# MODES="43 169on" by default; also 43on (4:3 with the fix: must equal 43,
# see hud_extents.py same) and 169off. TRACE=<callbacks|all> is
# BO3_HUD_MON_TRACE (default 4B4D0,5AC20: the boost message and the centre
# messages' text). The monitor's frames land in <run>/shots, the drive's
# periodic ones (CAPTURE=1, the default) in <run>/frames.
#
# It refuses to start while any other burnout3 runs (somebody is playing).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$here/../.." && pwd)"
out=$1; shift
scenes=("$@"); [ ${#scenes[@]} -eq 0 ] && scenes=(race roadrage burninglap crash)
py="$REPO/.venv/bin/python3"; [ -x "$py" ] || py=python3
mkdir -p "$out"; out="$(cd "$out" && pwd)"
: > "$out/report.txt"

mode_env() {
    case "$1" in
    43)     echo "RECOMP_DISPLAY_WIDESCREEN=0 RECOMP_GFX_HUD_FIX=0" ;;
    43on)   echo "RECOMP_DISPLAY_WIDESCREEN=0 RECOMP_GFX_HUD_FIX=1" ;;
    169off) echo "RECOMP_DISPLAY_WIDESCREEN=1 RECOMP_GFX_HUD_FIX=0" ;;
    169on)  echo "RECOMP_DISPLAY_WIDESCREEN=1 RECOMP_GFX_HUD_FIX=1" ;;
    *)      echo "unknown mode $1" >&2; exit 2 ;;
    esac
}

# Any burnout3 at all: this script runs one game at a time and waits for it
# to be gone, so whatever else runs is somebody playing (or another agent's
# run, which the machine cannot carry beside this one either).
playing() { pgrep '^burnout3' > /dev/null; }

for scene in "${scenes[@]}"; do
    for mode in ${MODES:-43 169on}; do
        d="$out/${scene}_$mode"
        if playing; then
            echo "another burnout3 is running (somebody is playing): not starting $scene $mode" >&2
            exit 3
        fi
        mkdir -p "$d/shots"
        # shellcheck disable=SC2046
        CAPTURE="${CAPTURE:-1}" STOP_AT_END=1 "$here/hud_scene.sh" "$d" "$scene" \
            RECOMP_AUDIO_MUTE=1 $(mode_env "$mode") \
            BO3_HUD_MON="$d/hudmon.txt" BO3_HUD_MON_TRACE="${TRACE:-4B4D0,5AC20}" \
            BO3_HUD_MON_SHOTS="$d/shots/" \
            > "$d/driver.out" 2>&1 || echo "$scene $mode: driver failed (see $d/driver.out)" >&2
        # The game takes a moment to go after its SIGTERM.
        n=0
        while kill -0 "$(cat "$d/pid" 2>/dev/null)" 2>/dev/null && [ $n -lt 60 ]; do sleep 1; n=$((n+1)); done
        sleep 1
    done
    if [ -f "$out/${scene}_43/hudmon.txt" ] && [ -f "$out/${scene}_169on/hudmon.txt" ]; then
        "$py" "$here/hud_extents.py" diff "$out/${scene}_43/hudmon.txt" \
            "$out/${scene}_169on/hudmon.txt" > "$out/$scene.diff.txt"
        { echo "==== $scene"; cat "$out/$scene.diff.txt"; echo; } >> "$out/report.txt"
    fi
done
cat "$out/report.txt"
