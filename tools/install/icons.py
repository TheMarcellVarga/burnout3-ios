"""The icon, made from the user's own XBE: $$XTIMAGE (the 128x128 title image the
dashboard shows) and $$XSIMAGE (the 64x64 save image) -> PNG, .icns, .ico.

Both sections are an "XPR0" resource file holding one Direct3D texture:

    0x00 "XPR0"   0x04 total size   0x08 header size (the pixel data starts
    there, 0x800 in practice)       0x0C D3D texture header: common u32,
    data u32, lock u32, format u32, size u32
    format: bits 8..15 D3DFORMAT (0x0C DXT1, 0x0E DXT3, 0x0F DXT5),
            bits 20..23 log2(width), bits 24..27 log2(height)

Block-compressed Xbox textures are stored linear (not swizzled), so decoding
is the PC DXT algorithm. Burnout 3's title image is DXT1.

Nothing here is shipped: the images are produced on the user's machine from
the user's disc, the way the game data is. Standard library only (zlib for
PNG); resizing is done here so the installer needs no Pillow.
"""

import struct
import zlib

D3DFMT = {0x0C: "DXT1", 0x0E: "DXT3", 0x0F: "DXT5"}


class IconError(Exception):
    pass


# --------------------------------------------------------------------- decode
def _rgb565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def _color_block(blk, dxt1):
    """16 (r, g, b, a) pixels of the 8-byte colour half of a DXT block."""
    c0, c1, bits = struct.unpack("<HHI", blk)
    p0, p1 = _rgb565(c0), _rgb565(c1)
    if c0 > c1 or not dxt1:
        pal = [p0 + (255,), p1 + (255,),
               tuple((2 * a + b) // 3 for a, b in zip(p0, p1)) + (255,),
               tuple((a + 2 * b) // 3 for a, b in zip(p0, p1)) + (255,)]
    else:                       # DXT1 3-colour mode: index 3 is transparent
        pal = [p0 + (255,), p1 + (255,),
               tuple((a + b) // 2 for a, b in zip(p0, p1)) + (255,),
               (0, 0, 0, 0)]
    return [pal[(bits >> (2 * i)) & 3] for i in range(16)]


def _alpha_dxt3(blk):
    a = struct.unpack("<Q", blk)[0]
    return [((a >> (4 * i)) & 15) * 17 for i in range(16)]


def _alpha_dxt5(blk):
    a0, a1 = blk[0], blk[1]
    bits = int.from_bytes(blk[2:8], "little")
    if a0 > a1:
        pal = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
    else:
        pal = [a0, a1] + [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
    return [pal[(bits >> (3 * i)) & 7] for i in range(16)]


def decode_xpr(section):
    """-> (width, height, rgba bytes) for an XPR0 section holding one DXT texture."""
    if len(section) < 0x20 or section[:4] != b"XPR0":
        raise IconError("not an XPR0 resource")
    total, header = struct.unpack_from("<II", section, 4)
    fmt = struct.unpack_from("<I", section, 0x18)[0]
    code = (fmt >> 8) & 0xFF
    w, h = 1 << ((fmt >> 20) & 15), 1 << ((fmt >> 24) & 15)
    if code not in D3DFMT:
        raise IconError("unsupported texture format 0x%02X in the XPR0 header" % code)
    if w % 4 or h % 4:
        raise IconError("texture size %dx%d is not a multiple of the block size" % (w, h))
    bsize = 8 if code == 0x0C else 16
    need = (w // 4) * (h // 4) * bsize
    if header + need > len(section):
        raise IconError("XPR0 data is shorter than its header says")
    out = bytearray(w * h * 4)
    pos = header
    for by in range(h // 4):
        for bx in range(w // 4):
            if code == 0x0C:
                px = _color_block(section[pos:pos + 8], True)
            else:
                alpha = (_alpha_dxt3 if code == 0x0E else _alpha_dxt5)(section[pos:pos + 8])
                px = [c[:3] + (a,) for c, a in zip(_color_block(section[pos + 8:pos + 16], False), alpha)]
            pos += bsize
            for i, (r, g, b, a) in enumerate(px):
                o = ((by * 4 + i // 4) * w + bx * 4 + i % 4) * 4
                out[o:o + 4] = bytes((r, g, b, a))
    return w, h, bytes(out)


# --------------------------------------------------------------------- resize
def resize(rgba, w, h, nw, nh):
    """Resample RGBA: area average when shrinking, bilinear when growing;
    premultiplied so transparent pixels do not bleed."""
    if (w, h) == (nw, nh):
        return rgba
    px = []
    for i in range(0, len(rgba), 4):
        r, g, b, a = rgba[i:i + 4]
        px.append((r * a / 255.0, g * a / 255.0, b * a / 255.0, float(a)))
    out = bytearray(nw * nh * 4)
    sx, sy = w / nw, h / nh
    for y in range(nh):
        for x in range(nw):
            if sx > 1 or sy > 1:                       # box over the source footprint
                x0, x1 = x * sx, (x + 1) * sx
                y0, y1 = y * sy, (y + 1) * sy
                acc, wsum = [0.0] * 4, 0.0
                for yy in range(int(y0), min(h, int(y1) + 1)):
                    wy = min(yy + 1, y1) - max(yy, y0)
                    if wy <= 0:
                        continue
                    for xx in range(int(x0), min(w, int(x1) + 1)):
                        wx = min(xx + 1, x1) - max(xx, x0)
                        if wx <= 0:
                            continue
                        p, wt = px[yy * w + xx], wx * wy
                        for k in range(4):
                            acc[k] += p[k] * wt
                        wsum += wt
                c = [v / wsum for v in acc]
            else:                                      # bilinear
                fx = min(max((x + 0.5) * sx - 0.5, 0), w - 1)
                fy = min(max((y + 0.5) * sy - 0.5, 0), h - 1)
                x0, y0 = int(fx), int(fy)
                x1, y1 = min(x0 + 1, w - 1), min(y0 + 1, h - 1)
                tx, ty = fx - x0, fy - y0
                c = [(px[y0 * w + x0][k] * (1 - tx) + px[y0 * w + x1][k] * tx) * (1 - ty)
                     + (px[y1 * w + x0][k] * (1 - tx) + px[y1 * w + x1][k] * tx) * ty
                     for k in range(4)]
            if c[3] > 0:
                o = (y * nw + x) * 4
                out[o:o + 4] = bytes((min(255, round(c[0] * 255 / c[3])),
                                      min(255, round(c[1] * 255 / c[3])),
                                      min(255, round(c[2] * 255 / c[3])),
                                      min(255, round(c[3]))))
    return bytes(out)


# --------------------------------------------------------------------- encode
def png_bytes(rgba, w, h):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def ico_bytes(frames):
    """frames: [(size, rgba)]; PNG frames from 128 up, 32-bit DIB below (which
    every Windows version reads)."""
    body, entries = [], []
    offset = 6 + 16 * len(frames)
    for size, rgba in frames:
        if size >= 128:
            data = png_bytes(rgba, size, size)
        else:
            rows = []
            for y in range(size - 1, -1, -1):                     # bottom-up BGRA
                row = rgba[y * size * 4:(y + 1) * size * 4]
                rows.append(b"".join(bytes((row[i + 2], row[i + 1], row[i], row[i + 3]))
                                     for i in range(0, len(row), 4)))
            mask = b"\0" * (((size + 31) // 32) * 4 * size)      # alpha does the masking
            data = (struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
                    + b"".join(rows) + mask)
        entries.append(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32,
                                   len(data), offset))
        offset += len(data)
        body.append(data)
    return struct.pack("<HHH", 0, 1, len(frames)) + b"".join(entries) + b"".join(body)


# type -> pixel size. ic13 is 128@2x, ic12 is 32@2x, ic11 is 16@2x, and so on.
ICNS_TYPES = ((b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128),
              (b"ic08", 256), (b"ic11", 32), (b"ic12", 64), (b"ic13", 256))


def icns_bytes(frames_by_size):
    """frames_by_size: {pixel size: rgba}. PNG payloads, as macOS 10.7+ reads."""
    chunks = []
    for tag, size in ICNS_TYPES:
        if size in frames_by_size:
            png = png_bytes(frames_by_size[size], size, size)
            chunks.append(tag + struct.pack(">I", 8 + len(png)) + png)
    body = b"".join(chunks)
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


# ---------------------------------------------------------------------- driver
SIZES = (16, 32, 48, 64, 128, 256)


def make_icons(xbe, out_dir, progress=None):
    """Write the icon set for `xbe` (an xbe.Xbe) into out_dir. Returns a dict of
    kind -> path. Raises IconError when the XBE has no usable title image."""
    import os
    os.makedirs(out_dir, exist_ok=True)
    section = xbe.section("$$XTIMAGE")
    if section is None:
        raise IconError("the XBE has no $$XTIMAGE section")
    w, h, rgba = decode_xpr(section)
    if w != h:
        raise IconError("title image is %dx%d, not square" % (w, h))
    frames = {s: resize(rgba, w, h, s, s) for s in SIZES}
    frames[w] = rgba
    paths = {}

    def write(name, data, kind):
        p = os.path.join(out_dir, name)
        with open(p, "wb") as f:
            f.write(data)
        paths[kind] = p
        if progress:
            progress(len(paths) / 8.0)

    write("title-%d.png" % w, png_bytes(rgba, w, h), "title_png")
    for s in (64, 256):
        write("icon-%d.png" % s, png_bytes(frames[s], s, s), "png%d" % s)
    write("AppIcon.icns", icns_bytes(frames), "icns")
    write("AppIcon.ico", ico_bytes([(s, frames[s]) for s in SIZES]), "ico")
    save = xbe.section("$$XSIMAGE")
    if save:
        try:
            sw, sh, srgba = decode_xpr(save)
            write("save-%d.png" % sw, png_bytes(srgba, sw, sh), "save_png")
        except IconError:
            pass                      # the save image is a nicety, never a failure
    return paths
