#!/bin/bash
# measure.sh <name> <exe> <gm|gs|none> <crash|race|menu> [KEY=VALUE...]
# start the game, drive it to the scene, wait 20 s, then 30 s of: power/clock
# samples, a top -H snapshot of the game's threads; flip stats for those 30 s.
#
# The Steam Deck test dir (BO3_DECK_DIR, default on the SD card) holds:
#   bin/   tools/deck/* and tools/perf/deck_power.sh
#   game/  burnout3*.exe (llvm-mingw build), "Burnout 3 Takedown"/, saves/
#   umu/   umu-launcher 1.4.4 zipapp (the release xboxrecomp-cli pins, sha256
#          eb590691...c851); its runtime lands in xdg/, the prefix in prefix/
#   runs/  one dir per run
# Proton is the GE-Proton the Deck already has (game.sh, PROTONPATH). Display:
# gm = the Game Mode screen (focus.sh gives the window focus), gs = a nested
# headless gamescope (costs ~70% of a core itself), none = no window (only
# for RECOMP_PB_BACKEND=null). From BO-18 (2026-10-10).
#
#   measure.sh b1-race burnout3.exe gm race RECOMP_PB_BACKEND=d3d11
T=${BO3_DECK_DIR:-/run/media/deck/emudeck/Games/burnout3-test}
N=$1; EXE=$2; DISP=$3; WHAT=$4; shift 4
R=$T/runs/$N
$T/bin/start.sh "$N" "$EXE" "$DISP" RECOMP_TRACE=pacing=all "$@" >/dev/null
[ "$DISP" = gm ] && $T/bin/focus.sh > $R/focus.txt 2>&1 &
$T/bin/drive.sh "$N" "$WHAT" || { $T/bin/stop.sh "$N"; exit 1; }
sleep 20
pid=$(pgrep -x guest-main | head -1)
top -H -b -n 2 -d 15 -p $pid > $R/top.txt &
$T/bin/deck_power.sh "$R" 30 "$WHAT" > $R/power-summary.txt
wait
python3 $T/bin/stats.py $R/log.txt 30 > $R/stats.txt
# other processes' CPU during the window (gamescope etc.)
top -b -n 1 -o %CPU | head -15 > $R/top-all.txt
$T/bin/stop.sh "$N" >/dev/null
echo "== $N ($EXE $DISP $WHAT $*)"
cat $R/stats.txt $R/power-summary.txt
grep -a "PACING\] executor" $R/log.txt | tail -2
grep -a "PACING\] flips" $R/log.txt | tail -1
awk '/^top -/{n++} n==2' $R/top.txt | sed -n '7,20p'
