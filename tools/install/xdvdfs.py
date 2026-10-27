"""XDVDFS (Xbox DVD filesystem) reader: list and extract a disc image.

Written for the installer from the format itself, standard library only. No
code was taken from the Xerenge installer (its repository carries no licence
file, so only the list of partition offsets it probes was noted) or from the
toolkit's tools/xiso (MIT; does the same job and is the place to compare if
this ever disagrees with it).

Format, all little-endian, 2048-byte sectors:

* Sector 32 of the *game partition* is the volume descriptor: the 20 bytes
  "MICROSOFT*XBOX*MEDIA", the root directory's start sector (u32 at 0x14) and
  its size in bytes (u32 at 0x18), and the same magic again at 0x7EC.
* A directory is a binary search tree stored in a flat table. Each entry:
  left u16, right u16 (both in dwords from the table start; 0 = none),
  start sector u32, size u32, attributes u8 (0x10 = directory), name length u8,
  then the name. Entries are padded to 4 bytes with 0xFF. A slot whose left
  field is 0xFFFF is empty padding.
* A redump of a retail disc is the whole DVD: a video partition first, then the
  game partition at a fixed byte offset. Which offset depends on the dump, so
  the descriptor is looked for at each known base.
"""

import os
import struct

SECTOR = 2048
MAGIC = b"MICROSOFT*XBOX*MEDIA"
ATTR_DIRECTORY = 0x10

# Byte offsets of the game partition in the layouts seen in the wild:
#   0x00000000  an xiso / trimmed image: the partition is the whole file
#   0x0000FD90, 0x00002080, 0x00030600  rebuilt or odd images (Xerenge's reader
#               and the toolkit's each know some of these; this is the union)
#   0x0FD90000  XGD2 (Xbox 360 disc, back-compat)
#   0x18300000  redump of an original-Xbox disc: ~387 MB video partition, then
#               the game partition (descriptor at 0x18310000)
#   0x1FB20000  XGD3
# The descriptor's magic is checked at both ends, so a wrong guess is cheap.
BASES = (0x00000000, 0x0000FD90, 0x00002080, 0x00030600,
         0x0FD90000, 0x18300000, 0x1FB20000)


class XdvdfsError(Exception):
    pass


class Entry:
    __slots__ = ("name", "sector", "size", "attributes", "path")

    def __init__(self, name, sector, size, attributes, path):
        self.name = name
        self.sector = sector
        self.size = size
        self.attributes = attributes
        self.path = path        # "dir/sub/name", forward slashes, no leading slash

    @property
    def is_dir(self):
        return bool(self.attributes & ATTR_DIRECTORY)


def _safe_name(name):
    """A name from the image is data, not a path: refuse separators and dots."""
    if (not name or name in (".", "..") or "/" in name or "\\" in name
            or "\0" in name or ":" in name):
        raise XdvdfsError("unsafe file name in the image: %r" % name)
    return name


class Image:
    """An opened disc image. Use as a context manager."""

    def __init__(self, path):
        self.path = path
        self._f = open(path, "rb")
        self.file_size = os.fstat(self._f.fileno()).st_size
        self.base = None
        for base in BASES:
            if self._has_descriptor(base):
                self.base = base
                break
        if self.base is None:
            self._f.close()
            raise XdvdfsError("%s is not an Xbox disc image (no XDVDFS volume "
                              "descriptor at any known partition offset)" % path)
        d = self._read(32 * SECTOR, SECTOR)
        self.root_sector, self.root_size = struct.unpack_from("<II", d, 0x14)
        if self.root_size == 0 or self.root_size > 64 * 1024 * 1024:
            raise XdvdfsError("implausible root directory size %d" % self.root_size)

    def close(self):
        self._f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    # -- low level ----------------------------------------------------------
    def _has_descriptor(self, base):
        off = base + 32 * SECTOR
        if off + SECTOR > self.file_size:
            return False
        self._f.seek(off)
        d = self._f.read(SECTOR)
        return d[:20] == MAGIC and d[0x7EC:0x7EC + 20] == MAGIC

    def _read(self, part_offset, size):
        """`size` bytes at a byte offset counted from the game partition."""
        self._f.seek(self.base + part_offset)
        data = self._f.read(size)
        if len(data) != size:
            raise XdvdfsError("the image ends early (truncated download or copy?)")
        return data

    # -- directories --------------------------------------------------------
    def listdir(self, dir_path=""):
        """Entries of a directory ("" = root), sorted by name."""
        if dir_path:
            entry = self.find(dir_path)
            if entry is None or not entry.is_dir:
                raise XdvdfsError("no such directory: " + dir_path)
            return self._read_table(entry.sector, entry.size, entry.path)
        return self._read_table(self.root_sector, self.root_size, "")

    def _read_table(self, sector, size, prefix):
        if size == 0:
            return []
        table = self._read(sector * SECTOR, size)
        out, seen, todo = [], set(), [0]
        while todo:
            off = todo.pop() * 4
            if off in seen or off + 14 > len(table):
                continue
            seen.add(off)
            left, right, start, length, attr, nlen = struct.unpack_from("<HHIIBB", table, off)
            if left == 0xFFFF:                  # padding, not an entry
                continue
            name = _safe_name(table[off + 14:off + 14 + nlen].decode("latin-1"))
            out.append(Entry(name, start, length, attr,
                             prefix + "/" + name if prefix else name))
            if left:
                todo.append(left)
            if right:
                todo.append(right)
        out.sort(key=lambda e: e.name.lower())
        return out

    def find(self, path):
        """The entry at `path` (case-insensitive, either slash), or None."""
        parts = [p for p in path.replace("\\", "/").split("/") if p]
        entries = self.listdir("")
        entry = None
        for i, part in enumerate(parts):
            entry = next((e for e in entries if e.name.lower() == part.lower()), None)
            if entry is None:
                return None
            if i < len(parts) - 1:
                if not entry.is_dir:
                    return None
                entries = self._read_table(entry.sector, entry.size, entry.path)
        return entry

    def walk(self, dir_path=""):
        """Yield every file entry below `dir_path`, depth first."""
        for e in self.listdir(dir_path):
            if e.is_dir:
                yield from self.walk(e.path)
            else:
                yield e

    # -- reading files ------------------------------------------------------
    def read(self, entry, limit=None):
        n = entry.size if limit is None else min(limit, entry.size)
        return self._read(entry.sector * SECTOR, n)

    def copy_to(self, entry, dest, progress=None, chunk=4 * 1024 * 1024):
        """Write a file to `dest` through dest + ".part", renamed when whole, so
        a killed run never leaves a half file that looks finished."""
        tmp = dest + ".part"
        left = entry.size
        self._f.seek(self.base + entry.sector * SECTOR)
        with open(tmp, "wb") as out:
            while left > 0:
                data = self._f.read(min(chunk, left))
                if not data:
                    raise XdvdfsError("the image ends inside " + entry.path)
                out.write(data)
                left -= len(data)
                if progress:
                    progress(len(data))
        os.replace(tmp, dest)
