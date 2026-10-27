tools/mix: the BO-114 mix study (what a custom 5.1 mixer could tell apart).

The trace is the toolkit's RECOMP_MIX_TRACE=<file> (src/apu/apu_vp.c): off by
default, nothing in the mix reads it. RECOMP_MIX_TRACE_GP=<from>-<to> adds the
GP effect states of the title's image (hex offsets) every 10 s.

  mix_race.sh / mix_crash.sh / mix_nav.sh   headless scenes (tools/headless style):
      a race with boost, traffic lanes and the pause menu; the Crash event;
      menu walks with a frame after each press (NAV="down:200 a:400 ...").
      Run with a scratch HOME, RECOMP_SAVE_DIR and RECOMP_SETTINGS=none, e.g.
      bash tools/mix/mix_race.sh <rundir> RECOMP_SETTINGS=none \
          RECOMP_AUDIO_SPEAKERS=5.1 RECOMP_MIX_TRACE=<rundir>/mix.txt
  mixlib.py    reads a trace; names each voice's wave from the disc's wave
               dictionaries (sound/*.awd, tracks/*/sound.awd, pveh/*.hwd, *.lwd)
  analyse.py   <run>...: per phase, speaker levels and peaks, and per bus the
               level, voices and share on each speaker (runs/<run>/mix.txt and
               scene.txt, from the folder holding runs/)
  plots.py     <run>...: the same over time as PNG and CSV (needs matplotlib)
  xbe_refs.py  <regex>: strings of default.xbe and the functions that refer to them
