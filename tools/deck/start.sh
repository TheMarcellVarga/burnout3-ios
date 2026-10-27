#!/bin/bash
# start.sh <name> <exe> <gm|gs|none> [KEY=VALUE...]: game.sh as a user unit bo3-<name>
# (survives ssh), sampler beside it. Stop: stop.sh <name>.
T=${BO3_DECK_DIR:-/run/media/deck/emudeck/Games/burnout3-test}
N=$1; shift
R=$T/runs/$N; mkdir -p "$R"
systemctl --user reset-failed "bo3-$N" 2>/dev/null
systemd-run --user --collect --unit "bo3-$N" -p KillMode=control-group \
    /bin/bash "$T/bin/game.sh" "$R" "$@"
