#!/usr/bin/env bash
# drive.sh <save|boot> <exe> <home> <rundir>: one headless start of the game in the
# scratch profile, driven through the pad file by tools/headless/scene_lib.sh.
#
#   boot   to the main menu, which loads Profile 1 (the save must be there)
#   save   to the main menu, then Driver Details > Profile > Save Profile >
#          Profile 1 > Overwrite YES: the game writes its own profile
#
# <home> is the scratch HOME (macOS, Linux) or the scratch profile folder
# whose Roaming and Local the caller has put in APPDATA and LOCALAPPDATA
# (Windows). HOLD='cmd' runs a command while the game sits in the menu (the
# second-instance check). The game is stopped by its process id at the end;
# on Windows that is the Windows pid of the program and of whatever it
# started: killing the bash subshell alone leaves Takedawn.exe running and
# holding the save folder's lock.
set -u
MODE=$1; EXE=$2; HM=$3; RD=$4
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$REPO/tools/headless/scene_lib.sh"
mkdir -p "$RD"; D="$(cd "$RD" && pwd)"
rm -f "$D"/* 2>/dev/null; : > "$D/pad.txt"; PADN=0; SCENE_TIMEOUT=${SCENE_TIMEOUT:-300}
cd "$(dirname "$D")"
case "$(uname -s)" in
Darwin) BACKEND=metal;  ENVI=(env -i HOME="$HM" PATH=/usr/bin:/bin:/usr/sbin TMPDIR=/tmp) ;;
MINGW*|MSYS*|CYGWIN*) BACKEND=vulkan; ENVI=(env) ;;
*)      BACKEND=vulkan; ENVI=(env -i HOME="$HM" PATH=/usr/bin:/bin TMPDIR=/tmp) ;;
esac

# stop_game <pid>: the process and its children, by pid, and wait until they are gone.
stop_game() {
    local p=$1 w
    case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        # ps -W: PID PPID PGID WINPID ...; the Windows pids of p and its children
        for w in $(ps -W 2>/dev/null | awk -v p="$p" '$1==p || $2==p {print $4}'); do
            taskkill //F //T //PID "$w" > /dev/null 2>&1
        done
        for w in $(seq 1 20); do
            [ -z "$(ps -W 2>/dev/null | awk -v p="$p" '$1==p || $2==p {print $4}')" ] && break; sleep 0.5
        done ;;
    *)  pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null
        for w in $(seq 1 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done ;;
    esac
}
scene_stop() {
    local p; p=$(cat "$D/pid" 2>/dev/null) || return 0
    stop_game "$p"
    rm -f "$D"/fb_[0-9]*.bmp
    note "stopped (flip $(flip), $(( $(date +%s) - T0 )) s)"
}

( exec "${ENVI[@]}" RECOMP_LOG_DIAG=1 RECOMP_PB_BACKEND=$BACKEND RECOMP_HEADLESS=1 \
    RECOMP_PAD_LIVE="$D/pad.txt" RECOMP_STDIO_LOG="$D/log.txt" RECOMP_FLIP_MARK=1 \
    "$EXE" --headless > "$D/out.txt" 2>&1 ) &
echo $! > "$D/pid"; T0=$(date +%s)
gpid=$(cat "$D/pid"); : > "$D/events.txt"
( ( tail -n +1 -F "$D/log.txt" 2>/dev/null & echo $! > "$D/tail.pid"; wait ) \
    | grep -a --line-buffered -E '\[GPU\] flip [0-9]+ |\[FILE\]|PAD: live "|dumped |fb_dump_at|\[AUTOPILOT\]|\[AUDIO-WAV\] t=' >> "$D/events.txt" &
  while kill -0 "$gpid" 2>/dev/null; do sleep 2; done; sleep 2; kill "$(cat "$D/tail.pid")" 2>/dev/null ) >/dev/null 2>&1 &
note "start $MODE pid=$gpid"
to_main_menu
if [ "$MODE" = save ]; then
  press down:200 20; press down:200 20; press down:200 20; press down:200 20
  press a:400 90              # Driver Details
  press down:200 20; press down:200 20; press down:200 20
  press a:400 90              # Profile
  press down:200 20
  press a:400 180             # Save Profile: the slots
  press a:400 180             # Profile 1: overwrite? on NO
  press up:300 90             # YES
  press a:400 400
  press a:400 120
  wait_flips 120
fi
if [ "${HOLD:-0}" != 0 ]; then note "holding"; eval "$HOLD"; fi
scene_stop
kill "$(cat "$D/tail.pid" 2>/dev/null)" 2>/dev/null
echo done
