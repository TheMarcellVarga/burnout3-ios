# Burnout 3: Takedown for iOS

This branch preserves the older **PS2-based version**. Our main iOS app now
uses the Xbox-based runtime on the [xbox-ios branch](https://github.com/TheMarcellVarga/burnout3-ios/tree/xbox-ios).
Only the Xbox app is kept installed; the PS2 source remains here for reference.

An experimental native iOS port of **Burnout 3: Takedown**, inspired by
[burnout3-pc](https://github.com/danielgomesvieira2000/burnout3-pc). This project
targets the PlayStation 2 version and brings it to Apple ARM64 with GPU
rendering, landscape touch controls, device audio and a persistent virtual
memory card. Development and physical-device testing currently target the
**iPhone 15 Pro Max**.

**Status: a working proof of concept under active development.** The game boots,
reaches its menus and runs recorded race tests on the phone. Performance and
visual correctness are still being improved; full-game compatibility and a
stable 50–60 FPS rate have not been established.

## Why I started

I wanted Burnout 3: Takedown on my iPhone. Seeing burnout3-pc made me want to
explore what bringing it to iOS would involve: adapting the runtime for Apple
Silicon, getting graphics onto the phone and making a controller-driven game
usable through touch.

The work in this repository focuses on that Apple adaptation and the experience
around the game: the iOS app, ISO import, analog touch controls, audio, local
saves and device performance. The current build also reuses pinned translation
tools, PS2 runtime code and the Vulkan renderer from burnout3-pc; those components
and their authors are credited below.

## How it works

The build tools translate the original game's PS2 Emotion Engine executable
into C++, then compile it ahead of time for ARM64. A native host supplies PS2
runtime services, disc access, audio and graphics. Captured VU microprograms
can also be compiled ahead of time, with interpreter fallback for unmatched code.

Graphics use burnout3-pc's Vulkan renderer through **MoltenVK / Metal**, with
direct Metal-backed presentation on iOS. This repository adds the UIKit ISO
import screen and touch controller, AVAudioEngine integration and persistent
storage in the app sandbox. A software renderer is retained for reference and
diagnosis.

Ahead-of-time compilation means the app does not require emulator JIT
activation, iLoader or a separate PS2 BIOS. The original game disc image is
supplied separately.

## What works today

- **On-device ISO import:** choose a supported disc image in Files once;
  subsequent launches start the game automatically. Import stays on the device.
- **Landscape touch controls:** two proportional analog sticks, D-pad, face
  buttons, shoulders, Start/Select, accelerator and brake. Controls are
  translucent at rest and brighten during use.
- **GPU rendering:** Vulkan graphics through MoltenVK / Metal, including
  backported shader specialization and pipeline caching.
- **Audio output:** buffered stereo playback through the device's audio engine.
- **Persistent storage:** a virtual memory card in slot 1 keeps saves across
  app restarts and updates.
- **Development tools:** a macOS headless host, translation checks, runtime
  regressions, GPU pixel tests and scripted device diagnostics.

Development notes document physical iPhone 15 Pro Max checks on **iOS 27.0.1**,
seven Mac regression groups, GPU/math checks and recorded race runs. The raw
device reports and captures are kept under ignored `local/` paths and are not
included here. Of 9,368 analyzed game functions, 9,366 translate into 44 C++
chunks; that translation count does not mean every function is behaviorally
verified.

## iOS settings

Select **iOS Settings** in the game's main menu. All settings use the game's
own menu graphics, help ticker and button prompts. Use the on-screen D-pad to
choose a page or row, Cross to cycle a value, and Triangle to go back. The pages
are **Display and Graphics**, **Touch Controls**, and **Reset iOS Settings**.
Changes apply immediately and save across launches.

| Setting | Choices | Default |
| --- | --- | --- |
| Render resolution | Original (640 × 448), Sharper (1280 × 896) | Original |
| Picture shape | Original (4:3), Widescreen (16:9) | Original |
| Blur and glow | Off, On | Off |
| Racing buttons | Classic, Triggers | Classic |
| Steering response | Gentle, Standard, Quick | Standard |
| Analog stick size | Standard, Large (fits available space) | Standard |
| Control visibility | Subtle, Medium, High | Subtle |

Sharper rendering uses a matching Metal output surface and costs more GPU work.
Widescreen adjusts the camera, HUD and presentation together; both picture shapes
fit inside the safe area without cropping. Steering response changes the left
stick's horizontal curve while retaining full steering at full travel. The
right stick and digital D-pad retain their existing response.

Classic uses Cross to accelerate, Square to brake and R1 to boost. Triggers uses
R2 to accelerate, L2 to brake and Cross to boost; the touch labels update to match.
Music/effects volumes and gameplay preferences stay in the game's own options.
Frame pacing is automatic, while reflections and depth haze retain the mobile
performance policy. Desktop fullscreen, manual V-sync, display-resolution
scaling, desktop antialiasing, keyboard and adaptive-trigger options are omitted.
Leave the app through iOS rather than a Quit Game menu item.

**Reset iOS settings** asks before restoring these defaults; it keeps the disc,
saved profiles and unrelated game options. Preferences retain the internal
`pc_settings.ini` filename alongside the virtual memory card for compatibility.
Unsupported values left by older desktop-style builds are normalized on startup.

## Performance and limitations

The current default targets a **50–60 FPS proof of concept** at **640 × 448**.
It retains the original meshes, textures, LOD and camera distances, while
omitting live reflection cameras/overlays and reducing glow, speed blur and
depth haze. Car paint and glass consequently look flatter.

The latest completed short-race replay, build 52, measured **39.8 minimum / 51.25
median / 60.9 maximum main-scene submissions per second** across 12 two-second
intervals. Build 52 used a shorter camera distance; it did not improve the rate
and has been dropped. Build 53 restores the original distance and selects the
original queue waits for a device comparison, which is still pending. Raw reports
are local and not included here. Scene submissions, simulation ticks and display
presentations are separate measurements, so these figures do not guarantee a
stable displayed frame rate.

Additional limits:

- Only the **PS2 NTSC-U disc, `SLUS_210.50` / `SLUS-21050`**, is supported.
- Complete races across every track, crash mode, long sessions and save/profile
  round trips still need broader validation.
- Sustained audio quality and graphics accuracy remain unfinished.
- Physical-controller support remains future work.
- Backgrounding or an audio interruption ends the current run. Close and reopen
  the app to start another session.
- Game Mode eligibility metadata is included; activation and any benefit on the
  tested phone are unconfirmed.

Developer launch arguments `--live-reflections` and `--original-quality` restore
live reflection materials and the fuller original effects respectively, at a
performance cost. [Graphics notes](docs/GPU_STATUS.md) explain the current
quality tradeoffs and measurements. [iOS port notes](docs/NATIVE_STATUS.md)
summarize the architecture, validation and known limits.

## Build and run

### Requirements

- An Apple Silicon Mac with Xcode and the iOS platform installed.
- Python **3.10+**, CMake **3.24+**, Git and the Xcode command-line tools.
- Your own supported **Burnout 3: Takedown NTSC-U ISO**.
- For a physical iPhone: Developer Mode and Apple development signing in Xcode.
  The generated project targets iOS **17.4+**; the tested device/OS is listed above.

### 1. Prepare the native source and game translation

Run these commands from the repository root. Preparation fetches the pinned
upstream sources and applies this repository's Apple patches.

```sh
python3 scripts/prepare_native.py
```

Place your ISO at `local/disc/Burnout 3 - Takedown.iso`, then inspect the disc,
extract its executable, analyze it and generate the C++ translation:

```sh
python3 scripts/inspect_disc.py 'local/disc/Burnout 3 - Takedown.iso' --output local/reports/disc.json
python3 local/upstream/burnout3-pc/engine/tools/isotool.py extract 'local/disc/Burnout 3 - Takedown.iso' SLUS_210.50 -o local/upstream/burnout3-pc/games/burnout3/extracted/
python3 local/upstream/burnout3-pc/engine/tools/analyze.py --game local/upstream/burnout3-pc/games/burnout3
python3 scripts/emit_native_game.py --check
```

The recorded supported boot ELF SHA-256 is
`e118dba952bf9fde6a04ee284bb1f06fa0bb49c9e04bbe762af1039dcc443c66`.
Generated code stays local. Captured VU programs and discovered startup helpers
also live in ignored `local/native/` files; the documented device results use
that local development data, which is not distributed with a fresh checkout.

### 2. Build the iPhone app

Prepare the pinned graphics dependencies and generate an unsigned Release build:

```sh
python3 scripts/prepare_gpu.py
python3 scripts/configure_ios.py --native-boot --gpu --build
open build/ios/BurnoutNative.xcodeproj
```

In Xcode, select the `BurnoutNativeProbe` target, choose your signing team and
connected iPhone, and run the app using Release configuration. The target retains
its development name. Running `configure_ios.py --build` without `--native-boot`
builds only the runtime math probe.

On first launch, tap **Upload ISO file** and select the supported ISO in Files.
The app validates the image and stores a copy at `Documents/burnout3.iso`, then
starts the game. Later launches reuse that copy and start automatically.
Profiles use `Documents/memcard/`. Deleting the app removes its imported ISO
and saves.

### 3. Run Mac checks

After preparing the native source, build and run the base runtime tests:

```sh
python3 scripts/check_native_runtime.py
cmake -S . -B build/cmake-macos -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build/cmake-macos --parallel 2
ctest --test-dir build/cmake-macos --output-on-failure
```

With the disc analysis and translation prepared, run the translation sample
checks or the bounded headless startup:

```sh
python3 scripts/check_native_translation.py
python3 scripts/run_headless_boot.py --frames 1200 --timeout 45 --max-rounds 10
```

The headless helper builds the host and compiles newly discovered helpers ahead
of subsequent runs. Reports and software-rendered frames go under `local/runs/`.
GPU-specific checks are documented in [GPU status](docs/GPU_STATUS.md#reproduce).

## Repository layout

| Path | Purpose |
| --- | --- |
| `native/ios/` | iOS app, import flow, touch controls, audio and presentation |
| `native/platform/` | Apple runtime adapters and fiber support |
| `native/patches/`, `native/game-patches/` | Changes applied to the pinned engine and game project |
| `native/tests/` | Runtime, host, controller and graphics regressions |
| `native/upstream.json`, `native/gpu/dependencies.json` | Pinned source and graphics dependencies |
| `scripts/`, `cmake/` | Preparation, translation, build and diagnostic tooling |
| `docs/` | iOS architecture, graphics and validation notes |
| `local/`, `build/` | Ignored game data, dependencies, captures, reports and generated builds |

## Credits and game content

[burnout3-pc](https://github.com/danielgomesvieira2000/burnout3-pc) inspired this
project. Its translation tools, PS2 recompilation runtime and Vulkan renderer
are also reused in the current implementation, with the revisions recorded in
[`native/upstream.json`](native/upstream.json). Their MIT license and copyright
notices remain in the prepared source checkouts. The Apple adapters, iOS app
integration, touch interaction and device-specific work live in this repository.

MoltenVK, glslang and the vendored Boost.Context assembly retain their respective
license notices; Boost provenance is recorded in
[its vendor directory](native/vendor/boost-context/README.md). Bundled artwork
provenance is documented in [iOS assets](native/ios/ASSETS.md).

Burnout 3: Takedown is the original Criterion Games / Electronic Arts title.
The game ISO, extracted executable, generated game code and signing credentials
are not included in this repository.

## License

This repository does not currently grant a license to reuse its original code.
The referenced upstream projects and bundled dependencies retain their own
licenses and notices. A license for this repository's contributions has not
been selected.
