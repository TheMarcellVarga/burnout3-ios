#!/usr/bin/env bash
# mix_nav.sh <rundir> [KEY=VALUE...]: main menu, then the presses in NAV ("down:200 a:400 ..."),
# a frame dumped 50 flips after each (nav_<n>.bmp). NAV_AFTER=race continues into a single race.
set -u
source "$(dirname "$0")/../headless/scene_lib.sh"
scene_start "$@"
to_main_menu
n=0
snap() {
    local f=$(( $(flip) + ${1:-50} ))
    echo "$f-$f" >> "$D/dumpat.txt"
    wait_flip $(( f + 3 ))
    n=$(( n + 1 ))
    mv "$(printf '%s/fb_flip_%05u.bmp' "$D" $f)" "$D/nav_$(printf %02d $n)_$2.bmp" 2>/dev/null || note "no frame $f"
}
snap 30 start
for p in ${NAV:-}; do case "$p" in a:*|b:*) press "$p" 90;; *) press "$p" 25;; esac; case "$p" in *!) ;; esac; [ -z "${NAVQ:-}" ] && snap 50 "${p%%:*}"; [ -n "${NAVQ:-}" ] && [ "$PADN" -gt "${NAVQ}" ] && snap 50 "${p%%:*}"; done
if [ "${NAV_AFTER:-}" = race ]; then
    to_single_event
    press a:400 90; press a:400 90
    wait_log 'CAR1[.]bgv' "car select"
    press a:400 0
    wait_log "$(track_re crash1)" "race begins"
    a=$(anchor "$(track_re crash1)"); wait_flip $(( a + 300 ))
    note "PHASE race"
    press rt:8000 500; press rt+a:6000 380; press rt:8000 500; press rt+a:8000 500
    snap 10 race
fi
scene_end "nav done"
