#!/usr/bin/env python3
"""Read an ISO9660 PS2 disc without mounting it or executing its contents."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

SECTOR = 2048


def inspect(path):
    with path.open('rb') as disc:
        def read(offset, size):
            if offset < 0 or size < 0 or offset + size > path.stat().st_size:
                raise ValueError('Disc extent outside image (possibly incomplete extraction)')
            disc.seek(offset)
            data = disc.read(size)
            if len(data) != size:
                raise ValueError('Truncated disc extent')
            return data

        pvd = read(16 * SECTOR, SECTOR)
        if pvd[:7] != b'\x01CD001\x01':
            raise ValueError('Expected an ISO9660 primary volume descriptor')
        if int.from_bytes(pvd[128:130], 'little') != SECTOR:
            raise ValueError('Unsupported logical block size')
        volume_bytes = int.from_bytes(pvd[80:84], 'little') * SECTOR
        if path.stat().st_size < volume_bytes:
            raise ValueError('Image is shorter than its declared volume size')

        def record(raw):
            return {
                'name': raw[33:33 + raw[32]].decode('ascii', errors='replace').split(';')[0],
                'sector': int.from_bytes(raw[2:6], 'little'),
                'bytes': int.from_bytes(raw[10:14], 'little'),
                'directory': bool(raw[25] & 2),
            }

        root = record(pvd[156:190])
        raw = read(root['sector'] * SECTOR, root['bytes'])
        entries = []
        pos = 0
        while pos < len(raw):
            length = raw[pos]
            if length == 0:
                pos = (pos // SECTOR + 1) * SECTOR
                continue
            if length < 34 or pos + length > len(raw):
                raise ValueError('Malformed ISO directory record')
            entry = record(raw[pos:pos + length])
            if entry['name'] not in ('\x00', '\x01'):
                entries.append(entry)
            pos += length
        result = {
            'image': path.name,
            'bytes': path.stat().st_size,
            'volume_id': pvd[40:72].decode('ascii', errors='replace').strip(),
            'root_entries': entries,
        }
        config = next((e for e in entries if e['name'].upper() == 'SYSTEM.CNF'), None)
        if config:
            if config['bytes'] > 65536:
                raise ValueError('Unexpectedly large SYSTEM.CNF')
            cnf = read(config['sector'] * SECTOR, config['bytes']).decode('ascii', errors='replace')
            result['system_cnf'] = cnf
            match = re.search(r'BOOT2\s*=\s*cdrom0:\\([^;\r\n]+)', cnf, re.I)
            if match:
                name = match[1].strip()
                exe = next((e for e in entries if e['name'].upper() == name.upper()), None)
                if exe:
                    if exe['bytes'] > 64 * 1024 * 1024:
                        raise ValueError('Unexpectedly large boot executable')
                    elf = read(exe['sector'] * SECTOR, exe['bytes'])
                    if len(elf) < 52 or elf[:6] != b'\x7fELF\x01\x01':
                        raise ValueError('Expected a 32-bit little-endian boot ELF')
                    result['executable'] = {
                        'name': name, 'bytes': len(elf),
                        'sha256': hashlib.sha256(elf).hexdigest(),
                        'machine': struct.unpack_from('<H', elf, 18)[0],
                        'entry_point': hex(struct.unpack_from('<I', elf, 24)[0]),
                    }
                    result['platform'] = 'PlayStation 2' if result['executable']['machine'] == 8 else 'Unknown ELF target'
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('iso', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        output = json.dumps(inspect(args.iso), indent=2) + '\n'
    except (OSError, ValueError, IndexError, struct.error) as error:
        parser.exit(1, f'Disc inspection failed: {error}\n')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
