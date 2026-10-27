# iOS optimization check — build 9

23 October 2026, iPhone 15 Pro Max, 1× render scale / 4:3, Release build.

## Frame pacing comparison

Three sequential runs used the same boot/profile/main-menu input script.
The comparison takes five 5-second windows at approximately 55–75 seconds
after profiling began, after the menus settled. CPU uses getrusage for the
whole process, expressed as a percentage of one core. Flip times come from
the runtime's recent guest-flip ring, not an optical display measurement.

| Vblank spin lead | Mean process CPU | Mean recent flip p95 | Thermal states |
|---|---:|---:|---|
| 8 ms (old default) | 76.92% | 16.760 ms | Fair → serious |
| 1 ms | 58.18% | 19.106 ms | Serious |
| 4 ms (new default) | 52.98% | 16.744 ms | Serious |

The short menu comparison showed about 31% less CPU time at 4 ms with
comparable p95 guest flip timing. The 1 ms setting was rejected for less
consistent timing. Runs were sequential on a warm phone, not randomized or
thermally controlled. This is evidence for the default, not a battery-life
claim or proof of sustained race performance. Explicit environment overrides
remain available.

## Overlay and native UI

- Unchanged controls do not repaint. Dirty steering/button regions avoid
  repainting the whole overlay; paint reuses the input snapshot and label map.
- Touch events refresh the visual snapshot immediately; the game input itself
  still reaches the runtime directly.
- Native Settings and the Resume launcher hold the guest at a cooperative GPU
  pause and pause its audio. Session/background holds cannot release each
  other. The overlay display link stops while native UI owns input.
- Auto-lock is allowed on the launcher and prevented in gameplay.

The initial return/resume experiment showed frozen guest-flip counts while
paused, followed by resumed flips at the same Settings page. The resident
runtime still used CPU while held (roughly half a core in that initial
experiment). This is a live paused session, not a teardown or zero-cost idle.
The final revision also stops the overlay's display link while native UI is
open. Its race-pause return/resume check kept guest flips at 17,726 through the
hold, then advanced them after Resume; whole-process CPU while held was still
about 58% of one core. This remaining idle cost needs separate runtime-thread
profiling; the frontend does not claim to eliminate it.

## Evidence and remaining scope

Ignored run folder: `local/runs/iphone-20261023/`.

- `perf-spin8.log`, `perf-spin1-session.log`, `perf-spin4.log`
- `optimization-comparison.json`: five-window aggregates above
- `native-settings-page.png`: injected row rendered by the game's widget
- `native-panel-open.png`, `native-launcher-roundtrip.png`: native flow
- `host-tests-9.log`: seven focused suites pass

The host suites cover the menu row/count bounds, guest register preservation,
original Quit dispatch, pause ownership/idempotence/background nesting, and
the earlier controller, memory, preference/import and MMIO checks. Physical
comfort, audio quality, long race/thermal behavior and the earlier HUD issue
remain outside this short optimization check.
