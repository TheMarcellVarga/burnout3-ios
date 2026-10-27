# Contributing to Burnout 3 iOS

Current work targets the Xbox-based iOS app on `main`. The former PS2 source is
on [ps2-legacy](https://github.com/TheMarcellVarga/burnout3-ios/tree/ps2-legacy).
Start with the [iOS guide](ios/README.md) and [dependency pins](ios/dependencies.json).
The [upstream Takedawn reference](docs/UPSTREAM_README.md) describes inherited
desktop/Android functionality and is not the iPhone setup guide.

## Reporting a bug

Report iOS problems to [this repository](https://github.com/TheMarcellVarga/burnout3-ios/issues).
Include app build, device/iOS version, relevant settings, game mode and track,
reproduction steps, expected behavior and actual behavior. Say which checks were
scripted and which used physical touch or a controller. Review logs for private
paths before attaching them. See the [README](README.md#reporting-a-bug).

## Implementation and verification

- Game-specific hooks belong in `src/game/`; native iOS UI, preferences and session ownership belong in `ios/`.
- Keep runtime changes in `ios/runtime.patch` against the pinned xboxrecomp revision, and SDL changes in `ios/sdl.patch`.
- Preparation and build tooling lives in `tools/ios/build.py`. Dependencies and generated code remain local.
- Run the relevant [host suites](README.md#tests). Record the exact device, app build, menus/races and inputs used in device tests.
- For performance changes, compare the same scene and explain temperature, warm-up and sampling limits. Keep diagnostics opt-in.
- Report missing checks explicitly; shader compilation on a Mac does not prove iPhone rendering or sustained frame rate.

Do not commit disc images, extracted game files, generated C, disassembly,
profiles, signing material, shader caches or device captures. Existing app
artwork has its own [provenance record](ios/ASSETS.md); code licenses do not
transfer ownership of game artwork. Keep upstream attribution and notices.

Desktop/Android-specific reference pages and release scripts are retained from
Takedawn. Changes intended for those upstream platforms should name their tested
platform and should not be presented as verified iOS behavior.
