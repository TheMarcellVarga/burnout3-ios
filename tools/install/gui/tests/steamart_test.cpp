// The Steam library art (steam_artwork.cpp): the file names of an app id (the id the
// shortcut has in shortcuts.vdf), the sizes of Takedawn's own pictures, the texture
// reader on dictionaries made here, and the rule that someone else's file is kept as
// a backup and comes back when the art is removed. No game data is needed: with
// TAKEDAWN_STEAMART_GAME (a folder with Data/) one more test composes the real art,
// and TAKEDAWN_STEAMART_OUT names a folder to write it to for a look.
#include <QtTest>

#include <filesystem>
#include <fstream>

#include "steam_artwork.h"
#include "steam_shortcut.h"

using namespace steamart;

namespace {

void Put32(std::string* d, size_t at, uint32_t v) {
  if (d->size() < at + 4) d->resize(at + 4);
  for (int i = 0; i < 4; ++i) (*d)[at + i] = char((v >> (8 * i)) & 0xFF);
}

struct Tex {
  std::string name;
  uint32_t format;  // 0x0B P8, 0x0C DXT1, 0x0F DXT5
  int log_w, log_h;
  std::string pixels;   // as stored
  std::string palette;  // P8: 1024 bytes
};

// A dictionary in the game's layout (steam_artwork.cpp).
std::string Dictionary(const std::vector<Tex>& texs) {
  std::string d;
  Put32(&d, 0, 0x543C0000u);
  Put32(&d, 4, 0xBCDEED81u);
  Put32(&d, 8, uint32_t(texs.size()));
  Put32(&d, 12, 0x10);
  size_t at = (0x10 + 16 * texs.size() + 0x7F) & ~size_t(0x7F);
  for (size_t i = 0; i < texs.size(); ++i) {
    const Tex& t = texs[i];
    Put32(&d, 0x10 + 16 * i, uint32_t(i + 1));
    Put32(&d, 0x10 + 16 * i + 8, uint32_t(at));
    d.resize(at + 0x80);
    Put32(&d, at + 0x00, 0x00040001u);
    Put32(&d, at + 0x04, 0x80);
    Put32(&d, at + 0x0C, 0x29u | t.format << 8 | 1u << 16 | uint32_t(t.log_w) << 20 | uint32_t(t.log_h) << 24);
    Put32(&d, at + 0x34, t.format);
    Put32(&d, at + 0x38, 1u << t.log_w);
    Put32(&d, at + 0x3C, 1u << t.log_h);
    std::memcpy(&d[at + 0x48], t.name.data(), std::min<size_t>(t.name.size(), 31));
    d += t.pixels;
    if (!t.palette.empty()) {
      const size_t head = d.size();
      d.resize(head + 0x40);
      Put32(&d, head, 0x00030001u);
      d += t.palette;
    }
    at = (d.size() + 0x7F) & ~size_t(0x7F);
    d.resize(at);
  }
  return d;
}

// A 4 x 4 DXT1 block: red everywhere but (1, 0), which is blue.
Tex Dxt1Tex(const std::string& name) {
  std::string b(8, '\0');
  b[0] = char(0x00), b[1] = char(0xF8);  // c0 = red (565)
  b[2] = char(0x1F), b[3] = char(0x00);  // c1 = blue
  b[4] = char(1 << 2);                   // pixel 1 uses c1
  return {name, 0x0C, 2, 2, b, {}};
}

// A 4 x 4 palette image: pixel (x, y) is colour y * 4 + x, stored swizzled (x's bits
// at 1 and 4, y's at 2 and 8); colour i is (R 3i, G 2i, B i, A 255 - i).
Tex P8Tex(const std::string& name) {
  std::string px(16, '\0');
  for (int y = 0; y < 4; ++y)
    for (int x = 0; x < 4; ++x) {
      const int s = (x & 1) | (x & 2) << 1 | (y & 1) << 1 | (y & 2) << 2;
      px[s] = char(y * 4 + x);
    }
  std::string pal(1024, '\0');
  for (int i = 0; i < 256; ++i) {
    pal[4 * i] = char(i), pal[4 * i + 1] = char(2 * i), pal[4 * i + 2] = char(3 * i), pal[4 * i + 3] = char(255 - i);
  }
  return {name, 0x0B, 2, 2, px, pal};
}

// LoadScrn.bin's layout: u32 count, u32 0, (u64 hash, u32 size, u32 offset) each, the
// dictionaries from 0x800.
std::string LoadScreens(const std::vector<std::string>& dicts) {
  std::string a;
  Put32(&a, 0, uint32_t(dicts.size()));
  Put32(&a, 4, 0);
  size_t off = 0;
  std::string body;
  for (size_t i = 0; i < dicts.size(); ++i) {
    Put32(&a, 8 + 16 * i, 0x1234u + uint32_t(i));
    Put32(&a, 8 + 16 * i + 4, 0);
    Put32(&a, 8 + 16 * i + 8, uint32_t(dicts[i].size()));
    Put32(&a, 8 + 16 * i + 12, uint32_t(off));
    body += dicts[i];
    off += dicts[i].size();
  }
  a.resize(0x800);
  return a + body;
}

QImage Plain(QColor c) {
  QImage img(40, 20, QImage::Format_ARGB32);
  img.fill(c);
  return img;
}

}  // namespace

class SteamArtTest : public QObject {
  Q_OBJECT
 private slots:
  // The names Steam looks for, and the id is the one AddShortcut writes into
  // shortcuts.vdf, read unsigned (the file stores it as a signed int32).
  void fileNamesOfTheShortcutsId() {
    QCOMPARE(FileName(3141592653u, Portrait), QString("3141592653p.png"));
    QCOMPARE(FileName(3141592653u, Wide), QString("3141592653.png"));
    QCOMPARE(FileName(3141592653u, Hero), QString("3141592653_hero.png"));
    QCOMPARE(FileName(3141592653u, Logo), QString("3141592653_logo.png"));
    QCOMPARE(FileName(3141592653u, Icon), QString("3141592653_icon.png"));
    QCOMPARE(FileName(0xFFFFFFFFu, Portrait), QString("4294967295p.png"));

    QTemporaryDir tmp;
    const std::string vdf = (tmp.path() + "/shortcuts.vdf").toStdString();
    const std::string exe = "/home/deck/Applications/Takedawn.AppImage";
    const steam::Added added = steam::AddShortcut(vdf, "Takedawn", exe, "/home/deck/Applications", "");
    std::ifstream f(vdf, std::ios::binary);
    const std::string data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    int32_t stored = 0;
    const std::vector<steam::Node> root = steam::Parse(data);
    for (const steam::Node& field : root.at(0).items.at(0).items)
      if (field.key == "appid") stored = field.number;
    QVERIFY(stored < 0);  // the high bit is always set
    QCOMPARE(uint32_t(stored), added.app_id);
    QCOMPARE(added.app_id, steam::AppId("\"" + exe + "\"", "Takedawn"));
    QCOMPARE(FileName(uint32_t(stored), Portrait), QString::number(added.app_id) + "p.png");
    QVERIFY(!FileName(uint32_t(stored), Hero).contains('-'));
  }

  void fallbackHasSteamsSizes() {
    const QImage icon(":/takedawn/icon-512.png");
    QVERIFY(!icon.isNull());
    const Art art = Fallback(icon);
    QCOMPARE(art.source, QString("takedawn"));
    QCOMPARE(art.image[Portrait].size(), QSize(600, 900));
    QCOMPARE(art.image[Wide].size(), QSize(920, 430));
    QCOMPARE(art.image[Hero].size(), QSize(1920, 620));
    QCOMPARE(art.image[Icon].size(), QSize(256, 256));
    const QImage& logo = art.image[Logo];
    QVERIFY(!logo.isNull());
    QVERIFY(logo.width() <= 1280 && logo.height() <= 720);
    QVERIFY(logo.width() > 2 * logo.height());  // the icon and the name beside it
    QVERIFY(logo.hasAlphaChannel());
    QCOMPARE(qAlpha(logo.pixel(logo.width() - 1, 0)), 0);  // transparent around the name
    QCOMPARE(qAlpha(art.image[Wide].pixel(0, 0)), 255);    // capsules are opaque
  }

  void readsTheGamesTextureLayout() {
    const std::string dict = Dictionary({Dxt1Tex("first"), P8Tex("second")});
    QImage img;
    std::string why;
    QVERIFY2(DecodeTexture(dict, "first", &img, &why), why.c_str());
    QCOMPARE(img.size(), QSize(4, 4));
    QCOMPARE(img.pixel(0, 0), qRgba(255, 0, 0, 255));
    QCOMPARE(img.pixel(1, 0), qRgba(0, 0, 255, 255));
    QCOMPARE(img.pixel(3, 3), qRgba(255, 0, 0, 255));
    QVERIFY2(DecodeTexture(dict, "second", &img, &why), why.c_str());
    for (int y = 0; y < 4; ++y)
      for (int x = 0; x < 4; ++x) {
        const int i = y * 4 + x;
        QCOMPARE(img.pixel(x, y), qRgba(3 * i, 2 * i, i, 255 - i));
      }
    QVERIFY(!DecodeTexture(dict, "third", &img, &why));
    QVERIFY(QString::fromStdString(why).contains("not in the dictionary"));
    QVERIFY(!DecodeTexture(dict.substr(0, dict.size() - 600), "second", &img, &why));  // palette cut off
    QVERIFY(!DecodeTexture("not a dictionary at all", "first", &img, &why));
  }

  void findsALoadingScreen() {
    const std::string a = LoadScreens({Dictionary({Dxt1Tex("GNRL0001")}), Dictionary({P8Tex("GNRL0002")})});
    const std::string second = LoadScreenDictionary(a, "GNRL0002");
    QVERIFY(!second.empty());
    QImage img;
    std::string why;
    QVERIFY(DecodeTexture(second, "GNRL0002", &img, &why));
    QVERIFY(LoadScreenDictionary(a, "CARS0001").empty());
    QVERIFY(LoadScreenDictionary(a.substr(0, 0x900), "GNRL0002").empty());
  }

  void noGameDataMeansNoGameArt() {
    QTemporaryDir tmp;
    QString why;
    const Art art = FromGame(tmp.path(), &why);
    QVERIFY(art.image[Hero].isNull());
    QVERIFY(!why.isEmpty());
  }

  // Someone else's file of the same name is kept as a backup, ours are replaced in
  // place, and removing the art puts theirs back.
  void keepsOtherFilesAndCleansUp() {
    QTemporaryDir tmp;
    const QString grid = tmp.path() + "/userdata/42/config/grid";
    const uint32_t id = 2900000001u;
    QDir().mkpath(grid);
    const QString theirs = grid + "/" + FileName(id, Portrait);
    QVERIFY(Plain(Qt::green).save(theirs));
    const QString unrelated = grid + "/12345p.png";
    QVERIFY(Plain(Qt::blue).save(unrelated));
    QVERIFY(!IsOurs(theirs));

    const Art art = Fallback(QImage(":/takedawn/icon-512.png"));
    Written w = WriteGridArt(grid, id, art);
    QVERIFY2(w.errors.isEmpty(), qPrintable(w.errors.join("; ")));
    QCOMPARE(w.files.size(), int(KindCount));
    QCOMPARE(w.backups.size(), 1);
    QVERIFY(w.backups[0].startsWith(theirs + ".takedawn-backup-"));
    for (const QString& f : w.files) QVERIFY(IsOurs(f));
    QCOMPARE(QImage(theirs).size(), QSize(600, 900));

    w = WriteGridArt(grid, id, art);  // again: ours are replaced, nothing more is backed up
    QVERIFY(w.errors.isEmpty());
    QVERIFY(w.backups.isEmpty());
    QCOMPARE(QDir(grid).entryList({"*.takedawn-backup-*"}, QDir::Files).size(), 1);
    QVERIFY(QDir(grid).entryList({"*.takedawn-tmp"}, QDir::Files).isEmpty());

    QCOMPARE(RemoveGridArt(grid, id), int(KindCount));
    QStringList left = QDir(grid).entryList(QDir::Files);
    left.sort();
    QCOMPARE(left, QStringList({"12345p.png", FileName(id, Portrait)}));
    QCOMPARE(QImage(theirs).pixel(0, 0), QColor(Qt::green).rgba());
    QCOMPARE(QImage(unrelated).pixel(0, 0), QColor(Qt::blue).rgba());
  }

  // The button for a player who updated: the art of the shortcuts Steam already has,
  // every Steam user's, and shortcuts.vdf untouched.
  void addsArtToExistingShortcuts() {
    QTemporaryDir tmp;
    std::vector<steam::User> users;
    QByteArray vdf_before;
    for (const QString id : {"42", "43"}) {
      const QString config = tmp.path() + "/userdata/" + id + "/config";
      QDir().mkpath(config);
      if (id == "42") {
        std::filesystem::create_directories(config.toStdString());
        const std::string vdf = (config + "/shortcuts.vdf").toStdString();
        steam::AddShortcut(vdf, "Takedawn", "/home/deck/Applications/Takedawn.AppImage", "/home/deck/Applications", "");
        QFile f(QString::fromStdString(vdf));
        QVERIFY(f.open(QIODevice::ReadOnly));
        vdf_before = f.readAll();
      }  // user 43 has no shortcuts at all
      users.push_back({id.toStdString(), config.toStdString(), tmp.path().toStdString()});
    }
    const uint32_t id = steam::AppId("\"/home/deck/Applications/Takedawn.AppImage\"", "Takedawn");
    const QString grid = tmp.path() + "/userdata/42/config/grid";
    QDir().mkpath(grid);
    QVERIFY(Plain(Qt::green).save(grid + "/" + FileName(id, Hero)));  // the player's own hero

    const Art art = Fallback(QImage(":/takedawn/icon-512.png"));
    const Existing e = WriteForExisting(users, art);
    QVERIFY2(e.errors.isEmpty(), qPrintable(e.errors.join("; ")));
    QCOMPARE(e.users, 2);
    QCOMPARE(e.shortcuts, 1);
    QCOMPARE(e.files, int(KindCount));
    QCOMPARE(e.backups, 1);
    for (int k = 0; k < KindCount; ++k) QVERIFY(IsOurs(grid + "/" + FileName(id, Kind(k))));
    QVERIFY(e.Line().contains("Added library art"));
    QVERIFY(!QDir(tmp.path() + "/userdata/43/config").exists("grid"));
    QFile f(tmp.path() + "/userdata/42/config/shortcuts.vdf");
    QVERIFY(f.open(QIODevice::ReadOnly));
    QCOMPARE(f.readAll(), vdf_before);

    QCOMPARE(WriteForExisting({users[1]}, art).Line(),
             QString("Takedawn is not in your Steam library; use the setup window's Add to Steam."));
    QVERIFY(WriteForExisting({}, art).Line().contains("Steam was not found"));
  }

  // The real thing, on the game's own files (not in the repository).
  void composesFromTheGame() {
    const QString game = qEnvironmentVariable("TAKEDAWN_STEAMART_GAME");
    if (game.isEmpty()) QSKIP("TAKEDAWN_STEAMART_GAME names no installed game");
    QString why;
    Art art = FromGame(game, &why);
    QVERIFY2(!art.image[Hero].isNull(), qPrintable(why));
    QCOMPARE(art.source, QString("game"));
    QCOMPARE(art.image[Portrait].size(), QSize(600, 900));
    QCOMPARE(art.image[Wide].size(), QSize(920, 430));
    QCOMPARE(art.image[Hero].size(), QSize(1920, 620));
    QVERIFY(art.image[Logo].hasAlphaChannel());
    QVERIFY(art.image[Logo].width() <= 1280 && art.image[Logo].height() <= 720);
    qInfo() << "made from" << art.used;
    const QString out = qEnvironmentVariable("TAKEDAWN_STEAMART_OUT");
    if (!out.isEmpty()) {
      art.image[Icon] = QImage(":/takedawn/icon-512.png").scaled(256, 256, Qt::KeepAspectRatio, Qt::SmoothTransformation);
      QVERIFY(WriteGridArt(out + "/game", 3141592653u, art).errors.isEmpty());
      QVERIFY(WriteGridArt(out + "/takedawn", 3141592653u, Fallback(QImage(":/takedawn/icon-512.png"))).errors.isEmpty());
    }
  }
};

QTEST_MAIN(SteamArtTest)
#include "steamart_test.moc"
