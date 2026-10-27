#!/usr/bin/env python3
"""hdr_report.py: pictures and numbers from RECOMP_DEBUG=hdr_dump frames (BO-110).

    hdr_report.py <out_dir> <frame.rgbaf> [<frame.rgbaf> ...]
        [--paper 203] [--peak 1000] [--pair sdr.rgbaf:hdr.rgbaf ...]

A frame is the presented render target as 32-bit float RGBA (header "HDR1",
w, h, half): the title's own values, gamma-encoded as it blends them, past
1.0 where light stacked in a half-float target. For each frame:

  <name>_sdr.png    clamped to [0, 1]: what an SDR target would hold
  <name>_false.png  false colour of the brightest channel: the SDR picture
                    in grey up to 1.0, then blue (1-1.5), cyan (1.5-2),
                    green (2-3), yellow (3-4), orange (4-8), red (>8)
  <name>_pq.png     16-bit PNG, BT.2020 primaries, PQ, with a cICP chunk:
                    shown as HDR by a browser on an HDR display. Values up
                    to 1.0 at paper white unchanged; above, a shoulder that
                    starts with slope 1 and reaches the peak
  <name>_tm.png     the same mapping seen on an SDR screen (peak shown as
                    white, paper white as 1/(peak/paper))

and a line of numbers (share of pixels past 1.0, the brightest value,
percentiles) in <out_dir>/report.json. --pair a:b also writes the largest
difference of the clamped pictures (SDR identity: an SDR run against the
same frame of an HDR run, both clamped) and the share of pixels that differ.
"""
import json
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image


def load(path):
    with open(path, "rb") as f:
        head = f.read(16)
        if head[:4] != b"HDR1":
            raise SystemExit(f"{path}: not an hdr_dump frame")
        w, h, half = struct.unpack("<III", head[4:])
        a = np.frombuffer(f.read(), dtype="<f4")
    return a.reshape(h, w, 4), bool(half)


def to8(x):
    return (np.clip(x, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def eotf(v):
    # The title's values are gamma-encoded (it blends in that space); an
    # extended sRGB-like power curve, kept monotonic past 1.0.
    return np.sign(v) * np.abs(v) ** 2.2


def shoulder(x, m):
    # identity up to 1.0; above, 1 + (m-1)(1 - exp(-(x-1)/(m-1))): slope 1 at
    # 1.0, approaching m (peak / paper white).
    if m <= 1.0:
        return np.minimum(x, 1.0)
    y = 1.0 + (m - 1.0) * (1.0 - np.exp(-(x - 1.0) / (m - 1.0)))
    return np.where(x <= 1.0, x, y)


M709_TO_2020 = np.array([[0.6274, 0.3293, 0.0433],
                         [0.0691, 0.9195, 0.0114],
                         [0.0164, 0.0880, 0.8956]])


def pq(nits):
    m1, m2 = 2610 / 16384, 2523 / 4096 * 128
    c1, c2, c3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
    y = np.clip(nits / 10000.0, 0.0, 1.0) ** m1
    return ((c1 + c2 * y) / (1 + c3 * y)) ** m2


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


BANDS = [(1.0, 1.5, (40, 90, 255)), (1.5, 2.0, (0, 200, 230)), (2.0, 3.0, (40, 210, 60)),
         (3.0, 4.0, (240, 230, 30)), (4.0, 8.0, (255, 140, 0)), (8.0, 1e9, (240, 20, 20))]


def false_colour(px):
    m = px[..., :3].max(axis=2)
    grey = to8(px[..., :3]).astype(np.float32).mean(axis=2) * 0.6
    out = np.repeat(grey[..., None], 3, axis=2).astype(np.uint8)
    for lo, hi, c in BANDS:
        sel = (m > lo) & (m <= hi)
        out[sel] = c
    return out


def main():
    args = sys.argv[1:]
    paper, peak, pairs, frames = 203.0, 1000.0, [], []
    global hud_nits
    hud_nits = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--paper":
            paper = float(args[i + 1]); i += 2; continue
        if a == "--peak":
            peak = float(args[i + 1]); i += 2; continue
        if a == "--hud":
            hud_nits = float(args[i + 1]); i += 2; continue
        if a == "--pair":
            pairs.append(args[i + 1].split(":")); i += 2; continue
        frames.append(a); i += 1
    out = frames.pop(0)
    if hud_nits is None:
        hud_nits = paper
    os.makedirs(out, exist_ok=True)
    rep = {"paper_nits": paper, "peak_nits": peak, "frames": {}, "pairs": []}
    m = peak / paper
    for f in frames:
        if f.endswith("_scene.rgbaf"):
            continue
        px, half = load(f)
        name = os.path.splitext(os.path.basename(f))[0]
        rgb = px[..., :3]
        # The scene snapshot of the same flip (the frame before the HUD),
        # when there is one: HUD pixels are where the frame differs from it,
        # as the presenter's composite (fb_present_metal.m fs_hdr_comp) tells.
        sp = f[:-len(".rgbaf")] + "_scene.rgbaf"
        hud = np.ones(rgb.shape[:2], bool)
        if os.path.exists(sp):
            sc, _ = load(sp)
            hud = np.abs(rgb - sc[..., :3]).max(axis=2) >= 0.002
            Image.fromarray(np.where(hud, 255, 0).astype(np.uint8)).save(
                os.path.join(out, name + "_hudmask.png"))
        mx = np.where(hud, np.minimum(rgb.max(axis=2), 1.0), rgb.max(axis=2))
        Image.fromarray(to8(rgb)).save(os.path.join(out, name + "_sdr.png"))
        fc = px.copy()
        fc[hud, :3] = np.minimum(fc[hud, :3], 1.0)
        Image.fromarray(false_colour(fc)).save(os.path.join(out, name + "_false.png"))
        lin = eotf(np.maximum(rgb, 0.0))
        # hue-preserving: the shoulder on the brightest channel, the others
        # scaled with it; HUD pixels clamped to 1.0 at the HUD's white
        lmax = lin.max(axis=2, keepdims=True)
        scale = np.where(lmax > 1.0, shoulder(lmax, m) / np.maximum(lmax, 1e-6), 1.0)
        disp = lin * scale                       # 1.0 = paper white
        disp = np.where(hud[..., None], eotf(np.clip(rgb, 0.0, 1.0)) * (hud_nits / paper), disp)
        nits = np.einsum("ij,hwj->hwi", M709_TO_2020, disp) * paper
        png16_cicp(os.path.join(out, name + "_pq.png"),
                   (pq(nits) * 65535.0 + 0.5).astype(np.uint16))
        tm = (disp / m) ** (1 / 2.2)
        Image.fromarray(to8(tm)).save(os.path.join(out, name + "_tm.png"))
        st = {"hud_share": float(hud.mean()), "w": int(px.shape[1]), "h": int(px.shape[0]), "half": half,
              "max": float(mx.max()),
              "share_over_1": float((mx > 1.0 + 1e-3).mean()),
              "share_over_2": float((mx > 2.0).mean()),
              "share_over_4": float((mx > 4.0).mean()),
              "p99": float(np.percentile(mx, 99)), "p999": float(np.percentile(mx, 99.9))}
        for lo, hi, _ in BANDS:
            st[f"band_{lo:g}_{hi:g}"] = float(((mx > lo) & (mx <= hi)).mean())
        rep["frames"][name] = st
        print(name, json.dumps(st))
    for a, b in pairs:
        pa, _ = load(a)
        pb, _ = load(b)
        da, db = to8(pa[..., :3]).astype(int), to8(pb[..., :3]).astype(int)
        d = np.abs(da - db)
        r = {"a": a, "b": b, "max_diff": int(d.max()),
             "share_diff": float((d.max(axis=2) > 0).mean())}
        rep["pairs"].append(r)
        print("pair", json.dumps(r))
    with open(os.path.join(out, "report.json"), "w") as f:
        json.dump(rep, f, indent=1)


if __name__ == "__main__":
    main()
