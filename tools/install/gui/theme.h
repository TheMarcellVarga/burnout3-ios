#pragma once

#include <QColor>
#include <QFont>
#include <QString>

class QApplication;
class QLabel;
class QWidget;

// The setup window's look, in one place. The colours are the "game" table of the
// toolkit's settings overlay (src/overlay/overlay_ui.cpp, k_theme_game), by the
// same names, so the window and the overlay read as one program: ink-navy panels,
// steel-blue rules and focus, pale blue text, white for what is lit, the crimson
// for the one thing to press. Colours only: every shape is drawn in code or comes
// from the port's own icon, the fonts are the system's, nothing is the game's.
// Fusion is the base style so the window looks the same on every system.
namespace theme {

// ── the overlay's named colours (keep the two tables the same) ────────
extern const QColor kPanel;       // panel      the menu body navy
extern const QColor kEdge;        // edge       the steel-blue rule
extern const QColor kRule;        // rule       the grid line
extern const QColor kCrimson;     // sel_bar    the title crimson
extern const QColor kEntry;       // text       the menu entries, pale blue
extern const QColor kLit;         // text_hi    the lit entry, white
extern const QColor kDim;         // text_dim   hints
extern const QColor kAction;      // action     action rows; the body text here
extern const QColor kInk;         // on_accent  the darkest navy
extern const QColor kTrack;       // track      slider tracks; raised controls here
extern const QColor kFillDim;     // fill_dim
extern const QColor kPlate;       // toast_bg   the header and footer plate
extern const QColor kWarnText;    // warn       the crimson lifted to read as text
extern const QColor kNotice;      // notice_bg  the deep red band
extern const QColor kGood;        // perf_good
extern const QColor kCaution;     // perf_warn
extern const QColor kBad;         // perf_bad

// ── what the widgets ask for, each one of the above ───────────────────
extern const QColor kBackground;   // the window
extern const QColor kPanelRaised;  // buttons
extern const QColor kField;        // the log
extern const QColor kBorder;
extern const QColor kText;
extern const QColor kMuted;
extern const QColor kAccent;       // the primary button, the header's edge
extern const QColor kOnAccent;     // text on it
extern const QColor kFocus;        // focus rings, the progress fill, links
extern const QColor kDanger;
extern const QColor kOk;
extern const QColor kWarn;

// Dark palette, Fusion style and the style sheet, for the whole application.
void Apply(QApplication& app);
// The picture files the style sheet points at live in a temporary folder; it is removed
// when the program ends, and by this before it turns into the game (exec runs no
// destructors). Nothing is drawn from them afterwards.
void RemoveTemporaryFiles();

// A bold italic condensed face for the title and headings: the first of a list of
// system fonts that has a condensed cut (Bahnschrift, Avenir Next Condensed, Arial
// Narrow, Roboto Condensed, DejaVu Sans Condensed), else the system font, in bold
// italic. Nothing is bundled.
QFont DisplayFont(qreal point_size);

// A heading: the display face, upper case, a little letter spacing.
void StyleHeading(QLabel* label);

// Sets a dynamic property the style sheet switches on, and re-applies the style.
void SetProperty(QWidget* widget, const char* name, const QString& value);

// "#rrggbb", for rich text.
QString Css(const QColor& color);
// "rgba(r, g, b, a)" with a in 0..255, for the style sheet and rich text.
QString Css(const QColor& color, int alpha);

}  // namespace theme
