@echo off
rem play-trace.cmd - starts burnout3.exe the way a double-click does (this folder,
rem the same console window) and records, in traces\ beside it:
rem   log-<stamp>.txt      the game log (pipeline compiles, texture uploads, the
rem                        presenter statistics every 5 s)
rem   ft-<stamp>.csv       one line per frame (where its time went)
rem   vp-<stamp>.csv       every present and every refresh of the display
rem   hudmon-<stamp>.txt   the HUD boxes an edge of the picture cuts, and the boost
rem                        message's place at every flip (BO-89)
rem   hud-<stamp>_*.bmp    a frame when a HUD text or message box is cut, a few of each
rem Play as usual, then send the files. Your settings.toml is not touched.
rem
rem No per-frame lines go to the log (pacing, not pacing=all): with the power
rem mode Maximum such a line waits for the log's lock behind the title's file
rem thread, 30-60 ms at a time, and the trace would make the stutter it is
rem there to find (BO-75). tools\win\pacing_stats.py reads these files:
rem   python pacing_stats.py traces\log-X.txt traces\ft-X.csv traces\vp-X.csv
setlocal
cd /d "%~dp0"
tasklist /FI "IMAGENAME eq burnout3.exe" 2>nul | find /I "burnout3.exe" >nul && (
  echo Burnout 3 is already running - close it first.
  pause
  exit /b 1
)
if not exist traces mkdir traces
set "TS="
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
if not defined TS set "TS=%RANDOM%"
set "TP=%~dp0traces"
set "TP=%TP:\=/%"
set "RECOMP_TRACE=pacing,pcache,frametime=%TP%/ft-%TS%.csv,frametime_us=0,vk_present=%TP%/vp-%TS%.csv"
set "RECOMP_PRESENT_STATS=1"
set "RECOMP_STDIO_LOG=%~dp0traces\log-%TS%.txt"
set "BO3_HUD_MON=%TP%/hudmon-%TS%.txt"
rem The boost message (DRIFT, AIR...) is followed at every flip it is drawn; frames are
rem written only when a box of the boost message, the HUD texts or the awards is cut
rem (a few of each kind: a frame dump costs that frame 11-30 ms).
set "BO3_HUD_MON_TRACE=4B4D0"
set "BO3_HUD_MON_SHOTS=%TP%/hud-%TS%_"
set "BO3_HUD_MON_SHOTS_CB=4B4D0,F7C20,5AC20"
burnout3.exe
