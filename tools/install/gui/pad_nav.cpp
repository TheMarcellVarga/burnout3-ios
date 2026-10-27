#include "pad_nav.h"

#include <QAbstractButton>
#include <QAbstractItemView>
#include <QComboBox>
#include <QDialog>
#include <QListWidget>
#include <QPlainTextEdit>
#include <QScrollArea>
#include <QScrollBar>
#include <QWidget>

#include <algorithm>
#include <climits>

namespace {

// Where a control is, with every page that scrolls rolled out to its full
// height: what is scrolled out of sight keeps its place in the order (it does
// not lie "under" the controls below the page), and what is below a page moves
// down by what the page hides.
QRect RectIn(QWidget* root, QWidget* w) {
  QRect r(w->mapTo(root, QPoint(0, 0)), w->size());
  for (auto* area : root->findChildren<QScrollArea*>()) {
    QWidget* content = area->widget();
    if (!content || !area->isVisibleTo(root) || area->window() != root->window()) continue;
    const QRect view(area->viewport()->mapTo(root, QPoint(0, 0)), area->viewport()->size());
    const int hidden = std::max(0, content->height() - view.height());
    if (content->isAncestorOf(w)) {
      r.moveTop(view.top() + w->mapTo(content, QPoint(0, 0)).y());
    } else if (r.top() >= view.bottom() - 2) {
      r.translate(0, hidden);
    }
  }
  return r;
}

// The gap between two spans on one axis (0 when they overlap).
int Gap(int a0, int a1, int b0, int b1) { return std::max({0, b0 - a1, a0 - b1}); }

}  // namespace

QList<QWidget*> PadNavigator::Targets(QWidget* root) {
  QList<QWidget*> out;
  if (!root) return out;
  for (QWidget* w : root->findChildren<QWidget*>()) {
    if (!w->isVisibleTo(root) || !w->isEnabled() || !(w->focusPolicy() & Qt::TabFocus)) continue;
    // A window of its own inside this one (a dialog) is not part of it.
    if (w->window() != root->window()) continue;
    const bool control = qobject_cast<QAbstractButton*>(w) || qobject_cast<QComboBox*>(w) || qobject_cast<QListWidget*>(w);
    if (!control || w->width() <= 0 || w->height() <= 0) continue;
    out << w;
  }
  return out;
}

QWidget* PadNavigator::Neighbour(QWidget* root, QWidget* from, PadKey key) {
  if (!root || !from) return nullptr;
  const QRect c = RectIn(root, from);
  const bool vertical = key == PadKey::Up || key == PadKey::Down;
  const bool forward = key == PadKey::Down || key == PadKey::Right;
  QWidget* best = nullptr;
  qint64 best_score = LLONG_MAX;
  for (QWidget* w : Targets(root)) {
    if (w == from) continue;
    const QRect r = RectIn(root, w);
    // It must lie that way: its centre past this one's, and not beside it.
    int along, across;
    if (vertical) {
      if (forward ? r.center().y() <= c.center().y() : r.center().y() >= c.center().y()) continue;
      along = forward ? r.top() - c.bottom() : c.top() - r.bottom();
      across = Gap(c.left(), c.right(), r.left(), r.right());
    } else {
      if (forward ? r.center().x() <= c.center().x() : r.center().x() >= c.center().x()) continue;
      along = forward ? r.left() - c.right() : c.left() - r.right();
      across = Gap(c.top(), c.bottom(), r.top(), r.bottom());
    }
    if (along < -2) continue;  // it reaches back past this one: not that way
    along = std::max(along, 0);
    // What is straight ahead (in the same row or column) before anything off to
    // the side; among those the nearest, and off to the side costs three times.
    const qint64 centre = vertical ? qAbs(r.center().x() - c.center().x()) : qAbs(r.center().y() - c.center().y());
    const qint64 score = (across > 0 ? 100000000ll : 0) + qint64(along) * 1000 + qint64(across) * 3000 + centre;
    if (score < best_score) {
      best_score = score;
      best = w;
    }
  }
  return best;
}

void PadNavigator::FocusOn(QWidget* widget) {
  if (!widget) return;
  widget->setFocus(Qt::TabFocusReason);
  // Into view, when it is on a page that scrolls.
  for (QWidget* p = widget->parentWidget(); p; p = p->parentWidget()) {
    if (auto* area = qobject_cast<QScrollArea*>(p)) {
      area->ensureWidgetVisible(widget, 12, 24);
      break;
    }
  }
  if (auto* list = qobject_cast<QListWidget*>(widget)) {
    if (list->count() > 0 && list->currentRow() < 0) list->setCurrentRow(0);
  }
}

void PadNavigator::Press(PadKey key) {
  QWidget* root = Root ? Root() : nullptr;
  if (!root) return;
  auto* dialog = qobject_cast<QDialog*>(root);
  if (key == PadKey::Back) {
    if (dialog) dialog->reject();
    else if (Back) Back();
    return;
  }
  if (key == PadKey::Start) {
    if (!dialog && Start) Start();
    return;
  }
  if (key == PadKey::PageUp || key == PadKey::PageDown) {
    Scroll(root, key == PadKey::PageUp ? -1 : 1);
    return;
  }
  // The control the presses go to: the one with the focus, if a controller can be on it.
  const QList<QWidget*> targets = Targets(root);
  QWidget* focus = root->window()->focusWidget();
  if (!focus || !targets.contains(focus)) {
    QWidget* first = DefaultFocus && !dialog ? DefaultFocus() : nullptr;
    if (!first || !targets.contains(first)) first = targets.isEmpty() ? nullptr : targets.first();
    FocusOn(first);
    return;  // the first press only shows where the focus is
  }
  if (key == PadKey::Accept) Activate(focus);
  else Move(root, focus, key);
}

void PadNavigator::Move(QWidget* root, QWidget* focus, PadKey key) {
  if (auto* list = qobject_cast<QListWidget*>(focus)) {
    const int row = list->currentRow();
    if (key == PadKey::Down && row + 1 < list->count()) {
      list->setCurrentRow(row + 1);
      return;
    }
    if (key == PadKey::Up && row > 0) {
      list->setCurrentRow(row - 1);
      return;
    }
  }
  FocusOn(Neighbour(root, focus, key));
}

void PadNavigator::Activate(QWidget* focus) {
  if (auto* button = qobject_cast<QAbstractButton*>(focus)) {
    button->click();
  } else if (auto* list = qobject_cast<QListWidget*>(focus)) {
    if (QListWidgetItem* item = list->currentItem()) emit list->itemActivated(item);
  } else if (auto* combo = qobject_cast<QComboBox*>(focus)) {
    if (combo->count() > 0) combo->setCurrentIndex((combo->currentIndex() + 1) % combo->count());
  }
}

// The shoulder buttons: the list with the focus by a page of rows, else the first
// text that is shown (the log, a licence), else the page that scrolls.
void PadNavigator::Scroll(QWidget* root, int pages) {
  if (auto* list = qobject_cast<QListWidget*>(root->window()->focusWidget())) {
    if (list->isVisibleTo(root) && list->count() > 0) {
      const int per_page = std::max(1, list->viewport()->height() / std::max(1, list->sizeHintForRow(0)) - 1);
      list->setCurrentRow(std::clamp(list->currentRow() + pages * per_page, 0, list->count() - 1));
      return;
    }
  }
  QAbstractScrollArea* area = nullptr;
  for (auto* text : root->findChildren<QPlainTextEdit*>()) {
    if (text->isVisibleTo(root)) {
      area = text;
      break;
    }
  }
  if (!area) {
    for (auto* page : root->findChildren<QScrollArea*>()) {
      if (page->isVisibleTo(root) && page->verticalScrollBar()->maximum() > 0) {
        area = page;
        break;
      }
    }
  }
  if (!area) return;
  QScrollBar* bar = area->verticalScrollBar();
  bar->setValue(bar->value() + pages * std::max(40, bar->pageStep() * 3 / 4));
}
