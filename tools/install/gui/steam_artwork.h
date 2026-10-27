// The Steam library art of the Takedawn shortcut (Linux, Steam Deck): without it Steam
// shows a grey tile. Written by the "Add to Steam" step (installer_window.cpp), right
// after the shortcut, into userdata/<user>/config/grid/, under the names Steam (and
// Steam ROM Manager, SteamGridDB) use for a non-Steam shortcut with app id N, the
// unsigned 32-bit id that shortcuts.vdf stores as "appid" (steam::AppId):
//
//   Np.png       portrait capsule, 600 x 900
//   N.png        wide capsule, 920 x 430
//   N_hero.png   the library page's banner, 1920 x 620
//   N_logo.png   the logo Steam draws over the banner, transparent
//   N_icon.png   the icon (the shortcut's "icon" field names it)
//
// Where the pictures come from:
//  * the person's own copy of the game, already installed by then: the title screen's
//    logo (Data/Frontend.txd, "titlescreen_logo") and two of the loading screens
//    (Data/LoadScrn.bin, "GNRL0001" and "GNRL0002"), decoded and composed here, on the
//    person's machine. Nothing made from the game's data is in the repository or in
//    a release package;
//  * else Takedawn's own: the icon (assets/icon/takedawn.svg, compiled into the
//    setup) and the name on its navy, drawn at the same sizes.
//
// Every file written carries a PNG text chunk (Software = kMarker). A file of the
// same name without it is someone else's (the person's own art, SteamGridDB's): it
// is renamed to <name>.takedawn-backup-<time> first, never overwritten.
// RemoveGridArt undoes it all: our files go, the newest backup of each comes back.
#pragma once

#include <QImage>
#include <QString>
#include <QStringList>
#include <cstdint>
#include <string>
#include <vector>

#include "steam_shortcut.h"

namespace steamart {

inline constexpr const char kMarker[] = "Takedawn setup";

enum Kind { Portrait, Wide, Hero, Logo, Icon, KindCount };

// The file name of each picture of app id `app_id` (no folder): "123p.png", ...
QString FileName(uint32_t app_id, Kind kind);
// The size of each (Logo: the most it may be; it keeps its own proportions).
QSize TargetSize(Kind kind);

struct Art {
  QImage image[KindCount];  // a null image is not written
  QString source;           // "game" or "takedawn"
  QStringList used;         // the game's textures it was made from
};

// One texture of the game's texture dictionaries (the Xbox D3D layout Criterion's
// .txd uses): DXT1, DXT3/5 and swizzled 8-bit palette images. `data` is the whole
// dictionary; false (and `why`) when there is no such texture or it is not readable.
bool DecodeTexture(const std::string& data, const std::string& name, QImage* out, std::string* why);
// The dictionary called `name` inside LoadScrn.bin (an archive of one-texture
// dictionaries); its bytes, or "" when it is not there.
std::string LoadScreenDictionary(const std::string& archive, const std::string& name);

// The art made from the game's files under `game_dir` (the folder with Data/).
// Images are null (and `why` says why) when a file or texture is missing.
Art FromGame(const QString& game_dir, QString* why);
// The art made from Takedawn's own icon (any size; the 512 px one is best).
Art Fallback(const QImage& icon);

// The art for the Takedawn shortcut: made from the game's files under `game_dir` when
// they can be read (the icon `icon` is then the Icon), else Takedawn's own from `icon`.
// `note` says which and why, for a log.
Art ForShortcut(const QString& game_dir, const QImage& icon, QString* note);

// The file at `path` is one this code wrote (its PNG carries kMarker).
bool IsOurs(const QString& path);

struct Written {
  QStringList files;    // what was written
  QStringList backups;  // someone else's files, renamed out of the way
  QStringList errors;
};
// Writes the art of `app_id` into `grid_dir` (made when missing).
Written WriteGridArt(const QString& grid_dir, uint32_t app_id, const Art& art);
// Removes our files of `app_id` from `grid_dir` and puts back the newest backup of
// each name. For when the shortcut is removed; returns the number of files removed.
int RemoveGridArt(const QString& grid_dir, uint32_t app_id);


// "Add Steam library art" (the game's settings overlay, takedawn-setup --steam-art): for
// the person who updated and never sees the setup window again. Every Takedawn shortcut
// in the shortcuts.vdf of each of `users` (steam::FindTakedawn) gets `art`, the files
// written as above. Only the art folder is touched, never shortcuts.vdf, so it is fine
// while Steam runs. `log` has a line per user and per file.
struct Existing {
  int users = 0;      // Steam users looked at
  int shortcuts = 0;  // Takedawn shortcuts found
  int files = 0;      // art files written
  int backups = 0;    // someone else's files kept as .takedawn-backup
  QStringList errors;
  QStringList log;
  // The one line the person is shown.
  QString Line() const;
};
Existing WriteForExisting(const std::vector<steam::User>& users, const Art& art);

}  // namespace steamart
