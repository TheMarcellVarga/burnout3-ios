#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>

// A controller for the setup window, so that it can be used where there is no
// mouse or keyboard (a Steam Deck in Game Mode). Three pieces:
//
//   PadState     what a controller reports at one moment
//   PadRepeater  turns a row of states into key presses: one per button press,
//                and a held direction repeats (the d-pad and the left stick are
//                one direction)
//   PadSource    reads the controllers with SDL's game controller API on a
//                timer and emits the presses; built without SDL it reports no
//                controller and emits nothing
//
// The window acts on the presses in pad_nav.h. Nothing here touches sound.

enum class PadKey { Up, Down, Left, Right, Accept, Back, Start, PageUp, PageDown };

struct PadState {
  bool up = false, down = false, left = false, right = false;
  bool accept = false;  // the south face button ("A")
  bool back = false;    // the east face button ("B")
  bool start = false;
  bool page_up = false, page_down = false;  // the shoulder buttons
  int lx = 0, ly = 0;   // the left stick, -32768..32767, down and right positive
};

class PadRepeater {
 public:
  // The presses the step from the last state to `state` makes, at `now_ms`.
  QList<PadKey> Step(const PadState& state, qint64 now_ms);
  // Forget what is held (the controller went away, the window lost the focus).
  void Reset() { *this = PadRepeater(); }

  static constexpr int kStickThreshold = 16000;
  static constexpr int kFirstRepeatMs = 420;
  static constexpr int kRepeatMs = 130;

 private:
  int held_direction_ = -1;  // a PadKey, or -1
  qint64 next_repeat_ = 0;
  bool accept_ = false, back_ = false, start_ = false, page_up_ = false, page_down_ = false;
};

class PadSource : public QObject {
  Q_OBJECT

 public:
  explicit PadSource(QObject* parent = nullptr);
  ~PadSource() override;

  // Starts reading. False when this build has no controller support or SDL
  // would not start; the window then works with mouse and keyboard as before.
  bool Start();
  // Lets go of every controller (the game takes them over). Start() reads again.
  void Stop();
  bool Connected() const { return connected_ > 0; }
  QString Name() const { return name_; }
  // Presses are dropped while this is off (the window is not the active one).
  void SetListening(bool on);
  static bool Available();

  // Tests of the real program: a controller made inside SDL (its virtual
  // joystick), so the presses take the whole way a real controller's do from
  // SDL on, without a device and without anything another program could see.
  bool AttachVirtual();
  void SetVirtual(PadKey key, bool down);

 signals:
  void Pressed(PadKey key);
  void ConnectedChanged(bool connected, const QString& name);

 private:
  void Poll();

  QTimer timer_;
  PadRepeater repeater_;
  int connected_ = 0;
  QString name_;
  bool listening_ = true;
  bool started_ = false;
  struct Impl;
  Impl* impl_ = nullptr;
};
