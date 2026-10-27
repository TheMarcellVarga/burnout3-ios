# Custom music: your own folder in EA GAMES TRAX (BO-108)

Burnout 3 on the Xbox plays custom soundtracks: music ripped on the dashboard
shows up in Driver Details > Settings > EA GAMES TRAX, where X ("NEXT
SOUNDTRACK") steps from EA GAMES TRAX through the console's soundtracks. The
port offers a folder of your own music there. Off by default.

## Use

In the game: the settings overlay (Back+Start, F1, Cmd+,), Audio page,
**Custom music folder**. A opens a folder list inside the overlay; a pad is
enough (D-pad, A to open or choose, B to go back):

- it starts on the places: the folder in use, Music, Home, Downloads and what
  is mounted (macOS: /Volumes; Linux and the Steam Deck: /run/media, the SD
  card among them, /media, /mnt; Windows: the drive letters), and "Computer: /";
- in a folder: "Use this folder", "..", and its folders, each with the number
  of songs in it as the game reads it (three levels down)
  (counted in the background, up to 20 000 entries a row: "1234+ songs" when
  it stopped there);
- "Turn custom music off" on the places, when a folder is set.

The choice is saved as `audio.custom_music_dir` in settings.toml and used at
once: the line under the row counts the files while the folder is read, then
says how many soundtracks there are. Then, in the game: Driver Details >
Settings > EA GAMES TRAX, X until the folder's name is the heading, A to
confirm. The title remembers the choice in the profile. In a race the Black
button skips to the next song, as with EA GAMES TRAX; Y in the screen
switches random order.

One case waits for the next start: while one of the folder's soundtracks is
the game's music, a change is saved and the row says so (choose EA GAMES TRAX
in the game's screen first to change the folder without a restart).

Also: `--music-dir <folder>` for one run, or `RECOMP_AUDIO_MUSIC_DIR` (the
row is then locked), or the key in settings.toml by hand:

```toml
[audio]
custom_music_dir = "/Users/you/Music/Driving"
```

- A folder of songs, or a folder of folders: each one a soundtrack. The
  folder's own files are one soundtrack, and each folder directly in it is
  another, named after the folder, with the songs in its own folders two
  levels further down counted in (an artist's folder with album and disc
  folders is one soundtrack; the albums are not soundtracks of their own).
  100 soundtracks, 500 songs each; the rest is left out and the log says how
  many. Deeper than that is not read, and a folder that is a link is not
  followed. The folder is read in the background, at start too (the game
  never waits for it), and at most 20 000 entries of it: choosing Home or a
  whole disk stops there and the row says so.
- mp3, flac, ogg (Vorbis) and wav play everywhere. On macOS also m4a (AAC and
  Apple Lossless, what an Apple Music or iTunes library holds), aiff and caf,
  through the system's own decoder; protected files (m4p) do not. Opus and
  WMA files do not play.
- A file that cannot be read is left out, and said: the line under the row
  counts what was left out, the lines below it name the files with the
  reason, and the log has every one (`[SOUNDTRACK] left out: <file>:
  <reason>`).
- Songs are listed in natural order of file name and named by their title
  tag, else the file name. Names are cut at 31 characters and kept to
  Latin-1, as far as the title's font goes: "ő" shows as "ö".
- At start the folder is read before the title boots (10 000 small files:
  0.3 s on the Mac it was measured on).

## Loudness (BO-132)

Modern songs are mastered at about -7.5 LUFS with peaks at or past 0 dBFS.
The title sends a custom-soundtrack stream about 8 dB hotter than its own
EA GAMES TRAX streams, and in stereo the fold sums the fronts, the centre
and the surrounds on top, so the mix reached past full scale and the 16-bit
clamp cut it flat: distortion. Two things stand in front of that.

- **Custom music loudness** (Audio page, under "Custom music folder";
  `audio.custom_music_level`, `RECOMP_AUDIO_CUSTOM_LEVEL`): `off`, `quieter`,
  `match` (default) or `louder`. A slow gain on the custom-soundtrack voices
  only (the voices the custom player starts; EA GAMES TRAX, speech and
  effects are not touched): a 3 s mean-square envelope of the song's two
  channels, the gain that brings it to the level EA GAMES TRAX has in the
  game (-20 LUFS in the game; one constant,
  `APU_LEVEL_TARGET_DB` in the toolkit's `src/apu/apu_level.h`), limited to
  -15 .. +6 dB, followed down in 0.3 s and up in 4 s, interpolated across each
  0.67 ms mixer block, frozen in silence, under -40 dBFS and while the level
  falls (a fade out). The 0.3 s reading less 2 dB counts as well, so a step
  from quiet to loud is caught in a fraction of a second. A new song starts at
  the gain the last one settled on; the very first song starts at -6 dB until
  half a second of it has been heard. `quieter` and `louder` are 4 dB under
  and over `match`. `off` is no code at all: your songs are mixed as the
  title sends them. A song that was already playing when the setting
  changed is followed from the next song.
- **A safety peak limiter** on the final output (also on the fold of a 5.1 title
  to a stereo device), always on (the
  toolkit's `src/apu/apu_limit.h`; `RECOMP_AUDIO_SAFETY_LIMITER=0` switches it
  off for comparison): ceiling -0.5 dBFS, no look-ahead (no added
  latency), instant attack, 50 ms release, all channels linked, after the
  stereo fold or on the six channels. While nothing reaches the ceiling it does
  nothing and the output is bit for bit what it was without it
  (`tests/apu_bus`, with a recording of a race: 0 frames differ).

Measured (stereo, headless, `tools/headless/custom_level_scene.sh` and
`level_report.py`; four dance masters at -5.2 to -8.6 LUFS, the first, at -5.2
LUFS with sample peaks at +3 dBFS, playing; the menu has the music alone, the
race adds engine and effects; loudness is EBU R128 of the WAV the run kept):

| | menu, music alone | race: samples at full scale / within 0.5 dB of it | race true peak |
|---|---|---|---|
| EA GAMES TRAX | -19.2 LUFS here; -20.1 LUFS on average (-19.7, -23.1, -18.6, three songs) | 0 / 34 | -0.2 dBFS |
| custom, as before (off, no limiter) | -8.4 LUFS | 886 / 2805 | +0.6 dBFS |
| custom, off, safety limiter only | -8.4 LUFS (same bytes) | 0 / 298 | 0.0 dBFS |
| custom, match | -20.1 LUFS | 0 / 65 | -0.2 dBFS |

Off was 10.8 dB above the game's own music in the menu; match lands at its
average (-20.1 LUFS, the target constant set from that measurement; a song of
the player's own is a point, not a rule: EA GAMES TRAX's songs themselves
differ by 4 dB). A 5.1 title played on a stereo device folds its six feeds
(L = FL + 0.707 C + 0.707 SL); the limiter stands after that fold too, on the
16-bit sums, and the fold's gains are the game's own.

`RECOMP_AUDIO_LEVEL_LOG=1` logs the envelope and the gain once a second.
`tools/headless/custom_level_scene.sh` plays copies of songs as a soundtrack
in a headless run and keeps the WAV; `tools/headless/level_report.py` reads it.

## How it works

The title side, from the executable (addresses of the NTSC-U build):

| what | where |
|---|---|
| XDK soundtrack library: ST.DB block read, open, XFindNext/FirstSoundtrack, XGetSoundtrackSongInfo, XOpenSoundtrackSong | 0x001D0134, 0x001D0172, 0x001D0256 / 0x001D0275, 0x001D032C, 0x001D0554 |
| the EA GAMES TRAX screen counts and lists the soundtracks | sub_00155720 (set-up: also makes the music stream), sub_00155CB0 |
| a song's name for the list | sub_00084CF0, sub_001538F0 |
| the music player, once a frame | sub_00155900 |
| asks the file thread for song n of soundtrack s | sub_00155D60 -> sub_001B3E20; the thread: sub_001B3B40 |
| makes the WMA decoder for the opened handle | sub_00155DB0 -> sub_0030211F (WMADEC section) |
| next song: in order, or from a shuffled list of up to 500 | sub_00153660, sub_00153950 |

The player makes one DirectSound stream (PCM, 44.1 kHz, 16 bit, stereo) and,
for a user soundtrack, pulls 0x2000-byte packets from the song's WMA decoder
into it: `DoWork`, `GetStatus`, `Process`, and `Release` at the end. A packet
of 0 bytes ends the song. EA GAMES TRAX songs come through the same player
and stream, from the disc's own files.

With no database on the emulated disk (the case until now: the open of
`TDATA\FFFE0000\MUSIC\ST.DB` fails) the screen still shows NEXT SOUNDTRACK,
and X stays on EA GAMES TRAX.

The port (`src/game/soundtrack.c`, the toolkit's `src/soundtrack`,
`docs/runtime/soundtrack.md` there):

0. The overlay's row and folder list are the toolkit's
   (`xbox_OverlaySetMusicFolder`, the browser's model `xsb_*` in
   `src/soundtrack/xst_browse.c`); the port answers "chosen" and the status
   line (`src/game/soundtrack.c`).
1. At start, with a folder set, the toolkit scans it, writes the database to
   `<save dir>/TDATA/FFFE0000/MUSIC.HOST/ST.DB` and sends the title's `MUSIC`
   paths there. A `MUSIC` folder copied from a real console is not touched.
2. `sub_001D0554` (XOpenSoundtrackSong) is wrapped: the title's own code,
   then a note of which song the handle is.
3. `sub_0030211F` (the decoder for a handle) is wrapped: for one of the
   folder's songs the title gets an object whose ten methods are host
   functions (called through its vtable, at addresses 0xFE7F5700.. that
   `recomp_lookup_manual` answers); `Process` fills the title's packet from
   the host's decoder. For any other handle the title's own decoder is made.

Everything after the decoder is the title's: the stream and its mix bins
(stereo music, as EA GAMES TRAX; 5.1 is untouched), the music volume of the
Audio settings, pause, skip, shuffle, the choice saved in the profile.

A change while the game runs: the title counts the console's soundtracks
once, when its music manager is set up during boot (sub_00152E00 ->
sub_00155720), and reads everything else from the database each time: the
EA GAMES TRAX screen at every step (sub_00155CB0), the player at every song.
So after the new folder is scanned (a thread of its own) and its database is
in place, the port sets the two numbers the title keeps, at the manager
(0x004115E8): +0x0C0 the soundtracks counted and +0x558 the sources (that
plus one, EA GAMES TRAX being source 0). It does so only while the title is
on EA GAMES TRAX (+0x538 set, +0x568 the chosen source 0): a chosen
soundtrack is an index into the list that changes. Checked in a run: no
folder at boot, a folder chosen in the overlay, and the title's screen
listed its soundtracks at the next visit.

Why not real WMA files (the dashboard's way): it needs a WMA encoder, of
which there is none under a permissive licence (FFmpeg's is LGPL and large),
and an import step that re-encodes the whole library with a loss.

AAC: no decoder under a licence this project ships is small enough to vendor
(FAAD2 is GPL, FDK-AAC has its own licence, FFmpeg's is LGPL and large,
Android's old OpenCORE one is Apache but a hundred files). The operating
systems have one each; macOS's (AudioToolbox, ExtAudioFile) is used, since
that is where such libraries are. Windows (Media Foundation) and Android
(MediaCodec) could do the same; Linux has none to rely on.

## A soundtrack longer than EA GAMES TRAX (BO-120)

EA GAMES TRAX has 44 tracks, in a table at 0x3EC450 (24 bytes a track: the
pop-up's artist, title and album string indices and the modes the track may
play in). The title starts a track with sub_001537C0(index), which takes the
record at table + index * 24 and checks nothing. And it has ways to go from
a custom soundtrack back to EA GAMES TRAX with an index of the list it is
leaving: sub_00155420 picks the next index (sub_00153660: the one after the
last played, or a random one of the list's count) before it switches the
source; that is what runs after B (Cancel) in the EA GAMES TRAX screen once
X has shown a soundtrack. From a soundtrack of more than 44 songs the index
can be 44 or more. The record is then whatever lies after the table: the
pop-up (sub_001530D0, 0x153161) uses two of its words as string indices, and
for some indices (59 and 60 were seen) that is a wild address: the crash of
BO-120, with a 142-song folder. The same code is on the disc: a console with
a long soundtrack has the bug too.

`bo3_soundtrack_start_track` (the third wrapped function, sub_001537C0)
brings such an index into EA GAMES TRAX's range (index modulo its count)
before the title's code runs, and says so in the log once a few times
(`[SOUNDTRACK] EA GAMES TRAX was asked for track 97 of 44 ...`). It looks
only after a music folder has been in use in the run.

`tools/headless/custom_music_scene.sh <rundir>` is the check for all of
this: a made 142-song soundtrack, X, 59 rows down, cancel, the screen again,
random play, the soundtrack chosen, 30 s in the menu and 30 s of a race with
two skips; in 5.1 and with split-screen music on by default
(`SPEAKERS=stereo`, `SPLIT_MUSIC=0` for the others). It fails on a fault, a
dead game, or no song of the folder opened where one must be.

## With the setting empty

- `bo3_soundtrack_init` only gives the overlay its row; no folder is read,
  no path redirect is installed and no file is written.
- The wrapped functions call the title's body and nothing else (the track
  start, sub_001537C0, is the one of the three the title reaches without a
  folder: it tests one flag and goes on). They are
  only reached while a user soundtrack plays, which needs a database: a run
  with a probe in all three entry points (boot, menus, the EA GAMES TRAX
  screen with X, a race, two skips, pause and resume) printed nothing.
- `recomp_lookup_manual`, asked at every indirect call, compares the address
  with 0xFE7F5700 first; no title code is above it.
- The generated code differs from before in the names of the two functions
  only (`sub_001D0554_gen`, `sub_0030211F_gen`).

The game's audio is not the same from run to run (two runs of one build
agree to the sample for the first 2.2 s of sound, then in 11 % of the
frames), so a capture cannot show identity by itself; build against build is
inside that same spread.

## Checking it

Unit tests: the toolkit's `tests/soundtrack` (scan, names, ST.DB, decoders)
and `tests/overlay_settings` (the text setting).

A run: make a folder with a 1 kHz sine in it, start with
`RECOMP_AUDIO_MUSIC_DIR=<folder> RECOMP_AUDIO_WAV=<file>` (scratch `HOME`,
`RECOMP_SAVE_DIR` and `RECOMP_SETTINGS=none`, as for every test run), choose
the soundtrack in EA GAMES TRAX and start a race: the log has a
`[SOUNDTRACK] song ...` line for each song the title opens, and the WAV's
spectrum the tone. Measured on macOS: a sine at -9.0 dBFS RMS in the file
comes out at -10.4 dBFS in the menu and in the race at the title's default
music volume, 99 % of the power at 1 kHz between engine sounds.

## Android

Done with way 1 below (2026-10-13): the row asks for `READ_MEDIA_AUDIO`
through SDL_AndroidRequestPermission the first time it is opened, on its own
thread so the menu keeps drawing; places that cannot be listed are left out,
and a chosen folder that cannot be read leaves the game's own music playing
with a status line. The two ways that were weighed:

1. Shared storage as files (the smaller one): `READ_MEDIA_AUDIO` (Android
   13+; `READ_EXTERNAL_STORAGE` before) in the manifest and asked for at
   run time from the game's activity when the row is opened. With it, audio
   files under /storage/emulated/0 and a card's /storage/<id> are ordinary
   paths, which is what the browser's Android places already list and the
   decoders already read. Left: the manifest line, the request (Java, in the
   SDL activity, called through JNI from the port's "chosen"/open hook), and
   a run on a device.
2. The document-tree picker (SAF), the system's own folder dialog: an
   activity like the driver page's (`ACTION_OPEN_DOCUMENT_TREE`,
   `takePersistableUriPermission`), the tree URI stored as the setting, the
   scan through `DocumentsContract` child queries (Java, handed to native as
   a list), and the decoders opened on file descriptors
   (`ContentResolver.openFileDescriptor` -> `fdopen`; dr_libs and stb_vorbis
   take callbacks or a `FILE *`). It needs no storage permission, but paths
   stop being paths: `xst_song.path` becomes a URI and every open goes
   through JNI. About two days with a device to test on.

## Not done

- Android: played by the owner on a Retroid Pocket 5 with his own folder;
  the permission prompt's deny path was not tried on a device. Windows and Linux are compiled (Windows: cross-compiled)
  but not run: the drive letters, /run/media and the Deck's SD card are in
  the browser's model and its unit test, not seen on a device.
- Folder names in the overlay's list: Latin (Central European, Baltic and
  Turkish letters included), Greek and Cyrillic are drawn; other scripts
  (CJK, Arabic ...) show as squares, though the folder still works (the
  toolkit's docs/runtime/overlay.md, "Text and fonts"). In the title's own
  menu names stay folded to Latin-1.
- m4a outside macOS.
- Real libraries: long playlists, odd tags, slow or network disks (the scan
  at start waits for the folder).
- The EA GAMES TRAX pop-up did not show for a user's song in a race (the
  title's own behaviour, as far as seen).
- The shader pre-build's runs read the setting too; they need not.
