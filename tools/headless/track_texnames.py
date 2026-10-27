#!/usr/bin/env python3
"""track_texnames.py [<game dir>] > texnames.tsv   (BO-204)

Every texture of the tracks' .dat files (Tracks/<region>/<track>/) with the
hash the toolkit's nv2a_texrep registers it by (texrep_dump's hash: level 0
of the title's bytes, nv2a_tex_hash), its name, size and NV2A format, and
the tracks that carry those bytes. A record is <format u32> <w u32> <h u32>
<8 bytes> <name, 32 bytes> <24 bytes> <data>. For finding a decal's hash by
its name (the LED signs' words: Chgo_AccidentSign_Words) without a run.
"""
import glob
import re
import struct
import sys

M = (1 << 64) - 1
P = 0x100000001B3
SEED = 0xCBF29CE484222325


def tex_hash(b):
    l = [SEED, SEED ^ 1, SEED ^ 2, SEED ^ 3]
    n = len(b) // 32 * 32
    ws = struct.unpack_from("<%dQ" % (n // 8), b)
    for j in range(0, len(ws), 4):
        for k in range(4):
            l[k] = ((l[k] ^ ws[j + k]) * P) & M
    for c in b[n:]:
        l[0] = ((l[0] ^ c) * P) & M
    return ((l[0] ^ (l[1] << 1) ^ (l[2] << 2) ^ (l[3] << 3)) * P) & M


BPP = {0x0C: 0.5, 0x0E: 1, 0x0F: 1, 0x06: 4, 0x07: 4, 0x0B: 1, 0x04: 2, 0x05: 2, 0x02: 2,
       0x03: 2, 0x19: 1, 0x00: 1, 0x01: 1, 0x1A: 2}
POW2 = {1 << i for i in range(11)}
root = (sys.argv[1] if len(sys.argv) > 1 else "Burnout 3 Takedown").rstrip("/") + "/Tracks/"
out = {}
for f in sorted(glob.glob(root + "*/*/*.dat")):
    tr = f[len(root):].rsplit("/", 1)[0]
    d = open(f, "rb").read()
    for m in re.finditer(rb"[\x20-\x7e]{3,31}\x00", d):
        p = m.start()
        if p < 20:
            continue
        fmt, w, h = struct.unpack_from("<III", d, p - 20)
        if fmt not in BPP or w not in POW2 or h not in POW2:
            continue
        dxt = fmt in (0x0C, 0x0E, 0x0F)
        n = int(max(w, 4 if dxt else 1) * max(h, 4 if dxt else 1) * BPP[fmt])
        if p + 56 + n > len(d):
            continue
        key = (tex_hash(d[p + 56:p + 56 + n]), m.group()[:-1].decode(), w, h, fmt)
        out.setdefault(key, set()).add(tr)
for (hv, name, w, h, fmt), trs in sorted(out.items(), key=lambda x: x[0][1]):
    print("%016x\t%s\t%dx%d\tf%02x\t%s" % (hv, name, w, h, fmt, " ".join(sorted(trs))))
