#include "ui_widgets.h"

#include <QFontMetrics>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QTextOption>

#include "theme.h"

namespace {

QColor Edge(Tone tone) {
  switch (tone) {
    case Tone::Error: return theme::kBad;
    case Tone::Ready: return theme::kEdge;
    default: return theme::kCrimson;
  }
}

QColor WithAlpha(QColor c, int alpha) {
  c.setAlpha(alpha);
  return c;
}

}  // namespace

// ------------------------------------------------------------------ header

HeaderBand::HeaderBand(QWidget* parent) : QWidget(parent) {
  setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
  setFixedHeight(100);
}

void HeaderBand::paintEvent(QPaintEvent*) {
  QPainter p(this);
  p.setRenderHint(QPainter::Antialiasing);
  const qreal w = width(), h = height();
  p.fillRect(rect(), theme::kPlate);

  // One slanted panel under the icon and the title.
  const qreal edge_x = std::min(w * 0.66, w - 250.0);
  const qreal skew = 30;
  QPainterPath panel;
  panel.moveTo(0, 0);
  panel.lineTo(edge_x + skew, 0);
  panel.lineTo(edge_x, h);
  panel.lineTo(0, h);
  panel.closeSubpath();
  QLinearGradient fill(0, 0, edge_x, 0);
  fill.setColorAt(0, theme::kTrack);
  fill.setColorAt(1, theme::kPanel);
  p.fillPath(panel, fill);
  // Its slanted edge, in the tone's colour.
  QPen edge(Edge(tone_), 3);
  edge.setCapStyle(Qt::FlatCap);
  p.setPen(edge);
  p.drawLine(QPointF(edge_x + skew, 0), QPointF(edge_x, h));

  // Two faint speed streaks behind the readout.
  const qreal x0 = edge_x + skew + 14;
  struct Streak { qreal y; qreal length; int alpha; };
  const Streak streaks[] = {{0.16, 0.90, 46}, {0.86, 0.70, 40}};
  for (const Streak& s : streaks) {
    const qreal len = std::max(20.0, (w - x0 - 12) * s.length);
    QLinearGradient g(x0 + len, 0, x0, 0);
    g.setColorAt(0, WithAlpha(Edge(tone_), s.alpha));
    g.setColorAt(1, WithAlpha(Edge(tone_), 0));
    p.setPen(QPen(QBrush(g), 2, Qt::SolidLine, Qt::FlatCap));
    p.drawLine(QPointF(x0, h * s.y), QPointF(x0 + len, h * s.y));
  }
  // The readout: what the installer is doing, right-aligned.
  if (!readout_big_.isEmpty()) {
    const QRectF area(x0 + 6, 10, w - x0 - 6 - 22, h - 25);
    QFont big_font = theme::DisplayFont(15);
    QFont small_font = font();
    small_font.setPointSizeF(small_font.pointSizeF() * 0.95);
    const qreal big_h = QFontMetricsF(big_font).height();
    const qreal small_h = QFontMetricsF(small_font).height();
    const qreal top = area.top() + (area.height() - big_h - small_h - 2) / 2;
    p.setFont(big_font);
    p.setPen(tone_ == Tone::Error ? theme::kWarnText : theme::kLit);
    p.drawText(QRectF(area.left(), top, area.width(), big_h), Qt::AlignRight | Qt::AlignVCenter,
               QFontMetricsF(big_font).elidedText(readout_big_, Qt::ElideRight, area.width()));
    p.setFont(small_font);
    p.setPen(theme::kMuted);
    p.drawText(QRectF(area.left(), top + big_h + 2, area.width(), small_h), Qt::AlignRight | Qt::AlignVCenter,
               QFontMetricsF(small_font).elidedText(readout_small_, Qt::ElideMiddle, area.width()));
  }

  // A thin chevron strip along the foot.
  p.save();
  p.setClipRect(QRectF(0, h - 5, w, 5));
  p.setPen(Qt::NoPen);
  p.setBrush(WithAlpha(Edge(tone_), 55));
  for (qreal x = -10; x < w; x += 16) {
    QPolygonF stripe;
    stripe << QPointF(x, h) << QPointF(x + 7, h) << QPointF(x + 12, h - 5) << QPointF(x + 5, h - 5);
    p.drawPolygon(stripe);
  }
  p.restore();

  // The icon, then the title and the line under it.
  const int icon = 72;
  const QRectF icon_rect(18, (h - icon) / 2 - 2, icon, icon);
  if (!icon_.isNull()) p.drawPixmap(icon_rect.toRect(), icon_);
  const qreal text_x = icon_rect.right() + 18;
  const qreal text_w = std::max(120.0, edge_x - 24 - text_x);
  QFont title_font = theme::DisplayFont(24);
  QFont sub_font = font();
  sub_font.setPointSizeF(sub_font.pointSizeF() * 0.95);
  const QFontMetricsF sub_metrics(sub_font);
  const QRectF sub_bound = sub_metrics.boundingRect(QRectF(0, 0, text_w, 60), Qt::TextWordWrap, subtitle_);
  const qreal title_h = QFontMetricsF(title_font).height();
  const qreal block = title_h + 2 + sub_bound.height();
  const qreal top = (h - 5 - block) / 2;
  p.setFont(title_font);
  p.setPen(theme::kLit);
  p.drawText(QRectF(text_x, top, text_w, title_h), Qt::AlignLeft | Qt::AlignVCenter, title_);
  p.setFont(sub_font);
  p.setPen(theme::kMuted);
  QTextOption opt;
  opt.setWrapMode(QTextOption::WordWrap);
  p.drawText(QRectF(text_x, top + title_h + 2, text_w, sub_bound.height() + 2), subtitle_, opt);
}

// ------------------------------------------------------------ progress bar

HeatProgressBar::HeatProgressBar(QWidget* parent) : QProgressBar(parent) {
  setTextVisible(false);
  setFixedHeight(16);
  timer_.setInterval(60);
  connect(&timer_, &QTimer::timeout, this, [this] {
    offset_ = (offset_ + 2) % 16;
    update();
  });
}

void HeatProgressBar::SetAnimated(bool on) {
  if (on) timer_.start();
  else timer_.stop();
  update();
}

void HeatProgressBar::paintEvent(QPaintEvent*) {
  QPainter p(this);
  p.setRenderHint(QPainter::Antialiasing);
  const qreal w = width() - 1, h = height() - 1;
  const qreal slant = 5;
  QPainterPath track;
  track.moveTo(slant, 0.5);
  track.lineTo(w, 0.5);
  track.lineTo(w - slant, h);
  track.lineTo(0.5, h);
  track.closeSubpath();
  p.fillPath(track, theme::kField);
  p.setPen(QPen(theme::kBorder, 1));
  p.drawPath(track);

  const qreal range = std::max(1, maximum() - minimum());
  const qreal share = std::clamp((value() - minimum()) / range, 0.0, 1.0);
  if (share <= 0) return;
  p.save();
  p.setClipPath(track);
  const qreal fill_w = w * share;
  QLinearGradient g(0, 0, w, 0);
  if (tone_ == Tone::Error) {
    g.setColorAt(0, theme::kNotice);
    g.setColorAt(1, theme::kBad);
  } else {
    g.setColorAt(0, theme::kFillDim);
    g.setColorAt(0.5, theme::kEdge);
    g.setColorAt(1, theme::kEntry);
  }
  p.fillRect(QRectF(0, 0, fill_w, h + 1), g);
  if (timer_.isActive() && fill_w > 12) {  // faint stripes sliding with the fill
    p.setPen(QPen(WithAlpha(theme::kLit, 34), 4));
    for (qreal x = -16 + offset_; x < fill_w; x += 16) p.drawLine(QPointF(x, h + 2), QPointF(x + h, -1));
  }
  p.setPen(QPen(WithAlpha(theme::kLit, 110), 2));  // the bright front edge
  p.drawLine(QPointF(fill_w - 1, 1), QPointF(fill_w - 1, h));
  p.restore();
}

// -------------------------------------------------------------- step glyph

StepGlyph::StepGlyph(QWidget* parent) : QWidget(parent) {
  setFixedSize(22, 22);
  timer_.setInterval(40);
  connect(&timer_, &QTimer::timeout, this, [this] {
    angle_ = (angle_ + 22) % 360;
    update();
  });
}

void StepGlyph::SetState(State state) {
  if (state == state_) return;
  state_ = state;
  if (state == State::Running) timer_.start();
  else timer_.stop();
  update();
}

void StepGlyph::paintEvent(QPaintEvent*) {
  QPainter p(this);
  p.setRenderHint(QPainter::Antialiasing);
  const QRectF r(4, 4, 14, 14);
  switch (state_) {
    case State::Pending:
      p.setPen(QPen(theme::kFillDim, 1.6));
      p.drawEllipse(r);
      break;
    case State::Running: {
      p.setPen(QPen(WithAlpha(theme::kEdge, 70), 2.6));
      p.drawEllipse(r);
      QPen arc(theme::kEntry, 2.8);
      arc.setCapStyle(Qt::RoundCap);
      p.setPen(arc);
      p.drawArc(r, -angle_ * 16, 100 * 16);
      break;
    }
    case State::Done: {
      QPen pen(theme::kOk, 2.2);
      pen.setCapStyle(Qt::RoundCap);
      pen.setJoinStyle(Qt::RoundJoin);
      p.setPen(pen);
      QPainterPath tick;
      tick.moveTo(5.5, 11.5);
      tick.lineTo(9.5, 15.5);
      tick.lineTo(16.5, 6.5);
      p.drawPath(tick);
      break;
    }
    case State::Warning: {  // an optional step that did not work: an amber triangle, not a cross
      QPen pen(theme::kWarn, 2.0);
      pen.setJoinStyle(Qt::RoundJoin);
      pen.setCapStyle(Qt::RoundCap);
      p.setPen(pen);
      QPainterPath tri;
      tri.moveTo(11, 4.5);
      tri.lineTo(18, 16.5);
      tri.lineTo(4, 16.5);
      tri.closeSubpath();
      p.drawPath(tri);
      p.drawLine(QPointF(11, 9), QPointF(11, 12.6));
      p.drawPoint(QPointF(11, 14.6));
      break;
    }
    case State::Failed: {
      QPen pen(theme::kDanger, 2.4);
      pen.setCapStyle(Qt::RoundCap);
      p.setPen(pen);
      p.drawLine(QPointF(6, 6), QPointF(16, 16));
      p.drawLine(QPointF(16, 6), QPointF(6, 16));
      break;
    }
  }
}
