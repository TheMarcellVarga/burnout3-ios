"""Make a macOS executable self-contained: copy the non-system dynamic libraries
it needs (and theirs, recursively) into <app>/Contents/Frameworks, rewrite the
install names to @rpath, and sign everything ad hoc. Standard library plus the
Command Line Tools (otool, install_name_tool, codesign).

What counts as system: /System/*, /usr/lib/*. Everything else (Homebrew, MacPorts)
is copied.

One library is loaded by name at run time instead of linked: sdl2-compat (the
brew "sdl2" formula) dlopens libSDL3.dylib from @loader_path or @executable_path
(its strings say so). `extra` names such libraries to bundle under a given file
name; the installer passes SDL3 when it sees sdl2-compat.
"""

import os
import re
import shutil
import subprocess

SYSTEM_PREFIXES = ("/System/", "/usr/lib/")
EXE_RPATH = "@executable_path/../Frameworks"
LIB_RPATH = "@loader_path"


class BundleError(Exception):
    pass


def _run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    if r.returncode != 0:
        raise BundleError("%s failed: %s" % (" ".join(cmd[:2]), r.stdout.strip()[-400:]))
    return r.stdout


def parse_otool_l(text):
    """Dependencies from `otool -L` output: [install name], first line (the
    file's own name, or its id for a dylib) skipped."""
    deps = []
    for line in text.splitlines()[1:]:
        m = re.match(r"^\s+(\S.*?) \(compatibility version", line)
        if m:
            deps.append(m.group(1))
    return deps


def dylib_id(path):
    out = _run(["otool", "-D", path]).splitlines()
    return out[1].strip() if len(out) > 1 else None


def rpaths(path):
    out = _run(["otool", "-l", path]).splitlines()
    res = []
    for i, line in enumerate(out):
        if line.strip() == "cmd LC_RPATH":
            m = re.search(r"path (.+) \(offset", out[i + 2])
            if m:
                res.append(m.group(1))
    return res


def is_system(name):
    return name.startswith(SYSTEM_PREFIXES)


def resolve(name, referrer, referrer_rpaths):
    """The real file an install name refers to, or None."""
    if name.startswith("@rpath/"):
        rest = name[len("@rpath/"):]
        cands = [os.path.join(r.replace("@loader_path", os.path.dirname(referrer))
                              .replace("@executable_path", os.path.dirname(referrer)), rest)
                 for r in referrer_rpaths]
    elif name.startswith("@loader_path/"):
        cands = [os.path.join(os.path.dirname(referrer), name[len("@loader_path/"):])]
    elif name.startswith("@executable_path/"):
        cands = [os.path.join(os.path.dirname(referrer), name[len("@executable_path/"):])]
    else:
        cands = [name]
    for c in cands:
        if os.path.exists(c):
            return os.path.realpath(c)
    return None


def bundle(exe, frameworks, extra=None, log=lambda s: None):
    """Bundle `exe` (already inside the app) against `frameworks`. `extra` is
    {file name: source path} for libraries loaded by dlopen. Returns the list of
    bundled file names. Does not sign."""
    os.makedirs(frameworks, exist_ok=True)
    done = {}                           # source realpath -> bundled file name
    names = set()
    queue = [(exe, True)]               # (file in the bundle, is the executable)
    # Libraries first copied from `extra` (no referrer to rewrite).
    for name, src in (extra or {}).items():
        dest = os.path.join(frameworks, name)
        shutil.copy2(os.path.realpath(src), dest)
        os.chmod(dest, 0o755)
        done[os.path.realpath(src)] = name
        names.add(name)
        queue.append((dest, False))
        _run(["install_name_tool", "-id", "@rpath/" + name, dest])
    while queue:
        path, is_exe = queue.pop()
        own_rpaths = rpaths(path)
        own_id = None if is_exe else dylib_id(path)
        for dep in parse_otool_l(_run(["otool", "-L", path])):
            if is_system(dep) or dep == own_id:
                continue
            src = resolve(dep, path, own_rpaths)
            if src is None:
                if dep.startswith(("@rpath/", "@loader_path/", "@executable_path/")) \
                        and os.path.exists(os.path.join(frameworks, os.path.basename(dep))):
                    src = os.path.realpath(os.path.join(frameworks, os.path.basename(dep)))
                else:
                    raise BundleError("%s needs %s, which cannot be found" % (os.path.basename(path), dep))
            if src.startswith(SYSTEM_PREFIXES):
                continue
            if os.path.realpath(path) == src:
                continue
            name = done.get(src)
            if name is None:
                name = os.path.basename(dep)
                if name in names:                       # same name from another place
                    raise BundleError("two different libraries are both called " + name)
                dest = os.path.join(frameworks, name)
                shutil.copy2(src, dest)
                os.chmod(dest, 0o755)
                _run(["install_name_tool", "-id", "@rpath/" + name, dest])
                done[src] = name
                names.add(name)
                queue.append((dest, False))
                log("bundled " + name + " from " + src)
            if dep != "@rpath/" + name:
                _run(["install_name_tool", "-change", dep, "@rpath/" + name, path])
        want = EXE_RPATH if is_exe else LIB_RPATH
        if want not in own_rpaths:
            _run(["install_name_tool", "-add_rpath", want, path])
        # an rpath that points outside the bundle (Homebrew's, the build tree's)
        for r in own_rpaths:
            if r != want and not r.startswith("@"):
                _run(["install_name_tool", "-delete_rpath", r, path])
    return sorted(names)


def sign(app, frameworks):
    """Ad hoc signature, libraries first (a changed install name voids the old one)."""
    for n in sorted(os.listdir(frameworks)):
        _run(["codesign", "--force", "--sign", "-", os.path.join(frameworks, n)])
    _run(["codesign", "--force", "--deep", "--sign", "-", app])
    _run(["codesign", "--verify", "--deep", "--strict", app])


def audit(files):
    """Every non-system dependency of `files` that is not @rpath/@loader_path/
    @executable_path: [(file, dependency)]. Empty means self-contained."""
    bad = []
    for f in files:
        for dep in parse_otool_l(_run(["otool", "-L", f])):
            if not (is_system(dep) or dep.startswith(("@rpath/", "@loader_path/", "@executable_path/"))):
                bad.append((f, dep))
    return bad
