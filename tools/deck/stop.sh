#!/bin/bash
# stop.sh <name>: end the run's unit (the whole cgroup: gamescope, umu, wine, game)
T=${BO3_DECK_DIR:-/run/media/deck/emudeck/Games/burnout3-test}
systemctl --user stop "bo3-$1" 2>/dev/null
sleep 2
WINEPREFIX=$T/prefix /home/deck/.local/share/Steam/compatibilitytools.d/GE-Proton10-10/files/bin/wineserver -k 2>/dev/null
pgrep -a -x guest-main || echo "no game left"
