# Vulkan/Metal graphics bring-up — 17 October 2026

The Apple GPU path reuses the pinned upstream Vulkan GS renderer, linked
directly to MoltenVK 1.4.2. MoltenVK executes its graphics and compute work via
Metal. SDL and a desktop Vulkan loader are unnecessary for the existing UIKit
app. The native interface, audio and controller implementation remain in place.

## Verified on Mac

- All upstream GPU pixel-test groups pass on Apple M3 Pro through MoltenVK.
- All six CTest groups pass with GPU support compiled into the Apple host.
- The real game reaches frame 1,200 with `Gs::rasterize` disabled: 198,310
  primitives and zero CPU-rasterized pixels. The bounded run reports 2.7 seconds;
  this is a Mac observation, not an iPhone benchmark.
- Its image shows the original memory-card prompt. Against the software reference,
  mean RGB channel difference is 1.230/255, maximum 16/255; 54 of 860,160 channels
  differ by more than 8. The GPU's known blending/16-bit quantization differences
  remain; this is not bit-exact rendering.

The initial Metal checks failed partial colour masks because Metal does not
expose Vulkan fixed-function logic operations. Patch 0005 handles partial masks
in the fragment shader using a destination copy, preserving masked bits after
blending. The existing 32-bit and 16-bit pixel checks both pass afterward.
The instance initialization also checks whether portability enumeration is
advertised, since direct MoltenVK linking does not expose the loader extension.

## iPhone status

Build 9 is installed with GPU drawing enabled by default. The upstream pixel
checks pass on the physical iPhone 15 Pro Max through MoltenVK/Metal. Two extra
regressions cover partial masks after blending and overlapping masked draws.
The final pixel-test report is `local/reports/iphone-gpu-tests.json`.

- First combined pixel-test/startup run: 4.764 seconds, frame 1,200 reached.
- Separate startup-only run with the shader cache warm: 0.870 seconds, frame
  1,200 reached; software drawing time 0%, device thermal state Nominal.
- Longer scripted run: frame 4,000 reached in 15.126 seconds and the original
  Burnout 3 title screen displayed on the phone. CPU rasterization remains off;
  the GPU is reported active. The device stays in thermal state Nominal.
- The phone startup frame's mean RGB channel difference against software is
  1.230/255, maximum 16/255, matching the Mac comparison. Inspectable device
  output is `local/reports/iphone-gpu-title.png`.

These are bounded observations, not a racing-FPS benchmark. Shader-cache and
thermal conditions differ from the earlier ~19.7-second software startup run.
They establish GPU execution and substantial startup headroom, not complete game
correctness or sustained racing performance.

Normal launches keep the existing audio and transparent analog/touch controls.
`--software-renderer` selects the CPU fallback for diagnosis. `--gpu-tests` runs
pixel checks and then continues into normal play. `--gpu-title-test` performs the
bounded scripted title check; ordinary launches do not automate player input.

GPU rendering uses the upstream local-memory ownership and texture cache bridge.
The initial UIKit presentation reads back the GPU output into the existing image
view. This moves GS rasterization onto the GPU, but is not a zero-copy display
path. Sustained racing performance, zero-copy presentation, and later game scenes remain unverified.

## Reproduce

```sh
python3 scripts/prepare_native.py
python3 scripts/prepare_gpu.py
cmake -S . -B build/cmake-gpu -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DBURNOUT_BUILD_GPU=ON
cmake --build build/cmake-gpu --target apple_gpu_tests --parallel 2
build/cmake-gpu/apple_gpu_tests
python3 scripts/configure_ios.py --native-boot --gpu --build
```

Dependencies and SHA-256 checks are pinned in `native/gpu/dependencies.json`.
MoltenVK's Apache license and glslang's license notices stay in their extracted
source/package directories. Generated SPIR-V, downloaded libraries and game
assets are ignored. Patches 0001–0005 apply sequentially to clean pinned engine
source. Mac evidence lives under `local/runs/gpu-mac-initial/` and `build/`.

Final live-run verification: the log identifies Apple A17 Pro as the active GPU
instead of the software GS. Later 120-frame intervals report 59.9–60.0 simulation
frames/second, GS-thread busy 27–30% and GPU busy 4–6% in this menu. The audio
engine is running on Speaker, with nonzero game and rendered samples, one
underrun and zero dropped frames at the captured snapshot. This is menu evidence,
not sustained race validation. See `local/reports/iphone-gpu-live.log` and
`local/reports/iphone-gpu-audio.json`.

## Car geometry performance

The original phone run drops to 13.9–14.3 vertical blanks/second, about seven
VIF1 geometry updates/second, once cars appear. GPU busy time is only 8–9%.
The Apple build had linked no compiled game VU microprograms: geometry was
interpreted, and ARM used scalar arithmetic where the x86 host uses SIMD.

The host now compiles captured microprograms from the ignored
`local/native/vu_programs.txt` with upstream `vurecomp.py`. Registration objects
reach both final executables directly, avoiding static-archive dead stripping.
Instruction-memory checks and interpreter fallback remain active. Patch 0006
adds ARM64 NEON arithmetic to the macro and compiled micro paths, preserving
chop rounding, denormal cleaning, saturation, masked writes and separate
multiply/add rounding. ARM rounding scopes save and restore FPCR/FPSR directly.
Preparation recognizes overlapping patches using disposable file copies.

Validation on the captured compact-car selector:

- All 256 real phone VU captures match the interpreter in registers, flags,
  memory, cycle state and emitted GIF packets. All 603,466 instruction pairs
  in these captures execute compiled. Run the comparison with
  `build/cmake-game/vu_capture_tests local/runs/iphone-geometry-first/vu-snapshots.bin`.
- All six Mac CTest groups pass, including the randomized VU corpus and GPU
  pixel tests. ARM64 and Rosetta x86_64 math checks pass in console and
  verification rounding modes. The physical phone's runtime checks also pass.
- The unpaced phone selector sustains 74.7–79.2 vertical blanks/second,
  37.4–39.6 VIF1 updates/second, across the measured steady intervals. All
  1,509,970,477 VU1 pairs in that complete run execute compiled.
- The interpreter and compiled selector images at frame 5,400 are pixel-identical
  (640 × 448). The optimized frame is `local/reports/iphone-car-compiled.png`.
- Signed build 17 completes the paced replay in 100.725 seconds, with no
  host failure and all VU1 pairs compiled. Steady selector intervals hold
  59.9–60.0 vertical blanks/second and 29.9–30.0 VIF1 updates/second. Thermal
  state is Fair. Evidence: `local/reports/iphone-geometry-paced.json` and
  `local/reports/iphone-geometry-paced.log`. The app was then relaunched normally.

Phone evidence: `local/reports/iphone-car-lag-before.log`,
`local/reports/iphone-geometry-compiled.log`,
`local/reports/iphone-geometry-compiled.json`, and
`local/reports/iphone-geometry-runtime.json`. These establish the measured
selector's performance and equivalence, not sustained racing or every car variant.

For repeatable phone measurements, copy a standard recorded pad stream to
`Documents/geometry-input.txt` and launch with `--geometry-test`. This runs to
frame 6,000 with a disposable memory card. Add `--geometry-paced` for normal
60 Hz pacing, or `--geometry-interpreter` for the interpreter baseline. Add
`--geometry-capture` only to collect new microprograms and VU states; its
per-invocation microcode traversal substantially slows the run and must be
disabled for performance measurements. Merge new captured program lines into
the local manifest and reconfigure before building. Captures and generated game
code stay ignored. Normal launches use none of these diagnostic options.

## Race performance, build 24

The original iOS host always selected the deterministic test clock. That also
prevented the engine's real-time VIF1 worker from starting, so geometry ran on
the simulation thread. Normal play now uses the real-time scheduler and
asynchronous VIF1 worker. Bounded boot/selector diagnostics retain deterministic
timing. The race replay switches from deterministic boot to real time at frame
6,000, before race rendering begins; `--race-virtual-clock` retains the old mode
for comparison. Measure geometry and actual presentation as well as the timer:
60 vertical blanks alone do not establish 60 distinct rendered pictures.

The old iOS display path synchronously read each GPU picture into a CPU-backed
UIImage. `native/ios/gpu_display.mm` now provides a CAMetalLayer-backed
`ps2gpu::Display`, using the engine's existing `PresentGpuPicture` path. Vulkan
and Metal share the same underlying command queue; synchronous MoltenVK submit
encoding and the engine's queue lock preserve submission order. The shader
samples the visible rectangle, and Core Animation preserves aspect-fit layout.
Two presentation-tracked slots bound queued drawables, reserving the third for
the visible surface. Surplus loading blanks are dropped before requesting a
drawable, with a loose 8 ms CPU limit that allows normal 60 Hz arrival jitter.
Presentation statistics use the drawable's actual presented timestamp. The
startup shader check verifies channel order and orientation with asymmetric
colors. Native presentation is immediate and bounded by drawable availability;
the timed-presentation experiment described below was not retained. CPU-produced pictures can still be uploaded, and `--cpu-display` retains
the previous image display path as a diagnostic fallback.

The ignored VU manifest now includes 91 programs. Patches 0006 and 0009 add ARM64
SIMD arithmetic, integer/float conversions and cross products while preserving
separate rounding, truncation, saturation, masked writes and pipeline state.
Two sets of 256 real race/collision captures match the interpreter's full state
and GIF output: 473,611/473,611 and 560,959/560,959 instruction pairs compiled.
See `local/reports/race-neon-vu-{early,late}.txt`. The first longer real-time run
executes all 4,989,743,901 VU1 pairs through compiled code.

Patch 0008 enables capability-checked tile-local destination reads on MoltenVK
with `VK_KHR_dynamic_rendering_local_read`, input attachments and by-region
color-write/input-read barriers between existing non-overlapping batches. The
blend arithmetic and masks stay the same. Unsupported devices, or
`PS2HOST_GPU_COPY_BLEND=1` (`--copy-blend` on iOS), retain the copied destination.
See Vulkan's [local-read specification](https://docs.vulkan.org/features/latest/features/proposals/VK_KHR_dynamic_rendering_local_read.html).

Patch 0010 limits target/depth write-back compute work to dirty page columns.
It retains the previous full-width transfer for unusual wrapping layouts and
with `PS2HOST_GPU_FULL_WRITEBACK=1`. The recorded race requires 10,804,048
write-back pixel operations instead of 26,930,000, with byte-identical output
image and all 4 MB of graphics memory. Tests for 32-bit and both 16-bit formats
verify that a narrow transfer preserves every byte outside its GS block.

Patch 0011 marks foreground frame workers as User Interactive on iOS. CPU
profiles with matching binary UUIDs show VIF1/GS workers moving from roughly
42–50% of sampled time on performance cores to roughly 74–76%. This is a
scheduling hint; the OS retains control, including thermal throttling.

Patch 0012 computes the four lanes' MAC/STATUS zero and sign flags with NEON,
fused with the FMAC result instead of storing and reloading it for scalar flag
reconstruction. Sticky flags, lane masks, flag latency and complete final state
remain exact. Both capture sets still match all registers, flags, memory, cycle
state and GIF packets (`local/reports/race-flags-vu-{early,late}.txt`). Fast mode
that omits unobserved flags remains disabled.

All six Mac regression groups pass, including the new transfer guards. Build 22
also passed physical-phone runtime math checks, GPU pixel checks and the direct
presentation shader check. Its 12,000-frame run reached the target with no host
failure, all VU1 pairs compiled, Low Power Mode off and Serious thermal state.
Across 33 later race intervals, simulation has median 59.9 Hz (57.5–60.0),
geometry median 29.0 updates/second (23.1–33.9), and actual drawable presentation
median 28.3 FPS (24.3–32.5). This is not a 60 FPS rendering lock. Evidence:
`local/reports/iphone-race-flags.{json,log}` and
`local/reports/iphone-race-flags-{gpu,runtime}.json`.

Build 22 was relaunched normally and reported `playing` with the real-time
scheduler (`local/reports/iphone-race-build22-normal-launch.json`). Build 23 tested
Metal presentation deadlines under the same replay protocol. It completed with
no host failure, all 5,026,326,580 VU1 pairs compiled, Low Power Mode off and
Serious thermal state. Later intervals had median 27.5 FPS and median reported
jitter 11.54 ms, versus 28.3 FPS and 11.99 ms in build 22. The live runs do not
follow exactly identical rendered trajectories, so this is not a controlled
speed comparison; it provided no clear reason to retain the extra scheduling
path. Build 24 restores build 22's validated display implementation and keeps
the exact vector/graphics optimizations. Evidence for the experiment:
`local/reports/iphone-race-paced-display.{json,log}`.

The game clock is improved; the measured rendering limitation is still present.
Compiled VU execution and graphics submission remain the major CPU costs in the
matching-UUID profiles under `local/runs/race-{rect,priority}-cpu.trace`.
Sustained 60 FPS is not achieved by these changes.

Final build 24 was signed and installed after removing the timed-presentation
experiment. Its on-device math and GPU checks pass, the presentation shader
check passes, and a clean launch with no diagnostic arguments reports `playing`.
The normal startup log confirms the real-time VIF1 worker. Evidence:
`local/reports/iphone-race-release-{gpu,runtime,normal-launch}.json` and
`local/reports/iphone-race-release-normal.log`. The retained display implementation
is the one measured in the build 22 longer replay.

For a repeatable race, generate input with
`scripts/create_performance_replay.py --scene race`, copy it to
`Documents/race-input.txt`, and launch with `--race-test` (frame 8,400) or
`--race-soak` (frame 12,000). These use a disposable card. The stream confirms the
car with Cross, skips training with Start and holds the original PS2 accelerator
(Cross). Confirm a fresh result, nonzero `race_world_calls` and a HUD screenshot
before treating a run as racing. `--geometry-capture` records programs and VU
states but substantially slows execution; never use its rates as a benchmark.
`--race-state-capture` records states only. Game-derived captures stay ignored.

Blur/glow remain enabled. `--race-no-blur` was tested but did not resolve the
bottleneck and is a diagnostic option only. Full-race completion, other tracks,
all car variants and long-term thermal stability remain unverified.
