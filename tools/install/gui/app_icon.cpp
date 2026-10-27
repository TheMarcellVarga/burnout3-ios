#include "app_icon.h"

#include <QImage>

namespace {
const int kSizes[] = {16, 32, 64, 128, 256, 512};
QString Resource(int px) { return QString(":/takedawn/icon-%1.png").arg(px); }
}  // namespace

QIcon AppIcon() {
  QIcon icon;
  for (int px : kSizes) icon.addFile(Resource(px), QSize(px, px));
  return icon;
}

QPixmap AppIconPixmap(int logical, qreal dpr) {
  const int wanted = qRound(logical * dpr);
  int source = kSizes[sizeof kSizes / sizeof kSizes[0] - 1];
  for (int px : kSizes) {
    if (px >= wanted) {
      source = px;
      break;
    }
  }
  QImage image(Resource(source));
  if (image.isNull()) return {};
  QPixmap pixmap = QPixmap::fromImage(image.scaled(wanted, wanted, Qt::KeepAspectRatio, Qt::SmoothTransformation));
  pixmap.setDevicePixelRatio(dpr);
  return pixmap;
}
