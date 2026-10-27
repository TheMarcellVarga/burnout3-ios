"""The opt-in `shaders` step (BO-93): the installed game builds its own shader
cache by playing a race and a crash event by itself (`burnout3 --build-shaders`,
docs/shader-prebuild.md). It is never forced: it runs only with `--shaders` or
`--only shaders`.

The game is started the way a player starts it, through the launcher the
package step wrote (on macOS the bundle's own executable, because Metal's
compiled cache belongs to the bundle id; on Linux `burnout3.sh`; on Windows
`burnout3.exe` with `<root>\\Game` as the working directory). Its stdout is the
installer's own protocol with one step, `shaders`; its PROGRESS and LOG lines are
forwarded under this step.

A failure here does not fail the install: the game works without the cache, it
only compiles each shader when first drawn. So it is raised as StepWarning, which
the driver reports as `STEP shaders FAIL <code> <text>` plus a `WARN` line and
then carries on: RESULT stays OK. Running the step again (`--only shaders`, or
the whole installer: the game skips scenes it has finished) picks up where it
stopped.
"""

import os
import signal
import subprocess
import sys
import time

from common import StepError

STEP = "shaders"

# What the game's failure codes mean, in plain words (the GUI has its own wording).
MESSAGES = {
    "cache-off": "the game's shader cache is switched off (render.shader_cache is none) "
                 "or its folder cannot be made",
    "no-game-data": "the game could not find the disc's files where it was started",
    "scene-failed": "the game lost its way twice in a scene (its log is kept in <cache>/prebuild)",
    "cancelled": "it was stopped before it finished; finished scenes are kept and the next run goes on",
    "game-failed": "the game ended with an error without saying why",
    "no-result": "the game ended without saying whether it worked",
    "game-not-started": "the game could not be started",
}


class StepWarning(Exception):
    """A step that did not work but must not fail the install."""

    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code = code


def launcher(ctx):
    """The program that starts the installed game and the working directory to
    start it in (None: the launcher chooses it itself)."""
    if ctx.mac:
        return os.path.join(ctx.app, "Contents", "MacOS", "Burnout 3 Takedown"), None
    if ctx.win:
        return os.path.join(ctx.app_dir, "burnout3.exe"), ctx.game_parent
    return os.path.join(ctx.app_dir, "burnout3.sh"), None


def command(ctx):
    exe, cwd = launcher(ctx)
    argv = [exe, "--build-shaders"]
    if getattr(ctx, "shader_cache", None):
        argv += ["--cache-dir", ctx.shader_cache]
    return argv, cwd


def parse(line):
    """(kind, rest) of one line of the game's protocol; kind is the first word."""
    parts = line.strip().split(" ", 1)
    return parts[0], (parts[1] if len(parts) > 1 else "")


def run(ctx, popen=subprocess.Popen):
    """Run the game's pre-build. Returns ("OK"|"SKIP", summary); raises StepError when
    there is no installed game, StepWarning when the build did not work."""
    argv, cwd = command(ctx)
    if not os.path.isfile(argv[0]):
        raise StepError("no-package", "no installed game at %s: run the package step first" % argv[0])
    os.makedirs(ctx.logs, exist_ok=True)
    log_path = os.path.join(ctx.logs, STEP + ".log")
    env = dict(ctx.env)
    state = {"cache": getattr(ctx, "shader_cache", None) or env.get("RECOMP_RENDER_SHADER_CACHE"),
             "result": None, "fail": None, "last": []}

    try:
        with open(log_path, "ab") as log:
            log.write(("\n==== %s: %s\n" % (time.strftime("%F %T"), " ".join(argv))).encode())
            try:
                p = popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            except OSError as e:
                raise StepWarning("game-not-started", "%s: %s" % (MESSAGES["game-not-started"], e))

            def cancel(signum, frame):
                # Asked to stop (the window's Cancel, Ctrl-C): tell the game the polite way
                # (the file it looks for within a second), then end it. Whatever it compiled is
                # in the key lists already; the next run goes on.
                if state["cache"]:
                    try:
                        os.makedirs(os.path.join(state["cache"], "prebuild"), exist_ok=True)
                        open(os.path.join(state["cache"], "prebuild", "cancel"), "w").close()
                    except OSError:
                        pass
                try:
                    p.terminate()
                    p.wait(timeout=5)
                except Exception:
                    p.kill()
                sys.exit(128 + signum)

            old = {}
            if os.name == "posix":
                for sig in (signal.SIGTERM, signal.SIGINT):
                    old[sig] = signal.signal(sig, cancel)
            try:
                for raw in iter(p.stdout.readline, b""):
                    log.write(raw)
                    line = raw.decode("utf-8", "replace").strip()
                    if not line:
                        continue
                    _forward(ctx, line, state)
                rc = p.wait()
                p.stdout.close()
            finally:
                for sig, handler in old.items():
                    signal.signal(sig, handler)
    except OSError as e:
        raise StepWarning("game-not-started", "%s: %s" % (MESSAGES["game-not-started"], e))

    if state["fail"]:
        code, text = state["fail"]
        raise StepWarning(code, "%s%s" % (MESSAGES.get(code, "the pre-build failed"),
                                          (": " + text) if text else ""))
    if state["result"]:
        kind, text = state["result"]
        return kind, text or "built"
    if rc != 0:
        for line in state["last"]:
            ctx.out.log(STEP, line)
        ctx.out.log(STEP, "full log: " + log_path)
        raise StepWarning("game-failed", "%s (status %d)" % (MESSAGES["game-failed"], rc))
    raise StepWarning("no-result", MESSAGES["no-result"])


def _forward(ctx, line, state):
    kind, rest = parse(line)
    state["last"] = (state["last"] + [line])[-15:]
    if kind == "PROGRESS":
        # PROGRESS shaders <0..1> <text>
        parts = rest.split(" ", 2)
        try:
            ctx.out.progress(STEP, float(parts[1]), parts[2] if len(parts) > 2 else "")
        except (ValueError, IndexError):
            ctx.out.log(STEP, line)
    elif kind in ("LOG", "WARN"):
        text = rest[len(STEP) + 1:] if rest.startswith(STEP + " ") else rest
        if text.startswith("cache "):
            state["cache"] = text[len("cache "):].strip()
        (ctx.out.log if kind == "LOG" else ctx.out.warn)(STEP, text)
    elif kind == "STEP":
        parts = rest.split(" ", 2)
        what = parts[1] if len(parts) > 1 else ""
        text = parts[2] if len(parts) > 2 else ""
        if what == "OK":
            state["result"] = ("OK", text)
        elif what == "SKIP":
            state["result"] = ("SKIP", text)
        elif what == "FAIL":
            code, _, why = text.partition(" ")
            state["fail"] = (code, why)
    # PROTOCOL, PLAN, BEGIN, RESULT: nothing to forward (the installer has its own)
