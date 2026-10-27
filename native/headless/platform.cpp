#include "ps2host/host.h"
#include "ps2host/run.h"
#include "ps2host/gs.h"
#include "apple_frame_sink.h"
#include "apple_touch_input.h"
#if BURNOUT_IOS
#include "mobile_settings.h"
#endif
#include "apple_audio_sink.h"
#if PS2HOST_VULKAN
#include "ps2gpu/gs_renderer.h"
#include "ps2gpu/display.h"
#endif
#include <atomic>
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <chrono>
#include <mutex>

namespace applehost {
namespace {
std::atomic<bool> touch_enabled{false};
std::atomic<unsigned> touch_buttons{0};
std::atomic<unsigned> touch_sticks[2]{{0x8080}, {0x8080}};
AudioSink audio_sink;
bool audio_open = false;
FrameSink frame_sink;
#if PS2HOST_VULKAN
ps2gpu::Display* gpu_display = nullptr;
#endif
std::mutex frame_mutex;
std::chrono::steady_clock::time_point last_frame;
}
#if PS2HOST_VULKAN
void SetGpuDisplay(ps2gpu::Display* display) { gpu_display = display; }
#endif
void SetAudioSink(AudioSink sink) { audio_sink = sink; }
void EnableTouchController(bool enabled) {
    ReleaseTouchButtons(); touch_enabled.store(enabled);
}
void SetTouchButton(unsigned input, bool held) {
    if (input >= 16) return;
    if (held) touch_buttons.fetch_or(1u << input);
    else touch_buttons.fetch_and(~(1u << input));
}
void SetTouchStick(unsigned stick, float x, float y) {
    if (stick >= 2) return;
    if (!std::isfinite(x) || !std::isfinite(y)) x = y = 0;
    const float magnitude = std::hypot(x, y);
    if (magnitude < 0.08f) x = y = 0;
    else if (magnitude > 1) { x /= magnitude; y /= magnitude; }
    auto axis = [](float value) { return unsigned(std::lround(128 + value * (value < 0 ? 128 : 127))); };
    touch_sticks[stick].store(axis(x) | (axis(y) << 8));
}
void ReleaseTouchButtons() {
    touch_buttons.store(0);
    for (auto& stick : touch_sticks) stick.store(0x8080);
}
void SetFrameSink(FrameSink sink) {
    std::lock_guard<std::mutex> lock(frame_mutex);
    frame_sink = std::move(sink); last_frame = {};
}
}

namespace ps2host {
namespace {
std::function<bool(std::vector<u32>*, u32*, u32*)> picture_source;
std::string title;
bool quit = false, fullscreen = false, vsync = true;
float aspect = 4.0f / 3.0f;
u32 supersampling = 1;
std::FILE* wav = nullptr;
u32 wav_bytes = 0;
void U16(u16 value) { unsigned char b[] = {u8(value), u8(value >> 8)}; std::fwrite(b, 1, 2, wav); }
void U32(u32 value) { U16(u16(value)); U16(u16(value >> 16)); }
void WavHeader() {
    std::rewind(wav);
    std::fwrite("RIFF", 1, 4, wav); U32(wav_bytes + 36);
    std::fwrite("WAVEfmt ", 1, 8, wav); U32(16); U16(1); U16(2);
    U32(48000); U32(48000 * 4); U16(4); U16(16);
    std::fwrite("data", 1, 4, wav); U32(wav_bytes);
}
}
bool OpenWindow(const wchar_t*, int, int) { throw Unimplemented{"native window backend is unavailable in the headless host"}; }
void SetGameTitle(const std::string& value) { title = value; }
const std::string& GameTitle() { return title; }
bool WindowOpen() { return false; }
bool WindowClosed() { return quit; }
bool WindowFocused() { return false; }
void QuitGame() { quit = true; }
bool PumpWindow() { return !quit; }
void PresentFrame() {
    applehost::FrameSink sink;
    {
        std::lock_guard<std::mutex> lock(applehost::frame_mutex);
        if (!applehost::frame_sink) return;
        const auto now = std::chrono::steady_clock::now();
        if (now - applehost::last_frame < std::chrono::milliseconds(16)) return;
        applehost::last_frame = now;
        sink = applehost::frame_sink;
    }
    std::vector<u32> pixels;
    u32 width = 0, height = 0;
    if ((picture_source && picture_source(&pixels, &width, &height)) ||
        gs::TheGs().Picture(&pixels, &width, &height)) sink(pixels, width, height);
}
void SetWindowFullscreen(bool on) { fullscreen = on; }
bool WindowFullscreen() { return fullscreen; }
void SetWindowVsync(bool on) { vsync = on; }
bool WindowVsync() { return vsync; }
void SetWindowAspect(const std::string& value) { aspect = value == "16:9" ? 16.0f / 9.0f : 4.0f / 3.0f; }
float PictureAspect() {
#if BURNOUT_IOS
    return applehost::MobilePictureAspect();
#else
    return aspect;
#endif
}
void SetWindowAntiAliasing(const std::string& mode) { supersampling = mode == "ssaa4" ? 4 : mode == "ssaa2" ? 2 : 1; }
u32 SupersamplingFactor() { return supersampling; }
void SetWindowStatus(const std::string&) {}
void SetWindowOverlay(const std::vector<std::string>&) {}
void SetPictureSource(std::function<bool(std::vector<u32>*, u32*, u32*)> source) { picture_source = std::move(source); }
ps2gpu::Display* WindowDisplay() {
#if PS2HOST_VULKAN
    return applehost::gpu_display;
#else
    return nullptr;
#endif
}
#if PS2HOST_VULKAN
ps2gpu::Gpu* WindowGpu() { return applehost::gpu_display ? applehost::gpu_display->SharedGpu() : nullptr; }
#endif
bool HostKeyDown(int) { return false; }
bool HostPad(HostPadState* state) {
    if (!state) return false;
    *state = HostPadState{};
    if (!applehost::touch_enabled.load()) return false;
    state->buttons = u16(applehost::touch_buttons.load());
    for (unsigned i = 0; i < 16; ++i)
        state->pressure[i] = state->buttons & (1u << i) ? 255 : 0;
    state->l2 = state->pressure[8]; state->r2 = state->pressure[9];
    for (unsigned stick = 0; stick < 2; ++stick) {
        const unsigned value = applehost::touch_sticks[stick].load();
        const unsigned slot = stick == 0 ? 2 : 0;
        state->sticks[slot] = u8(value); state->sticks[slot + 1] = u8(value >> 8);
    }
    // Supply analog steering as well as the D-pad for games that use sticks.
    if (state->buttons & (1u << 7)) state->sticks[2] = 0;
    if (state->buttons & (1u << 5)) state->sticks[2] = 255;
    return true;
}
bool TakeHostMouse(HostMouseState* state) { if (state) *state = HostMouseState{}; return false; }
void SetHostCursor(const u32*, u32, u32, u32, u32) {}
void ShowHostCursor(bool) {}
void HostRumble(u8, u8) {}
void HostTriggerEffects(const HostTriggerEffect&, const HostTriggerEffect&) {}
void ReleaseController() {}
bool OpenAudio() {
    applehost::audio_open = applehost::audio_sink.open && applehost::audio_sink.open();
    return applehost::audio_open;
}
void CloseAudio() {
    if (applehost::audio_open && applehost::audio_sink.close) applehost::audio_sink.close();
    applehost::audio_open = false;
    if (wav) { WavHeader(); std::fclose(wav); wav = nullptr; } }
bool OpenWavDump(const std::string& path) {
    if (wav) { WavHeader(); std::fclose(wav); wav = nullptr; }
    wav_bytes = 0;
    wav = std::fopen(path.c_str(), "wb");
    if (!wav) return false;
    WavHeader(); return !std::ferror(wav);
}
void AudioFrames(const short* frames, unsigned count) {
    if (!frames || !count) return;
    if (applehost::audio_open && applehost::audio_sink.write) applehost::audio_sink.write(frames, count);
    if (!wav) return;
    const u64 bytes = u64(count) * 4;
    if (bytes > 0xffffffffull - 36 - wav_bytes) throw Unimplemented{"WAV exceeds RIFF size limit"};
    if (std::fwrite(frames, 1, std::size_t(bytes), wav) != bytes) throw Unimplemented{"WAV write failed"};
    wav_bytes += u32(bytes);
}
}
