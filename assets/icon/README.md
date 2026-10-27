# Takedawn icon

Original artwork for this project (the "crimson T" on the navy panel); nothing
in it is taken from the game.

| file | what |
|---|---|
| `takedawn.svg` | the master, 1024x1024, full square (Windows `.ico`, Linux PNG, the setup window) |
| `takedawn-macos.svg` | the macOS shape: rounded square with the margin an `.icns` wants |
| `takedawn-android-fg.svg`, `takedawn-android-bg.svg` | the two layers of an Android adaptive icon |

All four are plain vector SVG (gradients and paths, no embedded bitmaps, no
fonts), so any renderer gives the same picture:

```
resvg -w 256 -h 256 assets/icon/takedawn.svg icon-256.png      # or rsvg-convert -w 256
```

The `.icns`, `.ico` and PNG sizes are made by the packaging scripts, not kept here.
