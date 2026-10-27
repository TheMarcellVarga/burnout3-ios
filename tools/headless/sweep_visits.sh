#!/usr/bin/env bash
# sweep_visits.sh [part...]: the visit list of the coverage sweep (BO-208), one per
# line, for sweep.sh:  tools/headless/sweep.sh out $(tools/headless/sweep_visits.sh)
# parts: race roadrage timeattack crash garage auto wt split menus steps (default: all)
# wt, split and menus write their script files to $STEPS_DIR (default ./sweep-steps).
# Single Event's Region/Track rows: 1 USA 13 tracks, 2 Europe 16, 3 Asia 8 (both
# directions are separate entries), unlocked in memory.
parts=${*:-race roadrage timeattack crash garage wt split menus steps}
STEPS_DIR=${STEPS_DIR:-$PWD/sweep-steps}
mkdir -p "$STEPS_DIR"
rep() { local n=$2 i; for ((i = 0; i < n; i++)); do echo "$1"; done; }
here=$(cd "$(dirname "$0")" && pwd)
for p in $parts; do
  case $p in
  race)
    for t in $(seq 1 13); do echo race/1/$t/1/12; done
    for t in $(seq 1 16); do echo race/2/$t/1/12; done
    for t in $(seq 1 8); do echo race/3/$t/1/12; done ;;
  roadrage)
    for rt in 1/1 1/4 1/7 1/10 1/13 2/2 2/5 2/9 2/12 2/16 3/3 3/6; do echo roadrage/$rt/1/12; done ;;
  timeattack)
    for rt in 1/2 2/4 3/6; do echo timeattack/$rt/1/12; done ;;
  crash)
    for j in $(seq 1 40); do echo crash/0/$j/1; done ;;
  garage)
    echo garage/1/1/70 ;;
  auto)
    for rt in 1/3 1/9 2/4 2/10 3/2 3/7; do echo autorace/$rt/1/150; done
    echo autoroadrage/1/5/1/150; echo autoroadrage/2/6/1/150 ;;
  wt)
    # World Tour: region R, the location L (right presses on the map), the
    # event E (ups from the list's last row), then whatever it asks: a Select
    # Car, and the race tail. Events that are not races fail their waits and
    # keep the keys they made.
    for r in 1 2 3; do for l in 0 1 2 3 4 5; do for e in 0 1 2 3 4 5; do
      f=$STEPS_DIR/wt_${r}_${l}_${e}.steps
      { echo bootmain; echo "wait 60"; echo "press a:400 200"; rep "press right:200 60" $((r - 1))
        echo "press a:400 200"; rep "press right:200 60" $l; echo "press a:400 200"
        rep "press up:200 40" $e; echo "press a:400 150"; echo "mark select"; echo "wait 120"
        echo "race_tail"; echo end; } > "$f"
      echo "script:$f"
    done; done; done ;;
  split)
    # Multiplayer: 2 downs from the main menu; modes race, roadrage, teamcrush,
    # doubleimpact, partycrash (split_scene.sh); P1 and P2 pick the first car.
    m=0
    for mode in race roadrage teamcrush doubleimpact partycrash; do
      f=$STEPS_DIR/split_$mode.steps
      { echo bootmain; echo "wait 60"; echo "press down:200 30"; echo "press down:200 30"
        echo "press a:400 150"; rep "press down:200 30" $m; echo "press a:400 150"
        case $mode in race|roadrage) echo "press right:200 30"; echo "press down:200 30"; echo "press right:200 30" ;;
                      *) echo "press down:200 30" ;; esac
        echo "pressuntil a:400 car1.bgv 150"; echo "mark p1 car"; echo "wait 60"
        echo "press a:400 90"; echo "press p2-a:400 0"; echo "pressuntil p2-a:400 streamed.dat 150"; echo "mark loaded"
        echo "wait 700"; echo "mark driving"
        echo "press p2-rt:9000 0"; echo "press rt:9000 540"; echo "press rt+a+lleft:5000 600"; echo "press rt:4000 250"
        echo "mark done"; echo end; } > "$f"
      echo "script:$f"; m=$((m + 1))
    done ;;
  menus)
    # The title's own menu pages: Driver Details, the garage's car classes, the options.
    f=$STEPS_DIR/menus.steps
    { echo bootmain; echo "wait 60"; echo "mark main"
      echo "press down:200 30"; echo "press down:200 30"; echo "press down:200 30"; echo "press down:200 30"
      echo "press a:400 200"; echo "mark driver details"; echo "press right:200 60"; echo "mark dd2"
      echo "press right:200 60"; echo "mark dd3"; echo "press right:200 60"; echo "mark dd4"
      echo "press b:300 120"; echo "press up:200 30"; echo "press up:200 30"; echo "press a:400 200"; echo "mark single event"
      echo end; } > "$f"
    echo "script:$f" ;;
  steps)
    for f in "$here"/sweep/*.steps; do [ -f "$f" ] && echo "script:$f"; done ;;
  esac
done
