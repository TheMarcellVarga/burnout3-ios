#!/usr/bin/env python3
"""Frame-time statistics per game state of a Windows (or any) run.

    RECOMP_TRACE=pacing=all,pcache,frametime=ft.csv RECOMP_STDIO_LOG=log.txt \\
        ./burnout3.exe          (play-trace.cmd, or tools/headless/to_race.sh; docs/windows.md)
    python3 tools/win/pacing_stats.py log.txt ft.csv [race-start-flip] [vp.csv]

Reads the "[PACING] flip N t_us T" and "[PACING] present N t_us T" lines of
the log (RECOMP_TRACE=pacing=all) and the per-flip CSV of RECOMP_TRACE=
frametime=<file> (its `iv` column is the interval the title asked for: 1 is
60 Hz, 2 the 30 Hz of the crash cameras and replays). With vp.csv
(RECOMP_TRACE=vk_present=<file>) the presents come from it instead, each with
its flip. The race starts at the flip where tracks\\crash1.rws is opened,
unless given; a log without the per-flip lines (RECOMP_TRACE=pacing, as
play-trace.cmd records: see there why) has no such flip, and the menus then
count with the 60 Hz state. Prints, per state:

  guest flip-to-flip  the title's own flip times (the CSV's frame_ms);
  host present-to-present  when each frame was handed to the display
                      (vkQueuePresent returned; with FIFO that is one per
                      refresh the frame waited for).

with p50/p95/p99/p99.9/max in ms, and the frames more than 1.5 periods long
("missed"). A steady run shows p95 ~17.0 and p99 ~17.2 ms at 60 Hz, 33.3 ms
in the crash cameras, and no missed frames.

Three things an earlier version got wrong (BO-75):
  - Lines are found anywhere in a log line. Two threads' stderr lines can run
    together on Windows ("...fence 0x00008779[PACING] present 8097 ..."); read
    only at a line's start, each such present was lost and the two intervals
    around it counted as one of 33 ms.
  - A flip is "racing" only with interval 1 on it and on both neighbours, and
    "crash cameras" likewise with 2. The frames where the title changes between
    60 and 30 Hz are listed apart, not as missed racing frames.
  - The first frames of the race scene (the cut from the loading screen: every
    texture of the scene is uploaded in one frame, 65-80 ms) are apart too.

Every racing frame over 20 ms is listed with where its time went:
  draws        the executor worked in the backend's draws (ex_cpu near ex_busy):
               a shader or pipeline compiled at first use, or new textures; the
               "[vulkan] pcache: compiled ... on the ack thread" and
               "[vulkan] textures:" lines of RECOMP_TRACE=pcache name it
  executor off the executor's thread did not run (ex_busy long, ex_cpu short):
               blocked or descheduled
  title late   the executor waited for the title to submit (ex_idle long)
  present late the title's frame was on time, the present came a refresh late
"""
import bisect, collections, csv, re, sys

RF = re.compile(r'\[PACING\] flip (\d+) t_us (\d+)')
RP = re.compile(r'\[PACING\] present \d+ t_us (\d+)')
CUT = 6          # flips of the scene cut at the race start


def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, int(q * (len(v) - 1) + 0.5))] if v else float('nan')


def load(log, ft, vp):
    flips, pres, race, torn = {}, [], None, 0
    last = 0
    for l in open(log, errors='ignore'):
        if '[PACING] ' in l:
            for m in RF.finditer(l):
                last = int(m.group(1))
                flips[last] = int(m.group(2))
            for m in RP.finditer(l):
                pres.append((int(m.group(1)), None))
                if not l.startswith('[PACING] present') or not l.rstrip().endswith(m.group(1)):
                    torn += 1
        elif race is None and re.search(r'\[FILE\] D:\\tracks\\crash1\.rws', l):
            race = last
    rows = {}
    for r in csv.DictReader(open(ft, errors='replace')):
        try:
            rows[int(r['flip'])] = r
            float(r['frame_ms']), int(r['iv'])
        except (ValueError, TypeError, KeyError):
            rows.pop(int(r['flip']) if (r.get('flip') or '').isdigit() else -1, None)   # a run killed mid-line
    if vp:
        pres = []
        for r in csv.reader(open(vp, errors='replace')):
            if len(r) > 3 and r[1] == 'present' and r[2].isdigit() and r[3].isdigit():
                pres.append((int(r[2]) // 1000, int(r[3])))
    pres.sort()
    return flips, pres, rows, race, torn


def show(name, v, period):
    if not v:
        return
    late = sum(1 for x in v if x > period * 1.5)
    print(f'  {name}: n={len(v)} p50 {pct(v, .5):.2f} p95 {pct(v, .95):.2f} '
          f'p99 {pct(v, .99):.2f} p99.9 {pct(v, .999):.2f} max {max(v):.1f} ms, '
          f'over 20 ms {sum(1 for x in v if x > 20)}, '
          f'missed (> {period * 1.5:.1f} ms) {late} ({100 * late / len(v):.3f}%), '
          f'over {period * 2:.0f} ms {sum(1 for x in v if x > period * 2 + 0.9)}')


def cause(r, present_ms):
    f = lambda k: float(r.get(k) or 0)
    frame, busy, draw, idle, cpu = f('frame_ms'), f('ex_busy'), f('ex_draw'), f('ex_idle'), f('ex_cpu')
    if frame <= 20 and present_ms > 20:
        return 'present late (the guest frame was on time)'
    if draw > 12:
        return 'draws (a compile or texture uploads on the executor)'
    if idle > 12:
        return 'title late (the executor waited for the title)'
    if busy - draw > 12:
        if 'ex_cpu' in r and r['ex_cpu'] not in (None, ''):
            return 'executor off (blocked or descheduled)' if cpu < busy / 2 else 'executor busy outside draws'
        return 'executor busy or blocked outside draws'
    return 'unclear'


def main():
    a = sys.argv[1:]
    log, ft = a[0], a[1]
    race_arg = int(a[2]) if len(a) > 2 and a[2].isdigit() else None
    vp = next((x for x in a[2:] if not x.isdigit()), None)
    flips, pres, rows, race, torn = load(log, ft, vp)
    if race_arg is not None:
        race = race_arg
    if race is None:
        race = 0

    def iv(f):
        r = rows.get(f)
        return int(r['iv']) if r else None

    def state(f):
        if f < race:
            return 'before the race (boot, menus, loading)'
        if race and f < race + CUT:
            return 'race, the scene cut (its first frames)'
        x, y, z = iv(f - 1), iv(f), iv(f + 1)
        if x == y == z == 1:
            return 'race, 60 Hz (racing)'
        if x == y == z == 2:
            return 'race, 30 Hz (crash cameras, replays)'
        return 'race, 60/30 Hz changes'

    period = lambda k: 33.333 if '30 Hz (crash' in k else 16.667
    guest = collections.defaultdict(list)
    for f, r in rows.items():
        guest[state(f)].append(float(r['frame_ms']))
    fl = sorted(flips)
    ts = [flips[f] for f in fl]
    host = collections.defaultdict(list)
    long_ = []
    for (a_t, _), (b_t, b_f) in zip(pres, pres[1:]):
        if b_f is None:
            j = bisect.bisect_right(ts, b_t) - 1
            if j < 0:
                continue
            b_f = fl[j]
        s = state(b_f)
        d = (b_t - a_t) / 1000.0
        host[s].append(d)
        if s.startswith('race, 60 Hz') and d > 20:
            long_.append((b_f, d))
    print(f'race starts at flip {race}; {len(rows)} flips, {len(pres)} presents'
          + (f' ({torn} of their log lines ran into another thread\'s)' if torn else ''))
    for title, d in (('guest flip-to-flip', guest), ('host present-to-present', host)):
        print(title + ':')
        for k in sorted(d):
            show(k, d[k], period(k))
    seen = set()
    for f, r in sorted(rows.items()):
        if state(f).startswith('race, 60 Hz') and float(r['frame_ms']) > 20:
            long_.append((f, 0.0))
    if long_:
        print('racing frames over 20 ms (flip, seconds since the first flip, guest frame, present interval, cause):')
    shown = 0
    for f, d in sorted(long_):
        if f in seen or f - 1 in seen and d:
            continue
        seen.add(f)
        r = rows.get(f, {})
        dd = max([x for g, x in long_ if g in (f, f + 1)] + [d])
        shown += 1
        if shown > 80:
            continue
        print(f'  flip {f} (at {float(r.get("t_ms") or 0) / 1000:.1f} s): guest {float(r.get("frame_ms") or 0):.1f} ms, '
              f'present {dd:.1f} ms: {cause(r, dd)}; hold {r.get("ex_hold")} busy {r.get("ex_busy")} '
              f'draw {r.get("ex_draw")} idle {r.get("ex_idle")} ex_cpu {r.get("ex_cpu", "-")}')
    if shown > 80:
        print(f'  ... and {shown - 80} more')
    secs = collections.defaultdict(list)
    for f in fl:
        if f >= race:
            secs[int(flips[f] / 1e6)].append(iv(f) or 1)
    full = [len(v) for v in secs.values() if len(v) > 30 and all(x == 1 for x in v)]
    if full:
        print(f'whole seconds in the 60 Hz race state: {len(full)}; flips per second '
              f'min {min(full)}, p5 {pct(full, .05)}, median {pct(full, .5)}; '
              f'under 59: {sum(1 for x in full if x < 59)}')


if __name__ == '__main__':
    main()
