#!/usr/bin/env python3
"""scenery_report.py <rundir> [--crops outdir]

Reads what tools/headless/scenery_scene.sh left (ab.tsv, frames/, log.txt)
and prints one line a change of graphics.scenery_detail at flip N:

  #  N  where  draws o/f  indices o/f  o:f  o:o'  changed%

Frame N is drawn at "original", N+4 at "far", N+10 at "original" again
(the setting moves at N and N+6). "draws" and "indices" are the frame's draw
calls and the indices they sent, all render passes together
(RECOMP_TRACE=metal_frame). o:f and o:o' are mean absolute differences of
two frames (0..255, all pixels); "changed%" the share of pixels that differ
by more than 16 between N and N+4. Under the pause menu o:o' is 0 and every
difference in o:f is the setting's.

--crops writes, for each line under the pause menu, the box around the
pixels that differ (grown, at least 160x120), original | far, enlarged
three times, as <outdir>/<k>_<where>.png, and the whole frames as
<outdir>/<k>_full_{o,f}.png.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

OFF = (0, 4, 10)


def load(d, n):
    p = d / "frames" / f"fb_flip_{n:05d}.bmp"
    return Image.open(p).convert("RGB") if p.exists() else None


def counts(log):
    out = {}
    rx = re.compile(r"\[metal\] frame (\d+): \d+ passes \d+ copies(.*)")
    with open(log, errors="replace") as f:
        for line in f:
            m = rx.match(line)
            if not m:
                continue
            dr = ix = 0
            for p in m.group(2).split("|"):
                t = p.split()
                if len(t) >= 6 and t[0].startswith("0x"):
                    dr += int(t[3])
                    ix += int(t[5][1:]) if t[5].startswith("i") else 0
            out[int(m.group(1))] = (dr, ix)
    return out


def arr(im):
    return np.asarray(im, dtype=np.int16)


def main():
    d = Path(sys.argv[1])
    crops = None
    if len(sys.argv) > 3 and sys.argv[2] == "--crops":
        crops = Path(sys.argv[3])
        crops.mkdir(parents=True, exist_ok=True)
    cnt = counts(d / "log.txt")
    rows = [l.split("\t") for l in open(d / "ab.tsv").read().splitlines() if l]
    print("  #      N  where    draws o/f    indices o/f           o:f   o:o'  changed%")
    tot = {}
    for k, (n, where) in enumerate(rows):
        n = int(n)
        fr = [load(d, n + o) for o in OFF]
        c = [cnt.get(n + o) for o in OFF]
        if any(f is None for f in fr) or any(v is None for v in c):
            print(f"{k:3d} {n:6d}  {where:6s} (frames or trace missing)")
            continue
        a, b, a2 = (arr(f) for f in fr)
        diff = np.abs(a - b).max(axis=2)
        ch = float((diff > 16).mean() * 100)
        tot.setdefault(where, []).append((c[0][0], c[1][0], c[0][1], c[1][1]))
        print(f"{k:3d} {n:6d}  {where:6s} {c[0][0]:5d}/{c[1][0]:5d}  "
              f"{c[0][1]:8d}/{c[1][1]:8d}  "
              f"{np.abs(a - b).mean():5.2f}  {np.abs(a - a2).mean():5.2f}  {ch:6.2f}")
        if crops and where != "drive":
            fr[0].save(crops / f"{k}_full_o.png")
            fr[1].save(crops / f"{k}_full_f.png")
            ys, xs = np.nonzero(diff > 16)
            if len(xs):
                x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
                cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
                w = max(160, x1 - x0 + 24)
                h = max(120, y1 - y0 + 24)
                box = (max(0, cx - w // 2), max(0, cy - h // 2),
                       min(a.shape[1], cx + w // 2), min(a.shape[0], cy + h // 2))
                o, f = fr[0].crop(box), fr[1].crop(box)
                o = o.resize((o.width * 3, o.height * 3), Image.NEAREST)
                f = f.resize((f.width * 3, f.height * 3), Image.NEAREST)
                out = Image.new("RGB", (o.width * 2 + 6, o.height), (40, 40, 40))
                out.paste(o, (0, 0))
                out.paste(f, (o.width + 6, 0))
                out.save(crops / f"{k}_{where}.png")
    for where, v in tot.items():
        m = [sum(x[i] for x in v) / len(v) for i in range(4)]
        print(f"{where}: {len(v)} lines, mean draws {m[0]:.0f} / {m[1]:.0f} "
              f"({(m[1] / m[0] - 1) * 100:+.1f} %), indices {m[2]:.0f} / {m[3]:.0f} "
              f"({(m[3] / m[2] - 1) * 100:+.1f} %); largest indices "
              f"{max(x[2] for x in v)} / {max(x[3] for x in v)}")


main()
