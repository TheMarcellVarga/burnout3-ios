#!/usr/bin/env python3
"""framestats.py - summarise RECOMP_TRACE=frametime CSVs, one run or two side by side.

    RECOMP_TRACE=frametime=runs/x/ft.csv ./bin/burnout3 --headless ...
    tools/perf/framestats.py runs/x/ft.csv                 # one run
    tools/perf/framestats.py before.csv after.csv          # compared
    tools/perf/framestats.py --from-ms 20000 --to-ms 40000 --iv 1 ft.csv

Every column is milliseconds per frame (the toolkit's
src/kernel/kernel_frametime.c says what each one is). Per column: mean, p50,
p95, p99. The guest columns are sampled (500 us by default), so a single
frame's figure is coarse; the means and percentiles over hundreds of frames
are what to read. Groups printed under the table:

  game      g_game              the title's lifted code (.text: game, RenderWare, CRT)
  guest D3D g_d3d               the XDK's D3D8/XGRPH code building the pushbuffer
  guest XDK g_xdk               the XDK's other libraries (DirectSound, XMV, XPP...)
  host NV2A ex_busy             the executor: pushbuffer decode, state, draws, present
  waits     ex_hold, g_spin, g_wait   the vblank hold, guest busy-waits, guest blocked
  host      g_host              host code reached from guest threads (kernel HLE, MMIO traps)
"""
import argparse
import csv
import sys

COLS = ['frame_ms', 'ex_hold', 'ex_busy', 'ex_draw', 'ex_present', 'ex_idle',
        'g_game', 'g_d3d', 'g_xdk', 'g_spin', 'g_host', 'g_wait', 'cpu_proc']


def load(path, a):
    rows = []
    with open(path, newline='') as f:
        for r in csv.DictReader(f):
            try:   # a run killed mid-line leaves a short last row
                t = float(r['t_ms'])
                iv = int(r['iv'])
                for c in COLS:
                    float(r[c])
            except (KeyError, ValueError, TypeError):
                continue
            if t < a.from_ms or (a.to_ms and t > a.to_ms):
                continue
            if a.iv and iv != a.iv:
                continue
            rows.append(r)
    return rows


def pct(v, p):
    if not v:
        return float('nan')
    v = sorted(v)
    return v[min(len(v) - 1, int(p * (len(v) - 1) + 0.5))]


def stats(rows):
    out = {}
    for c in COLS:
        v = [float(r[c]) for r in rows if r.get(c) not in (None, '')]
        out[c] = (sum(v) / len(v) if v else float('nan'), pct(v, .5), pct(v, .95), pct(v, .99))
    n = len(rows)
    out['_n'] = n
    out['_late'] = sum(int(r['late']) for r in rows) / n if n else 0
    ivs = {}
    for r in rows:
        ivs[r['iv']] = ivs.get(r['iv'], 0) + 1
    out['_iv'] = ivs
    span = (float(rows[-1]['t_ms']) - float(rows[0]['t_ms'])) / 1000 if n > 1 else 0
    out['_fps'] = (n - 1) / span if span else float('nan')
    out['_cpu'] = (sum(float(r['cpu_proc']) for r in rows) / (span * 1000) * 100
                   if span else float('nan'))
    return out


def show(names, sts):
    w = 30
    print(f'{"":12s}' + ''.join(f'{n[-w:]:>{w}s}' for n in names))
    print(f'{"frames":12s}' + ''.join(f'{s["_n"]:>{w}d}' for s in sts))
    print(f'{"flips/s":12s}' + ''.join(f'{s["_fps"]:>{w}.2f}' for s in sts))
    print(f'{"process CPU":12s}' + ''.join(f'{s["_cpu"]:>{w - 1}.0f}%' for s in sts))
    print(f'{"late swaps":12s}' + ''.join(f'{s["_late"] * 100:>{w - 1}.1f}%' for s in sts))
    print(f'{"intervals":12s}' + ''.join(
        f'{" ".join(f"{k}:{v}" for k, v in sorted(s["_iv"].items())):>{w}s}' for s in sts))
    print(f'{"ms/frame":12s}' + ''.join(f'{"mean    p50    p95    p99":>{w}s}' for s in sts))
    for c in COLS:
        print(f'{c:12s}' + ''.join(
            f'{"{:6.2f} {:6.2f} {:6.2f} {:6.2f}".format(*s[c]):>{w}s}' for s in sts))
    print('\nby bucket (mean ms/frame):')
    groups = [('game', ['g_game']), ('guest D3D', ['g_d3d']), ('guest XDK', ['g_xdk']),
              ('host NV2A', ['ex_busy']), ('host (guest)', ['g_host']),
              ('wait: vblank', ['ex_hold']), ('wait: spin', ['g_spin']),
              ('wait: blocked', ['g_wait'])]
    for g, cs in groups:
        print(f'{g:14s}' + ''.join(f'{sum(s[c][0] for c in cs):>{w - 2}.2f}' for s in sts))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('csv', nargs='+')
    ap.add_argument('--from-ms', type=float, default=0)
    ap.add_argument('--to-ms', type=float, default=0)
    ap.add_argument('--iv', type=int, default=0, help='only frames whose swap asked this interval')
    a = ap.parse_args()
    sts = []
    for p in a.csv:
        rows = load(p, a)
        if not rows:
            sys.exit(f'{p}: no frames in range')
        sts.append(stats(rows))
    show(a.csv, sts)


if __name__ == '__main__':
    main()
