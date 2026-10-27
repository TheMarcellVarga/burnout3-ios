#!/usr/bin/env python3
"""Golden frames for the reference scenes. Standard library only (runs on
the Mac and on the Deck's system python3).

    golden.py capture SCENE [--backend B] [--out DIR] [KEY=VALUE...]
        run tools/headless/to_SCENE.sh with CAPTURE=1 STOP_AT_END=1 and the
        backend (metal, cpu, d3d11); the shots land in DIR/shots
    golden.py update RUNDIR... [--backend B]
        make RUNDIR's shots the references for its backend: copy them to
        $GOLDEN_DIR/<backend>/<shot>.png and write their hashes into
        golden.json
    golden.py check RUNDIR... [--against B] [--window]
        compare RUNDIR's shots with the references of their own backend
        (or of backend B: a cross-backend check, with the looser
        "cross_backend" limits and the deviations golden.json documents);
        exit 1 on a FAIL, 2 on a missing reference or shot
    golden.py determinism RUNDIR_A RUNDIR_B
        the same scene run twice with the same build and backend: every
        shot must be identical or within its limits
    golden.py diff A.bmp B.png
        the compare's numbers for two images
    golden.py xmvref
        decode the movies golden.json names (WMV2 in XMV) with ffmpeg into
        $GOLDEN_DIR/xmv/<movie>/NNNNN.png
    golden.py xmvcheck RUNDIR...
        compare the video shots with the ffmpeg frames around their time:
        the best frame within the window must be within the video limits
        (check does this too for a movie shot that misses its reference:
        the movie keeps its own clock, so a slower run lands frames on)
    golden.py list
        the scenes, their shots and anchors, and the reference columns

golden.json (beside this file, committed) holds the scenes, their shots
(log anchor and flip offset, as the drivers take them; masks; limits), the
backend columns and the references' SHA-256 and size. It holds no image
data: the reference PNGs are game frames and live in $GOLDEN_DIR
(default <repo>/runs/golden, or the main checkout's when this is a
worktree; outside git).

A shot passes when its pixel hash equals the reference's, or when every
channel's mean absolute difference is at most max_channel_mae, the share
of pixels off by more than pixel_tol in any channel is at most
max_bad_fraction, and no 64x64 tile has more than max_tile_bad_fraction of
them. A shot's "skip" names backends where it is not
comparable, with the reason (SKIP neither passes nor fails). A mask rect
takes pixels out of the compare (the run's pixels there
become the reference's): for things that animate on a clock the anchor
does not follow, or are random (the EA Trax song box). The hash is
SHA-256 of width, height and the RGB pixels top-down, so it does not depend
on BMP or PNG.

The image reading, the hash and the tile statistics follow apexJCL's
xboxrecomp-cli golden.py (MIT, github.com/apexJCL/xboxrecomp-cli,
src/xboxrecomp_cli/golden.py at 161f48a), the BLiNX 2 golden gate; the
anchors here are the scene drivers' log events instead of fixed presents.
"""

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MANIFEST = os.path.join(HERE, "golden.json")


def load():
    with open(MANIFEST) as f:
        return json.load(f)


def save(g):
    with open(MANIFEST, "w") as f:
        json.dump(g, f, indent=2, sort_keys=False)
        f.write("\n")


def golden_dir(g):
    d = os.path.expanduser(os.environ.get("GOLDEN_DIR") or g["golden_dir"])
    if os.path.isabs(d):
        return d
    # relative: under the repository, or under the main checkout when this is
    # a linked worktree (runs/ is git-ignored, so a worktree has none)
    repo = os.path.abspath(os.path.join(HERE, "..", ".."))
    here = os.path.join(repo, d)
    if not os.path.isdir(here):
        try:
            out = subprocess.run(["git", "-C", repo, "worktree", "list", "--porcelain"],
                                 capture_output=True, text=True).stdout
            first = out.split("\n", 1)[0]
            main = os.path.join(first[len("worktree "):], d) if first.startswith("worktree ") else ""
            if main and os.path.isdir(main):
                return main
        except OSError:
            pass
    return here


# ---- images ----------------------------------------------------------------

def read_bmp(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:2] != b"BM":
        raise ValueError(f"{path}: not a BMP")
    off = struct.unpack_from("<I", d, 10)[0]
    w, h = struct.unpack_from("<ii", d, 18)
    bpp = struct.unpack_from("<H", d, 28)[0]
    if bpp not in (24, 32):
        raise ValueError(f"{path}: {bpp} bpp BMP not supported")
    bypp = bpp // 8
    stride = (w * bypp + 3) & ~3
    rows = range(abs(h)) if h < 0 else range(h - 1, -1, -1)
    out = bytearray()
    for y in rows:
        row = d[off + y * stride: off + y * stride + w * bypp]
        px = bytearray(w * 3)
        px[0::3] = row[2::bypp]
        px[1::3] = row[1::bypp]
        px[2::3] = row[0::bypp]
        out += px
    return w, abs(h), bytes(out)


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat, w = 8, b"", None
    while pos < len(d):
        n, typ = struct.unpack_from(">I4s", d, pos)
        body = d[pos + 8: pos + 8 + n]
        pos += 12 + n
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype not in (2, 6) or inter:
                raise ValueError(f"{path}: only 8-bit RGB/RGBA non-interlaced PNG")
            bypp = 3 if ctype == 2 else 4
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = w * bypp
    prev = bytearray(stride)
    out = bytearray()
    i = 0
    for _ in range(h):
        ft = raw[i]
        cur = bytearray(raw[i + 1: i + 1 + stride])
        i += 1 + stride
        if ft == 1:
            for x in range(bypp, stride):
                cur[x] = (cur[x] + cur[x - bypp]) & 255
        elif ft == 2:
            for x in range(stride):
                cur[x] = (cur[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                left = cur[x - bypp] if x >= bypp else 0
                cur[x] = (cur[x] + ((left + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                left = cur[x - bypp] if x >= bypp else 0
                ul = prev[x - bypp] if x >= bypp else 0
                cur[x] = (cur[x] + _paeth(left, prev[x], ul)) & 255
        elif ft != 0:
            raise ValueError(f"{path}: bad PNG filter {ft}")
        if bypp == 4:
            rgb = bytearray(w * 3)
            rgb[0::3], rgb[1::3], rgb[2::3] = cur[0::4], cur[1::4], cur[2::4]
            out += rgb
        else:
            out += cur
        prev = cur
    return w, h, bytes(out)


def write_png(path, img):
    w, h, rgb = img
    stride = w * 3
    raw = b"".join(b"\x00" + rgb[y * stride: (y + 1) * stride] for y in range(h))

    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))

    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))
    os.replace(tmp, path)


def read_image(path):
    with open(path, "rb") as f:
        magic = f.read(2)
    return read_bmp(path) if magic == b"BM" else read_png(path)


def pixel_sha(img):
    w, h, rgb = img
    return hashlib.sha256(struct.pack("<II", w, h) + rgb).hexdigest()


def crop(img, w, h):
    iw, ih, rgb = img
    if (iw, ih) == (w, h):
        return img
    return w, h, b"".join(rgb[y * iw * 3: y * iw * 3 + w * 3] for y in range(h))


def apply_masks(img, ref, masks):
    """The run's pixels inside each mask rect replaced by the reference's."""
    if not masks:
        return img
    w, h, a = img
    b = ref[2]
    out = bytearray(a)
    for m in masks:
        x, y, mw, mh = m["rect"]
        x0, x1 = max(0, x), min(w, x + mw)
        for yy in range(max(0, y), min(h, y + mh)):
            j0, j1 = 3 * (yy * w + x0), 3 * (yy * w + x1)
            out[j0:j1] = b[j0:j1]
    return w, h, bytes(out)


TILE = 64


def stats(a, b, pixel_tol):
    """Per-channel mean abs diff, the share of pixels with a channel off by
    more than pixel_tol, and the worst 64x64 tile's share (two grids, the
    second shifted by half a tile, as xboxrecomp-cli's golden.py)."""
    (wa, ha, pa), (_, _, pb) = a, b
    n = wa * ha
    if pa == pb:
        return {"mae": [0.0] * 3, "bad": 0.0, "tile": 0.0, "tile_at": (0, 0)}
    sums = [0, 0, 0]
    for c in range(3):
        ca, cb = pa[c::3], pb[c::3]
        if ca == cb:
            continue
        hist = [0] * 256
        for x, y in zip(ca, cb):
            hist[x - y if x >= y else y - x] += 1
        sums[c] = sum(i * k for i, k in enumerate(hist))
    H = TILE // 2
    tw, th = (wa + TILE - 1) // TILE, (ha + TILE - 1) // TILE
    tbad = [0] * (tw * th)
    sw, sh = (wa + H) // TILE + 1, (ha + H) // TILE + 1
    sbad = [0] * (sw * sh)
    bad = 0
    for y in range(ha):
        row = 3 * y * wa
        ty = (y // TILE) * tw
        sy = ((y + H) // TILE) * sw
        ra, rb = pa[row: row + 3 * wa], pb[row: row + 3 * wa]
        if ra == rb:
            continue
        for x in range(wa):
            j = 3 * x
            if (abs(ra[j] - rb[j]) > pixel_tol or abs(ra[j + 1] - rb[j + 1]) > pixel_tol
                    or abs(ra[j + 2] - rb[j + 2]) > pixel_tol):
                bad += 1
                tbad[ty + x // TILE] += 1
                sbad[sy + (x + H) // TILE] += 1
    worst, wt = 0.0, (0, 0)
    for t, k in enumerate(tbad):
        if k:
            tx, ty = t % tw, t // tw
            area = min(TILE, wa - tx * TILE) * min(TILE, ha - ty * TILE)
            if k / area > worst:
                worst, wt = k / area, (tx * TILE, ty * TILE)
    for t, k in enumerate(sbad):
        x0, y0 = (t % sw) * TILE - H, (t // sw) * TILE - H
        if k and x0 >= 0 and y0 >= 0 and x0 + TILE <= wa and y0 + TILE <= ha:
            if k / (TILE * TILE) > worst:
                worst, wt = k / (TILE * TILE), (x0, y0)
    return {"mae": [s / n for s in sums], "bad": bad / n, "tile": worst, "tile_at": wt}


def within(s, lim):
    return (max(s["mae"]) <= lim["max_channel_mae"] and s["bad"] <= lim["max_bad_fraction"]
            and s["tile"] <= lim["max_tile_bad_fraction"])


def fmt(s):
    return "mae %.2f/%.2f/%.2f bad %.4f tile %.3f@%d,%d" % (
        *s["mae"], s["bad"], s["tile"], *s["tile_at"])


def compare(img, ref, limits, masks):
    """(verdict, note): EXACT, CLOSE or FAIL."""
    note = ""
    if img[:2] != ref[:2]:
        w, h = min(img[0], ref[0]), min(img[1], ref[1])
        note = " size %dx%d vs %dx%d" % (img[0], img[1], ref[0], ref[1])
        img, ref = crop(img, w, h), crop(ref, w, h)
    img = apply_masks(img, ref, masks)
    if img[2] == ref[2]:
        return ("EXACT" if not note else "CLOSE"), "identical" + note
    s = stats(img, ref, limits["pixel_tol"])
    return ("CLOSE" if within(s, limits) else "FAIL"), fmt(s) + note


def compare_window(cands, ref, limits, masks):
    """The centre first; when it is not EXACT, every flip of the window, and
    the best one (smallest worst-channel mae) decides. A movie or a load on
    its own clock can put the frame a flip or two from the anchor's count;
    the shift is reported. Returns (verdict, note, shift)."""
    best = None
    for k, path in cands:
        img = read_image(path)
        v, note = compare(img, ref, limits, masks)
        if v == "EXACT":
            return v, note, k
        mae = max(float(x) for x in note.split()[1].split("/")) if note.startswith("mae") else 0.0
        rank = (0 if v == "CLOSE" else 1, mae, abs(k))
        if best is None or rank < best[0]:
            best = (rank, v, note, k)
    return best[1], best[2], best[3]


# ---- manifest helpers ------------------------------------------------------

def shot_index(g):
    """shot name -> (scene name, shot dict)."""
    out = {}
    for sn, sc in g["scenes"].items():
        for name, sh in sc["shots"].items():
            out[name] = (sn, sh)
    return out


def limits_for(g, shot, kind="same_backend"):
    lim = dict(g["limits"][kind])
    lim.update(shot.get("limits", {}).get(kind, {}))
    return lim


def run_shots(d):
    """The shots of a run directory: name -> (path, backend, anchor, offset)."""
    out = {}
    tsv = os.path.join(d, "shots.tsv")
    if not os.path.exists(tsv):
        return out
    with open(tsv) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 5:
                continue
            name, anchor, off, tgt, be = p[:5]
            path = os.path.join(d, "shots", name + ".bmp")
            if os.path.exists(path):
                cands = [(0, path)]
                wd = os.path.join(d, "shots", name)
                if os.path.isdir(wd):
                    for f in os.listdir(wd):
                        if f.endswith(".bmp"):
                            cands.append((int(f[:-4]), os.path.join(wd, f)))
                cands.sort(key=lambda c: (abs(c[0]), c[0]))
                out[name] = {"path": path, "backend": be, "anchor": int(anchor),
                             "offset": int(off), "flip": int(tgt), "window": cands}
    return out


def run_label(d):
    """A run directory as golden.json records it: relative to the repo, or
    its last two parts (no home paths in the manifest)."""
    a = os.path.abspath(d)
    if a.startswith(REPO + os.sep):
        return os.path.relpath(a, REPO)
    return os.path.join(*a.split(os.sep)[-2:])


def ref_path(g, backend, name):
    return os.path.join(golden_dir(g), backend, name + ".png")


# ---- commands --------------------------------------------------------------

def cmd_list(g, args):
    print("golden dir:", golden_dir(g))
    for be, col in g["backends"].items():
        print("column %-6s %s" % (be, col.get("status", "")))
    for sn, sc in g["scenes"].items():
        print("%s (%s)" % (sn, sc["driver"]))
        for name, sh in sc["shots"].items():
            refs = [be for be in g["backends"] if name in g.get("references", {}).get(be, {})]
            print("  %-16s %s + %d flips  refs: %s" % (
                name, sh["anchor"], sh["offset"], ",".join(refs) or "-"))


def cmd_capture(g, args):
    if not args:
        sys.exit("capture SCENE [--backend B] [--out DIR] [KEY=VALUE...]")
    scene, rest = args[0], args[1:]
    if scene not in g["scenes"]:
        sys.exit("no scene %r (golden.py list)" % scene)
    be, out, env = "metal", None, []
    it = iter(rest)
    for a in it:
        if a == "--backend":
            be = next(it)
        elif a == "--out":
            out = next(it)
        else:
            env.append(a)
    if not out:
        out = os.path.join(golden_dir(g), "runs", "%s-%s-%s" % (
            scene, be, time.strftime("%Y%m%d-%H%M%S")))
    out = os.path.abspath(out)
    e = dict(os.environ, CAPTURE="1", STOP_AT_END="1", RECOMP_PB_BACKEND=be)
    drv = os.path.join(HERE, g["scenes"][scene]["driver"])
    rc = subprocess.call([drv, out] + env, cwd=REPO, env=e)
    print("capture %s %s -> %s (rc %d)" % (scene, be, out, rc))
    return rc


def cmd_update(g, args):
    be_force, dirs = None, []
    it = iter(args)
    for a in it:
        if a == "--backend":
            be_force = next(it)
        else:
            dirs.append(a)
    idx = shot_index(g)
    refs = g.setdefault("references", {})
    n = 0
    for d in dirs:
        for name, r in sorted(run_shots(d).items()):
            if name not in idx:
                print("skip %s: not in golden.json" % name)
                continue
            be = be_force or r["backend"]
            sh = idx[name][1]
            if r["offset"] != sh["offset"]:
                sys.exit("%s: run took it at +%d, golden.json says +%d: driver and "
                         "manifest disagree" % (name, r["offset"], sh["offset"]))
            img = read_image(r["path"])
            dst = ref_path(g, be, name)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            write_png(dst, img)
            refs.setdefault(be, {})[name] = {
                "sha256": pixel_sha(img), "size": [img[0], img[1]],
                "from": run_label(d),
                "recorded": time.strftime("%Y-%m-%d"),
            }
            print("%-16s %-6s %s" % (name, be, dst))
            n += 1
    save(g)
    print("%d references written" % n)
    return 0


def check_pair(g, name, run, ref_be, kind):
    idx = shot_index(g)
    sh = idx[name][1]
    ref = g.get("references", {}).get(ref_be, {}).get(name)
    rp = ref_path(g, ref_be, name)
    if ref and pixel_sha(read_image(run["path"])) == ref["sha256"]:
        return "EXACT", "hash"
    if not os.path.exists(rp):
        return "MISSING", "no %s reference (%s)" % (ref_be, rp)
    v, note, k = compare_window(run["window"], read_image(rp), limits_for(g, sh, kind),
                                sh.get("masks", []))
    return v, note + ("  (window %+d)" % k if k else "")


def cmd_check(g, args):
    against, dirs = None, []
    it = iter(args)
    for a in it:
        if a == "--against":
            against = next(it)
        else:
            dirs.append(a)
    idx = shot_index(g)
    counts = {}
    for d in dirs:
        shots = run_shots(d)
        if not shots:
            print("%s: no shots (shots.tsv)" % d)
            counts["MISSING"] = counts.get("MISSING", 0) + 1
        for name, r in sorted(shots.items()):
            if name not in idx:
                continue
            sh = idx[name][1]
            ref_be = against or r["backend"]
            why = sh.get("skip", {}).get(r["backend"]) or sh.get("skip", {}).get(ref_be)
            if why:
                counts["SKIP"] = counts.get("SKIP", 0) + 1
                print("%-8s %-16s %s vs %s: %s" % ("SKIP", name, r["backend"], ref_be, why))
                continue
            kind = "same_backend" if ref_be == r["backend"] else "cross_backend"
            v, note = check_pair(g, name, r, ref_be, kind)
            if v in ("FAIL", "MISSING") and "video" in sh:
                v, note = video_verdict(g, name, sh, r)
                note = "vs the movie: " + note
            pair = "%s_vs_%s" % (r["backend"], ref_be)
            known = sh.get("known", {}).get(pair)
            if v == "FAIL" and known:
                v, note = "KNOWN", note + " -- " + known
            counts[v] = counts.get(v, 0) + 1
            print("%-8s %-16s %s vs %s: %s" % (v, name, r["backend"], ref_be, note))
    print(" ".join("%s %d" % kv for kv in sorted(counts.items())))
    if counts.get("FAIL"):
        return 1
    return 2 if counts.get("MISSING") else 0


def cmd_determinism(g, args):
    if len(args) != 2:
        sys.exit("determinism RUNDIR_A RUNDIR_B")
    a, b = run_shots(args[0]), run_shots(args[1])
    idx = shot_index(g)
    counts = {}
    for name in sorted(set(a) | set(b)):
        why = idx.get(name, (None, {}))[1].get("skip", {}).get(
            (a.get(name) or b.get(name))["backend"])
        if why:
            v, note = "SKIP", why
        elif name not in a or name not in b:
            v, note = "MISSING", "only in one run"
        else:
            sh = idx.get(name, (None, {}))[1]
            v, note, k = compare_window(b[name]["window"], read_image(a[name]["path"]),
                                        limits_for(g, sh, "same_backend") if name in idx
                                        else g["limits"]["same_backend"], sh.get("masks", []))
            if k:
                note += "  (window %+d)" % k
            fa, fb = a[name]["flip"] - a[name]["anchor"], b[name]["flip"] - b[name]["anchor"]
            note += "  (anchor flips %d / %d)" % (a[name]["anchor"], b[name]["anchor"])
            if fa != fb:
                note += " OFFSETS DIFFER"
        counts[v] = counts.get(v, 0) + 1
        print("%-8s %-16s %s" % (v, name, note))
    print(" ".join("%s %d" % kv for kv in sorted(counts.items())))
    return 1 if counts.get("FAIL") else (2 if counts.get("MISSING") else 0)


def cmd_diff(g, args):
    a, b = read_image(args[0]), read_image(args[1])
    tol = int(args[2]) if len(args) > 2 else g["limits"]["same_backend"]["pixel_tol"]
    if a[:2] != b[:2]:
        print("size %dx%d vs %dx%d; comparing the common part" % (a[0], a[1], b[0], b[1]))
        w, h = min(a[0], b[0]), min(a[1], b[1])
        a, b = crop(a, w, h), crop(b, w, h)
    print(fmt(stats(a, b, tol)))
    return 0


def movies(g):
    """movie -> list of (shot name, shot) that compare against it."""
    out = {}
    for sc in g["scenes"].values():
        for name, sh in sc["shots"].items():
            if "video" in sh:
                out.setdefault(sh["video"]["movie"], []).append((name, sh))
    return out


def xmv_dir(g, movie):
    return os.path.join(golden_dir(g), "xmv", os.path.splitext(os.path.basename(movie))[0])


def cmd_xmvref(g, args):
    for movie in movies(g):
        src = os.path.join(REPO, "Burnout 3 Takedown", movie)
        out = xmv_dir(g, movie)
        if os.path.isdir(out) and len(os.listdir(out)) > 1:
            print("%s: have %d frames" % (movie, len(os.listdir(out))))
            continue
        os.makedirs(out, exist_ok=True)
        # Resampled to a constant 29.97 fps (cri_rw30 has a variable frame
        # rate), so frame k is at k / 29.97 s from the movie's start.
        # Placed as the title shows its movies: scaled to 640x448 at y 16 in
        # a 640x464 frame (fitted against the Metal dumps: mean abs
        # difference 0.05-0.55 against ffmpeg's decode).
        pl = g["xmv_place"]
        vf = "fps=30000/1001,scale=%d:%d:flags=bilinear,pad=%d:%d:%d:%d" % (
            pl["w"], pl["h"], pl["frame"][0], pl["frame"][1], pl["x"], pl["y"])
        subprocess.check_call(["ffmpeg", "-loglevel", "error", "-i", src, "-vf", vf,
                               "-pix_fmt", "rgb24", os.path.join(out, "%05d.png")])
        print("%s: %d frames -> %s" % (movie, len(os.listdir(out)), out))
    return 0


def video_verdict(g, name, sh, r):
    """A movie shot against ffmpeg's frames of the same movie, the best within
    the window around its time: (verdict, note). The movie keeps its own
    clock, so a run that flipped slower (a loaded machine, a slow backend)
    lands a few movie frames on; the decode is what is judged."""
    v = sh["video"]
    fd = xmv_dir(g, v["movie"])
    if not os.path.isdir(fd):
        return "MISSING", "no movie frames (golden.py xmvref)"
    frames = sorted(os.listdir(fd))
    # Where in the movie the shot should be: the file opens at the anchor
    # and the title flips at 60 Hz (or the frame golden.json pins, for a
    # movie whose start lags).
    k0 = v.get("frame", int(round(r["offset"] / 60.0 * v["fps"])))
    win = v.get("window", 8)
    img = read_image(r["path"])
    lim = dict(g["limits"]["video"])
    lim.update(sh.get("limits", {}).get("video", {}))
    best = None
    for k in sorted(range(max(0, k0 - win), min(len(frames), k0 + win + 1)),
                    key=lambda k: abs(k - k0)):
        a, b = img, read_image(os.path.join(fd, frames[k]))
        if a[:2] != b[:2]:
            w, h = min(a[0], b[0]), min(a[1], b[1])
            a, b = crop(a, w, h), crop(b, w, h)
        st = stats(a, b, lim["pixel_tol"])
        if best is None or max(st["mae"]) < max(best[1]["mae"]):
            best = (k, st)
        if within(st, lim) and max(st["mae"]) < 1.0:
            break       # close enough; the window is slow in pure Python
    if best is None:
        return "MISSING", "no movie frames near %d" % k0
    return ("CLOSE" if within(best[1], lim) else "FAIL",
            "movie frame %d (expected ~%d, %+d): %s" % (best[0], k0, best[0] - k0, fmt(best[1])))


def cmd_xmvcheck(g, args):
    idx = shot_index(g)
    counts = {}
    for d in args:
        for name, r in sorted(run_shots(d).items()):
            sh = idx.get(name, (None, {}))[1]
            if "video" not in sh:
                continue
            vd, note = video_verdict(g, name, sh, r)
            counts[vd] = counts.get(vd, 0) + 1
            print("%-8s %-16s %s" % (vd, name, note))
    print(" ".join("%s %d" % kv for kv in sorted(counts.items())))
    return 1 if counts.get("FAIL") else (2 if counts.get("MISSING") else 0)


COMMANDS = {
    "list": cmd_list, "capture": cmd_capture, "update": cmd_update, "check": cmd_check,
    "determinism": cmd_determinism, "diff": cmd_diff, "xmvref": cmd_xmvref,
    "xmvcheck": cmd_xmvcheck,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__)
        return 2
    return COMMANDS[argv[1]](load(), argv[2:]) or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
