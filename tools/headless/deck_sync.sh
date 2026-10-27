#!/usr/bin/env bash
# deck_sync.sh <burnout3.exe> [host]: from the Mac, put the scene drivers,
# the exe and a fresh copy of the reference saves on the Deck (deck_env.sh
# says where). The game data is linked from the BO-18 folder ($T/game).
#
#   tools/headless/deck_sync.sh ../burnout3-win/bin/burnout3.exe
#   tools/headless/deck_sync.sh x.exe deck@<ip-or-host>
# Your own defaults live in the git-ignored tools/headless/local.env, e.g.
#   : "${DECK_HOST:=deck@192.0.2.10}"             # the Deck's address, when its name does not resolve
#   : "${DECK_SSH:=ssh -o HostKeyAlias=my-deck}"
# (the := form lets an already set environment variable win; an argument wins over both)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
[ ! -f "$HERE/local.env" ] || . "$HERE/local.env"
. "$HERE/scene_lib.sh"
EXE=${1:?usage: deck_sync.sh <burnout3.exe> [user@host]}
HOST=${2:-${DECK_HOST:-}}
[ -n "$HOST" ] || { echo "deck_sync: give the Deck as the second argument (deck@<address>) or set DECK_HOST" >&2; exit 2; }
SSH=${DECK_SSH:-ssh}
T=/run/media/deck/emudeck/Games/burnout3-test
$SSH "$HOST" "mkdir -p $T/scenes/tools $T/scenes/runs $T/scenes-game && \
  ln -sfn '$T/game/Burnout 3 Takedown' '$T/scenes-game/Burnout 3 Takedown' && \
  true"
rsync -a -e "$SSH" --delete --exclude local.env "$HERE/" "$HOST:$T/scenes/tools/headless/"
rsync -a -e "$SSH" "$EXE" "$HOST:$T/scenes-game/burnout3.exe"
rsync -a -e "$SSH" --delete "${SAVES:-$(scene_default_saves)}/" "$HOST:$T/scenes-game/saves.ref/"
echo "synced to $HOST:$T/scenes (game folder $T/scenes-game)"
