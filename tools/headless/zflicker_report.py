#!/usr/bin/env python3
"""zflicker_report.py <rundir> [--offset -1] [--min 30] [--dip 0.7]   (BO-204)

Reads a zflicker_scene.sh run: the frame dumps fb_flip_NNNNN.bmp and the
"[TEXREP] zbias ab: on|off from flip N" lines. Counts the magenta (ztint)
pixels of every frame; a frame is a flicker frame when its count is under
--dip times the smaller of its two neighbours' (the other arm, one flip
either side: a car passing or the camera turning moves both alike), that
being at least --min pixels (a decal far away or out of
view counts for neither arm). The dump of executor flip N is fb_flip_(N +
offset) (zprobe_report.py's calibration: -1 on Vulkan).

--consume: count and delete as the run goes (see below). Prints per arm (offsets on / off): frames counted, flicker frames, and the
flicker frames' numbers; writes <rundir>/zflicker.tsv (frame, arm, count,
neighbour median).
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

d = Path(sys.argv[1])
args = sys.argv[2:]


def opt(name, default, conv):
    return conv(args[args.index(name) + 1]) if name in args else default


offset = opt("--offset", -1, int)
mn = opt("--min", 30, int)
dip = opt("--dip", 0.7, float)

on_parity = None
for line in open(d / "log.txt", errors="replace"):
    m = re.search(r"zbias ab: (on|off) from flip (\d+)", line)
    if m:
        on_parity = (int(m[2]) + offset) % 2 if m[1] == "on" else (int(m[2]) + offset + 1) % 2
        break

def magenta(p):
    a = np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = (r > 70) & (b > 70) & (g * 3 < np.minimum(r, b)) & (np.abs(r - b) * 3 < np.maximum(r, b))
    return int(m.sum())


# --consume (while the run goes): count the frames written more than two
# seconds ago into counts.tsv and delete those without magenta (a whole
# drive's dumps would not fit on the disk; the frames with magenta and the
# four after are kept, as .seen).
import time
cf = d / "counts.tsv"
if "--consume" in args:
    recent = [0, 0, 0, 0]
    if cf.exists():
        recent = ([int(x.split()[1]) for x in open(cf).read().split("\n") if x] + recent)[-4:]
    with open(cf, "a") as o:
        for p in sorted(d.glob("fb_flip_*.bmp")):
            if time.time() - p.stat().st_mtime < 2:
                continue
            try:
                c = magenta(p)
            except Exception:
                continue
            o.write(f"{int(p.stem.split('_')[-1])}\t{c}\n")
            # kept: frames with magenta, and the dark ones right after
            p.rename(p.with_suffix(".seen")) if c or max(recent) else p.unlink()
            recent = recent[1:] + [c]
    sys.exit(0)
cnt = {}
if cf.exists():
    for line in open(cf):
        n, c = line.split()
        cnt[int(n)] = int(c)
for p in sorted(d.glob("fb_flip_*.bmp")):
    cnt[int(p.stem.split("_")[-1])] = magenta(p)

res = {0: [0, []], 1: [0, []]}
rows = []
for n, c in sorted(cnt.items()):
    if n - 1 not in cnt or n + 1 not in cnt:
        continue
    med = float(min(cnt[n - 1], cnt[n + 1]))
    if med < mn:
        continue
    arm = n % 2
    res[arm][0] += 1
    if c < dip * med:
        res[arm][1].append(n)
    rows.append(f"{n}\t{'on' if arm == on_parity else 'off'}\t{c}\t{med:.0f}")
(d / "zflicker.tsv").write_text("\n".join(rows) + "\n")
for arm in (0, 1):
    lab = "on " if arm == on_parity else "off"
    tot, fl = res[arm]
    print(f"offsets {lab}: {len(fl)}/{tot} frames with the decal dipping  {fl[:40]}")
