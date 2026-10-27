#!/usr/bin/env python3
"""pcache_keys.py: look at, compare and merge a backend's key lists (BO-208).

  pcache_keys.py <list> [<list>]
      Counts the keys of each kind in a key list (metal_pipelines.bin,
      vk_pipelines.bin, gaps_vulkan.bin, gaps_metal.bin: the keys the render thread
      had to build in a real run, BO-208; also an input of `manifest`: the toolkit's src/d3d/nv2a_pcache.h). With
      two lists: the keys only one of them has, and exit status 1 when the
      two sets differ. (docs/shader-prebuild.md)

  pcache_keys.py manifest -o <manifest> --rev <name> [--base <manifest>] <list>...
      The union of the lists as the shipped coverage manifest
      (graphics/pipelines-<backend>.manifest): vertex programs by the 64-bit
      hash of their slots (record type 16; the microcode itself is title code
      and is left out), combiner states and pipeline keys as they are. With
      --base: the keys of that manifest are kept too (the manifest only
      grows), and what is new and what a list lacks are printed. A vertex
      program a key names that is not in a list's vertex records stays a
      hash-less pipeline key and is reported.

  pcache_keys.py info <manifest>
      Counts of a manifest and its revision.

The key lists are the title's data; this prints counts and hashes only.
"""
import struct
import sys

KIND = {0: 'vertex', 1: 'fragment', 2: 'pipeline', 3: 'fragment-hdr', 16: 'vertex-hash'}
FNV_INIT = 0xcbf29ce484222325
FNV_PRIME = 0x100000001b3
M64 = (1 << 64) - 1
MAGIC = b'XRPCACHE'
VS_HASH = 16


def fnv64(b, h=FNV_INIT):
    for c in b:
        h = ((h ^ c) * FNV_PRIME) & M64
    return h


def rec_sum(kind, data):
    h = fnv64(struct.pack('<I', kind))
    h = fnv64(struct.pack('<I', len(data)), h)
    h = fnv64(data, h)
    return h or 1


def read(path):
    """-> (version, [(kind, data)]); records in order, a torn tail dropped."""
    b = open(path, 'rb').read()
    if len(b) < 16 or b[:8] != MAGIC:
        raise SystemExit(f'{path}: not a key list')
    fmt, n = struct.unpack_from('<II', b, 8)
    version = b[16:16 + n].decode('ascii', 'replace')
    off, recs, seen = 16 + n, [], set()
    while off + 16 <= len(b):
        kind, ln, h = struct.unpack_from('<IIQ', b, off)
        if off + 16 + ln > len(b):
            break
        data = b[off + 16:off + 16 + ln]
        if rec_sum(kind, data) != h:
            break
        if h not in seen:
            seen.add(h)
            recs.append((kind, data))
        off += 16 + ln
    return version, recs


def write(path, version, recs):
    v = version.encode('ascii')
    out = bytearray(MAGIC + struct.pack('<II', 1, len(v)) + v)
    for kind, data in recs:
        out += struct.pack('<IIQ', kind, len(data), rec_sum(kind, data)) + data
    open(path, 'wb').write(bytes(out))


def counts(recs):
    c = {}
    for kind, _ in recs:
        c[kind] = c.get(kind, 0) + 1
    return ', '.join(f'{c.get(k, 0)} {KIND.get(k, k)}' for k in sorted(set(c) | {0, 1, 2}))


def keyset(recs):
    return {(k, rec_sum(k, d)): len(d) for k, d in recs}


def cmd_compare(argv):
    lists = [read(p) for p in argv]
    for p, (version, recs) in zip(argv, lists):
        print(f'{p}: {counts(recs)} [{version}]')
    if len(lists) == 1:
        return 0
    a, b = keyset(lists[0][1]), keyset(lists[1][1])
    if lists[0][0] != lists[1][0]:
        print('the two lists are of different key formats')
        return 1
    only_a, only_b = sorted(set(a) - set(b)), sorted(set(b) - set(a))
    for name, only, src in (('first', only_a, a), ('second', only_b, b)):
        for kind, h in only:
            print(f'only in the {name}: {KIND.get(kind, kind)} {h:016x} ({src[(kind, h)]} bytes)')
    print(f'{len(set(a) & set(b))} keys in both, {len(only_a)} only in the first, '
          f'{len(only_b)} only in the second')
    return 1 if only_a or only_b else 0


def cmd_manifest(argv):
    out = rev = base = None
    lists = []
    i = 0
    while i < len(argv):
        if argv[i] == '-o':
            out = argv[i + 1]; i += 2
        elif argv[i] == '--rev':
            rev = argv[i + 1]; i += 2
        elif argv[i] == '--base':
            base = argv[i + 1]; i += 2
        else:
            lists.append(argv[i]); i += 1
    if not out or not rev or not lists:
        print(__doc__)
        return 2
    version = None
    merged = {}          # (kind, payload) -> first seen, vs as hash
    order = []
    vs_hashes = set()
    named_vs = set()     # vs ids pipelines name
    missing = 0

    def add(kind, data):
        key = (kind, data)
        if key not in merged:
            merged[key] = True
            order.append(key)

    old = set()
    if base:
        bv, brecs = read(base)
        version = bv.split('; manifest ')[0]
        for kind, data in brecs:
            old.add((kind, data))
            add(kind, data)
    for p in lists:
        v, recs = read(p)
        v = v.split('; manifest ')[0].split('; toolkit ')[0].split('; gaps')[0]
        if version is None:
            version = v
        elif v != version:
            raise SystemExit(f'{p}: key format [{v}] is not [{version}]')
        for kind, data in recs:
            if kind == 0:
                add(VS_HASH, struct.pack('<Q', fnv64(data)))
            elif kind in (1, 2, 3, VS_HASH):
                add(kind, data)
    recs = [(k, d) for k, d in order]
    # A pipeline names its vertex program by the id the backend gives it:
    # fnv64 of the slots (the same hash, +3 when it is 0..2). Report pipelines
    # that name one the manifest has no hash for.
    vsh = {struct.unpack('<Q', d)[0] for k, d in recs if k == VS_HASH}
    pso_vs = {struct.unpack_from('<Q', d, 0)[0] for k, d in recs if k == 2 and len(d) >= 8}
    for h in pso_vs:
        if h > 2 and h not in vsh:
            missing += 1
    write(out, f'{version}; manifest {rev}', recs)
    new = [(k, d) for k, d in recs if (k, d) not in old]
    print(f'{out}: {counts(recs)} [{version}; manifest {rev}]')
    if base:
        print(f'{len(new)} new against {base} ({counts(new)}); nothing was dropped')
    if missing:
        print(f'{missing} pipelines name a vertex program that is in no list (built-in or run-time'
              f' assembled: they stay unresolved on a player\'s machine)')
    return 0


def cmd_info(argv):
    v, recs = read(argv[0])
    print(f'{argv[0]}: {counts(recs)} [{v}]')
    return 0


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 2
    if argv[0] == 'manifest':
        return cmd_manifest(argv[1:])
    if argv[0] == 'info':
        return cmd_info(argv[1:])
    if len(argv) not in (1, 2):
        print(__doc__)
        return 2
    return cmd_compare(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
