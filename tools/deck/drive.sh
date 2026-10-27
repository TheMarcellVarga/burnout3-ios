#!/bin/bash
# drive.sh <name> <crash|race|menu>: drive a started run (start.sh) by its log
# through RECOMP_PAD_LIVE, as BO-25's crash.sh/race.sh on the Mac:
#   crash: Single Event > Crash > 2nd junction (Trailer Trash) > first car, hold RT
#   race:  Single Event > Race > first track (Silver Lake) > first car, hold RT
T=${BO3_DECK_DIR:-/run/media/deck/emudeck/Games/burnout3-test}
N=$1; WHAT=$2; D=$T/runs/$N; P=$D/pad.txt
alive() { systemctl --user -q is-active "bo3-$N" || { echo "game exited"; exit 1; }; }
wait_for() { until grep -aq "$1" $D/log.txt 2>/dev/null; do alive; sleep 1; done; }
wait_for '_FEMain.xmv'
until grep -aq 'SaveMeta.xbx' $D/log.txt; do alive; echo start:600 >> $P; sleep 4; done
sleep 4; echo a:400 >> $P
wait_for 'Profile 1'
sleep 6; date +%s > $D/menu_t0
[ "$WHAT" = menu ] && { echo "at main menu"; exit 0; }
echo a:400 >> $P; sleep 6          # load successful -> continue
echo a:400 >> $P; sleep 6          # main menu
echo down:200 >> $P; sleep 1.5
echo a:400 >> $P; sleep 7          # single event
if [ "$WHAT" = crash ]; then
    for i in 1 2 3; do echo down:200 >> $P; sleep 1.5; done
    echo a:400 >> $P; sleep 8      # crash: junction selection
    echo down:200 >> $P; sleep 1.5
fi
echo a:400 >> $P; sleep 10         # track/junction -> car select
echo a:600 >> $P; sleep 8
echo a:600 >> $P
for i in $(seq 120); do grep -aq "streamed.dat" $D/log.txt && break; alive; sleep 2; done
if [ "$WHAT" = crash ]; then
    sleep 10; echo a:400 >> $P; sleep 5; echo a:400 >> $P; sleep 4; echo rt:600000 >> $P
else
    sleep 12; echo a:400 >> $P; sleep 3; echo rt:600000 >> $P
fi
date +%s > $D/${WHAT}_t0
echo "$WHAT: driving"
