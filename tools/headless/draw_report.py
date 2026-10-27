#!/usr/bin/env python3
"""draw_report.py <rundir> [--sheet out.png [n ...]] [--zoom x0,y0,x1,y1]

Reads what tools/headless/draw_scene.sh left (ab.tsv, frames/, log.txt,
drive.txt) and prints one line a change of graphics.vehicle_detail at flip N:

  #  N  where  mph  draws o/f/F  indices o/f/F  o:f  o:F  o:o'  motion

Frame N is drawn at "original", N+4 at "far", N+10 at "farthest", N+16 at
"original" again (the setting moves at N, N+6 and N+12; a change reaches the
picture one or two frames on). "draws" and "indices" are the frame's draw
calls and the indices they sent, all render passes together
(RECOMP_TRACE=metal_frame): counts, so the load of the machine does not move
them. The last columns are mean absolute differences of two frames (0..255,
all pixels): original against far, against farthest, against the original
twelve frames on (what the scene's own movement makes over the same time),
and "motion", consecutive frames at one level.

The summary gives the largest and the mean indices of the three levels and
the frame with the most.

--sheet writes, for the listed lines (default: every grid line), the frames
N, N+4, N+10 one above the other, cut to --zoom (default the whole frame)
and enlarged three times.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

OFF = (0, 4, 10, 16)


def load(d, n):
    p = d / "frames" / f"fb_flip_{n:05d}.bmp"
    if not p.exists():
        return None
    return Image.open(p).convert("RGB")


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


def speeds(path):
    out = {}
    if path.exists():
        for line in open(path, errors="replace"):
            t = line.split()
            if len(t) > 3 and t[0] == "D":
                out[int(t[1])] = float(t[3]) * 2.2369
    return out


def mad(a, b):
    return float(np.abs(np.asarray(a, dtype=np.int16) - np.asarray(b, dtype=np.int16)).mean())


def main():
    d = Path(sys.argv[1])
    args = sys.argv[2:]
    sheet, picks, zoom = None, [], None
    while args:
        a = args.pop(0)
        if a == "--sheet":
            sheet = args.pop(0)
            while args and args[0].isdigit():
                picks.append(int(args.pop(0)))
        elif a == "--zoom":
            zoom = tuple(int(v) for v in args.pop(0).split(","))
    cnt = counts(d / "log.txt")
    spd = speeds(d / "drive.txt")
    rows = [l.split("\t") for l in open(d / "ab.tsv").read().splitlines() if l]
    print("  #      N  where  mph   draws o/f/F      indices o/f/F            o:f    o:F   o:o'  motion")
    tot = [[], [], []]
    worst = (0, 0)
    for k, (n, where) in enumerate(rows):
        n = int(n)
        fr = [load(d, n + o) for o in OFF]
        c = [cnt.get(n + o) for o in OFF]
        if any(f is None for f in fr) or any(v is None for v in c):
            print(f"{k:3d} {n:6d}  {where:5s}  (frames or trace missing)")
            continue
        for i in range(3):
            tot[i].append(c[i][1])
        if c[2][1] > worst[1]:
            worst = (n + 10, c[2][1])
        pre, nxt = load(d, n - 1), load(d, n + 11)
        motion = max(mad(pre, fr[0]) if pre else 0.0, mad(fr[2], nxt) if nxt else 0.0)
        print(f"{k:3d} {n:6d}  {where:5s} {spd.get(n, 0.0):4.0f}  "
              f"{c[0][0]:4d}/{c[1][0]:4d}/{c[2][0]:4d}  "
              f"{c[0][1]:7d}/{c[1][1]:7d}/{c[2][1]:7d}  "
              f"{mad(fr[0], fr[1]):5.2f}  {mad(fr[0], fr[2]):5.2f}  {mad(fr[0], fr[3]):5.2f}  {motion:5.2f}")
    if tot[0]:
        print("indices a frame, original / far / farthest: mean %d / %d / %d, largest %d / %d / %d"
              % (*(sum(t) // len(t) for t in tot), *(max(t) for t in tot)))
        print("most at farthest: flip %d, %d indices" % worst)
    if sheet:
        if not picks:
            picks = [k for k, r in enumerate(rows) if r[1] == "grid"]
        tiles = []
        for k in picks:
            n = int(rows[k][0])
            col = [load(d, n + o) for o in OFF[:3]]
            if any(f is None for f in col):
                continue
            if zoom:
                col = [f.crop(zoom) for f in col]
            col = [f.resize((f.width * 3, f.height * 3), Image.NEAREST) for f in col]
            tiles.append(col)
        if tiles:
            w, h = tiles[0][0].size
            out = Image.new("RGB", (len(tiles) * (w + 4), 3 * (h + 4)), (40, 40, 40))
            for x, col in enumerate(tiles):
                for y, f in enumerate(col):
                    out.paste(f, (x * (w + 4), y * (h + 4)))
            out.save(sheet)
            print("sheet:", sheet, "(columns: lines %s; rows: original, far, farthest)"
                  % " ".join(str(k) for k in picks))


main()
