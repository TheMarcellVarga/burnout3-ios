#!/usr/bin/env bash
# update-test.sh: an update of the game, old -> new -> old again, with a scratch profile (BO-100).
#
#   update-test.sh --old <app> --new <app> --disc <disc folder|image> --saves <dir> --work <scratch dir>
#                  [--allow-same-build]
#
# <app> is what the platform ships:
#   macOS    a Takedawn.app (from the mounted dmg, or build/release/macos/Takedawn.app)
#   Linux    a Takedawn-<version>-linux-x86_64.AppImage
#   Windows  the program folder (Takedawn\ with Takedawn.exe; run this under
#            Git Bash). The Windows setup exe itself is tested by setup-test.ps1.
# --saves is a folder with UDATA and TDATA (the reference profile: one profile,
# "Profile 1"). Everything happens inside --work: HOME (macOS, Linux) or
# APPDATA and LOCALAPPDATA (Windows) point there, so the real profile is never
# read, made or moved; the script refuses a --work that is the real home or
# lies in a real profile folder. One game at a time: it does not run while a
# Takedawn of this --work runs; do not run it while someone plays.
#
# What it does, and checks (PASS/FAIL lines, exit status 1 on any FAIL):
#   1  OLD is put at the place the player keeps it (macOS /Applications-like
#      Takedawn.app; Linux the stable name Takedawn.AppImage; Windows the
#      program folder), data installed from --disc, reference saves, a
#      settings.toml with non-default values, mixer.toml + mixer-1.toml,
#      --build-shaders, then the game saves Profile 1 itself; a hash of
#      everything the player owns is taken (saves, settings, mixer files, game
#      data marker, shader cache; not logs, backups, save history, crash reports)
#   2  UPDATE: NEW replaces OLD the way the platform does it (macOS: the
#      bundle is replaced; Linux: the file is renamed over the old one, a
#      launcher script that stores the path, as a Steam shortcut does, still
#      starts it and now says the new version; Windows: the program folder is
#      copied over, as the setup does). --version changes, --data-status says
#      the data is installed, --build-shaders --status is the same as before,
#      the hash is the same
#   3  NEW starts headless to the main menu (loads Profile 1), and a second
#      copy started meanwhile is refused (exit status 3, "already running");
#      the hash is the same; the log does not say the settings started afresh
#   4  ROLLBACK: OLD put back; it boots with the same Profile 1; the hash is the
#      same (a killed game left no stale lock: the start would be refused)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLD=""; NEW=""; DISC=""; SAVES=""; WORK=""; SAME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --old) OLD="$2"; shift ;; --new) NEW="$2"; shift ;; --disc) DISC="$2"; shift ;;
        --saves) SAVES="$2"; shift ;; --work) WORK="$2"; shift ;;
        --allow-same-build) SAME=1 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac; shift
done
for v in OLD NEW DISC SAVES WORK; do [ -n "${!v}" ] || { echo "usage: see the top of $0 (missing --$(echo $v | tr A-Z a-z))" >&2; exit 2; }; done
[ -d "$SAVES/UDATA" ] || { echo "--saves: no UDATA in $SAVES" >&2; exit 2; }
FAILS=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }
same() { diff -q "$1" "$2" > /dev/null; }
check() { local n="$1"; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
say() { echo "### $*"; }

OS=$(uname -s)
mkdir -p "$WORK" && T="$(cd "$WORK" && pwd)" || exit 2
case "$OS" in
Darwin) case "$T/" in "$HOME/"|"$HOME/Library/"*) echo "--work is the real home or profile" >&2; exit 2 ;; esac ;;
MINGW*|MSYS*|CYGWIN*) case "$T/" in "$(cygpath -u "${APPDATA:-/nonexistent}")/"*|"$(cygpath -u "${LOCALAPPDATA:-/nonexistent}")/"*) echo "--work is in the real profile" >&2; exit 2 ;; esac ;;
*) [ "$T" != "$HOME" ] || { echo "--work is the real home" >&2; exit 2; } ;;
esac
rm -rf "$T/s"; S="$T/s"; mkdir -p "$S/run" "$S/logs"
PLAT=""
case "$OS" in
Darwin)
    PLAT=mac; H="$S/home"; mkdir -p "$H"
    SD="$H/Library/Application Support/Takedawn"; DD="$SD/Game"; CD="$H/Library/Caches/Takedawn"
    APP="$S/Applications/Takedawn.app"; EXE="$APP/Contents/MacOS/Takedawn"
    E() { env -i HOME="$H" PATH=/usr/bin:/bin:/usr/sbin TMPDIR=/tmp RECOMP_LOG_DIAG=1 "$@"; }
    put() { rm -rf "$APP"; mkdir -p "$S/Applications"; ditto "$1" "$APP"; }
    replace() { rm -rf "$APP.new"; ditto "$1" "$APP.new" && rm -rf "$APP" && mv "$APP.new" "$APP"; } ;;
MINGW*|MSYS*|CYGWIN*)
    PLAT=win; H="$S"; mkdir -p "$S/Roaming" "$S/Local"
    SD="$S/Roaming/Takedawn"; DD="$S/Local/Takedawn/Game"; CD="$S/Local/Takedawn/cache"
    APP="$S/app/Takedawn"; EXE="$APP/Takedawn.exe"
    export APPDATA="$(cygpath -w "$S/Roaming")" LOCALAPPDATA="$(cygpath -w "$S/Local")"
    E() { RECOMP_LOG_DIAG=1 "$@"; }
    put() { rm -rf "$APP"; mkdir -p "$S/app"; cp -r "$1" "$APP"; }
    replace() { cp -rf "$1/." "$APP/"; } ;;
*)
    PLAT=linux; H="$S/home"; mkdir -p "$H"
    SD="$H/.local/share/takedawn"; DD="$SD/Game"; CD="$H/.cache/takedawn"
    APP="$S/Applications/Takedawn.AppImage"; EXE="$APP"
    E() { env -i HOME="$H" PATH=/usr/bin:/bin RECOMP_LOG_DIAG=1 "$@"; }
    put() { mkdir -p "$S/Applications"; cp "$1" "$APP"; chmod +x "$APP"; }
    replace() { cp "$1" "$APP.tmp" && chmod +x "$APP.tmp" && mv -f "$APP.tmp" "$APP"; } ;;
esac
[ "$PLAT" = linux ] && {
    # what a Steam shortcut is: it stores the path of the file and starts it
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$APP" > "$S/shortcut.sh"; chmod +x "$S/shortcut.sh"
}
say "$PLAT, scratch profile $S"

h256() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-16; }
# What the player owns: hashes of saves, settings, mixer files, the data marker, the shader cache.
snap() {
    ( cd "$SD" && find . \( -path ./Game -o -path ./logs -o -path ./backup -o -path ./save-history -o -path ./crash \) -prune \
        -o -type f ! -name 'Partition*.img' ! -name '*.lock' -print | LC_ALL=C sort | while read -r f; do
        printf '%s  %s\n' "$(h256 "$f")" "$f"; done )
    ( cd "$CD" 2>/dev/null && find . -type f ! -name 'vk_pipeline_*' | LC_ALL=C sort | while read -r f; do
        printf '%s  cache/%s\n' "$(h256 "$f")" "$f"; done )
    [ -f "$DD/.complete" ] && printf '%s  Game/.complete\n' "$(h256 "$DD/.complete")"
    true
}
ver() { E "$1" --version 2>&1 | sed -n 1,6p | tr '\n' ' '; }
run_dir() { cd "$S/run"; }
drive() { ( run_dir; "$HERE/drive.sh" "$@" ); }

# ── 1 OLD ────────────────────────────────────────────────────────────
say "OLD in place"
put "$OLD"
V_OLD=$(ver "$EXE"); echo "  $V_OLD"
[ "$PLAT" = win ] && DISC="$(cygpath -w "$DISC")"
( run_dir; E "$EXE" --install "$DISC" > "$S/logs/old-install.txt" 2>&1 ); RC=$?
check "OLD --install from the disc" test $RC -eq 0
mkdir -p "$SD"; cp -R "$SAVES/UDATA" "$SAVES/TDATA" "$SD/" 2>/dev/null
printf '[graphics]\nrender_scale = 2\n\n[audio]\ncustom_music_level = "quieter"\nmixer = true\n' > "$SD/settings.toml"
printf '[bus.music]\ngain_db = -3.0\n[master]\nlimiter = "soft"\n' > "$SD/mixer.toml"; cp "$SD/mixer.toml" "$SD/mixer-1.toml"
( run_dir; E "$EXE" --build-shaders > "$S/logs/old-prebuild.txt" 2>&1 ); RC=$?
check "OLD --build-shaders" test $RC -eq 0
drive save "$EXE" "$H" "$S/run/old-save" > "$S/logs/old-save.txt" 2>&1
check "OLD saved Profile 1 itself" grep -aq "SaveMeta" "$S/run/old-save/events.txt"
printf '\n[game]\nspeed_units = "kmh"\n' >> "$SD/settings.toml"
snap > "$S/before.snap"
check "the profile has files to compare" test "$(wc -l < "$S/before.snap")" -gt 6
SHADER_OLD=$( ( run_dir; E "$EXE" --build-shaders --status 2>&1 ) | tr -d '\r' )

# ── 2 UPDATE ─────────────────────────────────────────────────────────
say "UPDATE: NEW replaces OLD"
cp -R "$APP" "$S/old-copy" 2>/dev/null || cp -r "$APP" "$S/old-copy"
replace "$NEW"
V_NEW=$(ver "$EXE"); echo "  $V_NEW"
if [ "$PLAT" = linux ]; then
    V_SC=$(E "$S/shortcut.sh" --version 2>&1 | sed -n 1,6p | tr '\n' ' ')
    check "the stored path (a Steam shortcut) starts the NEW file" test "$V_SC" = "$V_NEW"
fi
[ "$SAME" = 1 ] || check "--version changed" test "$V_OLD" != "$V_NEW"
DS=$( ( run_dir; E "$EXE" --data-status 2>&1 ) | tr -d '\r' )
check "the data is still installed (no disc asked)" sh -c 'echo "$1" | grep -aiq "installed" && ! echo "$1" | grep -aiq "not.installed"' _ "$DS"
SHADER_NEW=$( ( run_dir; E "$EXE" --build-shaders --status 2>&1 ) | tr -d '\r' )
check "--build-shaders --status unchanged" test "$SHADER_OLD" = "$SHADER_NEW"
snap > "$S/after-queries.snap"
check "the profile is the same after the queries" same "$S/before.snap" "$S/after-queries.snap"

# ── 3 NEW boots, a second copy is refused ────────────────────────────
say "NEW: boot, second instance"
PRE=""; [ "$PLAT" = win ] || PRE="env -i HOME='$H' PATH=/usr/bin:/bin:/usr/sbin TMPDIR=/tmp"
export HOLD="(cd '$S/run'; $PRE RECOMP_LOG_DIAG=1 RECOMP_HEADLESS=1 '$EXE' --headless > '$S/logs/second.txt' 2>&1; echo second_status=\$? >> '$S/logs/second.txt')"
drive boot "$EXE" "$H" "$S/run/new-boot" > "$S/logs/new-boot.txt" 2>&1
check "NEW reached the menu and loaded Profile 1" grep -aq "Profile 1" "$S/run/new-boot/events.txt"
check "a second copy was refused (exit 3)" grep -aq "second_status=3" "$S/logs/second.txt"
check "... saying it is already running" grep -aq "already running" "$S/logs/second.txt"
snap > "$S/after-boot.snap"
check "the profile is the same after NEW ran" same "$S/before.snap" "$S/after-boot.snap"
check "settings did not start afresh" test "$(grep -a -c 'started afresh' "$SD/logs/run.log" 2>/dev/null)" = 0
unset HOLD

# ── 4 ROLLBACK ───────────────────────────────────────────────────────
say "ROLLBACK: OLD put back"
rm -rf "$APP"; if [ -d "$S/old-copy" ]; then cp -R "$S/old-copy" "$APP"; else cp "$S/old-copy" "$APP"; fi
[ "$PLAT" = linux ] && chmod +x "$APP"
check "OLD's version again" test "$(ver "$EXE")" = "$V_OLD"
drive boot "$EXE" "$H" "$S/run/old-rollback" > "$S/logs/rollback.txt" 2>&1
check "OLD started (no stale lock) and loaded Profile 1" grep -aq "Profile 1" "$S/run/old-rollback/events.txt"
snap > "$S/after-rollback.snap"
check "the profile is the same after OLD ran again" same "$S/before.snap" "$S/after-rollback.snap"

for f in after-queries after-boot after-rollback; do
    [ -f "$S/$f.snap" ] && ! diff -q "$S/before.snap" "$S/$f.snap" > /dev/null && { echo "--- $f differs:"; diff "$S/before.snap" "$S/$f.snap" | head -8; }
done
if [ "$FAILS" = 0 ]; then echo "RESULT OK update test ($PLAT)"; else echo "RESULT FAIL $FAILS check(s) ($PLAT); logs in $S/logs"; exit 1; fi
