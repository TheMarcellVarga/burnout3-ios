# Burnout 3 iOS

This is the Xbox-based iOS implementation on this repository’s `main` branch.
It adapts Takedawn and xboxrecomp while retaining their attribution and licenses.
The former PS2 source is preserved on [ps2-legacy](https://github.com/TheMarcellVarga/burnout3-ios/tree/ps2-legacy).
No game files or generated game code are tracked.

## Current state

The only installed app is **Burnout 3**, using the Xbox-based runtime and
the red B3 logo on a white background. The older PS2 app was removed
from the device at the owner’s request after backing up its memory card saves.

Current installed build: **13** (27 October 2026). Race/performance evidence
below was collected on 23 October; later identity and icon checks are recorded
in [DEVICE_STATUS.md](DEVICE_STATUS.md).

- All 716 supplied USA Xbox files match the upstream disc manifest.
- Translation generated 24,001 functions without generation failures, plus
  upstream stubs for 15 unresolved call targets. Not every game path is tested.
- The signed ARM64 Release app targets iOS 17.4+ and runs on the owner's
  iPhone 15 Pro Max. PS2 memory-card saves were backed up before that app was removed.
- On the phone: intro, menus, garage, Silver Lake Southbound race, scripted
  acceleration/steering/braking/pause, and profile save followed by a fresh
  launch and successful profile reload were exercised.
- During roughly 155 seconds between the first acceleration command and pause,
  31 five-second presentation samples reported 59.9–60.1 Metal presentations/s
  (59.9–60.2 guest flips/s). This includes coasting and time without held input;
  it is a short single-track sample, not sustained performance certification.
- The captured run reported zero Metal shader compilation errors. A visible
  checker-pattern defect remains in the lower-left race HUD. Rendering fidelity,
  touch interaction, audio quality, interruptions, memory pressure and thermal
  behavior need further validation. No complete race or broad mode coverage
  is claimed.
- Host checks pass: 103 controller checks, 23 ARM64 MMIO traps, a 64 MiB
  file-backed shared-memory alias/cleanup test, and 1,200 Mac Metal shader
  compilations. The Mac shader suite is separate from device validation.

Build 7 adds our native launch screen and project icon, persistent iOS settings
(render resolution, picture shape, control size/visibility and automatic gas),
and a Files folder importer. Graphics preferences take effect on the next app
launch; touch preferences update immediately. Settings are accessible before
Play and from the gear button in the game menus or pause screen. The bundle ID
is unchanged, so existing Xbox profiles remain available after upgrading. The
home-screen name is **Burnout 3**. Build 11 promotes this to the main app;
the older PS2 app is no longer installed. The Xbox bundle ID stays unchanged
so installing updates preserves its data.

The port uses a UIKit scene lifecycle, patched SDL scene-backed windows, sandbox
paths, a native touch view backed by xboxrecomp's controller mapping, and the
direct Metal presenter. On-device fixes include temporary-file-backed memory
mapping, case folding for Xbox paths on the iOS filesystem, and refreshing cached
runtime defaults after initialization. Diagnostics are quiet by default; explicit
tracing remains available. The runtime uses the public iOS vm_map API.

See [device test evidence](DEVICE_STATUS.md) for the bounded test and limitations.

Desktop settings, automatic shader prebuild by spawning another process, desktop
setup UI, and restarting the executable are excluded from this prototype.
Shaders can compile on demand. The desktop settings UI is replaced by the native iOS panel. Background
handling and audio interruptions are not yet validated.

## Build

Use an Apple Silicon Mac with Xcode, the iOS SDK, CMake, Python 3.10+ and Git.
Clone [this repository’s main branch](https://github.com/TheMarcellVarga/burnout3-ios/tree/main),
then run the following commands from its root. Do not use the PS2 branch’s build scripts.
The preparation script pins SDL and the Xbox runtime and applies
[runtime.patch](runtime.patch) and [sdl.patch](sdl.patch). Downloaded dependencies, disc files, generated
sources and build products remain ignored.

For an already extracted supported Xbox folder:

```sh
python3 tools/ios/build.py --game-dir '/path/to/Burnout 3 Takedown' --build --team YOUR_TEAM_ID
```

Or use a local 7z archive containing that folder:

```sh
python3 tools/ios/build.py --archive '/path/to/game.7z' --build --team YOUR_TEAM_ID
```

The script validates every disc file, prepares the pinned runtime under
`local/upstream/xboxrecomp`, builds static SDL for iOS, translates the game and
configures the Xcode project. Omit `--team` for an unsigned compile check.
Use `--regenerate` after changing the translation inputs. The output is
`bin/TakedawnIOS.app`, and the project is `build/ios/burnout3_recomp.xcodeproj`.

## Install and test

Connect and unlock the iPhone, enable Developer Mode, then:

```sh
python3 tools/ios/build.py --build --team YOUR_TEAM_ID --device DEVICE_UDID --copy-game
xcrun devicectl device process launch --device DEVICE_UDID --terminate-existing dev.burnout3.takedawn-ios
```

Game files go in `Documents/Burnout 3 Takedown`, saves in `Documents/Saves`,
and the runtime log in `Documents/takedawn.log`. File sharing is enabled for
Finder/Files access. Game data is supplied separately from the app. The launch screen can also import an extracted USA Xbox folder from Files.
It stages a copy and checks all manifest sizes and SHA-256 hashes before moving
it into place. Failed imports clean up their staging folder and preserve any
existing installation. PS2 files and compressed archives are not accepted.
An existing partial nonempty game folder must be moved aside in Files before
importing; the app does not overwrite it.

The first bounded race and save/relaunch check have passed. Next validate touch
interaction, audio, a complete race, background/resume and sustained memory/thermal
behavior as follow-up validation for the main Xbox implementation.

## Host controller regression

After preparation:

```sh
cmake -S ios/tests -B build/ios-host-checks -DCMAKE_BUILD_TYPE=Release
cmake --build build/ios-host-checks --parallel 4
ctest --test-dir build/ios-host-checks --output-on-failure
```

## Provenance

[dependencies.json](dependencies.json) records the exact upstream Takedawn and
xboxrecomp commits and the SDL download checksum. Runtime modifications are kept
as a reviewable patch; the upstream runtime license notices remain in place.

## Migration scope

The Xbox implementation is now the main iOS app. The [ps2-legacy branch](https://github.com/TheMarcellVarga/burnout3-ios/tree/ps2-legacy)
preserves the older implementation for source comparison. The native settings interaction and
project artwork carry forward from that app, while Xbox-specific rendering and
input use Takedawn/xboxrecomp. PS2 saves and renderer-specific switches are not
compatible and are not copied automatically.

The host suite exercises preference validation/persistence, explicit diagnostic
environment overrides, complete-file hashing, rejection of corrupted/truncated/
missing files and symlinks, successful staged installation, preservation of
existing game files and cleanup after rejection. The same native validator also
passes against the full 716-file supplied disc. Files picker/provider integration
and physical touch interaction still require hands-on device testing.

For automated device checks, `RECOMP_IOS_AUTOPLAY=1` selects Play through the
launcher after one second, and `RECOMP_IOS_SETTINGS_PREVIEW=1` opens the native
settings sheet. Normal launches set neither. The app includes upstream credits
and license texts under Settings → Credits & licenses.

## Hybrid touch controls (build 8)

The default Hybrid layout combines the earlier iOS analog stick treatment with
the Xbox runtime's contextual racing controls. GAS (RT), BOOST (A + RT) and
BRAKE (LT) form a compact right-thumb cluster. Slide between gas and boost
without lifting; brake remains a distinct target. Smaller CRASH, LOOK and VIEW buttons
handle crashbreaker, look behind and camera view. Menus retain Xbox A/B/X/Y.

The left stick anchors near its visible resting position. Touch farther away
on the left to float the base to your thumb. Pickup is neutral even when your
thumb lands off-center; movement after pickup steers. Travel matches the visible knob's
range and reaches full steering. Standard, Gentle and Quick responses are
static curves: steering input is never delayed or animated. Lifting returns
input to neutral immediately; only the visible knob springs back, respecting
Reduce Motion. The overlay checks context at 60 Hz and repaints only when its state changes.

Settings → Touch controls includes the original Xbox prototype layout for
comparison, steering response, size, visibility and automatic acceleration.
Changing layouts releases existing fingers. Cancellation releases the cancelled
finger immediately, without affecting a second finger. Physical controller
mappings are unchanged. Tablet control sizes are capped using UIKit point
density to keep them within thumb reach.

The new host touch suite checks monotonic/symmetric steering, full travel,
dead center, response curves, independent fingers, cancellation, layout changes,
and continuous throttle through boost gliding. Geometry checks cover 320–430 pt
phone heights and two tablet sizes, in standard and large modes, with safe-area
insets and non-overlapping visible targets. Physical comfort still requires
hands-on evaluation on the phone.

## Native game-menu integration (build 9)

**Driver Details → Settings → IOS SETTINGS** opens the native panel. The
ordinary race pause menu also gets **IOS SETTINGS** immediately before the
game's existing **QUIT** row. Original game actions stay intact. Alternate
pause layouts that lack spare row capacity keep their original rows; the
native gear button remains available there.

The native panel's **Launcher** toolbar button (also listed under Session)
returns to the iOS launcher with **Resume game**. This preserves the current
live session in memory and pauses the guest GPU and audio through the runtime's
cooperative host pause. It does not end the process or force a profile save.
Use the game's Save Profile for progress that must survive an app closure.
Render/aspect changes still require a new app launch; Resume uses the current
runtime. The launcher allows normal device auto-lock; gameplay prevents it.

Settings, launcher and background pauses have separate ownership, so closing
a sheet or reactivating the app cannot accidentally release another hold.
Input is blocked and released while native UI owns it. The game overlay's
display link stops behind native UI and while the app is inactive.

The overlay now paints only dirty control regions, draws the cached input
snapshot once, and handles touch changes immediately without a duplicate
layout read in paint. See [optimization measurements](OPTIMIZATION.md) for the
short device comparison that selected a 4 ms frame-pacing spin lead.

Diagnostic-only `RECOMP_IOS_PROFILE=1` reports whole-process CPU, recent guest
flip timing, thermal state and overlay draw counts every five seconds.
`RECOMP_IOS_UI_TEST=1` exercises the actual Return/Resume handlers after an
in-game Settings activation (12 seconds in Settings, 15 in the launcher).
Neither diagnostic flag is enabled in ordinary launches.

Driving controls use faint PS2-style idle visuals and brighten while held.
Action names are centered without Xbox correspondence badges; the visibility
setting also controls label and stick opacity.
