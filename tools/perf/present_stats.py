#!/usr/bin/env python3
"""present_stats.py [--from-flip N] [--to-flip N] [--label TEXT] <csv> [<csv> ...]

Host present-to-present intervals of a windowed run: p50 / p95 / p99 / max in
ms and how many presents came more than 20 ms and more than 33 ms after the
one before. Reads either per-present log:

  Metal    RECOMP_TRACE=latency=<file>     rows "P,<flip>,<t_ns>": the present
           of that flip was committed
  Vulkan   RECOMP_TRACE=vk_present=<file>  rows "<id>,present,<t_ns>,<flip>"

The window is by the title's flip numbers (a scene driver's scene.txt names
them: "race begins ... (flip N)"), so the same part of the game is compared
in two runs. A load does not flip, so a window should start after it.
BO-93: a first race with and without the shader pre-build.
"""
import argparse
import csv
import sys


def load(path):
    out = []        # (flip, t_ms), first present of each flip
    seen = set()
    with open(path, newline='') as f:
        for r in csv.reader(f):
            try:
                if len(r) >= 3 and r[0] == 'P':
                    flip, t = int(r[1]), int(r[2]) / 1e6
                elif len(r) >= 4 and r[1] == 'present' and r[3] != '':
                    flip, t = int(r[3]), int(r[2]) / 1e6
                else:
                    continue
            except ValueError:
                continue
            if flip in seen:
                continue
            seen.add(flip)
            out.append((flip, t))
    return out


def pct(v, p):
    v = sorted(v)
    k = (len(v) - 1) * p / 100.0
    i = int(k)
    j = min(i + 1, len(v) - 1)
    return v[i] + (v[j] - v[i]) * (k - i)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from-flip', type=int, default=0)
    ap.add_argument('--to-flip', type=int, default=1 << 62)
    ap.add_argument('--label', default='')
    ap.add_argument('files', nargs='+')
    a = ap.parse_args()
    print(f"{'file':34} {'presents':>8} {'p50':>6} {'p95':>6} {'p99':>6} {'max':>7} {'>20ms':>6} {'>33ms':>6}")
    for path in a.files:
        rows = load(path)
        iv = [t1 - t0 for (f0, t0), (f1, t1) in zip(rows, rows[1:])
              if a.from_flip <= f0 and f1 <= a.to_flip]
        if not iv:
            print(f"{path[-34:]:34} (no presents in the window)")
            continue
        print(f"{(a.label or path)[-34:]:34} {len(iv):8d} {pct(iv, 50):6.1f} {pct(iv, 95):6.1f} "
              f"{pct(iv, 99):6.1f} {max(iv):7.1f} {sum(x > 20 for x in iv):6d} {sum(x > 33 for x in iv):6d}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
