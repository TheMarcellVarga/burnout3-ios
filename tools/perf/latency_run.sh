#!/usr/bin/env bash
# latency_run.sh <rundir> [env...]
#
# Input-to-photon run (BO-74): boot, Single Event > Race > first track >
# first car, drive a few seconds, pause, then step the pause menu down/up
# N times at random gaps -- a still screen where the only change is the
# game's answer to the press -- with RECOMP_TRACE=latency writing
# <rundir>/lat.csv. Then tools/perf/latency.py <rundir>/lat.csv.
#
#   WINDOW=1   run in a window (the CAMetalLayer present and its on-glass
#              times only exist there); default headless
#   N=30       pause-menu steps (two presses each)
#   BIN=...    the binary (default ./bin/burnout3)
#
#   tools/perf/latency_run.sh runs/lat/base
#   WINDOW=1 tools/perf/latency_run.sh runs/lat/win RECOMP_DEBUG=metal_drawables=2
#
# Leaves nothing running: the game is killed at the end.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
D="$(cd "$REPO" && mkdir -p "$1" && cd "$1" && pwd)"; shift
N=${N:-30}
rm -f "$D"/log.txt "$D"/out.txt "$D"/pid "$D"/lat.csv; : > "$D/pad.txt"
cd "$REPO"
if [ "${WINDOW:-0}" = 1 ]; then HL=(); ARG=(); else HL=(RECOMP_HEADLESS=1); ARG=(--headless); fi
env ${HL[@]+"${HL[@]}"} RECOMP_PB_BACKEND="${RECOMP_PB_BACKEND:-metal}" \
    RECOMP_PAD_LIVE="$D/pad.txt" RECOMP_STDIO_LOG="$D/log.txt" \
    RECOMP_RENDER_SHADER_CACHE="${RECOMP_RENDER_SHADER_CACHE:-$REPO/build/shader-cache}" \
    RECOMP_TRACE="latency=$D/lat.csv${TRACE:+,$TRACE}" "$@" \
    "${BIN:-./bin/burnout3}" ${ARG[@]+"${ARG[@]}"} > "$D/out.txt" 2>&1 &
echo $! > "$D/pid"
PID=$(cat "$D/pid")
trap 'kill $PID 2>/dev/null || true' EXIT
press() { echo "$1" >> "$D/pad.txt"; sleep "$2"; }
alive() { kill -0 "$PID" 2>/dev/null || { echo "game exited" >&2; exit 1; }; }
until grep -aq '_FEMain.xmv' "$D/log.txt" 2>/dev/null; do alive; sleep 1; done
until grep -aq 'SaveMeta.xbx' "$D/log.txt"; do alive; press start:600 4; done
sleep 4; press a:400 0
until grep -aq 'Profile 1' "$D/log.txt"; do alive; sleep 1; done
sleep 6
press a:400 6          # load successful -> continue
press a:400 6          # main menu
press down:200 1.5
press a:400 7          # single event: Race
press a:400 8          # track
press a:400 10         # car
press a:600 8
press a:600 0
for _ in $(seq 90); do grep -aq streamed.dat "$D/log.txt" && break; alive; sleep 2; done
sleep 12; press a:400 3
press rt:8000 10       # drive a little (a live line holds the pad until done)
press start:120 3      # pause
echo "pausing; probing $N steps" >&2
for _ in $(seq "$N"); do
    press down:120 "0.$((RANDOM % 6 + 8))"
    press up:120 "0.$((RANDOM % 6 + 8))"
done
sleep 1
alive
kill "$PID"; trap - EXIT
sleep 1
python3 "$REPO/tools/perf/latency.py" "$D/lat.csv" --presses-only --digital 01,02 | tee "$D/summary.txt"
