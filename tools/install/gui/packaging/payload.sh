#!/bin/sh
# Shared by make-macos-app.sh and make-appimage.sh (and what make-windows.ps1 does
# in PowerShell): puts together what the installer carries to the player's
# machine, from an EXPLICIT list. Nothing else of the repositories goes in: no
# docs/ (it tracks screenshots of the game), no backlog/, runs/, tests/, no
# installer sources, and nothing from the game.
#
#   assemble_payload <payload dir> <licences dir>      needs $repo, $gui; $XBOXRECOMP_DIR optional

BURNOUT_INCLUDE="LICENSE README.md CMakeLists.txt cmake config regen.sh src tools/install tools/win"
BURNOUT_EXCLUDE="tools/install/gui tools/install/tests"
TOOLKIT_INCLUDE="LICENSE LICENSES NOTICE README.md CMakeLists.txt cmake include src templates tests third_party tools/__init__.py tools/xbe_parser tools/disasm tools/func_id tools/abi_analysis tools/recomp"

assemble_payload() {
    dest=$1
    lic=$2
    mkdir -p "$dest/burnout3" "$lic"
    # shellcheck disable=SC2086
    git -C "$repo" archive HEAD $BURNOUT_INCLUDE | tar -x -C "$dest/burnout3" \
        --exclude 'tools/install/gui' --exclude 'tools/install/tests'
    git -C "$repo" rev-parse HEAD > "$dest/STAMP"
    cp "$repo/LICENSE" "$lic/burnout3-LICENSE.txt"
    if [ -n "${XBOXRECOMP_DIR:-}" ]; then
        mkdir -p "$dest/xboxrecomp"
        # shellcheck disable=SC2086
        git -C "$XBOXRECOMP_DIR" archive "${TOOLKIT_REF:-HEAD}" $TOOLKIT_INCLUDE | tar -x -C "$dest/xboxrecomp"
        git -C "$XBOXRECOMP_DIR" rev-parse "${TOOLKIT_REF:-HEAD}" >> "$dest/STAMP"
        cp "$XBOXRECOMP_DIR/LICENSE" "$lic/xboxrecomp-LICENSE.txt"
        cp "$XBOXRECOMP_DIR/NOTICE" "$lic/xboxrecomp-NOTICE.txt"
        cp "$XBOXRECOMP_DIR/LICENSES/LGPL-2.1.txt" "$lic/xboxrecomp-LGPL-2.1.txt"
    else
        echo "note: XBOXRECOMP_DIR not set, the toolkit is not in the package (the player names it under Advanced)" >&2
    fi
    qtv=$( (qmake6 -query QT_VERSION || qmake -query QT_VERSION) 2>/dev/null | head -n 1)
    for f in Qt-LGPL-3.0.txt Qt-GPL-3.0.txt Qt-THIRD-PARTY.txt README.txt; do cp "$gui/licenses/$f" "$lic/"; done
    # QT_NOTICE_KEEP=1 leaves the placeholder for the build that really links Qt (the container)
    if [ -n "${QT_NOTICE_KEEP:-}" ]; then cp "$gui/licenses/Qt-NOTICE.txt" "$lic/Qt-NOTICE.txt"
    else sed "s/@QT_VERSION@/${qtv:-6}/" "$gui/licenses/Qt-NOTICE.txt" > "$lic/Qt-NOTICE.txt"; fi
    check_payload "$dest"
}

# No image, video, audio, font or data file from anywhere: by name and by size.
check_payload() {
    bad=$(find "$1" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.bmp' \
        -o -iname '*.tga' -o -iname '*.dds' -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.bik' -o -iname '*.xmv' \
        -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.mp3' -o -iname '*.ttf' -o -iname '*.otf' -o -iname '*.xbe' \
        -o -iname '*.iso' -o -iname '*.xiso' -o -iname '*.bin' -o -iname '*.dat' -o -iname '*.img' -o -iname '*.zip' \) )
    if [ -n "$bad" ]; then
        echo "the payload holds media or game-like files:" >&2
        echo "$bad" >&2
        return 1
    fi
    echo "payload files over 100 KB (all must be source or text):" >&2
    find "$1" -type f -size +100k -exec ls -l {} \; | awk '{print "  " $5 "  " $9}' >&2
}
