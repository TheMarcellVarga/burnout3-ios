#!/usr/bin/env bash
# test-arg-order.sh <program> <scratch dir> [<disc image or folder>]
#
# --data <dir> means the same before and after the word it goes with:
# --data-status, --install (where it names the destination, as --dest does),
# --build-shaders, --bug-report and --version; and TAKEDAWN_DATA says the
# same as --data. Each pair of command lines is run with a scratch profile
# (HOME and XDG_* in <scratch dir>; APPDATA and LOCALAPPDATA on Windows) and
# must give the same exit status and the same answer. Nothing is installed:
# --install is run with --check.
set -u
PROG="${1:?program}"; T="${2:?scratch dir}"; DISC="${3:-}"
die() { echo "FAIL $*" >&2; exit 1; }
[ -x "$PROG" ] || die "no program $PROG"
mkdir -p "$T" && T="$(cd "$T" && pwd)" || die "no scratch dir"
[ "$T" != "$(cd "${HOME:-/}" && pwd)" ] || die "the scratch dir is the real home"
P="$T/profile"; D="$T/data root"; rm -rf "$P" "$D" "$T/out"; mkdir -p "$P" "$D" "$T/out" "$T/cwd"
case "$(uname -s)" in
    MINGW*|MSYS*) PW="$(cygpath -w "$P")"; D="$(cygpath -w "$D")"
        run() { ( cd "$T/cwd" && APPDATA="$PW\\Roaming" LOCALAPPDATA="$PW\\Local" USERPROFILE="$PW" "$PROG" "$@" ); } ;;
    *)  run() { ( cd "$T/cwd" && env -i HOME="$P" XDG_DATA_HOME="$P/data" XDG_CACHE_HOME="$P/cache" \
                      PATH=/usr/bin:/bin ${TAKEDAWN_DATA:+TAKEDAWN_DATA="$TAKEDAWN_DATA"} "$PROG" "$@" ); } ;;
esac
n=0
same() {    # <what> <args A...> -- <args B...>: same status, same stdout
    local what="$1" a=() b=() sa sb; shift
    while [ "$1" != -- ]; do a+=("$1"); shift; done; shift; b=("$@")
    run "${a[@]}" > "$T/out/a.txt" 2> "$T/out/a.err"; sa=$?
    run "${b[@]}" > "$T/out/b.txt" 2> "$T/out/b.err"; sb=$?
    [ "$sa" = "$sb" ] || die "$what: exit status $sa against $sb"
    # the bug report's file name carries the time of day
    if ! diff <(sed -E 's/[0-9]{8}-[0-9]{6}/TIME/g' "$T/out/a.txt") <(sed -E 's/[0-9]{8}-[0-9]{6}/TIME/g' "$T/out/b.txt") > /dev/null; then
        diff "$T/out/a.txt" "$T/out/b.txt" | head -6 >&2; die "$what: the two orders answer differently"
    fi
    n=$((n + 1))
}
same "--data-status" --data-status --data "$D" -- --data "$D" --data-status
grep -q -F "LOG data root $D" "$T/out/b.txt" || die "--data before --data-status is not the root asked about ($(sed -n 3p "$T/out/b.txt"))"
TAKEDAWN_DATA="$D" run --data-status > "$T/out/env.txt" 2>/dev/null
case "$(uname -s)" in MINGW*|MSYS*) ;; *) cmp -s "$T/out/env.txt" "$T/out/a.txt" || die "TAKEDAWN_DATA does not answer as --data does"; n=$((n + 1)) ;; esac
same "--version" --version --data "$D" -- --data "$D" --version
same "--build-shaders --status" --build-shaders --status --data "$D" -- --data "$D" --build-shaders --status
same "--bug-report" --bug-report --out "$T/out" --data "$D" -- --data "$D" --bug-report --out "$T/out"
if [ -n "$DISC" ] && [ -e "$DISC" ]; then
    same "--install --check" --install "$DISC" --check --data "$D" -- --data "$D" --install "$DISC" --check
    grep -q "^RESULT OK" "$T/out/b.txt" || die "--data before --install --check: no RESULT OK"
    same "--install --check, --dest" --install "$DISC" --check --dest "$D" -- --dest "$D" --check --install "$DISC"
    [ -z "$(ls -A "$D")" ] || die "--install --check wrote into the data root"
fi
echo "OK   --data means the same before and after its word: $n pairs"
