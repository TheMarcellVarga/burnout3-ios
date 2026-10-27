# Contributors

Everyone who has moved this project forward, and what they did. If you've
contributed and aren't listed, or a line here is wrong, open a PR against this
file.

## Maintainer of Takedawn

### xenophobentx
The macOS, Linux, Steam Deck, Windows and Android ports, the Vulkan backend,
the installer, the settings menu and the optional picture and sound features.

## The upstream project

### Ned Heller, [@sp00nznet](https://github.com/sp00nznet)
Creator of [burnout3](https://github.com/sp00nznet/burnout3) and of the
[xboxrecomp](https://github.com/sp00nznet/xboxrecomp) toolkit, which Takedawn
grew from. The recompilation, the move onto the shared xboxrecomp runtime, and
the runtime work that got every mode playing.

### [apexJCL](https://github.com/apexJCL)
The fork of the toolkit that Takedawn's runtime is based on, with the Metal
backend and the first macOS host.

## Issue reports and testing (upstream)

### [@VincxBlox](https://github.com/VincxBlox)
Reported #1, *Unclear instructions in the readme, and not runnable*. It was
right on every count. The README described three build steps that didn't
produce a working game, pointed at a naming tool that wasn't in the repo, and
never said the result would show only a black screen at a steady 32 fps. That
build was a hand-written fork: fake menus and a fake road drawn over a game that
never really started. The report pushed the rewrite onto the xboxrecomp
runtime, where the title boots through its real entry point, plus a README whose
steps are tested from a clean folder and a one-click `Setup.cmd` (both in the upstream repository).
