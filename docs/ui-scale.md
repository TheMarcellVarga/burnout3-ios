# Menu and HUD upscaling (`graphics.ui_scale`, BO-117)

The game's 2D art (menu text, HUD, icons, logos, button prompts) is drawn from
small textures: a font page is 256x256, the speedometer digits are about 20
texels tall. At a render scale above 1x the 3D gets sharper and the 2D stays
a bilinear enlargement with visible stair-steps. `graphics.ui_scale` scales
those textures 2x or 4x with an edge-following scaler before they go to the
GPU, as PPSSPP's texture scaling does, for the 2D art only.

Overlay: Graphics > "Menu and HUD upscaling" (Off, 2x, 4x).
`settings.toml`: `[graphics] ui_scale = "off" | "2x" | "4x"`.
Environment: `RECOMP_GFX_UI_SCALE`. Default 2x on the packaged desktop programs,
the Steam Deck and Android (the owner's decision of 2026-10-12, set in `main.c`'s
first-start block; a value in `settings.toml` or the variable wins), off in a
development build and in a `--headless` run. A change
shows at once (each texture as soon as its scaled picture is ready).

The code is the toolkit's (`src/kernel/nv2a_texscale.[ch]`,
`nv2a_texscale_store.c`, hooks in the Metal and Vulkan backends; its
`docs/runtime/overlay.md` has the mechanism). This page is what it does in
this game and what it costs.

## Which textures

No list and no hashes of the game's textures: the rule is how a texture is
used and what it is.

1. A draw with the depth test off and no depth write, into the frame itself
   (not one of the 320x240, 160x120, 128x128 effect targets), binds it. The
   title's 2D engine draws everything that way; the 3D world, particles and
   flares are drawn with the depth test on.
2. It has one mip level, a swizzled or DXT format, is at most 512x512, and is
   not a render target, cube map or signed (bump) texture.
3. Opaque or not: since bo3/uiscale-menu every texture a 2D draw binds is
   scaled, photographs included (the Crash Nav map, the loading pictures,
   the static between screens), as the owner asked for the whole 2D front
   end. Only the pass that runs when the setting is switched on keeps to art
   cut out with alpha.

Checked with `RECOMP_DEBUG=ui_scale_log,texrep_dump=<dir>` over the front
end, a race (Silver Lake) and a crash event (Trailer Trash): 219 textures
uploaded, 33 pass 1 and 2:

| Caught | |
|---|---|
| The three font pages (256x256, 128x256, 128x128) | yes |
| HUD pieces: position and lap plates, speedometer plate, boost bar, arrows, corner pieces | yes |
| Button prompts (the title's, or BO-107's replacements: scaled after they are put in) | yes |
| Burnout 3 logo, the mode logos (Race, Crash, Single Event), EA Trax art, Crashbreaker sign | yes |
| Car pictures of the car select, the menu frame's pieces | yes |
| A lens-flare sheet and a glow drawn in 2D (128x256, 64x64) | only where they have alpha; no visible change |
| Five 256x256 frames of static noise, the 512x256 loading photograph | no longer: opaque (rule 3). They were about two thirds of the scaled texels and three quarters of the scaling time |

Missed, because the title draws them as 3D objects with the depth test on:
the gold, silver and bronze medals, the yellow pick-up sign of the crash
junctions, the cracked-glass overlay. No world texture, sky, car texture,
video frame or render target is caught: every mipmapped texture fails rule
2, the films are linear 640x352 / 640x480 textures, and the sky strip that
is drawn without depth test goes into the 128x128 reflection faces.

## The scaler

Super-xBR (Hyllian, MIT; written from his three shader passes, notice in the
toolkit's `NOTICE` and in `THIRD_PARTY_NOTICES.md`). It was compared on the
title's own textures and in the game with a Catmull-Rom bicubic, a Lanczos-3
and MMPX (McGuire and Gagiu), and for a while all four could be chosen in the
menu; the owner looked at them side by side and kept Super-xBR alone:

- Super-xBR turns the stair-steps of the fonts, digits and outlines into clean
  edges. Photographic art (the red logo) gains less and looks slightly
  smoothed.
- Bicubic and Lanczos sharpen the stairs without removing them.
- MMPX needs texels that are exactly equal; this art is antialiased and
  DXT-compressed, so it leaves most of it as blocks.

Only Super-xBR and the bicubic (`RECOMP_DEBUG=ui_scale_algo=bicubic`, for
comparison) are in the program. Lanczos and MMPX were taken out again;
Scale2x, xBRZ and HQx were never in it (GPL/LGPL).

Colour is scaled premultiplied by alpha, with alpha as a fourth channel and
part of the edge measure, and given back as straight alpha (what the title's
blending expects); transparent texels beside visible ones take the visible
colour, so a glyph has no dark fringe. The values are the title's own
(gamma) values, as its blending and the GPU's filter use them. Past a
texture's edge the edge texel repeats. Cells of a sheet are not known to the
scaler: a result texel is held between the lowest and highest of the four
source texels around it, so a neighbouring cell cannot show where bilinear
filtering of the original would not show it.

The scaled texture has the mip levels down to the original size and is
sampled trilinearly, so an element drawn smaller than the scaled texture is
reduced through them (at render scale 1x that is the scaled picture reduced
to the original's size: nothing looked broken in headless 640x480 frames, it
was not compared closely). The setting is for a render scale of 2x and
above; 4x is for a 4K-class output.

## No hitch: the worker and the cache

Scaling a 256x256 font page to 4x takes 120 ms on one core of this Mac (M5),
33 ms on four. None of it is done on the render thread:

- A texture the rule picks is uploaded as the game has it, and its texels are
  queued for a worker thread. The worker loads the scaled picture from the
  disk cache, or scales it and writes it there. The render thread swaps the
  scaled texture in at a later frame, one texture a frame.
- The disk cache is `<shader cache>/ui_scale/` (per user, beside the shader
  lists; made from the player's own disc, never shipped): one file a texture,
  raw texels behind a header with a checksum, named by the hash of the
  source texels, the factor and the scaler's version. Written under another
  name and renamed. A damaged or cut file is deleted and made again. Past
  256 MB (`RECOMP_DEBUG=ui_scale_cache_mb=<n>`) the least recently used files
  go.
- Ahead of time: the shader pre-build (`--build-shaders`,
  [shader-prebuild.md](shader-prebuild.md)) plays the front end, a race and a
  crash; with `ui_scale` on (the environment variable, or the key in the
  player's `settings.toml`) its scenes fill this cache as they draw. And when
  the setting is switched on in the overlay, every loaded texture of at most
  256x256 that could be scaled is queued while the game is held, and the
  row's note says "Preparing sharper menus and HUD... n of m". (Larger ones
  are left to their own draw: that pass cannot tell 2D art from the car
  liveries and tree lines, and wrote those too, 8 MB a file at 4x.)

Measured on this Mac (M5, Metal) in a 3412x1920 window at render scale 4,
one run each: boot, front end, race load and 20 s of a race. The machine was
shared with other programs' test runs throughout, so the frame times carry
their noise (the run with the setting off had frames over 34 ms too).

| | 4x cold | 4x warm | 2x cold | 2x warm |
|---|---|---|---|---|
| Worker thread, all textures | 473 ms scaling (25) | 52 ms loading | 59 ms scaling (23) | 39 ms loading |
| Render thread, worst frame, boot and front end | 5.1 ms | 5.2 ms | 1.0 ms | 0.8 ms |
| Render thread, worst frame, race load and race | 12.2 ms (one swap; the next largest 2 ms) | 0.8 ms | 0.15 ms | 0.2 ms |
| Render thread, the whole path | 34 ms | 19 ms | 4.6 ms | 4.8 ms |
| Frames over 34 ms: front end / race load / race (off: 1 / 0 / 4) | 0 / 4 / 3 | 0 / 0 / 0 | 0 / 0 / 1 | 0 / 0 / 0 |
| Cache on disk | 33.4 MB, 25 files | the same | 6.1 MB, 23 files | the same |

The render thread's share is the hash and copy of a texture when it is
queued (0.4 ms at most) and the upload of the scaled texture when it is
swapped in. With a warm cache, and at 2x either way, no frame was longer
than without the setting. At 4x with a cold cache the race load had four
frames over 34 ms (85 ms the longest) while the worker was scaling on four
threads; one run on a shared machine does not say whether that is the
worker or the neighbours. The pre-build, or one earlier visit, makes the
cache warm.

Headless, crash event from a cold start, 4x: 25 textures, 330 ms scaling
cold, 50 ms loading warm, 25 MB on disk. Before the worker (scaling at
upload, one thread) the same paths had frames of 110 to 330 ms.

Texture memory, from the cache sizes (the scaled textures with their levels,
less the originals; not read from the GPU): about 42 MB more at 4x and 6 MB
at 2x on the race path. The pre-build's race scene wrote 28 MB at 4x and
7.2 MB at 2x.

Switched on in the overlay at the main menu: 13 loaded textures were queued
at once and the row's note read "Preparing sharper menus and HUD... 0 of
13."; the menu was scaled when the overlay closed.

Off: the factor asked for is 0, no draw is classified, nothing is hashed,
queued or allocated, and no thread is started. Checked against a build
without any of this, same commit otherwise, crash event, headless: the frame
taken a fixed number of frames after the junction's load (3D, HUD and
caption text, a still scene) is the same in every pixel of the drawn
picture, and the title bars of three menu frames (logo and page title) are
the same bytes. Two launches of one build do not reach their menus on the
same frame, so the other frames cannot be compared pixel for pixel.

The button prompts BO-107 replaces (PlayStation set tried) are scaled like
the title's own after they are put in; they come out clean, so they are not
drawn a second time at the larger size.

Vulkan: one headless run on MoltenVK at 4x (25 textures scaled and swapped
in, frames as the run without the setting at 640x480). Not seen in a window.

## Other machines

On by default (2x) on the Deck and Android since 2026-10-12. On Android it was
held off for a while: on a Retroid Pocket 5 (Adreno 650, Turnip) a session with
2x ended in a GPU hang with one 2D texture drawn as garbage. The hold was
taken out of the toolkit again (`nv2a_texscale_held()` is 0 unless
`RECOMP_DEBUG=ui_scale_hold=1`, BO-128), so the row shows and the default
applies; `ui_scale_hold=1` holds it anywhere, a way to rule it out when a GPU
fault is chased. On a Steam Deck or an RP5 the worker does the
scaling on cores the game also wants, two to four times slower than here; the
render thread's share (the swap) grows with the texture upload speed of the
device. Not run on either.
