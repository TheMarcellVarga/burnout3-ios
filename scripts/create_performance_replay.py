#!/usr/bin/env python3
"""Create pad streams for the iOS selector/race performance diagnostics.

The diagnostics use an empty disposable memory card. Race input confirms the
compact car, skips the first-race training video, then holds the original PS2
accelerator (Cross). Reports are replayed after the modern-controller filter.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUTTONS = {'up': 4, 'down': 6, 'cross': 14, 'start': 3}
PRESSURE_ORDER = [5, 7, 4, 6, 12, 13, 14, 15, 10, 11, 8, 9]
SELECTOR = [
    ('up', 800), ('cross', 830), ('start', 2100), ('start', 2500),
    ('start', 2900), ('down', 3300), ('cross', 3340), ('cross', 3600),
    ('cross', 3900), ('up', 4200), ('cross', 4240), ('down', 4600),
    ('cross', 4640), ('cross', 4900), ('cross', 5200),
]


def replay(scene):
    events = [(8, 0)]
    presses = SELECTOR + ([('cross', 5500), ('start', 5900)] if scene == 'race' else [])
    for button, frame in presses:
        events.extend([(frame, 1 << BUTTONS[button]), (frame + 6, 0)])
    if scene == 'race':
        events.append((6100, 1 << BUTTONS['cross']))
    lines = []
    for frame, held in sorted(events):
        mask = (~held) & 0xFFFF
        data = [mask & 255, mask >> 8, 128, 128, 128, 128]
        data += [255 if held & (1 << button) else 0 for button in PRESSURE_ORDER]
        lines.append(str(frame) + ' ' + ' '.join(f'{value:02X}' for value in data))
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scene', choices=['selector', 'race'], default='race')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or ROOT / 'local/runs' / f'{args.scene}-replay.txt'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(replay(args.scene))
    print(output)


if __name__ == '__main__':
    main()
