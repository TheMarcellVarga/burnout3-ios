"""Paths and compiler settings for the Apple Silicon port experiments."""
from pathlib import Path
import json
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'local/upstream/burnout3-pc'
ENGINE = UPSTREAM / 'engine'
BUILD = ROOT / 'build/native'
LOCK = json.loads((ROOT / 'native/upstream.json').read_text())


def require_upstream():
    for directory, expected in [(UPSTREAM, LOCK['commit']), (ENGINE, LOCK['engine_commit'])]:
        actual = subprocess.check_output(['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != expected:
            raise SystemExit(f'Unexpected upstream revision in {directory}; run scripts/prepare_native.py')
    sys.path[:0] = [str(ENGINE), str(ENGINE / 'tools')]


def compiler(arch='arm64'):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This experiment requires an Apple Silicon Mac.')
    if arch not in ('arm64', 'x86_64'):
        raise ValueError('Unsupported architecture')
    return ['xcrun', '--sdk', 'macosx', 'clang++', '-std=c++17', '-arch', arch,
            '-O2', '-frounding-math', '-ffp-contract=off', '-I' + str(ENGINE / 'runtime/include')]


def compile_harness(sources, output, *, shared=False, arch='arm64'):
    command = compiler(arch)
    if shared:
        command += ['-dynamiclib']
    command += [str(p) for p in sources]
    command += [str(p) for p in sorted((ENGINE / 'runtime/src').glob('*.cpp'))]
    subprocess.run(command + ['-o', str(output)], check=True)
