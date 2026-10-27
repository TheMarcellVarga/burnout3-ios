#include "shots.h"

#include <QApplication>
#include <QCheckBox>
#include <QDialog>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QAbstractButton>
#include <QLabel>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollArea>
#include <QTextStream>
#include <QThread>
#include <QToolButton>

#include "disc_browser.h"
#include "messages.h"
#include <QListWidget>
#include <QProcess>
#include <QTimer>
#include <QStackedWidget>
#include "theme.h"

namespace {
QString Plain(const QString& html) { return QString(html).replace("<br>", " / ").remove(QRegularExpression("<[^>]*>")); }
}  // namespace

InstallerWindow* ShotRunner::Make(bool fake_root, const std::function<void(const QString&)>& prepare) {
  w_.reset();
  LaunchConfig config = config_;
  config.test = true;
  config.shaders = false;  // the window's default is ticked; the shots that show the step tick it themselves
  if (fake_root) {
    root_ = std::make_unique<QTemporaryDir>(QDir::tempPath() + "/Takedawn-XXXXXX");
    const QString root = root_->path() + "/Takedawn/Game";
    qputenv("TAKEDAWN_FAKE_ROOT", root.toUtf8());
    if (prepare) prepare(root);
  }
  w_ = std::make_unique<InstallerWindow>(config);
  if (size_.isValid()) w_->resize(size_);
  w_->setAttribute(Qt::WA_DontShowOnScreen);  // rendered, never put on a screen
  w_->show();
  return w_.get();
}

bool ShotRunner::WaitFor(const std::function<bool()>& condition, int timeout_ms) {
  QElapsedTimer t;
  t.start();
  while (!condition()) {
    if (t.elapsed() > timeout_ms) {
      QTextStream(stderr) << "shots: timed out waiting (" << prefix_ << " after shot " << n_ << "): phase "
                          << int(w_->phase_) << " disc " << int(w_->disc_state_) << " failure " << w_->failure_.code << "\n";
      for (const QString& l : w_->log_lines_.mid(std::max<qsizetype>(0, w_->log_lines_.size() - 12))) {
        QTextStream(stderr) << "  " << l << "\n";
      }
      ok_ = false;
      Shot("TIMEOUT");  // what the window looked like
      return false;
    }
    QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    QThread::msleep(5);
  }
  QCoreApplication::processEvents();
  return true;
}

void ShotRunner::Shot(const QString& name, QWidget* widget) {
  QCoreApplication::processEvents();
  QDir().mkpath(dir_);
  const QString path = QString("%1/%2-%3-%4.png").arg(dir_, prefix_).arg(++n_, 2, 10, QChar('0')).arg(name);
  (widget ? widget : w_.get())->grab().save(path);
  QTextStream(stdout) << path << Qt::endl;
}

// A wait that times out ends the run: the steps after it would use states that never came.
#define WAIT(...) if (!WaitFor(__VA_ARGS__)) return false

bool ShotRunner::Run() {
  using DS = InstallerWindow::DiscState;
  using PH = InstallerWindow::Phase;
  using RS = InstallerWindow::RowStatus;
  const QString games = "/Users/you/Games/";
  const QString good = games + "Burnout 3 - Takedown (USA).iso";
  qputenv("TAKEDAWN_FAKE_PACE", "2");
  qputenv("TAKEDAWN_FAKE_SHADERS", "ok");

  // 1. A fresh start: nothing installed, nothing chosen.
  InstallerWindow* w = Make(true);
  WAIT([&] { return w->phase_ == PH::Idle; });
  Shot("empty");
  theme::SetProperty(w->disc_card_, "tone", "drop");  // a file is held over the window
  Shot("empty-drop-target");
  w->ShowAbout();
  Shot("about", w->about_dialog_);
  w->about_dialog_->close();

  // 2. The disc is accepted.
  w->SetDisc(good);
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->shaders_box_->setChecked(true);   // as the window opens for a player
  Shot("disc-accepted");
  w->activateWindow();
  w->primary_->setFocus(Qt::TabFocusReason);
  Shot("disc-accepted-shaders-ticked-focus");
  w->shaders_box_->setChecked(false);
  Shot("disc-accepted-shaders-unticked");
  w->primary_->clearFocus();

  // 3. A disc that cannot be used: every code the check can give.
  for (const QString& code : messages::InstallCodes()) {
    if (!messages::IsDiscProblem(code)) continue;
    w->SetDisc(games + code + ".iso");
    WAIT([&] { return w->disc_state_ == DS::Invalid; });
    Shot("error-check-" + code);
  }

  // 4. Installing; stopped; resumed into each failure the copy can end with.
  w->SetDisc(games + "hold.iso");
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->primary_->click();
  WAIT([&] { auto* r = w->Row("disc"); return r && r->status == RS::Running && r->fraction >= 0.6; });
  QThread::msleep(300);
  Shot("installing");
  w->details_toggle_->setChecked(true);
  Shot("installing-details");
  w->details_toggle_->setChecked(false);
  w->primary_->click();  // Stop
  WAIT([&] { return w->phase_ == PH::Paused; });
  Shot("stopped");
  for (const QString& code : messages::InstallCodes()) {
    if (code == "cancelled" || (messages::IsDiscProblem(code) && code != "damaged-source" && code != "source-unreadable")) continue;
    Make(true);
    w = w_.get();
    WAIT([&] { return w->phase_ == PH::Idle; });
    w->SetDisc(games + "install-" + code + ".iso");
    WAIT([&] { return w->disc_state_ == DS::Valid; });
    w->primary_->click();
    WAIT([&] { return w->phase_ == PH::Failed; });
    Shot("error-install-" + code);
    if (code == "disk-full") {
      w->details_toggle_->setChecked(true);
      Shot("error-install-disk-full-details");
    }
  }
  // The program ends without an answer.
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Idle; });
  w->SetDisc(games + "crash.iso");
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->primary_->click();
  WAIT([&] { return w->phase_ == PH::Failed; });
  Shot("error-program-crashed");

  // 5. Resume after a failure, to the end.
  w->SetDisc(good);
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  Shot("resume-other-disc");
  w->primary_->click();
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("done");

  // 6. With the shader build: running, done; then one that did not work.
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Idle; });
  w->SetDisc(good);
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->shaders_box_->setChecked(true);
  qputenv("TAKEDAWN_FAKE_SHADERS", "hold");
  w->primary_->click();
  WAIT([&] { auto* r = w->Row("shaders"); return r && r->status == RS::Running && r->fraction >= 0.5; });
  QThread::msleep(200);
  Shot("shaders-running");
  w->primary_->click();  // Stop: the install is whole, the shader build is not
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("done-shaders-stopped");
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Idle; });
  w->SetDisc(good);
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->shaders_box_->setChecked(true);
  qputenv("TAKEDAWN_FAKE_SHADERS", "fail");
  w->primary_->click();
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("done-shaders-failed");
  qputenv("TAKEDAWN_FAKE_SHADERS", "ok");
  // The copy under way with the graphics step ticked (the header counts both steps, the row one),
  // and the graphics step done: its result is one short line.
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Idle; });
  w->SetDisc(games + "hold.iso");
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->shaders_box_->setChecked(true);
  w->primary_->click();
  WAIT([&] { auto* r = w->Row("disc"); return r && r->status == RS::Running && r->fraction >= 0.6; });
  QThread::msleep(300);
  Shot("installing-with-graphics");
  w->primary_->click();  // Stop
  WAIT([&] { return w->phase_ == PH::Paused; });
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Idle; });
  w->SetDisc(good);
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  w->shaders_box_->setChecked(true);
  w->primary_->click();
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("done-shaders-ready");

  // 7. An older install without the marker: checked in place, by itself.
  const auto old_install = [](const QString& root) {
    QDir().mkpath(root + "/Burnout 3 Takedown");
    QFile f(root + "/Burnout 3 Takedown/default.xbe");
    if (f.open(QIODevice::WriteOnly)) f.write("old");
  };
  qputenv("TAKEDAWN_FAKE_PACE", "12");
  Make(true, old_install);
  w = w_.get();
  WAIT([&] { auto* r = w->Row("disc"); return w->phase_ == PH::Running && r && r->fraction >= 0.45; });
  Shot("unverified-checking");
  qputenv("TAKEDAWN_FAKE_PACE", "2");
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("unverified-done");
  Make(true, [&](const QString& root) {
    old_install(root);
    QFile f(root + "/Burnout 3 Takedown/damaged");
    if (f.open(QIODevice::WriteOnly)) f.write("x");
  });
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Failed; });
  Shot("unverified-damaged");

  // 8. Already installed: nothing to do but play.
  Make(true, [](const QString& root) {
    QDir().mkpath(root + "/Burnout 3 Takedown");
    QFile f(root + "/.complete");
    if (f.open(QIODevice::WriteOnly)) f.write("manifest x\n");
  });
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("installed-already");

  // 9. No game beside the window.
  const QString program = config_.program;
  config_.program = "/nowhere/Takedawn";
  Make(true);
  w = w_.get();
  WAIT([&] { return w->phase_ == PH::Broken; });
  Shot("error-program-missing");
  config_.program = program;
  w_.reset();
  return ok_;
}

bool ShotRunner::RunRealCheck(const QString& image) {
  using DS = InstallerWindow::DiscState;
  using PH = InstallerWindow::Phase;
  InstallerWindow* w = Make(false);
  WAIT([&] { return w->phase_ != PH::Asking; });
  if (w->phase_ == PH::Idle) {
    w->SetDisc(image);
    WAIT([&] { return w->disc_state_ == DS::Valid || w->disc_state_ == DS::Invalid; }, 120000);
  }
  QTextStream(stdout) << "data: " << (w->status_code_.isEmpty() ? QString("installed") : w->status_code_) << " in "
                      << w->data_root_ << "\n"
                      << "disc: " << (w->disc_state_ == DS::Valid ? "valid" : "invalid") << " - "
                      << Plain(w->disc_status_->text()) << "\n";
  Shot("real-check");
  const bool ok = w->disc_state_ == DS::Valid;
  w_.reset();
  return ok;
}

bool ShotRunner::RunRealInstall(const QString& image) {
  using DS = InstallerWindow::DiscState;
  using PH = InstallerWindow::Phase;
  using RS = InstallerWindow::RowStatus;
  QTextStream out(stdout);
  InstallerWindow* w = Make(false);
  WAIT([&] { return w->phase_ != PH::Asking; });
  out << "data at start: " << (w->status_code_.isEmpty() ? QString("installed") : w->status_code_) << " in "
      << w->data_root_ << Qt::endl;
  Shot("start");
  if (w->phase_ == PH::Idle) {
    w->SetDisc(image);
    WAIT([&] { return w->disc_state_ == DS::Valid || w->disc_state_ == DS::Invalid; }, 120000);
    out << "disc: " << Plain(w->disc_status_->text()) << Qt::endl;
    Shot("disc");
    if (w->disc_state_ != DS::Valid) return false;
    // The Steam step too, when a test names the Steam config folder to write into.
    if (w->steam_box_ && !qEnvironmentVariableIsEmpty("TAKEDAWN_STEAM_CONFIG")) w->steam_box_->setChecked(true);
    w->primary_->click();
  }
  if (w->phase_ == PH::Running) {
    // (an older install is being checked in place, or the copy has just been started)
    WaitFor([&] { auto* r = w->Row("disc"); return w->phase_ != PH::Running || (r && r->status == RS::Running && r->fraction >= 0.35); },
            600000);
    if (w->phase_ == PH::Running) Shot("installing");
    WAIT([&] { return w->phase_ != PH::Running; }, 1800000);
  }
  Shot(w->phase_ == PH::Done ? "done" : "failed");
  for (const InstallerWindow::StepRow& row : w->rows_) out << "step " << row.id << ": " << row.detail << Qt::endl;
  if (w->steam_box_ && w->steam_box_->isChecked()) out << "steam: " << Plain(w->note_text_->text()) << Qt::endl;
  out << "result: " << (w->phase_ == PH::Done ? "installed" : "failed " + w->failure_.code + " " + w->failure_.message)
      << " in " << w->run_millis_ / 1000.0 << " s; status line: " << w->status_->text() << Qt::endl;
  const bool ok = w->phase_ == PH::Done;
  if (ok) {
    w->play_->click();  // (a test: counted, nothing is started)
    out << "play pressed: " << w->play_count_ << Qt::endl;
  }
  w_.reset();
  return ok;
}

// A made-up home and a made-up SD card: folders, a few files that are not discs,
// an image and an extracted disc.
static void MakeTree(const QString& top, bool with_disc_at_home) {
  const auto file = [](const QString& path, qint64 size) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (f.open(QIODevice::WriteOnly)) f.resize(size);  // sparse: takes no room
  };
  const QString home = top + "/home/deck", card = top + "/run/media/deck/SDCARD";
  for (const char* d : {"Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"}) QDir().mkpath(home + "/" + d);
  file(home + "/Downloads/notes.txt", 100);
  file(home + "/Downloads/steamdeck-recovery.iso", 20 * 1000 * 1000);
  for (const char* d : {"Emulation/roms/xbox", "Emulation/roms/ps2", "Emulation/saves", "Games", "Movies"}) QDir().mkpath(card + "/" + d);
  file(card + "/Emulation/roms/xbox/Burnout 3 - Takedown (USA).iso", 7825162240ll);
  file(card + "/Emulation/roms/xbox/Halo - Combat Evolved (USA).iso", 7825162240ll);
  file(card + "/Emulation/roms/xbox/OutRun 2 (USA).xiso", 2100000000ll);
  if (with_disc_at_home) {
    file(home + "/Games/Burnout 3 Takedown/default.xbe", 4000000);
    QDir().mkpath(home + "/Games/Burnout 3 Takedown/Tracks");
  }
}

bool ShotRunner::RunPad() {
  using DS = InstallerWindow::DiscState;
  using PH = InstallerWindow::Phase;
  using RS = InstallerWindow::RowStatus;
  qputenv("TAKEDAWN_FAKE_PACE", "2");
  qputenv("TAKEDAWN_FAKE_SHADERS", "ok");
  QTemporaryDir tree(QDir::tempPath() + "/Takedawn-tree-XXXXXX");
  MakeTree(tree.path(), false);
  config_.couch = true;
  config_.platform = "linux";
  config_.home = tree.path() + "/home/deck";
  config_.media_roots = QStringList{tree.path() + "/run/media"};
  const auto press = [&](std::initializer_list<PadKey> keys) {
    for (PadKey k : keys) {
      w_->activateWindow();
      w_->PadPress(k);
      QCoreApplication::processEvents();
    }
  };

  // 1. The start: the search of the likely places found the image on the card.
  InstallerWindow* w = Make(true);
  w->activateWindow();
  WAIT([&] { return w->phase_ == PH::Idle && w->found_->isVisible(); });
  Shot("found-offered");

  // 1b. "Use it": the disc is accepted, and its card must still be in view (the page
  // is not left scrolled down to the options).
  press({PadKey::Accept});
  WAIT([&] { return w->disc_state_ == DS::Valid; });
  Shot("use-it-accepted");
  {
    const QPoint top = w->disc_card_->mapTo(w->scroll_->viewport(), QPoint(0, 0));
    const bool in_view = top.y() >= 0 && top.y() + w->disc_card_->height() <= w->scroll_->viewport()->height();
    QTextStream(stdout) << "disc card in view after Use it: " << in_view << Qt::endl;
    ok_ = ok_ && in_view;
  }
  w = Make(true);
  w->activateWindow();
  WAIT([&] { return w->phase_ == PH::Idle && w->found_->isVisible(); });

  // 2. "Choose another...": the browser, its places, a folder, the images.
  press({PadKey::Right, PadKey::Accept});
  WAIT([&] { return w->stack_->currentWidget() == w->browser_; });
  Shot("browser-places");
  press({PadKey::Down, PadKey::Down, PadKey::Down});
  Shot("browser-places-moved");
  // (to the card's row, whichever it is, and in)
  for (int i = 0; i < w->browser_->List()->count(); ++i) {
    if (w->browser_->List()->item(i)->text().startsWith("Drive")) w->browser_->List()->setCurrentRow(i);
  }
  press({PadKey::Accept});
  Shot("browser-card");
  press({PadKey::Back});
  press({PadKey::Up, PadKey::Up, PadKey::Up, PadKey::Up});
  for (int i = 0; i < w->browser_->List()->count(); ++i) {
    if (w->browser_->List()->item(i)->text().startsWith("Xbox")) w->browser_->List()->setCurrentRow(i);
  }
  press({PadKey::Accept});
  Shot("browser-xbox-folder");
  press({PadKey::Accept});  // the first image: Burnout 3
  WAIT([&] { return w->stack_->currentWidget() == w->main_page_ && w->disc_state_ == DS::Valid; });
  Shot("disc-accepted");

  // 3. Down to the options, the shader box ticked, About and back.
  press({PadKey::Up, PadKey::Up});
  Shot("focus-on-options");
  w->ShowAbout();
  Shot("about", w->about_dialog_);
  press({PadKey::Back});

  // 4. Start: the install; Start again when it is done: Play.
  qputenv("TAKEDAWN_FAKE_PACE", "6");
  press({PadKey::Start});
  WAIT([&] { auto* r = w->Row("disc"); return r && r->status == RS::Running && r->fraction >= 0.5; });
  Shot("installing");
  WAIT([&] { return w->phase_ == PH::Done; });
  Shot("done");
  press({PadKey::Start});
  QTextStream(stdout) << "play pressed: " << w->play_count_ << Qt::endl;
  ok_ = ok_ && w->play_count_ == 1;
  w_.reset();
  return ok_;
}

// ------------------------------------------------ the scripted controller

PadScript::PadScript(InstallerWindow* window, const QString& script)
    : QObject(window), w_(window), steps_(script.split(',', Qt::SkipEmptyParts)) {}

void PadScript::Say(const QString& text) { QTextStream(stderr) << "[SCRIPT] " << text << Qt::endl; }

bool PadScript::Begin() {
  if (!w_->pad_ || !w_->pad_->AttachVirtual()) {
    Say("no controller could be made (this build has no SDL, or SDL has no virtual joystick)");
    return false;
  }
  Say(QString("controllers: %1").arg(w_->pad_->Name()));
  QTimer::singleShot(600, this, &PadScript::Next);
  return true;
}

void PadScript::Press(PadKey key, int then_ms) {
  w_->pad_->SetVirtual(key, true);
  QTimer::singleShot(80, this, [this, key, then_ms] {
    w_->pad_->SetVirtual(key, false);
    QTimer::singleShot(then_ms, this, &PadScript::Next);
  });
}

void PadScript::Next() {
  using DS = InstallerWindow::DiscState;
  using PH = InstallerWindow::Phase;
  if (at_ >= steps_.size()) {
    Say("end");
    return;
  }
  const QString step = steps_[at_].trimmed();
  const QString name = step.section(':', 0, 0), arg = step.section(':', 1);
  static const struct { const char* name; PadKey key; } kKeys[] = {
      {"up", PadKey::Up}, {"down", PadKey::Down}, {"left", PadKey::Left}, {"right", PadKey::Right}, {"a", PadKey::Accept},
      {"b", PadKey::Back}, {"start", PadKey::Start}, {"lb", PadKey::PageUp}, {"rb", PadKey::PageDown}};
  for (const auto& k : kKeys) {
    if (name == k.name) {
      ++at_;
      QWidget* f = w_->PadRoot()->window()->focusWidget();
      const auto* button = qobject_cast<QAbstractButton*>(f);
      Say(QString("%1 (focus: %2)").arg(name, button ? button->text() : f ? QString(f->metaObject()->className()) : QString("none")));
      Press(k.key);
      return;
    }
  }
  if (name == "wait") {
    ++at_;
    QTimer::singleShot(arg.toInt(), this, &PadScript::Next);
  } else if (name == "until") {
    const bool browser = w_->stack_->currentWidget() == w_->browser_;
    const bool there = arg == "idle" ? w_->phase_ == PH::Idle && !w_->detect_proc_ && w_->detect_queue_.isEmpty()
                       : arg == "found" ? w_->found_->isVisible()
                       : arg == "valid" ? w_->disc_state_ == DS::Valid && w_->phase_ == PH::Idle
                       : arg == "browser" ? browser
                       : arg == "main" ? !browser
                       : arg == "running" ? w_->phase_ == PH::Running
                       : arg == "done" ? w_->phase_ == PH::Done : false;
    if (!waited_.isValid()) waited_.start();
    if (there) {
      Say(QString("until:%1 after %2 ms").arg(arg).arg(waited_.elapsed()));
      waited_.invalidate();
      ++at_;
      QTimer::singleShot(250, this, &PadScript::Next);
    } else if (waited_.elapsed() > (arg == "done" ? 900000 : 120000)) {
      Say(QString("until:%1 never came (phase %2, disc %3): stopping").arg(arg).arg(int(w_->phase_)).arg(int(w_->disc_state_)));
    } else {
      QTimer::singleShot(100, this, &PadScript::Next);
    }
  } else if (name == "list") {
    QListWidget* list = w_->browser_->List();
    int row = -1;
    for (int i = 0; i < list->count(); ++i) {
      if (list->item(i)->text().startsWith(arg)) row = i;
    }
    if (row < 0 || w_->stack_->currentWidget() != w_->browser_) {
      QStringList rows;
      for (int i = 0; i < list->count(); ++i) rows << list->item(i)->text();
      Say(QString("list:%1: no such row among: %2: stopping").arg(arg, rows.join(" | ")));
    } else if (list->currentRow() == row) {
      Say(QString("list:%1 is the current row").arg(arg));
      ++at_;
      QTimer::singleShot(150, this, &PadScript::Next);
    } else {
      Press(list->currentRow() < row ? PadKey::Down : PadKey::Up, 160);  // (the step stays until the row is reached)
    }
  } else if (name == "shot") {
    ++at_;
    const QString dir = qEnvironmentVariable("TAKEDAWN_SETUP_SHOT_DIR", QDir::tempPath());
    QDir().mkpath(dir);
    w_->PadRoot()->grab().save(QString("%1/%2-qt.png").arg(dir, arg));
    const int rc = QProcess::execute("gamescopectl", {"screenshot", QString("%1/%2.png").arg(dir, arg)});
    Say(QString("shot:%1 (gamescopectl %2)").arg(arg).arg(rc));
    QTimer::singleShot(900, this, &PadScript::Next);  // (gamescope writes the file a frame or two later)
  } else if (name == "quit") {
    Say("quit");
    w_->close();
  } else {
    Say("unknown step " + step + ": stopping");
  }
}
