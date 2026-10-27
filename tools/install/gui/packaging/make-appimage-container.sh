#!/bin/sh
# The Linux installer package without Qt on the build machine: a container does it.
#
#   stage (anywhere with git; the Mac):
#     tools/install/gui/packaging/make-appimage-container.sh stage <dir>
#   build (anywhere with podman or docker and an x86_64 image; the Steam Deck):
#     tools/install/gui/packaging/make-appimage-container.sh build <dir> [podman options]
#     -> <dir>/out/Burnout3_Takedown_Installer-x86_64.AppImage
#
# `stage` puts the sources of the window, the payload (payload.sh: explicit lists, no
# game data) and the licence texts in <dir>; `build` runs inside-container.sh in an
# ubuntu:24.04 container with <dir> mounted (it installs Qt 6 there and downloads
# linuxdeploy; nothing is installed on the host). Options after <dir> go to podman, e.g.
# `--root DIR --runroot DIR` for an image store on an SD card.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gui=$(cd "$here/.." && pwd)
case "$1" in
stage)
    out=${2:?stage needs a folder}
    repo=$(git -C "$gui" rev-parse --show-toplevel)
    . "$here/payload.sh"
    rm -rf "$out"
    mkdir -p "$out/gui"
    # the window's sources, from the commit: no build folders, no packages
    git -C "$repo" archive HEAD tools/install/gui | tar -x -C "$out" --strip-components=3 -s ',^,gui/,' 2>/dev/null \
        || { git -C "$repo" archive HEAD tools/install/gui | tar -x -C "$out/gui" --strip-components=3; }
    QT_NOTICE_KEEP=1 assemble_payload "$out/payload" "$out/licenses"
    echo "staged in $out"
    ;;
build)
    dir=${2:?build needs the staged folder}
    shift 2
    runtime=podman
    command -v podman >/dev/null 2>&1 || runtime=docker
    mkdir -p "$dir/out"
    "$runtime" "$@" run --rm -v "$dir":/work -e JOBS="${JOBS:-4}" docker.io/library/ubuntu:24.04 \
        sh /work/gui/packaging/inside-container.sh
    echo "built: $dir/out/Burnout3_Takedown_Installer-x86_64.AppImage"
    ;;
*)
    echo "usage: $0 stage <dir> | build <dir> [podman options]" >&2
    exit 2
    ;;
esac
