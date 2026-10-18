#!/usr/bin/env python3
"""Fetch pinned source and apply the local ARM64 patches, without game content."""
import subprocess
import re
import shutil
import tempfile
from pathlib import Path
from native_common import ROOT, UPSTREAM, ENGINE, LOCK, require_upstream


def git(directory, *args, **kwargs):
    return subprocess.run(['git', '-C', str(directory), *args], **kwargs)


def applied_prefix(directory, patches):
    """Recognize stacked patches even when later patches change earlier hunks.

    Reverse only disposable copies of affected files. Checking each patch on
    the live tree alone fails for a header added by one patch and extended by
    another; the user's checkout must never be rolled back for this check.
    """
    paths = {match for patch in patches for match in
             re.findall(r'^(?:--- a/|\+\+\+ b/)(.+)$', patch.read_text(), re.M)}
    for count in range(len(patches), 0, -1):
        with tempfile.TemporaryDirectory(prefix='burnout-patch-check-') as temporary:
            scratch = Path(temporary)
            for name in paths:
                source = directory / name
                if source.is_file():
                    target = scratch / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
            for patch in reversed(patches[:count]):
                if git(scratch, 'apply', '--reverse', str(patch), capture_output=True).returncode:
                    break
            else:
                return count
    return 0


def main():
    if not UPSTREAM.exists():
        UPSTREAM.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', '--no-checkout', LOCK['repository'], str(UPSTREAM)], check=True)
        git(UPSTREAM, 'checkout', '--detach', LOCK['commit'], check=True)
    # Do not reset or discard a user's checkout if its revision differs.
    actual = subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != LOCK['commit']:
        raise SystemExit('Existing checkout differs from the pinned revision; refusing to overwrite it.')
    if not (ENGINE / 'runtime').exists():
        git(UPSTREAM, 'submodule', 'update', '--init', '--depth', '1', 'engine', check=True)
    require_upstream()
    for directory, folder in [(ENGINE, 'native/patches'), (UPSTREAM, 'native/game-patches')]:
        patches = sorted((ROOT / folder).glob('*.patch'))
        already = applied_prefix(directory, patches)
        for index, patch in enumerate(patches):
            if index < already:
                print(f'Already applied: {patch.name}')
                continue
            git(directory, 'apply', '--check', str(patch), check=True)
            git(directory, 'apply', str(patch), check=True)
            print(f'Applied: {patch.name}')


if __name__ == '__main__':
    main()
