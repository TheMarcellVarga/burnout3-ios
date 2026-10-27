#!/usr/bin/env python3
"""Prepare and build the experimental Xbox-based iOS port.

No game content is downloaded or tracked. --game-dir names a user's extracted
USA Xbox folder. --archive optionally extracts that folder from a local .7z.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / 'local'
DEPS = json.loads((ROOT / 'ios/dependencies.json').read_text())


def run(args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True, cwd=ROOT, **kwargs)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def validate_game(folder):
    actual = {p.relative_to(folder).as_posix().lower(): p for p in folder.rglob('*') if p.is_file()}
    errors = []
    checked = 0
    for line in (ROOT / 'config/disc/ntsc-u-retail.manifest').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        expected, size, name = line.split(' ', 2)
        path = actual.get(name.lower())
        if path is None or path.stat().st_size != int(size) or sha256(path) != expected:
            errors.append(name)
        checked += 1
    report = {'checked': checked, 'errors': errors}
    (LOCAL / 'disc-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    if errors:
        raise SystemExit('Unsupported or incomplete game files: ' + ', '.join(errors[:12]))
    print(f'Validated all {checked} game files.', flush=True)


def prepare_runtime():
    runtime = LOCAL / 'upstream/xboxrecomp'
    spec = DEPS['runtime']
    if not (runtime / '.git').exists():
        runtime.parent.mkdir(parents=True, exist_ok=True)
        run(['git', 'clone', spec['url'], runtime])
        run(['git', '-C', runtime, 'checkout', '--detach', spec['commit']])
    head = subprocess.check_output(['git', '-C', runtime, 'rev-parse', 'HEAD'], text=True).strip()
    if head != spec['commit']:
        raise SystemExit(f'Runtime is at {head}; expected {spec["commit"]}. Existing checkout preserved.')
    patch = ROOT / spec['patch']
    applied = subprocess.run(['git', '-C', runtime, 'apply', '--reverse', '--check', patch], capture_output=True).returncode == 0
    if not applied:
        run(['git', '-C', runtime, 'apply', '--check', patch])
        run(['git', '-C', runtime, 'apply', patch])
    return runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--team', help='Apple development team for signing')
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--device', help='Install on this connected, unlocked device; implies --build')
    parser.add_argument('--copy-game', action='store_true', help='Copy validated game data to the device')
    parser.add_argument('--regenerate', action='store_true')
    args = parser.parse_args()
    if args.device and not args.team:
        parser.error('--device requires --team for a signed build')
    if args.copy_game and not args.device:
        parser.error('--copy-game requires --device')
    LOCAL.mkdir(exist_ok=True)
    game = args.game_dir.resolve() if args.game_dir else None
    if args.archive:
        extracted = LOCAL / 'disc'
        extracted.mkdir(exist_ok=True)
        run(['bsdtar', '-xf', args.archive.resolve(), '-C', extracted])
        game = extracted / 'Burnout 3 Takedown'
    link = ROOT / 'Burnout 3 Takedown'
    if game:
        validate_game(game)
        if link.is_symlink():
            if link.resolve() != game:
                raise SystemExit(f'{link} already points elsewhere; existing data preserved.')
        elif link.exists():
            if link.resolve() != game:
                raise SystemExit(f'{link} already exists; existing data preserved.')
        else:
            link.symlink_to(game, target_is_directory=True)
    elif link.exists():
        game = link.resolve()
        validate_game(game)
    else:
        raise SystemExit('Supply --game-dir or --archive with the supported USA Xbox files.')
    runtime = prepare_runtime()
    py = ROOT / '.venv/bin/python3'
    ninja = ROOT / '.venv/bin/ninja'
    if not py.exists():
        run([sys.executable, '-m', 'venv', ROOT / '.venv'])
    if subprocess.run([py, '-c', 'import capstone, ninja'], capture_output=True).returncode:
        run([py, '-m', 'pip', 'install', 'capstone==5.0.9', 'ninja==1.13.2'])
    sdl = DEPS['sdl']
    archive = LOCAL / 'deps' / f'SDL2-{sdl["version"]}.tar.gz'
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        urllib.request.urlretrieve(sdl['url'], archive)
    if sha256(archive) != sdl['sha256']:
        raise SystemExit('SDL archive checksum mismatch; build stopped.')
    source = archive.parent / f'SDL2-{sdl["version"]}'
    if not source.exists():
        run(['bsdtar', '-xf', archive, '-C', archive.parent])
    patch = ROOT / sdl['patch']
    patch_base = ['patch', '-d', str(source), '-p1', '-t', '-s', '-i', str(patch)]
    if subprocess.run(patch_base + ['-R', '-C'], capture_output=True).returncode:
        run(patch_base + ['-N'])
    prefix = archive.parent / 'sdl-ios'
    stamp = prefix / '.takedawn-patch-sha256'
    patch_hash = sha256(patch)
    if not (prefix / 'lib/libSDL2.a').exists() or not stamp.exists() or stamp.read_text().strip() != patch_hash:
        run(['cmake', '-S', source, '-B', ROOT / 'build/sdl-ios-ninja', '-G', 'Ninja',
             f'-DCMAKE_MAKE_PROGRAM={ninja}', '-DCMAKE_SYSTEM_NAME=iOS',
             f'-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPS["deployment_target"]}',
             '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_BUILD_TYPE=Release',
             f'-DCMAKE_INSTALL_PREFIX={prefix}', '-DSDL_SHARED=OFF', '-DSDL_STATIC=ON',
             '-DSDL_TEST=OFF', '-DSDL_TESTS=OFF'])
        run(['cmake', '--build', ROOT / 'build/sdl-ios-ninja', '--target', 'install', '--parallel', '4'])
        stamp.write_text(patch_hash + '\n')
    if args.regenerate or not (ROOT / 'src/game/recomp/gen/recomp_0000.c').exists():
        run(['bash', ROOT / 'regen.sh', '--disasm'], env=dict(os.environ, XBOXRECOMP_DIR=str(runtime)))
    build = ROOT / 'build/ios'
    run(['cmake', '-S', ROOT, '-B', build, '-G', 'Xcode', '-DCMAKE_SYSTEM_NAME=iOS',
         f'-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPS["deployment_target"]}', '-DCMAKE_OSX_ARCHITECTURES=arm64',
         f'-DXBOXRECOMP_DIR={runtime}', f'-DSDL2_DIR={prefix / "lib/cmake/SDL2"}',
         '-DXBOXRECOMP_VULKAN=OFF', '-DBO3_OVERLAY=OFF', '-DBO3_GLYPHS=OFF'])
    if args.build or args.device:
        command = ['xcodebuild', '-project', build / 'burnout3_recomp.xcodeproj', '-target', 'burnout3',
                   '-configuration', 'Release', '-sdk', 'iphoneos', '-jobs', '4']
        command += ['-allowProvisioningUpdates', f'DEVELOPMENT_TEAM={args.team}'] if args.team else ['CODE_SIGNING_ALLOWED=NO']
        run(command)
    if args.device:
        if not args.team:
            raise SystemExit('--device requires --team for a signed build.')
        run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device, ROOT / 'bin/TakedawnIOS.app'])
        if args.copy_game:
            run(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', args.device,
                 '--source', game, '--destination', 'Documents/Burnout 3 Takedown',
                 '--domain-type', 'appDataContainer', '--domain-identifier', 'dev.burnout3.takedawn-ios'])


if __name__ == '__main__':
    main()
