#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QString>
#include <QStringList>
#include <QWidget>

class ElidedLabel;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QToolButton;

// Choosing the disc without a mouse: a plain list of folders and of what could be
// the disc, in the window's own look, for a controller, a finger or a mouse. It
// replaces Qt's own file dialog where that is all there is (Linux; under
// gamescope there is no desktop to ask for a better one).
namespace discs {

struct Place {
  QString label;
  QString path;
};

// Where the list starts: the home folder, Downloads, every mounted card and
// drive (the folders one and two levels under each of `media_roots`, which is
// how /run/media/<user>/<label> and /run/media/<label> both look), and the
// emulation folders EmuDeck and RetroDECK make, when they exist. Only folders
// that exist, each once.
QList<Place> Places(const QString& home, const QStringList& media_roots);
// The media roots of this system (/run/media, /media, /mnt on Linux).
QStringList SystemMediaRoots();

// A disc image by its name (.iso, .xiso), and a folder of extracted files (it
// has a default.xbe).
bool IsImageName(const QString& file_name);
bool IsDiscFolder(const QString& folder);

// What in the places could be the Burnout 3 disc: extracted folders and images,
// looked for in the places themselves and a few levels under them, never the
// whole disk: it stops after `max_entries` directory entries. The likeliest
// first (the name says Burnout, then extracted folders, then the largest
// images). The game decides whether one of them is the disc.
QStringList Candidates(const QList<Place>& places, int max_entries = 6000, int max_results = 6);

}  // namespace discs

class DiscBrowser : public QWidget {
  Q_OBJECT

 public:
  explicit DiscBrowser(QWidget* parent = nullptr);

  void SetPlaces(const QList<discs::Place>& places);
  // Whether the "system file chooser" button is offered (a desktop with a mouse).
  void SetNativeOffered(bool offered);
  // Choosing a folder to install into (BO-197) in place of the disc: every folder has
  // "Install here" on top, and no disc images are listed.
  void SetFolderMode(bool on);
  bool FolderMode() const { return folder_mode_; }
  // Shows the places, or `folder` when it is given and exists.
  void Open(const QString& folder = QString());
  // One level up: the parent folder, the places from a place, Cancelled from the places.
  void GoBack();

  QString CurrentFolder() const { return folder_; }  // empty: the places
  QListWidget* List() const { return list_; }
  QToolButton* BackButton() const { return back_; }
  QToolButton* NativeButton() const { return native_; }

 signals:
  void Chosen(const QString& path);
  void Cancelled();
  void NativeRequested();

 private:
  enum Kind { KindPlace = 1, KindUp, KindUseFolder, KindFolder, KindDiscFolder, KindImage };
  void ShowPlaces();
  void ShowFolder(const QString& folder_in, const QString& select_in = QString());
  void OnActivated(QListWidgetItem* item);
  QListWidgetItem* AddRow(Kind kind, const QString& text, const QString& path, const QString& note = QString());
  bool IsPlaceRoot(const QString& folder) const;

  QList<discs::Place> places_;
  QString folder_;
  bool folder_mode_ = false;
  QElapsedTimer click_clock_;
  QLabel* title_ = nullptr;
  ElidedLabel* where_ = nullptr;
  QListWidget* list_ = nullptr;
  QLabel* empty_ = nullptr;
  QToolButton* back_ = nullptr;
  QToolButton* native_ = nullptr;
};
