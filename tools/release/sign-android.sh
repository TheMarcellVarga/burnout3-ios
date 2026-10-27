#!/usr/bin/env bash
# sign-android.sh: sign a release APK with the project's key, on the machine
# that holds the key.
#
#   tools/release/sign-android.sh <unsigned-aligned.apk> <signed.apk>
#
# The key never leaves this machine and is never copied: apksigner reads the
# keystore where it lies and takes the password from the file beside it
# (--ks-pass file:; a PKCS#12 key has the store's password, and apksigner
# tries that one for the key), so neither is on a command line or in a log. What is
# printed is the certificate's SHA-256 fingerprint and nothing else of it.
# The APK comes aligned from tools/android/build-apk.sh (zipalign before
# signing, as the v2 scheme wants).
#
# apksigner is Java (apksigner.jar of the Android SDK's build-tools, Apache
# 2.0). It needs a Java runtime, 11 or newer; a JRE unpacked into a folder is
# enough, nothing is installed system-wide.
#
#   TAKEDAWN_SIGN_DIR       the key's folder (default ~/.takedawn-signing):
#                           takedawn-release.p12, password.txt, alias takedawn
#   TAKEDAWN_JAVA           the java program (default: $TAKEDAWN_DEPS/jre/.../bin/java, else java)
#   TAKEDAWN_APKSIGNER_JAR  apksigner.jar (default $TAKEDAWN_DEPS/android/apksigner.jar)
set -euo pipefail
[ $# = 2 ] || { echo "usage: sign-android.sh <unsigned.apk> <signed.apk>" >&2; exit 1; }
IN="$1"; OUT="$2"
DEPS="${TAKEDAWN_DEPS:-$HOME/.cache/takedawn-deps}"
KD="${TAKEDAWN_SIGN_DIR:-$HOME/.takedawn-signing}"
KS="$KD/takedawn-release.p12"; PW="$KD/password.txt"
[ -f "$KS" ] && [ -f "$PW" ] || { echo "!! no key in $KD (takedawn-release.p12, password.txt)" >&2; exit 1; }
case "$(cd "$(dirname "$OUT")" && pwd)/" in "$(cd "$KD" && pwd)/"*) echo "!! not into the key's folder" >&2; exit 1 ;; esac
JAR="${TAKEDAWN_APKSIGNER_JAR:-$DEPS/android/apksigner.jar}"
[ -f "$JAR" ] || { echo "!! no apksigner.jar at $JAR: copy build-tools/<version>/lib/apksigner.jar from an Android SDK" >&2; exit 1; }
JAVA="${TAKEDAWN_JAVA:-}"
if [ -z "$JAVA" ]; then
    JAVA="$(ls -d "$DEPS"/jre/*/Contents/Home/bin/java "$DEPS"/jre/*/bin/java 2>/dev/null | head -1 || true)"
    [ -n "$JAVA" ] || JAVA=java
fi
"$JAVA" -version >/dev/null 2>&1 || { echo "!! no Java runtime ($JAVA): unpack a JRE under $DEPS/jre or set TAKEDAWN_JAVA" >&2; exit 1; }
rm -f "$OUT" "$OUT.idsig"
"$JAVA" -jar "$JAR" sign --ks "$KS" --ks-type PKCS12 --ks-key-alias takedawn \
    --ks-pass "file:$PW" \
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true \
    --out "$OUT" "$IN"
rm -f "$OUT.idsig"
certs="$("$JAVA" -jar "$JAR" verify --print-certs "$OUT")" || { echo "!! apksigner verify failed" >&2; exit 1; }
fp="$(printf '%s\n' "$certs" | sed -n 's/^.*[Ss]igner[^:]*: certificate SHA-256 digest: //p' | head -1)"
[ -n "$fp" ] || { echo "!! no signer in the verified APK" >&2; exit 1; }
if [ -f "$KD/cert.pem" ] && command -v openssl >/dev/null 2>&1; then
    want="$(openssl x509 -in "$KD/cert.pem" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')"
    [ "$want" = "$fp" ] || { echo "!! signed with a certificate ($fp) that is not the project's ($want)" >&2; exit 1; }
fi
echo "==> signed: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$OUT" | cut -d' ' -f1))"
echo "==> certificate SHA-256: $fp"
