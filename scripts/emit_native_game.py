#!/usr/bin/env python3
"""Generate the disc executable's C++ translation and optionally check ARM64 syntax.

This does not claim behavioral verification. Generated game code stays in ignored
build/; no assets or instructions from the disc are executed by this script.
"""
import argparse
import json
import re
import subprocess
from native_common import UPSTREAM, BUILD, require_upstream, compiler


def batch_cop2(source):
    """Group strictly adjacent VU macros; labels, EE operations and calls end runs."""
    pattern = re.compile(r'^    lifted::Cop2\(c, (0x[0-9A-Fa-f]+u)\);(?:  /\*.*\*/)?$')
    result, pending = [], []
    def flush():
        if len(pending) > 1:
            words = ', '.join(word for _, word in pending)
            result.append('    { static constexpr u32 ops[] = {' + words + '};\n'
                          '      lifted::Cop2Batch(c, ops, sizeof ops / sizeof *ops); }\n')
        else:
            result.extend(line for line, _ in pending)
        pending.clear()
    for line in source.splitlines(keepends=True):
        match = pattern.fullmatch(line.rstrip('\n'))
        if match:
            pending.append((line, match[1]))
        else:
            flush()
            result.append(line)
    flush()
    return ''.join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check every generated chunk with Clang for ARM64')
    args = parser.parse_args()
    require_upstream()
    from ps2decomp import game as game_config, lift
    import lift as pipeline
    game = game_config.load(str(UPSTREAM / 'games/burnout3'))
    database, elf = game.load_database(), game.load_elf()
    section = elf.exec_sections[0]
    image = elf.section_data(section)
    lift.use_sections(pipeline._other_sections(elf, section))
    lift.use_function_starts(f['addr'] for f in database['functions'])
    functions = [f for f in database['functions'] if f['end'] > f['addr']]
    translated, refused = pipeline.lift_all(functions, image, section.addr)
    work = BUILD / 'game'
    work.mkdir(parents=True, exist_ok=True)
    paths = []
    for index, group in enumerate(pipeline._groups(sorted(translated), translated)):
        path = work / f'game_{index:03d}.cpp'
        path.write_text('// Generated from the local disc. NOT behaviorally verified.\n'
                        '#include "ps2rt/lifted.h"\nusing namespace generated;\nusing namespace lifted;\n\n' +
                        '\n'.join(batch_cop2(translated[a]) for a in group))
        paths.append(path)
    # Remove only stale generated chunks in this dedicated output directory.
    for stale in work.glob('game_*.cpp'):
        if stale not in paths:
            stale.unlink()
    manifest = {
        'analyzed_functions': len(functions), 'translated_functions': len(translated),
        'refused_reasons': dict(refused), 'chunks': [p.name for p in paths],
        'untranslated_functions': ['0x%08X' % f['addr'] for f in functions if f['addr'] not in translated],
        'behaviorally_verified': False, 'arm64_syntax_checked': False,
    }
    manifest_path = work / 'manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Generated {len(translated)}/{len(functions)} functions in {len(paths)} chunks', flush=True)
    if args.check:
        for index, path in enumerate(paths):
            subprocess.run(compiler() + ['-fsyntax-only', str(path)], check=True)
            print(f'ARM64 syntax {index + 1}/{len(paths)}: PASS', flush=True)
        manifest['arm64_syntax_checked'] = True
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
