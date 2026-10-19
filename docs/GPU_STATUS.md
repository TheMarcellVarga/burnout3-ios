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


## Upstream performance backport, builds 28–30 (18 October 2026)

The implementation still follows burnout3-pc's native recompilation approach:
translated EE code and recorded VU programs compile into ARM64 machine code;
the GS renderer uses Vulkan through MoltenVK/Metal. It does not require an
emulator app, BIOS or JIT. Reproducing PS2 packet and local-memory semantics
still has a runtime cost. Native compilation alone does not guarantee 60 FPS.

The pinned base predates newer upstream performance work. Patch 0013 backports
the GPU changes from ps2-port-engine `aa3ce9dcc52c20ef2a0044bb8cb5d1f55c10a5c3`:
specialized fragment pipelines, asynchronous creation and persistent caching,
word gathers for texture filtering, cached layout tables and direct texture
decoding into images. It preserves the Apple local-read blend path and partial
write-back columns. Pipeline hints and the menu/crash 60 FPS overrides come
from burnout3-pc `b662c55f664042203246ee9afb4a803e997d3c77`. The whole upstream
checkout is not upgraded; the existing ARM64 and Apple host patches remain.

The mobile performance preset disables glow, speed blur and depth haze and
caps the world camera's far plane at 240 game units. Frontend/auxiliary cameras
are excluded from the far-plane override. VU1 uses upstream's conservative
fast-flags mode; VU0 remains exact. `--original-quality` retains the original
effects, world distance and exact VU1 flags for comparison. The internal
resolution remains 640×448; there is no measured basis yet to promise 2x/4x
rendering at 60 FPS.

Presentation now gives a normal-speed drawable up to one refresh to retire
instead of immediately dropping a completed frame when both slots are busy.
Accelerated loading retains nonblocking presentation. Patch 0014 brings the
upstream pending-interrupt retry fix and uses sleeping deadlines on iOS rather
than letting the timer spin on a performance core. Build 30 also includes the
upstream 60 FPS menu/movie and crash-slow-motion overrides.

Build 28 completed the actual race replay through frame 12000, with no reported
failure, thermal state Serious and Low Power Mode off. Across 33 two-second
intervals starting at frame 8000, geometry-transfer rate was min/median/max
30.0/58.4/60.0 per second and drawable presentation was 46.9/56.9/60.4 FPS.
Median presentation jitter was 3.60 ms. Some 60 FPS presentations repeat an
image while the game's crash mode draws at 30; presentation count alone must
not be reported as 60 unique game frames. This is a large improvement over
the build 22 median of 28.3 presented FPS, but is not a locked-60 claim.
Evidence: `local/reports/iphone-race-specialized.{json,log}`, the corresponding
GPU-test JSON and the frame-12000 image.

All six Mac regression groups pass, including the upstream renderer and local
mask/partial-transfer tests. The copy-blend fallback also passes. Fast VU mode
matches 512 real race snapshots for registers, memory, CLIP, timing and GIF
packets; omitted MAC/STATUS results are intentionally excluded. The captured
race replay differs from the older renderer in 703/286720 RGB pixels, with
maximum channel difference 8/255; GS memory is consequently not byte-identical.
These upstream shader/filter changes must not be described as pixel-exact.


## Main-scene counters and ARM64 cleanup, builds 35–39

Patch 0015 avoids presenting a target whose image, draw serial, memory mutation
serial and size have not changed. Patch 0016 extends the existing SSE
known-clean register/accumulator tracking to ARM64 NEON, avoiding repeated
normalization only when the same existing proof applies. Exact and fast modes
both pass 512 captured race states (fast mode intentionally excludes MAC/STATUS).
An interleaved five-run Mac capture benchmark improved warm medians from
6.36 to 5.85 ms and 7.62 to 7.08 ms; this is an isolated VU result, not a claim
of that percentage for the whole iPhone game. All six Mac regression groups
pass after these changes.

Build 35 added a counter at the actual main-world render entry, independent of
VIF DMA and screen refresh. It measured a median 49.75 main-world submissions/s
in the replay. Build 36 measured 47.45 on a different trajectory; the exact
NEON cleanup alone did not establish a whole-game improvement.

The single-player renderer builds four cameras. Captured GS descriptors confirm
that view 0 is the 640×448 display target (FBP 0x46), while views 1–3 are
128×128 targets (FBP 0x18B, 0x193, 0x19B). Build 38 experimentally kept their
first render and skipped subsequent auxiliary rendering. Across 42 two-second
main-world intervals its min/median/max was 45.4/59.9/61.1 submissions/s;
33 displayed-frame intervals from blank 8000 were 52.4/59.4/60.4 FPS.
It completed blank 12000, thermal state Serious, Low Power Mode off.
However, simply retaining their contents is invalid: the GS reuses those pages,
and the cars then sample corrupted reflections. This experiment is not the
shipped quality solution. Evidence is in
`local/reports/iphone-race-static-aux-{result.json,run.log}`.

Patch 0017 adds an explicitly enabled Burnout 3 mobile reflection-overlay
omission, restricted to main targets sampling the game's small RGB reflection
maps at FBP 0x16B–0x1A7. It avoids sampling scratch contents when auxiliary
cameras are disabled. Original-quality rendering and renderer pixel tests
retain the full pipeline. Build 39 completed the on-device visual/performance check for this combination:
42 main-world intervals measured 44.1/59.6/61.0 submissions/s, and 33 presented
intervals from blank 8000 measured 56.9/59.9/60.4 FPS. Car paint and decals are
clean in the blank-9000 and blank-12000 images; the mobile cars lose their live
reflection overlay. The device GPU and math checks pass. Evidence:
`local/reports/iphone-race-flat-{result.json,run.log,gpu.json,runtime.json}`.

Build 40 made this the default mobile preset and tested a 180-unit main-world
far plane. It completed blank 12000: main-world min/median/max was
43.6/59.45/60.8 submissions/s and presented intervals from blank 8000 were
56.9/59.5/60.0 FPS. It did not establish an improvement over the 240-unit clip;
build 41 restores 240. Its GPU/math checks pass and paint/decals remain clean.
Evidence: `local/reports/iphone-race-performance-{result.json,run.log}`. `--original-quality` restores
original effects/distance, all auxiliary views and exact VU flags.
`--live-reflections` retains just the live reflection path for comparison.
The diagnostic `--aux-refresh`/`--static-aux` switches control auxiliary cadence;
these are not required for normal performance mode.


Patch 0018 computes primitive vertex extrema once and reuses them for target
bounds and scissor rejection. The captured race GS replay's final displayed
BMP and all 4 MiB of GS memory remain byte-identical before/after this cleanup.
All six Mac regression groups pass again. This reduces redundant per-primitive
work; no isolated speedup percentage is claimed. The software-renderer fallback
keeps auxiliary cameras because the reflection omission is in the GPU bridge.


Build 41 completed blank 12000 with no reported failure and the default mobile
preset (240-unit far clip, flat reflections, reduced postprocessing). All six
Mac groups and the physical-device GPU/math checks pass. Across 42 main-world
intervals min/median/max was 44.4/59.5/60.9 submissions/s; 33 displayed intervals
from blank 8000 were 57.4/59.4/60.4 FPS. Thermal state was Serious and Low Power
Mode was off. This still does **not** satisfy a locked-60 requirement: screen
refresh may repeat during busy geometry sections. Evidence:
`local/reports/iphone-race41-{result.json,run.log,gpu.json,runtime.json}`.
A subsequent profiling run is diagnostic and must not replace this unprofiled
measurement in performance claims.


## Original camera distances and macro batching, builds 44–45

The user clarified that PS2-equivalent visibility takes priority over locked 60,
with drops around 30–40 FPS acceptable. Increasing the clip to 600 (build 42)
and 400 (build 43) did not meet the visibility goal; observed busy intervals
also fell below 30. These were diagnostic runs, interrupted before their targets,
and must not be presented as completed race benchmarks. Their logs are
`iphone-race42-600-rejected.log` and `iphone-race43-400.log` in local/reports.

Build 44 removes the world-distance override entirely. The observer logs
original world-camera values of 2000 and 10000 game units; these are clip planes,
not metres or a universal visible horizon. Fog, object culling and LOD still
belong to the original game. Its real race check reaches blank 8400 with no
reported failure. Eleven main-world intervals measured 23.6/27.9/47.8
min/median/max submissions/s, thermal state Serious. Original visibility is
restored, but the busy-scene rate still needs improvement. Evidence:
`local/reports/iphone-race44-original-{result.json,run.log}`.

The build-41 Time Profiler recording eventually started after a device-service
delay and captured actual race work. Its main CPU leaf hotspot is VU0 macro
floating-point state save/restore. Patch 0019 shares that scope across strictly
adjacent macro instructions, preserving the same instruction bodies and the
caller's full floating-point environment, including on exceptions. The emitter
ends every batch at a label, control flow, scalar FP, memory operation or call.
It reduces 31851 static macro sites to 20114 rounding scopes (6779 batches);
this is a static count, not a measured frame-rate gain. Differential tests
compare batched and individual instructions across all four host rounding modes,
including masks, aliases, zero, denormals, overflow, infinity, NaN and exceptions.
Both console and verification modes pass, as do all six Mac regression groups.
Build 45 is the physical-device performance check with original view distances.

The isolated synthetic 12-instruction Mac benchmark processes 2.4 million
instructions in median 96.138 ms individually versus 22.608 ms batched across
five interleaved runs. Registers match. This overstates the expected whole-game
gain because real groups vary in length and VIF/GS/Metal work remains.
Evidence: `local/reports/macro-batch-benchmark.txt`.


Build 45 completed the physical iPhone race through blank 12000 with no reported
failure, original camera values unchanged and `world_far_clip_override: 0`.
Across 42 main-world intervals it measured min/median/max
47.0/59.9/61.1 submissions/s; 33 presentation intervals from blank 8000 measured
53.6/59.4/60.0 FPS. The first scene interval includes the starting boundary,
which can add one counted submission; values above 60 are interval phasing,
not a higher simulation rate. The run submitted 4985 main-world scenes,
processed 7,905,419,786 VU1 pairs and completed in 123.657 seconds including
accelerated boot. Thermal state was Serious; Low Power Mode was off.
The phone's GPU and extended runtime/math checks both pass. Paint/decals,
traffic, HUD, distant scenery and the actual race are visible in the blank-9000
and blank-12000 images. Its improvement is observed under this replay, not a
controlled percentage attributed solely to batching; trajectories vary.

This satisfies the revised target for this checked race: original view distance
and dips above the accepted 30–40 range. It does not establish locked 60 for
all tracks, cars or long thermal sessions. Original-quality effects remain
available via `--original-quality`; no camera clipping is applied in either
preset. The app was then relaunched normally without diagnostic flags.
Evidence: `local/reports/iphone-race45-original-{result.json,run.log}`,
`iphone-race45-{gpu,runtime}.json`, and the corresponding race images.


## Original car materials, build 46

The user found build 45's cars visibly worse than PS2. The asset meshes and LOD
rules had not been replaced; the flat-reflection mode omitted the car's normal
environment-map overlay, flattening paint and glass. Build 46 restores live
reflection sampling and all four world/reflection cameras every frame by default.
Original camera distances remain unchanged. The old simplified materials are
available only as an explicit `--flat-reflections` diagnostic. Periodic/stale
auxiliary-map switches were removed from startup selection, since the GS reuses
those pages and simply retaining them is not safe.

The existing build-45 binary was checked with `--live-reflections` before the
default changed. That complete blank-12000 replay measured main-scene
min/median/max 28.9/45.5/60.2 submissions/s across 42 intervals, thermal state
Serious. Car-selector and race screenshots show reflective paint/glass with
clean original decals. This restores appearance at a measurable performance
cost; the old 59.9 median/47 minimum is not a claim for this material preset.
Evidence: `local/reports/iphone-live-car-{result.json,run.log}` and its images.

The first build-46 check stopped before its target and is not a completed soak.
A fresh default-preset run is being checked; the current device GPU and extended
math checks pass. No renderer/math code changed after the six Mac regression
groups passed for build 45; this change selects the original material path.


The fresh build-46 default-preset check completed blank 12000 with no reported
failure. Its result confirms `flat_reflections: false`,
`auxiliary_refresh_interval: 1`, `car_materials: original live reflections`,
and `world_far_clip_override: 0`. Across 42 main-world intervals it measured
24.7/48.55/61.0 min/median/max submissions/s. Across 33 presentation intervals
from blank 8000 it measured 47.2/54.7/60.4 FPS. These are distinct metrics;
repeated display refreshes must not hide the sub-30 main-scene intervals.
Thermal state was Serious and Low Power Mode was off. Its GPU and extended
math checks pass with fresh timestamps. Default car-selector and race images
show the original glossy paint, reflective glass and decals, with the world
camera distances retained. The preferred 30–40 floor remains unresolved in
busy sections with these materials enabled; the visual restoration is not a
claim that performance is solved.

The app was relaunched without diagnostic flags after the test.
Evidence: `local/reports/iphone-race46-{result.json,run.log,gpu.json,runtime.json}`,
`iphone-race46-selector.png`, `iphone-race46-race.png` and the normal launch JSON.


## Graphics-preserving backpressure fix, build 47

The user accepted the restored car materials and requested eliminating the
remaining large drops without reducing graphics. A fresh build-46 full-reflection
Time Profiler capture identifies repeated `Feed::WaitFor` yield calls as a
major leaf hotspot during the busy race section (samples after second 45):
1075 samples at the system yield call came directly from GS-ring backpressure,
with further samples from frame synchronization. The VIF1 worker was repeatedly
spending CPU while it could not submit more work, competing with the consumer.
Evidence: `local/runs/race46-live-cpu.trace`, its exported XML and the app-only
symbolicated analysis. This profiled run is diagnostic, not a new FPS benchmark.

Patch 0020 changes Apple GS-ring space/drain waits to predicate-based condition
variables. The consumer notifies after 16 KiB of progress and at the end of each
batch, including short batches and failure. Notification takes the same mutex
as the predicate check/wait transition, preventing lost wakeups. Packet order,
queue capacity, VU arithmetic, textures, shaders, reflection cadence, car meshes
and original view distance are unchanged. Non-Apple wait behavior is retained.

A new regression deliberately stalls the consumer until the 16 MiB ring fills,
then forces ring wraparound, verifies all 1.4 million frame records in order,
checks drain completion and propagates a consumer exception. The old code
fails its waiting-CPU budget: 70.02 ms wall / 69.88 ms producer CPU. The new
code passes: 65.04 ms wall / 0.02 ms producer CPU. All seven Mac regression
groups pass after relinking the host; the concurrency regression also passes
ten consecutive runs. Patch preparation recognizes all 20 engine patches.
Evidence: `local/reports/gs-wait-{baseline,fixed}.txt`,
`build/race47-regressions.log` and `build/race47-wait-stress.log`.

Build 47 completed the physical-device soak to blank 12000 in 126.53 seconds,
without failure, with original live reflections, all four views and original
camera distances. Across 42 two-second scene intervals, min/median/max was
32.4/46.4/60.9 submissions/s (build 46: 24.7/48.55/61.0). The minimum improved,
but the median did not, and this does not establish a stable 40 or 60 FPS floor.
Both runs reported thermal state 2, with low power mode disabled. Device GPU and
runtime checks pass. Evidence: `local/reports/iphone-race47-{result.json,run.log}`,
`iphone-race47-gpu.json`, and `iphone-race47-runtime.json`. The isolated wait
improvement must not be reported as a whole-game speed multiplier.

## Exact zero-area triangle rejection, build 48

An offline replay of the captured race frame contains 54,989 primitives, of
which 53,695 are triangles and 3,112 have exactly zero area. Patch 0021 rejects
only those triangles before GPU texture/target bookkeeping. The determinant
uses double arithmetic on the GS's exact 1/16-pixel coordinates; all possible
products fit exactly, so skinny nonzero triangles remain. Point, line and
sprite primitives are unaffected. This does not change meshes, LOD, materials,
reflection cadence, resolution or camera distance.

The captured race replay before and after produces byte-identical screen.bmp,
screen_1x.bmp and all 4 MiB of GS memory. Evidence: `local/runs/race48-before/`
and `local/runs/race48-after/`. Full-memory SHA-256:
`1015cf6de514ad8994d572203cb751b760e3bcdecd7f02cd26c91fe0e5bc9a6d`.
Build 48 completes the device soak to blank 12000 without failure in 132.19 s,
at thermal state 2 and with low power mode disabled. Across 42 two-second
scene intervals, min/median/max is 30.0/47.0/60.8 submissions/s; seven intervals
are below 40. This is not a consistent improvement over build 47, and a stable
40 FPS floor remains unresolved. The replay equality establishes correctness,
not a whole-game performance gain. All seven Mac regression groups pass, and
the physical-device GPU and runtime checks pass for build 48. Evidence:
`local/reports/iphone-race48-{result.json,run.log,gpu.json,runtime.json}` and
`build/race48-regressions.log`. The final-frame image is
`local/reports/iphone-race48-race.png`. A subsequent profiled run is diagnostic
and must not replace these unprofiled benchmark results.


## DMA snapshot copying, build 49

A fresh build-48 Time Profiler capture, filtered to the busy race after second
45, confirms the previous repeated GS yield hotspot is absent from the top
leaf samples. Copying queued DMA payloads remains prominent: 603 leaf samples
in vector insertion, including 423 directly from the EE chain snapshot path.
Evidence: `local/runs/race48-live-cpu.trace` and its app-only symbolicated report.

Patch 0022 retains initialized DMA snapshot storage across pool reuse and
appends using memcpy. Only the used prefix and recorded runs are consumed;
packet bytes and order, guest-memory snapshot timing, ownership and worker
completion are unchanged. Storage grows when needed and remains bounded by
the existing pool policy. New regressions cover a chain larger than the initial
buffer, split and empty runs, source mutation after the snapshot, and reuse
with a shorter chain. All seven Mac groups pass. An isolated Mac copy workload
has median 44.466 ms before / 39.455 ms after across seven runs (about 11% faster
in this copy workload, not whole-game FPS). Evidence:
`local/reports/dma-copy-bench.txt`, `build/race49-regressions.log`.
Build 49's full device race completes without failure in 168.86 seconds,
with thermal state 2 and low power mode disabled. Its 41 two-second scene
intervals measure min/median/max 18.4/23.8/36.6. This is materially worse than
the earlier runs. The loading/selection sequence was already roughly half
as fast before asynchronous DMA copying became active, so this run cannot
isolate the copy change; the cause of the slowdown is not established. Device
GPU and runtime checks still pass. Evidence:
`local/reports/iphone-race49-{result.json,run.log,gpu.json,runtime.json}`.
No stable 30/40/60 FPS floor can be claimed across these runs.


## Explicit iOS Game Mode eligibility, build 50

The user reports that iOS does not recognize the app for Game Mode. The source
and packaged plists were missing explicit Game Mode support and a game category.
Build 50 adds boolean `LSSupportsGameMode=true` (Apple's current key, available
from iOS 18.6), boolean `GCSupportsGameMode=true` for iOS 18.0–18.5 compatibility,
and `LSApplicationCategoryType=public.app-category.racing-games`. The packaged
Release app is checked for the actual boolean types and values, not merely the
source template. Build 50 retains build 49's renderer and graphics settings.

Apple documents that omission of LSSupportsGameMode can prevent Game Mode from
turning on: https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode
This makes the app eligible; activation on the phone and any FPS benefit still
need verification. It does not establish that Game Mode caused prior drops.


## POC performance priority, build 51

The user revised the immediate goal to a 50–60 FPS proof of concept, leaving
visual kinks for later. Build 51 makes the known fast flat-reflection preset
the default again: every-frame main world, original camera distances, meshes,
textures and LOD; dynamic reflection cameras and their overlays are disabled.
The existing reduced blur/glow/depth-haze preset remains. This is an explicit
quality tradeoff, not a claim that the full-material bottleneck is solved.
`--live-reflections` restores the fuller current material path; `--original-quality`
restores original effects as well. The prior build-45 fast-preset race's
47.0 minimum / 59.9 median is historical evidence, not a build-51 measurement.

The user reports no Game Overlay entry with build 50. Build 51 uses the general
`public.app-category.games` category and retains both Game Mode support keys.
Before fresh installation, all 110 Documents/Library files were backed up,
including the complete 2,867,822,592-byte disc and saved profiles. Memory-card
hashes match the earlier separate backup. Evidence:
`local/backups/build50-game-mode/backup-file-sizes.json` and
`memcard-sha256.json`. Restoration is complete, and saved-profile hashes read back from the phone
match the backup. The full 2,867,822,592-byte disc is present. Launch is currently
blocked by iOS's Security/developer-trust rejection after fresh installation.
`codesign --verify --deep --strict` passes, the profile includes the phone and
expires on 2026-10-23. The user has been asked to trust the developer profile.
Fresh race and Game Mode validation remain pending. Evidence:
`local/backups/build50-game-mode/restored-memcard/` and
`local/reports/iphone-build51-restored-files.json`.


## POC short-race results and bounded distance tradeoff, build 52

Build 51 completes the short physical-device race test to blank 8400 in 71.04 s,
without failure, with flat_reflections=true, auxiliary interval 0 and original
camera distances. Across 12 two-second scene intervals, min/median/max is
42.9/51.85/61.0 submissions/s. Thermal state is 2. This improves the typical
rate substantially over full reflections, but is not a strict 50 FPS floor.
Evidence: `local/reports/iphone-race51-{result.json,run.log}`.

Build 52 retains the POC materials and changes only the known 2000-unit world
camera settings at the three observed world-camera callers to 1700 (15% shorter).
The 10000-unit camera settings and unrelated cameras are unchanged. The original
setter computes projection/frustum data; its caller's f12 argument is restored.
`--ps2-distance` retains original distances with the fast materials, while
`--live-reflections` restores full reflection materials and original distances.
The on-device report records the override instead of claiming PS2 distance.
A targeted harness links the actual mobile-quality source and tests all three
world callers, 10000 and 1500 distances, an unrelated caller, result/argument
preservation, and disabling the limit. All checks pass. Evidence:
`local/reports/poc-camera-check.txt`. Build 52 race validation is in progress.


## Original queue waits in the fast POC, build 53

Build 52's completed short race measured 39.8/51.25/60.9 min/median/max
submissions/s across 12 two-second scene intervals, thermal state 2, without
failure. The 1700-unit camera experiment did not improve the checked rate.
Build 53 therefore restores original camera distances rather than keeping an
unhelpful visual tradeoff. Evidence: `local/reports/iphone-race52-{result.json,run.log}`.

Patch 0023 allows selecting the original GS backpressure/drain yield waits
with `PS2HOST_GS_BUSY_WAITS`. The POC flat-material path selects them for a
physical-device comparison against the earlier near-60 build-45 setup. Other
material paths retain the condition-variable waits. This is a latency/CPU-cost
tradeoff, not an assertion that busy waiting is universally faster. The consumer
omits drained notifications in the busy-wait mode. Capacity, order, packet
contents and mathematics are unchanged.

The concurrency regression passes ordered wraparound, drain and exception
checks in both modes. The sleep mode additionally enforces its low waiting-CPU
budget. Latest samples: sleep 65.05 ms wall / 0.01 ms CPU; busy mode 63.92 ms
wall / 60.81 ms CPU. The latter intentionally uses CPU to poll and must not be
called an energy optimization. Evidence:
`local/reports/gs-{sleep,busy}-queue53.txt`. The short device comparison is running.
