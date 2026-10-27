# iPhone test — 23 October 2026

Build 6 (`dev.burnout3.takedawn-ios`), Release ARM64, iPhone 15 Pro Max.
Game data: supported USA original Xbox release; all 716 files verified.

## Observed result

The app boots through the intro and menus, creates a profile, and reloads that
profile after a fresh process launch (the game displayed “Load successful”).
Single Event → Race → USA → Silver Lake Southbound → Compact Type 1 loaded.
Scripted trigger input accelerated the car; a screenshot captured 121 mph.
Further input exercised steering, braking and pause. The touch overlay changed
between menu and driving controls; physical touch usability remains unverified.

From the first acceleration command at pad t=125223 ms to pause at t=280702 ms,
31 periodic samples reported 59.9–60.1 presentations/s and 59.9–60.2 guest flips/s.
The interval includes coasting and idle input, collisions and track driving.
These counters measure guest flips and Metal presentation submission, not
optically measured display refresh or full frame-time percentiles. The captured
renderer counters reported zero shader compilation errors.

## Limits and next work

- Lower-left HUD has a visible checker-pattern rendering defect.
- One track and a partial race only; other events and unresolved call paths remain.
- Audio quality, actual multitouch input, controllers, interruptions,
  background/resume, sustained temperature and memory pressure are unverified.
- This test supports continuing the Xbox iOS prototype. It does not establish
  superiority over the existing PS2 port; a comparable PS2 test is still needed.

## Local evidence

Ignored files under `local/runs/iphone-20261023/`:

- `runtime-controlled.log`: complete log captured after pausing the test.
- `control-profile-loaded.png`: successful saved-profile reload.
- `control-driving-1.png`: race at 121 mph.
- `control-boost.png`, `control-steering.png`, `control-brake.png`,
  `control-paused.png`: later input steps. Boost was commanded; its effect was
  not separately established.
- `build-6.log` and `host-tests-final.log`: build and focused host checks.

The app is relaunched without test scripts or a timed exit after capture.

## Build 7 — native app migration

The installed app now appears as **Burnout 3 Xbox** with our original B3 icon.
The bundle ID and Xbox data locations are unchanged. A native launch screen,
settings panel and staged folder importer have been added. The launcher and
settings were inspected on the iPhone; automated Play selection successfully
transitioned through the launcher into the game intro with the native overlay.
No new race-performance claim is made for build 7.

The four focused host suites pass, including new preference and import checks.
The exact native validator also verifies all 716 original files on the Mac.
The import tests cover corrupted/missing data, symbolic links, staging cleanup
and preservation of an existing installation. The Files picker itself has not
been driven end to end on the phone; that remains an explicit test gap.

Evidence: `launcher-7-ready.png`, `settings-7.png`, `game-after-launcher-7.png`,
`runtime-launcher-7.log`, and `build-7-handoff.log` in the same ignored run folder.
The earlier race test and known HUD defect still apply.

The final build 7 revision installed successfully, but its final launch attempt
was rejected because the phone had locked. The earlier build 7 launcher/settings
and launcher-to-game checks above passed before that lock.

## Build 8 — hybrid controls

Installed and launched normally on the unlocked phone, with no scripted inputs
or timed exit left active. A race was reached with the hybrid overlay and
profile reload still passed. `hybrid-driving.png` captures the layout during
a race/collision camera; `runtime-hybrid-8.log` contains that bounded run.

The final control logic passes 683 new checks; all five focused host suites
pass. The original 103-check touch suite still passes with Hybrid disabled.
Tests cover control geometry at five phone/tablet sizes and two size settings,
neutral pickup, response curves, independent fingers, release/cancellation and
continuous throttle while sliding into boost. Tablet geometry is tested on the
host; an iPad has not been used for physical validation.

The first build-8 race/collision-camera sample had 20 periodic presentation
reports: 18 at 60.0–60.1/s, one at 59.0/s and one at 37.0/s. The cause of the
brief dip has not been isolated. Do not interpret this as sustained 60 fps.
The final revision avoids repainting unchanged controls while retaining a
60 Hz context/input check and independent Core Animation release springs;
its race presentation rate has not been remeasured.

Physical comfort, true touch latency, audio, long sessions and the earlier
HUD issue remain hands-on/device follow-up items. The final app defaults to
Hybrid; Settings → Touch controls → Control layout restores Xbox prototype
for comparison. No physical controller mappings were changed.

Final evidence: `build-8-handoff.log`, `host-tests-8-final.log`, and the
reviewable `ios/runtime.patch`.

## Build 9 — optimization and game-menu integration

Installed and tested on the same iPhone. The game's Driver Details → Settings
and ordinary race pause menu both render IOS SETTINGS. Selecting the injected
entry opens the native panel. Launcher is directly accessible in the toolbar;
the launcher offers Resume game. The live game returned to the same pause menu
after the scripted return/resume sequence. The original race QUIT still showed
its confirmation and returned to the front end after confirmation.

The final held interval kept guest flips at 17,726, and they advanced again
after Resume. The native overlay clock stops while held; opt-in profiling
continues on a slow timer. Process CPU while the live session was held remained
about 58% of a core in this sample, so returning to the launcher does not fully
tear down or idle the runtime. Normal auto-lock is restored on the launcher.

Seven focused host suites pass. Menu tests cover labels/counts, register
preservation, original Quit dispatch and item bounds; session tests cover
settings/launcher/background ownership and idempotence. Background ownership is
unit-tested; a fresh physical background/resume cycle was not exercised here.

A three-run menu pacing comparison selected 4 ms spin lead as the new iOS
default: 52.98% mean process CPU versus 76.92% at 8 ms, with comparable recent
guest flip p95 (16.744 vs 16.760 ms). These are short sequential warm-phone
menu samples, not battery-life or sustained racing results. Full details and
thermal caveats are in OPTIMIZATION.md.

Final evidence under the existing ignored run folder:

- `final9-pause-menu.png`: injected pause row, original Quit preserved.
- `final9-native-panel.png`: native Settings with Launcher toolbar action.
- `native-launcher-roundtrip.png`: Resume launcher in the earlier menu run.
- `final9-resumed-pause.png`: return to the same paused event and selected row.
- `final9-quit-confirm.png`, `final9-after-race-quit.png`: original Quit flow.
- `final9-session-complete.log`: final default pacing and session trace.
- `build-9-handoff.log`, `host-tests-9.log`: signed build and seven host suites.

The app was relaunched normally without diagnostic flags, automated input or
a timed exit. Physical touch/audio quality, long-session thermals and the
earlier HUD defect remain follow-up items.


## Build 10 — quieter controls

Installed and launched on the same iPhone. The overlay now follows the PS2
visual treatment: visibility applies to labels and the stick as well as rings,
with brighter feedback while held. Removed the extra Xbox correspondence badges
from driving buttons and centered the action names. Layout and touch mapping
are unchanged. Menu navigation keeps its button names.

Signed device build, signature verification, plist lint and diff whitespace
checks pass. Visually checked the race overlay on-device in
`local/runs/iphone-20261023/build10-grid.png`; this is a visual check, not a
new physical touch or performance test. Build log: `build-10.log`. Relaunched
normally at the native launcher after the scripted check.


## Build 11 — main app identity (27 October 2026)

The Xbox-based app is now named **Burnout 3** and installed as build 11.
The app icon is byte-identical to the original PS2 project icon (SHA-256
`6f3215292f04c0eedaed299744300b7e024ffc0f23dd0d8ac962bb303f5d0440`).
Bundle ID remains `dev.burnout3.takedawn-ios`, preserving its existing container.
Signed build, signature verification, plist lint and whitespace checks pass;
device app inventory confirms name/version. The initial launch was blocked by the locked phone; after account renewal,
normal launch succeeded and the native launcher showed game files Available.

The old PS2 project's source display name is now Burnout 3 PS2, but its device
update is pending: Xcode reports no signed-in account and its profile expired
on 23 October. The installed PS2 build 54 still displays Burnout 3. Nothing
was uninstalled or migrated between game formats. The main app’s existing
profile expires 27 October at 21:29 Singapore time; renewal needs Xcode account
sign-in. Evidence: `local/runs/iphone-20261027/build-11.log`.

Signing follow-up: Xcode Apple Accounts now contains the owner’s account.
The main profile was renewed to 3 November 2026, 10:40 Singapore time;
after refreshing the profile, the bundle was explicitly re-signed and
strict signature verification passed. The renewed app installed successfully.
Evidence: `build-11-renewed.log`, `main-launcher-renewed.png`.

Completion after account sign-in: the PS2 Release build succeeded, strict
signature verification passed, and build 55 installed as **Burnout 3 PS2**.
Device inventory confirms the main app **Burnout 3**, build 11, and the older
**Burnout 3 PS2**, build 55. Both keep their original bundle IDs and containers;
neither app was uninstalled. Both profiles now expire 3 November 2026 around
10:40 Singapore time. The earlier signing/rename blockers above are resolved.
The PS2 update was built and installed, without a new gameplay test.
Evidence: `app-identities-final.json` and the PS2 repo’s
`local/runs/iphone-20261027/legacy-name-build.log`.


Final identity correction at the owner’s request: keep only the Xbox app.
Copied and verified the PS2 memory card (3 files, 77,970 bytes) to the PS2 repo’s
`local/runs/iphone-20261027/ps2-memcard-backup` before uninstalling
`dev.burnout3.nativeprobe`. Device inventory now contains only **Burnout 3**,
Xbox build 11. Source artwork and both compiled iPhone/iPad icon PNGs match
the old PS2 app byte-for-byte (original orange B3 artwork). No main-app data
was removed. Evidence: `single-app-final.json`.


## Build 12 — white/red icon correction

The owner clarified that the intended icon is the red B3 logo on white.
Used the old upstream `burnout3-pc/games/burnout3/port/icon.ico` artwork,
packaged on an opaque white 1024px canvas. The compiled iPhone icon was
decoded and visually inspected (`icon/compiled-preview.png`). Signed build,
strict signature verification, plist lint and whitespace checks pass. Installed
build 12 in place, keeping the Xbox app container. Device inventory confirms
only one Burnout app: `dev.burnout3.takedawn-ios`, build 12. The PS2 app remains
uninstalled. Evidence: `build-12-icon.log`, `icon/app-final.json`.


## Build 13 — exact historical PS2 icon restored

Recovered the actual PS2 iOS icon from local Git object
`ed367fd6dd2fb4763aa9b62f810523fbb9b82524`. Earlier session records confirm
it was installed in the PS2 project on 17 October and superseded during the
20 October repository cleanup. Build 12’s upstream desktop B3 icon was the
wrong image. Build 13 uses the recovered PNG byte-for-byte; `git hash-object`
matches the historical blob. The compiled icon was decoded and visually
checked. Signed build and strict signature verification pass. Installed in
place; device inventory confirms only Xbox-based Burnout 3 build 13.
Evidence: `build-13-original-icon.log`, `icon/restored-original-preview.png`,
`icon/restored-final.json`. Xbox data remains in its original container.
