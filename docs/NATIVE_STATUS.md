# Native development status — 17 October 2026

The real game runs on Apple Silicon through ahead-of-time translated ARM64 code.
The current iPhone build uses the Vulkan/Metal GPU renderer and reaches the
original title screen; the software GS remains a reference and fallback. A bounded Mac run reaches frame
1,200 and displays the game's memory-card prompt. The full native host also reaches
frame 1,200 on the physical iPhone 15 Pro Max, iOS 27.0.1. Landscape touch controls are connected; a complete playable race remains
unverified.

## Verified evidence

- The supplied NTSC-U SLUS_210.50 disc is read directly by the native host.
- 9,366 of 9,368 analyzed functions translate into 44 C++ files. Two unsupported
  translation cases remain. Four additional startup helpers are discovered and
  compiled ahead of time; the host does not generate executable code at runtime.
- The successful Mac run executes 1,870 distinct translated functions and renders
  198,310 GS primitives. See `local/runs/native-boot-20261016T170054Z/result.json`
  and its round-3 log/frame output. Its host exit code of 2 denotes the deliberate
  frame-limit stop; `target_reached` is the success criterion.
- All five Mac CTest groups pass: upstream host semantics, headless I/O, Apple
  fiber scheduling, console arithmetic and verification arithmetic. Host coverage
  includes generated VU programs; I/O checks cover WAV output and large-file seeks.
- A separate 32-function differential sample agrees with the upstream reference
  model for 31 functions, with one untestable. Translation counts do not establish
  correctness of every game function.
- Signed probe build 2 runs on the iPhone 15 Pro Max, iOS 27.0.1. Its retrieved
  `local/reports/iphone-runtime-result.json` confirms the arithmetic checks pass.
  This report covers the math probe, not full game startup.

The phone startup report is saved at `local/reports/iphone-native-boot-result.json`:
`target_reached: true`, `failure: null`, ARM64, iOS 27.0.1. Its raw frame 1,200 was
retrieved and visually verified as the original memory-card prompt. Host exit code
2 is the intentional bounded-run stop. The initial UIKit image adapter treated
PS2 framebuffer alpha as display transparency; the follow-up build ignores that
alpha and captures the final frame explicitly. That signed follow-up was installed
and re-run successfully; `local/reports/iphone-native-last-frame.png` is its
verified on-device output, and its report timestamp is 2026-10-16T17:14:13Z.

## Apple implementation

Portable floating-point scopes preserve rounding and exception state; builds
observe rounding changes and disable floating-point contraction. Apple cooperative
fibers use guarded writable stacks and two Boost.Context ARM64 Mach-O assembly
routines, under the Boost Software License. Tests exercise arbitrary fiber
switching, exception propagation and floating-point environment preservation.

Windows-specific paths, timing, priority and CRT calls have Apple adapters. The
real game overrides, dispatch table, kernel services, disc reader, IOP/VU host and
software GS renderer are linked into the headless executable. Upstream IOP/VU
interpretation remains part of this host; this is not a wholly reimplemented engine.

The iOS host adds a landscape UIKit frame view, a multitouch DualShock-style
controller, continuous paced runs, explicit stop and sandboxed diagnostics.
Frame updates are coalesced before the main queue so input does not wait behind
old frames. The developer `--native-boot` argument retains the bounded
1,200-frame test; `--input-smoke` exercises UIControl events in a 2,400-frame run. The disc is stored in the app's Documents
folder. The implementation uses UIKit's scene lifecycle and normal Apple development
signing; iLoader and emulator JIT activation are unnecessary.

## Remaining engineering

1. Validate touch controls through menus and into an actual race; add physical-controller support.
2. Improve audio pacing, add save handling and an import flow for the user's disc.
3. Measure sustained GPU performance in races and improve presentation to avoid
   GPU read-back through the UIKit image view. See `GPU_STATUS.md` for the
   verified GPU bring-up evidence.
4. Validate races, crash mode, saves, interruptions and application lifecycle.

The host currently supports one run per app process. Normal launches have no
frame/time limit; Stop or backgrounding ends the run. Close and reopen to restart.
GPU acceleration and complete game correctness remain unfinished. Device audio
playback is connected; sustained playback quality still needs validation.
The device layout report confirms 932 × 430 points, landscape, with 14 touch
buttons. Mac regressions include concurrent steering/accelerator state and release
behavior; all five test groups pass after this addition.
Game assets, generated game code and signing credentials remain local and ignored.

The follow-up device control smoke run reaches frame 2,400 with no host failure
(report timestamp 2026-10-16T17:21:19Z). Its pad recording confirms Up at frame
1,473, Cross at frame 1,504, then release at frame 1,534, following the UIKit
button handlers. The post-confirmation output is black at frame 2,400, so this
test establishes input delivery and continued execution, not a playable menu or
race beyond the startup prompt. The app was subsequently launched normally,
without test automation or a frame limit.

## iOS audio playback

Build 5 connects the SPU2 output to AVAudioSourceNode / AVAudioEngine and enables
the host sound mixer. AVAudioSession uses playback mode; microphone permission
is unnecessary. A bounded single-producer/single-consumer ring bridges game and
device timing, with stereo conversion, small drift correction and fades on
underrun. Its real-time callback has no locks, allocation or file operations.
Backgrounding or an audio interruption stops the run.

The on-device 2,400-frame control/audio test succeeds with no host failure.
`local/reports/iphone-audio-result.json` records the Speaker route at 48 kHz,
293,987 nonzero game frames and 299,008 nonzero rendered frames, no dropped
frames and no setup error. Rendered counts include underrun fades; they need
not equal source counts. The test has 85 underruns, so smooth sustained playback
is not established. At the final snapshot the engine is stopped because the
bounded test ended. The app was subsequently relaunched in normal continuous
mode. These counters confirm delivery to the output callback, not an acoustic
recording or complete music/racing compatibility.

All five Mac test groups pass after adding ring checks for stereo preservation,
wraparound, underrun/refill, overflow and simultaneous WAV/device output.

## Transparent controls and analog sticks

Build 6 expands the game image across the safe area and uses 24% idle opacity
for the controller overlay (60% while held). Left and right analog controls
provide two independent axes each, with radial clamping and an 8% dead zone;
release/cancel/backgrounding centers them. D-pad, face buttons, shoulders and
Start/Select remain available. A stick and accelerator can be held together.

Host tests cover partial left/right movement, simultaneous accelerator input,
dead-zone centering, full-travel clamping and releasing all four axes. All five
Mac test groups pass after this addition. Physical-device UI and input checks
use the optional `--stick-smoke` launch argument.

The physical-device recording confirms simultaneous right stick (192, 64),
left stick (64, 160), and R2 at frame 1,299, then both sticks centered (128, 128)
and R2 released at frame 1,360. See `local/reports/iphone-analog-input.txt`.
The app's own rendered view was saved and inspected at
`local/reports/iphone-analog-controls.png`; both sticks and the faint overlay
fit within the landscape safe area without overlapping each other's hit targets.

The stick smoke run reaches frame 2,400 with `failure: null` (timestamp
2026-10-16T17:30:03Z); its result is `local/reports/iphone-analog-result.json`.
The installed app was then relaunched in normal continuous mode.

## Performance build 7

The installed build now uses Release optimization throughout the translated
game/runtime and ThinLTO across the host and app. Runtime rounding controls
and disabled floating-point contraction are retained; fast math is not enabled.
The setup helper and Xcode launch scheme now select Release by default.
Normal runs no longer encode periodic PNGs or record every controller-state
change to disk. Diagnostic launch modes retain these outputs. The presentation
throttle changes from 33 ms to 16 ms; this permits more display updates but
does not establish 60 unique rendered pictures per second.

Device observations for the same 1,200-frame startup scope:

| Build | Seconds | Final thermal state |
| --- | ---: | --- |
| Debug baseline | 22.785 | Serious |
| Release | 19.696 | Fair |
| Release, two draw threads | 22.239 | Fair |
| Release with ThinLTO | 19.743 | Fair |

These are individual device observations, not controlled repeated benchmarks;
thermal conditions changed. Two draw threads are slower and are not the default.
ThinLTO does not measurably change this startup result. The original Debug and
first Release raw frame 1,200 are byte-identical (SHA-256
`9d771dcb9b6e96452e9ba74cec6d4f4a54f2dc789d84e8af1ee959540f2661c1`).
The later ThinLTO snapshot shows YES selected instead of NO, so its full-frame
hash is not comparable to the untouched baseline; its graphics were inspected.

The paced 2,400-frame control test completes in 41.766 seconds with no host
failure. Its last five 120-frame intervals report 59.9–60.0 simulated frames
per second, with the GS thread busy around 60–61%. These are simulation timing
measurements in a menu, not proof of 60-FPS racing or unique screen presentation.
The unpaced profile still spends about 93% of wall time inside GS drawing.
A GPU renderer remains the main path to a larger sustained graphics improvement.

Evidence is in `local/reports/iphone-performance-*.json` and
`local/reports/iphone-performance-paced.log`. All five optimized Mac test groups
pass, including with ThinLTO; the upstream host tests also pass with the optional
two-thread raster pool. All three engine patches apply cleanly to pinned source.
The signed Release build was installed and launched without test flags.

## GPU build 9

The installed app now renders on the phone's GPU by default through MoltenVK/Metal.
Device pixel checks pass and both frame 1,200 and the title screen at frame 4,000
were verified. The warm startup-only check takes 0.870 seconds; the longer title
check takes 15.126 seconds, both with nominal device thermal state. Software
rasterization is disabled. See `GPU_STATUS.md` for limits, frame comparisons,
reproduction instructions and source/dependency provenance. Full race correctness
and sustained performance remain unverified.

## Analog touch fix, build 10

Corrected the Objective-C UIControl overrides to
`beginTrackingWithTouch:withEvent:`, `continueTrackingWithTouch:withEvent:` and
`endTrackingWithTouch:withEvent:`. The previous Swift-style names were never
called by UIKit, leaving both sticks stationary during physical drags.
The earlier direct-position smoke test bypassed those handlers and missed this.

The signed Release update was installed and launched on the iPhone 15 Pro Max.
All 19 on-device regression checks pass, covering selector overrides, hit tests,
independent axes, concurrent accelerator input, thumb movement, release and
cancellation. These checks dispatch synthetic touch locations through the actual
tracking methods; they do not inject physical touchscreen events. The owner
subsequently confirmed that both sticks move and return to center with finger
input. Evidence: `local/reports/iphone-stick-tracking.json`.

## Takehome-inspired stick feedback, build 11

Adapted the joystick interaction from the owner's local
`2025-frontend-takehome/src/robot-remote-control` implementation. Finger tracking
remains direct; release uses a native Core Animation spring with mass 1,
stiffness 800 and damping 30, matching the reference return spring. Direction
chevrons brighten in proportion to input and opacity fades between the existing
0.24 idle / 0.6 active levels. The transparent game overlay is retained.

Game axes become neutral immediately on release, independently of visual bounce.
Regrabbing interrupts the spring immediately; cancellation/backgrounding clears
input without bounce. Reduce Motion disables spring and opacity transitions.
The robot controller's 100 ms command throttle was deliberately not carried into
game steering. Release signing and installation succeeded; all 24 on-device
tracking checks pass, including release neutrality, spring presence and regrab
interruption. Evidence: `local/reports/iphone-stick-spring.json`. Owner assessment
of the new motion feel is still pending.

## Game launcher, build 12

The owner confirmed the build 11 controller feel. Build 12 replaces the visible
Native Probe identity with Burnout 3, an original orange/black B3 app icon, a
matching system launch screen and a landscape home screen with a Play button.
Play shows a spinner while startup runs off the main thread. The first nonblack
game frame reveals gameplay and the existing transparent controls. The debug
Stop button and status banner are removed. Missing data and failed/stopped
sessions return to a readable launcher message. The bundle identifier remains
unchanged so the installed game data is retained.

Normal opening waits at Play, without running runtime or controller tests.
Developer flags retain bounded startup, GPU and controller tests; `--launch-smoke`
uses the actual Play action and captures the three launch states. The signed
Release build installed successfully; on-device screenshots verify the ready,
starting and visible-game states, and all 24 controller checks pass in build 12.
Evidence: `local/reports/iphone-launch*.{json,png}`. The host still supports one
game session per process: backgrounding ends it and restarting requires closing
and reopening the app. Full race correctness remains unverified.

## Persistent memory card, build 15

The iOS launcher now attaches `Documents/memcard/` to slot 1 through the host's
memory-card option. Previously that option was empty, so profile creation saw
an absent card. Launch creates or reuses the directory and reports a launcher
error if it cannot be opened for writing. App restarts and updates reuse the
same save location.

The host semantics suite passes, including memory-card creation, write/readback,
listing and formatted-card checks. The signed Release update was installed on
the iPhone 15 Pro Max. Its 1,200-frame startup run reaches the target without an
exception, shows the Criterion logo past the former missing-card prompt, and
logs the host-card GetInfo and GetDir handlers. Evidence is in
`local/reports/iphone-memory-card-startup.{json,png}` and
`local/reports/iphone-memory-card-title.log`. Creating and reloading a complete
profile through the game UI remains unverified. The app was relaunched normally
after the developer checks.

## Original logo, build 13

Replaced the custom launcher monogram and separately typeset title with the
original Burnout 3: Takedown logo, displayed unchanged at its original aspect
ratio. The system launch screen uses the same logo. Artwork provenance is in
`native/ios/ASSETS.md`. The Home Screen icon remains separate. The signed update
was installed; the on-device launcher screenshot and Play-to-game transition
were verified in `local/reports/iphone-original-logo-{ready.png,launch.json}`.

## Original title-screen style, build 14

Adapted the owner's supplied animated WebP into the launcher. ImageIO loads its
four original 600 × 420 frames with a 10-second loop. The central racing/logo
panel is clipped by views at its original proportions; native blue grid lines,
sweeping frame, Criterion/EA credits and copyright extend the composition across
the phone's wider landscape screen. The START text is a full-width 44-point
button wired to the existing startup action. Loading and failure text use the
same lower band. Animation stops when hidden/backgrounded and Reduce Motion
shows a still image. The artwork file is bundled unchanged.

The signed update installed successfully. The on-device screenshot verifies the
reference layout, and the START action reaches visible game output (recorded
state `playing`, build 14). Evidence:
`local/reports/iphone-title-style-{ready.png,launch.json}`. A normal launch is left
at the title screen for the owner to start manually.

## Universal custom launcher, build 16

Replaced the PS2 title-screen shell with a neutral Library detail view: original
portrait cover, game title/subtitle, developer and genre/year, readiness status,
Touch to Launch and a working Controls guide. All game identity, cover selection
and help text come from `native/ios/Resources/game.json`; the UIKit launcher has
no Burnout-specific strings. The system launch screen is a matching neutral
background. The game host still supports Burnout only.

Cover scans are downsampled to a 1024-pixel maximum dimension. Launching disables
actions and shows an inline spinner; stopped/error messages stay in the same
layout. Header heights and count width follow Dynamic Type, with scrollable
content at large accessibility sizes. Product and visual decisions are recorded
in `PRODUCT.md` and `DESIGN.md`.

Release build/signature checks pass, the update is installed, and the launch
action reaches visible game output. On-device captures verify normal layout,
the Controls guide and the largest accessibility text category without altering
the owner's system settings. The finish review found one header-sizing issue;
it was fixed and reviewed with disposition **ship**, no material issues left.
Evidence: `local/reports/iphone-universal-launcher*.{png,json}`. Normal startup is
left at Library for the owner to launch manually. Existing one-session/background
and unverified full-race limits remain.


## Race performance work, build 24

Normal startup now selects the real-time scheduler, which enables the existing
asynchronous VIF1 worker. iOS presents GPU targets directly through Metal rather
than reading every live frame back into a UIImage. Presentation drops surplus
loading blanks and bounds queued drawables. The local geometry corpus includes
91 compiled programs, with additional ARM64 vector conversion/cross-product
paths. Graphics changes add capability-checked local destination reads and
page-column-limited memory transfers. Original blur/glow remain enabled.

Six Mac regression groups pass; 512 captured race VU states match the interpreter
exactly, and a recorded race frame plus all graphics memory remain byte-identical
after the transfer changes. iOS frame workers use foreground rendering priority,
and the NEON flag path preserves complete MAC/STATUS semantics. Build 22 passed
the on-device math/GPU/display checks and completed the longer race replay:
simulation median 59.9 Hz, drawable presentation median 28.3 FPS, Serious thermal
state, Low Power Mode off, all 5,070,433,711 VU1 pairs compiled. It was then
relaunched normally and reported `playing`. This is not sustained 60 FPS
rendering. A timed-presentation experiment in build 23 did not establish a
benefit and was removed. Build 24 restores the verified immediate display path
while retaining the CPU/GPU optimizations. Its on-device math/GPU checks pass,
and a clean normal launch reports `playing` with the real-time worker active.
The rendering lag remains unresolved at the measured frame rate. See [GPU status](GPU_STATUS.md) for reproduction commands,
evidence and remaining limits.


## Native rendering performance, build 41

The iOS implementation retains burnout3-pc's native recompilation architecture,
compiled for ARM64, with Vulkan through MoltenVK/Metal. Upstream shader
specialization, asynchronous pipeline creation and persistent caching are
backported without replacing the Apple host. Additional NEON clean-value
tracking preserves the existing PS2 math model. Full main-scene submissions
are now counted independently from VIF transfers and drawable presentations.

The default performance preset omits live car reflections, glow, blur and depth
haze, and caps the world far clip at 240 units; the internal image is still
640×448. Skipping reflection cameras alone caused corrupt car textures because
the GS reuses their memory. The paired reflection-overlay omission fixes that
artifact while retaining paint/decals and the complete main view. A tested
180-unit clip did not establish a speed improvement and was reverted.

Build 41 reaches the real race replay's blank 12000 with no reported failure.
Main-world rendering min/median/max is 44.4/59.5/60.9 submissions/s across 42
two-second intervals. Displayed frames from blank 8000 measure
57.4/59.4/60.4 FPS across 33 intervals. This is a substantial improvement over
build 22's 28.3 median presentation, but busy-scene geometry still falls below
60; locked 60 FPS and higher internal resolutions remain unproven. All six Mac
regression groups, 512 captured exact VU states, 512 fast-mode states (excluding
intentionally omitted MAC/STATUS) and the device GPU/math checks pass. The
primitive-bounds cleanup preserves the captured race image and full GS memory
byte for byte. See GPU_STATUS.md for individual experiments and evidence.


## Original PS2 view distance, builds 44–45

The user rejected the aggressive camera clipping, accepting lower frame rates
in exchange for PS2-equivalent visibility. Build 44 removes the far-plane
modification entirely; an observer logs the game's own 2000/10000-unit camera
values without changing them. These are camera clip planes, not metres or a
single visible horizon. The short actual-race baseline reaches blank 8400, but
its busy-scene main-world median is 27.9 submissions/s (minimum 23.6), so it
does not yet establish the desired 30–40 FPS floor at original distances.

Build 45 keeps those original camera values. A device Time Profiler capture
identified VU0 macro floating-point state changes as a CPU hotspot. Strictly
adjacent translated macro instructions now share their rounding scope, with
labels, EE operations and calls ending a group. Full register results and host
rounding/exception state match individual execution in differential tests.
All six Mac regression groups pass after regenerating the translation.
A synthetic 12-instruction Mac batch benchmark reduces the median from
96.138 to 22.608 ms for 2.4 million instructions, with matching output; this
is not a whole-game FPS claim. The iPhone race check determines its real effect.


Build 45's on-device check now completes the longer actual race replay through
blank 12000 with original camera distances unchanged, no failure and passing
GPU/math tests. Main-scene min/median/max is 47.0/59.9/61.1 submissions/s over
42 two-second intervals; presentation is 53.6/59.4/60.0 FPS across 33 intervals
from blank 8000. The scene counter's initial boundary can count one extra
submission. The measured minimum is above the user's accepted 30–40 range.
This satisfies the revised compromise in the checked race, without establishing
locked 60 on every track or long thermal sessions. The app was reopened normally
without diagnostic flags. Evidence and the remaining quality reductions are
listed in GPU_STATUS.md.


## Restored car materials, build 46

Build 46 restores the original live reflection/material passes and every-frame
reflection cameras by default, fixing the flat paint/glass introduced by build
45's quality reduction. Car meshes, textures and original view distances are
retained. The simplified material path is now an explicit developer diagnostic
only (`--flat-reflections`); stale/periodic auxiliary-map startup options were
removed. Blur/glow/depth haze remain reduced.

The complete actual-race replay reaches blank 12000 without failure. Main-scene
min/median/max is 24.7/48.55/61.0 submissions/s across 42 two-second intervals;
presentations from blank 8000 measure 47.2/54.7/60.4 FPS across 33 intervals.
The physical-device GPU and extended math checks pass. The original material
path improves appearance at a measurable performance cost: busy scenes still
fall below the user's desired 30–40 floor. The earlier flat-material 59.9 median
and 47 minimum must not be attributed to this preset. The app was reopened
normally after the completed test. See GPU_STATUS.md for evidence and images.


## Graphics-preserving GS waits, build 47

The GS producer now sleeps on a predicate-based condition variable when its
16 MiB ring is full, instead of repeatedly yielding. Ordering, wraparound,
drain and failure propagation are covered by a new concurrency regression,
which also verifies that a blocked producer consumes little CPU. All seven
Mac regression groups and ten consecutive concurrency runs pass.
The full device race completes with min/median/max scene rates of
32.4/46.4/60.9 submissions/s in two-second intervals. The floor improved from
build 46's 24.7, but a stable 40 FPS floor remains unproven. Graphics are retained.


## Current follow-up, builds 48–50

Build 48 adds exact zero-area triangle rejection, with byte-identical captured
race images and all 4 MiB of GS memory before/after. Build 49 reuses initialized
DMA snapshot storage for memcpy-based appends; new tests cover growth, run
boundaries, source mutation and pool reuse. All seven regression groups pass.
Device GPU and runtime checks pass, but full race performance remains variable:
build 48 min/median scene rates 30.0/47.0; build 49 18.4/23.8. The latter run
slowed before the changed asynchronous copy path became active, so attribution
is unresolved. A reliable 30/40/60 FPS floor cannot be claimed.

Build 50 fixes missing Game Mode eligibility metadata: current and compatibility
Game Mode keys plus the racing-game category. Boolean types and values are
verified in the built app. On-device activation and FPS benefit need checking.
Graphics and original world camera distances remain unchanged. See GPU_STATUS.md
for complete evidence and limitations.


## POC performance default, build 51

The user now prioritizes a 50–60 FPS proof of concept and postpones visual
kinks. The default therefore returns to the previously measured near-60 fast
preset: original meshes, textures, LOD and main view distances, with live
reflection cameras/overlays disabled and reduced post effects. Materials look
flatter. `--live-reflections` restores the fuller material path for later work.
The build-45 fast-preset figures are historical; build 51 still needs a fresh
race measurement.

Build 50 did not expose a Game Overlay entry according to the user. Build 51
uses the general Games category with both Game Mode keys. A fresh installation
was performed after backing up all Documents and Library data. The complete
disc and user data are restored, and restored memory-card hashes match. App
signature verification passes and the valid profile includes the phone, but
iOS currently rejects launch with a developer trust/security error. The user
has been asked to trust their developer profile in Settings. Game Mode and
race validation remain pending that device action.
