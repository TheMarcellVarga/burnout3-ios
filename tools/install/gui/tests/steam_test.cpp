// The Steam shortcut writer (steam_shortcut.cpp) on files made here: the cases of
// the Python it replaced (tools/install/tests/test_install.py, SteamTests), plus the
// process rules of "Steam is running" (fake /proc folders) and the search for the users' folders.
// No real Steam configuration is read or written: everything is in a temporary folder.
#include <QtTest>

#include <filesystem>
#include <fstream>

#include "steam_shortcut.h"

namespace fs = std::filesystem;
using steam::Node;

namespace {

Node Str(const std::string& k, const std::string& v) { Node n; n.key = k; n.type = Node::String; n.text = v; return n; }
Node Num(const std::string& k, int32_t v) { Node n; n.key = k; n.type = Node::Int; n.number = v; return n; }
Node Obj(const std::string& k, std::vector<Node> items) {
  Node n; n.key = k; n.type = Node::Object; n.items = std::move(items); return n;
}

// The synthetic file of the Python tests: n entries with the fields an older Steam writes.
std::string SyntheticVdf(int n) {
  std::vector<Node> entries;
  for (int i = 0; i < n; ++i) {
    const std::string s = std::to_string(i);
    entries.push_back(Obj(s, {Num("appid", -1000 - i), Str("AppName", "Game " + s), Str("Exe", "\"/g/" + s + ".sh\""),
                              Str("StartDir", "/g"), Str("icon", ""), Str("ShortcutPath", ""),
                              Str("LaunchOptions", "%command%"), Num("IsHidden", 0), Obj("tags", {Str("0", "x")})}));
  }
  return steam::Dump({Obj("shortcuts", entries)});
}

void Write(const fs::path& p, const std::string& data) {
  fs::create_directories(p.parent_path());
  std::ofstream f(p, std::ios::binary | std::ios::trunc);
  f.write(data.data(), std::streamsize(data.size()));
}
std::string Read(const fs::path& p) {
  std::ifstream f(p, std::ios::binary);
  return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}
std::vector<Node> EntriesOf(const fs::path& p) { return steam::Parse(Read(p)).at(0).items; }
const Node* Field(const Node& entry, const std::string& key) {
  for (const Node& f : entry.items) if (f.key == key) return &f;
  return nullptr;
}

struct LoginUser { unsigned id; std::vector<std::pair<std::string, std::string>> keys; };
fs::path LoginFile(const fs::path& dir, const std::vector<LoginUser>& users) {
  std::string body;
  for (const LoginUser& u : users) {
    body += "\t\"" + std::to_string(76561197960265728ULL + u.id) + "\"\n\t{\n\t\t\"AccountName\"\t\t\"a\"\n";
    for (const auto& kv : u.keys) body += "\t\t\"" + kv.first + "\"\t\t\"" + kv.second + "\"\n";
    body += "\t}\n";
  }
  const fs::path p = dir / "loginusers.vdf";
  Write(p, "\"users\"\n{\n" + body + "}\n");
  return p;
}

// A fake /proc/<pid>: comm, stat (state `S`, `Z` for a zombie), cmdline (arguments joined
// by NUL) and, when `exe` is not empty, the exe link.
void FakeProc(const fs::path& proc, int pid, const std::string& comm, const std::vector<std::string>& args,
              const std::string& exe = "", char state = 'S') {
  const fs::path d = proc / std::to_string(pid);
  Write(d / "comm", comm + "\n");
  Write(d / "stat", std::to_string(pid) + " (" + comm + ") " + state + " 1 1 1 0 -1 4194560 0 0 0 0\n");
  std::string cmd;
  for (const std::string& a : args) cmd += a + '\0';
  Write(d / "cmdline", cmd);
  if (!exe.empty()) fs::create_symlink(exe, d / "exe");
}

}  // namespace

class SteamTest : public QObject {
  Q_OBJECT
 private slots:
  void vdfRoundTripIsExact() {
    const std::string d = SyntheticVdf(3);
    QCOMPARE(steam::Dump(steam::Parse(d)), d);
    QVERIFY_EXCEPTION_THROWN(steam::Parse(d.substr(0, d.size() - 3)), steam::VdfError);
    QVERIFY_EXCEPTION_THROWN(steam::Parse(d + "x"), steam::VdfError);
    std::string bad = d;
    bad[bad.find('\x02')] = '\x05';  // a value type that does not exist
    QVERIFY_EXCEPTION_THROWN(steam::Parse(bad), steam::VdfError);
  }

  void appIdIsSteams() {
    // crc32("123456789") is 0xCBF43926: the standard check value, with the top bit set.
    QCOMPARE(steam::AppId("12345", "6789"), 0xCBF43926u | 0x80000000u);
    QVERIFY(steam::AppId("\"/app/Takedawn.AppImage\"", "Takedawn") >= 0x80000000u);
    QVERIFY(steam::AppId("\"/a\"", "Takedawn") != steam::AppId("\"/b\"", "Takedawn"));
  }

  void addKeepsExistingEntriesAndIsIdempotent() {
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "shortcuts.vdf";
    Write(p, SyntheticVdf(2));
    const std::vector<Node> before = EntriesOf(p);
    const steam::Added a = steam::AddShortcut(p.string(), "Takedawn", "/app/Takedawn.AppImage", "/app", "/art/icon.png");
    QVERIFY(a.added);
    QCOMPARE(a.app_id, steam::AppId("\"/app/Takedawn.AppImage\"", "Takedawn"));
    const std::vector<Node> after = EntriesOf(p);
    QCOMPARE(after.size(), size_t(3));
    QVERIFY(after[0] == before[0] && after[1] == before[1]);  // untouched
    const Node& mine = after[2];
    QCOMPARE(mine.key, std::string("2"));
    QCOMPARE(Field(mine, "AppName")->text, std::string("Takedawn"));
    QCOMPARE(Field(mine, "Exe")->text, std::string("\"/app/Takedawn.AppImage\""));
    QCOMPARE(Field(mine, "icon")->text, std::string("/art/icon.png"));
    QCOMPARE(uint32_t(Field(mine, "appid")->number), a.app_id);
    // the same fields, in the same order, as the entry before it
    QCOMPARE(mine.items.size(), before[1].items.size());
    for (size_t i = 0; i < mine.items.size(); ++i) {
      QCOMPARE(mine.items[i].key, before[1].items[i].key);
      QCOMPARE(int(mine.items[i].type), int(before[1].items[i].type));
    }
    // one backup, holding the file as it was
    QVERIFY(!a.backup.empty());
    QCOMPARE(Read(a.backup), SyntheticVdf(2));
    int backups = 0;
    for (const auto& e : fs::directory_iterator(p.parent_path()))
      if (e.path().filename().string().find("backup") != std::string::npos) ++backups;
    QCOMPARE(backups, 1);
    QVERIFY(!fs::exists(p.string() + ".takedawn-tmp"));
    // a second time: nothing is written
    const std::string bytes = Read(p);
    const steam::Added again = steam::AddShortcut(p.string(), "Takedawn", "/app/Takedawn.AppImage", "/app", "x");
    QVERIFY(!again.added);
    QCOMPARE(again.app_id, a.app_id);
    QCOMPARE(Read(p), bytes);
  }

  void keepsAnotherSteamsKeySpellingAndUnknownFields() {
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "shortcuts.vdf";
    Write(p, steam::Dump({Obj("Shortcuts", {Obj("7", {Num("AppId", 5), Str("appname", "Other"), Str("exe", "\"/o\""),
                                                    Str("Future", "x"), Num("FutureNumber", 9),
                                                    Obj("Tags", {})})})}));
    QVERIFY(steam::AddShortcut(p.string(), "Takedawn", "/t", "/", "").added);
    const std::vector<Node> after = EntriesOf(p);
    QCOMPARE(after.size(), size_t(2));
    QCOMPARE(after[1].key, std::string("0"));  // the first free index
    QCOMPARE(Field(after[1], "appname")->text, std::string("Takedawn"));
    QCOMPARE(Field(after[1], "Future")->text, std::string(""));
    QCOMPARE(Field(after[1], "FutureNumber")->number, 0);
    QCOMPARE(Field(after[1], "Tags")->items.size(), size_t(1));
  }

  void createsTheFileWhenThereIsNone() {
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "config" / "shortcuts.vdf";
    const steam::Added a = steam::AddShortcut(p.string(), "G", "/x.sh", "/", "");
    QVERIFY(a.added);
    QVERIFY(a.backup.empty());
    QCOMPARE(EntriesOf(p).size(), size_t(1));
  }

  void refusesAFileThatIsNotOne() {
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "shortcuts.vdf";
    Write(p, "not a vdf");
    QVERIFY_EXCEPTION_THROWN(steam::AddShortcut(p.string(), "G", "/x", "/", ""), steam::VdfError);
    QCOMPARE(Read(p), std::string("not a vdf"));  // untouched, no backup needed
    Write(p, steam::Dump({Obj("something", {})}));
    QVERIFY_EXCEPTION_THROWN(steam::AddShortcut(p.string(), "G", "/x", "/", ""), steam::VdfError);
  }

  void mostRecentUser() {
    QTemporaryDir t;
    const fs::path d = t.path().toStdString();
    // MostRecent wins over a later Timestamp
    QCOMPARE(steam::MostRecentUser(LoginFile(d, {{11, {{"MostRecent", "0"}, {"Timestamp", "900"}}},
                                                 {22, {{"MostRecent", "1"}, {"Timestamp", "100"}}}}).string()),
             std::string("22"));
    // no MostRecent (newer Steam): the highest Timestamp
    QCOMPARE(steam::MostRecentUser(LoginFile(d, {{11, {{"Timestamp", "900"}}}, {22, {{"Timestamp", "100"}}}}).string()),
             std::string("11"));
    // cannot decide: a tie, no timestamps, a missing file
    QCOMPARE(steam::MostRecentUser(LoginFile(d, {{11, {{"Timestamp", "5"}}}, {22, {{"Timestamp", "5"}}}}).string()),
             std::string());
    QCOMPARE(steam::MostRecentUser(LoginFile(d, {{11, {}}, {22, {}}}).string()), std::string());
    QCOMPARE(steam::MostRecentUser((d / "nope").string()), std::string());
  }

  void pickUser() {
    QTemporaryDir t;
    const fs::path root = t.path().toStdString();
    LoginFile(root / "config", {{11, {{"Timestamp", "1"}}}, {22, {{"Timestamp", "2"}}}});
    const std::vector<steam::User> users{{"11", "/s/userdata/11/config", root.string()},
                                         {"22", "/s/userdata/22/config", root.string()}};
    steam::User u;
    std::string why;
    QVERIFY(steam::PickUser(users, &u, &why));
    QCOMPARE(u.id, std::string("22"));
    QVERIFY(steam::PickUser({users[0]}, &u, &why));
    QCOMPARE(u.id, std::string("11"));
    QVERIFY(!steam::PickUser({users[0], {"33", "/x", root.string()}}, &u, &why));  // 22 has no folder
    QVERIFY(!steam::PickUser({}, &u, &why));
  }

  void findsUsersUnderAHome() {
    QTemporaryDir t;
    const fs::path home = t.path().toStdString();
    fs::create_directories(home / ".local/share/Steam/userdata/123/config");
    fs::create_directories(home / ".local/share/Steam/userdata/0/config");       // Steam's own, never a user
    fs::create_directories(home / ".local/share/Steam/userdata/456");             // no config: not yet a user
    fs::create_directories(home / ".var/app/com.valvesoftware.Steam/.local/share/Steam/userdata/789/config");
    fs::create_directories(home / ".steam");
    fs::create_directory_symlink(home / ".local/share/Steam", home / ".steam/steam");  // the usual link: not twice
    const std::vector<steam::User> users = steam::UserdataConfigs(home.string());
    QCOMPARE(users.size(), size_t(2));
    QCOMPARE(users[0].id, std::string("123"));
    QCOMPARE(users[1].id, std::string("789"));
    QVERIFY(steam::UserdataConfigs((home / "nobody").string()).empty());
  }

  void sameExeIsTheSameShortcutWhateverItsName() {
    // Steam's own "Add to Steam" names the entry after the file: no second one beside it.
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "shortcuts.vdf";
    Write(p, steam::Dump({Obj("shortcuts", {Obj("0", {Num("appid", -123456), Str("AppName", "Takedawn.AppImage"),
                                                     Str("Exe", "\"/home/deck/Applications/Takedawn.AppImage\""),
                                                     Str("StartDir", "/home/deck/Applications"), Str("icon", ""),
                                                     Str("LaunchOptions", "")}),
                                              Obj("1", {Num("appid", -5), Str("AppName", "Takedawn"),
                                                        Str("Exe", "\"/elsewhere/Takedawn.AppImage\"")})})}));
    const std::string before = Read(p);
    const steam::Added a = steam::AddShortcut(p.string(), "Takedawn", "/home/deck/Applications/Takedawn.AppImage",
                                              "/home/deck/Applications", "x");
    QVERIFY(!a.added);
    QCOMPARE(a.app_id, uint32_t(-123456));  // the existing entry's id, so its art is found
    QCOMPARE(Read(p), before);
    // another exe with the same name is another shortcut
    QVERIFY(steam::AddShortcut(p.string(), "Takedawn", "/third/Takedawn.AppImage", "/third", "").added);
    QCOMPARE(EntriesOf(p).size(), size_t(3));
  }

  void findsTheTakedawnShortcutsOnly() {
    QTemporaryDir t;
    const fs::path p = fs::path(t.path().toStdString()) / "shortcuts.vdf";
    QVERIFY(steam::FindTakedawn(p.string()).empty());  // no file: none, no error
    Write(p, steam::Dump({Obj("shortcuts", {Obj("0", {Num("appid", -5), Str("AppName", "Some Game"),
                                                     Str("Exe", "\"/games/some\"")}),
                                              Obj("1", {Num("appid", -123456), Str("AppName", "Takedawn.AppImage"),
                                                        Str("Exe", "\"/home/deck/Applications/Takedawn.AppImage\"")}),
                                              Obj("2", {Str("AppName", "takedawn"), Str("Exe", "/opt/other")})})}));
    const std::vector<steam::Found> found = steam::FindTakedawn(p.string());
    QCOMPARE(found.size(), size_t(2));
    QCOMPARE(found[0].app_id, uint32_t(-123456));  // the entry's own id: that is what names its art
    QCOMPARE(found[1].app_id, steam::AppId("/opt/other", "takedawn"));  // no field: the id Steam computes
    Write(p, "not a vdf");
    QVERIFY_EXCEPTION_THROWN(steam::FindTakedawn(p.string()), steam::VdfError);
  }

  void shortcutExePrefersTheStableName() {
    QTemporaryDir t;
    const fs::path home = t.path().toStdString();
    const fs::path image = home / "Downloads" / "Takedawn-1.0-linux-x86_64.AppImage";
    Write(image, "x");
    // no stable file yet: the running AppImage; neither: the program
    QCOMPARE(steam::ShortcutExe(home.string(), image.string(), "/prog"), image.string());
    QCOMPARE(steam::ShortcutExe(home.string(), (home / "gone").string(), "/prog"), std::string("/prog"));
    QCOMPARE(steam::ShortcutExe(home.string(), "", "/prog"), std::string("/prog"));
    // the stable name wins, running from elsewhere or not
    const fs::path stable = home / "Applications" / "Takedawn.AppImage";
    Write(stable, "x");
    QCOMPARE(steam::ShortcutExe(home.string(), image.string(), "/prog"), stable.string());
    QCOMPARE(steam::ShortcutExe(home.string(), stable.string(), "/prog"), stable.string());
  }

  void steamCommandIsFlatpaksOnlyForFlatpak() {
    QCOMPARE(steam::SteamCommand("/home/deck/.local/share/Steam"), std::vector<std::string>{"steam"});
    const std::vector<std::string> fp{"flatpak", "run", "com.valvesoftware.Steam"};
    QCOMPARE(steam::SteamCommand("/home/me/.var/app/com.valvesoftware.Steam/.local/share/Steam"), fp);
  }

  // Steam is told apart by what the process is, never by the words of its command line.
  void steamProcessNames() {
    QVERIFY(steam::IsSteamProcess("steam", ""));
    QVERIFY(steam::IsSteamProcess("steam", "bash"));  // /usr/bin/steam, a script: the exe is its interpreter
    QVERIFY(steam::IsSteamProcess("steam.sh", "bash"));
    QVERIFY(steam::IsSteamProcess("steamwebhelper", ""));
    QVERIFY(steam::IsSteamProcess("", "steam"));  // a renamed process still running the client
    QVERIFY(steam::IsSteamProcess("whatever", "steamwebhelper"));
    QVERIFY(!steam::IsSteamProcess("steamos-manager", "steamos-manager"));
    QVERIFY(!steam::IsSteamProcess("gamescope-sessi", "gamescope-session-plus"));
    QVERIFY(!steam::IsSteamProcess("Takedawn.AppImag", "Takedawn.AppImage"));
    QVERIFY(!steam::IsSteamProcess("steam-runtime-l", ""));
    QVERIFY(!steam::IsSteamProcess("tail", "tail"));
    QVERIFY(!steam::IsSteamProcess("bash", "bash"));
    QVERIFY(!steam::IsSteamProcess("", ""));
  }

  void steamRunningLooksAtTheProcessNotTheArguments() {
    QTemporaryDir t;
    const fs::path proc = t.path().toStdString();
    const std::string home = "/home/deck/.local/share/Steam";
    // The case of the bug: nothing of Steam, but its words in other processes' arguments.
    FakeProc(proc, 100, "bash", {"bash", "-c", "tail -f " + home + "/logs/steam -n 5"}, "/usr/bin/bash");
    FakeProc(proc, 101, "tail", {"tail", "-f", home + "/logs/steam ", "steamwebhelper.log"}, "/usr/bin/tail");
    FakeProc(proc, 102, "grep", {"grep", "/steam ", "steamwebhelper"}, "/usr/bin/grep");
    FakeProc(proc, 103, "sh", {"/bin/sh", "/home/deck/steam-notes/steam", "run"}, "/usr/bin/dash");
    FakeProc(proc, 104, "Takedawn.AppImag", {"/home/deck/Applications/Takedawn.AppImage", "--install", "/games/steam.iso"},
             "/tmp/.mount_x/usr/bin/takedawn-setup");
    FakeProc(proc, 105, "steamos-manager", {"/usr/bin/steamos-manager"}, "/usr/bin/steamos-manager");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
    // The client: comm steam.
    FakeProc(proc, 200, "steam", {home + "/ubuntu12_32/steam", "-steamos3", "-steampal", "-steamdeck", "-gamepadui"},
             home + "/ubuntu12_32/steam");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "200");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
    // Only its web helper is left.
    FakeProc(proc, 201, "steamwebhelper", {home + "/ubuntu12_64/steamwebhelper", "--type=zygote"},
             home + "/ubuntu12_64/steamwebhelper");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "201");
    // The wrapper script: comm is the script's name, the exe its interpreter.
    FakeProc(proc, 202, "steam", {"/bin/bash", "/usr/bin/steam", "-gamepadui"}, "/usr/bin/bash");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "202");
    FakeProc(proc, 203, "steam.sh", {"/bin/bash", home + "/steam.sh"}, "/usr/bin/bash");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "203");
    // Steam replaced its own binary while running: the exe link says "(deleted)", comm is unchanged.
    FakeProc(proc, 204, "x", {home + "/ubuntu12_32/steam"}, home + "/ubuntu12_32/steam (deleted)");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "204");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
  }

  void steamRunningOnSteamOsGameMode() {
    QTemporaryDir t;
    const fs::path proc = t.path().toStdString();
    // Game Mode: gamescope-session starts steam under the deck user; steam, its web helper
    // and a game's reaper are all there. Closing Steam leaves the session around.
    FakeProc(proc, 300, "gamescope-sessi", {"/usr/bin/gamescope-session-plus", "steam"}, "/usr/bin/bash");
    FakeProc(proc, 301, "gamescope", {"gamescope", "-e", "--", "steam", "-steamos3"}, "/usr/bin/gamescope");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
    FakeProc(proc, 302, "steam", {"/home/deck/.local/share/Steam/ubuntu12_32/steam", "-steamos3", "-steampal", "-steamdeck"},
             "/home/deck/.local/share/Steam/ubuntu12_32/steam");
    FakeProc(proc, 303, "steamwebhelper", {"steamwebhelper", "-lang=en_US"}, "/home/deck/.local/share/Steam/ubuntu12_64/steamwebhelper");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "302");
    QVERIFY(steam::SteamRunningIn(proc.string()));  // the helper alone still counts
    fs::remove_all(proc / "303");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
  }

  void steamRunningInFlatpak() {
    QTemporaryDir t;
    const fs::path proc = t.path().toStdString();
    // Flatpak Steam, as the host's /proc shows it: bwrap, flatpak's helpers (their command
    // lines name the app), and inside the sandbox steam / steamwebhelper, whose exe is
    // unreadable from outside (no link) or a path under /app or the app's data.
    FakeProc(proc, 400, "flatpak", {"flatpak", "run", "com.valvesoftware.Steam"}, "/usr/bin/flatpak");
    FakeProc(proc, 401, "bwrap", {"bwrap", "--args", "41", "/app/bin/steam", "com.valvesoftware.Steam"}, "/usr/bin/bwrap");
    FakeProc(proc, 402, "xdg-dbus-proxy", {"xdg-dbus-proxy", "--args=42", "/run/user/1000/.dbus-proxy/session-bus-proxy"},
             "/usr/bin/xdg-dbus-proxy");
    QVERIFY(!steam::SteamRunningIn(proc.string()));  // the wrapper processes alone are not Steam
    FakeProc(proc, 403, "steam", {"/home/me/.var/app/com.valvesoftware.Steam/.local/share/Steam/ubuntu12_32/steam"});
    QVERIFY(steam::SteamRunningIn(proc.string()));  // exe unreadable: comm is enough
    fs::remove_all(proc / "403");
    FakeProc(proc, 404, "steamwebhelper", {"steamwebhelper", "--type=gpu-process"}, "/app/bin/steamwebhelper");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    fs::remove_all(proc / "404");
    QVERIFY(!steam::SteamRunningIn(proc.string()));  // back to the wrapper processes: closed
  }

  void steamRunningIgnoresZombiesAndOwnProcesses() {
    QTemporaryDir t;
    const fs::path proc = t.path().toStdString();
    // Steam exited but its parent has not collected it yet: it is not running.
    FakeProc(proc, 500, "steam", {}, "", 'Z');
    FakeProc(proc, 501, "steamwebhelper", {}, "", 'Z');
    // A name with ") Z " in it does not fool the state check.
    FakeProc(proc, 502, "a) Z (b", {"x"}, "/usr/bin/x");
    QVERIFY(!steam::SteamRunningIn(proc.string()));
    // This process and its parent are not Steam even if they carry its name.
    FakeProc(proc, 600, "steam", {"steam", "-shutdown"}, "/usr/bin/bash");
    FakeProc(proc, 601, "steam.sh", {"steam.sh"}, "/usr/bin/bash");
    QVERIFY(steam::SteamRunningIn(proc.string()));
    QVERIFY(steam::SteamRunningIn(proc.string(), {600}));
    QVERIFY(!steam::SteamRunningIn(proc.string(), {600, 601}));
    // No /proc (macOS, Windows): not running.
    QVERIFY(!steam::SteamRunningIn((proc / "nothing-here").string()));
  }

  void steamGameRunning() {
    QTemporaryDir t;
    const fs::path proc = t.path().toStdString();
    FakeProc(proc, 700, "bash", {"bash", "-c", "ps | grep 'reaper SteamLaunch AppId=1'"}, "/usr/bin/bash");
    FakeProc(proc, 701, "grep", {"grep", "reaper", "SteamLaunch"}, "/usr/bin/grep");
    FakeProc(proc, 702, "reaper", {"reaper", "other"}, "/x/reaper");
    QVERIFY(!steam::SteamGameRunningIn(proc.string()));
    FakeProc(proc, 703, "reaper", {"/home/deck/.local/share/Steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=123", "--", "game"},
             "/home/deck/.local/share/Steam/ubuntu12_32/reaper");
    QVERIFY(steam::SteamGameRunningIn(proc.string()));
    QVERIFY(!steam::SteamGameRunningIn(proc.string(), {703}));
  }
};

QTEST_APPLESS_MAIN(SteamTest)
#include "steam_test.moc"
