#!/usr/bin/env bash
# pacing_check.sh <rundir> [KEY=VALUE...]   (BO-211)
#
# A short check of the pacing watchdog in a real run: the autopilot race of
# race_drive.sh with MIX=1 (the pause menu and the settings overlay opened
# and closed a few times during the race) and RECOMP_TRACE=pacing, for
# CHECK_SECS seconds of racing (default 240), then the game is stopped and
# the log is read. No hand measurement.
#
# Pass:
#   - the race ran (at least CHECK_SECS / 15 "[PACING] flips 600" lines);
#   - no "[PACING] watchdog:" line: nothing in a normal race is a pacing
#     fault, so nothing is reset (the pauses and the overlay are void
#     windows, not faults);
#   - no "pacing fault" diagnosis line.
# Said, not judged: any other [PACING] line (executor-bound, title-bound: a
# slow machine), and the flip interval p50/p95 range of the trace windows.
# The verdict and the lines go to <rundir>/pacing_check.txt; exit 0 on pass.
#
# The other variables are race_drive.sh's and scene_lib.sh's (BIN, LAUNCH,
# GAME_DIR, SAVES, WINDOW ...).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "usage: $0 <rundir> [KEY=VALUE...]" >&2; exit 2; }
rundir=$1; shift
secs=${CHECK_SECS:-240}
REPO="${REPO:-$(cd "$here/../.." && pwd)}"
D="$(cd "$REPO" && mkdir -p "$rundir" && cd "$rundir" && pwd)"

MIX=1 STOP_AT_END=1 bash "$here/race_drive.sh" "$rundir" RECOMP_TRACE=pacing "$@" \
    > "$D/pacing_check.out" 2>&1 &
drv=$!

# Wait for the GO (the autopilot engaged), then CHECK_SECS of racing.
t=$(date +%s)
until grep -aq '\[AUTOPILOT\] engaged' "$D/log.txt" 2>/dev/null; do
    kill -0 $drv 2>/dev/null || break
    [ $(( $(date +%s) - t )) -gt 900 ] && break
    sleep 1
done
t=$(date +%s)
while kill -0 $drv 2>/dev/null && [ $(( $(date +%s) - t )) -lt "$secs" ]; do sleep 2; done
# Stop the driver and the game.
pkill -P $drv 2>/dev/null
kill $drv 2>/dev/null
[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null
sleep 2
[ -f "$D/pid" ] && kill -9 "$(cat "$D/pid")" 2>/dev/null
wait $drv 2>/dev/null

log="$D/log.txt"
out="$D/pacing_check.txt"
{
    echo "pacing check: $(date), $secs s of racing"
    [ -f "$log" ] || { echo "FAIL: no log"; exit 1; }
    engaged=$(grep -ac '\[AUTOPILOT\] engaged' "$log")
    windows=$(grep -ac '\[PACING\] flips 600' "$log")
    resets=$(grep -ac '\[PACING\] watchdog:' "$log")
    faults=$(grep -ac 'a pacing fault' "$log")
    forced=$(grep -ac 'start over$' "$log")
    echo "autopilot engaged $engaged, trace windows $windows, watchdog resets $resets," \
         "pacing-fault lines $faults, forced resets (gap, setting) $forced"
    grep -a '\[PACING\] flips 600' "$log" | sed -E 's/.*p50 ([0-9.]+) p95 ([0-9.]+).*/\1 \2/' |
        awk 'NF == 2 { if (!n || $1 < a) a = $1; if ($1 > b) b = $1; if (!n || $2 < c) c = $2;
                       if ($2 > d) d = $2; n++ }
             END { if (n) printf "flip interval p50 %.1f-%.1f ms, p95 %.1f-%.1f ms over %d windows\n", a, b, c, d, n }'
    # The watchdog's own count, from the last trace line: it ran, and how
    # many windows it voided (the pauses and the overlay).
    grep -a '\[PACING\] flips 600' "$log" | tail -1 | grep -ao 'watchdog windows.*' || echo "no watchdog count (a toolkit before BO-211?)"
    echo "[PACING] lines other than the trace:"
    grep -a '\[PACING\]' "$log" | grep -av 'flips 600\|  site \|vblank raises\|display refresh:\|swaps 600\|executor per flip\|swap interval' | head -20
    verdict=PASS
    [ "$engaged" -ge 1 ] || { verdict=FAIL; echo "FAIL: the race never started"; }
    [ "$windows" -ge $(( secs / 15 )) ] || { verdict=FAIL; echo "FAIL: only $windows trace windows"; }
    [ "$resets" -eq 0 ] || { verdict=FAIL; echo "FAIL: $resets watchdog resets in a normal race"; }
    [ "$faults" -eq 0 ] || { verdict=FAIL; echo "FAIL: $faults pacing-fault lines"; }
    grep -a '\[PACING\] flips 600' "$log" | tail -1 | grep -q 'watchdog windows [1-9]' \
        || { verdict=FAIL; echo "FAIL: the watchdog saw no window"; }
    echo "$verdict"
} | tee "$out"
grep -q '^PASS$' "$out"
