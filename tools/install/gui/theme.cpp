#include "theme.h"

#include <QApplication>
#include <QFile>
#include <QFontDatabase>
#include <QLabel>
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QPalette>
#include <QTemporaryDir>
#include <QStyle>
#include <QStyleFactory>
#include <QWidget>

namespace theme {

// The overlay's table (k_theme_game), by name.
const QColor kPanel(0x16, 0x1d, 0x26);
const QColor kEdge(0x5a, 0x99, 0xc0);
const QColor kRule(0x3f, 0x4d, 0x5d);
const QColor kCrimson(0xc4, 0x1c, 0x1c);
const QColor kEntry(0xac, 0xd4, 0xfc);
const QColor kLit(0xff, 0xff, 0xff);
const QColor kDim(0x82, 0x96, 0xab);
const QColor kAction(0xd4, 0xe4, 0xfc);
const QColor kInk(0x0f, 0x13, 0x19);
const QColor kTrack(0x2f, 0x39, 0x42);
const QColor kFillDim(0x4a, 0x5a, 0x6a);
const QColor kPlate(0x11, 0x15, 0x1a);
const QColor kWarnText(0xff, 0x8a, 0x80);
const QColor kNotice(0x94, 0x0c, 0x14);
const QColor kGood(0x5c, 0xb0, 0x1a);
const QColor kCaution(0xe8, 0xc8, 0x46);
const QColor kBad(0xe8, 0x48, 0x40);

// The roles, each one of the above.
const QColor kBackground = kInk;
const QColor kPanelRaised = kTrack;
const QColor kField = kPlate;
const QColor kBorder = kRule;
const QColor kText = kAction;
const QColor kMuted = kDim;
const QColor kAccent = kCrimson;
const QColor kOnAccent = kLit;
const QColor kFocus = kEdge;
const QColor kDanger = kBad;
const QColor kOk = kGood;
const QColor kWarn = kCaution;

QString Css(const QColor& c) { return c.name(); }
QString Css(const QColor& c, int alpha) {
  return QString("rgba(%1, %2, %3, %4)").arg(c.red()).arg(c.green()).arg(c.blue()).arg(alpha);
}

namespace {

// A step between two of the named colours (t = 0: a, 1: b).
QColor Mix(const QColor& a, const QColor& b, qreal t) {
  return QColor(qRound(a.red() + (b.red() - a.red()) * t), qRound(a.green() + (b.green() - a.green()) * t),
                qRound(a.blue() + (b.blue() - a.blue()) * t));
}

// The tick of a checked box, drawn here and written to a temporary file the style
// sheet can point at (a style sheet image must be a file). Empty if it cannot be.
QTemporaryDir& TickDir() {
  static QTemporaryDir dir;
  return dir;
}

QString TickImage() {
  QTemporaryDir& dir = TickDir();
  if (!dir.isValid()) return QString();
  const QString path = dir.filePath("tick.png");
  if (!QFile::exists(path)) {
    QImage image(40, 40, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    QPen pen(kInk, 5.2);
    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    p.setPen(pen);
    QPainterPath tick;
    tick.moveTo(10, 21);
    tick.lineTo(17, 28);
    tick.lineTo(30, 12);
    p.drawPath(tick);
    p.end();
    if (!image.save(path, "PNG")) return QString();
  }
  return path;
}

QString StyleSheet() {
  // Derived steps, so the sheet below names no number of its own.
  const QColor hover = Mix(kTrack, kEdge, 0.22), pressed = Mix(kTrack, kInk, 0.5);
  const QColor off_text = Mix(kDim, kPanel, 0.45), off_edge = Mix(kRule, kPanel, 0.5);
  const QColor crimson_hi = Mix(kCrimson, kLit, 0.14), crimson_lo = Mix(kCrimson, kInk, 0.22);
  QString css = QString(R"CSS(
QToolTip { background: %TRACK%; color: %TEXT%; border: 1px solid %RULE%; padding: 4px 6px; }

QPlainTextEdit { background: %PLATE%; color: %ENTRY%; border: 1px solid %RULE%; border-radius: 5px;
                 padding: 4px 8px; selection-background-color: %EDGE%; selection-color: %INK%; }
QPlainTextEdit:focus { border: 1px solid %EDGE%; }

QPushButton { background: %TRACK%; color: %TEXT%; border: 1px solid %RULE%; border-radius: 6px;
              padding: 8px 18px; min-height: 22px; }
QPushButton:hover { background: %HOVER%; border-color: %EDGE%; }
QPushButton:pressed { background: %PRESSED%; }
QPushButton:focus, QPushButton[padFocus="true"] { border: 2px solid %EDGE%; padding: 7px 17px; }
QPushButton:disabled { background: %PANEL%; color: %OFFTEXT%; border-color: %OFFEDGE%; }
QPushButton[role="primary"] { background: %CRIMSON%; color: %LIT%; border: 1px solid %CRIMSONHI%;
                              font-weight: bold; font-style: italic; }
QPushButton[role="primary"]:hover { background: %CRIMSONHI%; }
QPushButton[role="primary"]:pressed { background: %CRIMSONLO%; }
QPushButton[role="primary"]:focus, QPushButton[role="primary"][padFocus="true"] { border: 3px solid %ENTRY%; padding: 6px 16px; }
QPushButton[role="primary"]:disabled { background: %PANEL%; color: %OFFTEXT%; border-color: %OFFEDGE%; }
QPushButton[role="stop"] { background: transparent; color: %ENTRY%; border: 2px solid %EDGE%; font-weight: bold;
                           font-style: italic; padding: 7px 17px; }
QPushButton[role="stop"]:hover { background: %EDGEWASH%; }
QPushButton[role="stop"]:focus, QPushButton[role="stop"][padFocus="true"] { border: 3px solid %ENTRY%; padding: 6px 16px; }
QPushButton[role="stop"]:disabled { color: %OFFTEXT%; border-color: %OFFEDGE%; }

QToolButton { background: %TRACK%; color: %TEXT%; border: 1px solid %RULE%; border-radius: 5px; padding: 4px 12px;
              min-height: 28px; }
QToolButton:hover { background: %HOVER%; border-color: %EDGE%; }
QToolButton:pressed { background: %PRESSED%; }
QToolButton:focus, QToolButton[padFocus="true"] { border: 2px solid %EDGE%; padding: 3px 11px; }
QToolButton[padFocus="true"] { background: %HOVER%; color: %LIT%; }
QToolButton:disabled { background: %PANEL%; color: %OFFTEXT%; border-color: %OFFEDGE%; }
QToolButton#fold { background: transparent; border: none; border-radius: 4px; padding: 4px 6px; font-weight: bold;
                   font-style: italic; color: %DIM%; }
QToolButton#fold:hover { color: %LIT%; }
QToolButton#fold:focus, QToolButton#fold[padFocus="true"] { border: 2px solid %EDGE%; padding: 2px 4px; color: %LIT%; background: transparent; }

QCheckBox { spacing: 10px; color: %TEXT%; border: 2px solid transparent; border-radius: 5px; padding: 1px 6px 1px 2px; }
QCheckBox:focus, QCheckBox[padFocus="true"] { border-color: %EDGE%; background: %EDGEWASH%; color: %LIT%; }
QCheckBox::indicator { width: 18px; height: 18px; border: 1px solid %FILLDIM%; border-radius: 4px; background: %PLATE%; }
QCheckBox::indicator:hover { border-color: %EDGE%; }
QCheckBox::indicator:focus { border: 2px solid %EDGE%; }
QCheckBox::indicator:checked { image: url(%TICK%); background: %EDGE%; border-color: %ENTRY%; }
QCheckBox::indicator:disabled { background: %PANEL%; border-color: %OFFEDGE%; }
QCheckBox:disabled { color: %OFFTEXT%; }

QScrollArea { background: transparent; border: none; }
QScrollArea > QWidget > QWidget { background: transparent; }
QScrollBar:vertical { background: transparent; width: 12px; margin: 2px; }
QScrollBar::handle:vertical { background: %RULE%; border-radius: 4px; min-height: 36px; }
QScrollBar::handle:vertical:hover { background: %FILLDIM%; }
QScrollBar:horizontal { background: transparent; height: 12px; margin: 2px; }
QScrollBar::handle:horizontal { background: %RULE%; border-radius: 4px; min-width: 36px; }
QScrollBar::handle:horizontal:hover { background: %FILLDIM%; }
QScrollBar::add-line, QScrollBar::sub-line { width: 0; height: 0; }
QScrollBar::add-page, QScrollBar::sub-page { background: none; }

QListWidget#browser { background: %PLATE%; border: 1px solid %RULE%; border-radius: 8px; padding: 4px; outline: none; }
QListWidget#browser:focus, QListWidget#browser[padFocus="true"] { border: 2px solid %EDGE%; padding: 3px; }
QComboBox[padFocus="true"] { border: 2px solid %EDGE%; }
QLabel#padHints { background: %PLATE%; color: %DIM%; border-top: 1px solid %RULE%; padding: 7px 14px; }

QLabel#status { padding: 6px 12px; border-radius: 6px; color: %TEXT%; }
QLabel#status[tone="error"] { background: %BADWASH%; color: %LIT%; }
QLabel#status[tone="success"] { background: %EDGEWASH%; color: %LIT%; }
QLabel[state="running"] { color: %LIT%; }
QLabel[state="done"] { color: %TEXT%; }
QLabel[state="pending"] { color: %DIM%; }
QLabel[state="failed"] { color: %WARNTEXT%; }
QLabel[state="warning"] { color: %CAUTION%; }
QLabel[hint="true"] { color: %DIM%; }

QFrame#section { background: %PANEL%; border: 1px solid %RULE%; border-radius: 10px; }
QFrame#card { background: %PLATE%; border: 1px dashed %FILLDIM%; border-radius: 8px; }
QFrame#card[tone="valid"] { background: %GOODWASH%; border: 1px solid %GOODEDGE%; }
QFrame#card[tone="invalid"] { background: %BADWASH%; border: 1px solid %BADEDGE%; }
QFrame#card[tone="checking"] { background: %EDGEWASH%; border: 1px solid %EDGE%; }
QFrame#card[tone="drop"] { background: %EDGEWASH%; border: 2px dashed %ENTRY%; }
QFrame#note { background: %EDGEWASH%; border: 1px solid %EDGEHALF%; border-radius: 8px; }
QFrame#note[tone="error"] { background: %BADWASH%; border: 1px solid %BADEDGE%; }
QFrame#note[tone="warning"] { background: %CAUTIONWASH%; border: 1px solid %CAUTIONEDGE%; }
QFrame#section QLabel, QFrame#card QLabel, QFrame#note QLabel { background: transparent; }

QDialog, QMessageBox { background: %PANEL%; }
)CSS");
  const struct { const char* key; QString value; } k[] = {
      {"%TEXT%", Css(kText)}, {"%DIM%", Css(kDim)}, {"%PANEL%", Css(kPanel)}, {"%TRACK%", Css(kTrack)},
      {"%PLATE%", Css(kPlate)}, {"%RULE%", Css(kRule)}, {"%EDGEWASH%", Css(kEdge, 40)}, {"%EDGEHALF%", Css(kEdge, 120)},
      {"%EDGE%", Css(kEdge)}, {"%ENTRY%", Css(kEntry)}, {"%LIT%", Css(kLit)}, {"%INK%", Css(kInk)},
      {"%FILLDIM%", Css(kFillDim)}, {"%CRIMSONHI%", Css(crimson_hi)}, {"%CRIMSONLO%", Css(crimson_lo)},
      {"%CRIMSON%", Css(kCrimson)}, {"%HOVER%", Css(hover)}, {"%PRESSED%", Css(pressed)},
      {"%OFFTEXT%", Css(off_text)}, {"%OFFEDGE%", Css(off_edge)}, {"%WARNTEXT%", Css(kWarnText)},
      {"%CAUTIONWASH%", Css(kCaution, 26)}, {"%CAUTIONEDGE%", Css(kCaution, 120)}, {"%CAUTION%", Css(kCaution)},
      {"%GOODWASH%", Css(kGood, 30)}, {"%GOODEDGE%", Css(kGood, 150)}, {"%BADWASH%", Css(kBad, 38)},
      {"%BADEDGE%", Css(kBad, 170)}, {"%TICK%", TickImage()},
  };
  for (const auto& e : k) css.replace(e.key, e.value);
  return css;
}

}  // namespace

void RemoveTemporaryFiles() { TickDir().remove(); }

void Apply(QApplication& app) {
  app.setStyle(QStyleFactory::create("Fusion"));
  QPalette p;
  const auto set = [&](QPalette::ColorRole role, const QColor& c) { p.setColor(role, c); };
  set(QPalette::Window, kBackground);
  set(QPalette::WindowText, kText);
  set(QPalette::Base, kField);
  set(QPalette::AlternateBase, kPanel);
  set(QPalette::Text, kText);
  set(QPalette::Button, kPanelRaised);
  set(QPalette::ButtonText, kText);
  set(QPalette::BrightText, kLit);
  set(QPalette::Highlight, kEdge);
  set(QPalette::HighlightedText, kInk);
  set(QPalette::PlaceholderText, kDim);
  set(QPalette::ToolTipBase, kPanelRaised);
  set(QPalette::ToolTipText, kText);
  set(QPalette::Link, kEntry);
  set(QPalette::Light, kFillDim);
  set(QPalette::Midlight, kRule);
  set(QPalette::Mid, kTrack);
  set(QPalette::Dark, kInk);
  set(QPalette::Shadow, Qt::black);
  const QColor off = Mix(kDim, kPanel, 0.45);
  for (QPalette::ColorRole role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText}) {
    p.setColor(QPalette::Disabled, role, off);
  }
  p.setColor(QPalette::Disabled, QPalette::Base, kPanel);
  app.setPalette(p);
  app.setStyleSheet(StyleSheet());
}

QFont DisplayFont(qreal point_size) {
  static const QStringList wanted{"Bahnschrift", "Avenir Next Condensed", "Arial Narrow", "Roboto Condensed",
                                  "Noto Sans Condensed", "DejaVu Sans Condensed"};
  QStringList families;
  const QStringList installed = QFontDatabase::families();
  for (const QString& f : wanted) {
    if (installed.contains(f)) families << f;
  }
  QFont font = QApplication::font();
  if (!families.isEmpty()) font.setFamilies(families);
  font.setPointSizeF(point_size);
  font.setBold(true);
  font.setItalic(true);
  font.setLetterSpacing(QFont::AbsoluteSpacing, 0.6);
  return font;
}

void StyleHeading(QLabel* label) {
  label->setText(label->text().toUpper());
  QFont f = DisplayFont(11.5);
  f.setLetterSpacing(QFont::AbsoluteSpacing, 1.2);
  label->setFont(f);
}

void SetProperty(QWidget* widget, const char* name, const QString& value) {
  if (widget->property(name).toString() == value) return;
  widget->setProperty(name, value);
  widget->style()->unpolish(widget);
  widget->style()->polish(widget);
  widget->update();
}

}  // namespace theme
