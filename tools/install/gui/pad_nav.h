#pragma once

#include <QObject>

#include <functional>

#include "pad_input.h"

class QWidget;

// What a controller press does to a window of ordinary widgets:
//
//   a direction   the focus goes to the nearest control that way; inside a list
//                 it moves the row, and leaves the list at its ends
//   Accept        presses the focused button, ticks the box, opens the row,
//                 steps a combo box to its next entry
//   Back          closes a dialog (as Esc does), else Back() of the window
//   Start         Start() of the window (its main button)
//   PageUp/Down   scroll the text or the page that can scroll
//
// The window says which widget is the one being driven now (a message box, the
// About box, itself) with Root, so the navigation never leaves what is on top.
class PadNavigator : public QObject {
  Q_OBJECT

 public:
  explicit PadNavigator(QObject* parent = nullptr) : QObject(parent) {}

  std::function<QWidget*()> Root;          // the top widget now
  std::function<QWidget*()> DefaultFocus;  // where the focus starts when it is nowhere
  std::function<void()> Back;              // Back outside a dialog
  std::function<void()> Start;             // Start outside a dialog

  void Press(PadKey key);

  // The controls of `root` a controller can reach: shown, enabled, focusable.
  static QList<QWidget*> Targets(QWidget* root);
  // The target nearest to `from` in the direction of `key`, or null.
  static QWidget* Neighbour(QWidget* root, QWidget* from, PadKey key);

 private:
  void Move(QWidget* root, QWidget* focus, PadKey key);
  void Activate(QWidget* focus);
  void Scroll(QWidget* root, int pages);
  static void FocusOn(QWidget* widget);
};
