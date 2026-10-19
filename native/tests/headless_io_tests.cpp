#include "ps2host/run.h"
#include "ps2host/chain_copy.h"
#include "msvc_crt.h"
#include "apple_touch_input.h"
#include "apple_audio_sink.h"
#include "audio_ring.h"
#include <cmath>
#include <array>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>
#include <unistd.h>

namespace {
unsigned device_frames = 0, device_closes = 0;
bool OpenFakeAudio() { return true; }
void CloseFakeAudio() { ++device_closes; }
void WriteFakeAudio(const short*, unsigned count) { device_frames += count; }
}
int main() {
    // Queued DMA must own the exact source bytes even if guest memory changes.
    // Exercise growth, empty runs, run boundaries, and reuse after consumption.
    ps2host::detail::DmaChainCopy snapshot;
    std::vector<std::uint32_t> packet(70003);
    for (unsigned i = 0; i < packet.size(); ++i) packet[i] = i * 2654435761u;
    const auto original = packet;
    snapshot.Append(packet.data(), 3, 0x1000);
    snapshot.Append(nullptr, 0, 0x2000);
    snapshot.Append(packet.data() + 3, unsigned(packet.size() - 3), 0x3000);
    std::fill(packet.begin(), packet.end(), 0xDEADBEEFu);
    if (snapshot.used != original.size() || snapshot.runs.size() != 3 ||
        snapshot.runs[0] != std::make_pair(3u, 0x1000u) ||
        snapshot.runs[1] != std::make_pair(0u, 0x2000u) ||
        snapshot.runs[2] != std::make_pair(unsigned(original.size() - 3), 0x3000u) ||
        !std::equal(original.begin(), original.end(), snapshot.words.begin())) return 30;
    snapshot.Reset();
    snapshot.Append(packet.data(), 17, 0x4000);
    if (snapshot.used != 17 || snapshot.runs.size() != 1 ||
        !std::equal(packet.begin(), packet.begin() + 17, snapshot.words.begin())) return 31;
    // The real-time consumer must preserve stereo samples, bound the queue,
    // fade on underrun and resume after refilling, across ring wraparound.
    applehost::AudioRing ring;
    std::vector<short> signal(4096 * 2);
    for (unsigned i = 0; i < 4096; ++i) { signal[i * 2] = 8192; signal[i * 2 + 1] = -16384; }
    std::array<float, 1024> left{}, right{};
    ring.Render(left.data(), right.data(), 1024);
    if (ring.nonzero_output.load()) return 20;
    ring.Push(signal.data(), 4096);
    ring.Render(left.data(), right.data(), 1024);
    if (std::abs(left[200] - 0.25f) > 1e-6f || std::abs(right[200] + 0.5f) > 1e-6f) return 21;
    for (unsigned i = 0; i < 10; ++i) ring.Render(left.data(), right.data(), 1024);
    if (ring.underruns.load() != 1 || left.back() != 0 || right.back() != 0) return 22;
    for (unsigned cycle = 0; cycle < 12; ++cycle) {
        ring.Push(signal.data(), 4096);
        for (unsigned i = 0; i < 5; ++i) ring.Render(left.data(), right.data(), 1024);
    }
    if (ring.nonzero_output.load() < 40000 || ring.dropped.load()) return 23;
    for (unsigned i = 0; i < 6; ++i) ring.Push(signal.data(), 4096);
    if (!ring.dropped.load() || ring.Filled() > applehost::AudioRing::capacity) return 24;
    applehost::SetAudioSink({OpenFakeAudio, CloseFakeAudio, WriteFakeAudio});
    if (!ps2host::OpenAudio()) return 25;
    ps2host::HostPadState pad;
    if (ps2host::HostPad(&pad)) return 10;
    applehost::EnableTouchController(true);
    applehost::SetTouchButton(7, true);  // steering and accelerator together
    applehost::SetTouchButton(9, true);
    if (!ps2host::HostPad(&pad) || pad.buttons != ((1u << 7) | (1u << 9)) ||
        pad.sticks[2] != 0 || pad.r2 != 255 || pad.pressure[9] != 255) return 11;
    applehost::SetTouchButton(7, false);
    if (!ps2host::HostPad(&pad) || pad.sticks[2] != 128 || pad.r2 != 255) return 12;
    applehost::ReleaseTouchButtons();
    if (!ps2host::HostPad(&pad) || pad.buttons || pad.r2 || pad.sticks[2] != 128) return 13;
    applehost::SetTouchStick(0, -0.5f, 0.25f);
    applehost::SetTouchStick(1, 0.5f, -0.5f);
    applehost::SetTouchButton(9, true);
    if (!ps2host::HostPad(&pad) || pad.sticks[2] != 64 || pad.sticks[3] != 160 ||
        pad.sticks[0] != 192 || pad.sticks[1] != 64 || pad.r2 != 255) return 15;
    applehost::SetTouchStick(0, 0.02f, 0.01f);
    applehost::SetTouchStick(1, 4, 0);
    if (!ps2host::HostPad(&pad) || pad.sticks[2] != 128 || pad.sticks[3] != 128 || pad.sticks[0] != 255) return 16;
    applehost::ReleaseTouchButtons();
    if (!ps2host::HostPad(&pad) || pad.buttons || pad.r2 || pad.sticks[0] != 128 || pad.sticks[1] != 128 ||
        pad.sticks[2] != 128 || pad.sticks[3] != 128) return 17;
    applehost::EnableTouchController(false);
    if (ps2host::HostPad(&pad)) return 14;
    namespace fs = std::filesystem;
    const fs::path dir = fs::temp_directory_path() / ("burnout-native-io-" + std::to_string(getpid()));
    fs::create_directory(dir);
    const fs::path file = dir / "sound.wav";
    if (!ps2host::OpenWavDump(file.string())) return 1;
    const short samples[] = {32767, -32768, 0, 1234};
    ps2host::AudioFrames(nullptr, 0);
    ps2host::AudioFrames(samples, 2);
    if (device_closes) return 26; // A WAV dump must not disconnect live playback.
    ps2host::CloseAudio();
    if (device_frames != 2 || device_closes != 1) return 27;
    applehost::SetAudioSink({});
    std::ifstream stream(file, std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(stream)), {});
    if (bytes.size() != 52 || std::memcmp(bytes.data(), "RIFF", 4) ||
        std::memcmp(bytes.data() + 8, "WAVEfmt ", 8) ||
        std::memcmp(bytes.data() + 36, "data", 4) || bytes[40] != 8 ||
        std::memcmp(bytes.data() + 44, samples, sizeof samples)) return 2;
    if (ps2host::OpenWavDump((dir / "missing/sound.wav").string())) return 3;
    // Exercise the disc-seek adapter beyond 32-bit file offsets without writing
    // a multi-gigabyte fixture. tmpfile is removed by the OS when closed.
    std::FILE* sparse = std::tmpfile();
    if (!sparse) return 4;
    const std::int64_t offset = (std::int64_t(1) << 32) + 17;
    if (_fseeki64(sparse, offset, SEEK_SET) || _ftelli64(sparse) != offset) return 5;
    std::fclose(sparse);
    std::tm epoch{}; std::time_t zero = 0;
    if (gmtime_s(&epoch, &zero) || epoch.tm_year != 70 || epoch.tm_mon != 0 || epoch.tm_mday != 1) return 6;
    stream.close();
    fs::remove(file); fs::remove(dir);
    std::puts("Headless WAV, large-file offsets and UTC adapter: PASS");
}
