#!/usr/bin/env python3
"""The sun's brightness profile in HDR dumps (BO-203).

    hdr_sun_report.py [--label NAME] [--png OUT.png] [--box x0,y0,x1,y1]
                      [--at x,y] [--rim PX] [--before FILE] FILE.pq10...

Each FILE is a presented HDR frame (RECOMP_DEBUG=hdr_dump, the .pq10 beside
its .rgbaf; a .rgbaf alone, Metal's, is read as paper 200 x v^2.2 without the
roll-off). The sun is found as the brightest smoothed spot of the search
box (default: the top 60 % of the frame); with --at the centre is given.
Per frame it prints:

  centre     the 5x5 mean at the centre, in nits (max of R, G, B)
  profile    the mean in rings 4 px wide round the centre, nits, out to 160 px
  rim        the radius where the sun's own layer ends. Given with --rim, or
             from --before (the same moment with the disc as the title draws
             it, a flat top with a hard edge): the radius where its profile
             falls through the middle of the centre value and the ring
  ring       the profile just outside the rim
  monotone   the centre-out profile never rises by more than 2 % up to the rim
  step       the largest drop between profile samples 12 px apart (nits)
  plateau    the area within 2 % of the centre value, connected to it, as a
             share of the area of the disc (pixels above the ring value
             + 10 %, connected to the centre)

and, with --png, a crop of the sun in every file side by side: grey (nits,
gamma 0.45 to 900) above, 100-nit bands in colour below (a plateau is one
flat patch there). Standard library and numpy only.
"""
import os
import struct
import sys
import zlib

import numpy as np

M1, M2, C1, C2, C3 = 0.1593017578125, 78.84375, 0.8359375, 18.8515625, 18.6875


def load_nits(path):
    """The max of R, G, B in nits, h x w."""
    with open(path, "rb") as f:
        head = f.read(16)
        if head[:4] == b"HDR1":
            # The title's own float frame (Metal writes only these): the nits
            # the pass would give before its roll-off, paper white 200 x v^2.2.
            w, h, _ = struct.unpack("<III", head[4:])
            v = np.frombuffer(f.read(), dtype="<f4").reshape(h, w, 4)[..., :3]
            return 200.0 * np.maximum(np.max(v, axis=2), 0.0) ** 2.2
        if head[:4] != b"PQ10":
            raise SystemExit(f"{path}: not a pq10 or hdr_dump frame")
        w, h, _ = struct.unpack("<III", head[4:])
        v = np.frombuffer(f.read(), dtype="<u4").reshape(h, w)
    best = None
    for sh in (0, 10, 20):
        e = np.clip(((v >> sh) & 1023) / 1023.0, 0.0, 1.0)
        p = e ** (1.0 / M2)
        n = 10000.0 * (np.maximum(p - C1, 0.0) / (C2 - C3 * p)) ** (1.0 / M1)
        best = n if best is None else np.maximum(best, n)
    return best


def box_mean(a, k):
    pad = k // 2
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(np.cumsum(p, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    h, w = a.shape
    return (c[k:k + h, k:k + w] - c[:h, k:k + w] - c[k:k + h, :w] + c[:h, :w]) / float(k * k)


def find_sun(n, box):
    h, w = n.shape
    x0, y0, x1, y1 = box if box else (0, 0, w, int(h * 0.6))
    sm = box_mean(n, 9)
    sub = sm[y0:y1, x0:x1]
    iy, ix = np.unravel_index(int(np.argmax(sub)), sub.shape)
    return ix + x0, iy + y0


def centre_of_plateau(n, cx, cy):
    """Refine: the centroid of the pixels within 2 % of the local maximum."""
    r = 40
    y0, y1, x0, x1 = max(cy - r, 0), cy + r + 1, max(cx - r, 0), cx + r + 1
    sub = n[y0:y1, x0:x1]
    m = sub.max()
    ys, xs = np.nonzero(sub >= 0.98 * m)
    return int(round(xs.mean())) + x0, int(round(ys.mean())) + y0


def profile(n, cx, cy, rmax=160, step=4):
    h, w = n.shape
    y, x = np.mgrid[0:h, 0:w]
    r = np.hypot(x - cx, y - cy)
    out = []
    for r0 in range(0, rmax, step):
        m = (r >= r0) & (r < r0 + step)
        out.append(float(n[m].mean()) if m.any() else float("nan"))
    return out


def component(mask, cx, cy):
    """The connected part of mask holding (cx, cy), 4-connected."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    if not mask[cy, cx]:
        return seen
    stack = [(cy, cx)]
    seen[cy, cx] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                seen[yy, xx] = True
                stack.append((yy, xx))
    return seen


def rim_from_before(prof, step=4):
    """The radius where a flat-topped profile has fallen through the middle of its
    centre value and the ring value (the lowest value before the glow flattens)."""
    c = prof[0]
    ring = min(prof[:25])
    half = 0.5 * (c + ring)
    for i, v in enumerate(prof):
        if v < half:
            return i * step
    return len(prof) * step


def analyse(path, a):
    n = load_nits(path)
    h, w = n.shape
    box = tuple(int(v) for v in a["box"].split(",")) if a.get("box") else None
    if a.get("at"):
        cx, cy = (int(v) for v in a["at"].split(","))
    else:
        cx, cy = find_sun(n, box)
        cx, cy = centre_of_plateau(n, cx, cy)
    c = float(n[max(cy - 2, 0):cy + 3, max(cx - 2, 0):cx + 3].mean())
    prof = profile(n, cx, cy)
    return {"path": path, "nits": n, "cx": cx, "cy": cy, "centre": c, "profile": prof, "w": w, "h": h}


def png_rgb(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


BANDS = np.array([(20, 20, 40), (40, 70, 150), (30, 130, 170), (40, 170, 90), (150, 190, 40),
                  (230, 200, 40), (240, 140, 40), (230, 70, 50), (200, 40, 140), (255, 255, 255)],
                 dtype=np.uint8)


def crop_panel(r, half=110, scale=3):
    n = r["nits"]
    cx, cy = r["cx"], r["cy"]
    y0, x0 = max(cy - half, 0), max(cx - half, 0)
    sub = n[y0:cy + half, x0:cx + half]
    ph, pw = 2 * half, 2 * half
    pad = np.zeros((ph, pw), dtype=np.float64)
    pad[:sub.shape[0], :sub.shape[1]] = sub
    g = (np.clip(pad / 900.0, 0, 1) ** 0.45 * 255).astype(np.uint8)
    grey = np.stack([g, g, g], axis=2)
    band = BANDS[np.clip((pad // 100).astype(int), 0, 9)]
    both = np.concatenate([grey, band], axis=0)
    return np.repeat(np.repeat(both, scale, axis=0), scale, axis=1)


def main(argv):
    a, files, i = {}, [], 0
    while i < len(argv):
        t = argv[i]
        if t in ("--label", "--png", "--box", "--at", "--rim", "--before"):
            a[t[2:]] = argv[i + 1]
            i += 2
        else:
            files.append(t)
            i += 1
    if not files:
        raise SystemExit(__doc__)
    rim = int(a["rim"]) if a.get("rim") else None
    if a.get("before"):
        rb = analyse(a["before"], a)
        rim = rim_from_before(rb["profile"])
        print("before %s: centre %.0f nits at (%d,%d), rim %d px" % (os.path.basename(a["before"]),
              rb["centre"], rb["cx"], rb["cy"], rim))
        if not a.get("at"):
            a["at"] = "%d,%d" % (rb["cx"], rb["cy"])
    panels, res = [], []
    for p in files:
        r = analyse(p, a)
        prof = r["profile"]
        rr = rim if rim else rim_from_before(prof)
        ring_i = min(rr // 4 + 2, len(prof) - 1)
        ring = prof[ring_i]
        k = rr // 4 + 1
        mono = all(prof[j + 1] <= prof[j] * 1.02 + 1.0 for j in range(k))
        steps = [prof[j] - prof[j + 3] for j in range(0, min(k + 3, len(prof) - 3))]
        step = max(steps) if steps else 0.0
        n = r["nits"]
        disc = component(n >= ring * 1.10, r["cx"], r["cy"])
        plat = component(n >= 0.98 * r["centre"], r["cx"], r["cy"])
        share = float(plat.sum()) / max(float(disc.sum()), 1.0)
        label = a.get("label", "")
        print("%s %s sun (%d,%d) centre %.0f nits | rim %d px ring %.0f | monotone %s | step/12px %.0f nits |"
              " plateau %d px of disc %d px = %.0f %%" % (label, os.path.basename(p), r["cx"], r["cy"],
              r["centre"], rr, ring, "yes" if mono else "NO", step, plat.sum(), disc.sum(), 100 * share))
        print("  profile (4 px rings from the centre):", " ".join("%.0f" % v for v in prof[:36]))
        res.append((r["centre"], mono, step, share, ring))
        panels.append(crop_panel(r))
    if a.get("png"):
        png_rgb(a["png"], np.concatenate(panels, axis=1))
        print("wrote", a["png"])
    return res


if __name__ == "__main__":
    main(sys.argv[1:])
