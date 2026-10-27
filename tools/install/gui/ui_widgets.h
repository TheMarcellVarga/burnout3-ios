#pragma once

#include <QPixmap>
#include <QProgressBar>
#include <QTimer>
#include <QWidget>

// How a state reads: normal (the crimson edge), failed (red), ready to play (steel blue).
enum class Tone { Normal, Error, Ready };

// The window's top band: the icon, the title in the display face, a line under it,
// on a dark band with one slanted panel, a few faint speed streaks and a thin
// chevron strip along its foot. Drawn in code; the colours follow the tone.
class HeaderBand : public QWidget {
 public:
  explicit HeaderBand(QWidget* parent = nullptr);
  void SetTitle(const QString& title) { title_ = title; update(); }
  void SetSubtitle(const QString& text) { subtitle_ = text; update(); }
  void SetIcon(const QPixmap& icon) { icon_ = icon; update(); }
  void SetTone(Tone tone) { tone_ = tone; update(); }
  // The compact readout on the right: a state in capitals and a line under it.
  void SetReadout(const QString& big, const QString& small) { readout_big_ = big; readout_small_ = small; update(); }
  QSize sizeHint() const override { return QSize(600, 100); }
  QSize minimumSizeHint() const override { return QSize(300, 100); }

 protected:
  void paintEvent(QPaintEvent*) override;

 private:
  QString title_, subtitle_, readout_big_, readout_small_;
  QPixmap icon_;
  Tone tone_ = Tone::Normal;
};

// A progress bar that fills with the steel-blue gradient and has slanted ends. Same API as QProgressBar; faint stripes slide along the fill while
// SetAnimated(true).
class HeatProgressBar : public QProgressBar {
 public:
  explicit HeatProgressBar(QWidget* parent = nullptr);
  void SetTone(Tone tone) { tone_ = tone; update(); }
  void SetAnimated(bool on);
  QSize sizeHint() const override { return QSize(200, 16); }

 protected:
  void paintEvent(QPaintEvent*) override;

 private:
  Tone tone_ = Tone::Normal;
  QTimer timer_;
  int offset_ = 0;
};

// The state mark in front of a step: an open ring, a turning arc, a check, a cross.
class StepGlyph : public QWidget {
 public:
  enum class State { Pending, Running, Done, Failed, Warning };
  explicit StepGlyph(QWidget* parent = nullptr);
  void SetState(State state);
  QSize sizeHint() const override { return QSize(22, 22); }

 protected:
  void paintEvent(QPaintEvent*) override;

 private:
  State state_ = State::Pending;
  QTimer timer_;
  int angle_ = 0;
};
