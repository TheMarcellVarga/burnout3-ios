"""The opt-in `shaders` step (BO-93) against a fake game that replays the game's
--build-shaders protocol: built, already built, a scene that failed, cancelled by
the cancel file, ending without a word, and the installer being told to stop."""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import common    # noqa: E402
import shaders   # noqa: E402

INSTALL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "install.py")

FAKE = r'''#!/bin/sh
# Replays `burnout3 --build-shaders`. FAKE_SHADERS picks the story; the arguments are recorded.
echo "$@" > "$FAKE_ARGS"
cache="$FAKE_CACHE"
while [ $# -gt 0 ]; do [ "$1" = "--cache-dir" ] && cache="$2"; shift; done
echo "PROTOCOL 1"
echo "PLAN shaders"
echo "STEP shaders BEGIN Building shaders: the game plays 2 scenes by itself"
echo "LOG shaders cache $cache"
case "$FAKE_SHADERS" in
ok)
    echo "PROGRESS shaders 0.000 race"
    echo "PROGRESS shaders 0.250 race: driving"
    echo "LOG shaders race: done; the list holds 29 vertex, 32 fragment, 53 pipelines"
    echo "PROGRESS shaders 0.750 crash"
    echo "PROGRESS shaders 1.000 done"
    echo "STEP shaders OK 29 vertex, 34 fragment, 70 pipelines; 63259 bytes in $cache; 264 s"
    echo "RESULT OK $cache" ;;
built)
    echo "STEP shaders SKIP already built (race, crash)"
    echo "RESULT OK $cache" ;;
scene-failed)
    echo "PROGRESS shaders 0.200 race"
    echo "STEP shaders FAIL scene-failed race lost its way twice"
    echo "RESULT FAIL shaders scene-failed"
    exit 1 ;;
cache-off)
    echo "STEP shaders FAIL cache-off render.shader_cache is none"
    echo "RESULT FAIL shaders cache-off"
    exit 1 ;;
cancelled)
    echo "PROGRESS shaders 0.100 race"
    echo "STEP shaders FAIL cancelled stopped by the cancel file"
    echo "RESULT FAIL shaders cancelled"
    exit 1 ;;
silent)
    echo "PROGRESS shaders 0.100 race"
    exit 0 ;;
crash)
    echo "something broke" >&2
    exit 3 ;;
hold)
    echo "PROGRESS shaders 0.100 race"
    echo $$ > "$FAKE_PID"
    sleep 30 ;;
esac
'''


class Out:
    def __init__(self):
        self.events = []

    def progress(self, step, frac, text=""):
        self.events.append(("PROGRESS", step, round(frac, 3), text))

    def log(self, step, text):
        self.events.append(("LOG", step, text))

    def warn(self, step, text):
        self.events.append(("WARN", step, text))


@unittest.skipIf(sys.platform == "win32", "the fake game is a shell script")
class ShadersStepTests(unittest.TestCase):
    @staticmethod
    def read(path):
        with open(path) as f:
            return f.read()

    def make_ctx(self, t, story):
        ctx = type("Ctx", (), {})()
        ctx.out = Out()
        ctx.mac = sys.platform == "darwin"
        ctx.linux = not ctx.mac
        ctx.win = False
        ctx.root = os.path.join(t, "root")
        ctx.app_dir = os.path.join(t, "apps") if ctx.mac else os.path.join(t, "app")
        ctx.app = os.path.join(ctx.app_dir, "Burnout 3 Takedown.app") if ctx.mac else ctx.app_dir
        ctx.game_parent = os.path.join(ctx.root, "Game")
        ctx.logs = os.path.join(t, "logs")
        ctx.shader_cache = os.path.join(t, "cache")
        ctx.env = dict(os.environ, FAKE_SHADERS=story, FAKE_ARGS=os.path.join(t, "args"),
                       FAKE_CACHE=ctx.shader_cache, FAKE_PID=os.path.join(t, "pid"))
        exe, _ = shaders.launcher(ctx)
        os.makedirs(os.path.dirname(exe))
        with open(exe, "w") as f:
            f.write(FAKE)
        os.chmod(exe, 0o755)
        return ctx

    def test_built(self):
        with tempfile.TemporaryDirectory() as t:
            ctx = self.make_ctx(t, "ok")
            kind, text = shaders.run(ctx)
            self.assertEqual(kind, "OK")
            self.assertIn("70 pipelines", text)
            self.assertIn(("PROGRESS", "shaders", 0.25, "race: driving"), ctx.out.events)
            self.assertIn(("LOG", "shaders", "race: done; the list holds 29 vertex, 32 fragment, 53 pipelines"),
                          ctx.out.events)
            # the game's own lines are not repeated as installer events
            self.assertFalse([e for e in ctx.out.events if e[0] == "LOG" and "PLAN" in e[2]])
            args = self.read(os.path.join(t, "args")).split()
            self.assertEqual(args, ["--build-shaders", "--cache-dir", ctx.shader_cache])

    def test_without_a_cache_dir_the_games_own_is_used(self):
        with tempfile.TemporaryDirectory() as t:
            ctx = self.make_ctx(t, "ok")
            ctx.shader_cache = None
            ctx.env["FAKE_CACHE"] = os.path.join(t, "default-cache")
            shaders.run(ctx)
            self.assertEqual(self.read(os.path.join(t, "args")).split(), ["--build-shaders"])

    def test_already_built_is_a_skip(self):
        with tempfile.TemporaryDirectory() as t:
            kind, text = shaders.run(self.make_ctx(t, "built"))
            self.assertEqual(kind, "SKIP")
            self.assertIn("already built", text)

    def test_failures_are_warnings_with_the_game_s_code(self):
        for story, code, words in (("scene-failed", "scene-failed", "lost its way twice"),
                                   ("cache-off", "cache-off", "switched off"),
                                   ("cancelled", "cancelled", "finished scenes are kept")):
            with tempfile.TemporaryDirectory() as t:
                with self.assertRaises(shaders.StepWarning) as cm:
                    shaders.run(self.make_ctx(t, story))
                self.assertEqual(cm.exception.code, code)
                self.assertIn(words, str(cm.exception))

    def test_ending_without_a_word_or_with_an_error(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(shaders.StepWarning) as cm:
                shaders.run(self.make_ctx(t, "silent"))
            self.assertEqual(cm.exception.code, "no-result")
        with tempfile.TemporaryDirectory() as t:
            ctx = self.make_ctx(t, "crash")
            with self.assertRaises(shaders.StepWarning) as cm:
                shaders.run(ctx)
            self.assertEqual(cm.exception.code, "game-failed")
            self.assertTrue([e for e in ctx.out.events if e[0] == "LOG" and "something broke" in e[2]])

    def test_no_installed_game_is_a_real_error(self):
        with tempfile.TemporaryDirectory() as t:
            ctx = self.make_ctx(t, "ok")
            os.remove(shaders.launcher(ctx)[0])
            with self.assertRaises(common.StepError) as cm:
                shaders.run(ctx)
            self.assertEqual(cm.exception.code, "no-package")


@unittest.skipIf(sys.platform == "win32", "the fake game is a shell script")
class ShadersDriverTests(unittest.TestCase):
    """install.py itself: the step is off by default, a failure keeps RESULT OK, and
    being told to stop ends the game too."""

    def driver(self, t, story, *extra, **kw):
        helper = ShadersStepTests()
        ctx = helper.make_ctx(t, story)
        args = [sys.executable, INSTALL, "--root", ctx.root, "--app-dir", ctx.app_dir,
                "--work", os.path.join(t, "work"), "--only", "shaders", "--shader-cache", ctx.shader_cache] + list(extra)
        return ctx, subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ctx.env,
                                     universal_newlines=True)

    def lines(self, p):
        out, err = p.communicate(timeout=30)
        return [l.split(" ", 4) for l in out.splitlines()], err

    def test_built_ends_ok(self):
        with tempfile.TemporaryDirectory() as t:
            ctx, p = self.driver(t, "ok")
            lines, err = self.lines(p)
            self.assertEqual(p.returncode, 0, err)
            kinds = [" ".join(l[:3]) for l in lines]
            self.assertIn("PLAN shaders", " ".join(kinds))
            self.assertTrue([l for l in lines if l[:3] == ["STEP", "shaders", "OK"]])
            self.assertEqual(lines[-1][:2], ["RESULT", "OK"])

    def test_a_failed_scene_is_a_warning_and_the_install_still_ends_ok(self):
        with tempfile.TemporaryDirectory() as t:
            ctx, p = self.driver(t, "scene-failed")
            lines, err = self.lines(p)
            self.assertEqual(p.returncode, 0, err)
            fail = [l for l in lines if l[:3] == ["STEP", "shaders", "FAIL"]]
            self.assertTrue(fail and fail[0][3] == "scene-failed")
            self.assertTrue([l for l in lines if l[0] == "WARN"])
            self.assertEqual(lines[-1][:2], ["RESULT", "OK"])

    def test_not_offered_unless_asked_for(self):
        out = subprocess.run([sys.executable, INSTALL, "--only", "toolchain", "--help"],
                             stdout=subprocess.PIPE, universal_newlines=True).stdout
        self.assertIn("--shaders", out)
        import install
        self.assertNotIn("shaders", install.STEPS)
        self.assertIn("shaders", install.OPTIONAL_STEPS)

    def test_stopping_the_installer_cancels_the_game(self):
        with tempfile.TemporaryDirectory() as t:
            ctx, p = self.driver(t, "hold")
            pid_file = os.path.join(t, "pid")
            for _ in range(100):
                if os.path.exists(pid_file):
                    break
                time.sleep(0.1)
            self.assertTrue(os.path.exists(pid_file), "the fake game did not start")
            game = int(ShadersStepTests.read(pid_file))
            p.send_signal(signal.SIGTERM)
            p.communicate(timeout=20)
            self.assertEqual(p.returncode, 128 + signal.SIGTERM)
            time.sleep(0.5)
            with self.assertRaises(ProcessLookupError):
                os.kill(game, 0)
            self.assertTrue(os.path.exists(os.path.join(ctx.shader_cache, "prebuild", "cancel")))


if __name__ == "__main__":
    unittest.main()
