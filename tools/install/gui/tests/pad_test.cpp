// The controller and the disc browser, without a controller and without a disc:
// the key repeat from made-up controller states, the places and the search over a
// made-up tree of folders, and the setup window driven by presses alone, against
// the fake installer, from the first screen to Play. Offscreen
// (QT_QPA_PLATFORM=offscreen; CTest sets it).
#include <QtTest>

#include <QCheckBox>
#include <QDialog>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QStackedWidget>
#include <QTemporaryDir>
#include <QToolButton>

#include "disc_browser.h"
#include "installer_window.h"
#include "pad_input.h"
#include "pad_nav.h"

class PadTest : public QObject {
  Q_OBJECT

  using PH = InstallerWindow::Phase;
  using DS = InstallerWindow::DiscState;

  std::unique_ptr<QTemporaryDir> tmp_;
  std::unique_ptr<InstallerWindow> w_;
  QString top_, home_, card_, root_;

  static void File(const QString& path, qint64 size = 10) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly));
    QVERIFY(f.resize(size));  // sparse
  }

  // A home folder and an SD card as a Steam Deck has them.
  void Tree() {
    tmp_ = std::make_unique<QTemporaryDir>();
    top_ = tmp_->path();
    home_ = top_ + "/home/deck";
    card_ = top_ + "/run/media/deck/SDCARD";
    for (const char* d : {"Desktop", "Documents", "Downloads", ".local/share/Steam/steamapps"}) QDir().mkpath(home_ + "/" + d);
    File(home_ + "/Downloads/readme.txt");
    File(home_ + "/Downloads/small.iso", 5 * 1000 * 1000);
    for (const char* d : {"Emulation/roms/xbox", "Emulation/roms/ps2", "Games"}) QDir().mkpath(card_ + "/" + d);
    File(card_ + "/Emulation/roms/xbox/Halo (USA).iso", 7000000000ll);
    File(card_ + "/Emulation/roms/xbox/Burnout 3 - Takedown (USA).iso", 7000000000ll);
    File(card_ + "/Emulation/roms/ps2/Other.iso", 4000000000ll);
    // The same card under its second name, as SteamOS links it.
    QFile::link(card_, top_ + "/run/media/mmcblk0p1");
  }

  QList<discs::Place> Places() const { return discs::Places(home_, {top_ + "/run/media"}); }

  InstallerWindow* Make(bool couch = true) {
    w_.reset();
    root_ = top_ + "/data/Takedawn/Game";
    qputenv("TAKEDAWN_FAKE_ROOT", root_.toUtf8());
    qputenv("TAKEDAWN_FAKE_PACE", "0");
    qputenv("TAKEDAWN_FAKE_SHADERS", "ok");
    LaunchConfig config;
    config.program = QCoreApplication::applicationDirPath() + "/fake_installer";
    config.test = true;
    config.couch = couch;
    config.platform = "linux";
    config.home = home_;
    config.media_roots = QStringList{top_ + "/run/media"};
    w_ = std::make_unique<InstallerWindow>(config);
    w_->resize(1024, 640);
    w_->setAttribute(Qt::WA_DontShowOnScreen);
    w_->show();
    return w_.get();
  }

  void Press(std::initializer_list<PadKey> keys) {
    for (PadKey k : keys) {
      w_->PadPress(k);
      QCoreApplication::processEvents();
    }
  }

  int RowOf(QListWidget* list, const QString& starts) {
    for (int i = 0; i < list->count(); ++i) {
      if (list->item(i)->text().startsWith(starts)) return i;
    }
    return -1;
  }

  // Presses Down or Up until the list is on `row` (as a player would).
  void MoveTo(QListWidget* list, int row) {
    QVERIFY(row >= 0);
    for (int guard = 0; guard < 200 && list->currentRow() != row; ++guard) {
      Press({list->currentRow() < row ? PadKey::Down : PadKey::Up});
    }
    QCOMPARE(list->currentRow(), row);
  }

 private slots:
  // ---- the key repeat, from made-up controller states
  void repeaterEdgesAndRepeat() {
    PadRepeater r;
    PadState s;
    QVERIFY(r.Step(s, 0).isEmpty());
    s.accept = true;
    QCOMPARE(r.Step(s, 10), QList<PadKey>{PadKey::Accept});
    QVERIFY(r.Step(s, 500).isEmpty());   // held: one press
    QVERIFY(r.Step(s, 2000).isEmpty());
    s.accept = false;
    QVERIFY(r.Step(s, 2010).isEmpty());
    s.down = true;                        // a held direction repeats
    QCOMPARE(r.Step(s, 3000), QList<PadKey>{PadKey::Down});
    QVERIFY(r.Step(s, 3000 + PadRepeater::kFirstRepeatMs - 1).isEmpty());
    QCOMPARE(r.Step(s, 3000 + PadRepeater::kFirstRepeatMs), QList<PadKey>{PadKey::Down});
    QVERIFY(r.Step(s, 3000 + PadRepeater::kFirstRepeatMs + PadRepeater::kRepeatMs - 1).isEmpty());
    QCOMPARE(r.Step(s, 3000 + PadRepeater::kFirstRepeatMs + PadRepeater::kRepeatMs), QList<PadKey>{PadKey::Down});
    s.down = false;
    s.back = s.start = true;
    QCOMPARE(r.Step(s, 9000), (QList<PadKey>{PadKey::Back, PadKey::Start}));
  }

  void repeaterStickIsADirection() {
    PadRepeater r;
    PadState s;
    s.lx = PadRepeater::kStickThreshold - 1;  // inside the dead zone
    QVERIFY(r.Step(s, 0).isEmpty());
    s.lx = 30000;
    QCOMPARE(r.Step(s, 10), QList<PadKey>{PadKey::Right});
    s.ly = -32768;                            // the larger axis wins
    QCOMPARE(r.Step(s, 20), QList<PadKey>{PadKey::Up});
    s.lx = s.ly = 0;
    QVERIFY(r.Step(s, 30).isEmpty());
    s.ly = 20000;
    s.up = true;                              // the d-pad before the stick
    QCOMPARE(r.Step(s, 40), QList<PadKey>{PadKey::Up});
    r.Reset();
    s = PadState();
    s.page_down = true;
    QCOMPARE(r.Step(s, 50), QList<PadKey>{PadKey::PageDown});
  }

  // ---- the places and the search, over a made-up tree
  void placesOfAHomeAndACard() {
    Tree();
    const QList<discs::Place> places = Places();
    QStringList paths, labels;
    for (const discs::Place& p : places) {
      paths << p.path;
      labels << p.label;
    }
    QCOMPARE(paths.value(0), home_);
    QVERIFY(paths.contains(home_ + "/Downloads"));
    QVERIFY2(paths.contains(card_), qPrintable(paths.join(" | ")));
    QVERIFY(paths.contains(card_ + "/Emulation/roms/xbox"));
    QCOMPARE(paths.count(card_), 1);
    QVERIFY(!paths.contains(top_ + "/run/media/mmcblk0p1"));  // the card once, not under both names
    QVERIFY(!paths.contains(top_ + "/run/media/deck"));       // the user's folder is not a drive
    QVERIFY(labels.contains("Drive: SDCARD"));
    // Nothing that does not exist.
    QCOMPARE(discs::Places(top_ + "/nowhere", {top_ + "/none"}).size(), 0);
  }

  void candidatesAreTheLikelyOnesOnly() {
    Tree();
    File(home_ + "/Games/Burnout 3 Takedown/default.xbe", 4000000);
    File(home_ + "/Games/Burnout 3 Takedown/Tracks/deep/more/default.xbe");  // under a disc: not another
    File(home_ + "/.hidden/Burnout 3.iso", 7000000000ll);                    // hidden folders are not searched
    File(home_ + "/.local/share/Steam/steamapps/Burnout 3.iso", 7000000000ll);
    File(home_ + "/a/b/c/d/e/Burnout 3 too deep.iso", 7000000000ll);
    // A link to a folder elsewhere is followed, and a loop of links ends.
    File(top_ + "/elsewhere/dumps/Burnout 3 again/default.xbe");
    QVERIFY(QFile::link(top_ + "/elsewhere/dumps", home_ + "/Documents/dumps"));
    QVERIFY(QFile::link(home_, home_ + "/Documents/loop"));
    const QStringList found = discs::Candidates(Places());
    QVERIFY2(found.size() >= 3, qPrintable(found.join(" | ")));
    QVERIFY2(found.contains(home_ + "/Documents/dumps/Burnout 3 again"), qPrintable(found.join(" | ")));
    // The ones named Burnout first: the extracted folder, then the image.
    QCOMPARE(found[0], home_ + "/Games/Burnout 3 Takedown");
    QCOMPARE(found[1], card_ + "/Emulation/roms/xbox/Burnout 3 - Takedown (USA).iso");
    QVERIFY(found.contains(card_ + "/Emulation/roms/xbox/Halo (USA).iso"));
    for (const QString& f : found) {
      QVERIFY2(!f.contains("small.iso") && !f.contains(".hidden") && !f.contains("steamapps") && !f.contains("too deep") &&
                   !f.contains("Tracks"), qPrintable(f));
    }
    QVERIFY(found.size() <= 6);
    // A budget of a few entries ends the search early, and it still answers.
    QVERIFY(discs::Candidates(Places(), 3).size() <= found.size());
    QCOMPARE(discs::Candidates({}).size(), 0);
  }

  void discFolderAndImageNames() {
    Tree();
    File(top_ + "/x/DEFAULT.XBE");
    QVERIFY(discs::IsDiscFolder(top_ + "/x"));
    QVERIFY(!discs::IsDiscFolder(home_));
    QVERIFY(discs::IsImageName("a.ISO"));
    QVERIFY(discs::IsImageName("b.xiso"));
    QVERIFY(!discs::IsImageName("c.zip"));
  }

  // ---- the browser page by itself
  void browserListsFoldersAndDiscsOnly() {
    Tree();
    File(card_ + "/Games/Burnout 3 Takedown/default.xbe");
    DiscBrowser b;
    b.SetPlaces(Places());
    QSignalSpy chosen(&b, &DiscBrowser::Chosen), cancelled(&b, &DiscBrowser::Cancelled);
    b.Open();
    QVERIFY(b.CurrentFolder().isEmpty());
    QCOMPARE(b.List()->count(), Places().size());
    QCOMPARE(b.List()->currentRow(), 0);

    // Into Downloads: the small .iso is listed (any image may be chosen), the text file is not.
    b.List()->setCurrentRow(RowOf(b.List(), "Downloads"));
    emit b.List()->itemActivated(b.List()->currentItem());
    QCOMPARE(b.CurrentFolder(), home_ + "/Downloads");
    QStringList rows;
    for (int i = 0; i < b.List()->count(); ++i) rows << b.List()->item(i)->text();
    QCOMPARE(rows, (QStringList{"Up one folder", "small.iso"}));
    b.GoBack();  // a place: back to the places
    QVERIFY(b.CurrentFolder().isEmpty());

    // The card: folders; Games has an extracted disc, which is chosen, not entered.
    b.Open(card_ + "/Games");
    rows.clear();
    for (int i = 0; i < b.List()->count(); ++i) rows << b.List()->item(i)->text();
    QCOMPARE(rows, (QStringList{"Up one folder", "Burnout 3 Takedown"}));
    QCOMPARE(b.List()->currentRow(), 1);  // on what can be chosen
    emit b.List()->itemActivated(b.List()->currentItem());
    QCOMPARE(chosen.size(), 1);
    QCOMPARE(chosen[0][0].toString(), card_ + "/Games/Burnout 3 Takedown");

    // Inside a disc folder: "Use this folder" comes first.
    b.Open(card_ + "/Games/Burnout 3 Takedown");
    QCOMPARE(b.List()->item(0)->text(), QString("Use this folder"));
    QCOMPARE(b.List()->currentRow(), 0);
    // Up, and up: the folder left is the row the list stands on; from a place to the places; then out.
    b.GoBack();
    QCOMPARE(b.CurrentFolder(), card_ + "/Games");
    QCOMPARE(b.List()->currentItem()->text(), QString("Burnout 3 Takedown"));
    b.GoBack();
    QCOMPARE(b.CurrentFolder(), card_);
    QCOMPARE(b.List()->currentItem()->text(), QString("Games"));
    b.GoBack();
    QVERIFY(b.CurrentFolder().isEmpty());
    QCOMPARE(cancelled.size(), 0);
    b.GoBack();
    QCOMPARE(cancelled.size(), 1);
  }

  // ---- the window, by presses alone
  void searchOffersTheDiscAndStartInstalls() {
    Tree();
    InstallerWindow* w = Make();
    QTRY_VERIFY_WITH_TIMEOUT(w->found_->isVisible(), 10000);
    QCOMPARE(w->phase_, PH::Idle);
    QCOMPARE(w->found_path_, card_ + "/Emulation/roms/xbox/Burnout 3 - Takedown (USA).iso");
    QVERIFY(w->found_text_->text().contains("Found Burnout 3: Takedown"));
    QCOMPARE(w->disc_state_, DS::Empty);  // offered, not used
    QVERIFY(!w->primary_->isEnabled());
    QCOMPARE(w->focusWidget(), w->found_use_);
    QVERIFY(w->hints_->isVisible());
    QVERIFY(w->hints_->text().contains("Select"));

    Press({PadKey::Accept});  // "Use it"
    QTRY_COMPARE_WITH_TIMEOUT(w->disc_state_, DS::Valid, 10000);
    QVERIFY(!w->found_->isVisible());
    QCOMPARE(w->focusWidget(), w->primary_);
    QVERIFY(w->hints_->text().contains("Install"));

    Press({PadKey::Start});
    QTRY_COMPARE_WITH_TIMEOUT(w->phase_, PH::Done, 20000);
    QVERIFY(QFileInfo::exists(root_ + "/.complete"));
    QCOMPARE(w->focusWidget(), w->play_);
    QVERIFY(w->hints_->text().contains("Play"));
    Press({PadKey::Start});
    QCOMPARE(w->play_count_, 1);
    Press({PadKey::Accept});  // the focus is on Play too
    QCOMPARE(w->play_count_, 2);
  }

  void browseWithThePadFromTheFirstScreenToPlay() {
    Tree();
    QFile::remove(card_ + "/Emulation/roms/xbox/Burnout 3 - Takedown (USA).iso");
    QFile::remove(card_ + "/Emulation/roms/xbox/Halo (USA).iso");
    QFile::remove(card_ + "/Emulation/roms/ps2/Other.iso");
    File(card_ + "/Games/discs/Burnout 3 - Takedown (USA).iso", 500);  // too small to be searched for, fine to choose
    InstallerWindow* w = Make();
    QTRY_COMPARE(w->phase_, PH::Idle);
    QTRY_VERIFY(w->detect_queue_.isEmpty() && !w->detect_proc_);
    QVERIFY(!w->found_->isVisible());
    QCOMPARE(w->focusWidget(), w->image_browse_);
    QVERIFY(!w->folder_browse_->isVisible());  // one list shows both

    Press({PadKey::Accept});
    QCOMPARE(w->stack_->currentWidget(), w->browser_);
    QListWidget* list = w->browser_->List();
    QCOMPARE(w->focusWidget(), list);
    QVERIFY(w->hints_->text().contains("Back"));
    QVERIFY(!w->browser_->NativeButton()->isVisible());  // nothing to point at it with

    MoveTo(list, RowOf(list, "Drive: SDCARD"));
    Press({PadKey::Accept});
    QCOMPARE(w->browser_->CurrentFolder(), card_);
    MoveTo(list, RowOf(list, "Games"));
    Press({PadKey::Accept});
    QCOMPARE(w->browser_->CurrentFolder(), card_ + "/Games");
    Press({PadKey::Back});  // one level up, on the folder left
    QCOMPARE(w->browser_->CurrentFolder(), card_);
    QCOMPARE(list->currentItem()->text(), QString("Games"));
    Press({PadKey::Accept});
    MoveTo(list, RowOf(list, "discs"));
    Press({PadKey::Accept});
    QCOMPARE(list->currentItem()->text(), QString("Burnout 3 - Takedown (USA).iso"));
    Press({PadKey::Start});  // not on this page
    QCOMPARE(w->stack_->currentWidget(), w->browser_);
    Press({PadKey::Accept});
    QCOMPARE(w->stack_->currentWidget(), w->main_page_);
    QTRY_COMPARE_WITH_TIMEOUT(w->disc_state_, DS::Valid, 10000);
    QCOMPARE(w->disc_path_, card_ + "/Games/discs/Burnout 3 - Takedown (USA).iso");
    QCOMPARE(w->focusWidget(), w->primary_);

    // Up from Install to the boxes, tick one, and back down.
    Press({PadKey::Left});
    QCOMPARE(w->focusWidget(), w->about_);
    Press({PadKey::Up});
    QCOMPARE(w->focusWidget(), w->details_toggle_);
    Press({PadKey::Up});
    QCOMPARE(w->focusWidget(), w->steam_box_);
    Press({PadKey::Up});
    QCOMPARE(w->focusWidget(), w->shaders_box_);
    QVERIFY(w->shaders_box_->isChecked());      // ticked by default
    Press({PadKey::Accept});
    QVERIFY(!w->shaders_box_->isChecked());
    Press({PadKey::Accept});
    QVERIFY(w->shaders_box_->isChecked());
    Press({PadKey::Up});
    QCOMPARE(w->focusWidget(), w->change_);     // where the data goes (BO-197)
    Press({PadKey::Up});
    QCOMPARE(w->focusWidget(), w->image_browse_);
    Press({PadKey::Down, PadKey::Down, PadKey::Down, PadKey::Down, PadKey::Down, PadKey::Right});
    QCOMPARE(w->focusWidget(), w->primary_);

    Press({PadKey::Accept});  // Install
    QTRY_COMPARE_WITH_TIMEOUT(w->phase_, PH::Done, 20000);
    Press({PadKey::Start});
    QCOMPARE(w->play_count_, 1);
  }

  // Change... with the controller (BO-197): the same list in its folder mode, no disc
  // images in it, "Install here" on top; the SD card gets a Takedawn folder.
  void changeWithThePadPutsTheDataOnTheCard() {
    Tree();
    InstallerWindow* w = Make();
    QTRY_COMPARE(w->phase_, PH::Idle);
    w->change_->setFocus();
    Press({PadKey::Accept});
    QCOMPARE(w->stack_->currentWidget(), static_cast<QWidget*>(w->browser_));
    QVERIFY(w->browser_->FolderMode());
    QListWidget* list = w->browser_->List();
    MoveTo(list, RowOf(list, "Drive: SDCARD"));
    Press({PadKey::Accept});
    QCOMPARE(list->item(0)->text(), QString("Install here"));
    for (int i = 0; i < list->count(); ++i) QVERIFY(!list->item(i)->text().endsWith(".iso"));
    MoveTo(list, 0);
    Press({PadKey::Accept});
    QCOMPARE(w->stack_->currentWidget(), w->main_page_);
    QVERIFY(!w->browser_->FolderMode());
    QTRY_COMPARE(w->phase_, PH::Idle);
    QCOMPARE(w->data_root_, QDir::cleanPath(card_ + "/Takedawn"));
    // The disc browser afterwards is the disc browser again.
    w->image_browse_->click();
    QVERIFY(!w->browser_->FolderMode());
    Press({PadKey::Back});
  }

  void backLeavesTheBrowserAndClosesAbout() {
    Tree();
    InstallerWindow* w = Make();
    QTRY_VERIFY_WITH_TIMEOUT(w->found_->isVisible(), 10000);
    Press({PadKey::Right});
    QCOMPARE(w->focusWidget(), w->found_other_);
    Press({PadKey::Accept});  // "Choose another..."
    QCOMPARE(w->stack_->currentWidget(), w->browser_);
    QVERIFY(!w->found_->isVisible());
    Press({PadKey::Back});    // from the places: out
    QCOMPARE(w->stack_->currentWidget(), w->main_page_);
    QCOMPARE(w->focusWidget(), w->image_browse_);
    Press({PadKey::Back});    // nothing to go back to: nothing happens
    QCOMPARE(w->stack_->currentWidget(), w->main_page_);
    QVERIFY(w->isVisible());

    w->about_->setFocus();
    Press({PadKey::Accept});
    QVERIFY(w->about_dialog_ && w->about_dialog_->isVisible());
    QVERIFY(w->hints_->text().contains("Close"));
    Press({PadKey::Start});   // not while a box is open
    QCOMPARE(w->phase_, PH::Idle);
    Press({PadKey::Back});
    QVERIFY(!w->about_dialog_->isVisible());
  }

  void everyControlIsFingerSizedAndReachable() {
    Tree();
    InstallerWindow* w = Make();
    QTRY_VERIFY_WITH_TIMEOUT(w->found_->isVisible(), 10000);
    QCoreApplication::processEvents();
    const QList<QWidget*> targets = PadNavigator::Targets(w);
    QVERIFY(targets.size() >= 6);
    for (QWidget* t : targets) {
      QVERIFY2(t->height() >= 44, qPrintable(QString("%1 is %2 px high").arg(t->metaObject()->className()).arg(t->height())));
    }
    // From the first control every other one is reached by directions alone.
    QSet<QWidget*> reached{targets.first()};
    QList<QWidget*> todo{targets.first()};
    while (!todo.isEmpty()) {
      QWidget* at = todo.takeFirst();
      for (PadKey k : {PadKey::Up, PadKey::Down, PadKey::Left, PadKey::Right}) {
        QWidget* n = PadNavigator::Neighbour(w, at, k);
        if (n && !reached.contains(n)) {
          reached.insert(n);
          todo << n;
        }
      }
    }
    for (QWidget* t : targets) {
      const auto* button = qobject_cast<QAbstractButton*>(t);
      QVERIFY2(reached.contains(t), qPrintable(button ? button->text() : QString(t->metaObject()->className())));
    }
    // The browser's rows too.
    w->OpenBrowser();
    QCoreApplication::processEvents();
    QVERIFY(w->browser_->List()->sizeHintForRow(0) >= 44);
    QVERIFY(w->browser_->BackButton()->height() >= 44);
  }

  // With a mouse (not under gamescope) nothing changes until a controller is used.
  void desktopWindowIsAsItWas() {
    Tree();
    InstallerWindow* w = Make(false);
    QTRY_VERIFY_WITH_TIMEOUT(w->found_->isVisible(), 10000);
    QVERIFY(!w->hints_->isVisible());
    QVERIFY(!(w->windowFlags() & Qt::FramelessWindowHint));
    QVERIFY(w->browser_->NativeButton()->isVisibleTo(w->browser_));
    Press({PadKey::Down});  // a controller after all: the hints come
    QVERIFY(w->hints_->isVisible());
  }

  void cleanup() { w_.reset(); }
};

QTEST_MAIN(PadTest)
#include "pad_test.moc"
