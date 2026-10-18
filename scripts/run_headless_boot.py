#!/usr/bin/env python3
"""Run a bounded native boot; rebuild newly discovered code ahead of time."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
from native_common import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frames', type=int, default=60)
    parser.add_argument('--timeout', type=int, default=20)
    parser.add_argument('--max-rounds', type=int, default=10)
    args = parser.parse_args()
    if min(args.frames, args.timeout, args.max_rounds) < 1:
        parser.error('All limits must be positive')
    build = ROOT / 'build/cmake-game'
    discovery = ROOT / 'local/native/discovered.txt'
    discovery.parent.mkdir(parents=True, exist_ok=True)
    run_root = ROOT / 'local/runs' / datetime.now(timezone.utc).strftime('native-boot-%Y%m%dT%H%M%SZ')
    run_root.mkdir(parents=True)
    results = []
    success = False
    for index in range(args.max_rounds):
        work = run_root / str(index + 1)
        work.mkdir()
        before = discovery.read_text() if discovery.exists() else ''
        with (work / 'build.log').open('w') as log:
            subprocess.run(['cmake', '-S', str(ROOT), '-B', str(build),
                            '-DBURNOUT_BUILD_TRANSLATED=ON', '-DBURNOUT_BUILD_HEADLESS=ON'],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            subprocess.run(['cmake', '--build', str(build), '--target', 'burnout_headless', '--parallel', '2'],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        with (work / 'run.log').open('w') as log:
            result = subprocess.run([str(build / 'burnout_headless'), '--disc',
                                     str(ROOT / 'local/disc/Burnout 3 - Takedown.iso'),
                                     '--virtual-time', '--until-frame', str(args.frames),
                                     '--timeout', str(args.timeout), '--limit', '20',
                                     '--frames', str(work), '--frames-every', str(max(1, args.frames // 3)),
                                     '--discover', str(discovery)], stdout=log,
                                    stderr=subprocess.STDOUT, timeout=args.timeout + 30)
        text = (work / 'run.log').read_text()
        outcome = next((line for line in text.splitlines() if line.startswith('stopped:')), 'No host stop report')
        results.append({'round': index + 1, 'host_exit_code': result.returncode,
                        'outcome': outcome, 'log': str(work / 'run.log')})
        print(f'Round {index + 1}: {outcome}', flush=True)
        success = outcome == f'stopped: frame {args.frames} reached (--until-frame)'
        after = discovery.read_text() if discovery.exists() else ''
        if success or after == before:
            break
    report = {'scope': 'Headless native startup; not interactive gameplay',
              'target_frame': args.frames, 'target_reached': success, 'rounds': results}
    report_path = run_root / 'result.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {report_path}', flush=True)
    return 0 if success else 2


if __name__ == '__main__':
    raise SystemExit(main())
