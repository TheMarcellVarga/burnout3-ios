#!/bin/bash
# deck_power.sh <outdir> <seconds> <tag> [pid]
#
# Once a second on a Steam Deck (or any amdgpu APU host): APU socket power
# (amdgpu hwmon power1_average, slowPPT, in W), GPU busy %, the current GPU
# sclk, mean CPU clock, battery discharge (BAT1 power_now, 0 on AC) and the
# game process's CPU % (all its threads; default pid: the thread group named
# guest-main, the recompiled title under Proton). Writes
# <outdir>/power-<tag>.csv and prints one summary line (means).
#
#   tools/perf/deck_power.sh runs/race 30 race
#
# From BO-18/BO-52 (2026-10-10). Start it once the scene is running, beside
# RECOMP_TRACE=pacing=all for the frame times of the same window.
R=$1; SECS=${2:-30}; TAG=${3:-scene}
HW=$(for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = amdgpu ] && echo $h; done | head -1)
DEV=$(dirname "$(ls /sys/class/drm/card*/device/gpu_busy_percent | head -1)")
pid=${4:-$(pgrep -x guest-main | head -1)}
ticks=$(getconf CLK_TCK)
prev=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null)
mkdir -p "$R"; out=$R/power-$TAG.csv
echo "t,apu_w,gpu_busy,sclk_mhz,cpu_mhz,bat_w,bat_status,game_cpu_pct" > "$out"
for i in $(seq 1 "$SECS"); do
    sleep 1
    p=$(cat $HW/power1_average 2>/dev/null || cat $HW/power1_input)
    b=$(cat $DEV/gpu_busy_percent)
    s=$(sed -n 's/^[0-9]*: \([0-9]*\)Mhz \*$/\1/p' $DEV/pp_dpm_sclk)
    c=$(awk '{s+=$1;n++} END{printf "%d", s/n/1000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq)
    bw=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null)
    bs=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)
    cur=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null)
    g=$(( (${cur:-0} - ${prev:-0}) * 100 / ticks )); prev=$cur
    echo "$i,$(awk "BEGIN{printf \"%.2f\", $p/1e6}"),$b,${s:-0},$c,$(awk "BEGIN{printf \"%.2f\", ${bw:-0}/1e6}"),$bs,$g" >> "$out"
done
awk -F, 'NR>1{n++; a+=$2; v[n]=$2; g+=$3; s+=$4; c+=$5; bw+=$6; pc+=$8}
    END{asort(v); k = int(n * 0.95); if (k < 1) k = 1
        printf "%s: %d s  APU %.2f W (p95 %.2f)  GPU busy %.0f%%  sclk %.0f MHz  CPU %.0f MHz  battery %.2f W  game CPU %.0f%%\n",
        FILENAME, n, a/n, v[k], g/n, s/n, c/n, bw/n, pc/n}' "$out"
