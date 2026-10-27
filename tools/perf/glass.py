#!/usr/bin/env python3
"""glass.py <glass.csv> [--from FLIP] [--to FLIP] [--pace FILE] [--label TEXT] [--row]

What reached the glass, from a RECOMP_TRACE=glass=<file> run (BO-115): one
line per presented frame with its emulated vblank, the time the present was
aimed at, and the time the system says it was on the glass.

Prints, for the flips asked for (default all):

  frames         presented / shown / never shown / skipped by the presenter
  on-glass interval histogram in display refreshes (a variable display:
                 in ms bins), and the share that is not the title's own
                 spacing ("uneven": the judder a flat flip graph hides)
  vblank->glass  how long after its emulated vblank a frame was shown
  vblank interval  the title's flip pacing (the acceptance targets are
                 p95 <= 17.5 and p99 <= 18.5 ms)

--row prints one markdown table row instead (for the before/after tables).
"""
import argparse
import collections
import csv
import sys

FRAME_MS = 1000.0 / 60.0


def pct(v, p):
    v = sorted(v)
    if not v:
        return float("nan")
    return v[min(len(v) - 1, int(round(p / 100.0 * (len(v) - 1))))]


def analyse(path, lo=0, hi=1 << 62, only=None):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            try:
                fl = int(r["flip"])
            except (ValueError, KeyError, TypeError):
                continue
            # A run that was killed leaves its last line cut short.
            if any(v is None for v in r.values()):
                continue
            if lo <= fl <= hi and (only is None or fl in only):
                rows.append(r)
    if not rows:
        return None
    hz = float(rows[-1]["refresh_hz"] or 0)
    vrr = int(rows[-1]["vrr"] or 0)
    fixed = hz > 0 and not vrr
    refresh_ms = 1000.0 / hz if hz > 0 else FRAME_MS
    tol = refresh_ms / 4 if fixed else 1.5
    shown = [r for r in rows if int(r["glass_ns"] or 0) > 0]
    skipped = sum(int(r["skipped"]) for r in rows)
    out = {"frames": len(rows), "shown": len(shown), "skipped": skipped,
           "never": len(rows) - len(shown) - skipped, "hz": hz, "vrr": vrr,
           "strategy": collections.Counter(r["strategy"] for r in rows).most_common(1)[0][0],
           "depth": rows[-1]["depth"]}
    lat = [(int(r["glass_ns"] or 0) - int(r["vblank_ns"] or 0)) / 1e6 for r in shown if int(r["vblank_ns"] or 0)]
    out["lat"] = lat
    hist = collections.Counter()
    ivs, uneven, gaps = [], 0, 0
    prev = None
    gap = 0
    for r in rows:
        g = int(r["glass_ns"] or 0)
        if not g:
            if prev is not None:
                gap += 1
            continue
        if prev is not None and g > int(prev["glass_ns"]):
            iv = (g - int(prev["glass_ns"])) / 1e6
            want = (int(r["vblank_ns"] or 0) - int(prev["vblank_ns"])) / 1e6
            if want <= 0:
                want = FRAME_MS * (int(r["flip"]) - int(prev["flip"]))
            ivs.append(iv)
            bad = abs(iv - want) > tol
            uneven += max(1 if bad else 0, gap)
            gaps += gap
            hist[round(iv / refresh_ms) if fixed else round(iv)] += 1
        prev = r
        gap = 0
    out.update(ivs=ivs, uneven=uneven, hist=hist, fixed=fixed, refresh_ms=refresh_ms)
    vb = sorted(set(int(r["vblank_ns"] or 0) for r in rows if int(r["vblank_ns"] or 0)))
    out["vv"] = [(b - a) / 1e6 for a, b in zip(vb, vb[1:])]
    lates = sum(int(r["late"]) for r in rows)
    out["late"] = lates
    tg = [(int(r["glass_ns"] or 0) - int(r["target_ns"])) / 1e6 for r in shown if int(r["target_ns"])]
    out["tg"] = tg
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--from", dest="lo", type=int, default=0)
    ap.add_argument("--to", dest="hi", type=int, default=1 << 62)
    ap.add_argument("--label", default="")
    ap.add_argument("--row", action="store_true")
    ap.add_argument("--pace", default=None,
                    help="a BO3_PACE_LOG file: only the flips of a race (the title's state 5)")
    a = ap.parse_args()
    only = None
    if a.pace:
        only = set()
        with open(a.pace, errors="replace") as f:
            for line in f:
                p = line.split()
                if len(p) > 30 and p[0] == "P":
                    d = dict(zip(p[0::2], p[1::2]))
                    if d.get("st") == "5":
                        only.add(int(d["P"]))
    o = analyse(a.csv, a.lo, a.hi, only)
    if not o:
        sys.exit("no frames in that range")
    n = len(o["ivs"])
    unit = "refreshes" if o["fixed"] else "ms"
    hist = " ".join(f"{k}:{v}" for k, v in sorted(o["hist"].items()))
    un = 100.0 * o["uneven"] / n if n else float("nan")
    if a.row:
        print(f"| {a.label} | {o['shown']}/{o['frames']} | {hist} | {o['uneven']} ({un:.1f}%) |"
              f" {pct(o['lat'], 50):.1f} / {pct(o['lat'], 95):.1f} |"
              f" {pct(o['vv'], 50):.2f} / {pct(o['vv'], 95):.2f} / {pct(o['vv'], 99):.2f} | {o['skipped']} |")
        return
    names = {"0": "legacy", "1": "lock", "2": "timed", "3": "timed (not a multiple of 60)"}
    print(f"{a.label + ': ' if a.label else ''}display {o['hz']:.2f} Hz"
          f" {'variable' if o['vrr'] else 'fixed'}, strategy {names.get(o['strategy'], o['strategy'])}"
          f" (depth {o['depth']})")
    print(f"frames {o['frames']}: shown {o['shown']}, never shown {o['never']},"
          f" skipped by the presenter {o['skipped']}, picked up late {o['late']}")
    if not n:
        print("on-glass times: not available (the window was not visible?)")
        return
    print(f"on-glass interval in {unit}: {hist}")
    print(f"uneven (not the title's own spacing, or a frame never shown between): {o['uneven']} of {n} ({un:.2f}%)")
    print(f"on-glass interval ms: p5 {pct(o['ivs'], 5):.2f} p50 {pct(o['ivs'], 50):.2f}"
          f" p95 {pct(o['ivs'], 95):.2f} max {max(o['ivs']):.2f}")
    print(f"vblank->glass ms: p5 {pct(o['lat'], 5):.2f} p50 {pct(o['lat'], 50):.2f}"
          f" p95 {pct(o['lat'], 95):.2f} max {max(o['lat']):.2f}"
          f"  ({pct(o['lat'], 50) / FRAME_MS:.2f} frames at p50)")
    if o["tg"]:
        print(f"glass - target ms: p5 {pct(o['tg'], 5):.2f} p50 {pct(o['tg'], 50):.2f}"
              f" p95 {pct(o['tg'], 95):.2f} max {max(o['tg']):.2f}")
    if o["vv"]:
        print(f"vblank (flip) interval ms: p50 {pct(o['vv'], 50):.2f} p95 {pct(o['vv'], 95):.2f}"
              f" p99 {pct(o['vv'], 99):.2f} max {max(o['vv']):.2f}")


if __name__ == "__main__":
    main()
