#!/usr/bin/env python3
"""Compile every runtime unit for macOS ARM64 and run arithmetic regressions."""
import os
import argparse
import subprocess
from native_common import ROOT, BUILD, require_upstream, compile_harness


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64')
    args = parser.parse_args()
    require_upstream()
    from ps2decomp import liftcheck
    work = BUILD / ('runtime-' + args.arch)
    work.mkdir(parents=True, exist_ok=True)
    harness = work / 'host.cpp'
    # Reuse upstream's memory/call harness, with Clang's export spelling.
    harness.write_text(liftcheck.harness_source([]).replace('__declspec(dllexport)', '__attribute__((visibility("default")))'))
    executable = work / 'runtime_tests'
    compile_harness([harness, ROOT / 'native/tests/runtime_tests.cpp'], executable, arch=args.arch)
    print(f'Testing {args.arch}', flush=True)
    env = dict(os.environ)
    env.pop('PS2RT_EE_ROUND_NEAREST', None)
    subprocess.run([str(executable)], env=env, check=True)
    env['PS2RT_EE_ROUND_NEAREST'] = '1'
    subprocess.run([str(executable)], env=env, check=True)


if __name__ == '__main__':
    main()
