#!/usr/bin/env python3
"""Translate a bounded disc-code sample to ARM64 and compare with the PS2 model.

This is a translation check, not a game launcher. Each selected function is
native C++; memory and any unexpected external call use upstream's test harness.
"""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess
from native_common import ROOT, UPSTREAM, ENGINE, BUILD, require_upstream, compile_harness


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--count', type=int, default=32)
    args = parser.parse_args()
    if not 1 <= args.count <= 128:
        parser.error('--count must be between 1 and 128')
    require_upstream()
    from ps2decomp import game as game_config, lift, liftcheck, testplan
    from ps2decomp.emu import Machine
    from ps2decomp.liftverify import verify
    game = game_config.load(str(UPSTREAM / 'games/burnout3'))
    if not Path(game.elf_path).exists() or not Path(game.database_path).exists():
        parser.error('Extract and analyze the disc first; see README.md')
    elf = game.load_elf()
    database = game.load_database()
    section = elf.exec_sections[0]
    image = elf.section_data(section)
    lift.use_sections([(elf.section_data(s), s.addr) for s in elf.sections
                       if s is not section and s.size and s.flags & 2 and s.type != 8])
    lift.use_function_starts(f['addr'] for f in database['functions'])
    pool = [f for f in database['functions'] if 32 <= f['size'] <= 192
            and f['has_return'] and not f['calls'] and not f.get('chunks')]
    # Spread the sample over the executable rather than its startup routines.
    selected = pool[::max(1, len(pool) // args.count)][:args.count]
    if not selected:
        parser.error('No suitable functions found in the analysis')
    work = BUILD / 'translation'
    work.mkdir(parents=True, exist_ok=True)
    functions = []
    source = ['#include "ps2rt/lifted.h"', 'using namespace generated;', 'using namespace lifted;']
    refused = {}
    for function in selected:
        try:
            source.append(lift.lift_function(image, section.addr, function['addr'], function['end']))
            functions.append(function)
        except lift.Refused as error:
            refused[hex(function['addr'])] = str(error)
    if not functions:
        parser.error('All selected functions were refused by the translator')
    translated = work / 'game_sample.cpp'
    translated.write_text('\n\n'.join(source) + '\n')
    harness = work / 'host.cpp'
    harness.write_text(liftcheck.harness_source(['F_%08X' % f['addr'] for f in functions])
                       .replace('__declspec(dllexport)', '__attribute__((visibility("default")))'))
    library_path = work / 'game_sample.dylib'
    compile_harness([translated, harness], library_path, shared=True)
    machine = Machine.from_elf(elf)
    testplan.prepare_test_memory(machine, database, image, section.addr, functions, seeds=[])
    library = liftcheck.LiftedFunctions(str(library_path), machine)
    outcomes = {}
    for function in functions:
        outcome = verify(function, machine, library)
        outcomes['0x%08X' % function['addr']] = outcome
        print('0x%08X: %s' % (function['addr'], outcome), flush=True)
    verified = sum(v == 'verified' for v in outcomes.values())
    report = {
        'platform': f'{platform.system()} {platform.machine()}',
        'scope': 'Bounded function translation comparison; not a game boot or iOS test',
        'executable_sha256': hashlib.sha256(Path(game.elf_path).read_bytes()).hexdigest(),
        'verification_rounding': 'nearest, matching upstream interpreter',
        'selected': len(selected), 'compiled': len(functions), 'verified': verified,
        'refused': refused, 'outcomes': outcomes,
    }
    report_path = ROOT / 'local/reports/native_translation.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(f'{verified}/{len(functions)} compiled functions verified; report: {report_path}')
    failures = [v for v in outcomes.values() if v != 'verified' and not v.startswith('untestable')]
    if failures or not verified:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
