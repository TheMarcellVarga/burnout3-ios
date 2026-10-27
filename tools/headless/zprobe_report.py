#!/usr/bin/env python3
"""zprobe_report.py <rundir> <window flip> [--keep]   (BO-204)

Reads a zprobe_scene.sh window: the "[TEXREP] zprobe flip F #k <hash> <w>x<h>
f<fmt>" lines after "zprobe window from flip <window flip>" in log.txt and the
frame dumps fb_flip_NNNNN.bmp. For each probed texture, the pixels that
differ (any channel > 24) between its flip and both neighbouring (unprobed)
flips: what pushing that texture's draws 512 depth units back hid or showed,
and the same for its flip two on, 4 units back. A decal a few centimetres in
front of a surface loses a patch at 512 and nothing at 4; a pass over the
same geometry (reflections, lightmaps) loses at both; anything else a seam.

Appends to <rundir>/zprobe.tsv: window, k, hash, size, format, changed
pixels, bounding box, fill (pixels / box area: a lost decal is a patch), track,
pixels at 4 units; writes <rundir>/zp/<window>_<k>_<hash>.png (the
unprobed and probed crops and the changed pixels in red, side by side, x3) for those over 20 pixels. Deletes
the window's frames unless --keep.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

d = Path(sys.argv[1])
win = int(sys.argv[2])
keep = "--keep" in sys.argv


def load(n):
    p = d / f"fb_flip_{n:05d}.bmp"
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16) if p.exists() else None


probes = []
on = False
for line in open(d / "log.txt", errors="replace"):
    if "zprobe window from flip" in line:
        on = int(line.split()[-1]) == win
        continue
    if on and "zprobe done" in line:
        break
    m = re.search(r"zprobe flip (\d+) #(\d+) ([0-9a-f]{16}) (\d+x\d+) f([0-9a-f]+)", line)
    if on and m:
        probes.append((int(m[1]), int(m[2]), m[3], m[4], m[5]))
track = (d / "track.txt").read_text().strip() if (d / "track.txt").exists() else "?"


def changed(f, o):
    a, b, c = load(f + o), load(f + o - 1), load(f + o + 1)
    if a is None or b is None or c is None:
        return None, None
    m = (np.abs(a - b).max(axis=2) > 24) & (np.abs(a - c).max(axis=2) > 24)
    return m, (a, b)


# The dump's flip number against the executor's: pick the offset at which
# the probed flips differ most (one calibration per window).
best, bo = -1, 0
for o in (-1, 0, 1, 2):
    s = 0
    for f, *_ in probes[:80]:
        m, _ = changed(f, o)
        if m is not None:
            s += int(m.sum())
    if s > best:
        best, bo = s, o
(d / "zp").mkdir(exist_ok=True)
rows = []
for f, k, h, size, fmt in probes:
    m, ab = changed(f, bo)
    if m is None:
        continue
    px = int(m.sum())
    box, fill = "", 0.0
    if px:
        ys, xs = np.nonzero(m)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        box = f"{x0},{y0},{x1},{y1}"
        fill = px / float((x1 - x0 + 1) * (y1 - y0 + 1))
        if px > 20:
            pad = 12
            X0, Y0 = max(0, x0 - pad), max(0, y0 - pad)
            X1, Y1 = min(m.shape[1], x1 + pad + 1), min(m.shape[0], y1 + pad + 1)
            a, b = ab
            hl = b[Y0:Y1, X0:X1].copy()
            hl[m[Y0:Y1, X0:X1]] = (255, 0, 0)
            crop = np.concatenate([b[Y0:Y1, X0:X1], a[Y0:Y1, X0:X1], hl], axis=1).astype(np.uint8)
            im = Image.fromarray(crop)
            im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
            im.save(d / "zp" / f"{win}_{k:03d}_{h}.png")
    m4, _ = changed(f + 2, bo)
    px4 = int(m4.sum()) if m4 is not None else -1
    rows.append(f"{win}\t{k}\t{h}\t{size}\tf{fmt}\t{px}\t{box}\t{fill:.2f}\t{track}\t{px4}")
with open(d / "zprobe.tsv", "a") as o:
    for r in rows:
        o.write(r + "\n")
print(f"window {win}: {len(probes)} textures, offset {bo}, "
      f"{sum(1 for r in rows if int(r.split(chr(9))[5]) > 20)} over 20 px")
if not keep:
    lo = min((p[0] for p in probes), default=win) - 10
    hi = max((p[0] for p in probes), default=win) + 10
    for p in d.glob("fb_flip_*.bmp"):
        n = int(p.stem.split("_")[-1])
        if lo <= n <= hi + 800:
            p.unlink()
