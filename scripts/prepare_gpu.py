#!/usr/bin/env python3
"""Prepare pinned MoltenVK libraries and a native Mac shader compiler."""
import hashlib
import json
from pathlib import Path
import subprocess
from native_common import ROOT


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    lock = json.loads((ROOT / 'native/gpu/dependencies.json').read_text())
    deps = ROOT / 'local/gpu-deps'
    deps.mkdir(parents=True, exist_ok=True)
    version = lock['moltenvk']['version']
    for platform in ('ios', 'macos'):
        archive = deps / f'MoltenVK-{platform}-{version}.tar'
        if not archive.exists():
            run('curl', '-fL', '--retry', '3',
                f'https://github.com/KhronosGroup/MoltenVK/releases/download/v{version}/MoltenVK-{platform}.tar',
                '-o', archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['moltenvk'][platform + '_sha256']:
            raise SystemExit(f'Checksum mismatch: {archive}')
        destination = deps / ('moltenvk-' + platform)
        if not (destination / 'MoltenVK/LICENSE').exists():
            destination.mkdir(exist_ok=True)
            run('tar', '-xf', archive, '-C', destination)
    compiler = deps / 'glslang'
    if not compiler.exists():
        run('git', 'clone', '--depth', '1', '--branch', lock['glslang']['tag'],
            'https://github.com/KhronosGroup/glslang.git', compiler)
    actual = subprocess.check_output(['git', '-C', str(compiler), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != lock['glslang']['commit']:
        raise SystemExit('Existing glslang revision differs; refusing to reset it.')
    build = ROOT / 'build/glslang'
    run('cmake', '-S', compiler, '-B', build, '-DCMAKE_BUILD_TYPE=Release', '-DENABLE_OPT=OFF',
        '-DENABLE_HLSL=OFF', '-DENABLE_GLSLANG_BINARIES=ON', '-DGLSLANG_TESTS=OFF',
        '-DBUILD_TESTING=OFF', '-DGLSLANG_ENABLE_INSTALL=OFF')
    run('cmake', '--build', build, '--target', 'glslang-standalone', '--parallel', '2')
    print('GPU dependencies ready; licenses are preserved inside local/gpu-deps/.')


if __name__ == '__main__':
    main()
