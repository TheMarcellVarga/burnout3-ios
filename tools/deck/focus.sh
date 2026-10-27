#!/bin/bash
# focus.sh: Game Mode shows only windows whose STEAM_GAME app id is in Steam's
# GAMESCOPECTRL_BASELAYER_APPID list; give the game's own window the first id
# there (a property on our window only; Steam itself is not touched).
export DISPLAY=:0
for i in $(seq 120); do
    W=$(xdotool search --name '^Burnout 3' 2>/dev/null | head -1)
    [ -n "$W" ] && break; sleep 1
done
[ -n "$W" ] || { echo "no window"; exit 1; }
ID=$(xprop -root GAMESCOPECTRL_BASELAYER_APPID | sed 's/.*= \([0-9]*\).*/\1/')
xprop -id $W -f STEAM_GAME 32c -set STEAM_GAME $ID
sleep 1; xprop -root GAMESCOPE_FOCUSED_WINDOW
