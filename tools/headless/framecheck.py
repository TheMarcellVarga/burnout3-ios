"""Count isolated pure-black pixels (the XMV dot grid of BO-43) per dumped frame.

    .venv/bin/python3 tools/headless/framecheck.py runs/x [runs/y ...]
"""
import sys, glob, os
import numpy as np
from PIL import Image

def dots(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    lum = a.max(axis=2)
    c = lum[1:-1, 1:-1]
    nb = (lum[:-2, 1:-1] + lum[2:, 1:-1] + lum[1:-1, :-2] + lum[1:-1, 2:]) / 4
    return int(((c < 8) & (nb > 40)).sum())

for d in sys.argv[1:]:
    fs = sorted(glob.glob(os.path.join(d, "f*.bmp")))
    v = [dots(f) for f in fs]
    bad = sum(1 for x in v if x > 5000)
    print(f"{d}: {len(fs)} frames, {bad} with >5000 dots, max {max(v) if v else 0}, "
          f"median {sorted(v)[len(v)//2] if v else 0}")
