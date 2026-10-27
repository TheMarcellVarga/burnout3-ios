#!/usr/bin/env python3
"""level_report.py <rundir>... : the music level and the clipping of runs of
custom_level_scene.sh (BO-132), from each run's out.wav.

Per run and per phase (the menu: the music alone; the race: music, engine
and effects), the stretch of the WAV the phase covers: peak, samples at full
scale, integrated loudness (EBU R128, ffmpeg's ebur128) and the true peak.
The phase times are seconds into the WAV (phases.txt: the runtime marks the
log once a second of audio, "[AUDIO-WAV] t=N"). --window s trims that many
seconds off both ends of each phase (a menu change, a loading gap).

  tools/headless/level_report.py runs/cl_eatrax runs/cl_off runs/cl_match
"""
import re, subprocess, sys, struct, os
import numpy as np

def wav_read(path):
    with open(path, 'rb') as f:
        d = f.read()
    assert d[:4] == b'RIFF'
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(d):
        cid, size = d[pos:pos+4], struct.unpack('<I', d[pos+4:pos+8])[0]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', d[pos+8:pos+24])
        elif cid == b'data':
            if size == 0 or pos + 8 + size > len(d):
                size = len(d) - pos - 8
            data = d[pos+8:pos+8+size]
            break
        pos += 8 + size + (size & 1)
    ch, rate = fmt[1], fmt[2]
    a = np.frombuffer(data[:len(data)//(2*ch)*2*ch], dtype='<i2').reshape(-1, ch)
    return a, rate

def r128(a, rate, tmp):
    """Integrated loudness and true peak of a stereo int16 array by ffmpeg."""
    with open(tmp, 'wb') as f:
        f.write(a[:, :2].astype('<i2').tobytes())
    out = subprocess.run(['ffmpeg', '-nostats', '-hide_banner', '-f', 's16le', '-ar', str(rate), '-ac', '2',
                          '-i', tmp, '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    s = out[out.rfind('Summary'):]
    i = re.search(r'I:\s+(-?[\d.]+) LUFS', s)
    tp = re.search(r'Peak:\s+(-?[\d.]+) dBFS', s)
    return (float(i.group(1)) if i else float('nan'), float(tp.group(1)) if tp else float('nan'))

def phases(path):
    ph = {}
    for line in open(path):
        m = re.match(r'(\w+) (\d+)', line)
        if m: ph[m.group(1)] = int(m.group(2))
    return ph

def main():
    args = sys.argv[1:]
    trim = 5.0
    if '--window' in args:
        i = args.index('--window'); trim = float(args[i+1]); del args[i:i+2]
    for rd in args:
        wav = os.path.join(rd, 'out.wav')
        if not os.path.exists(wav):
            print(rd, ': no out.wav'); continue
        a, rate = wav_read(wav)
        ph = phases(os.path.join(rd, 'phases.txt'))
        total = len(a) / rate
        # The WAV ends when the run is stopped, a moment after race_end.
        print('%s: %.1f s of audio, %d channels' % (rd, total, a.shape[1]))
        for name, s0, s1 in (('menu', 'menu_start', 'menu_end'), ('race', 'race_start', 'race_end'), ('all', None, None)):
            if s0 and (s0 not in ph or s1 not in ph): continue
            if s0:
                t0, t1 = ph[s0] + trim, ph[s1] - trim
            else:
                t0, t1 = 0.0, total
            seg = a[int(max(t0, 0) * rate):int(t1 * rate)]
            if len(seg) < rate: continue
            peak = np.abs(seg.astype(np.int32)).max()
            full = int(np.sum((seg >= 32767) | (seg <= -32768)))
            near = int(np.sum(np.abs(seg.astype(np.int32)) >= 30934))
            lufs, tp = r128(seg, rate, os.path.join(rd, '.segment.raw'))
            print('  %-5s %6.1f-%6.1f s  peak %5.2f dBFS  samples at full scale %6d  >= -0.5 dBFS %6d  %.1f LUFS  true peak %.1f dBFS'
                  % (name, t0, t1, 20 * np.log10(max(peak, 1) / 32768.0), full, near, lufs, tp))
        try: os.remove(os.path.join(rd, '.segment.raw'))
        except OSError: pass

main()
