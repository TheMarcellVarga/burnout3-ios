#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QSize>
#include <QStringList>
#include <QString>
#include <QTemporaryDir>

#include <functional>
#include <memory>

#include "installer_window.h"

class QWidget;

// Test modes: drive the window through its states and write a PNG of each with
// QWidget::grab(), so nothing has to be put on a screen (QT_QPA_PLATFORM=offscreen;
// QT_SCALE_FACTOR=2 for pictures at 2x).
// TAKEDAWN_SETUP_PAD_SCRIPT (a test of the real program, on the real screen):
// a controller made inside SDL presses the buttons the script names, one after
// the other, and the window acts on them as on a real one's. Steps, separated
// by commas:
//   up down left right a b start lb rb    a press (80 ms down, then a pause)
//   wait:<ms>                             a pause
//   until:<state>                         wait (up to two minutes) for idle,
//                                         found, valid, browser, main, running, done
//   list:<text>                           in the browser: Down or Up until the
//                                         row that starts with <text> is current
//   shot:<name>                           a PNG of the screen (gamescopectl) and one
//                                         of the window (Qt) into TAKEDAWN_SETUP_SHOT_DIR
//   quit                                  close the window
// What it did goes to stderr ("[SCRIPT] ..."); a step that cannot be done ends it.
class PadScript : public QObject {
 public:
  PadScript(InstallerWindow* window, const QString& script);
  bool Begin();

 private:
  void Next();
  void Press(PadKey key, int then_ms = 380);
  void Say(const QString& text);

  InstallerWindow* w_;
  QStringList steps_;
  int at_ = 0;
  QElapsedTimer waited_;
};

class ShotRunner {
 public:
  ShotRunner(const LaunchConfig& config, const QSize& size, const QString& directory, const QString& prefix)
      : config_(config), size_(size), dir_(directory), prefix_(prefix) {}
  // --shots: every state against the fake installer (tests/fake_installer.cpp, named
  // with --program): empty, disc accepted, each failure code, installing, stopped,
  // done, the shader build, an older install checked in place, no game.
  bool Run();
  // --check-shot: the real game checks `image`; one picture. True when it was accepted.
  bool RunRealCheck(const QString& image);
  // --e2e-shots: the real game installs from `image` into its data folder (--dest
  // or the per-user one): pictures of the accepted disc, the copy under way and the
  // end. True when the data is installed.
  bool RunRealInstall(const QString& image);
  // --pad-shots: the window as under gamescope, driven by controller presses
  // alone, against the fake installer and a made-up tree of folders: the disc
  // found by the search and offered, the browser, the install, Play.
  bool RunPad();

 private:
  // A fresh window; with `fake_root` over a data root of its own (empty to start with).
  InstallerWindow* Make(bool fake_root, const std::function<void(const QString& root)>& prepare = {});
  bool WaitFor(const std::function<bool()>& condition, int timeout_ms = 20000);
  void Shot(const QString& name, QWidget* widget = nullptr);

  LaunchConfig config_;
  QSize size_;
  QString dir_;
  QString prefix_;
  std::unique_ptr<InstallerWindow> w_;
  std::unique_ptr<QTemporaryDir> root_;
  int n_ = 0;
  bool ok_ = true;
};
