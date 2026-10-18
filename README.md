# Burnout 3 native iOS port experiment

Target: iPhone 15 Pro Max, iOS 27.0.1. This project adapts the
[burnout3-pc](https://github.com/danielgomesvieira2000/burnout3-pc) PS2-to-C++
translation path for Apple ARM64. Native startup now reaches the memory-card
prompt on both the Mac and iPhone 15 Pro Max through software rendering.
Landscape touch controls are now connected; complete gameplay remains unverified.

The user selected native development after an initial emulator investigation.
iLoader, emulator JIT activation and a separate PS2 BIOS are not required for
these experiments. Xcode will handle development signing for the iPhone.

## Verified so far

- Supplied disc: PS2 NTSC-U `SLUS_210.50`, 2,867,822,592 bytes.
- Boot ELF SHA-256: `e118dba952bf9fde6a04ee284bb1f06fa0bb49c9e04bbe762af1039dcc443c66`.
- All four runtime translation units build for macOS ARM64.
- Arithmetic regressions pass in console and verification modes, on ARM64 and x86_64 under Rosetta.
- A sample of 32 translated game functions compiles to ARM64: 31 match the PS2 reference model and one is untestable. Full register state and memory effects are compared using the upstream harness. External calls in this verification harness still go through the reference model.
- The emitter translates 9,366 of 9,368 analyzed functions into 44 C++ chunks; every chunk passes Clang ARM64 syntax checks. These are **not** 9,366 behaviorally verified functions. Two unsupported cases remain: `tlbwi` and a branch in a delay slot.
- The real host and game overrides now link on Apple ARM64. A bounded Mac run reaches frame 1,200 and renders the original memory-card prompt, executing 1,870 distinct translated functions.
- Five Mac test groups pass, covering host/VU semantics, Apple fibers, I/O and arithmetic.
- Signed math-probe build 2 runs on the physical iPhone 15 Pro Max with iOS 27.0.1. The full iOS host also reaches frame 1,200 on that phone and renders the original memory-card prompt. Its report and frame were retrieved from the device.

The Vulkan/Metal GPU path passes pixel tests on the Mac and iPhone and reaches
the original title screen on the phone. The installed build uses GPU drawing
by default. Build 24 adds real-time simulation with an asynchronous geometry
worker and direct Metal presentation; sustained 60 FPS racing remains unverified. See [GPU status](docs/GPU_STATUS.md).
Build 17 also compiles captured VU geometry programs and uses ARM64 vector
arithmetic. The tested compact-car selector now holds normal 60 Hz simulation
pacing on the phone, with about 30 geometry updates per second; the original
slow run managed about seven. Captured geometry states and the selector image
match the interpreter exactly. Build 24 expands the race geometry corpus and
reduces graphics-memory transfer work. See GPU status for measured race rates
and the remaining rendering limit.

See [development status](docs/NATIVE_STATUS.md) for remaining work and limits.

## Reproduce on an Apple Silicon Mac

```sh
python3 scripts/prepare_native.py
python3 scripts/check_native_runtime.py
python3 scripts/check_native_translation.py
python3 scripts/emit_native_game.py --check
```

The disc and analysis must exist for the last two commands; this workspace
already has them. On a fresh checkout, extract only the ISO from the archive
into `local/disc/`, then run:

```sh
python3 scripts/inspect_disc.py 'local/disc/Burnout 3 - Takedown.iso' --output local/reports/disc.json
python3 local/upstream/burnout3-pc/engine/tools/isotool.py extract 'local/disc/Burnout 3 - Takedown.iso' SLUS_210.50 -o local/upstream/burnout3-pc/games/burnout3/extracted/
python3 local/upstream/burnout3-pc/engine/tools/analyze.py --game local/upstream/burnout3-pc/games/burnout3
```

Source revisions are pinned in `native/upstream.json`. Local patches live in
`native/patches/` and `native/game-patches/`; preparation applies them without resetting existing changes.
Both upstream projects use MIT licenses; their license and copyright files remain
in the reference checkout. The two vendored Boost.Context assembly files retain
their Boost license and provenance in `native/vendor/boost-context/`. Game assets,
generated game code and signing credentials are ignored.

## CMake builds

```sh
cmake -S . -B build/cmake-macos -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build/cmake-macos --parallel 2
ctest --test-dir build/cmake-macos --output-on-failure
```

To compile generated game code into a static ARM64 library:

```sh
cmake -S . -B build/cmake-game -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS_DEBUG='-O0 -g0' -DCMAKE_OSX_ARCHITECTURES=arm64 -DBURNOUT_BUILD_TRANSLATED=ON
cmake --build build/cmake-game --target burnout_translated --parallel 2
```

## iPhone build

Open Xcode once and finish its setup, including the iOS platform. Then:

```sh
python3 scripts/configure_ios.py --build
open build/ios/BurnoutNative.xcodeproj
```

`BurnoutNativeProbe` runs the math checks by default. Use
`python3 scripts/configure_ios.py --native-boot --gpu --build` (run
`python3 scripts/prepare_gpu.py` first) to link the full native
startup host and software frame view. The helper builds Release by default; use `--configuration Debug` only for
diagnosis. Unsigned compilation works without a team;
running on a phone requires Apple development signing and Developer Mode.
The script uses `DEVELOPER_DIR` without changing the Mac's global selection.
The app appears as **Burnout 3** with an original B3 icon. On first use, tap
**Upload ISO file** and choose your Burnout 3: Takedown NTSC-U (`SLUS-21050`)
ISO in Files. Import stays on device and keeps a copy at `Documents/burnout3.iso`;
the ISO is not included in the app bundle. The app checks ISO metadata and the
supported executable name before installing the copy. Other regions are not supported.
After import, the game starts immediately. Later app launches start automatically;
existing compatible ISO installations also skip setup. A brief startup surface
covers controls until the first visible game frame. A virtual memory card is
attached in slot 1; profiles are saved in `Documents/memcard/` and persist across
app restarts and updates. Removing the app also removes its imported ISO and saves.
Normal launches then run continuously in landscape with two analog sticks, a D-pad, face buttons,
Start/Select, shoulders, accelerator and brake. Controls use 24% idle opacity,
brighten while held, and overlay the expanded game image. Both sticks provide
proportional axes with a small center dead zone and return to center on release. Device audio uses AVAudioEngine with a buffered 48 kHz stereo source.
On-device checks confirm nonzero game samples reach the speaker route.
Normal runs avoid PNG capture and input-recording disk writes. The display
update throttle permits up to 60 updates per second; actual throughput depends
on game and renderer workload. The developer launch argument `--native-boot` retains the bounded 1,200-frame
startup test; `--input-smoke` runs a paced 2,400-frame control test. Closing and
reopening the app starts a new run; backgrounding stops the current run.
Runtime and controller checks are opt-in (`--runtime-tests`, `--controller-tests`);
normal launch does not exercise test controls. `--launch-smoke` captures
starting and gameplay screens during automatic startup. Icon assets
can be regenerated with `swift scripts/generate_ios_art.swift native/ios/Assets.xcassets`.
`--launcher-accessibility` applies the largest accessibility text size to the
setup surface without changing the owner's system settings.

## Bounded native startup on Mac

```sh
python3 scripts/run_headless_boot.py --frames 1200 --timeout 45 --max-rounds 10
```

This builds the host, runs startup, and compiles discovered helpers ahead of the
next run. Results and software frames go under `local/runs/`. It requires the
prepared disc, analysis and generated game code described above.

## Local files

- `local/disc/`: supplied ISO, extracted without executing attached HTML.
- `local/upstream/burnout3-pc/`: pinned source, extracted ELF and analysis database.
- `local/reports/`: disc inspection and bounded translation verification results.
- `build/`: generated C++, object files, libraries, test executables and projects.
- `local/install/`: packages from the earlier emulator investigation; not used by the native build.
