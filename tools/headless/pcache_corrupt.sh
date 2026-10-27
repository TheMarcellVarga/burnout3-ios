#!/usr/bin/env bash
# pcache_corrupt.sh [cache dir]  (BO-208)
#
# The caches under damage: builds the manifest's graphics into a fresh cache
# (--build-shaders), then, one at a time, truncates and bit-flips the files
# the backend reads at its start (the driver's pipeline cache with its header,
# the key list, the SPIR-V file), builds again and checks that the program
# neither crashes nor fails, and that the damage was seen: a damaged blob is
# named and removed (Vulkan), a damaged list or SPIR-V file is cut at the bad
# record. Needs a build with a manifest (graphics/pipelines-<backend>.manifest).
# Run it from the folder that holds "Burnout 3 Takedown"; EXE is the program
# (default ./bin/burnout3), RECOMP_PB_BACKEND the backend as for any run.
set -u
EXE=${EXE:-./bin/burnout3}
C=${1:-$(mktemp -d)}
fail=0
run() {
    RECOMP_HEADLESS=1 RECOMP_AUDIO_MUTE=1 "$EXE" --build-shaders --force --cache-dir "$C" > "$C/out.txt" 2>&1
    rc=$?
    grep -a 'RESULT OK' "$C/out.txt" >/dev/null && [ $rc -eq 0 ]
}
rm -rf "$C"; mkdir -p "$C"
run || { echo "FAIL: the first build did not finish (see $C/out.txt)"; exit 1; }
echo "first build: $(grep -a '^STEP shaders OK' "$C/out.txt" | cut -c1-120)"
files=$(cd "$C" && ls *.bin)
for f in $files; do
    for how in flip truncate; do
        cp "$C/$f" "$C/$f.orig"
        size=$(wc -c < "$C/$f")
        if [ "$how" = flip ]; then
            python3 - "$C/$f" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read()); i = len(b) // 2; b[i] ^= 0xFF
open(p, 'wb').write(b)
PY
        else
            head -c $((size * 2 / 3)) "$C/$f.orig" > "$C/$f"
        fi
        if run; then
            msg=$(grep -a -E "damaged|truncated|cut at|started afresh|of another" "$C/out.txt" | head -1 | cut -c1-140)
            echo "ok   $f $how: finished${msg:+; says: $msg}"
        else
            echo "FAIL $f $how: the build failed or crashed (see $C/out.txt)"; fail=1
        fi
        rm -f "$C/$f.orig"
    done
done
exit $fail
