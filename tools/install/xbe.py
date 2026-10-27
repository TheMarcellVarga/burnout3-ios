"""Just enough of the Xbox executable (XBE) format for the installer: identify a
default.xbe and pull a named section out of it. Standard library only.

Layout used (all little-endian; addresses are virtual, file offset =
address - base for anything inside the header block):

    0x000  "XBEH"
    0x104  base address                  0x118  certificate address
    0x108  size of headers               0x11C  number of sections
    0x10C  size of image                 0x120  section headers address
    0x128  entry point, XOR-encoded (retail key 0xA8FC57AB, debug 0x94859D4B)

    certificate: +0x08 title id, +0x0C title name (UTF-16, 40 chars),
                 +0xA0 game region (1 NA, 2 Japan, 4 Rest of World)
    section header (0x38 bytes): flags, virtual address, virtual size, raw
                 address, raw size, name address, ... (digest, 20 bytes)
"""

import hashlib
import struct

ENTRY_KEYS = {"retail": 0xA8FC57AB, "debug": 0x94859D4B}
REGIONS = {1: "North America", 2: "Japan", 4: "Rest of World"}


class XbeError(Exception):
    pass


class Section:
    __slots__ = ("name", "flags", "vaddr", "vsize", "raddr", "rsize")


class Xbe:
    def __init__(self, data):
        if len(data) < 0x178 or data[:4] != b"XBEH":
            raise XbeError("not an Xbox executable (no XBEH header)")
        self.data = data
        (self.base, self.size_of_headers, self.size_of_image, _, self.timestamp,
         cert, nsec, sechdr) = struct.unpack_from("<8I", data, 0x104)
        coded = struct.unpack_from("<I", data, 0x128)[0]
        self.entry = None
        self.kind = None
        for kind, key in ENTRY_KEYS.items():
            if self.base <= coded ^ key < self.base + self.size_of_image:
                self.entry, self.kind = coded ^ key, kind
                break
        c = cert - self.base
        if not 0 <= c <= len(data) - 0xB0:
            raise XbeError("certificate outside the file")
        self.title_id = struct.unpack_from("<I", data, c + 8)[0]
        self.title_name = (data[c + 0x0C:c + 0x5C].decode("utf-16le", "replace")
                           .split("\0")[0])
        self.region = struct.unpack_from("<I", data, c + 0xA0)[0]
        if not 0 < nsec < 4096:
            raise XbeError("implausible section count %d" % nsec)
        self.sections = []
        for i in range(nsec):
            o = sechdr - self.base + i * 0x38
            if o < 0 or o + 0x38 > len(data):
                raise XbeError("section header %d outside the file" % i)
            s = Section()
            s.flags, s.vaddr, s.vsize, s.raddr, s.rsize, name = struct.unpack_from("<6I", data, o)
            n = name - self.base
            if not 0 <= n < len(data):
                raise XbeError("section %d has no readable name" % i)
            s.name = data[n:n + 32].split(b"\0")[0].decode("latin-1")
            self.sections.append(s)

    def section(self, name):
        """The raw bytes of the section called `name`, or None."""
        for s in self.sections:
            if s.name == name:
                if s.raddr + s.rsize > len(self.data):
                    raise XbeError("section %s runs past the end of the file" % name)
                return self.data[s.raddr:s.raddr + s.rsize]
        return None

    def describe(self):
        return {
            "title": self.title_name,
            "title_id": "0x%08X" % self.title_id,
            "region": REGIONS.get(self.region, "0x%X" % self.region),
            "base": "0x%X" % self.base,
            "entry": None if self.entry is None else "0x%08X" % self.entry,
            "size": len(self.data),
            "sections": len(self.sections),
        }


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()
