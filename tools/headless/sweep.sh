#!/usr/bin/env bash
# sweep.sh <outdir> <visit>...   (BO-208; docs/shader-prebuild.md, "The coverage sweep")
#
# Plays each visit (mode/region/track/cars/drive: shaderbuild.c, sweep_build)
# headless in a process of its own with an empty key list, so the list it
# leaves is that visit's. <outdir>/<visit>/cache holds the lists, sb.txt the
# scene's lines (SB DONE ok on success), sweep.log the title's log. Then:
#
#   pcache_keys.py manifest -o graphics/pipelines-<backend>.manifest --rev <r> \
#       --base graphics/pipelines-<backend>.manifest <outdir>/*/cache/*_pipelines.bin
#
# EXE            the program (default ./bin/burnout3), run in GAME (default .): the
#                folder that holds "Burnout 3 Takedown"
# JOBS           visits at a time (default 2)
# SWEEP_TIMEOUT  seconds a visit may take (default 600)
# SWEEP_MANIFEST=builtin  play with the program's own manifest (an acceptance run: a cold cache,
#                the first race on a track the manifest was made without); default none,
#                which is what a recording needs
# SWEEP_CACHE=dir the key lists and caches to play on (kept, not emptied: the acceptance run
#                after `--build-shaders` into the same directory)
# SWEEP_ENV      extra KEY=VALUE words for the program (e.g. RECOMP_PB_BACKEND=vulkan)
# A visit that is already done (sb.txt has SB DONE ok) is skipped.
set -u
OUT=$(mkdir -p "$1" && cd "$1" && pwd); shift
EXE=${EXE:-$PWD/bin/burnout3}
GAME=${GAME:-$PWD}
export OUT EXE GAME
one() {
    v=$1
    case "$v" in script:*) name=$(basename "${v#script:}" .steps) ;; *) name=${v//\//_} ;; esac
    d=$OUT/$name
    if grep -q 'SB DONE ok' "$d/sb.txt" 2>/dev/null; then echo "skip $v"; return 0; fi
    attempt=0
    while :; do
        attempt=$((attempt + 1))
        rm -rf "$d"; mkdir -p "$d/w" "$d/cache"
        spec=$v; sc=""
        case "$v" in script:*) spec=script; sc=BO3_SWEEP_SCRIPT=${v#script:} ;; esac
        t0=$(date +%s)
        (
            cd "$GAME" || exit 1
            # shellcheck disable=SC2086
            env BO3_SHADERBUILD_DIR="$d/w" BO3_SWEEP="$spec" ${sc:+$sc} RECOMP_RENDER_SHADER_CACHE="${SWEEP_CACHE:-$d/cache}" \
                $([ "${SWEEP_MANIFEST:-}" = builtin ] || echo RECOMP_PCACHE_MANIFEST=none) ${SWEEP_ENV:-} \
                "$EXE" --build-shaders-scene sweep > "$d/sb.txt" 2>"$d/err.txt" &
            pid=$!
            n=0
            while kill -0 $pid 2>/dev/null; do
                sleep 2; n=$((n + 2))
                if [ $n -gt "${SWEEP_TIMEOUT:-600}" ]; then kill -9 $pid 2>/dev/null; echo "SB TIMEOUT" >> "$d/sb.txt"; break; fi
            done
        )

        # A boot that did not come up (a busy machine, a flake of the title's first
        # screens: one of the first six steps) is played again, twice at most; what a
        # failed attempt compiled is dropped. Any other failure keeps what it made.
        grep -q 'SB DONE ok' "$d/sb.txt" 2>/dev/null && break
        [ $attempt -ge ${SWEEP_TRIES:-3} ] && break
        grep -aq 'SB TIMEOUT' "$d/sb.txt" && break
        grep -aq 'SB DONE fail step [1-6] ' "$d/sb.txt" || break     # only the boot is worth another try
    done
    mv "$d/w/sweep.log" "$d/sweep.log" 2>/dev/null
    rm -rf "$d/w/saves"
    r=$(grep -a 'SB DONE' "$d/sb.txt" | tail -1)
    echo "$v: ${r:-no result} ($(( $(date +%s) - t0 )) s) $(ls "$d"/cache/*_pipelines.bin 2>/dev/null | head -1 | xargs -I{} python3 "$(dirname "${BASH_SOURCE[0]:-$0}")/pcache_keys.py" {} 2>/dev/null | sed 's/.*bin: //; s/ \[.*//')"
}
export -f one
printf '%s\n' "$@" | xargs -P "${JOBS:-2}" -I{} bash -c 'one {}'
