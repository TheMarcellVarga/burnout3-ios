# Graphics and performance notes

These notes summarize development tests on Mac and an iPhone 15 Pro Max running
iOS 27.0.1. Raw captures, benchmark reports and run logs live under ignored
`local/` paths and are not included in this repository, so the results below
cannot be independently checked from those files here.

## Rendering path

The game uses the pinned Vulkan GS renderer from
[`burnout3-pc`](https://github.com/danielgomesvieira2000/burnout3-pc), with
MoltenVK translating Vulkan work to Metal. SDL and a desktop Vulkan loader are
not needed by the UIKit app. A software GS renderer remains available for
comparison and diagnosis.

The Apple patches cover Metal-specific masked colour writes, GPU transfers,
texture and pipeline behavior, and ARM64 geometry processing. GPU pixel tests and
targeted masked-blending regressions pass on the development Mac and phone. The
captured comparison against the software renderer found small blending and
16-bit quantization differences; rendering is not bit-exact. UIKit currently
displays GPU frames through a readback path, so presentation is not zero-copy.

## Current quality and performance

The proof-of-concept preset renders at 640 × 448 with original meshes, textures,
LOD and camera distances. It disables live reflection cameras and overlays and
reduces glow, speed blur and depth haze. Car paint and glass look flatter as a
result. Developer launch arguments `--live-reflections` and
`--original-quality` restore the fuller effects at a performance cost.

A short physical-device race replay on build 51 measured 42.9 minimum, 51.85
median and 61.0 maximum main-scene submissions per second across 12 two-second
intervals. Build 52's shorter camera-distance experiment measured 39.8 / 51.25 /
60.9 and was dropped because it did not improve the result and reduced the view
distance. Build 53 restores the original camera distances and selects the
original GS queue waits for a device comparison; that comparison is still
pending.

Scene submissions, simulation ticks and displayed frames are different measures.
These short runs do not establish a stable 50–60 FPS experience. Compiling
captured VU programs ahead of time and adding ARM64 NEON geometry paths improved
an isolated geometry replay, but whole-race performance remains variable.
Selecting the original queue waits also consumes more CPU while polling, so it
is a latency tradeoff rather than an energy optimization.

## Reproduce GPU checks

After preparing the pinned native and graphics sources, build and run the Mac GPU
tests, then generate the iOS project:

```sh
python3 scripts/prepare_native.py
python3 scripts/prepare_gpu.py
cmake -S . -B build/cmake-gpu -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DBURNOUT_BUILD_GPU=ON
cmake --build build/cmake-gpu --target apple_gpu_tests --parallel 2
build/cmake-gpu/apple_gpu_tests
python3 scripts/configure_ios.py --native-boot --gpu --build
```

Dependency revisions and hashes are pinned in
[`native/gpu/dependencies.json`](../native/gpu/dependencies.json). Generated
SPIR-V, fetched libraries, game data and test output remain in ignored
`local/` and `build/` directories.
