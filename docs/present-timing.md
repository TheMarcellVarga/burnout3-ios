# Frames on the glass: present timing (BO-115)

The toolkit's side (the strategies, the overlay graph, the traces) is in the
toolkit's `docs/runtime/present-timing.md`. This page has what was measured
with this game and how to measure it again.

Setting: `display.present_timing = legacy | auto` (F1 > Display > Frame
presentation; `RECOMP_PRESENT_TIMING`). The default is `legacy` until the
owner has compared the two on his variable-refresh monitor.

## How to measure

    RECOMP_TRACE=glass=<dir>/glass.csv,latency=<dir>/lat.csv   # a windowed run
    tools/perf/glass.py <dir>/glass.csv [--from FLIP --to FLIP | --pace <BO3_PACE_LOG file>]
    tools/perf/latency.py <dir>/lat.csv --presses-only --digital 01,02

`glass.py`: the on-glass interval histogram in display refreshes, the uneven
count, vblank-to-glass and the vblank interval. `latency.py`: press to glass
(its `D` row) on a still screen, as `tools/perf/latency_run.sh` drives it
(BO-74). The window must be visible for the whole run: a covered or minimised
window reports no on-glass times (`[PRESENT] window: not visible` in the log;
`RECOMP_DEBUG=window_float=1` keeps it on top, `window_display=<n>` picks the
display).

## Built-in 60 Hz panel (MacBook Air M5, macOS 26.7.1), 2026-10-12

Race on Silver Lake Southbound, about 880 frames of cornering, then 21
pause-menu presses; render scale 2, SMAA, 16:9, an 853x480 window (or
fullscreen). The Mac was shared with other agents' runs all day (load average
5 to 11). A run in which the title itself fell to 30 fps for part of the race
is no latency number; three such runs were made again and replaced, and the
cells that never got a clean run are listed below the table.

On-glass interval histogram is in refreshes of 16.67 ms ("1:874" = 874
intervals of one refresh). Times in ms.

| Power mode | Timing | On-glass intervals | Uneven | Vblank to glass p50 / p95 | Press to vblank p50 | Press to glass p50 / p95 | Flip interval p50 / p95 / p99 |
|---|---|---|---|---|---|---|---|
| Balanced, window | legacy | 1:874 2:1 | 1 (0.1%) | 59.5 / 59.6 | 39.3 | 98.1 / 106.7 | 16.67 / 16.67 / 16.69 |
| Balanced, window | auto | 1:874 | 0 | 21.67 / 21.67 | 38.8 | 60.4 / 68.3 | 16.67 / 16.67 / 16.68 |
| Maximum, window | legacy | 1:889 2:2 | 3 (0.3%) | 54.5 / 71.1 | 37.1 | 94.4 / 109.1 | 16.66 / 16.89 / 16.97 |
| Maximum, window | auto | 1:856 2:12 3:2 5:1 | 29 (3.3%), 17 frames skipped | 21.67 / 21.67 | 39.4 | 60.8 / 69.7 | 16.66 / 16.95 / 17.02 |
| Battery, window | legacy | 1:877 2:1 | 2 (0.2%) | 48.9 / 65.5 | 38.8 | 86.7 / 110.7 | 16.67 / 16.69 / 16.97 |
| Battery, window | auto | 1:866 2:3 6:1 | 12 (1.4%), 8 skipped | 21.67 / 21.67 | 39.4 | 61.0 / 70.4 | 16.67 / 16.69 / 16.73 |
| Balanced, fullscreen | legacy | 1:869 2:8 6:1 | 19 (2.2%) | 35.4 / 35.4 | 37.5 | 71.3 / 82.9 | 16.67 / 16.68 / 16.71 |
| Balanced, fullscreen | auto | 1:883 2:1 | 2 (0.2%), 1 skipped | 21.67 / 21.67 | 45.9 | 67.7 / 84.8 | 16.67 / 16.68 / 18.99 |

What holds in every run:

- `auto` puts a frame on the glass 21.67 ms after its emulated vblank (1.3
  frames: the 5 ms phase plus one refresh), the same at p5, p50 and p95.
  `legacy` is between 35 and 60 ms at p50 (2.1 to 3.6 frames), different from
  run to run and by up to a frame within one: the free 60.000 Hz timer has
  no fixed phase against the panel, and the two-drawable queue fills.
- Press to glass in a window fell from 86.7-98.1 ms to 60.4-61.0 ms (p50).
  Press to the emulated vblank did not change (37-39 ms).
- The flip interval is unchanged: with `auto` p95 16.67-16.95 and p99
  16.68-17.02 in a window (targets: 17.5 and 18.5); the fullscreen run's p99
  of 18.99 is one stall in that run.

Two things `auto` does worse:

- **It drops frames where `legacy` queues them.** When a frame misses its
  refresh (the compositor missed one, or the frame was picked up late),
  `auto` skips one frame to get back in step; `legacy` shows every frame and
  keeps the added frame of latency. In Maximum (busy-wait) that was 17 frames
  skipped of 890 (3.3% of the intervals uneven, against 0.3% with `legacy`),
  in Battery 8 of 879, in Balanced none and one. Whether the Maximum skips
  come from the 5 ms phase being too short for a present pass that competes
  with two spinning cores (`RECOMP_PRESENT_PHASE=8` would cost 3 ms of
  latency) has not been measured.
- **When the machine cannot hold 60 fps it is clearly worse.** Maximum in
  fullscreen did not hold 60 in either mode on this shared machine (`legacy`:
  153 of 869 frames at 33 ms, shown evenly). The `auto` run there skipped 124
  frames of 913 and picked 237 up too late for their refresh (32% of the
  intervals uneven). That cell needs a quiet machine before anything is
  concluded from it.

In a window a frame cannot be shown at the refresh right after its vblank:
with the vblank 10 ms before a refresh and the frame committed 0.3 ms after
the vblank, it was still shown one refresh later (the pacer raised its depth
from 0 to 1 by itself). 

## Not measured yet

- On the built-in panel: Battery in fullscreen (both modes); Maximum in
  fullscreen on a quiet machine; the same-refresh present in fullscreen
  (`RECOMP_PRESENT_DEPTH=0`, where the compositor may be bypassed); the phase
  at 5 against 8 ms in Maximum.

- The 120 Hz monitor (PG32UCDP), fixed and with VRR on, windowed and
  fullscreen: the owner's A/B (`play-glass.sh legacy|new [fullscreen]` in the
  session's scratch folder) writes the traces and prints these numbers.
  Expected at fixed 120 Hz: 13.3 ms from vblank to glass, every frame two
  refreshes.
- The variable-refresh strategy itself (`timed`), on any display.
- A ProMotion built-in panel.
- Vulkan on any host (Linux, Windows, Android, MoltenVK): presentation there
  is unchanged and the overlay says "not available". A measurement from
  `VK_KHR_present_wait` is on the toolkit branch `bo3/glass-vulkan`; it has
  been built on macOS only and has run nowhere.
