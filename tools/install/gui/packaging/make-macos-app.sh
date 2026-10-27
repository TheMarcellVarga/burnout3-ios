#!/bin/sh
# Builds the installer and packs it into a macOS app with its Qt frameworks and
# the payload it installs from: a snapshot of this source tree (the driver
# tools/install/install.py, regen.sh, the CMake project - no game data, no
# generated code) and, when XBOXRECOMP_DIR names a git checkout of the toolkit,
# a snapshot of that. Structure after Xerenge's make-macos-app.sh.
#
#   [XBOXRECOMP_DIR=<toolkit checkout>] tools/install/gui/packaging/make-macos-app.sh
#       ->   tools/install/gui/Burnout3_Takedown_Installer-macos-arm64.zip
#
# Needs Qt 6 (brew install qt); the app carries its own copy, so players do not.
# Both snapshots come from `git archive HEAD` of explicit paths (payload.sh):
# commit first, what is not committed is not in the payload.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gui=$(cd "$here/.." && pwd)
repo=$(git -C "$gui" rev-parse --show-toplevel)
build="$gui/build-macos"
qt=${QT_DIR:-$(brew --prefix qt 2>/dev/null || true)}

cmake -S "$gui" -B "$build" -DCMAKE_BUILD_TYPE=Release ${qt:+-DCMAKE_PREFIX_PATH="$qt"}
cmake --build "$build" -j"$(sysctl -n hw.ncpu)"

app="$build/Burnout 3 Takedown Installer.app"
rm -rf "$app"
cp -R "$build/Burnout3Installer.app" "$app"

# The icon, drawn by the installer itself (--write-icon), so no image is stored.
exe="$app/Contents/MacOS/Burnout3Installer"
iconset="$build/installer.iconset"
rm -rf "$iconset"
mkdir -p "$iconset" "$app/Contents/Resources"
icon() {
    QT_QPA_PLATFORM=offscreen "$exe" --write-icon "$iconset/$2" --icon-size "$1"
}
icon 16 icon_16x16.png
icon 32 icon_16x16@2x.png
icon 32 icon_32x32.png
icon 64 icon_32x32@2x.png
icon 128 icon_128x128.png
icon 256 icon_128x128@2x.png
icon 256 icon_256x256.png
icon 512 icon_256x256@2x.png
icon 512 icon_512x512.png
icon 1024 icon_512x512@2x.png
iconutil -c icns "$iconset" -o "$app/Contents/Resources/installer.icns"

# -libpath: Homebrew's Qt image plugins want libwebp and friends, which live in its lib/.
"${qt:+$qt/bin/}macdeployqt" "$app" -libpath="$(brew --prefix)/lib" 2>&1 | grep -v -E "Cannot resolve rpath|using QList|codesign verification|invalid signature" || true
# The installer reads no image formats beyond PNG (built into QtGui); Homebrew's
# image plugins (webp, tiff, ...) need libraries macdeployqt cannot find, so drop them.
rm -rf "$app/Contents/PlugIns/imageformats"
# Nor the virtual keyboard and icon-engine plugins (they pull QtQuick, QtQml, ...).
# What no remaining binary links any more is then taken out of Frameworks, so
# the app carries Qt Core/Gui/Widgets/Concurrent and the libraries they need.
rm -rf "$app/Contents/PlugIns/platforminputcontexts" "$app/Contents/PlugIns/iconengines"
python3 - "$app" <<'PY'
import os, re, shutil, subprocess, sys
app = sys.argv[1]
fw = os.path.join(app, "Contents", "Frameworks")
# Everything in Frameworks that the program and its plugins reach (otool -L,
# transitively) stays; the rest goes.
def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [re.sub(r" \(.*", "", l.strip()) for l in out]
def binaries(root):
    for dp, dn, fn in os.walk(root):
        for n in fn:
            p = os.path.join(dp, n)
            if not os.path.islink(p) and (n.endswith(".dylib") or os.access(p, os.X_OK) or "/Versions/" in p):
                if subprocess.run(["file", p], capture_output=True, text=True).stdout.find("Mach-O") >= 0:
                    yield p
byname = {}
for p in binaries(fw):
    byname[os.path.basename(p)] = p
roots = list(binaries(os.path.join(app, "Contents", "MacOS"))) + list(binaries(os.path.join(app, "Contents", "PlugIns")))
keep, todo = set(), list(roots)
while todo:
    cur = todo.pop()
    for d in deps(cur):
        base = os.path.basename(d)
        tgt = byname.get(base)
        if tgt and tgt not in keep:
            keep.add(tgt)
            todo.append(tgt)
removed = 0
for entry in sorted(os.listdir(fw)):
    full = os.path.join(fw, entry)
    if entry.endswith(".framework"):
        name = entry[:-len(".framework")]
        if not any(k.startswith(full + "/") or os.path.basename(k) == name for k in keep):
            shutil.rmtree(full); removed += 1
    elif entry.endswith(".dylib") and full not in keep:
        os.remove(full); removed += 1
print("pruned %d unused libraries from Frameworks" % removed)
PY

# Where the installer looks for it (LocateDriver): ../Resources/payload from
# Contents/MacOS. burnout3/ holds tools/install/install.py and the source the
# driver regenerates and builds in; xboxrecomp/ is the recompiler toolkit. The
# lists of what goes in are in payload.sh. The licence texts go to
# Resources/licenses (the About tab shows them).
. "$here/payload.sh"
assemble_payload "$app/Contents/Resources/payload" "$app/Contents/Resources/licenses"

# Nothing may still point into Homebrew or /usr/local: on a Mac without them
# the app would not start.
leaks=$(find "$app" -type f -perm +111 -not -path "*/Resources/payload/*" -exec sh -c \
    'otool -L "$1" 2>/dev/null | grep -E "^[[:space:]]+(/opt/homebrew|/usr/local)/" | sed "s|^|$1: |"' \
    _ {} \;)
if [ -n "$leaks" ]; then
    echo "$leaks" >&2
    echo "libraries outside the app are still linked; see above" >&2
    exit 1
fi

# Signed ad hoc: Apple silicon refuses to run unsigned code, and there is no
# developer certificate here. Gatekeeper still asks once (System Settings,
# Privacy & Security, Open Anyway) for a download.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

out="$gui/Burnout3_Takedown_Installer-macos-$(uname -m).zip"
rm -f "$out"
ditto -c -k --keepParent "$app" "$out"
echo "built: $out"

# A disk image of the installer: the app and a link to /Applications to drag it
# onto. No background and no layout script (nothing may open a Finder window
# here); the app carries the installer's own icon, drawn in code.
dmg="$gui/Burnout3_Takedown_Installer-macos-$(uname -m).dmg"
stage="$build/dmg-stage"
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Burnout 3 Takedown Installer.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Burnout 3 Takedown Installer" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
rm -rf "$stage"
echo "built: $dmg"
