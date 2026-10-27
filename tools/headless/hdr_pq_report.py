#!/usr/bin/env python3
"""hdr_pq_report.py: what the display gets with HDR on (BO-110), measured.

    hdr_pq_report.py <out_dir> <dump_dir> [--label NAME] [--cutoff 1000] [--classes C.json] [--m20-only]
    hdr_pq_report.py --candidates <out_dir> <texlog> <texdump_dir> [<m20.json>...] [--label L]
    hdr_pq_report.py --reclass <classes.json> <m20.json>...
    hdr_pq_report.py --sun [--before F.pq10] [--png OUT.png] F.pq10...   (BO-203, hdr_sun_report.py)
    hdr_pq_report.py <out_dir> <shot.avif> [<shot.avif> ...] [--paper 200] [--peak 1000]

The second form reads gamescope's HDR screenshots (lossless 10-bit AVIF,
BT.2020, ST 2084: the composed output the panel is sent, AA, scale and
overlay included) through ffmpeg; the metrics that need the game's own
frame (M2, M7) are then left out.

<dump_dir> holds RECOMP_DEBUG=hdr_dump frames of the Vulkan backend: for each
fb_dump_at flip NNNNN

  flip_NNNNN.rgbaf   the presented target: "HDR1", w, h, half; float RGBA,
                     the title's own (gamma-encoded) values, past 1.0 where
                     light stacked
  flip_NNNNN.pq10    the flip pass's output for the same frame: "PQ10", w, h,
                     0; A2B10G10R10 words, PQ, BT.2020 (what the window's
                     slot gets, before AA, sharpening, scale and overlay)
  flip_NNNNN.json    the levels the pass was given (peak, paper, hud,
                     shadows, highlights, decode)

Per frame (report.json, one line each on stdout) the metrics of the HDR
checklist (scratchpad bo110-df-plan.md 4.3):

  M1  black floor: min and 0.1-percentile of max(R,G,B) nits, the share of
      pixels at PQ code 0; pass: 0.1-percentile <= 0.005 nits where the
      frame has black (the 16F frame's own 0.1-percentile is 0)
  M2  SDR range: pixels whose 16F values are all <= 1.0 must come out at
      paper * v^2.2 (or the sRGB curve), shadows applied, within 1 PQ code
      (99.9 % of them); max and 99.9-percentile code error
  M4  peak: max nits <= the configured peak (+1 code); 99.9-percentile
  M5  share of pixels above paper white, above 4x paper, at the peak code
  M7  hue shift through the roll-off: for 16F max-RGB > 1.2 and saturation
      >= 0.1, the hue angle
      before (2.2-decoded 16F, BT.709) and after (pq10 back to BT.709
      linear); max and 99-percentile in degrees; saturation ratio
  M14 MaxCLL (CTA: max over pixels of max(R,G,B) nits, BT.2020), FALL
      (frame mean of max(R,G,B)), the 99.99-percentile, and luminance Y
      max/mean as Lilium shows them

  M20 (BO-195) per light class: with RECOMP_DEBUG=hdr_gains_ab=1 the dump's
      neighbouring flips differ by one thing (.json "ab": 1 in the odd ones):
      with hdr_gains_probe one probe texture is marked x4 (its "probe"), so
      the still pixels (the neighbours agree) where that flip is what x4 in
      linear light through the roll-off makes of them are the texture's,
      and the neighbours give its nits as the game shows them; without
      probes the gains are off in it, so the still pixels where the
      neighbours are >= 1.2x it are the gains' region (with and without).
      Per texture: samples, pixels, max / p95 / median nits; per class with
      --classes <json {hash: class}>; a crop of the best sample
      (m20_<hash>.png, the region outlined) for the candidate sheet

and per frame <name>_view.png (the PQ frame through a fixed SDR view:
1000 nits -> white, gamma 2.2, so frames compare in any browser),
<name>_heat.png (Lilium's nits bands, luminance Y; --cutoff
1000 for a 1000-nit panel: 400-600 yellow->red, 600-800 red->pink,
800-1000 pink->blue, above saturated red), <name>_sdr.png (the 16F frame
clamped) and <name>_pq.png (16-bit, cICP BT.2020/PQ: HDR in a browser on an
HDR display). index.html lists them with the numbers and pass/fail.
"""
import json
import math
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image

M1, M2, C1, C2, C3 = 0.1593017578125, 78.84375, 0.8359375, 18.8515625, 18.6875
M709_TO_2020 = np.array([[0.627404, 0.329283, 0.043313],
                         [0.069097, 0.919540, 0.011362],
                         [0.016391, 0.088013, 0.895595]])
M2020_TO_709 = np.linalg.inv(M709_TO_2020)
Y2020 = np.array([0.2627, 0.6780, 0.0593])
Y709 = np.array([0.2126, 0.7152, 0.0722])


def pq_eotf(code):
    """10-bit PQ codes (0..1023) to nits."""
    e = np.clip(code / 1023.0, 0.0, 1.0)
    p = e ** (1.0 / M2)
    return 10000.0 * (np.maximum(p - C1, 0.0) / (C2 - C3 * p)) ** (1.0 / M1)


def pq_oetf(nits):
    y = np.clip(nits / 10000.0, 0.0, 1.0) ** M1
    return ((C1 + C2 * y) / (1.0 + C3 * y)) ** M2


def load_rgbaf(path):
    with open(path, "rb") as f:
        head = f.read(16)
        if head[:4] != b"HDR1":
            raise SystemExit(f"{path}: not an hdr_dump frame")
        w, h, half = struct.unpack("<III", head[4:])
        a = np.frombuffer(f.read(), dtype="<f4")
    return a.reshape(h, w, 4)[..., :3].astype(np.float64), bool(half)


def load_pq10(path):
    with open(path, "rb") as f:
        head = f.read(16)
        if head[:4] != b"PQ10":
            raise SystemExit(f"{path}: not a pq10 frame")
        w, h, _ = struct.unpack("<III", head[4:])
        v = np.frombuffer(f.read(), dtype="<u4").reshape(h, w)
    return np.stack([v & 1023, (v >> 10) & 1023, (v >> 20) & 1023], axis=2).astype(np.float64)


def load_avif(path):
    """A 10-bit PQ BT.2020 AVIF (gamescope's HDR screenshot) as 10-bit codes,
    through ffmpeg (16-bit RGB out)."""
    import subprocess
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=width,height", "-of", "csv=p=0", path],
                           capture_output=True, text=True, check=True).stdout.split(",")
    w, h = int(probe[0]), int(probe[1])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt",
                          "rgb48le", "-"], capture_output=True, check=True).stdout
    v = np.frombuffer(raw[:w * h * 6], dtype="<u2").reshape(h, w, 3).astype(np.float64)
    return v / 65535.0 * 1023.0


def png16_cicp(path, rgb16):
    h, w, _ = rgb16.shape
    raw = b"".join(b"\x00" + rgb16[y].astype(">u2").tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 2, 0, 0, 0))
    data += chunk(b"cICP", bytes([9, 16, 0, 1]))     # BT.2020, PQ, RGB, full range
    data += chunk(b"IDAT", zlib.compress(raw, 6))
    data += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def lerp(a, b, t):
    t = np.clip(t, 0.0, 1.0)[..., None]
    return np.array(a) * (1 - t) + np.array(b) * t


def heat(y, cutoff):
    """Lilium's heat map bands, Y in nits -> RGB 0..1."""
    out = np.zeros(y.shape + (3,))
    g = np.clip(y / 100.0, 0, 1) * 0.25
    out[:] = np.repeat(g[..., None], 3, axis=2)
    cy, gr, ye, re_, pk, bl = (0, 1, 1), (0, 1, 0), (1, 1, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)
    if cutoff <= 1000:
        bands = [(100, 203, cy, gr), (203, 400, gr, ye), (400, 600, ye, re_),
                 (600, 800, re_, pk), (800, 1000, pk, bl)]
    else:
        bands = [(100, 203, cy, gr), (203, 400, gr, ye), (400, 1000, ye, re_),
                 (1000, 4000, re_, pk), (4000, 10000, pk, bl)]
    for lo, hi, a, b in bands:
        sel = (y > lo) & (y <= hi)
        out[sel] = lerp(a, b, (y[sel] - lo) / (hi - lo))
    out[y > cutoff] = (1, 0, 0)
    out[y < 0] = (0, 0, 1)
    return (out * 255 + 0.5).astype(np.uint8)


def hue(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.degrees(np.arctan2(math.sqrt(3) * (g - b), 2 * r - g - b))


def sat(rgb):
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-9), 0)


def analyse(name, f16, codes, lv, out_dir, cutoff):
    paper, peak = lv["paper"], lv["peak"]
    nits = pq_eotf(codes)                       # BT.2020 linear, nits, per channel
    maxrgb = nits.max(axis=2)
    ylum = nits @ Y2020
    r = {"frame": name, "levels": lv}

    if f16 is None:             # a composed capture (AVIF): no 16F frame to compare with
        f16 = np.zeros(codes.shape)
        only_out = True
    else:
        only_out = False
    # M1 black floor
    src_max = np.maximum(f16, 0).max(axis=2)
    r["M1"] = {"min_nits": float(maxrgb.min()), "p0.1_nits": float(np.percentile(maxrgb, 0.1)),
               "code0_share": float((codes.max(axis=2) == 0).mean()),
               "src_black_share": float((src_max <= 0).mean())}
    r["M1"]["pass"] = bool(r["M1"]["p0.1_nits"] <= 0.005 or np.percentile(src_max, 0.1) > 0.004)

    # M2 SDR range: expected codes for pixels <= 1.0
    sdr = (f16.max(axis=2) <= 1.0) & (f16.min(axis=2) >= 0.0)
    c = np.clip(f16, 0, None)
    if lv.get("decode") == "srgb":
        lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    else:
        lin = c ** 2.2
    k = lv.get("shadows", 1.0)
    if k != 1.0:
        yl = lin @ Y709
        f = np.where((yl > 0) & (yl < 0.18), 0.18 * (np.maximum(yl, 1e-12) / 0.18) ** k
                     / np.maximum(yl, 1e-12), 1.0)
        lin = lin * f[..., None]
    exp_codes = pq_oetf((lin @ M709_TO_2020.T) * paper) * 1023.0
    err = np.abs(exp_codes - codes).max(axis=2)[sdr]
    r["M2"] = {"pixels": int(sdr.sum()), "max_code_err": float(err.max()) if err.size else 0.0,
               "p99.9_code_err": float(np.percentile(err, 99.9)) if err.size else 0.0}
    r["M2"]["pass"] = bool(r["M2"]["p99.9_code_err"] <= 1.0)

    if only_out:
        r["M2"] = {"pass": None}
    # M4 peak
    peak_code = pq_oetf(np.array(peak)) * 1023.0
    r["M4"] = {"max_nits": float(maxrgb.max()), "p99.9_nits": float(np.percentile(maxrgb, 99.9)),
               "peak": peak}
    r["M4"]["pass"] = bool(codes.max() <= peak_code + 1.0)

    # M5 shares
    r["M5"] = {"above_paper": float((maxrgb > paper * 1.01).mean()),
               "above_4x_paper": float((maxrgb > 4 * paper).mean()),
               "at_peak_code": float((codes.max(axis=2) >= math.floor(peak_code)).mean())}

    # M7 hue shift through the roll-off
    bright = c.max(axis=2) > 1.2
    if only_out:
        r["M7"] = {"pass": None}
    elif bright.any():
        before = (c ** 2.2)[bright]
        after = (nits @ M2020_TO_709.T)[bright]
        # Hue is only defined where there is colour: saturation >= 0.1 (the
        # 10-bit codes of a near-grey pixel move its angle by degrees).
        ok = (before.max(axis=1) - before.min(axis=1)) >= 0.1 * before.max(axis=1)
        dh = np.abs(((hue(after[ok]) - hue(before[ok])) + 180) % 360 - 180) if ok.any() else np.zeros(1)
        sr = sat(after[ok]) / np.maximum(sat(before[ok]), 1e-9) if ok.any() else np.ones(1)
        r["M7"] = {"pixels": int(bright.sum()), "max_deg": float(dh.max()),
                   "p99_deg": float(np.percentile(dh, 99)), "sat_ratio_median": float(np.median(sr))}
        r["M7"]["pass"] = bool(r["M7"]["p99_deg"] < 2.0)
    else:
        r["M7"] = {"pixels": 0, "pass": True}

    # M14 MaxCLL / FALL
    r["M14"] = {"maxcll": float(maxrgb.max()), "fall": float(maxrgb.mean()),
                "p99.99_maxrgb": float(np.percentile(maxrgb, 99.99)),
                "y_max": float(ylum.max()), "y_mean": float(ylum.mean())}
    r["M14"]["pass"] = bool(r["M14"]["maxcll"] <= peak * 1.01 and r["M14"]["fall"] <= 250)

    # pictures
    view = view_png(nits)
    Image.fromarray(view).save(os.path.join(out_dir, name + "_view.png"))
    r["_nits"], r["_view"] = nits.astype(np.float32), view
    if not only_out:
        Image.fromarray((np.clip(f16, 0, 1) ** 1.0 * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(out_dir, name + "_sdr.png"))
    Image.fromarray(heat(ylum, cutoff)).save(os.path.join(out_dir, name + "_heat.png"))
    png16_cicp(os.path.join(out_dir, name + "_pq.png"), (codes / 1023.0 * 65535 + 0.5).astype(np.uint16))
    return r


def view_png(nits):
    """The PQ frame for an SDR screen: BT.2020 nits -> BT.709, 1000 nits = 1.0,
    gamma 2.2 (a fixed transform, so frames compare)."""
    v = np.clip((nits @ M2020_TO_709.T) / 1000.0, 0, 1) ** (1 / 2.2)
    return (v * 255 + 0.5).astype(np.uint8)


def _soft():
    """The flip pass's softer top (BO-195 P2): RECOMP_GFX_HDR_SHOULDER, default 0.35."""
    try:
        return float(os.environ.get("RECOMP_GFX_HDR_SHOULDER", "0.35"))
    except ValueError:
        return 0.35


def shoulder(x, m):
    """The flip pass's roll-off in linear light (x = multiples of paper white,
    m = peak / paper): identity to 1, then exp to m, blended towards a rational
    curve past 2.5x (weight s * clamp(m - 1.5, 0, 1) * smoothstep(2.5, 4, x))."""
    x = np.asarray(x, dtype=np.float64)
    if m <= 1.0001:
        return np.minimum(x, 1.0)
    k = m - 1.0
    xc = np.maximum(x, 1.0)
    e = 1 + k * (1 - np.exp(-(xc - 1) / k))
    r = 1 + k * (xc - 1) / ((xc - 1) + k)
    t = np.clip((xc - 2.5) / 1.5, 0, 1)
    w = _soft() * min(max(k - 0.5, 0.0), 1.0) * t * t * (3 - 2 * t)
    return np.where(x <= 1, x, e + w * (r - e))


def shoulder_inv(y, m):
    """The inverse by bisection (the curve is monotonic for m >= 1.5)."""
    y = np.asarray(y, dtype=np.float64)
    yc = np.minimum(y, m - 1e-4)
    lo, hi = np.ones_like(yc), np.full_like(yc, 1e4)
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        up = shoulder(mid, m) < yc
        lo = np.where(up, mid, lo)
        hi = np.where(up, hi, mid)
    return np.where(y <= 1, y, 0.5 * (lo + hi))


def m20_sample(fb, fa, probe, lv):
    """One hdr_gains_ab sample: fb the odd flip's nits (h, w, 3: BT.2020
    per channel), fa the neighbours' (one or two). A pixel counts where the
    neighbours agree (it did not move) and, for a probe, the odd flip is what
    x4 in linear light through the roll-off (on max(R,G,B), hue kept) makes
    of them, in every channel (the probe's draw is the pixel's last word);
    without probes, where the neighbours are >= 1.2x the odd flip. Returns
    (mask, max(R,G,B) as shown, without)."""
    paper, m = lv.get("paper", 200.0), lv.get("peak", 1000.0) / lv.get("paper", 200.0)
    amax, amin = np.max(fa, axis=0), np.min(fa, axis=0)
    a = 0.5 * (amax + amin)                    # per channel
    am, bm = a.max(axis=2), fb.max(axis=2)
    still = ((amax - amin) <= 0.08 * a + 0.5).all(axis=2)
    for dy in (-1, 0, 1):           # and so are its 8 neighbours (no moving edge)
        for dx in (-1, 0, 1):
            if dy or dx:
                still = still & np.roll(np.roll(still, dy, 0), dx, 1)
    if probe:
        r = shoulder(4 * shoulder_inv(am / paper, m), m) * paper / np.maximum(am, 1e-6)
        # (x4 must at least double the pixel: above ~330 nits, where the
        # roll-off squeezes it, a moving edge looks the same, so those are
        # left out: M20 measures what is shown at up to ~330 nits)
        mk = still & (am > 1.0) & (r >= 2.0)
        mk &= (np.abs(fb - r[..., None] * a) <= 0.12 * r[..., None] * a + 1.0).all(axis=2)
    else:
        mk = still & (amin.max(axis=2) > 1.2 * bm) & (amin.max(axis=2) > 5.0)
    # a pixel counts with at least two of its 8 neighbours
    n = np.zeros(mk.shape, np.int8)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                n += np.roll(np.roll(mk, dy, 0), dx, 1)
    mk &= n >= 2
    return mk, am[mk], (None if probe else bm[mk])


def stats(v):
    if v is None or not len(v):
        return {}
    return {"max": float(v.max()), "p99": float(np.percentile(v, 99)),
            "p95": float(np.percentile(v, 95)), "median": float(np.median(v))}


def m20_crop(path, view, m, vals):
    """Where a sample is: the frame (320 wide) with the region tinted
    magenta, and next to it a x2 zoom of the 120x120 with the most of its
    light, the region tinted."""
    h, w = m.shape
    img = view.astype(np.float32)
    img[m] = img[m] * 0.4 + np.array([255, 0, 255]) * 0.6
    full = Image.fromarray(img.astype(np.uint8)).resize((320, 320 * h // w), Image.BILINEAR)
    # the 120x120 window (on a 40-pixel grid) with the most light in the region
    wt = np.zeros(m.shape)
    wt[m] = vals
    g = wt[: h // 40 * 40, : w // 40 * 40].reshape(h // 40, 40, w // 40, 40).sum(axis=(1, 3))
    g3 = sum(np.roll(np.roll(g, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
    by, bx = np.unravel_index(int(np.argmax(g3)), g3.shape)
    cy, cx = by * 40 + 20, bx * 40 + 20
    y0, x0 = min(max(0, cy - 60), h - 120), min(max(0, cx - 60), w - 120)
    zv = view[y0:y0 + 120, x0:x0 + 120].astype(np.float32)
    zm = m[y0:y0 + 120, x0:x0 + 120]
    zv[zm] = zv[zm] * 0.6 + np.array([255, 0, 255]) * 0.4
    zoom = Image.fromarray(zv.astype(np.uint8)).resize((240, 240), Image.NEAREST)
    out = Image.new("RGB", (320 + 4 + 240, max(full.size[1], 240)), (0, 0, 0))
    out.paste(full, (0, 0))
    out.paste(zoom, (324, 0))
    out.save(path)


def m20_group(frames, per, rows, out_dir):
    """frames: {flip: (json levels, max(R,G,B) nits, view)}, one run of
    neighbouring flips of a dump made with hdr_gains_ab=1; adds its samples
    to per (by probe hash, or "gains") and rows."""
    probes = any(x[0].get("probe", "").strip("0") for x in frames.values())
    for f in sorted(frames):
        lv, fb, _ = frames[f]
        if not lv.get("ab"):
            continue
        nb = [frames[g] for g in (f - 1, f + 1) if g in frames and not frames[g][0].get("ab")]
        probe = lv.get("probe", "").strip("0") and lv["probe"]
        if not nb or (probes and not probe):
            continue        # no neighbour, or a probe run's flip with nothing marked
        key = probe or "gains"
        m, shown, without = m20_sample(fb, [x[1] for x in nb], bool(probe), lv)
        if m.sum() < 4:
            continue
        smp = {"flip": f, "key": key, "pixels": int(m.sum()), "shown": stats(shown)}
        if without is not None:
            smp["without"] = stats(without)
        rows.append(smp)
        e = per.setdefault(key, {"samples": 0, "pixels": 0, "vals": [], "wo": [], "best": 0})
        e["samples"] += 1
        e["pixels"] += int(m.sum())
        e["vals"].append(shown[:: max(1, len(shown) // 4000)])
        if without is not None:
            e["wo"].append(without[:: max(1, len(without) // 4000)])
        if m.sum() > e["best"]:     # the crop: the biggest sample, from a neighbour
            e["best"], e["flip"] = int(m.sum()), f
            m20_crop(os.path.join(out_dir, "m20_%s.png" % key), nb[0][2], m, shown)


def m20_finish(per, rows, classes):
    out, bycls = {}, {}
    for k, e in per.items():
        v = np.concatenate(e["vals"])
        out[k] = {"class": classes.get(k, ""), "samples": e["samples"], "pixels": e["pixels"],
                  "shown": stats(v), "crop": "m20_%s.png" % k, "flip": e.get("flip"),
                  "vals": [round(float(x), 1) for x in np.sort(v)[:: max(1, len(v) // 2000)]]}
        if e["wo"]:
            out[k]["without"] = stats(np.concatenate(e["wo"]))
        if classes.get(k):
            bycls.setdefault(classes[k], []).append(v)
    cls = {c: dict(stats(np.concatenate(v)), textures=len(v)) for c, v in bycls.items()}
    return {"textures": out, "classes": cls, "samples": rows}


def candidates(a):
    """--candidates <out_dir> <texlog> <texdump_dir> [<m20.json>...] [--label L]
    [--max 48] [--add 16]: the non-additive light textures for BO-195's P1 to
    pick from. From hdr_texlog's lines (tag 1 = a view's 3D; additive = the
    destination factor ONE) and texrep_dump's TGAs: a scene texture drawn
    without an additive blend whose brightest 2 % of texels are >= 0.9 while
    its median is below 0.75 (a light painted into a darker texture). Sorted
    by that contrast. Writes cand_<hash>.png, candidates.json, probes.txt
    (the hashes for hdr_gains_probe: these, then the --add most drawn
    additive ones, the classes measured for reference) and index.html, with
    the nits a probe run's m20.json measured where given."""
    import shutil
    out_dir, texlog, texdir = a[0], a[1], a[2]
    m20s = [x for x in a[3:] if x.endswith(".json") and not x.startswith("--")]
    label = a[a.index("--label") + 1] if "--label" in a else os.path.basename(texlog)
    nmax = int(a[a.index("--max") + 1]) if "--max" in a else 48
    nadd = int(a[a.index("--add") + 1]) if "--add" in a else 16
    os.makedirs(out_dir, exist_ok=True)
    tex, ids = {}, {}
    for line in open(texlog, errors="replace"):
        w = line.split()
        if "[HDRTEX]" in w:
            w = w[w.index("[HDRTEX]"):]
            h, add = w[2], int(w[7]) == 1 and int(w[11], 16) == 1
            t = tex.setdefault(h, {"hash": h, "fmt": w[4], "size": w[5], "first": int(w[15]),
                                   "combos": set(), "scene": False, "nonadd": False, "add": False,
                                   "draws": 0, "flips": 0, "n": {}})
            tag = int(w[13])
            t["combos"].add("%s %s/%s tag %d" % ("on" if w[7] == "1" else "off", w[9], w[11], tag))
            if tag == 1:
                t["scene"] = True
                t["add" if add else "nonadd"] = True
            if "id" in w:
                ids[int(w[w.index("id") + 1])] = (h, tag == 1)
        elif "[HDRTEXN]" in w:
            w = w[w.index("[HDRTEXN]"):]
            i = int(w[2])
            if i in ids and ids[i][1]:
                t = tex[ids[i][0]]
                t["n"][i] = (int(w[4]), int(w[6]))
    for t in tex.values():
        t["draws"] = sum(d for d, _ in t["n"].values())
        t["flips"] = max([f for _, f in t["n"].values()] or [0])
        del t["n"]
        t["combos"] = sorted(t["combos"])
    files = {}
    for fn in os.listdir(texdir):
        if fn.endswith(".tga") and "_m" not in fn.split("_f")[-1]:
            files.setdefault(fn.split("_")[0], fn)
    measured = {}
    for m in m20s:
        for k, v in json.load(open(m)).get("textures", {}).items():
            if k not in measured or v["pixels"] > measured[k]["pixels"]:
                measured[k] = dict(v, src=os.path.dirname(m))
    cand, adds = [], []
    for h, t in tex.items():
        if not t["scene"] or h not in files:
            continue
        im = np.asarray(Image.open(os.path.join(texdir, files[h])).convert("RGBA")).astype(np.float64) / 255
        a_ok = im[..., 3] >= 0.5
        if a_ok.mean() < 0.01:
            a_ok[:] = True
        mx = im[..., :3].max(axis=2)[a_ok]
        t.update(p98=float(np.percentile(mx, 98)), median=float(np.median(mx)),
                 bright=float((mx >= 0.9).mean()), file=files[h])
        if t["nonadd"] and t["p98"] >= 0.9 and t["median"] < 0.75:
            t["contrast"] = t["p98"] - t["median"]
            cand.append(t)
        elif t["add"] and not t["nonadd"]:
            adds.append(t)
    cand.sort(key=lambda t: (-round(t["contrast"], 2), -t["draws"]))
    cand = cand[:nmax]
    adds.sort(key=lambda t: -t["draws"])
    adds = adds[:nadd]
    with open(os.path.join(out_dir, "probes.txt"), "w") as f:
        f.write("+".join(t["hash"] for t in cand + adds) + "\n")
    for t in cand + adds:
        im = Image.open(os.path.join(texdir, t["file"])).convert("RGBA")
        bg = Image.new("RGBA", im.size, (40, 40, 48, 255))
        im = Image.alpha_composite(bg, im).convert("RGB")
        im.thumbnail((128, 128))
        im.save(os.path.join(out_dir, "cand_%s.png" % t["hash"]))
        m = measured.get(t["hash"])
        if m:
            t["nits"] = stats(np.array(m["vals"])) if m.get("vals") else m["shown"]
            t["samples"] = m["samples"]
            src = os.path.join(m["src"], m["crop"])
            if os.path.exists(src):
                shutil.copy(src, os.path.join(out_dir, "seen_%s.png" % t["hash"]))
                t["seen"] = "seen_%s.png" % t["hash"]
    json.dump({"label": label, "candidates": cand, "additive": adds},
              open(os.path.join(out_dir, "candidates.json"), "w"), indent=1)
    with open(os.path.join(out_dir, "index.html"), "w") as h:
        h.write("<!doctype html><meta charset=utf-8><title>Light candidates</title><style>"
                "body{font:13px sans-serif;background:#111;color:#ddd;margin:16px}"
                ".g{display:flex;flex-wrap:wrap;gap:10px}.c{background:#1c1c22;padding:8px;width:580px}"
                ".c img{max-width:100%%;vertical-align:top;margin:0 4px 4px 0}code{color:#9cf}</style>"
                "<h1>Non-additive light textures: %s</h1><p>Scene textures drawn without an additive "
                "blend whose brightest 2 %% of texels are white-ish while the rest is darker. "
                "Left: the texture; right: where a probe run found it in the game (outlined), with "
                "the nits it is shown at today (p99 of the region's still pixels; max is one pixel and can be "
                "a stray match; up to ~460 nits, above that x4 cannot be told from the roll-off). Draws/flips: hdr_texlog's counts.</p>" % label)
        for title, lst in (("Candidates", cand), ("Additive (reference, done)", adds)):
            h.write("<h2>%s (%d)</h2><div class=g>" % (title, len(lst)))
            for t in lst:
                n = t.get("nits")
                h.write("<div class=c><img src='cand_%s.png'>%s<br><code>%s</code> %s fmt %s<br>"
                        "%s<br>first flip %d, %d draws in %d flips<br>bright texels %.1f %%, "
                        "p98 %.2f, median %.2f<br><b>%s</b></div>" % (
                            t["hash"], "<img src='%s'>" % t["seen"] if t.get("seen") else "",
                            t["hash"], t["size"], t["fmt"], "; ".join(t["combos"]), t["first"],
                            t["draws"], t["flips"], 100 * t["bright"], t["p98"], t["median"],
                            "shown at p99 %.0f, max %.0f nits (%d samples)" % (
                                n.get("p99", n["max"]), n["max"], t["samples"]) if n else
                            "not measured (not in view on a probe flip)"))
            h.write("</div>")
    print("%d candidates, %d additive; probes.txt has %d hashes" % (len(cand), len(adds),
                                                                     len(cand) + len(adds)))


def reclass(a):
    """--reclass <classes.json> <m20.json>...: the per-class table again from
    measured runs, with a class map made after looking at the crops."""
    classes = json.load(open(a[0]))
    by = {}
    for m in a[1:]:
        for k, v in json.load(open(m))["textures"].items():
            if classes.get(k):
                by.setdefault(classes[k], {})[k] = np.array(v["vals"])
    out = {}
    for c, d in sorted(by.items()):
        out[c] = dict(stats(np.concatenate(list(d.values()))), textures=sorted(d))
        print("%-24s %2d textures  max %4.0f  p99 %4.0f  p95 %4.0f  median %4.0f nits"
              % (c, len(d), out[c]["max"], out[c]["p99"], out[c]["p95"], out[c]["median"]))
    return out


def main():
    a = sys.argv[1:]
    if a and a[0] == "--candidates":
        return candidates(a[1:])
    if a and a[0] == "--reclass":
        return reclass(a[1:])
    if a and a[0] == "--sun":           # BO-203: the sun's profile and plateau (hdr_sun_report.py)
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import hdr_sun_report
        return hdr_sun_report.main(a[1:])
    if len(a) < 2:
        raise SystemExit(__doc__)
    out_dir, dump_dir = a[0], a[1]
    label, cutoff = os.path.basename(os.path.normpath(dump_dir)), 1000.0
    if "--label" in a:
        label = a[a.index("--label") + 1]
    if "--cutoff" in a:
        cutoff = float(a[a.index("--cutoff") + 1])
    classes = json.load(open(a[a.index("--classes") + 1])) if "--classes" in a else {}
    os.makedirs(out_dir, exist_ok=True)
    rows, group, m20_per, m20_rows = [], {}, {}, []
    if dump_dir.endswith(".avif"):
        # gamescope's HDR screenshot(s): --paper/--peak say what the game was set to
        lv = {"paper": 200.0, "peak": 1000.0}
        for k in ("paper", "peak"):
            if "--" + k in a:
                lv[k] = float(a[a.index("--" + k) + 1])
        for path in [x for x in a[1:] if x.endswith(".avif")]:
            base = os.path.basename(path)[:-5]
            r = analyse(base, None, load_avif(path), lv, out_dir, cutoff)
            del r["_nits"], r["_view"]
            rows.append(r)
            print("%s M1 p0.1 %.4f nits | M4 max %.0f nits | M5 >paper %.2f%% | M14 MaxCLL %.0f FALL %.1f"
                  % (base, r["M1"]["p0.1_nits"], r["M4"]["max_nits"], 100 * r["M5"]["above_paper"],
                     r["M14"]["maxcll"], r["M14"]["fall"]))
    for fn in sorted(os.listdir(dump_dir)) if os.path.isdir(dump_dir) else []:
        if not fn.endswith(".pq10"):
            continue
        base = fn[:-5]
        p16, pj = os.path.join(dump_dir, base + ".rgbaf"), os.path.join(dump_dir, base + ".json")
        if not os.path.exists(p16):
            continue
        codes = load_pq10(os.path.join(dump_dir, fn))
        lv = json.load(open(pj)) if os.path.exists(pj) else {"peak": 1000, "paper": 200}
        if "--m20-only" in a:       # a probe run: only what M20 needs
            if "ab" in lv:
                nits = pq_eotf(codes)
                f = lv["flip"]
                if group and f - 1 not in group:
                    m20_group(group, m20_per, m20_rows, out_dir)
                    group = {}
                group[f] = (lv, nits.astype(np.float32), view_png(nits))
            continue
        f16, _ = load_rgbaf(p16)
        r = analyse(base, f16, codes, lv, out_dir, cutoff)
        if "ab" in lv:
            f = lv["flip"]
            if group and f - 1 not in group:
                m20_group(group, m20_per, m20_rows, out_dir)
                group = {}
            group[f] = (lv, r["_nits"], r["_view"])
        del r["_nits"], r["_view"]
        rows.append(r)
        print("%s M1 p0.1 %.4f nits (code0 %.1f%%) | M2 max %.2f p99.9 %.2f codes | M4 max %.0f "
              "nits | M5 >paper %.2f%% >4x %.2f%% @peak %.3f%% | M7 p99 %.2f deg | M14 MaxCLL %.0f "
              "FALL %.1f" % (base, r["M1"]["p0.1_nits"], 100 * r["M1"]["code0_share"],
                             r["M2"]["max_code_err"], r["M2"]["p99.9_code_err"], r["M4"]["max_nits"],
                             100 * r["M5"]["above_paper"], 100 * r["M5"]["above_4x_paper"],
                             100 * r["M5"]["at_peak_code"], r["M7"].get("p99_deg", 0),
                             r["M14"]["maxcll"], r["M14"]["fall"]))
    if group:
        m20_group(group, m20_per, m20_rows, out_dir)
    m20 = m20_finish(m20_per, m20_rows, classes) if m20_per else None
    if m20:
        json.dump(m20, open(os.path.join(out_dir, "m20.json"), "w"), indent=1)
        for c, v in sorted(m20["classes"].items()):
            print("M20 class %-14s %2d textures  max %4.0f  p95 %4.0f  median %4.0f nits"
                  % (c, v["textures"], v["max"], v["p95"], v["median"]))
    json.dump(rows, open(os.path.join(out_dir, "report.json"), "w"), indent=1)
    with open(os.path.join(out_dir, "index.html"), "w") as h:
        h.write("<!doctype html><meta charset=utf-8><title>%s</title><style>body{font:14px sans-serif;"
                "background:#111;color:#ddd}img{width:24%%}td{padding:2px 8px}.f{color:#f66}.p{color:#6d6}"
                "</style><h1>HDR checklist metrics: %s</h1>" % (label, label))
        if m20:
            h.write("<h2>M20 nits per light class (as shown)</h2><table><tr><td>class<td>textures"
                    "<td>max<td>p95<td>median")
            for c, v in sorted(m20["classes"].items(), key=lambda x: -x[1]["p95"]):
                h.write("<tr><td>%s<td>%d<td>%.0f<td>%.0f<td>%.0f" % (
                    c, v["textures"], v["max"], v["p95"], v["median"]))
            h.write("</table><h2>M20 per texture</h2><table><tr><td><td>texture<td>class<td>samples"
                    "<td>pixels<td>max<td>p95<td>median<td>without gains (max/p95)")
            for k, v in sorted(m20["textures"].items(), key=lambda x: -x[1]["shown"]["p95"]):
                wo = v.get("without")
                h.write("<tr><td><img style='width:160px' src='%s'><td>%s<td>%s<td>%d<td>%d<td>%.0f"
                        "<td>%.0f<td>%.0f<td>%s" % (
                            v["crop"], k, v["class"], v["samples"], v["pixels"], v["shown"]["max"],
                            v["shown"]["p95"], v["shown"]["median"],
                            "%.0f / %.0f" % (wo["max"], wo["p95"]) if wo else ""))
            h.write("</table>")
        for r in rows:
            h.write("<h2>%s</h2><p>levels: %s</p><table>" % (r["frame"], json.dumps(r["levels"])))
            for m in ("M1", "M2", "M4", "M5", "M7", "M14"):
                ok = r[m].get("pass")
                cls = "" if ok is None else ("p" if ok else "f")
                h.write("<tr><td>%s</td><td class=%s>%s</td><td>%s</td></tr>" % (
                    m, cls, "" if ok is None else ("PASS" if ok else "FAIL"),
                    json.dumps({k: v for k, v in r[m].items() if k != "pass"})))
            h.write("</table><img src='%s_sdr.png'> <img src='%s_view.png'> <img src='%s_heat.png'>"
                    " <img src='%s_pq.png'>" % ((r["frame"],) * 4))


if __name__ == "__main__":
    main()
