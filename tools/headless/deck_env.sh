# deck_env.sh: source this on the Steam Deck (bash, over SSH) before a
# scene driver, to run the Windows build under Proton through umu-run:
#
#   cd $T/scenes && . tools/headless/deck_env.sh
#   tools/headless/to_crash.sh runs/c1
#   CAPTURE=1 STOP_AT_END=1 tools/headless/to_garage.sh runs/g1
#
# T is the test folder (default the one BO-18 set up on the SD card):
#   $T/umu/umu-run, $T/prefix (Wine prefix), $T/xdg, $T/cache
#   $T/scenes          these scripts (tools/headless), runs/ under it
#   $T/scenes-game     the game folder the drivers run in: the exe, a
#                      symlink to the data, and saves/ copied fresh from the
#                      Mac's reference saves/ (deck_sync.sh)
#
# DECK_NATIVE=1: the native Linux Vulkan build instead ($T/vk/run/burnout3,
# or NATIVE_BIN; what vk/bin/game_native.sh sets for it must be set here
# too): no Proton, no Z: prefix, RECOMP_PB_BACKEND=vulkan.
#
# The runs keep their own game folder so that a measurement in $T/game,
# whose saves/ other runs write to, never changes the profile flow here.
T="${T:-/run/media/deck/emudeck/Games/burnout3-test}"
export WINEPREFIX="$T/prefix" GAMEID=umu-default \
       PROTONPATH="${PROTONPATH:-/home/deck/.local/share/Steam/compatibilitytools.d/GE-Proton10-10}" \
       XDG_DATA_HOME="$T/xdg" XDG_CACHE_HOME="$T/cache" UMU_RUNTIME_UPDATE=0
export GAME_DIR="${GAME_DIR:-$T/scenes-game}"
export SAVES="${SAVES:-$GAME_DIR/saves.ref}"   # copied to $GAME_DIR/saves per run
if [ "${DECK_NATIVE:-0}" = 1 ]; then
    export LAUNCH="exec '${NATIVE_BIN:-$T/vk/run/burnout3}' --headless"
    export GAME_PATH_PREFIX=
    export RECOMP_PB_BACKEND="${RECOMP_PB_BACKEND:-vulkan}"
    unset STOP
else
    export LAUNCH="exec '$T/umu/umu-run' '$GAME_DIR/${EXE:-burnout3.exe}' --headless"
    # Wine maps Z: to /: the paths the game opens (log, pad file, dumps).
    export GAME_PATH_PREFIX=Z:
    export RECOMP_PB_BACKEND="${RECOMP_PB_BACKEND:-d3d11}"
    # A Proton run leaves wineserver and its helpers behind the umu-run pid.
    export STOP="WINEPREFIX='$T/prefix' '$PROTONPATH/files/bin/wineserver' -k"
fi
