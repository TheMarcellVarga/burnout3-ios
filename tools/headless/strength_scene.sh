#!/usr/bin/env bash
# strength_scene.sh <rundir> [KEY=VALUE...]
#
# The strength sliders of the title's bloom and motion blur (graphics.bloom,
# graphics.motion_blur, BO-212, docs/effects.md) checked by the picture. Race,
# USA, the first track, the first car, as fx_scene.sh. After the GO the car is
# driven with the accelerator and boost held for DRIVE_SECS seconds (default
# 70), and the frames named by FRAMES are dumped: "from-to" flips counted from
# the stage's anchor (the log line of tracks\crash1.rws), as many as the
# dump list takes ahead of the game. Strengths come in with the run, in the
# environment: RECOMP_GFX_BLOOM=0.5 RECOMP_GFX_MOTION_BLUR=0.5 (any of 0, 0.1
# .. 1), or by BO3_FX_AT in the line form fx_scene.sh uses.
#
#   SCAN=<every>   one frame every <every> flips of the drive (default 20),
#                  to find a place by eye (a tunnel, a row of lamps)
#   FRAMES="a-b c-d ..."  these flip ranges (relative to the anchor) instead
#
#   AUTOPILOT=1    no pad: the title's AI drives (RECOMP_DEBUG=autopilot=1) and
#                  the race steps once a flip (RECOMP_GAME_RACE_CLOCK=1,
#                  docs/race-clock.md), so a frame of the same flip is the
#                  same picture from run to run (the exact comparison
#                  between builds and between strengths)
#
#   CYCLE=<every>  at every <every> flips of the drive (from 1500 on) one
#                  effect goes 100%, 50%, 0% five flips apart (bloom and
#                  blur in turn, the other at 100%) and the frames of that
#                  stretch are dumped: FX_AT_<k>_<effect> in cycles.tsv. The
#                  world moves a few metres between the three; the frames
#                  after each change settle in two flips (BO3_FX_AT)
#
# Output: <rundir>/frames/fb_flip_N.bmp (N absolute), <rundir>/anchor.txt.
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; shift
export CAPTURE=1
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
ap=()
[ "${AUTOPILOT:-0}" = 1 ] && ap=(RECOMP_DEBUG=autopilot=1 RECOMP_GAME_RACE_CLOCK=1)
fxa=()
[ -n "${CYCLE:-}" ] && fxa=(BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt")
scene_start "$rd" ${ap[@]+"${ap[@]}"} ${fxa[@]+"${fxa[@]}"} "$@"
: > "$D/fx.txt"; : > "$D/cycles.tsv"
to_main_menu
to_single_event
press a:400 90              # Race: Select Options
press right:200 25          # Region: Random > USA
press down:200 20
press right:200 25          # Track: Random > the first
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading
wait_log 'streamed[.]dat' "track streamed in"
wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
echo "$a" > "$D/anchor.txt"

secs=${DRIVE_SECS:-70}
# The dump list: ranges are read ahead of the game; 64 at a time.
want=()
if [ -n "${CYCLE:-}" ]; then
    k=0
    for (( f = 1500; f < 1500 + secs * 60 - 200; f += CYCLE )); do
        want+=("$(( f - 1 ))-$(( f + 14 ))")
        what=bloom; [ $(( k % 2 )) = 1 ] && what=blur
        # the file is read ahead of the game: appended while it is behind
        cyc[$k]="$what $f"
        k=$(( k + 1 ))
    done
elif [ -n "${FRAMES:-}" ]; then
    for r in $FRAMES; do want+=("$r"); done
else
    for (( f = ${SCAN_FROM:-1500}; f < 1500 + secs * 60; f += ${SCAN:-20} )); do want+=("$f-$f"); done
fi
queued=0; fxq=0
queue_fx() {
    local now=$(( $(flip) - a )) c
    while [ "$fxq" -lt "${#cyc[@]}" ]; do
        set -- ${cyc[$fxq]}
        [ "$2" -gt $(( now + 600 )) ] && break
        {
            echo "$(( a + $2 )) $1 1"
            echo "$(( a + $2 + 5 )) $1 0.5"
            echo "$(( a + $2 + 10 )) $1 0"
            echo "$(( a + $2 + 16 )) $1 1"
        } >> "$D/fx.txt"
        printf '%s\t%s\n' "$1" "$(( a + $2 ))" >> "$D/cycles.tsv"
        fxq=$(( fxq + 1 ))
    done
}
queue_some() {   # keep at most ~40 ranges ahead of the game
    local now=$(( $(flip) - a )) lo hi
    [ -n "${CYCLE:-}" ] && queue_fx
    # The dump list holds 64 ranges: the ones behind the game go.
    if [ -s "$D/dumpat.txt" ]; then
        awk -F- -v n="$(flip)" '$2 >= n' "$D/dumpat.txt" > "$D/dumpat.new" 2>/dev/null \
            && mv "$D/dumpat.new" "$D/dumpat.txt"
    fi
    while [ "$queued" -lt "${#want[@]}" ]; do
        lo=${want[$queued]%-*}; hi=${want[$queued]#*-}
        [ "$lo" -gt $(( now + 1200 )) ] && break
        echo "$(( a + lo ))-$(( a + hi ))" >> "$D/dumpat.txt"
        queued=$(( queued + 1 ))
    done
}

queue_some
wait_flip $(( a + 200 ))
queue_some
# The car stands on the grid after the GO. Up to speed, then the drive.
wait_flip $(( a + 1200 ))
queue_some
if [ "${AUTOPILOT:-0}" != 1 ]; then
echo "rt:9010" >> "$D/pad.txt"
echo "rt+lleft:310" >> "$D/pad.txt"
echo "rt+a:5010" >> "$D/pad.txt"
for (( k = 0; k * 21 < secs; k++ )); do
    cat >> "$D/pad.txt" <<'EOF'
rt:3000
rt+lt+lleft:500
rt+lleft:400
rt:2000
rt+lt+lright:500
rt+lright:400
rt+a:6000
rt+lleft:300
rt+a:5000
rt+lright:300
EOF
done
fi
end=$(( a + 1200 + secs * 60 ))
while [ "$(flip)" -lt "$end" ]; do alive; queue_some; sleep 1; done
mkdir -p "$D/frames"
mv "$D"/fb_flip_*.bmp "$D/frames/" 2>/dev/null
scene_end "strength scene (anchor $a)"
