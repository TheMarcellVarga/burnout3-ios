#!/usr/bin/env python3
"""make_ico.py <out.ico> <png>...: a Windows icon from square PNGs of the
sizes it should hold (16 to 256). Each image is stored as the PNG it is,
which Windows Vista and later, llvm-rc/windres and Inno Setup read; the
standard library is all it needs."""
import struct
import sys


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise SystemExit("not a PNG")
    return struct.unpack(">II", data[16:24])


def main(out, pngs):
    images = []
    for p in pngs:
        data = open(p, "rb").read()
        w, h = png_size(data)
        if w != h or not 16 <= w <= 256:
            raise SystemExit("%s: %dx%d is not a square of 16 to 256 pixels" % (p, w, h))
        images.append((w, data))
    images.sort()
    offset = 6 + 16 * len(images)
    head = struct.pack("<HHH", 0, 1, len(images))
    body = b""
    for w, data in images:
        head += struct.pack("<BBBBHHII", w & 255, w & 255, 0, 0, 1, 32, len(data), offset + len(body))
        body += data
    open(out, "wb").write(head + body)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2:])
