#!/usr/bin/env python3
"""controls_check.py <ps2|xbox> <race|crash> <ctl.txt> <drive.txt> [xbox|nintendo]

The checks of controls_scene.sh (BO-106), on the two logs of one run:
BO3_CTL_LOG (S: a word of the title's state changed; D: the gate; G: a pad's
layout; P: a pad as read and as given to the title) and BO3_DRIVE_LOG (the
HUD's speed and the pad bytes the title read, a line a frame).
Prints PASS/FAIL lines; exit 1 on a failure."""
import re
import sys

scheme, event, ctl_path, drive_path = sys.argv[1:5]
# The face layout the scripted controller went through. "read" in the log is
# the pad after it, as the title's buttons: with nintendo the bottom button
# is the title's B.
face = sys.argv[5] if len(sys.argv) > 5 else 'xbox'
BOTTOM = 'b' if (face == 'nintendo' and scheme == 'ps2') else 'a'
GAME_VT, FE_VT = 0x3A9ACC, 0x3A9E7C
NAMES = ['a', 'b', 'x', 'y', 'bk', 'wh', 'lt', 'rt']

S, D, G, P = [], [], [], []
for line in open(ctl_path):
    w = line.split()
    if not w:
        continue
    if w[0] == 'S':
        S.append((int(w[1]), w[2], int(w[3], 16), int(w[5], 16)))
    elif w[0] == 'D':
        D.append((int(w[1]), int(w[3])))
    elif w[0] == 'G':
        G.append((int(w[1]), int(w[3]), w[4]))
    elif w[0] == 'P':
        m = re.match(r'P (\d+) port (\d) (ps2|xbox)( latched)? read ([0-9A-F]{4}) (.*) -> (.*)$', line)
        f = lambda t: {k: int(v) for k, v in re.findall(r'([a-z]+)(-?\d+)', t)}
        P.append(dict(flip=int(m[1]), port=int(m[2]), layout=m[3], latched=bool(m[4]),
                      btn=int(m[5], 16), read=f(m[6]), given=f(m[7])))
speed = {}
for line in open(drive_path):
    m = re.match(r'D (\d+) v (-?[\d.]+) .* lt (\d+) rt (\d+)', line)
    if m:
        speed[int(m[1])] = (float(m[2]), int(m[3]), int(m[4]))

bad = 0


def check(ok, what):
    global bad
    print(('PASS ' if ok else 'FAIL ') + what)
    bad += not ok


def changes(name, to=None):
    return [s for s in S if s[1] == name and (to is None or s[3] == to)]


def gate_at(flip):
    v = 0
    for f, d in D:
        if f <= flip:
            v = d
    return v


def same(p):
    return all(p['read'][k] == p['given'][k] for k in NAMES) and p['read']['ry'] == p['given']['ry']


def held(p, side, name):
    return p[side][name] > 30


# The pad the script drives: the one with presses.
port = next((p['port'] for p in P if p['btn'] or any(p['read'][k] for k in NAMES)), 2)
P = [p for p in P if p['port'] == port]

enter = changes('module_vt', GAME_VT)
check(len(enter) == 1, 'the game module was entered once: %s' % [s[0] for s in enter])
game_from = enter[0][0] if enter else 0
first_drive = next((f for f, d in D if d), None)
check(first_drive is not None and first_drive > game_from,
      'driving begins after the game module is up (module at flip %d, driving at %s)' % (game_from, first_drive))

# 1. Until driving begins (boot, front end, garage, loading, intro): the pad
#    reaches the title as it was read, in either scheme.
pre = [p for p in P if p['flip'] < (first_drive or 0)]
check(len(pre) > 10 and all(same(p) and p['layout'] == 'xbox' for p in pre),
      'front end, garage, loading, intro: %d pad changes, every one given as read' % len(pre))
check(any(held(p, 'given', 'a') for p in pre) and any(p['btn'] & 0x10 for p in pre),
      'the menus were driven with A and Start, given as A and Start')

# 2. The gate is off whenever the title's own state says "not driving".
pause_on = [s[0] for s in changes('paused_by') if s[3] != 0xFFFFFFFF]
pause_off = [s[0] for s in changes('paused_by', 0xFFFFFFFF) if s[0] > game_from]
for f in pause_on:
    check(gate_at(f) == 0, 'paused at flip %d: the gate is off on that flip' % f)
ps2_flips = [g for g in G if g[2] == 'ps2' and g[1] == port]
if scheme == 'xbox':
    check(not ps2_flips, 'xbox scheme: the PS2 layout was never applied')
    check(all(same(p) and p['layout'] == 'xbox' for p in P),
          'xbox scheme: all %d pad changes given as read' % len(P))
else:
    check(bool(ps2_flips) and all(gate_at(g[0]) for g in ps2_flips),
          'ps2 scheme: the PS2 layout came on %d time(s), each with the gate on' % len(ps2_flips))
    check(all(p['layout'] == 'xbox' for p in P if not gate_at(p['flip'])),
          'ps2 scheme: no pad change was given in the PS2 layout with the gate off')

acc = BOTTOM if scheme == 'ps2' else 'rt'


def speed_gain(lo, hi):
    v = [speed[f][0] for f in sorted(speed) if lo <= f <= hi]
    return (max(v) - v[0]) if v else None


def hold(name, after, layout=None):
    """The first pad change at or after `after` with `name` read down (alone
    among the analog buttons), and the flip it is let go."""
    for i, p in enumerate(P):
        if p['flip'] >= after and held(p, 'read', name) and (layout is None or p['layout'] == layout) \
                and not any(held(p, 'read', k) for k in NAMES if k != name):
            end = next((q['flip'] for q in P[i + 1:] if not held(q, 'read', name)), p['flip'] + 600)
            return p, end
    return None, None


if event == 'race':
    # 3. The accelerator of the scheme accelerates, the other one does not.
    p, end = hold(BOTTOM, first_drive)
    check(p is not None, 'the bottom button (the title\'s %s) held while driving (flip %s to %s)'
          % (BOTTOM.upper(), p and p['flip'], end))
    if p:
        g = speed_gain(p['flip'], end)
        if scheme == 'ps2':
            check(p['layout'] == 'ps2' and p['given']['rt'] == 255 and p['given']['a'] == 0
                  and p['given']['b'] == 0,
                  'ps2: the bottom button reaches the title as the right trigger at 255')
            check(g is not None and g > 5.0, 'ps2: the car accelerates on it (+%.1f m/s)' % (g or 0))
            check(all(speed[f][2] == 255 for f in speed if p['flip'] + 2 <= f < end - 1),
                  'ps2: the title read rt 255 on every frame of the hold')
        else:
            # (A is the boost there: with some boost in the bar the car does gain.)
            check(same(p) and all(speed[f][2] == 0 for f in speed if p['flip'] <= f < end),
                  'xbox: A is given as A, and the title read no accelerator during the hold')
    # 4. Start with the button still down: paused on the next read, and the
    #    button is not a press in the menu.
    check(len(pause_on) >= 2, 'paused twice: %s' % pause_on)
    cd = next((s[0] for s in changes('p1_countdown') if s[0] > game_from and s[3] != 0xBF800000), None)
    seq = [d for f, d in D if f >= game_from]
    check(first_drive == cd and seq == [1, 0, 1, 0],
          'the gate: on with the countdown (flip %s), off and on around the first pause, off at the second: %s'
          % (cd, seq))
    if pause_on:
        f = pause_on[0]
        at = [p for p in P if p['flip'] == f]
        prev = [p for p in P if p['flip'] < f][-1]
        check(prev['btn'] & 0x10 and held(prev, 'read', BOTTOM),
              'Start arrived with the bottom button down (flip %d)' % prev['flip'])
        if scheme == 'ps2':
            check(prev['layout'] == 'ps2' and prev['given']['rt'] == 255,
                  'ps2: that read was still driving (rt 255)')
            check(len(at) == 1 and at[0]['layout'] == 'xbox' and at[0]['latched']
                  and held(at[0], 'read', BOTTOM) and not held(at[0], 'given', 'a')
                  and not held(at[0], 'given', 'b') and not held(at[0], 'given', 'rt'),
                  'ps2: on the pause flip %d the layout is off, and the held button is neither A nor the trigger' % f)
        release = next(p['flip'] for p in P if p['flip'] > f and not held(p, 'read', BOTTOM))
        check(not any(held(p, 'given', 'a') or held(p, 'given', BOTTOM) for p in P if f <= p['flip'] <= release),
              'the title saw no press from the held button (released at flip %d)' % release
              if scheme == 'ps2' else
              'xbox: A was down all along, no new press (released at flip %d)' % release
              if all(held(p, 'given', 'a') for p in P if f <= p['flip'] < release) else 'xbox: A flickered')
        # 5. The pause stays up until the real A press, and that press resumes.
        resume_press, _ = hold('a', release)
        r = pause_off[0] if pause_off else None
        check(resume_press is not None and r is not None and resume_press['flip'] < r
              and r - f > 100, 'the pause stayed up %s flips, until after the A press at flip %s'
              % (r and r - f, resume_press and resume_press['flip']))
        check(resume_press is not None and resume_press['layout'] == 'xbox'
              and held(resume_press, 'given', 'a') and not resume_press['latched'],
              'the A press in the pause menu was given as A (Resume)')
        check(r is not None and resume_press is not None and 0 < r - resume_press['flip'] < 120,
              'and it resumed the race (%s flips later)' % (r and resume_press and r - resume_press['flip']))
        # 6. The right trigger after the resume.
        p, end = hold('rt', resume_press['flip'] + 1 if resume_press else f, 'ps2' if scheme == 'ps2' else None)
        check(p is not None, '"rt" held after the resume (flip %s)' % (p and p['flip']))
        if p:
            g = speed_gain(p['flip'], end)
            if scheme == 'ps2':
                check(p['layout'] == 'ps2' and p['given']['b'] == 255 and p['given']['rt'] == 0,
                      'ps2: the right trigger reaches the title as B (crashbreaker), not as the accelerator')
            else:
                check(g is not None and g > 5.0, 'xbox: the right trigger accelerates (+%.1f m/s)' % (g or 0))
    # 7. Quit from the pause menu: d-pad, A, up, A, as on the Xbox layout.
    leave = changes('module_vt', FE_VT)
    leave = [s[0] for s in leave if s[0] > game_from]
    check(len(leave) == 1, 'Quit > Yes went back to the front end (flip %s)' % leave)
    if len(pause_on) >= 2:
        tail = [p for p in P if p['flip'] >= pause_on[1]]
        check(all(same(p) and p['layout'] == 'xbox' for p in tail) and not gate_at(pause_on[1] + 1)
              and all(d == 0 for f, d in D if f > pause_on[1]),
              'from the second pause to the front end: gate off, %d pad changes given as read' % len(tail))
else:
    cap = [p for p in P if game_from <= p['flip'] < (first_drive or 0) and held(p, 'read', 'a')]
    check(len(cap) >= 1 and all(same(p) for p in cap),
          'the A press on the captions was given as A (flip %s)' % [p['flip'] for p in cap])
    cd = next((s[0] for s in changes('p1_countdown') if s[0] > game_from and s[3] != 0xBF800000), None)
    check(cap and cd is not None and first_drive == cd and 0 < cd - cap[0]['flip'] < 200,
          'crash event: driving begins with the countdown (flip %s), after that press' % cd)
    seq = [d for f, d in D if f >= game_from]
    check(seq == [1, 0], 'the gate went on once and off once in the event: %s' % seq)
    p, end = hold(acc, first_drive or 0)
    check(p is not None, 'the accelerator held to the junction (flip %s)' % (p and p['flip']))
    if p:
        g = speed_gain(p['flip'], end)
        check(p['given']['rt'] == 255 and g is not None and g > 5.0,
              'the car accelerates on "%s" (+%.1f m/s)' % (acc, g or 0))
    crash = next((s[0] for s in changes('p1_state') if s[3] & 0x40), None)
    check(crash is not None and gate_at(crash) == 1,
          'the crash (state 0x40, flip %s) is still driving: impact time, aftertouch, crashbreaker' % crash)
    res = next((s[0] for s in changes('p1_results', 1)), None)
    check(res is not None and gate_at(res) == 0 and all(d == 0 for f, d in D if f >= res),
          'the results come up at flip %s: gate off from that flip on' % res)
    cont = [p for p in P if res and p['flip'] > res and held(p, 'read', 'a')]
    check(len(cont) >= 1 and all(same(p) and p['layout'] == 'xbox' for p in cont),
          'the A press on the results was given as A (flip %s)' % [p['flip'] for p in cont])
    leave = [s[0] for s in changes('module_vt', FE_VT) if s[0] > game_from]
    check(len(leave) == 1 and cont and leave[0] > cont[0]['flip'],
          'and Continue went back to the front end (flip %s)' % leave)

print('%s: %s scheme, %s event, %s face layout' % ('FAILED' if bad else 'ok', scheme, event, face))
sys.exit(1 if bad else 0)
