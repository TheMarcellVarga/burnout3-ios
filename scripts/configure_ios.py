#!/usr/bin/env python3
"""Generate the iPhone project; optionally compile an unsigned optimized build."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
from native_common import ROOT, require_upstream


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--game-code', action='store_true', help='Also build the generated game-code library for iOS')
    parser.add_argument('--native-boot', action='store_true', help='Link the native game host and startup UI')
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Release',
                        help='Build mode; Release is required for usable device performance')
    parser.add_argument('--gpu', action='store_true', help='Build the MoltenVK/Metal GPU path (prepare_gpu.py first)')
    args = parser.parse_args()
    require_upstream()
    env = dict(os.environ)
    chosen = subprocess.check_output(['xcode-select', '-p'], text=True).strip()
    developer = Path(env.get('DEVELOPER_DIR', chosen))
    if not (developer / 'usr/bin/xcodebuild').exists():
        developer = Path('/Applications/Xcode.app/Contents/Developer')
    if not (developer / 'usr/bin/xcodebuild').exists():
        parser.exit(1, 'Xcode is not installed yet. Finish the App Store download, then open Xcode and complete its setup.\n')
    env['DEVELOPER_DIR'] = str(developer)
    ready = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], env=env,
                           capture_output=True, text=True)
    if ready.returncode:
        parser.exit(1, 'The iOS SDK is unavailable. Open Xcode and complete setup, including the iOS platform.\n' + ready.stderr)
    if not shutil.which('cmake'):
        parser.exit(1, 'CMake is required to generate this project.\n')
    build = ROOT / 'build/ios'
    subprocess.run(['cmake', '-S', str(ROOT), '-B', str(build), '-G', 'Xcode',
                    '-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_SYSROOT=iphoneos',
                    '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=17.4',
                    '-DBURNOUT_BUILD_TRANSLATED=' + ('ON' if args.game_code or args.native_boot else 'OFF'),
                    '-DBURNOUT_BUILD_HEADLESS=' + ('ON' if args.native_boot else 'OFF'),
                    '-DBURNOUT_BUILD_GPU=' + ('ON' if args.gpu else 'OFF')],
                   env=env, check=True)
    if args.build:
        targets = ['BurnoutNativeProbe']
        if args.game_code:
            targets += ['burnout_translated', 'ps2vu_micro']
        subprocess.run(['cmake', '--build', str(build), '--config', args.configuration,
                        '--parallel', '2', '--target', *targets, '--', 'CODE_SIGNING_ALLOWED=NO'],
                       env=env, check=True)
    print(f'Project: {build / "BurnoutNative.xcodeproj"}')
    print('To run on the phone, open the project in Xcode and choose your signing team and iPhone.')


if __name__ == '__main__':
    main()
