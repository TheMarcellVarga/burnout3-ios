#include "steam_shortcut.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>

#if defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#endif

namespace steam {
namespace fs = std::filesystem;

namespace {

std::string Lower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return char(std::tolower(c)); });
  return s;
}

struct Reader {
  const std::string& d;
  size_t pos = 0;
  std::string CStr() {
    const size_t end = d.find('\0', pos);
    if (end == std::string::npos) throw VdfError("malformed shortcuts.vdf: a string without its end");
    std::string s = d.substr(pos, end - pos);
    pos = end + 1;
    return s;
  }
  std::vector<Node> Obj() {
    std::vector<Node> items;
    for (;;) {
      if (pos >= d.size()) throw VdfError("file ends inside an object");
      const unsigned char t = static_cast<unsigned char>(d[pos++]);
      if (t == 0x08) return items;
      Node n;
      n.key = CStr();
      if (t == 0x00) {
        n.type = Node::Object;
        n.items = Obj();
      } else if (t == 0x01) {
        n.type = Node::String;
        n.text = CStr();
      } else if (t == 0x02) {
        if (pos + 4 > d.size()) throw VdfError("malformed shortcuts.vdf: an integer cut short");
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i) v |= uint32_t(static_cast<unsigned char>(d[pos + i])) << (8 * i);
        n.type = Node::Int;
        n.number = static_cast<int32_t>(v);
        pos += 4;
      } else {
        char msg[80];
        std::snprintf(msg, sizeof msg, "unknown VDF value type 0x%02X at offset %zu", t, pos - 1);
        throw VdfError(msg);
      }
      items.push_back(std::move(n));
    }
  }
};

void Put(const std::vector<Node>& items, std::string* out) {
  for (const Node& n : items) {
    out->push_back(char(n.type));
    out->append(n.key);
    out->push_back('\0');
    if (n.type == Node::Object) {
      Put(n.items, out);
    } else if (n.type == Node::String) {
      out->append(n.text);
      out->push_back('\0');
    } else {
      const uint32_t v = static_cast<uint32_t>(n.number);
      for (int i = 0; i < 4; ++i) out->push_back(char((v >> (8 * i)) & 0xFF));
    }
  }
  out->push_back('\x08');
}

uint32_t Crc32(const std::string& s) {
  uint32_t crc = 0xFFFFFFFFu;
  for (unsigned char c : s) {
    crc ^= c;
    for (int k = 0; k < 8; ++k) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
  }
  return ~crc;
}

Node Str(const std::string& k, const std::string& v) {
  Node n;
  n.key = k;
  n.type = Node::String;
  n.text = v;
  return n;
}
Node Num(const std::string& k, int32_t v) {
  Node n;
  n.key = k;
  n.type = Node::Int;
  n.number = v;
  return n;
}

std::vector<Node>* Entries(std::vector<Node>* root) {
  for (Node& n : *root)
    if (Lower(n.key) == "shortcuts" && n.type == Node::Object) return &n.items;
  return nullptr;
}

bool ReadFile(const std::string& path, std::string* out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::ostringstream ss;
  ss << f.rdbuf();
  *out = ss.str();
  return true;
}

// Steam's text VDF ("key" "value" and "key" { ... }): the tokens.
struct Token {
  bool brace = false;
  char which = 0;
  std::string text;
};
std::vector<Token> TextTokens(const std::string& text) {
  std::vector<Token> toks;
  for (size_t i = 0; i < text.size(); ++i) {
    const char c = text[i];
    if (c == '{' || c == '}') {
      toks.push_back({true, c, {}});
    } else if (c == '"') {
      Token t;
      for (++i; i < text.size() && text[i] != '"'; ++i) {
        if (text[i] == '\\' && i + 1 < text.size()) t.text.push_back(text[i++]);
        t.text.push_back(text[i]);
      }
      toks.push_back(std::move(t));
    }
  }
  return toks;
}
using Flat = std::map<std::string, std::string>;
// "users" { "<id>" { key value ... } ... }: each user's own keys.
std::vector<std::pair<std::string, Flat>> LoginUsers(const std::string& text) {
  std::vector<std::pair<std::string, Flat>> users;
  const std::vector<Token> t = TextTokens(text);
  size_t i = 0;
  while (i + 1 < t.size() && !(!t[i].brace && t[i].text == "users" && t[i + 1].brace && t[i + 1].which == '{')) ++i;
  if (i + 1 >= t.size()) return users;
  i += 2;
  while (i < t.size() && !(t[i].brace && t[i].which == '}')) {
    if (t[i].brace || i + 1 >= t.size()) break;
    const std::string id = t[i].text;
    if (!(t[i + 1].brace && t[i + 1].which == '{')) {  // "key" "value" at this level: not a user
      i += 2;
      continue;
    }
    i += 2;
    Flat keys;
    int depth = 1;
    while (i < t.size() && depth > 0) {
      if (t[i].brace) {
        depth += t[i].which == '{' ? 1 : -1;
        ++i;
      } else if (depth == 1 && i + 1 < t.size() && !t[i + 1].brace) {
        keys[t[i].text] = t[i + 1].text;
        i += 2;
      } else {
        ++i;
      }
    }
    users.emplace_back(id, std::move(keys));
  }
  return users;
}

bool AllDigits(const std::string& s) {
  return !s.empty() && std::all_of(s.begin(), s.end(), [](unsigned char c) { return std::isdigit(c) != 0; });
}

const unsigned long long kSteamId64Base = 76561197960265728ULL;

}  // namespace

std::vector<Node> Parse(const std::string& data) {
  Reader r{data};
  std::vector<Node> root = r.Obj();
  if (r.pos != data.size()) throw VdfError("trailing bytes after the root object");
  return root;
}

std::string Dump(const std::vector<Node>& root) {
  std::string out;
  Put(root, &out);
  return out;
}

uint32_t AppId(const std::string& exe_quoted, const std::string& name) {
  return Crc32(exe_quoted + name) | 0x80000000u;
}

Added AddShortcut(const std::string& vdf_path, const std::string& name, const std::string& exe,
                  const std::string& start_dir, const std::string& icon, const std::string& launch_options,
                  const std::vector<std::string>& tags) {
  const std::string quoted = "\"" + exe + "\"";
  std::string data;
  std::error_code ec;
  const bool existed = fs::exists(vdf_path, ec);
  if (existed) {
    if (!ReadFile(vdf_path, &data)) throw std::runtime_error("cannot read " + vdf_path);
  } else {
    Node top;
    top.key = "shortcuts";
    top.type = Node::Object;
    data = Dump({top});
  }
  std::vector<Node> root = Parse(data);
  std::vector<Node>* entries = Entries(&root);
  if (!entries) throw VdfError("no \"shortcuts\" object in " + vdf_path);

  Added result;
  result.app_id = AppId(quoted, name);
  for (const Node& e : *entries) {
    if (e.type != Node::Object) continue;
    // The same program is the same shortcut, whatever it was called when it was added
    // (Steam's own "Add to Steam" names it after the file), quoted or not.
    std::string exe_there;
    bool has_exe = false;
    const Node* id_field = nullptr;
    for (const Node& f : e.items) {
      const std::string k = Lower(f.key);
      if (f.type == Node::String && k == "exe") exe_there = f.text, has_exe = true;
      if (f.type == Node::Int && k == "appid") id_field = &f;
    }
    if (has_exe && (exe_there == quoted || exe_there == exe)) {  // already there
      if (id_field) result.app_id = static_cast<uint32_t>(id_field->number);
      return result;
    }
  }

  Node tag_list;
  tag_list.key = "tags";
  tag_list.type = Node::Object;
  for (size_t i = 0; i < tags.size(); ++i) tag_list.items.push_back(Str(std::to_string(i), tags[i]));
  std::vector<Node> fields{
      Num("appid", static_cast<int32_t>(result.app_id)), Str("AppName", name), Str("Exe", quoted),
      Str("StartDir", start_dir), Str("icon", icon), Str("ShortcutPath", ""), Str("LaunchOptions", launch_options),
      Num("IsHidden", 0), Num("AllowDesktopConfig", 1), Num("AllowOverlay", 1), Num("OpenVR", 0), Num("Devkit", 0),
      Str("DevkitGameID", ""), Num("DevkitOverrideAppID", 0), Num("LastPlayTime", 0), Str("FlatpakAppID", ""),
      tag_list};
  if (!entries->empty() && entries->back().type == Node::Object) {
    // Follow the last entry: its fields, in its order, under its spelling of the keys.
    std::vector<Node> like;
    for (const Node& have : entries->back().items) {
      auto mine = std::find_if(fields.begin(), fields.end(),
                               [&](const Node& f) { return Lower(f.key) == Lower(have.key); });
      Node n;
      if (mine != fields.end()) {
        n = *mine;
      } else {
        n.type = have.type;  // a field this code does not know: its empty value
      }
      n.key = have.key;
      like.push_back(std::move(n));
    }
    fields = std::move(like);
  }
  std::set<std::string> taken;
  for (const Node& e : *entries) taken.insert(e.key);
  int index = 0;
  while (taken.count(std::to_string(index))) ++index;
  Node entry;
  entry.key = std::to_string(index);
  entry.type = Node::Object;
  entry.items = std::move(fields);
  entries->push_back(std::move(entry));

  if (existed) {
    char stamp[32];
    const std::time_t now = std::time(nullptr);
    std::strftime(stamp, sizeof stamp, "%Y%m%d-%H%M%S", std::localtime(&now));
    result.backup = vdf_path + ".takedawn-backup-" + stamp;
    fs::copy_file(vdf_path, result.backup, fs::copy_options::overwrite_existing, ec);
    if (ec) throw std::runtime_error("cannot make the backup " + result.backup + ": " + ec.message());
  } else {
    fs::create_directories(fs::path(vdf_path).parent_path(), ec);
  }
  const std::string tmp = vdf_path + ".takedawn-tmp";
  {
    std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
    const std::string out = Dump(root);
    f.write(out.data(), static_cast<std::streamsize>(out.size()));
    f.flush();
    if (!f) {
      fs::remove(tmp, ec);
      throw std::runtime_error("cannot write " + tmp);
    }
  }
  fs::rename(tmp, vdf_path, ec);
  if (ec) {
    std::error_code ignore;
    fs::remove(tmp, ignore);
    throw std::runtime_error("cannot replace " + vdf_path + ": " + ec.message());
  }
  result.added = true;
  return result;
}

std::vector<Found> FindTakedawn(const std::string& vdf_path) {
  std::vector<Found> found;
  std::string data;
  std::error_code ec;
  if (!fs::exists(vdf_path, ec)) return found;
  if (!ReadFile(vdf_path, &data)) throw std::runtime_error("cannot read " + vdf_path);
  std::vector<Node> root = Parse(data);
  const std::vector<Node>* entries = Entries(&root);
  if (!entries) throw VdfError("no \"shortcuts\" object in " + vdf_path);
  for (const Node& e : *entries) {
    if (e.type != Node::Object) continue;
    Found f;
    bool has_id = false;
    for (const Node& field : e.items) {
      const std::string k = Lower(field.key);
      if (field.type == Node::String && k == "appname") f.name = field.text;
      if (field.type == Node::String && k == "exe") f.exe = field.text;
      if (field.type == Node::Int && k == "appid") f.app_id = static_cast<uint32_t>(field.number), has_id = true;
    }
    std::string file = f.exe;
    if (file.size() >= 2 && file.front() == '"' && file.back() == '"') file = file.substr(1, file.size() - 2);
    file = Lower(fs::path(file).filename().string());
    if (Lower(f.name) != "takedawn" && file.rfind("takedawn", 0) != 0) continue;
    if (!has_id) f.app_id = AppId(f.exe, f.name);  // Steam computes the same when the field is missing
    found.push_back(std::move(f));
  }
  return found;
}

bool IsSteamProcess(const std::string& comm, const std::string& exe_name) {
  const auto is_steam = [](const std::string& n) { return n == "steam" || n == "steam.sh" || n == "steamwebhelper"; };
  return is_steam(comm) || is_steam(exe_name);
}

std::vector<std::string> SteamCommand(const std::string& steam_root) {
  if (steam_root.find("/.var/app/com.valvesoftware.Steam/") != std::string::npos)
    return {"flatpak", "run", "com.valvesoftware.Steam"};
  return {"steam"};
}

std::string ShortcutExe(const std::string& home, const std::string& appimage, const std::string& program) {
  std::error_code ec;
  const fs::path stable = fs::path(home) / "Applications" / "Takedawn.AppImage";
  if (fs::is_regular_file(stable, ec)) return stable.string();
  if (!appimage.empty() && fs::is_regular_file(appimage, ec)) return appimage;
  return program;
}

namespace {

// One /proc/<pid> as far as the Steam checks need it.
struct ProcInfo {
  std::string comm;      // the name, without the newline
  std::string exe_name;  // basename of the exe link, "" when unreadable
  bool zombie = false;   // exited, not yet reaped by its parent: it is not running
};

bool ReadProc(const fs::path& dir, ProcInfo* p) {
  std::string comm;
  if (!ReadFile((dir / "comm").string(), &comm)) return false;  // gone meanwhile
  while (!comm.empty() && (comm.back() == '\n' || comm.back() == '\0')) comm.pop_back();
  p->comm = comm;
  // stat: "pid (comm) S ...": the state follows the LAST ')' (comm may hold anything).
  std::string stat;
  if (ReadFile((dir / "stat").string(), &stat)) {
    const size_t close = stat.rfind(')');
    if (close != std::string::npos && close + 2 < stat.size()) {
      const char state = stat[close + 2];
      p->zombie = state == 'Z' || state == 'X' || state == 'x';
    }
  }
  std::error_code ec;
  std::string exe = fs::read_symlink(dir / "exe", ec).string();
  if (!ec) {
    static const std::string kDeleted = " (deleted)";  // Steam replaces its own files when it updates
    if (exe.size() > kDeleted.size() && exe.compare(exe.size() - kDeleted.size(), kDeleted.size(), kDeleted) == 0)
      exe.resize(exe.size() - kDeleted.size());
    p->exe_name = fs::path(exe).filename().string();
  }
  return true;
}

// Calls `match` for every live, not ignored process of proc_dir; true at the first yes.
template <class Match>
bool AnyProcess(const std::string& proc_dir, const std::vector<int>& ignore_pids, Match match) {
  std::error_code ec;
  for (fs::directory_iterator it(proc_dir, ec), end; !ec && it != end; it.increment(ec)) {
    const std::string name = it->path().filename().string();
    if (!AllDigits(name) || name.size() > 9) continue;
    if (std::find(ignore_pids.begin(), ignore_pids.end(), std::stoi(name)) != ignore_pids.end()) continue;
    ProcInfo p;
    if (!ReadProc(it->path(), &p) || p.zombie) continue;
    if (match(it->path(), p)) return true;
  }
  return false;
}

std::vector<int> OwnPids() {
#if defined(__unix__) || defined(__APPLE__)
  return {int(getpid()), int(getppid())};
#else
  return {};
#endif
}

}  // namespace

bool SteamRunningIn(const std::string& proc_dir, const std::vector<int>& ignore_pids) {
  return AnyProcess(proc_dir, ignore_pids,
                    [](const fs::path&, const ProcInfo& p) { return IsSteamProcess(p.comm, p.exe_name); });
}

bool SteamRunning() { return SteamRunningIn("/proc", OwnPids()); }

bool SteamGameRunningIn(const std::string& proc_dir, const std::vector<int>& ignore_pids) {
  return AnyProcess(proc_dir, ignore_pids, [](const fs::path& dir, const ProcInfo& p) {
    if (p.comm != "reaper") return false;
    std::string raw;  // "reaper\0SteamLaunch\0AppId=..." (argv[0] may be a path)
    if (!ReadFile((dir / "cmdline").string(), &raw)) return false;
    const size_t first = raw.find('\0');
    if (first == std::string::npos) return false;
    return raw.compare(first + 1, 11, "SteamLaunch") == 0 && (raw.size() == first + 12 || raw[first + 12] == '\0');
  });
}

bool SteamGameRunning() { return SteamGameRunningIn("/proc", OwnPids()); }

std::string MostRecentUser(const std::string& loginusers_path) {
  std::string text;
  if (!ReadFile(loginusers_path, &text)) return {};
  struct Rank {
    int recent;
    long long stamp;
    std::string id;
  };
  std::vector<Rank> ranked;
  for (const auto& [sid, keys] : LoginUsers(text)) {
    if (!AllDigits(sid) || sid.size() > 19) continue;
    const unsigned long long id64 = std::stoull(sid);
    if (id64 <= kSteamId64Base) continue;
    long long stamp = 0;
    auto ts = keys.find("Timestamp");
    if (ts != keys.end() && AllDigits(ts->second) && ts->second.size() < 18) stamp = std::stoll(ts->second);
    auto mr = keys.find("MostRecent");
    ranked.push_back({mr != keys.end() && mr->second == "1" ? 1 : 0, stamp, std::to_string(id64 - kSteamId64Base)});
  }
  std::sort(ranked.begin(), ranked.end(), [](const Rank& a, const Rank& b) {
    return a.recent != b.recent ? a.recent > b.recent : a.stamp > b.stamp;
  });
  if (ranked.empty() || (ranked[0].recent == 0 && ranked[0].stamp == 0)) return {};
  if (ranked.size() > 1 && ranked[1].recent == ranked[0].recent && ranked[1].stamp == ranked[0].stamp)
    return {};  // a tie at the top cannot decide
  return ranked[0].id;
}

std::vector<User> UserdataConfigs(const std::string& home) {
  static const char* const kBases[] = {".local/share/Steam", ".steam/steam",
                                       ".var/app/com.valvesoftware.Steam/.local/share/Steam",
                                       "Library/Application Support/Steam"};
  std::vector<User> found;
  std::vector<std::string> real_seen;
  for (const char* base : kBases) {
    const fs::path root = fs::path(home) / base;
    std::error_code ec;
    std::vector<fs::path> ids;
    for (fs::directory_iterator it(root / "userdata", ec), end; !ec && it != end; it.increment(ec))
      ids.push_back(it->path());
    std::sort(ids.begin(), ids.end());
    for (const fs::path& dir : ids) {
      const fs::path config = dir / "config";
      if (!fs::is_directory(config, ec)) continue;
      const std::string id = dir.filename().string();
      const std::string real = fs::weakly_canonical(config, ec).string();
      if (id == "0" || std::find(real_seen.begin(), real_seen.end(), real) != real_seen.end()) continue;
      real_seen.push_back(real);
      found.push_back({id, config.string(), root.string()});
    }
  }
  return found;
}

bool PickUser(const std::vector<User>& users, User* chosen, std::string* why) {
  if (users.size() == 1) {
    *chosen = users[0];
    *why = "the only Steam user";
    return true;
  }
  if (users.empty()) {
    *why = "no Steam user data found";
    return false;
  }
  const std::string recent = MostRecentUser((fs::path(users[0].root) / "config" / "loginusers.vdf").string());
  if (recent.empty()) {
    *why = "loginusers.vdf does not say who logged in last";
    return false;
  }
  for (const User& u : users) {
    if (u.id == recent) {
      *chosen = u;
      *why = "most recently logged in (loginusers.vdf)";
      return true;
    }
  }
  *why = "the most recent user (" + recent + ") has no userdata folder";
  return false;
}

}  // namespace steam
