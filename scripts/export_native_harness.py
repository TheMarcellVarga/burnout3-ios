#!/usr/bin/env python3
"""Export the upstream test host for Clang builds, without game content."""
from pathlib import Path
import sys
from native_common import require_upstream

require_upstream()
from ps2decomp import liftcheck

output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(liftcheck.harness_source([]).replace(
    '__declspec(dllexport)', '__attribute__((visibility("default")))'))
