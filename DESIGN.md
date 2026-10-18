# Game startup and ISO import

## Purpose and scope

Operate mode for a single first-use task: supply a Burnout 3 ISO. Following the
owner's 2026-10-17 request, normal launches start the saved game automatically.

## Interface

A dark native system surface uses Dynamic Type, semantic foreground colors and
a single system button: “Upload ISO file”. “Add your game” introduces the
supported NTSC-U disc and explains that import is needed once and stays on device.
A centered, readable column sits inside landscape safe areas. Content scrolls at
large text sizes; the import target is at least 44 points tall. No artwork,
library, game metadata, controls guide or manual launch action appears.

## Flow and states

With a supported Documents/burnout3.iso, startup proceeds automatically. A short
“Starting game…” state covers gameplay controls until the first visible frame.
Without it, the import screen opens Files. Cancel leaves the import action
available. Selection validates the ISO metadata and supported executable name,
copies to a temporary file in the background, checks the copy, then installs it
and starts the game. The saved ISO is excluded from backups. Existing compatible
installations start automatically without reimporting.

Import errors explain recovery and keep the upload action available. Session
failures and ended sessions show a minimal message directing the player to reopen
the app, consistent with the host's one-session-per-process constraint.
Saved profiles continue to live separately in Documents/memcard/.
