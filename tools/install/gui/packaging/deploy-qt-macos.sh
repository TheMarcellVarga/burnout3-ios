#!/bin/sh
# The setup window and its Qt into an app's Contents folder: MacOS/takedawn-setup,
# Frameworks (QtCore, QtGui, QtWidgets, QtDBus), PlugIns (platforms, styles) and
# Resources/qt.conf. Used by make-macos-bundle.sh (a development bundle) and by
# tools/release/build-macos.sh (the release), so there is one way of doing it.
#
#   packaging/deploy-qt-macos.sh <takedawn-setup binary> <Qt kit> <app>/Contents <arch>
#
# macdeployqt resolves Qt through the bundle's main executable, which in Takedawn.app
# is the game and knows no Qt, so the window is deployed in a staging bundle of its
# own, where it is the main executable, and the result is moved over. Qt's own macOS
# builds are universal; only <arch> stays. Fails when the Qt that lands in the bundle
# is not the one the window was linked with, or when anything of the window still
# names a library outside the app and the system. Signs nothing.
set -e
setup=${1:?usage: deploy-qt-macos.sh <takedawn-setup> <Qt kit> <Contents dir> <arch>}
qt=${2:?}; contents=${3:?}; arch=${4:?}
[ -x "$qt/bin/macdeployqt" ] || { echo "no macdeployqt in $qt/bin" >&2; exit 1; }
tmp=$(mktemp -d)
stage="$tmp/takedawn-setup.app"
mkdir -p "$stage/Contents/MacOS" "$contents/MacOS" "$contents/Resources"
cp "$setup" "$stage/Contents/MacOS/takedawn-setup"
"$qt/bin/macdeployqt" "$stage" -no-strip 2>&1 \
    | grep -v -E "Cannot resolve rpath|using QList|codesign verification|invalid signature|^$" || true
# Only what a Widgets program with PNG icons needs stays.
rm -rf "$stage/Contents/PlugIns/imageformats" "$stage/Contents/PlugIns/iconengines" \
       "$stage/Contents/PlugIns/platforminputcontexts" "$stage/Contents/PlugIns/networkinformation" \
       "$stage/Contents/PlugIns/tls" "$stage/Contents/PlugIns/generic"
for unused in QtSvg QtNetwork QtPdf QtOpenGL QtQml QtQuick QtVirtualKeyboard; do
    rm -rf "$stage/Contents/Frameworks/$unused.framework"
done
cp "$stage/Contents/MacOS/takedawn-setup" "$contents/MacOS/takedawn-setup"
ditto "$stage/Contents/Frameworks" "$contents/Frameworks"
ditto "$stage/Contents/PlugIns" "$contents/PlugIns"
cp "$stage/Contents/Resources/qt.conf" "$contents/Resources/qt.conf"
rm -rf "$tmp"

find "$contents/Frameworks" "$contents/PlugIns" "$contents/MacOS/takedawn-setup" -type f | while read -r f; do
    if lipo -archs "$f" 2>/dev/null | grep -q " " && lipo -archs "$f" | grep -qw "$arch"; then
        lipo -thin "$arch" "$f" -output "$f.thin" && mv "$f.thin" "$f"
    fi
done

linked=$(otool -L "$contents/MacOS/takedawn-setup" | sed -n 's|.*QtCore .*current version \([0-9.]*\)).*|\1|p')
shipped=$(otool -L "$contents/Frameworks/QtCore.framework/Versions/A/QtCore" | sed -n '2s|.*current version \([0-9.]*\)).*|\1|p')
if [ "$linked" != "$shipped" ]; then
    echo "the window was linked with Qt $linked but the bundle holds Qt $shipped (Qt kit $qt)" >&2
    exit 1
fi
leaks=$(for f in "$contents/MacOS/takedawn-setup" $(find "$contents/PlugIns" "$contents/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) 2>/dev/null); do
    otool -L "$f" 2>/dev/null | grep -E "^[[:space:]]+(/opt/homebrew|/usr/local|/private/tmp|/Users)/" | sed "s|^|$f: |"
done)
if [ -n "$leaks" ]; then
    echo "$leaks" >&2
    echo "the setup window still links libraries outside the app" >&2
    exit 1
fi
echo "Qt $shipped ($arch) deployed"
