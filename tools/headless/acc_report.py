#!/usr/bin/env python3
"""acc_report.py <log> ...  (BO-208 acceptance)

What a run's diagnostic log (RECOMP_LOG_DIAG=1, RECOMP_TRACE=pcache) says about
the shader cache: the manifest, the kind of start, the pre-warm, the waits the
title had, and what the render thread compiled and when. The compiles after the
car was chosen (the race's own load and the race) are counted apart."""
import re, sys

for path in sys.argv[1:]:
    txt = open(path, 'rb').read().decode('utf-8', 'replace').splitlines()
    print(f'== {path}')
    car = None
    last_present = None
    ack_lines = []
    for i, l in enumerate(txt):
        if re.search(r'\[pcache\] manifest|pcache: (cold|warm) start|pcache: pre-warmed|pipeline cache:|ack thread waited|building the .* variants|both variants', l):
            print('  ' + l.strip()[:230])
        if 'CAR1.bgv' in l and car is None and '[FILE]' in l:
            car = len(ack_lines)
        m = re.search(r'pcache at present #(\d+): .*?ack-thread compiles (\d+) vs \+ (\d+) fs \+ (\d+) pipelines in ([\d.]+) ms \(max ([\d.]+)', l)
        if m:
            last_present = tuple(map(float, m.groups()))
        if re.search(r'pcache: compiled .* on the ack thread', l):
            ack_lines.append(l.strip()[:200])
    if last_present:
        n, vs, fs, pso, ms, mx = last_present
        print(f'  at present #{int(n)}: render thread compiled {int(vs)} vs + {int(fs)} fs + {int(pso)} pipelines, {ms:.1f} ms in all (max {mx:.1f} ms)')
    print(f'  render-thread compiles in the trace: {len(ack_lines)}; after the car was chosen: {len(ack_lines) - (car or 0)}')
    for l in ack_lines[(car or 0):][:12]:
        print('    ' + l)
