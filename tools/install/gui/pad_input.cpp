#include "pad_input.h"

#include <QElapsedTimer>
#include <QStringList>

#ifdef TAKEDAWN_SETUP_SDL
#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <vector>
#endif

QList<PadKey> PadRepeater::Step(const PadState& s, qint64 now_ms) {
  QList<PadKey> out;
  // One direction at a time: the d-pad first, then the stick's larger axis.
  int direction = -1;
  if (s.up) direction = int(PadKey::Up);
  else if (s.down) direction = int(PadKey::Down);
  else if (s.left) direction = int(PadKey::Left);
  else if (s.right) direction = int(PadKey::Right);
  else {
    const int ax = s.lx < 0 ? -s.lx : s.lx, ay = s.ly < 0 ? -s.ly : s.ly;
    if (ax >= kStickThreshold || ay >= kStickThreshold) {
      if (ay >= ax) direction = int(s.ly < 0 ? PadKey::Up : PadKey::Down);
      else direction = int(s.lx < 0 ? PadKey::Left : PadKey::Right);
    }
  }
  if (direction != held_direction_) {
    held_direction_ = direction;
    if (direction >= 0) {
      out << PadKey(direction);
      next_repeat_ = now_ms + kFirstRepeatMs;
    }
  } else if (direction >= 0 && now_ms >= next_repeat_) {
    out << PadKey(direction);
    next_repeat_ = now_ms + kRepeatMs;
  }
  const auto edge = [&](bool now, bool* was, PadKey key) {
    if (now && !*was) out << key;
    *was = now;
  };
  edge(s.accept, &accept_, PadKey::Accept);
  edge(s.back, &back_, PadKey::Back);
  edge(s.start, &start_, PadKey::Start);
  edge(s.page_up, &page_up_, PadKey::PageUp);
  edge(s.page_down, &page_down_, PadKey::PageDown);
  return out;
}

#ifdef TAKEDAWN_SETUP_SDL

struct PadSource::Impl {
  std::vector<SDL_GameController*> pads;
  SDL_Joystick* virtual_pad = nullptr;
  QElapsedTimer clock;
  bool sdl_up = false;
};

bool PadSource::Available() { return true; }

PadSource::PadSource(QObject* parent) : QObject(parent), impl_(new Impl) {
  timer_.setInterval(16);
  connect(&timer_, &QTimer::timeout, this, &PadSource::Poll);
}

PadSource::~PadSource() {
  Stop();
  delete impl_;
}

void PadSource::Stop() {
  timer_.stop();
  for (SDL_GameController* pad : impl_->pads) SDL_GameControllerClose(pad);
  impl_->pads.clear();
  if (impl_->virtual_pad) SDL_JoystickClose(impl_->virtual_pad);
  impl_->virtual_pad = nullptr;
  if (impl_->sdl_up) SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
  impl_->sdl_up = false;
  started_ = false;
  connected_ = 0;
  repeater_.Reset();
}

bool PadSource::Start() {
  if (started_) return impl_->sdl_up;
  started_ = true;
  // This is a Qt program: SDL owns no window, so it must not wait for one of
  // its own to have the focus, and the signals stay Qt's.
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
  SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
  SDL_SetMainReady();
  if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) return false;
  impl_->sdl_up = true;
  impl_->clock.start();
  timer_.start();
  Poll();
  return true;
}

bool PadSource::AttachVirtual() {
  if (!Start()) return false;
  if (impl_->virtual_pad) return true;
  const int index = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER, SDL_CONTROLLER_AXIS_MAX,
                                              SDL_CONTROLLER_BUTTON_MAX, 0);
  if (index < 0) return false;
  impl_->virtual_pad = SDL_JoystickOpen(index);
  Poll();
  return impl_->virtual_pad != nullptr;
}

void PadSource::SetVirtual(PadKey key, bool down) {
  if (!impl_->virtual_pad) return;
  SDL_GameControllerButton b = SDL_CONTROLLER_BUTTON_INVALID;
  switch (key) {
    case PadKey::Up: b = SDL_CONTROLLER_BUTTON_DPAD_UP; break;
    case PadKey::Down: b = SDL_CONTROLLER_BUTTON_DPAD_DOWN; break;
    case PadKey::Left: b = SDL_CONTROLLER_BUTTON_DPAD_LEFT; break;
    case PadKey::Right: b = SDL_CONTROLLER_BUTTON_DPAD_RIGHT; break;
    case PadKey::Accept: b = SDL_CONTROLLER_BUTTON_A; break;
    case PadKey::Back: b = SDL_CONTROLLER_BUTTON_B; break;
    case PadKey::Start: b = SDL_CONTROLLER_BUTTON_START; break;
    case PadKey::PageUp: b = SDL_CONTROLLER_BUTTON_LEFTSHOULDER; break;
    case PadKey::PageDown: b = SDL_CONTROLLER_BUTTON_RIGHTSHOULDER; break;
  }
  if (b != SDL_CONTROLLER_BUTTON_INVALID) SDL_JoystickSetVirtualButton(impl_->virtual_pad, b, down ? 1 : 0);
}

void PadSource::Poll() {
  SDL_GameControllerUpdate();
  // The controllers there are now: opened as they come, closed as they go.
  bool changed = false;
  for (auto it = impl_->pads.begin(); it != impl_->pads.end();) {
    if (!SDL_GameControllerGetAttached(*it)) {
      SDL_GameControllerClose(*it);
      it = impl_->pads.erase(it);
      changed = true;
    } else {
      ++it;
    }
  }
  const int n = SDL_NumJoysticks();
  for (int i = 0; i < n; ++i) {
    if (!SDL_IsGameController(i)) continue;
    const SDL_JoystickID id = SDL_JoystickGetDeviceInstanceID(i);
    bool open = false;
    for (SDL_GameController* pad : impl_->pads) {
      open = open || SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad)) == id;
    }
    if (open) continue;
    if (SDL_GameController* pad = SDL_GameControllerOpen(i)) {
      impl_->pads.push_back(pad);
      changed = true;
    }
  }
  if (changed) {
    connected_ = int(impl_->pads.size());
    QStringList names;
    for (SDL_GameController* pad : impl_->pads) {
      SDL_Joystick* js = SDL_GameControllerGetJoystick(pad);
      names << QString("%1 (%2:%3)")
                   .arg(QString::fromUtf8(SDL_GameControllerName(pad)))
                   .arg(SDL_JoystickGetVendor(js), 4, 16, QChar('0'))
                   .arg(SDL_JoystickGetProduct(js), 4, 16, QChar('0'));
    }
    name_ = names.join(", ");
    repeater_.Reset();
    emit ConnectedChanged(connected_ > 0, name_);
  }
  // Every controller drives the window: their states are one.
  PadState s;
  for (SDL_GameController* pad : impl_->pads) {
    const auto button = [pad](SDL_GameControllerButton b) { return SDL_GameControllerGetButton(pad, b) != 0; };
    s.up = s.up || button(SDL_CONTROLLER_BUTTON_DPAD_UP);
    s.down = s.down || button(SDL_CONTROLLER_BUTTON_DPAD_DOWN);
    s.left = s.left || button(SDL_CONTROLLER_BUTTON_DPAD_LEFT);
    s.right = s.right || button(SDL_CONTROLLER_BUTTON_DPAD_RIGHT);
    s.accept = s.accept || button(SDL_CONTROLLER_BUTTON_A);
    s.back = s.back || button(SDL_CONTROLLER_BUTTON_B);
    s.start = s.start || button(SDL_CONTROLLER_BUTTON_START);
    s.page_up = s.page_up || button(SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    s.page_down = s.page_down || button(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
    const int x = SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX);
    const int y = SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTY);
    if (qAbs(x) > qAbs(s.lx)) s.lx = x;
    if (qAbs(y) > qAbs(s.ly)) s.ly = y;
  }
  const QList<PadKey> keys = repeater_.Step(s, impl_->clock.elapsed());
  if (!listening_) return;
  for (PadKey key : keys) emit Pressed(key);
}

#else  // no SDL: no controller

struct PadSource::Impl {};
bool PadSource::Available() { return false; }
PadSource::PadSource(QObject* parent) : QObject(parent) {}
PadSource::~PadSource() = default;
bool PadSource::Start() { return false; }
void PadSource::Stop() {}
void PadSource::Poll() {}
bool PadSource::AttachVirtual() { return false; }
void PadSource::SetVirtual(PadKey, bool) {}

#endif

void PadSource::SetListening(bool on) { listening_ = on; }
