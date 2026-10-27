#!/usr/bin/env python3
"""latency.py <lat.csv> [--pad-byte N] [--min-gap-ms MS] [-v]

Input-to-photon latency from a RECOMP_TRACE=latency=<file> run (BO-74).

For every pad change (an I row whose report differs from the one before),
find the first frame that reacts to it: the first flip, after the change
reached the guest, whose 16x12 signature differs from the frame before by
more than the screen's own noise (the largest frame-to-frame difference in
the frames just before the change, doubled, at least --floor). That works on
a still screen -- the pause menu, a static menu -- and is meaningless on a
moving one, so drive the run on one: tools/perf/latency_run.sh does.

Per reaction it reports the times from the pad change to:
  R  the guest's OHCI ISR ran (the driver has the report)
  S  the reacting frame's swap reached the executor (the guest built it)
  V  its FLIP_STALL released: the emulated vblank, where the console's
     scanout of that frame starts
  E  the backend's flip returned (committed to the host GPU)
  G  the host GPU finished it
  W  the presenter had a drawable for it
  P  its present was committed
  D  it was on glass (Metal presentedTime)
and the host's own share, D - V: what the port adds over the console,
which shows the frame from V. Printed as p50 / p95 / max in ms and in
frames of 1/60 s.
"""
import argparse
import csv
import sys

FRAME_MS = 1000.0 / 60.0


def load(path):
    rows = {k: {} for k in "BSVEGWPD"}
    sig, gpu_end, acq, onglass = {}, {}, {}, {}
    inputs, isr = [], []
    with open(path, newline="") as f:
        for r in csv.reader(f):
            if not r or r[0] == "kind" or len(r) < 3:
                continue
            k = r[0]
            try:
                n, t = int(r[1]), int(r[2])
            except ValueError:
                continue
            if k == "I":
                inputs.append((t, int(n), r[3] if len(r) > 3 else ""))
            elif k == "R":
                isr.append(t)
            elif k in rows:
                if k == "G":
                    try:
                        sig[n] = bytes.fromhex(r[4])
                        gpu_end[n] = int(r[3])
                    except (ValueError, IndexError):
                        continue
                if k == "W":
                    acq[n] = int(r[3]) if len(r) > 3 and r[3] else t
                if k == "D":
                    onglass.setdefault(n, int(r[3]) if len(r) > 3 and r[3] else 0)
                # First P/W/D per flip: a re-present of the same frame
                # (an expose) is not when it first showed.
                rows[k].setdefault(n, t)
    return rows, sig, gpu_end, acq, onglass, inputs, isr


def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def pct(v, p):
    v = sorted(v)
    if not v:
        return float("nan")
    i = min(len(v) - 1, int(round(p / 100.0 * (len(v) - 1))))
    return v[i]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--floor", type=int, default=40,
                    help="smallest signature change that counts (default 40)")
    ap.add_argument("--noise-frames", type=int, default=12)
    ap.add_argument("--within", type=int, default=12,
                    help="flips after the change to look in (default 12)")
    ap.add_argument("--presses-only", action="store_true",
                    help="only changes from an idle pad (no releases)")
    ap.add_argument("--digital", default=None,
                    help="only changes to these d-pad/button bytes (hex, comma"
                         " list; e.g. 01,02 = up, down: the pause-menu steps)")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()

    rows, sig, gpu_end, acq, onglass, inputs, isr = load(a.csv)
    S, V, E = rows["S"], rows["V"], rows["E"]
    G, W, P, D = rows["G"], rows["W"], rows["P"], rows["D"]
    flips = sorted(f for f in V if f in sig)
    if not flips:
        sys.exit("no frames with signatures (RECOMP_TRACE=latency on a Metal run?)")
    isr.sort()

    prev_rep = None
    res = []
    for t_in, pad, rep in sorted(inputs):
        idle_before = prev_rep is not None and set(prev_rep) <= {"0"}
        prev_rep = rep
        if a.presses_only and not idle_before:
            continue
        if a.digital and rep[:2] not in a.digital.split(","):
            continue
        # The swap of flip f is the S row numbered f-1 (the NOP precedes
        # FLIP_INCREMENT_WRITE). A frame can react only if its swap came
        # after the change.
        cand = [f for f in flips if (f - 1) in S and S[f - 1] > t_in]
        if len(cand) < 2:
            continue
        first = cand[0]
        before = [f for f in flips if f < first][-a.noise_frames:]
        noise = max((diff(sig[f], sig[f - 1]) for f in before if f - 1 in sig),
                    default=0)
        thr = max(a.floor, 2 * noise)
        hit = None
        for f in cand[: a.within]:
            if f - 1 in sig and diff(sig[f], sig[f - 1]) > thr:
                hit = f
                break
        if hit is None:
            if a.v:
                print(f"  t={t_in} {rep[:8]}: no reaction above {thr} (noise {noise})")
            continue
        r_t = next((t for t in isr if t >= t_in), None)
        e = {"R": r_t, "S": S.get(hit - 1), "V": V.get(hit), "E": E.get(hit),
             "G": gpu_end.get(hit) or G.get(hit), "W": acq.get(hit),
             "P": P.get(hit), "D": onglass.get(hit) or None}
        d = {k: (v - t_in) / 1e6 for k, v in e.items() if v}
        if "D" in d and "V" in d:
            d["D-V"] = d["D"] - d["V"]
        if "G" in d and "V" in d:
            d["G-V"] = d["G"] - d["V"]
        d["flips"] = hit - first
        res.append(d)
        if a.v:
            print(f"  t={t_in} {rep[:8]} -> flip {hit} (+{hit - first} after the first"
                  f" candidate, thr {thr}): "
                  + " ".join(f"{k}={v:.1f}" for k, v in d.items() if k != "flips"))

    if not res:
        sys.exit("no reactions found")
    print(f"{len(res)} reactions of {len(inputs)} pad changes")
    print(f"{'stage':6} {'p50 ms':>8} {'p95 ms':>8} {'max ms':>8} {'p50 fr':>7} {'p95 fr':>7}")
    for k in ["R", "S", "V", "E", "G", "W", "P", "D", "G-V", "D-V"]:
        v = [d[k] for d in res if k in d]
        if not v:
            continue
        print(f"{k:6} {pct(v, 50):8.1f} {pct(v, 95):8.1f} {max(v):8.1f}"
              f" {pct(v, 50) / FRAME_MS:7.2f} {pct(v, 95) / FRAME_MS:7.2f}")
    # Frame pacing over the whole run, for "60 fps stays stable".
    iv = [(V[f] - V[f - 1]) / 1e6 for f in sorted(V) if f - 1 in V]
    if iv:
        iv = iv[len(iv) // 10:]
        print(f"flip interval p50 {pct(iv, 50):.2f} ms, p95 {pct(iv, 95):.2f},"
              f" p99 {pct(iv, 99):.2f}; {len(iv)} flips")
    dl = [(onglass[f] - onglass[f - 1]) / 1e6 for f in sorted(onglass)
          if f - 1 in onglass and onglass[f] and onglass[f - 1]]
    if dl:
        drops = sum(1 for f in D if not onglass.get(f))
        print(f"on-glass interval p50 {pct(dl, 50):.2f} ms, p5 {pct(dl, 5):.2f},"
              f" p95 {pct(dl, 95):.2f}; {drops} presents never shown")


if __name__ == "__main__":
    main()
