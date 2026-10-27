#include "steam_artwork.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QImageReader>
#include <QImageWriter>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <algorithm>
#include <cstring>

namespace steamart {

namespace {

uint32_t U32(const std::string& d, size_t at) {
  uint32_t v = 0;
  for (int i = 0; i < 4; ++i) v |= uint32_t(static_cast<unsigned char>(d[at + i])) << (8 * i);
  return v;
}

// ── the game's textures ─────────────────────────────────────────────────────────
// A dictionary: u32 0x543C0000, u32 (a hash), u32 count, u32 the table's offset; the
// table has a (u64 index, u64 offset) per texture. A texture is the Xbox's D3D
// resource header (0x80 bytes: +0x04 the pixels' offset from it, +0x0C the format
// register, +0x10 the size register of a linear one, +0x38 / +0x3C width and height,
// +0x48 the name), then its pixels; an 8-bit palette image is followed by its
// palette's header (0x40 bytes) and 256 colours (B, G, R, A).
constexpr uint32_t kTxdMagic = 0x543C0000u;
constexpr uint32_t kPaletteCommon = 0x00030001u;
enum : uint32_t { kFmtP8 = 0x0B, kFmtDxt1 = 0x0C, kFmtDxt3 = 0x0E, kFmtDxt5 = 0x0F };

void C565(uint16_t c, int out[3]) {
  out[0] = ((c >> 11) & 31) * 255 / 31;
  out[1] = ((c >> 5) & 63) * 255 / 63;
  out[2] = (c & 31) * 255 / 31;
}

// DXT1/3/5 blocks, in rows, to `img` (ARGB32, w and h multiples of 4).
void DecodeDxt(const unsigned char* src, uint32_t format, QImage* img) {
  const int w = img->width(), h = img->height();
  for (int by = 0; by < h; by += 4) {
    for (int bx = 0; bx < w; bx += 4) {
      int alpha[16];
      std::fill(alpha, alpha + 16, 255);
      if (format == kFmtDxt5) {
        const int a0 = src[0], a1 = src[1];
        uint64_t bits = 0;
        for (int i = 0; i < 6; ++i) bits |= uint64_t(src[2 + i]) << (8 * i);
        int level[8] = {a0, a1};
        if (a0 > a1) {
          for (int i = 0; i < 6; ++i) level[2 + i] = ((6 - i) * a0 + (i + 1) * a1) / 7;
        } else {
          for (int i = 0; i < 4; ++i) level[2 + i] = ((4 - i) * a0 + (i + 1) * a1) / 5;
          level[6] = 0;
          level[7] = 255;
        }
        for (int i = 0; i < 16; ++i) alpha[i] = level[(bits >> (3 * i)) & 7];
        src += 8;
      } else if (format == kFmtDxt3) {
        for (int i = 0; i < 16; ++i) alpha[i] = ((src[i / 2] >> (4 * (i & 1))) & 15) * 17;
        src += 8;
      }
      const uint16_t c0 = uint16_t(src[0] | src[1] << 8), c1 = uint16_t(src[2] | src[3] << 8);
      const uint32_t bits = uint32_t(src[4]) | uint32_t(src[5]) << 8 | uint32_t(src[6]) << 16 | uint32_t(src[7]) << 24;
      src += 8;
      int c[4][3];
      C565(c0, c[0]);
      C565(c1, c[1]);
      const bool four = format != kFmtDxt1 || c0 > c1;
      for (int k = 0; k < 3; ++k) {
        c[2][k] = four ? (2 * c[0][k] + c[1][k]) / 3 : (c[0][k] + c[1][k]) / 2;
        c[3][k] = four ? (c[0][k] + 2 * c[1][k]) / 3 : 0;
      }
      for (int i = 0; i < 16; ++i) {
        const int k = (bits >> (2 * i)) & 3;
        const int a = (!four && k == 3) ? 0 : alpha[i];
        reinterpret_cast<QRgb*>(img->scanLine(by + (i >> 2)))[bx + (i & 3)] = qRgba(c[k][0], c[k][1], c[k][2], a);
      }
    }
  }
}

// The Xbox's swizzle of a power-of-two texture: the bits of x and y interleaved, from
// the lowest, while each still has some.
void SwizzleTables(int w, int h, std::vector<uint32_t>* xs, std::vector<uint32_t>* ys) {
  std::vector<uint32_t> xbit, ybit;
  uint32_t bit = 1;
  for (int mx = 1, my = 1; mx < w || my < h;) {
    if (mx < w) xbit.push_back(bit), bit <<= 1, mx <<= 1;
    if (my < h) ybit.push_back(bit), bit <<= 1, my <<= 1;
  }
  xs->assign(w, 0);
  ys->assign(h, 0);
  for (int x = 0; x < w; ++x)
    for (size_t i = 0; i < xbit.size(); ++i)
      if (x >> i & 1) (*xs)[x] |= xbit[i];
  for (int y = 0; y < h; ++y)
    for (size_t i = 0; i < ybit.size(); ++i)
      if (y >> i & 1) (*ys)[y] |= ybit[i];
}

std::string ReadAll(const QString& path) {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return {};
  const QByteArray b = f.readAll();
  return std::string(b.constData(), size_t(b.size()));
}

// `name` in `dir`, whatever its case (the disc's names are mixed case).
QString FindFile(const QString& dir, const QString& name) {
  const QString exact = QDir(dir).filePath(name);
  if (QFileInfo::exists(exact)) return exact;
  for (const QString& e : QDir(dir).entryList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot))
    if (e.compare(name, Qt::CaseInsensitive) == 0) return QDir(dir).filePath(e);
  return {};
}

// ── composing ─────────────────────────────────────────────────────────────────────
// `src` scaled to cover `size`, cut around (fx, fy) (0..1 of the scaled picture).
QImage Cover(const QImage& src, QSize size, double fx, double fy) {
  const double s = std::max(double(size.width()) / src.width(), double(size.height()) / src.height());
  const QImage big = src.scaled(qRound(src.width() * s), qRound(src.height() * s), Qt::IgnoreAspectRatio,
                                Qt::SmoothTransformation);
  const int x = std::clamp(qRound(big.width() * fx - size.width() / 2.0), 0, big.width() - size.width());
  const int y = std::clamp(qRound(big.height() * fy - size.height() / 2.0), 0, big.height() - size.height());
  return big.copy(x, y, size.width(), size.height()).convertToFormat(QImage::Format_ARGB32);
}

// `img` drawn as large as fits in `box`, centred, its proportions kept.
void DrawFitted(QPainter* p, const QImage& img, const QRectF& box) {
  const double s = std::min(box.width() / img.width(), box.height() / img.height());
  const QSizeF sz(img.width() * s, img.height() * s);
  p->drawImage(QRectF(box.center().x() - sz.width() / 2, box.center().y() - sz.height() / 2, sz.width(), sz.height()),
               img);
}

// A band of shade from `from` (alpha a0) to `to` (alpha 0), for a logo to stand on.
void Shade(QPainter* p, QRect area, QPointF from, QPointF to, int a0) {
  QLinearGradient g(from, to);
  g.setColorAt(0, QColor(0, 0, 0, a0));
  g.setColorAt(1, QColor(0, 0, 0, 0));
  p->fillRect(area, g);
}

// The part of `img` that is not (almost) transparent.
QImage Trim(const QImage& img) {
  int x0 = img.width(), y0 = img.height(), x1 = -1, y1 = -1;
  for (int y = 0; y < img.height(); ++y) {
    const QRgb* row = reinterpret_cast<const QRgb*>(img.constScanLine(y));
    for (int x = 0; x < img.width(); ++x) {
      if (qAlpha(row[x]) > 8) {
        x0 = std::min(x0, x), x1 = std::max(x1, x);
        y0 = std::min(y0, y), y1 = std::max(y1, y);
      }
    }
  }
  if (x1 < 0) return img;
  return img.copy(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

// Takedawn's colours (assets/icon/takedawn.svg).
const QColor kNavyTop(0x1c, 0x26, 0x34), kNavyBottom(0x0b, 0x0f, 0x16), kGlow(0xaf, 0xd2, 0xff), kGridLine(0x95, 0xc0, 0xe1),
    kWhite(0xf4, 0xf8, 0xff);

// The icon's navy with its faint grid and glow, `size` large.
QImage Backdrop(QSize size, QPointF glow_at) {
  QImage img(size, QImage::Format_ARGB32);
  QPainter p(&img);
  QLinearGradient bg(0, 0, 0, size.height());
  bg.setColorAt(0, kNavyTop);
  bg.setColorAt(1, kNavyBottom);
  p.fillRect(img.rect(), bg);
  QColor line = kGridLine;
  line.setAlphaF(0.07);
  p.setPen(QPen(line, 2));
  const int step = std::max(32, std::min(size.width(), size.height()) / 12);
  for (int x = step; x < size.width(); x += step) p.drawLine(x, 0, x, size.height());
  for (int y = step; y < size.height(); y += step) p.drawLine(0, y, size.width(), y);
  QRadialGradient glow(glow_at, std::max(size.width(), size.height()) * 0.55);
  QColor g0 = kGlow, g1 = kGlow;
  g0.setAlphaF(0.35);
  g1.setAlphaF(0);
  glow.setColorAt(0, g0);
  glow.setColorAt(1, g1);
  p.fillRect(img.rect(), glow);
  return img;
}

// "TAKEDAWN" in a plain bold face, as wide as `width` at most and `height` tall at most.
void DrawName(QPainter* p, const QRectF& box, Qt::Alignment align) {
  QFont f = QFontDatabase::systemFont(QFontDatabase::GeneralFont);  // the system's plain face
  f.setWeight(QFont::Black);
  f.setLetterSpacing(QFont::PercentageSpacing, 104);
  f.setPixelSize(std::max(8, int(box.height())));
  const QString name = "TAKEDAWN";
  const double w = QFontMetricsF(f).horizontalAdvance(name);
  if (w > box.width()) f.setPixelSize(std::max(8, int(f.pixelSize() * box.width() / w)));
  p->setFont(f);
  p->setPen(kWhite);
  p->drawText(box, align | Qt::AlignVCenter, name);
}

}  // namespace

QString FileName(uint32_t app_id, Kind kind) {
  static const char* const suffix[KindCount] = {"p.png", ".png", "_hero.png", "_logo.png", "_icon.png"};
  return QString::number(app_id) + suffix[kind];
}

QSize TargetSize(Kind kind) {
  switch (kind) {
    case Portrait: return {600, 900};
    case Wide: return {920, 430};
    case Hero: return {1920, 620};
    case Logo: return {1280, 720};
    case Icon: return {256, 256};
    default: return {};
  }
}

bool DecodeTexture(const std::string& d, const std::string& name, QImage* out, std::string* why) {
  if (d.size() < 16 || U32(d, 0) != kTxdMagic) {
    *why = "not a texture dictionary";
    return false;
  }
  const uint32_t count = U32(d, 8), table = U32(d, 12);
  if (count > 100000 || uint64_t(table) + uint64_t(count) * 16 > d.size()) {
    *why = "a texture table past the end";
    return false;
  }
  for (uint32_t i = 0; i < count; ++i) {
    const uint64_t off = U32(d, table + 16 * i + 8);
    if (off + 0x80 > d.size()) continue;
    char raw[33] = {};
    std::memcpy(raw, d.data() + off + 0x48, 32);
    if (name != raw) continue;
    const uint32_t reg = U32(d, off + 0x0C), linear = U32(d, off + 0x10);
    const uint32_t format = (reg >> 8) & 0xFF, dims = (reg >> 4) & 0xF;
    const int w = 1 << ((reg >> 20) & 0xF), h = 1 << ((reg >> 24) & 0xF);
    if (linear != 0 || dims != 2 || int(U32(d, off + 0x38)) != w || int(U32(d, off + 0x3C)) != h || w < 4 || h < 4 ||
        w > 4096 || h > 4096) {
      *why = name + ": not a 2D power-of-two texture";
      return false;
    }
    const uint64_t px = off + U32(d, off + 0x04);
    QImage img(w, h, QImage::Format_ARGB32);
    if (format == kFmtDxt1 || format == kFmtDxt3 || format == kFmtDxt5) {
      const uint64_t bytes = uint64_t(w) * h / (format == kFmtDxt1 ? 2 : 1);
      if (px + bytes > d.size()) {
        *why = name + ": cut short";
        return false;
      }
      DecodeDxt(reinterpret_cast<const unsigned char*>(d.data() + px), format, &img);
    } else if (format == kFmtP8) {
      const uint64_t pal_head = px + uint64_t(w) * h, pal = pal_head + 0x40;
      if (pal + 1024 > d.size() || U32(d, pal_head) != kPaletteCommon) {
        *why = name + ": no palette after the pixels";
        return false;
      }
      std::vector<uint32_t> xs, ys;
      SwizzleTables(w, h, &xs, &ys);
      const unsigned char* src = reinterpret_cast<const unsigned char*>(d.data());
      for (int y = 0; y < h; ++y) {
        QRgb* row = reinterpret_cast<QRgb*>(img.scanLine(y));
        for (int x = 0; x < w; ++x) {
          const unsigned char* c = src + pal + 4 * src[px + xs[x] + ys[y]];
          row[x] = qRgba(c[2], c[1], c[0], c[3]);
        }
      }
    } else {
      char msg[96];
      std::snprintf(msg, sizeof msg, ": format 0x%02X is not read here", unsigned(format));
      *why = name + msg;
      return false;
    }
    *out = img;
    return true;
  }
  *why = name + ": not in the dictionary";
  return false;
}

std::string LoadScreenDictionary(const std::string& a, const std::string& name) {
  // u32 count, u32 0, then per dictionary (u64 hash, u32 size, u32 offset); the
  // dictionaries follow from the next 2 KiB boundary.
  if (a.size() < 8) return {};
  const uint64_t count = U32(a, 0);
  if (count == 0 || count > 10000 || 8 + count * 16 > a.size()) return {};
  const uint64_t base = (8 + count * 16 + 0x7FF) & ~uint64_t(0x7FF);
  for (uint64_t i = 0; i < count; ++i) {
    const uint64_t size = U32(a, 8 + 16 * i + 8), off = base + U32(a, 8 + 16 * i + 12);
    if (size < 0x100 || off + size > a.size()) continue;
    const std::string dict = a.substr(off, size);
    if (dict.size() < 0x10 + 16 || U32(dict, 0) != kTxdMagic || U32(dict, 8) != 1) continue;
    const uint64_t table = U32(dict, 12);
    if (table + 16 > dict.size()) continue;
    const uint64_t tex = U32(dict, table + 8);
    if (tex + 0x68 > dict.size()) continue;
    char raw[33] = {};
    std::memcpy(raw, dict.data() + tex + 0x48, 32);
    if (name == raw) return dict;
  }
  return {};
}

Art FromGame(const QString& game_dir, QString* why) {
  Art art;
  art.source = "game";
  const QString data = FindFile(game_dir, "Data");
  const std::string frontend = data.isEmpty() ? std::string() : ReadAll(FindFile(data, "Frontend.txd"));
  const std::string screens = data.isEmpty() ? std::string() : ReadAll(FindFile(data, "LoadScrn.bin"));
  if (frontend.empty() || screens.empty()) {
    *why = "no Data/Frontend.txd or Data/LoadScrn.bin under " + game_dir;
    return art;
  }
  QImage logo, action, pack;
  std::string err;
  const auto shot = [&](const char* name, QImage* out) {
    const std::string dict = LoadScreenDictionary(screens, name);
    if (dict.empty()) {
      err = std::string(name) + ": not in LoadScrn.bin";
      return false;
    }
    if (!DecodeTexture(dict, name, out, &err)) return false;
    // A loading screen fills the 4:3 screen: 512 x 256 texels shown 512 x 384.
    *out = out->scaled(out->width(), out->width() * 3 / 4, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    art.used << QString("Data/LoadScrn.bin:") + name;
    return true;
  };
  if (!DecodeTexture(frontend, "titlescreen_logo", &logo, &err) || !shot("GNRL0002", &action) ||
      !shot("GNRL0001", &pack)) {
    *why = QString::fromStdString(err);
    art.used.clear();
    return art;
  }
  art.used.prepend("Data/Frontend.txd:titlescreen_logo");
  logo = Trim(logo);
  // Twice its size, as large as the title screen draws it on a 1080p screen.
  const QImage big_logo = logo.scaled(logo.size() * 2, Qt::KeepAspectRatio, Qt::SmoothTransformation);

  // The banner: the takedown with the sparks; Steam puts the logo on it itself.
  art.image[Hero] = Cover(action, TargetSize(Hero), 0.5, 0.5);

  // Portrait: the white car in the sparks, the logo on a shade at the top.
  {
    QImage img = Cover(action, TargetSize(Portrait), 0.56, 0.5);
    QPainter p(&img);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    Shade(&p, QRect(0, 0, 600, 420), QPointF(0, 0), QPointF(0, 420), 210);
    DrawFitted(&p, big_logo, QRectF(36, 48, 528, 260));
    art.image[Portrait] = img;
  }
  // Wide: the two cars, the logo on a shade at the bottom.
  {
    QImage img = Cover(pack, TargetSize(Wide), 0.5, 0.45);
    QPainter p(&img);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    Shade(&p, QRect(0, 180, 920, 250), QPointF(0, 430), QPointF(0, 180), 220);
    DrawFitted(&p, big_logo, QRectF(160, 250, 600, 165));
    art.image[Wide] = img;
  }
  art.image[Logo] = big_logo;
  return art;
}

Art Fallback(const QImage& icon_in) {
  Art art;
  art.source = "takedawn";
  const QImage icon = icon_in.convertToFormat(QImage::Format_ARGB32);
  const auto paint = [&](QImage* img, auto&& draw) {
    QPainter p(img);
    p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    draw(p);
  };
  art.image[Portrait] = Backdrop(TargetSize(Portrait), QPointF(300, 330));
  paint(&art.image[Portrait], [&](QPainter& p) {
    DrawFitted(&p, icon, QRectF(120, 150, 360, 360));
    DrawName(&p, QRectF(50, 600, 500, 92), Qt::AlignHCenter);
  });
  art.image[Wide] = Backdrop(TargetSize(Wide), QPointF(220, 215));
  paint(&art.image[Wide], [&](QPainter& p) {
    DrawFitted(&p, icon, QRectF(70, 75, 280, 280));
    DrawName(&p, QRectF(390, 150, 480, 130), Qt::AlignLeft);
  });
  art.image[Hero] = Backdrop(TargetSize(Hero), QPointF(1500, 260));
  paint(&art.image[Hero], [&](QPainter& p) {
    p.setOpacity(0.18);
    DrawFitted(&p, icon, QRectF(1280, 40, 540, 540));
  });
  art.image[Logo] = QImage(QSize(1280, 360), QImage::Format_ARGB32);
  art.image[Logo].fill(Qt::transparent);
  paint(&art.image[Logo], [&](QPainter& p) {
    DrawFitted(&p, icon, QRectF(0, 20, 320, 320));
    DrawName(&p, QRectF(350, 90, 920, 180), Qt::AlignLeft);
  });
  art.image[Logo] = Trim(art.image[Logo]);
  art.image[Icon] = icon.scaled(TargetSize(Icon), Qt::KeepAspectRatio, Qt::SmoothTransformation);
  return art;
}

Art ForShortcut(const QString& game_dir, const QImage& icon, QString* note) {
  QString why = "no data folder";
  Art art;
  if (!game_dir.isEmpty()) art = FromGame(game_dir, &why);
  if (art.image[Hero].isNull()) {
    *note = "library art from Takedawn's own icon: the game's pictures were not usable (" + why + ")";
    return Fallback(icon);
  }
  *note = "library art from the game's own pictures: " + art.used.join(", ");
  art.image[Icon] = icon.scaled(TargetSize(Icon), Qt::KeepAspectRatio, Qt::SmoothTransformation);
  return art;
}

bool IsOurs(const QString& path) {
  QImageReader r(path, "png");
  return r.canRead() && r.text("Software") == QLatin1String(kMarker);
}

Written WriteGridArt(const QString& grid_dir, uint32_t app_id, const Art& art) {
  Written out;
  if (!QDir().mkpath(grid_dir)) {
    out.errors << "cannot make " + grid_dir;
    return out;
  }
  const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
  for (int k = 0; k < KindCount; ++k) {
    if (art.image[k].isNull()) continue;
    const QString path = QDir(grid_dir).filePath(FileName(app_id, Kind(k)));
    const QString tmp = path + ".takedawn-tmp";
    QFile::remove(tmp);
    QImageWriter w(tmp, "png");
    w.setText("Software", kMarker);
    w.setText("Comment", "Steam library art of the Takedawn shortcut, made by its setup: " + art.source);
    if (!w.write(art.image[k])) {
      out.errors << "cannot write " + tmp + ": " + w.errorString();
      QFile::remove(tmp);
      continue;
    }
    if (QFileInfo::exists(path)) {
      if (IsOurs(path)) {
        QFile::remove(path);
      } else {
        const QString backup = path + ".takedawn-backup-" + stamp;
        if (!QFile::rename(path, backup)) {
          out.errors << "cannot move " + path + " out of the way; left as it was";
          QFile::remove(tmp);
          continue;
        }
        out.backups << backup;
      }
    }
    if (!QFile::rename(tmp, path)) {
      out.errors << "cannot replace " + path;
      QFile::remove(tmp);
      continue;
    }
    QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    out.files << path;
  }
  return out;
}

int RemoveGridArt(const QString& grid_dir, uint32_t app_id) {
  int removed = 0;
  const QDir dir(grid_dir);
  for (int k = 0; k < KindCount; ++k) {
    const QString name = FileName(app_id, Kind(k));
    const QString path = dir.filePath(name);
    if (QFileInfo::exists(path)) {
      if (!IsOurs(path)) continue;  // someone else's since: theirs to keep
      if (!QFile::remove(path)) continue;
      ++removed;
    }
    QStringList backups = dir.entryList({name + ".takedawn-backup-*"}, QDir::Files, QDir::Name);
    if (!backups.isEmpty()) QFile::rename(dir.filePath(backups.last()), path);
  }
  return removed;
}

QString Existing::Line() const {
  if (users == 0) return "Steam was not found here, so there is no library to add art to.";
  if (shortcuts == 0) return "Takedawn is not in your Steam library; use the setup window's Add to Steam.";
  if (files == 0)
    return "Steam library art could not be written: " + (errors.isEmpty() ? QString("see the log") : errors.first());
  QString line = QString("Added library art to %1 (%2 files).")
                     .arg(shortcuts == 1 ? QString("Takedawn") : QString("%1 Takedawn shortcuts").arg(shortcuts))
                     .arg(files);
  if (backups > 0) line += " Your earlier pictures were kept as .takedawn-backup files.";
  if (!errors.isEmpty()) line += " Some files failed; see the log.";
  return line;
}

Existing WriteForExisting(const std::vector<steam::User>& users, const Art& art) {
  Existing out;
  for (const steam::User& u : users) {
    ++out.users;
    const QString vdf = QDir(QString::fromStdString(u.config)).filePath("shortcuts.vdf");
    std::vector<steam::Found> found;
    try {
      found = steam::FindTakedawn(vdf.toStdString());
    } catch (const std::exception& e) {
      out.errors << vdf + ": " + QString::fromUtf8(e.what());
      out.log << "[steam] " + vdf + " cannot be read (" + QString::fromUtf8(e.what()) + "); left alone";
      continue;
    }
    const QString grid = QDir(QString::fromStdString(u.config)).filePath("grid");
    for (const steam::Found& f : found) {
      ++out.shortcuts;
      out.log << QString("[steam] user %1: \"%2\" (%3), app id %4")
                     .arg(QString::fromStdString(u.id), QString::fromStdString(f.name), QString::fromStdString(f.exe))
                     .arg(f.app_id);
      const Written w = WriteGridArt(grid, f.app_id, art);
      for (const QString& file : w.files) out.log << "[steam] wrote " + file;
      for (const QString& b : w.backups) out.log << "[steam] kept the earlier file as " + b;
      for (const QString& e : w.errors) out.log << "[steam] library art: " + e;
      out.files += w.files.size();
      out.backups += w.backups.size();
      out.errors << w.errors;
    }
  }
  return out;
}

}  // namespace steamart
