#pragma once

#include <QFontMetrics>
#include <QLabel>
#include <QPainter>

// A one-line label that shortens its text in the middle ("/Users/…/burnout3")
// instead of widening the window; the full text is the tooltip.
class ElidedLabel : public QLabel {
 public:
  using QLabel::QLabel;

  void SetFullText(const QString& text) {
    full_ = text;
    setToolTip(text.size() > 60 ? text : QString());
    update();
  }
  const QString& FullText() const { return full_; }

  QSize minimumSizeHint() const override { return QSize(40, QLabel::minimumSizeHint().height()); }
  QSize sizeHint() const override { return QSize(200, QLabel::sizeHint().height()); }

 protected:
  void paintEvent(QPaintEvent*) override {
    QPainter p(this);
    p.setPen(palette().color(QPalette::PlaceholderText));
    p.drawText(rect(), int(alignment()) | Qt::AlignVCenter,
               fontMetrics().elidedText(full_, Qt::ElideMiddle, width()));
  }

 private:
  QString full_;
};
