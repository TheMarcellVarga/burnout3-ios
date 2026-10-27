# iOS port engineering notes

These notes describe the implementation and its current limits. Device reports,
screenshots and run logs referenced during development live under ignored `local/`
paths and are not part of this repository. The measurements below summarize
those development runs; they cannot be independently checked from the raw files
here.

## Architecture

The build translates the supported game's PlayStation 2 Emotion Engine executable
ahead of time into C++, then compiles it for Apple ARM64. The native host supplies
disc access, PS2 runtime services, audio and graphics. This reuses pinned
translation tools, PS2 runtime code and the Vulkan renderer from
[`burnout3-pc`](https://github.com/danielgomesvieira2000/burnout3-pc); this
repository provides the Apple platform layer and iOS app integration.

The UIKit app imports a user-provided disc image into its sandbox, displays the
game in landscape and maps multitouch input to a DualShock-style controller.
AVAudioEngine plays game audio, and a virtual memory card persists saves across
launches. The GPU path uses Vulkan through MoltenVK and Metal. The current display
path reads rendered frames back for UIKit presentation; a software renderer is
retained for diagnosis.

Ahead-of-time compilation means the app does not use emulator JIT activation,
iLoader or a separate PS2 BIOS. The original game disc image is not included and
must be supplied by the user.

## Validation and limits

The translation analysis covers 9,368 game functions: 9,366 translate into 44
C++ chunks, while two cases remain unsupported. This count is not a measure of
behavioral correctness. A bounded native run has reached the original
memory-card prompt on Mac and on an iPhone 15 Pro Max running iOS 27.0.1. Touch
event delivery, audio output, memory-card persistence and short race replays have
also been exercised during development.

The supported disc is the NTSC-U release (`SLUS_210.50` / `SLUS-21050`). Full
compatibility across tracks and modes, long sessions, save/profile round trips,
sustained audio quality and a stable displayed frame rate still need broader
validation. A run currently ends when the app is backgrounded or interrupted;
reopen the app to start another session. Physical-controller support is future
work.

## Checks

The repository includes Mac runtime, translation, headless-host and GPU checks.
The setup and commands are in the [README](../README.md#build-and-run). Generated
game code, disc data, captures and test reports stay under ignored `local/` and
`build/` paths.

## In-game iOS settings

The port-settings entry uses the game's own lists, strings, help ticker and
controller prompts. Display and Graphics has three options; Touch Controls has
four. Cross cycles a value and Triangle returns to the previous page. Reset iOS
Settings uses the game's own Yes/No box with No selected initially; Yes restores
only the iOS defaults and returns to the menu instead of exiting the game.
There is no UIKit settings sheet or separate preview app.

The canonical saved choices, defaults, validation and steering curve live in
`native/platform/mobile_settings.h`. The UIKit touch overlay observes saved
changes on its main thread. The Metal drawable follows the selected 1x/2x scale.
Both the GPU view and CPU fallback use 4:3/16:9 presentation bounds; the game
camera and HUD read that aspect from the Apple host. Frame pacing stays on;
normal play retains mobile reflection and depth-haze optimizations.

`ios_settings_tests` runs the actual guest menu code with bounded guest-memory,
string-lookup and drawing fixtures. It checks text-pool capacity, page entry and
row counts, cycling and persisting every option, both reset answers, default-No
confirmation, and restoration of the original main-menu entries. It also checks
legacy-value normalization, steering endpoints and reset isolation. Run with
`ctest --test-dir build/cmake-game -R ios_settings --output-on-failure`.

Physical visual checks remain pending; the owner elected to finish with build
and automated checks during the settings rework.
