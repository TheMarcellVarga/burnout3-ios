#!/usr/bin/env python3
"""pcache_stats.py <csv> [<csv> ...] [--from S] [--to S]

Reads the per-flip CSV of RECOMP_TRACE=pcache=<file> (Metal backend:
flip, t_ms since process start, interval_ms since the previous flip,
ack-thread compiles in that interval and their ms) and prints, per file:
ack-thread compiles in the first 10 s of the process and in the window,
flips in the window, frame-time p50/p99/max, and how many flips took
more than 33 ms and 100 ms.

The window defaults to the first 30 s after the first flip (--from/--to
are seconds after the first flip). BO-58 (pipeline cache), 2026-10-10.
"""
import csv
import sys


def pct(v, p):
    if not v:
        return 0.0
    v = sorted(v)
    k = (len(v) - 1) * p / 100.0
    i = int(k)
    j = min(i + 1, len(v) - 1)
    return v[i] + (v[j] - v[i]) * (k - i)


def main(argv):
    lo, hi, files, i = 0.0, 30.0, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--from':
            lo = float(argv[i + 1]); i += 2
        elif a == '--to':
            hi = float(argv[i + 1]); i += 2
        else:
            files.append(a); i += 1
    if not files:
        print(__doc__)
        return 2
    print(f"{'file':40} {'c<10s':>6} {'c_win':>6} {'c_ms':>8} {'flips':>6} "
          f"{'p50':>6} {'p99':>7} {'max':>7} {'>33':>4} {'>100':>5}")
    for f in files:
        rows = list(csv.DictReader(open(f)))
        if not rows:
            print(f"{f:40} (empty)")
            continue
        t0 = float(rows[0]['t_ms'])
        c10 = sum(int(r['ack_compiles']) for r in rows if float(r['t_ms']) < 10000.0)
        win = [r for r in rows[1:]
               if lo * 1000 <= float(r['t_ms']) - t0 < hi * 1000]
        iv = [float(r['interval_ms']) for r in win]
        cw = sum(int(r['ack_compiles']) for r in win)
        cms = sum(float(r['ack_compile_ms']) for r in win)
        print(f"{f[-40:]:40} {c10:6d} {cw:6d} {cms:8.1f} {len(iv):6d} "
              f"{pct(iv, 50):6.1f} {pct(iv, 99):7.1f} {max(iv or [0]):7.1f} "
              f"{sum(x > 33.0 for x in iv):4d} {sum(x > 100.0 for x in iv):5d}")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
