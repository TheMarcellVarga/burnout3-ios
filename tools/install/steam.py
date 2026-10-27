"""Steam non-Steam-game shortcut for the installer (Linux / Steam Deck).

Steam keeps non-Steam shortcuts in a binary VDF, userdata/<id>/config/shortcuts.vdf,
and rewrites it when it exits, so the file may only be touched while Steam is
not running. The icon and the library art are files in config/grid/ named after
the shortcut's app id.

* binary VDF: 0x00 key\\0 <entries> 0x08 is an object, 0x01 key\\0 value\\0 a string,
  0x02 key\\0 <int32 LE> an integer, and 0x08 ends the object. The file is
  \\0shortcuts\\0 <entries "0", "1", ...> 0x08 0x08.
* app id of a shortcut: crc32(exe + name) | 0x80000000, where exe is the quoted
  path exactly as stored in the Exe field. It is stored in the file as a signed
  int32 and used unsigned in file names (grid art).

Existing entries are never changed: add_shortcut appends one (or reports that
an entry with the same name and exe is already there) and keeps a backup. The
art is made from the user's own title image; nothing is downloaded.

Standard library only (art goes through icons.py).
"""

import glob
import os
import shutil
import struct
import time
import zlib

try:
    import icons
except ImportError:
    from . import icons


class VdfError(Exception):
    pass


# ----------------------------------------------------------------- binary VDF
def parse(data):
    """-> list of (key, value); a value is str, int or a nested list."""
    pos = [0]

    def cstr():
        end = data.index(b"\0", pos[0])
        s = data[pos[0]:end].decode("utf-8", "surrogateescape")
        pos[0] = end + 1
        return s

    def obj():
        items = []
        while True:
            if pos[0] >= len(data):
                raise VdfError("file ends inside an object")
            t = data[pos[0]]
            pos[0] += 1
            if t == 0x08:
                return items
            key = cstr()
            if t == 0x00:
                items.append((key, obj()))
            elif t == 0x01:
                items.append((key, cstr()))
            elif t == 0x02:
                items.append((key, struct.unpack_from("<i", data, pos[0])[0]))
                pos[0] += 4
            else:
                raise VdfError("unknown VDF value type 0x%02X at offset %d" % (t, pos[0] - 1))

    try:
        root = obj()
    except (ValueError, struct.error) as e:
        raise VdfError("malformed shortcuts.vdf: %s" % e)
    if pos[0] != len(data):
        raise VdfError("trailing bytes after the root object")
    return root


def dump(items):
    out = bytearray()

    def put(items):
        for k, v in items:
            kb = k.encode("utf-8", "surrogateescape") + b"\0"
            if isinstance(v, list):
                out.append(0x00)
                out.extend(kb)
                put(v)
            elif isinstance(v, str):
                out.append(0x01)
                out.extend(kb + v.encode("utf-8", "surrogateescape") + b"\0")
            else:
                out.append(0x02)
                out.extend(kb + struct.pack("<i", v))
        out.append(0x08)

    put(items)
    return bytes(out)


# ------------------------------------------------------------------ shortcuts
def app_id(exe_quoted, name):
    """Unsigned 32-bit app id Steam derives for a non-Steam shortcut."""
    return (zlib.crc32((exe_quoted + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def _signed(n):
    return n - (1 << 32) if n >= 1 << 31 else n


def _entries(root):
    for k, v in root:
        if k.lower() == "shortcuts" and isinstance(v, list):
            return v
    return None


def add_shortcut(vdf_path, name, exe, start_dir, icon, launch_options="", tags=("Burnout 3",)):
    """Append a shortcut to shortcuts.vdf (creating the file when absent). Returns
    (app id, added). A backup is made first. If an entry with this name and exe is
    already there nothing is written and added is False. Entries that are there are
    kept as they are; the new one copies its field set from the last existing entry
    so it matches what this Steam version writes."""
    quoted = '"%s"' % exe
    data = open(vdf_path, "rb").read() if os.path.exists(vdf_path) else dump([("shortcuts", [])])
    root = parse(data)
    entries = _entries(root)
    if entries is None:
        raise VdfError("no \"shortcuts\" object in " + vdf_path)
    aid = app_id(quoted, name)
    for _, e in entries:
        if isinstance(e, list):
            d = {k.lower(): v for k, v in e}
            if d.get("appname") == name and d.get("exe") == quoted:
                return aid, False
    new = [("appid", _signed(aid)), ("AppName", name), ("Exe", quoted), ("StartDir", start_dir),
           ("icon", icon), ("ShortcutPath", ""), ("LaunchOptions", launch_options),
           ("IsHidden", 0), ("AllowDesktopConfig", 1), ("AllowOverlay", 1), ("OpenVR", 0),
           ("Devkit", 0), ("DevkitGameID", ""), ("DevkitOverrideAppID", 0), ("LastPlayTime", 0),
           ("FlatpakAppID", ""), ("tags", [(str(i), t) for i, t in enumerate(tags)])]
    if entries:                                   # follow the existing field set and case
        last = entries[-1][1]
        if isinstance(last, list):
            have = {k.lower(): k for k, _ in last}
            order = [k for k, _ in last]
            vals = {k.lower(): (k, v) for k, v in new}
            new = [(have[k.lower()], vals[k.lower()][1]) if k.lower() in vals else (k, _default(v))
                   for k, v in last]
            del order
    idx = 0
    taken = set(k for k, _ in entries)
    while str(idx) in taken:
        idx += 1
    entries.append((str(idx), new))
    if os.path.exists(vdf_path):
        shutil.copy2(vdf_path, "%s.bo3-backup-%s" % (vdf_path, time.strftime("%Y%m%d-%H%M%S")))
    tmp = vdf_path + ".bo3-tmp"
    with open(tmp, "wb") as f:
        f.write(dump(root))
    os.replace(tmp, vdf_path)
    return aid, True


def _default(v):
    return [] if isinstance(v, list) else (0 if isinstance(v, int) else "")


def steam_running():
    """True when a Steam client process is up (it would overwrite the file on exit)."""
    import subprocess
    for pat in ("(^|/)steam( |$)", "ubuntu12_32/steam( |$)", "steamwebhelper"):
        if subprocess.run(["pgrep", "-f", pat], stdout=subprocess.DEVNULL).returncode == 0:
            return True
    return False


STEAMID64_BASE = 76561197960265728


def parse_text_vdf(text):
    """Steam's text VDF ("key" "value" and "key" { ... }) -> nested dicts."""
    import re
    toks = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    pos = [0]

    def obj():
        d = {}
        while pos[0] < len(toks):
            q, brace = toks[pos[0]]
            pos[0] += 1
            if brace == "}":
                return d
            key = q
            if pos[0] >= len(toks):
                break
            q2, brace2 = toks[pos[0]]
            pos[0] += 1
            d[key] = obj() if brace2 == "{" else q2
        return d

    return obj()


def most_recent_user(loginusers_path):
    """Account id (the userdata folder name, a string) of the user who logged in
    last according to loginusers.vdf: MostRecent = 1, else the highest Timestamp.
    None when the file is missing, unreadable, or cannot decide."""
    try:
        with open(loginusers_path, encoding="utf-8", errors="replace") as f:
            users = parse_text_vdf(f.read()).get("users") or {}
    except OSError:
        return None
    ranked = []
    for sid, v in users.items():
        if not isinstance(v, dict) or not sid.isdigit() or int(sid) <= STEAMID64_BASE:
            continue
        try:
            ts = int(v.get("Timestamp", "0"))
        except ValueError:
            ts = 0
        ranked.append(((1 if v.get("MostRecent") == "1" else 0, ts), str(int(sid) - STEAMID64_BASE)))
    ranked.sort(reverse=True)
    if not ranked or ranked[0][0] == (0, 0):
        return None
    if len(ranked) > 1 and ranked[1][0] == ranked[0][0]:
        return None                                   # a tie at the top cannot decide
    return ranked[0][1]


def userdata_configs(home=None):
    """config dirs of every Steam user found: [(user id, config path, steam root)].
    Native Steam and Flatpak."""
    home = home or os.path.expanduser("~")
    found = []
    for base in (".local/share/Steam", ".steam/steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam",
                 "Library/Application Support/Steam"):
        for d in sorted(glob.glob(os.path.join(home, base, "userdata", "*", "config"))):
            uid = os.path.basename(os.path.dirname(d))
            real = os.path.realpath(d)
            if uid != "0" and real not in [os.path.realpath(p) for _, p, _ in found]:
                found.append((uid, d, os.path.join(home, base)))
    return found


def pick_user(users):
    """Choose among userdata_configs() entries: the only one, or the most recently
    logged-in per the Steam root's config/loginusers.vdf. Returns (entry, why) or
    (None, reason)."""
    if len(users) == 1:
        return users[0], "the only Steam user"
    if not users:
        return None, "no Steam user data found"
    recent = most_recent_user(os.path.join(users[0][2], "config", "loginusers.vdf"))
    if recent is None:
        return None, "loginusers.vdf does not say who logged in last"
    for u in users:
        if u[0] == recent:
            return u, "most recently logged in (loginusers.vdf)"
    return None, "the most recent user (%s) has no userdata folder" % recent


# ------------------------------------------------------------------------ art
def _canvas(w, h, logo, logo_size):
    """The logo, scaled to logo_size, centred on opaque black w x h."""
    lw = logo[0]
    rgba = icons.resize(logo[2], lw, lw, logo_size, logo_size) if logo_size != lw else logo[2]
    row0 = bytearray(b"\x00\x00\x00\xff" * w)
    out = bytearray()
    ox, oy = (w - logo_size) // 2, (h - logo_size) // 2
    for y in range(h):
        if oy <= y < oy + logo_size:
            r = bytearray(row0)
            src = rgba[(y - oy) * logo_size * 4:(y - oy + 1) * logo_size * 4]
            r[ox * 4:(ox + logo_size) * 4] = src
            out += r
        else:
            out += row0
    return bytes(out)


def make_art(xbe, grid_dir, aid):
    """Write the library art for shortcut `aid` into grid_dir from the XBE's title
    image: <id>_icon.png (256), <id>p.png (600x900 capsule), <id>.png (920x430
    wide capsule), <id>_hero.png (1920x620). The title image is a logo on black,
    so the capsules are that logo on black; they are placeholders for art the
    user may replace in Steam. Returns the paths."""
    section = xbe.section("$$XTIMAGE")
    if section is None:
        raise icons.IconError("the XBE has no $$XTIMAGE section")
    logo = icons.decode_xpr(section)
    os.makedirs(grid_dir, exist_ok=True)
    paths = {}
    specs = (("icon", "%d_icon.png" % aid, 256, 256, 256), ("portrait", "%dp.png" % aid, 600, 900, 480),
             ("wide", "%d.png" % aid, 920, 430, 400), ("hero", "%d_hero.png" % aid, 1920, 620, 600))
    for kind, name, w, h, size in specs:
        p = os.path.join(grid_dir, name)
        with open(p, "wb") as f:
            f.write(icons.png_bytes(_canvas(w, h, logo, size), w, h))
        paths[kind] = p
    return paths
