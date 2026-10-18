#!/usr/bin/env python3
"""Generate a native game's function registry from the local translated code."""
import json
from pathlib import Path
import re
import sys
from native_common import ROOT, BUILD, UPSTREAM, require_upstream

require_upstream()
from ps2decomp import game as game_config
import port
import vurecomp

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
manifest = json.loads((BUILD / 'game/manifest.json').read_text())
addresses = []
for name in manifest['chunks']:
    text = (BUILD / 'game' / name).read_text()
    addresses.extend(int(value, 16) for value in re.findall(r'^void F_([0-9A-F]{8})\(', text, re.M))
game = game_config.load(str(UPSTREAM / 'games/burnout3'))
database = game.load_database()
sizes = {f['addr']: f['size'] for f in database['functions']}
missing = set(sizes) - set(addresses)
discovery_path = ROOT / 'local/native/discovered.txt'
found = port.discovered_functions(game, str(discovery_path))
found = {address: value for address, value in found.items() if address not in set(addresses)}
discovered_source = ['// Locally discovered copied code, translated ahead of time. NOT behaviorally verified.',
                     '#include "ps2rt/lifted.h"', 'using namespace generated;', 'using namespace lifted;']
discovered_source.extend(text for original, text in found.values())
(out / 'discovered.cpp').write_text('\n\n'.join(discovered_source) + '\n')
addresses += list(found)
source = port.dispatch_source(addresses, {}, missing, sizes)
source += '\nextern const ps2host::OverlayEntry kGuestOverlays[] = {{}};\n'
source += 'extern const std::size_t kGuestOverlayCount = 0;\n'
(out / 'dispatch.cpp').write_text(source)
rows = (UPSTREAM / 'engine/data/iop_exports.csv').read_text().splitlines()
(out / 'iop_exports.inc').write_text('\n'.join(json.dumps(row + '\n') for row in rows) + '\n')
# Keep captured game microcode in ignored local storage, like discovered EE
# functions. The compiler emits exact blocks; unmatched/changed code continues
# through the interpreter's existing validation and fallback.
vurecomp.main(['--manifest', str(ROOT / 'local/native/vu_programs.txt'),
               '--out-dir', str(out)])
