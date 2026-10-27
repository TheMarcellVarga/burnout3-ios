#!/usr/bin/env python3
"""gp_compare.py <ours.f32> <reference.f32> [channels=6] [window_s=10]

Two interleaved float32 renders of the same frames (tests/gp's bo3_gp_replay
against a reference render of the GP stage): per channel the level of each,
their difference, the correlation, the residual (ours - reference) against
the reference's level, the largest sample difference in 24-bit steps, and
the worst window. Needs numpy."""
import sys
import numpy as np

def db(x):
    return 10 * np.log10(x) if x > 0 else -200.0

def main():
    a = np.memmap(sys.argv[1], np.float32)
    b = np.memmap(sys.argv[2], np.float32)
    nch = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    win = int(float(sys.argv[4]) * 48000) if len(sys.argv) > 4 else 480000
    n = min(len(a), len(b)) // nch
    a = a[:n * nch].reshape(n, nch)
    b = b[:n * nch].reshape(n, nch)
    names = ['FL', 'FR', 'C', 'LFE', 'SL', 'SR'] if nch == 6 else ['ch%d' % c for c in range(nch)]
    print('%d samples (%.1f s)' % (n, n / 48000))
    print('%-4s %9s %9s %7s %8s %9s %10s %9s  %s' % ('', 'ours dB', 'ref dB', 'diff', 'corr', 'resid dB', 'max lsb24', 'differ', 'worst %g s window: level diff / resid dB' % (win / 48000)))
    for c in range(nch):
        x = a[:, c].astype(np.float64)
        y = b[:, c].astype(np.float64)
        e = x - y
        px, py, pe = (x * x).mean(), (y * y).mean(), (e * e).mean()
        corr = (x * y).mean() / np.sqrt(px * py) if px > 0 and py > 0 else float('nan')
        worst_d, worst_r = 0.0, -200.0
        for o in range(0, n - win + 1, win):
            wx, wy, we = (x[o:o + win] ** 2).mean(), (y[o:o + win] ** 2).mean(), (e[o:o + win] ** 2).mean()
            if wy > 1e-10:
                d = db(wx) - db(wy)
                if abs(d) > abs(worst_d): worst_d = d
                r = db(we) - db(wy)
                if r > worst_r: worst_r = r
        print('%-4s %9.2f %9.2f %+7.2f %8.5f %9.1f %10.0f %9d  %+.2f / %.1f' % (
            names[c], db(px), db(py), db(px) - db(py), corr,
            db(pe) - db(py) if pe > 0 else -200.0, np.abs(e).max() * 8388608, int((e != 0).sum()), worst_d, worst_r))

if __name__ == '__main__':
    main()
