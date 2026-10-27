#!/bin/bash
# game.sh <rundir> <exe> <display: gm|gs|none> [KEY=VALUE...]
# Runs burnout3 (Windows build) under Proton via umu-run from the test dir.
# gs: inside a nested headless gamescope (nothing shown on the Deck screen);
# gm: on the Game Mode compositor (shown on the Deck screen); none: no display.
set -u
T=${BO3_DECK_DIR:-/run/media/deck/emudeck/Games/burnout3-test}
R=$1; EXE=$2; DISP=$3; shift 3
mkdir -p "$R"; : > "$R/pad.txt"; rm -f "$R/log.txt"
cd "$T/game"
export WINEPREFIX="$T/prefix" GAMEID=umu-default \
       PROTONPATH="${PROTONPATH:-/home/deck/.local/share/Steam/compatibilitytools.d/GE-Proton10-10}" \
       XDG_DATA_HOME="$T/xdg" XDG_CACHE_HOME="$T/cache" \
       UMU_RUNTIME_UPDATE="${UMU_RUNTIME_UPDATE:-0}" \
       PROTON_LOG_DIR="$R" \
       RECOMP_STDIO_LOG="Z:$R/log.txt" RECOMP_PAD_LIVE="Z:$R/pad.txt"
for kv in "$@"; do export "$kv"; done
env | grep -E '^(RECOMP_|PROTON|DXVK|WINE|GAMEID|XDG_DATA)' | sort > "$R/env.txt"
CMD=("$T/umu/umu-run" "$T/game/$EXE" --headless)
if [ "$DISP" = gm ]; then
    # the running Game Mode session's compositor (the Deck's screen)
    export DISPLAY=:0 GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 ENABLE_GAMESCOPE_WSI=1
    exec "${CMD[@]}" > "$R/console.txt" 2>&1
elif [ "$DISP" = gs ]; then
    exec gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -r 60 -- "${CMD[@]}" > "$R/console.txt" 2>&1
else
    exec "${CMD[@]}" > "$R/console.txt" 2>&1
fi
