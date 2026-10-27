"""Helpers shared by the installer driver and its platform backends: the step
error type, running tools with their output going to a log file, and the Python
(with capstone) the recompiler needs."""

import os
import shutil
import subprocess
import sys
import time

EXIT_FAIL, EXIT_USAGE, EXIT_TOOLCHAIN, EXIT_DISC = 1, 2, 3, 4


class StepError(Exception):
    def __init__(self, code, message, exit_code=EXIT_FAIL):
        Exception.__init__(self, message)
        self.code = code
        self.exit_code = exit_code


# ----------------------------------------------------------------- locations
def nearest_existing(path):
    """The path itself, or its closest parent that exists (a folder that will be
    created later is measured through where it will be created)."""
    p = os.path.abspath(path)
    while not os.path.exists(p):
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    return p


def check_location(path, need_gb=0.0):
    """(ok, detail) for a folder the installer will write to: it, or the nearest
    existing parent, must be a writable folder with `need_gb` free. Never raises."""
    base = nearest_existing(path)
    try:
        if not os.path.isdir(base):
            return False, "%s is not a folder (needed for %s)" % (base, path)
        if not os.access(base, os.W_OK | os.X_OK):
            return False, "cannot write to %s (needed to create %s)" % (base, path)
        free = shutil.disk_usage(base).free / 1e9
    except OSError as e:
        return False, "cannot use %s: %s" % (path, e)
    detail = "%.0f GB free for %s" % (free, path)
    return free >= need_gb, detail


# ------------------------------------------------------------ running tools
def run(ctx, step, cmd, cwd=None, env=None, on_line=None, nice=True, tee=None):
    """Run a tool, streaming its output to <logs>/<step>.log (and to on_line).
    Returns the exit status; on failure the log's tail is sent as LOG lines."""
    os.makedirs(ctx.logs, exist_ok=True)
    log_path = os.path.join(ctx.logs, step + ".log")
    full = list(cmd)
    if nice and ctx.nice and os.name == "posix":
        full = ["nice", "-n", str(ctx.nice)] + full
    tail = []
    tee_f = open(tee, "wb") if tee else None
    with open(log_path, "ab") as log:
        log.write(("\n==== %s: %s\n" % (time.strftime("%F %T"), " ".join(full))).encode())
        p = subprocess.Popen(full, cwd=cwd, env=env or ctx.env, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
        buf = b""
        while True:
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            log.write(chunk)
            if tee_f:
                tee_f.write(chunk)
            buf += chunk.replace(b"\r", b"\n")
            *lines, buf = buf.split(b"\n")
            for raw in lines:
                line = raw.decode("utf-8", "replace").rstrip()
                if not line:
                    continue
                tail = (tail + [line])[-15:]
                if on_line:
                    on_line(line)
        rc = p.wait()
    if tee_f:
        tee_f.close()
    if rc != 0:
        for line in tail:
            ctx.out.log(step, line)
        ctx.out.log(step, "full log: " + log_path)
    return rc


def capture(cmd, **kw):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                           timeout=60, **kw)
        return r.returncode, r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, str(e)


def python_for_regen(ctx, py=None):
    """The interpreter regen.sh will use: <work>/.venv/bin/python3 when there is
    one (regen.sh's own rule), else python3 from PATH, which this points at `py`
    (--python, the private venv, or this interpreter) with a shim."""
    venv = os.path.join(ctx.work, ".venv", "bin", "python3")
    if os.path.exists(venv):
        return venv
    if sys.platform == "win32":
        return py or ctx.python or sys.executable
    private = os.path.join(ctx.inst, "venv", "bin", "python3")
    py = (py or getattr(ctx, "py_shim", None) or (private if os.path.exists(private) else None)
          or ctx.python or sys.executable)
    shim_dir = os.path.join(ctx.inst, "bin")
    os.makedirs(shim_dir, exist_ok=True)
    shim = os.path.join(shim_dir, "python3")
    with open(shim, "w") as f:
        f.write('#!/bin/sh\nexec "%s" "$@"\n' % py)
    os.chmod(shim, 0o755)
    if shim_dir not in ctx.env.get("PATH", "").split(os.pathsep):
        ctx.env["PATH"] = shim_dir + os.pathsep + ctx.env.get("PATH", "")
    ctx.py_shim = py
    return py


def python_info(py):
    """(version tuple or None, has capstone) of an interpreter."""
    rc, v = capture([py, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
    if rc != 0:
        return None, False
    ver = tuple(int(x) for x in v.splitlines()[-1].split("."))
    return ver, capture([py, "-c", "import capstone"])[0] == 0


def ensure_capstone(ctx, py):
    """Return an interpreter that has capstone, installing it when it is missing
    (unless --no-pip): into <work>/.venv if that is where regen.sh looks, else
    into a private venv at <root>/install/venv. pip needs the network; its output
    is in logs/toolchain.log. Returns (python, note)."""
    ver, has = python_info(py)
    if ver is None:
        raise StepError("python-missing", "cannot run " + py, EXIT_TOOLCHAIN)
    if ver < (3, 10):
        raise StepError("python-too-old", "%s is Python %d.%d; the recompiler needs 3.10 or newer "
                        "(brew install python, then --python <it>)" % (py, ver[0], ver[1]), EXIT_TOOLCHAIN)
    if has:
        return py, "capstone present"
    if ctx.no_pip:
        raise StepError("missing-capstone", "python-capstone is missing (--no-pip given)", EXIT_TOOLCHAIN)
    venv_py = os.path.join(ctx.work, ".venv", "bin", "python3")
    if os.path.exists(venv_py):
        target = venv_py                                  # the venv regen.sh uses
    else:
        venv_dir = os.path.join(ctx.inst, "venv")
        target = os.path.join(venv_dir, "bin", "python3")
        if not os.path.exists(target):
            ctx.out.log("toolchain", "creating a private Python environment in " + venv_dir)
            if run(ctx, "toolchain", [py, "-m", "venv", venv_dir], nice=False) != 0:
                raise StepError("venv-failed", "could not create " + venv_dir, EXIT_TOOLCHAIN)
    ctx.out.log("toolchain", "installing capstone with pip (network) into " + target)
    if run(ctx, "toolchain", [target, "-m", "pip", "install", "--disable-pip-version-check", "capstone"],
           nice=False) != 0 or not python_info(target)[1]:
        raise StepError("pip-failed", "pip could not install capstone; see " +
                        os.path.join(ctx.logs, "toolchain.log"), EXIT_TOOLCHAIN)
    return target, "capstone installed into " + target


