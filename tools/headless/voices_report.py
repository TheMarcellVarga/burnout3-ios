#!/usr/bin/env python3
"""voices_report.py <rundir | log.txt>... [--from <regex>]

Counts the APU's active voices in a run made with RECOMP_TRACE=apu (BO-116,
docs/split-screen.md). The voice processor prints, every 60 of its frames
(0.32 s), one "[APU] voice N pos=a/b" line per active voice, and every 1500
frames one "[APU-VSTAT]" line per voice that played, with its format (stream
or buffer, stereo) and the RMS of what it produced.

Per run, from the first log line matching --from on (default: the stage's
streamed.dat, i.e. the race): the batches seen, the active voices per batch
(least, median, most) against the hardware's 256, the 3D voices among them
(numbers below 64, of the hardware's 64), and the stream voices (the music
player's and the films') with the reports in which they sounded and their
loudest RMS.
"""
import os
import re
import sys

VOICE = re.compile(r"\[APU\] voice (\d+) pos=")
STAT = re.compile(r"\[APU-VSTAT\] t=(\d+)s v=(\d+) fmt=\w+ stream=(\d) st=(\d)"
                  r".*? frames=(\d+) rms=(\d+)")


def report(path, start):
    if os.path.isdir(path):
        path = os.path.join(path, "log.txt")
    batches, cur, on = [], set(), False
    streams, others, nstat = {}, {}, 0
    with open(path, errors="replace") as f:
        for line in f:
            if not on:
                on = re.search(start, line) is not None
                continue
            m = VOICE.search(line)
            if m:
                v = int(m.group(1))
                if v in cur:            # the next batch begins
                    batches.append(cur)
                    cur = set()
                cur.add(v)
                continue
            m = STAT.search(line)
            if m:
                t, v, stream, st, frames, rms = map(int, m.groups())
                nstat += 1
                d = streams if stream else others
                e = d.setdefault(v, [0, 0, st])
                if rms > 0:
                    e[0] += 1
                e[1] = max(e[1], rms)
    if cur:
        batches.append(cur)
    print(f"== {path}")
    if not batches:
        print("  no [APU] voice lines after the start (RECOMP_TRACE=apu?)")
        return
    n = sorted(len(b) for b in batches)
    n3 = sorted(sum(1 for v in b if v < 64) for b in batches)
    print(f"  {len(batches)} batches; active voices least {n[0]}, median "
          f"{n[len(n) // 2]}, most {n[-1]} of 256; 3D voices least {n3[0]}, "
          f"median {n3[len(n3) // 2]}, most {n3[-1]} of 64")
    print(f"  buffer voices that sounded: {sum(1 for e in others.values() if e[0])}"
          f" (loudest RMS {max([e[1] for e in others.values()] or [0])})")
    if not streams:
        print("  stream voices: none")
    for v, (k, rms, st) in sorted(streams.items()):
        print(f"  stream voice {v}{' stereo' if st else ''}: sounded in {k} "
              f"reports, loudest RMS {rms}")


def main():
    args, start = [], r"streamed[.]dat"
    it = iter(sys.argv[1:])
    for a in it:
        if a == "--from":
            start = next(it)
        else:
            args.append(a)
    if not args:
        sys.exit(__doc__)
    for p in args:
        report(p, start)


if __name__ == "__main__":
    main()
