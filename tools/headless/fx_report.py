#!/usr/bin/env python3
"""fx_report.py <rundir> [--sheet out.png [n ...]]

Reads what tools/headless/fx_scene.sh left (ab.tsv, frames/, log.txt) and
prints one line a change of graphics.bloom / graphics.motion_blur at flip N:

  #  switch  N  where  passes  on:off  off:on  on:on'  motion  re-entry  [pixels]

Frame N has the effect, N+3 is without it, N+9 has it again (the switch
goes off at N and on at N+6; a change reaches the picture one or two
frames on). The numbers are mean absolute differences of two frames
(0..255, all pixels): "on:off" N against N+3, "off:on" N+3 against N+9,
"on:on'" N against N+9 (the picture came back), "motion" consecutive
frames in one state (N-1 against N, and N+3 against N+4: the larger), what
the scene's own movement makes. Where the picture stands still on:off is
the effect alone and on:on' is 0; for those lines the share of pixels that
differ at all between N and N+3 is printed too. "re-entry" is the first
frame with the effect again against the next one, less the pair after it:
near 0 unless the effect starts with something left over from before.
"edge" is the pair of frames the effect goes off between, less the median
of the other consecutive pairs: the change alone where the scene moves
little.
"passes" are the render passes with > without (RECOMP_TRACE=metal_frame).

--sheet writes the frames N, N+3 and their difference (x4) side by side
for the listed lines (default: the still scenes).
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load(d, n):
    p = d / "frames" / f"fb_flip_{n:05d}.bmp"
    if not p.exists():
        return None
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def passes(log):
    out = {}
    rx = re.compile(r"\[metal\] frame (\d+): (\d+) passes (\d+) copies(.*)")
    with open(log, errors="replace") as f:
        for line in f:
            m = rx.match(line)
            if m:
                sizes = [p.split()[1] for p in m.group(4).split("|")
                         if p.strip() and not p.strip().startswith("copy")]
                big = [s for s in sizes if s not in ("128x128", "64x32")]
                out[int(m.group(1))] = (int(m.group(2)), " ".join(
                    s.replace("640x480", "F").replace("320x240", "h")
                     .replace("160x120", "q") for s in big))
    return out


def d(a, b):
    return float(np.abs(a - b).mean())


def main():
    rd = Path(sys.argv[1])
    ps = passes(rd / "log.txt")
    rows = []
    for line in (rd / "ab.tsv").read_text().splitlines():
        what, n, tag = (line.split("\t") + [""])[:3]
        n = int(n)
        fr = {k: load(rd, n + k) for k in range(-2, 11)}
        if any(f is None for f in fr.values()):
            print(f"    {what} {n} {tag}: frames missing")
            continue
        on, off, on2 = fr[0], fr[3], fr[9]
        motion = max(d(fr[-1], on), d(off, fr[4]))
        differ = float((np.abs(on - off).max(axis=2) > 0).mean() * 100.0)
        # The first frame with the effect again (by its passes), against the
        # one after it, over the next pair: a frame-old leftover drawn as the
        # effect starts would stand out here.
        k = 7 if ps.get(n + 7, (0, ""))[0] == ps.get(n, (0, ""))[0] else 8
        entry = d(fr[k], fr[k + 1]) - d(fr[k + 1], fr[k + 2])
        # The pair of frames the effect goes off between (by the passes),
        # less the median of the other consecutive pairs: the change itself
        # with one frame of the scene's movement taken off.
        k = 0 if ps.get(n + 1, (0, ""))[0] != ps.get(n, (0, ""))[0] else 1
        steps = sorted(d(fr[j], fr[j + 1]) for j in range(-2, 10) if j != k)
        edge = d(fr[k], fr[k + 1]) - steps[len(steps) // 2]
        rows.append((what, n, tag, ps.get(n, (0, "")), ps.get(n + 3, (0, "")),
                     d(on, off), d(off, on2), d(on, on2), motion, differ, entry, edge))
    print("  # switch      N where     passes   on:off  off:on  on:on' motion"
          " re-entry    edge  pixels changed")
    for i, r in enumerate(rows):
        still = r[8] < 0.05
        print(f"{i:3d} {r[0]:6s} {r[1]:6d} {r[2]:9s} {r[3][0]:2d}>{r[4][0]:2d}"
              f"  {r[5]:7.3f} {r[6]:7.3f} {r[7]:7.3f} {r[8]:6.3f} {r[10]:+7.3f} {r[11]:+7.3f}"
              + (f"  {r[9]:5.1f}%" if still else ""))
    kinds = {}
    for r in rows:
        kinds.setdefault((r[0], r[3][1], r[4][1]), []).append(r)
    print("\npasses with > without (F 640x480, h 320x240, q 160x120):")
    for (what, a, b), rs in sorted(kinds.items()):
        print(f"  {what:6s} {len(rs):3d}x  {a}  >  {b}")
    if "--sheet" in sys.argv:
        i = sys.argv.index("--sheet")
        out = sys.argv[i + 1]
        pick = [int(x) for x in sys.argv[i + 2:]]
        if not pick:
            pick = [k for k, r in enumerate(rows) if r[8] < 0.05]
        tiles = []
        for k in pick:
            n = rows[k][1]
            a, b = load(rd, n), load(rd, n + 3)
            df = np.clip(np.abs(a - b) * 4, 0, 255)
            tiles.append(np.concatenate([a, b, df], axis=1))
        if tiles:
            Image.fromarray(np.concatenate(tiles, axis=0).astype(np.uint8)).save(out)
            print(f"\n{out}: lines {pick} (with | without | difference x4)")


if __name__ == "__main__":
    main()
