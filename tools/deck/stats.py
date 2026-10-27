#!/usr/bin/env python3
"""stats.py <log.txt> [seconds=30]: frame pacing over the last <seconds> of a
RECOMP_TRACE=pacing=all log ([PACING] flip N t_us T, and the
"[PACING] swap interval A -> B at flip N" changes).

Prints flips/s and the flip-interval p50/p95/p99/max over all flips, then the
same for the flips the title asked at interval 1 (60 Hz) only, with how many
of those missed their vblank (> 20 ms) -- the title's own 30 Hz phases
(interval 2: crash cams, replays) are not misses. From BO-18 (2026-10-10)."""
import re, sys

log = sys.argv[1]
last = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
flips, iv_at = [], []          # (flip, t_us); (flip, new interval)
for line in open(log, "rb"):
    m = re.search(rb"\[PACING\] flip (\d+) t_us (\d+)", line)
    if m:
        flips.append((int(m.group(1)), int(m.group(2))))
        continue
    m = re.search(rb"\[PACING\] swap interval (\d+) -> (\d+) at flip (\d+)", line)
    if m:
        iv_at.append((int(m.group(3)), int(m.group(2))))
if len(flips) < 10:
    print("no per-flip lines (RECOMP_TRACE=pacing=all)")
    sys.exit(0)

def interval_of(f):
    cur = 1
    for at, v in iv_at:
        if at <= f:
            cur = v
    return cur

end = flips[-1][1]
win = [x for x in flips if x[1] >= end - last * 1e6]
span = (win[-1][1] - win[0][1]) / 1e6
pairs = [((b - a) / 1000.0, interval_of(fb)) for (fa, a), (fb, b) in zip(win, win[1:])]

def line(name, xs):
    xs = sorted(xs)
    n = len(xs)
    if not n:
        return f"{name}: none"
    p = lambda q: xs[min(n - 1, int(q * n))]
    return (f"{name}: {n} flips, p50 {p(.5):.2f} p95 {p(.95):.2f} p99 {p(.99):.2f} "
            f"max {xs[-1]:.1f} ms; >20 ms {sum(x > 20 for x in xs)} "
            f"({100.0 * sum(x > 20 for x in xs) / n:.1f}%), >50 ms {sum(x > 50 for x in xs)}")

print(f"last {span:.1f} s: {len(pairs)} flips, {len(pairs) / span:.1f} flips/s; "
      f"interval-2 flips {sum(1 for _, v in pairs if v == 2)}")
print(line("  all       ", [d for d, _ in pairs]))
print(line("  interval 1", [d for d, v in pairs if v == 1]))

# Host presents ([PACING] present N t_us T, toolkit bo3/perf): what the swap
# chain was handed, in the same window. A present that repeats or skips a
# guest frame shows as a short/long pair; >18.5 ms counts as a miss at 60 Hz.
pres = []
for line_b in open(log, "rb"):
    m = re.search(rb"\[PACING\] present (\d+) t_us (\d+)", line_b)
    if m:
        pres.append(int(m.group(2)))
pres = [t for t in pres if t >= end - last * 1e6]
if len(pres) > 10:
    pd = sorted((b - a) / 1000.0 for a, b in zip(pres, pres[1:]))
    n = len(pd)
    q = lambda f: pd[min(n - 1, int(f * n))]
    print(f"  host present: {n} intervals, p50 {q(.5):.2f} p95 {q(.95):.2f} "
          f"p99 {q(.99):.2f} max {pd[-1]:.1f} ms; >18.5 ms {sum(x > 18.5 for x in pd)} "
          f"({100.0 * sum(x > 18.5 for x in pd) / n:.1f}%), <15 ms {sum(x < 15 for x in pd)}")
