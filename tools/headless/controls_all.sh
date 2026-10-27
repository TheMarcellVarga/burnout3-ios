#!/usr/bin/env bash
# controls_all.sh <rundir-prefix> [KEY=VALUE...]
#
# The default set of controls_scene.sh runs (BO-106), one after another:
#
#   ps2 race      the PS2 layout, a pause over the held accelerator, Quit
#   xbox race     the same presses with the setting at its default
#   ps2 crash     a crash event: captions, crash, results
#   ps2 race, nintendo face layout
#                 both settings together: the bottom button accelerates, the
#                 right-hand one drives the menus
#
# Each run's PASS/FAIL lines are in <prefix>-<name>/controls.txt; exit 1 if
# any run failed. The environment of controls_scene.sh applies (BIN, LAUNCH,
# SAVES, ...).
set -u
here="$(dirname "$0")"
pre="$1"; shift
rc=0
one() {
    local name="$1"; shift
    echo "== $name"
    if ! env "$@" bash "$here/controls_scene.sh" "$pre-$name" ${ARGS[@]+"${ARGS[@]}"}; then rc=1; fi
}
ARGS=("$@")
one ps2-race SCHEME=ps2 EVENT=race
one xbox-race SCHEME=xbox EVENT=race
one ps2-crash SCHEME=ps2 EVENT=crash
one ps2-nintendo-race SCHEME=ps2 EVENT=race FACE=nintendo
exit $rc
