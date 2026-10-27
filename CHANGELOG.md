# Changelog

What changed in each release of Takedawn, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Major releases carry
a codename, a song title from the game's soundtrack.

## 0.2.0 "Hot Night Crash"

Saves and settings from 0.1.1 carry over.

### Added

- Bloom and Motion blur are sliders, 0 to 100%, 100% is the original.
- HDR output on Windows, Linux and the Steam Deck (Graphics > HDR): peak, paper white, HUD brightness, shadows, highlights and gamma. The sun's disc fades from its centre. Macs show the row on an HDR display; not checked there.
- Frame pacing: Automatic, Low latency, Smooth (Windows, Linux, Deck). Automatic is Smooth on the Deck.
- A watchdog resets the frame timing after a long stall, a resume from sleep or a display change.
- Potato mode (Graphics): the race keeps real time from its start on a machine under 60 fps. Off by default.
- Import Xbox save... (Advanced), and `--import-save` on the command line.
- Touch controls on Android: in a race, a stick for the left thumb and GAS, BRAKE, BOOST, BREAKER, LOOK and VIEW on the right; in menus, a d-pad, A, B, X, Y, LT and RT. They hide while a controller is in use. Settings on the Input page: Touch controls (Auto, Always, Off), opacity, size, Accelerate automatically. The settings menu works by touch.
- The setup window can put the game data in another folder (Change...), on Mac, Windows and Linux.
- Menu sounds in the settings menu, from the player's disc (Audio > Menu sounds).
- Windows builds natively from Git Bash (d-b-c-e).

### Changed

- The game ships a list of the shaders and pipelines it needs and builds them all before the first picture ("Preparing graphics N/M"). The setup's graphics step takes seconds. On Android it runs at the first start and is kept in the app's files. The list holds no game data.
- The other HDR variant is built in the background. A damaged graphics cache is detected and built again.
- Android has no Fullscreen setting; the game always fills the screen.

### Fixed

- Windows with variable refresh (G-Sync, FreeSync): uneven frame times and a game clock that ran slightly fast (GitHub #4).
- The Crash Nav globe and the garage were drawn too small. The recompiler dropped part of the game's field-of-view calculation (GitHub #15).
- A failed sound bank load froze the race start or crashed Takedawn (GitHub #17).
- Quitting could crash on some systems; the render and sound threads now stop before the graphics device closes (GitHub #17).
- Windows, drive with 4096-byte sectors: "There is a problem with the disc you are using" (d-b-c-e).
- Reset this page and Reset all settings acted on one keypress; they ask once more.
- Diagnostic logging switched on in the settings was off at the next start.
- LED sign words and chevron markers flickered on some US and European tracks.

## 0.1.1 "Lazy Generation"

A fix and polish release. Saves and settings from 0.1.0 carry over.

### Added

- Power mode Auto. It watches how early each frame is ready and keeps the
  processor busy only when frames start to arrive late. When the game runs
  easily, it uses less power than Balanced.
- Scenery detail: Original or Far. On Original the pines switch to flat
  cut-outs at 250 m. On Far, trees and other roadside objects keep their
  detailed models as far as they are drawn. Far is the default on desktops
  and the Steam Deck, Original on Android.
- Score board: Original or Smooth. Smooth fades the dark plate behind the
  score together with its text.
- A hang report now also saves the game's memory, so a freeze can be traced
  back to its cause.

### Changed

- Fences, palms and other cut-out textures keep their density at a distance
  with Metal and Vulkan. Chain-link fences no longer turn into grey walls,
  and thin railings no longer disappear.

### Fixed

- A rare freeze after a long session, where the picture stopped and the game
  had to be closed. It came from the game's sound code being run later than
  on the console.
- The wait at the first loading screen on Mac, Windows and Linux.
- The LED signs above tunnels lost some of their letters for a frame now and
  then.
- Switching Bloom off while the glow was on screen left that glow frozen on
  the picture.
- The rows of the settings menu no longer jump when the hint text below them
  changes length.

## 0.1.0 "Lazy Generation"

The first release. Takedawn runs the original Xbox version of *Burnout 3:
Takedown* as a native program on Mac, Windows, Linux, the Steam Deck and
Android.

### Graphics

- Render scale from 1x to 4x of the console's 640x480, and 1.5x on Android.
- The game's 16:9 mode with a widescreen HUD fix: the HUD keeps its shape and
  stays at the edges of the picture.
- Ultrawide at 21:9, 32:9 or the window's shape. Races are drawn for the whole
  width. Menus and loading screens stay 16:9.
- Frames held to the display's refresh, including 120 Hz displays.
- 60 fps crash and takedown cameras, in races and in Crash mode. The console
  drops to 30 there. Off by default.
- 60 fps in two-player split screen. The console runs it at 30. Off by
  default.
- Menu and HUD upscaling at 2x or 4x with Super-xBR, so text and icons stay
  sharp at high resolutions.
- Anti-aliasing with FXAA or SMAA, sharpening with AMD FidelityFX CAS, and
  anisotropic filtering up to 16x.
- Texture sharpness: sharper texture levels at higher render scales.
- Vehicle detail distance: rival cars and traffic keep their detailed models
  two or four times as far.
- The game's bloom and motion blur can be switched off.
- The picture is cropped to what a television showed, with an option to show
  the whole frame and one to fill a 16:10 screen.
- Speed and distances in km/h and metres.
- Compiled shaders are remembered between starts.

### Sound

- Custom music: point Takedawn at a folder of MP3, FLAC, Ogg or WAV files and
  pick it in the game's EA GAMES TRAX menu. Each folder is a soundtrack. On
  Android the game asks for access to music files when you open the row.
- Loudness matching brings your songs to the level of the game's own music.
  Quieter, louder and off are available. A safety limiter on the output
  stops clipping.
- Music in split screen, which the console does not have. Off by default.
- 5.1 surround with automatic detection, a stereo fold-down, an effects level
  and a speaker test.
- The game's own reverb in 5.1, run from the original DSP program on the disc.
- A mixer sets each sound group (music, engines, crashes and others) per
  speaker. It includes a recommended 5.1 preset.

### Controls

- Button prompts for Xbox (original and modern), PlayStation (DualShock and
  DualSense), Nintendo and Steam pads, or a neutral set that shows the
  button's position. They follow the controller you use, or you pick one. The
  pictures are original artwork. The game's text and training films still
  name the Xbox buttons.
- The PlayStation 2 version's driving controls as an option: accelerate and
  brake on the face buttons, boost on the right shoulder. It holds only while
  driving.
- Rumble with a strength setting from 0 to 3. At 1.0 the curve follows the
  Xbox pad's.
- Android: the device's own vibrator for its built-in controls.
- A Nintendo face-button layout.
- The keyboard works as a pad on Mac, Windows and Linux. The map is fixed:
  W or Up accelerates, S or Down brakes, A and D or Left and Right steer,
  Space boosts, Shift looks back, Ctrl changes view, Backspace is the
  Crashbreaker, E is the next music track and Enter pauses. It uses the Xbox
  layout whatever Driving controls says, and a controller works beside it. Not
  on Android.
- The button prompts show keyboard keys while you use the keyboard, and the
  controller's buttons while you use the controller.
- A controller plugged in later is picked up, and a controller gets its port
  at its first button press.
- A or Start skips the training film before a mode's first event. The
  console has no skip.

### Menu

- A settings menu drawn in the game's own style, with its fonts and sprites.
  Open it with Back and Start, F1, or Cmd and comma on a Mac. It is also
  TAKEDAWN SETTINGS in the game's Settings menu and in the pause menu. The
  game is paused while it is open.
- Settings are saved to `settings.toml`. Each page can be reset to its
  defaults. Restart game and Quit game rows sit at the foot of every page.
- Power modes Balanced and Battery saver, and on a Mac also Maximum.
- A performance overlay with the frame rate and a frame-time graph.
- Create bug report on the Advanced page, or `--bug-report` from a terminal,
  writes one zip with logs, settings, a system summary and frame times. User
  name, computer name and home folder are taken out. Nothing is uploaded.
- Release builds keep quiet logs. Diagnostic logging on the Advanced page
  turns them on, and a crash turns them on by itself.

### Saves

- A history of the save as it was before each save. The 20 newest are kept,
  then one a day for a week and one a week for a month. "Restore an earlier
  save" in the menu brings one back.
- Saves can be exported to a folder and imported at the next start, also
  between platforms.
- The game writes a save beside the old file and renames it into place. One
  running copy per save folder.
- A crash, a failed check in the game or a hang writes a report folder.

### Install and updates

- A ready-to-run program for each platform: a disk image for Macs with Apple
  silicon and macOS 13 or newer, a setup program for 64-bit Windows, an
  AppImage for Linux and the Steam Deck, and an APK for Android devices with
  a Snapdragon chip. No compiler or other tool is needed.
- The downloads contain no game data. A setup window opens while the data is
  missing, asks for a copy of your own disc, checks that it is the North
  America retail release, copies the data and verifies every file by size and
  SHA-256. An interrupted install continues where it stopped, and the game
  does not start from an incomplete one. Other regions, patched executables
  and Xbox 360 discs are refused with the reason.
- The "Prepare graphics" box in the setup window, ticked by default, has the
  game play two scenes by itself to compile its shaders before the first
  race. It is also in the menu under Graphics. Not on Android.
- The same installer runs from a terminal with `--install`, and
  `--data-status` says whether the data is whole.
- Linux: a box in the setup window adds Takedawn to your Steam library. The
  window asks first, closes Steam for a moment and starts it again. It also
  writes library art (cover, hero and logo) made from your disc, or
  Takedawn's own art if that does not work. Advanced > Add Steam library art
  writes the same art for a Takedawn entry already in Steam. On Linux and the
  Steam Deck the setup window works with a controller, has its own disc
  browser and offers a disc it finds by itself.
- Android: the first start asks for the disc image with the system's file
  picker and needs no storage permission.
- Check for updates on the Advanced page (desktop) says whether a newer
  version is out. Nothing is downloaded.
- To update, run the new setup program on Windows, replace the AppImage under
  the same file name on Linux and the Steam Deck, drag the new app over the
  old one on a Mac, or install the new APK over the old one on Android.
  Saves, settings and game data are kept.
- Save, settings and cache folders are named Takedawn.
- None of the downloads is code signed. The README describes the one-time
  prompt on each system.

### Platforms

- macOS on Apple silicon, drawing with Metal.
- Windows, drawing with Vulkan.
- Linux and the Steam Deck as a native program drawing with Vulkan.
- Android on arm64, drawing with Vulkan through a bundled Mesa Turnip driver
  for Adreno GPUs. You can choose the bundled driver, the device's own or a
  driver package from the launcher, the setup page or the settings menu. If a
  chosen driver fails, the next start goes back to the bundled one. On
  the Retroid Pocket 5 the GPU still stalls now and then, about every 40
  minutes. The driver recovers within a frame or so and the game carries on.

First-start settings on every platform: full screen, 16:9 with the widescreen
HUD fix, linear filter, sharpening 30%, Menu and HUD upscaling 2x, texture
sharpness Auto. The rest depends on the platform:

| | Render scale | Anti-aliasing | Vehicle detail |
|---|---|---|---|
| Mac, Windows, Linux desktop | 3x | SMAA | Far |
| Steam Deck | 2x | SMAA | Far |
| Android | 1.5x | FXAA | Original |

On Android texture sharpness is off and anisotropic filtering is 4x.
