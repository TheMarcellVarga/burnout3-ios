#!/usr/bin/env python3
"""dsound_done_list.py <guestram.bin> [--core 0xADDR] [--max N]

Walks DirectSound's voice-done list in a hang report's guest RAM dump
(guestram.bin, written beside report.txt since BO-173) and says whether it
is sound.

The list is CMcpxCore+0x4A0 (a LIST_ENTRY). The APU interrupt's voice-done
path (sub_002F8644 -> sub_002FAAEF(1)) puts voice+0x54 on its end, and the
core's DPC (sub_002F8CA1 -> sub_002F8531) takes entries off the front and
calls the voice's notify method until the list is empty. An entry that
points at itself while the list still points at it is never taken off, and
the DPC loops on it: the BO-173 freeze.

Without --core the core is found from its DPC: a KDPC (type 0x13) at
core+0x4C8 whose routine is sub_002F8CA1 and whose context is the core.
In a hang report the DPC thread's esi is usually the core as well.

Addresses are guest addresses; RAM and its mirrors (0x80000000...) wrap at
the dump's size.
"""
import argparse
import struct
import sys

DPC_ROUTINE = 0x002F8CA1   # the core's deferred routine (Burnout 3 US)
CORE_DPC = 0x4C8           # KDPC inside the core
DONE_LIST = 0x4A0          # LIST_ENTRY head inside the core
VOICE_ENTRY = 0x54         # the voice's LIST_ENTRY on the done list
NOTIFY_SLOT = 0x18         # vtable slot the DPC calls


class Ram:
    def __init__(self, data):
        self.data = data
        self.size = len(data)

    def pa(self, va):
        if va >= 0xF0000000:
            return None
        if self.size & (self.size - 1) == 0:
            va &= self.size - 1
        return va if va + 4 <= self.size else None

    def u32(self, va):
        p = self.pa(va)
        if p is None:
            return None
        return struct.unpack_from("<I", self.data, p)[0]


def find_cores(ram):
    """Cores whose KDPC at +0x4C8 has the DirectSound routine."""
    pat = struct.pack("<I", DPC_ROUTINE)
    found = []
    start = 0
    while True:
        i = ram.data.find(pat, start)
        if i < 0:
            break
        start = i + 1
        dpc = i - 12                       # KDPC.DeferredRoutine is +12
        if dpc < 0 or dpc % 4:
            continue
        if struct.unpack_from("<H", ram.data, dpc)[0] != 0x13:
            continue
        ctx = struct.unpack_from("<I", ram.data, dpc + 16)[0]
        p = ram.pa(ctx)
        if p is not None and p + CORE_DPC == dpc:
            found.append(ctx)
    return found


def h(v):
    return "????????" if v is None else "%08X" % v


def walk(ram, core, limit):
    head = core + DONE_LIST
    hf, hb = ram.u32(head), ram.u32(head + 4)
    print("core %08X  done list head %08X  Flink %s  Blink %s" % (core, head, h(hf), h(hb)))
    if hf is None:
        print("  head not in the dump")
        return 2
    if hf == head:
        print("  empty (Blink %s)" % ("ok" if hb == head else "WRONG: " + h(hb)))
        return 0 if hb == head else 1
    bad = 0
    seen = {}
    prev = head
    node = hf
    n = 0
    while node != head and n < limit:
        f, b = ram.u32(node), ram.u32(node + 4)
        voice = node - VOICE_ENTRY
        vt = ram.u32(voice)
        notify = ram.u32(vt + NOTIFY_SLOT) if vt is not None else None
        notes = []
        if f == node:
            notes.append("SELF-LOOP: Flink is itself, so the DPC's unlink never takes it off")
        if b != prev:
            notes.append("Blink %s, expected %s" % (h(b), h(prev)))
        if node in seen:
            notes.append("CYCLE: already seen as node %d" % seen[node])
        print("  [%2d] node %08X  Flink %s  Blink %s  voice %08X  vtbl %s  notify %s%s"
              % (n, node, h(f), h(b), voice, h(vt), h(notify),
                 ("  <- " + "; ".join(notes)) if notes else ""))
        if notes:
            bad = 1
        if node in seen or f is None or f == node:
            break
        seen[node] = n
        prev, node = node, f
        n += 1
    if node == head:
        print("  back at the head after %d node(s); head Blink %s"
              % (n, "ok" if hb == prev else "WRONG: %s, last node %s" % (h(hb), h(prev))))
        if hb != prev:
            bad = 1
    elif n >= limit:
        print("  stopped after %d nodes" % limit)
        bad = 1
    print("  verdict: %s" % ("CORRUPT" if bad else "sound"))
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ram", help="guestram.bin from a hang report")
    ap.add_argument("--core", type=lambda s: int(s, 0), action="append",
                    help="CMcpxCore address (repeatable); default: found from its DPC")
    ap.add_argument("--max", type=int, default=512, help="most nodes to walk")
    a = ap.parse_args()
    with open(a.ram, "rb") as f:
        ram = Ram(f.read())
    cores = a.core or find_cores(ram)
    if not cores:
        print("no DirectSound core found (no KDPC with routine %08X); give --core"
              % DPC_ROUTINE)
        return 2
    rc = 0
    for c in cores:
        rc |= walk(ram, c, a.max)
    return rc


if __name__ == "__main__":
    sys.exit(main())
