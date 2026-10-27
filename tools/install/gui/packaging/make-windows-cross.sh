#!/bin/sh
# The Windows installer built on a Mac or Linux machine, so no Windows machine is
# loaded: the window is cross-compiled with llvm-mingw against a prebuilt Qt 6 for
# `win64_llvm_mingw` (aqtinstall), the Qt DLLs and the platform plugin go beside the
# exe (what windeployqt copies), the payload and licences as on the other systems,
# and the result is a zip.
#
#   QT_WIN=<Qt>/6.10.3/llvm-mingw_64   QT_HOST=<Qt>/6.10.3/macos   LLVM_MINGW=<llvm-mingw dir> \
#   [XBOXRECOMP_DIR=<toolkit>]  tools/install/gui/packaging/make-windows-cross.sh
#       ->   tools/install/gui/Burnout3_Takedown_Installer-win-x86_64.zip
#
# Getting the pieces into a scratch folder, no system-wide install:
#   python3 -m venv v && v/bin/pip install aqtinstall
#   v/bin/aqt install-qt windows desktop 6.10.3 win64_llvm_mingw -O qt    (the target Qt)
#   v/bin/aqt install-qt mac desktop 6.10.3 clang_64 -O qt                (host tools: moc, rcc; on
#                                                                        Linux: linux desktop ... linux_gcc_64)
#   llvm-mingw: the release the port pins (tools/install/pins.json, 20260922),
#   llvm-mingw-<version>-ucrt-macos-universal.tar.xz (Mac) or -ubuntu-*-x86_64 (Linux)
# The host Qt must be the same version as the target Qt. Qt 6.11's Windows packages were
# not on the server when this was written, hence 6.10.3.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gui=$(cd "$here/.." && pwd)
repo=$(git -C "$gui" rev-parse --show-toplevel)
: "${QT_WIN:?QT_WIN (the llvm-mingw_64 Qt) is required}"
: "${QT_HOST:?QT_HOST (the host Qt of the same version) is required}"
: "${LLVM_MINGW:?LLVM_MINGW is required}"
export LLVM_MINGW
build="$gui/build-win"
pkg="$build/package"

# The icon is drawn by the program itself: build the host copy once to write it.
host="$gui/build-host"
cmake -S "$gui" -B "$host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_HOST" >/dev/null
cmake --build "$host" -j"$(getconf _NPROCESSORS_ONLN)" >/dev/null
hostexe=$(find "$host" -type f \( -name Burnout3Installer -o -name burnout3-installer \) -perm +111 | head -n 1)
mkdir -p "$build"
QT_QPA_PLATFORM=offscreen BO3_INSTALLER_TEST=1 "$hostexe" --write-icon "$build/installer.ico" --icon-size 256

cmake -S "$gui" -B "$build/obj" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$here/windows-toolchain.cmake" \
    -DCMAKE_PREFIX_PATH="$QT_WIN" -DQT_HOST_PATH="$QT_HOST" -DBO3_APP_ICO="$build/installer.ico"
cmake --build "$build/obj" -j"$(getconf _NPROCESSORS_ONLN)"

rm -rf "$pkg"
mkdir -p "$pkg/platforms" "$pkg/styles"
cp "$build/obj/burnout3-installer.exe" "$pkg/"
cp "$build/installer.ico" "$pkg/installer.ico"   # the setup exe's icon (windows-setup.iss)
cp "$QT_WIN/plugins/platforms/qwindows.dll" "$QT_WIN/plugins/platforms/qoffscreen.dll" "$pkg/platforms/"
cp "$QT_WIN/plugins/styles/qmodernwindowsstyle.dll" "$pkg/styles/" 2>/dev/null || true
# Every DLL the exe and the plugins need, from Qt's bin or llvm-mingw's runtime (what
# windeployqt works out): the closure of "DLL Name:" in objdump -p, system DLLs left out.
python3 - "$pkg" "$QT_WIN/bin" "$LLVM_MINGW/x86_64-w64-mingw32/bin" "$LLVM_MINGW/bin/llvm-objdump" <<'PY'
import os, shutil, subprocess, sys
pkg, qtbin, rtbin, objdump = sys.argv[1:5]
def deps(path):
    out = subprocess.run([objdump, "-p", path], capture_output=True, text=True).stdout
    return [l.split(":", 1)[1].strip() for l in out.splitlines() if "DLL Name:" in l]
seen, todo = set(), [os.path.join(pkg, "burnout3-installer.exe")]
for dp, _, fn in os.walk(os.path.join(pkg, "platforms")): todo += [os.path.join(dp, f) for f in fn]
for dp, _, fn in os.walk(os.path.join(pkg, "styles")): todo += [os.path.join(dp, f) for f in fn]
while todo:
    cur = todo.pop()
    for d in deps(cur):
        key = d.lower()
        if key in seen: continue
        seen.add(key)
        for folder in (qtbin, rtbin):
            src = os.path.join(folder, d)
            if os.path.isfile(src):
                shutil.copy2(src, pkg)
                todo.append(os.path.join(pkg, d))
                break
print("deployed:", ", ".join(sorted(f for f in os.listdir(pkg) if f.endswith(".dll"))))
PY

. "$here/payload.sh"
QT_NOTICE_KEEP= assemble_payload "$pkg/payload" "$pkg/licenses"
qtv=$(basename "$(dirname "$QT_WIN")")
sed -i.bak "s/Qt [0-9.]* (https/Qt $qtv (https/" "$pkg/licenses/Qt-NOTICE.txt" && rm -f "$pkg/licenses/Qt-NOTICE.txt.bak"

out="$gui/Burnout3_Takedown_Installer-win-x86_64.zip"
rm -f "$out"
(cd "$pkg" && zip -qr "$out" .)
echo "built: $out"
