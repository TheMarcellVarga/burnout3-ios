#include "disc_browser.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPainter>
#include <QPainterPath>
#include <QSet>
#include <QStyledItemDelegate>
#include <QToolButton>
#include <QVBoxLayout>

#include <algorithm>

#include "elided_label.h"
#include "theme.h"

namespace discs {

namespace {

const int kRoleKind = Qt::UserRole, kRolePath = Qt::UserRole + 1, kRoleNote = Qt::UserRole + 2;

QString Canonical(const QString& path) {
  const QString c = QFileInfo(path).canonicalFilePath();
  return c.isEmpty() ? QDir::cleanPath(path) : c;
}

QStringList SubFolders(const QString& folder) {
  QStringList out;
  for (const QString& name : QDir(folder).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase)) {
    out << QDir(folder).filePath(name);
  }
  return out;
}

QString Size(qint64 bytes) {
  const double gb = bytes / 1e9;
  return gb >= 1 ? QString("%1 GB").arg(gb, 0, 'f', 1) : QString("%1 MB").arg(qRound(bytes / 1e6));
}

}  // namespace

bool IsImageName(const QString& file_name) {
  return file_name.endsWith(".iso", Qt::CaseInsensitive) || file_name.endsWith(".xiso", Qt::CaseInsensitive);
}

bool IsDiscFolder(const QString& folder) {
  // (name filters do not look at the case, which is what a disc's files want)
  return !QDir(folder).entryList({"default.xbe"}, QDir::Files).isEmpty();
}

QStringList SystemMediaRoots() {
#if defined(Q_OS_LINUX)
  return {"/run/media", "/media", "/mnt"};
#else
  return {};
#endif
}

QList<Place> Places(const QString& home, const QStringList& media_roots) {
  QList<Place> out;
  QSet<QString> seen;
  const auto add = [&](const QString& label, const QString& path) {
    if (path.isEmpty() || !QFileInfo(path).isDir()) return false;
    const QString key = Canonical(path);
    if (seen.contains(key)) return false;
    seen.insert(key);
    out.append({label, QDir::cleanPath(path)});
    return true;
  };
  QStringList bases;  // where an emulation folder may be
  if (!home.isEmpty()) {
    add(QObject::tr("Home"), home);
    add(QObject::tr("Downloads"), QDir(home).filePath("Downloads"));
    bases << home;
  }
  // Cards and drives: /run/media/<user>/<label> and /run/media/<label>.
  const QString user = QFileInfo(home).fileName();
  for (const QString& root : media_roots) {
    for (const QString& one : SubFolders(root)) {
      const QStringList two = SubFolders(one);
      const bool user_folder = QFileInfo(one).fileName() == user && !user.isEmpty();
      if (user_folder) {
        for (const QString& drive : two) {
          if (add(QObject::tr("Drive: %1").arg(QFileInfo(drive).fileName()), drive)) bases << drive;
        }
      } else if (add(QObject::tr("Drive: %1").arg(QFileInfo(one).fileName()), one)) {
        bases << one;
      }
    }
  }
  // Where EmuDeck and RetroDECK keep Xbox discs. Listed first after the home
  // folder: it is where the disc most likely is.
  QList<Place> emu;
  for (const QString& base : bases) {
    for (const char* sub : {"Emulation/roms/xbox", "retrodeck/roms/xbox", "ROMs/xbox", "roms/xbox"}) {
      const QString path = QDir(base).filePath(sub);
      if (!QFileInfo(path).isDir() || seen.contains(Canonical(path))) continue;
      seen.insert(Canonical(path));
      emu.append({QObject::tr("Xbox games (%1)").arg(QDir::toNativeSeparators(QDir(base).filePath(sub))), QDir::cleanPath(path)});
    }
  }
  for (int i = 0; i < emu.size(); ++i) out.insert(std::min<qsizetype>(out.size(), 1 + i), emu[i]);
  return out;
}

QStringList Candidates(const QList<Place>& places, int max_entries, int max_results) {
  struct Found {
    QString path;
    qint64 score;
  };
  QList<Found> found;
  QSet<QString> visited, listed;
  // Breadth first, so the nearest folders are looked at before the budget ends.
  // Links to folders are followed (a games folder is often one); a folder is
  // looked at once, whatever names lead to it, so a loop of links ends.
  struct Todo {
    QString folder;
    int depth;
  };
  QList<Todo> queue;
  for (const Place& p : places) queue.append({p.path, 0});
  static const QSet<QString> kSkip{"steamapps", "Steam", "node_modules", "proc", "sys", "dev", "lost+found",
                                   "compatdata", "shadercache", "bios", "saves", "storage", "Library"};
  int budget = max_entries;
  const int kDepth = 3;
  for (int i = 0; i < queue.size() && budget > 0; ++i) {
    const Todo todo = queue[i];
    const QString key = Canonical(todo.folder);
    if (visited.contains(key)) continue;
    visited.insert(key);
    const QFileInfoList entries =
        QDir(todo.folder).entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
    budget -= 1 + int(entries.size());
    bool disc_folder = false;
    for (const QFileInfo& e : entries) {
      if (e.isFile() && e.fileName().compare("default.xbe", Qt::CaseInsensitive) == 0) disc_folder = true;
    }
    const auto note = [&](const QString& path, qint64 score, const QString& name) {
      if (listed.contains(path)) return;
      listed.insert(path);
      if (name.contains("burnout", Qt::CaseInsensitive)) score += 1000000;
      if (name.contains("takedown", Qt::CaseInsensitive)) score += 500000;
      found.append({path, score});
    };
    if (disc_folder) {
      note(QDir::cleanPath(todo.folder), 100000 - todo.depth, QFileInfo(todo.folder).fileName());
      continue;  // nothing under a disc's own files is another disc
    }
    for (const QFileInfo& e : entries) {
      if (e.isFile()) {
        // An Xbox disc image is gigabytes; a small .iso is something else.
        if (IsImageName(e.fileName()) && e.size() >= 400ll * 1000 * 1000) {
          note(e.absoluteFilePath(), 1000 + e.size() / 100000000 - todo.depth, e.fileName());
        }
      } else if (e.isDir() && todo.depth < kDepth && !e.fileName().startsWith('.') &&
                 !kSkip.contains(e.fileName())) {
        queue.append({e.absoluteFilePath(), todo.depth + 1});
      }
    }
  }
  std::stable_sort(found.begin(), found.end(), [](const Found& a, const Found& b) { return a.score > b.score; });
  QStringList out;
  for (const Found& f : found) {
    if (out.size() >= max_results) break;
    out << f.path;
  }
  return out;
}

}  // namespace discs

// ------------------------------------------------------------- the list's rows

namespace {

using discs::kRoleKind;
using discs::kRoleNote;
using discs::kRolePath;

// A row: a small mark (a folder, a disc, an arrow), the name, and a dim note at
// the right. Tall enough for a finger.
class RowDelegate : public QStyledItemDelegate {
 public:
  using QStyledItemDelegate::QStyledItemDelegate;
  static constexpr int kHeight = 48;

  QSize sizeHint(const QStyleOptionViewItem&, const QModelIndex&) const override { return QSize(200, kHeight); }

  void paint(QPainter* p, const QStyleOptionViewItem& option, const QModelIndex& index) const override {
    p->save();
    p->setRenderHint(QPainter::Antialiasing);
    const QRect r = option.rect.adjusted(4, 2, -4, -2);
    const bool current = option.state & QStyle::State_Selected;
    // (the controller's own mark counts as the focus: a window that is not the
    // active one shows no focus, and the mark is all a controller has to go by)
    const bool focused = current && ((option.state & QStyle::State_HasFocus) ||
                                     (option.widget && option.widget->property("padFocus").toString() == "true"));
    const int kind = index.data(kRoleKind).toInt();
    const bool pick = kind == 3 || kind == 5 || kind == 6;  // what choosing ends on
    if (current) {
      p->setPen(QPen(focused ? theme::kEdge : theme::kRule, focused ? 2 : 1));
      p->setBrush(QColor(theme::kEdge.red(), theme::kEdge.green(), theme::kEdge.blue(), focused ? 56 : 24));
      p->drawRoundedRect(QRectF(r).adjusted(1, 1, -1, -1), 6, 6);
    }
    // The mark.
    const QRectF m(r.left() + 12, r.center().y() - 9, 22, 18);
    p->setPen(QPen(pick ? theme::kLit : theme::kEdge, 1.6));
    p->setBrush(Qt::NoBrush);
    if (kind == 2) {  // up
      QPainterPath a;
      a.moveTo(m.center().x(), m.top() + 2);
      a.lineTo(m.left() + 4, m.center().y());
      a.moveTo(m.center().x(), m.top() + 2);
      a.lineTo(m.right() - 4, m.center().y());
      a.moveTo(m.center().x(), m.top() + 2);
      a.lineTo(m.center().x(), m.bottom() - 1);
      p->drawPath(a);
    } else if (kind == 6) {  // a disc
      p->drawEllipse(m.center(), 8.5, 8.5);
      p->drawEllipse(m.center(), 2.2, 2.2);
    } else {  // a folder
      QPainterPath f;
      f.moveTo(m.left() + 1, m.top() + 3);
      f.lineTo(m.left() + 8, m.top() + 3);
      f.lineTo(m.left() + 11, m.top() + 6);
      f.lineTo(m.right() - 1, m.top() + 6);
      f.lineTo(m.right() - 1, m.bottom() - 1);
      f.lineTo(m.left() + 1, m.bottom() - 1);
      f.closeSubpath();
      if (pick) p->setBrush(QColor(theme::kEdge.red(), theme::kEdge.green(), theme::kEdge.blue(), 110));
      p->drawPath(f);
    }
    // The note, then the name in what is left.
    const QString note = index.data(kRoleNote).toString();
    QRect text = r.adjusted(46, 0, -12, 0);
    if (!note.isEmpty()) {
      QFont small = option.font;
      small.setPointSizeF(small.pointSizeF() * 0.9);
      p->setFont(small);
      const int w = std::min(QFontMetrics(small).horizontalAdvance(note) + 8, text.width() / 2);
      p->setPen(theme::kDim);
      p->drawText(QRect(text.right() - w, text.top(), w, text.height()), Qt::AlignRight | Qt::AlignVCenter,
                  QFontMetrics(small).elidedText(note, Qt::ElideLeft, w));
      text.setRight(text.right() - w - 10);
    }
    QFont f = option.font;
    f.setBold(pick);
    p->setFont(f);
    p->setPen(pick || current ? theme::kLit : theme::kText);
    p->drawText(text, Qt::AlignLeft | Qt::AlignVCenter,
                QFontMetrics(f).elidedText(index.data(Qt::DisplayRole).toString(), Qt::ElideMiddle, text.width()));
    p->restore();
  }
};

}  // namespace

// ------------------------------------------------------------------ the page

DiscBrowser::DiscBrowser(QWidget* parent) : QWidget(parent) {
  auto* layout = new QVBoxLayout(this);
  layout->setContentsMargins(0, 0, 0, 0);
  layout->setSpacing(8);
  auto* frame = new QFrame;
  frame->setObjectName("section");
  auto* inner = new QVBoxLayout(frame);
  inner->setContentsMargins(18, 14, 18, 14);
  inner->setSpacing(8);
  title_ = new QLabel(tr("Choose your game disc"));
  theme::StyleHeading(title_);
  inner->addWidget(title_);
  where_ = new ElidedLabel;
  where_->setMinimumHeight(22);
  inner->addWidget(where_);
  list_ = new QListWidget;
  list_->setObjectName("browser");
  list_->setItemDelegate(new RowDelegate(list_));
  list_->setUniformItemSizes(true);
  list_->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
  list_->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
  list_->setSelectionMode(QAbstractItemView::SingleSelection);
  list_->setMinimumHeight(RowDelegate::kHeight * 3);
  inner->addWidget(list_, 1);
  empty_ = new QLabel(tr("No folders and no disc images (.iso) here."));
  empty_->setProperty("hint", "true");
  empty_->setAlignment(Qt::AlignCenter);
  empty_->setVisible(false);
  inner->addWidget(empty_);
  layout->addWidget(frame, 1);

  auto* buttons = new QHBoxLayout;
  buttons->setSpacing(10);
  back_ = new QToolButton;
  back_->setText(tr("Back"));
  native_ = new QToolButton;
  native_->setText(tr("System file chooser..."));
  native_->setToolTip(tr("The file chooser of your desktop, for a mouse."));
  for (QToolButton* b : {back_, native_}) {
    b->setMinimumHeight(46);
    b->setMinimumWidth(150);
  }
  buttons->addWidget(back_);
  buttons->addStretch(1);
  buttons->addWidget(native_);
  layout->addLayout(buttons);

  // A tap, a click, Enter and a controller's Accept all open the row.
  // A double click also sends the second signal, about whatever row is under
  // the pointer by then: that one is dropped.
  connect(list_, &QListWidget::itemClicked, this, [this](QListWidgetItem* item) {
    click_clock_.start();
    OnActivated(item);
  });
  connect(list_, &QListWidget::itemActivated, this, [this](QListWidgetItem* item) {
    if (click_clock_.isValid() && click_clock_.elapsed() < 500) return;
    OnActivated(item);
  });
  connect(back_, &QToolButton::clicked, this, &DiscBrowser::GoBack);
  connect(native_, &QToolButton::clicked, this, &DiscBrowser::NativeRequested);
}

void DiscBrowser::SetPlaces(const QList<discs::Place>& places) { places_ = places; }

void DiscBrowser::SetNativeOffered(bool offered) { native_->setVisible(offered); }

void DiscBrowser::SetFolderMode(bool on) {
  folder_mode_ = on;
  title_->setText(on ? tr("Choose where to install the game's data") : tr("Choose your game disc"));
  empty_->setText(on ? tr("No folders here.") : tr("No folders and no disc images (.iso) here."));
}

void DiscBrowser::Open(const QString& folder) {
  if (!folder.isEmpty() && QFileInfo(folder).isDir()) ShowFolder(QDir::cleanPath(folder));
  else ShowPlaces();
  list_->setFocus(Qt::TabFocusReason);
}

bool DiscBrowser::IsPlaceRoot(const QString& folder) const {
  for (const discs::Place& p : places_) {
    if (p.path == folder) return true;
  }
  return false;
}

void DiscBrowser::GoBack() {
  if (folder_.isEmpty()) {
    emit Cancelled();
    return;
  }
  const QString up = QFileInfo(folder_).absolutePath();
  if (IsPlaceRoot(folder_) || up == folder_ || up.isEmpty()) ShowPlaces();
  else ShowFolder(up, folder_);
  list_->setFocus(Qt::TabFocusReason);
}

QListWidgetItem* DiscBrowser::AddRow(Kind kind, const QString& text, const QString& path, const QString& note) {
  auto* item = new QListWidgetItem(text, list_);
  item->setData(discs::kRoleKind, int(kind));
  item->setData(discs::kRolePath, path);
  item->setData(discs::kRoleNote, note);
  return item;
}

void DiscBrowser::ShowPlaces() {
  folder_.clear();
  list_->clear();
  where_->SetFullText(folder_mode_ ? tr("Where should the game's data go? It needs about 3 GB.")
                                   : tr("Where is the disc image (.iso) or the folder with the disc's files?"));
  for (const discs::Place& p : places_) AddRow(KindPlace, p.label, p.path, QDir::toNativeSeparators(p.path));
  empty_->setVisible(list_->count() == 0);
  if (list_->count() > 0) list_->setCurrentRow(0);
  back_->setText(tr("Back"));
}

void DiscBrowser::ShowFolder(const QString& folder_in, const QString& select_in) {
  const QString folder = folder_in, select = select_in;  // (either may be folder_ itself)
  folder_ = folder;
  list_->clear();
  where_->SetFullText(QDir::toNativeSeparators(folder));
  if (folder_mode_) {
    AddRow(KindUseFolder, tr("Install here"), folder, QString());
  } else if (discs::IsDiscFolder(folder)) {
    AddRow(KindUseFolder, tr("Use this folder"), folder, tr("it has the disc's files (default.xbe)"));
  }
  AddRow(KindUp, tr("Up one folder"), QString());
  const QDir dir(folder);
  int content = 0;
  QListWidgetItem* selected = nullptr;
  for (const QFileInfo& e : dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase)) {
    const bool disc = !folder_mode_ && discs::IsDiscFolder(e.absoluteFilePath());
    QListWidgetItem* item = AddRow(disc ? KindDiscFolder : KindFolder, e.fileName(), e.absoluteFilePath(),
                                   disc ? tr("disc files: choose") : QString());
    if (e.absoluteFilePath() == select) selected = item;
    ++content;
  }
  for (const QFileInfo& e : dir.entryInfoList(QDir::Files, QDir::Name | QDir::IgnoreCase)) {
    if (folder_mode_ || !discs::IsImageName(e.fileName())) continue;
    AddRow(KindImage, e.fileName(), e.absoluteFilePath(), discs::Size(e.size()));
    ++content;
  }
  empty_->setVisible(content == 0 && !folder_mode_ && !discs::IsDiscFolder(folder));
  // On what can be chosen when there is such a row, else where one came from.
  int row = 0;
  if (selected) {
    row = list_->row(selected);
  } else {
    for (int i = 0; i < list_->count(); ++i) {
      const int kind = list_->item(i)->data(discs::kRoleKind).toInt();
      if (kind == KindUseFolder || kind == KindDiscFolder || kind == KindImage) {
        row = i;
        break;
      }
      if (kind == KindFolder && row == 0) row = i;
    }
  }
  list_->setCurrentRow(row);
  list_->scrollToItem(list_->item(row));
  back_->setText(tr("Back"));
}

void DiscBrowser::OnActivated(QListWidgetItem* item) {
  if (!item) return;
  const int kind = item->data(discs::kRoleKind).toInt();
  const QString path = item->data(discs::kRolePath).toString();
  switch (kind) {
    case KindPlace:
    case KindFolder: ShowFolder(path); break;
    case KindUp: GoBack(); break;
    case KindUseFolder:
    case KindDiscFolder:
    case KindImage: emit Chosen(path); break;
  }
}
