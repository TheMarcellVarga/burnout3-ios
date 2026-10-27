// The Steam "add to library" step (Linux, Steam Deck): a non-Steam shortcut in
// userdata/<id>/config/shortcuts.vdf. tools/install/steam.py in C++, with its rules:
//
//  * existing entries are never changed: one is appended (with the field set and
//    the key spelling of the last existing entry, so it matches what this Steam
//    writes), or nothing is written when an entry with the same Exe is there
//    (whatever its name: Steam's own "Add to Steam" names it after the file);
//  * the file is copied to shortcuts.vdf.takedawn-backup-<time> first and replaced
//    through a temporary file;
//  * never while Steam runs (it rewrites the file when it exits): SteamRunning(), which
//    looks at the processes' names, never at their arguments. On a
//    Steam Deck Steam always runs, so the setup window asks, closes it with
//    `steam -shutdown`, waits until it is gone, writes, and starts it again
//    (SteamCommand()); not while a game started from Steam runs (SteamGameRunning());
//  * with several Steam users, the one who logged in last per loginusers.vdf, and
//    no guess when that cannot decide.
//
// Binary VDF: 0x00 key\0 <entries> 0x08 is an object, 0x01 key\0 value\0 a string,
// 0x02 key\0 <int32 LE> an integer; the file is \0shortcuts\0 <"0", "1", ...> 0x08 0x08.
// App id of a shortcut: crc32(exe + name) | 0x80000000, exe being the quoted path as
// stored in the Exe field; stored as a signed int32, used unsigned in the art's names.
//
// Standard C++ only (no Qt), so the tests run it on files they make themselves.
#pragma once

#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace steam {

struct VdfError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

struct Node {
  enum Type { Object = 0, String = 1, Int = 2 };
  std::string key;
  Type type = String;
  std::string text;         // String
  int32_t number = 0;       // Int
  std::vector<Node> items;  // Object
  bool operator==(const Node& o) const {
    return key == o.key && type == o.type && text == o.text && number == o.number && items == o.items;
  }
};

// The root object's entries. Throws VdfError on anything that is not a whole file.
std::vector<Node> Parse(const std::string& data);
std::string Dump(const std::vector<Node>& root);

uint32_t AppId(const std::string& exe_quoted, const std::string& name);

struct Added {
  uint32_t app_id = 0;
  bool added = false;  // false: an entry with this Exe was already there (app_id is its)
  std::string backup;  // the copy made before writing ("" when there was no file)
};
// Appends the shortcut (creating the file when there is none). Throws VdfError
// (a file that is not a shortcuts.vdf: nothing is written) or std::runtime_error (I/O).
Added AddShortcut(const std::string& vdf_path, const std::string& name, const std::string& exe,
                  const std::string& start_dir, const std::string& icon, const std::string& launch_options = "",
                  const std::vector<std::string>& tags = {"Takedawn"});

struct Found {
  std::string name;  // AppName
  std::string exe;   // Exe, as stored (quoted)
  uint32_t app_id = 0;
};
// The entries of the shortcuts.vdf at `vdf_path` that start Takedawn: an AppName of
// "Takedawn" or an Exe whose file name begins with "takedawn" (ours, or Steam's own
// "Add to Steam", which names the entry after the file). Reads only; an empty list when
// there is no file. Throws VdfError for a file that is not a shortcuts.vdf.
std::vector<Found> FindTakedawn(const std::string& vdf_path);

// A process is a Steam client by what it is, never by its arguments: its name
// (/proc/<pid>/comm, 15 characters at most) or the file it runs (basename of
// /proc/<pid>/exe) is `steam` (the client, or the `steam` / `steam.sh` wrapper script,
// whose comm is the script's name) or `steamwebhelper`. A shell, a `tail -f .../steam`
// or a grep that only has those words in its command line is not one. `exe_name` may be ""
// (unreadable, as for another user's or a sandboxed process).
bool IsSteamProcess(const std::string& comm, const std::string& exe_name);
// A Steam client is running: a process of `proc_dir` (/proc) that IsSteamProcess(), not a
// zombie (a Steam that exited and is not yet reaped), and not one of `ignore_pids`.
// False where there is no `proc_dir`.
bool SteamRunningIn(const std::string& proc_dir, const std::vector<int>& ignore_pids = {});
// The same, in /proc, ignoring this process and its parent (the setup window and whatever
// started it, a terminal command line included).
bool SteamRunning();
// A game or program that Steam started is running: a `reaper` process (comm) whose
// arguments begin with `SteamLaunch`. Same rules as SteamRunningIn().
bool SteamGameRunningIn(const std::string& proc_dir, const std::vector<int>& ignore_pids = {});
bool SteamGameRunning();
// The command that talks to a Steam client (append "-shutdown" to close it, nothing to
// start it): `steam`, or Flatpak's when `steam_root` (User::root) is the Flatpak's.
std::vector<std::string> SteamCommand(const std::string& steam_root);
// The file the shortcut starts: the stable name ~/Applications/Takedawn.AppImage when it
// is there (the path survives updates), else the running AppImage, else `program`.
std::string ShortcutExe(const std::string& home, const std::string& appimage, const std::string& program);

// The userdata folder name of the user who logged in last per loginusers.vdf:
// MostRecent = 1, else the highest Timestamp. "" when the file is missing or cannot decide.
std::string MostRecentUser(const std::string& loginusers_path);

struct User {
  std::string id;      // the userdata folder's name
  std::string config;  // .../userdata/<id>/config
  std::string root;    // the Steam folder it was found in
};
// Every Steam user found under `home` (native Steam and Flatpak).
std::vector<User> UserdataConfigs(const std::string& home);
// The only one, or the most recently logged in. `why` says which rule chose, or why none.
bool PickUser(const std::vector<User>& users, User* chosen, std::string* why);

}  // namespace steam
