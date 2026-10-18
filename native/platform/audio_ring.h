#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>

namespace applehost {
// Single producer (SPU2), single real-time consumer (AVAudioSourceNode).
// Callback work is bounded, with no allocation, file I/O or locks.
class AudioRing {
public:
    static constexpr unsigned capacity = 16384, target = 2880;
    std::atomic<std::uint64_t> produced{0}, nonzero_input{0}, rendered{0}, nonzero_output{0}, underruns{0}, dropped{0};
    void Push(const short* data, unsigned count) {
        if (!data || !count) return;
        auto w = written.load(std::memory_order_relaxed);
        const auto r = read.load(std::memory_order_acquire);
        const unsigned take = unsigned(std::min<std::uint64_t>(count, capacity - (w - r)));
        unsigned nonzero = 0;
        for (unsigned i = 0; i < take; ++i) {
            const auto slot = ((w + i) % capacity) * 2;
            samples[slot] = data[i * 2] / 32768.0f;
            samples[slot + 1] = data[i * 2 + 1] / 32768.0f;
            nonzero += data[i * 2] != 0 || data[i * 2 + 1] != 0;
        }
        written.store(w + take, std::memory_order_release);
        produced.fetch_add(count, std::memory_order_relaxed);
        nonzero_input.fetch_add(nonzero, std::memory_order_relaxed);
        dropped.fetch_add(count - take, std::memory_order_relaxed);
    }
    void Render(float* left, float* right, unsigned count) {
        auto r = read.load(std::memory_order_relaxed);
        const auto w = written.load(std::memory_order_acquire);
        if (buffering && w - r >= target) { buffering = false; fade = 0; }
        const double ratio = std::clamp(1.0 + (double(w - r) - target) * 0.000002, 0.995, 1.005);
        unsigned nonzero = 0, dry = 0;
        for (unsigned i = 0; i < count; ++i) {
            float a = 0, b = 0;
            if (!buffering && w - r >= 2) {
                const auto slot = (r % capacity) * 2, next = ((r + 1) % capacity) * 2;
                const float gain = std::min(1.0f, float(fade = std::min(fade + 1, 96u)) / 96.0f);
                a = (samples[slot] + float(phase) * (samples[next] - samples[slot])) * gain;
                b = (samples[slot + 1] + float(phase) * (samples[next + 1] - samples[slot + 1])) * gain;
                phase += ratio;
                const unsigned step = unsigned(phase);
                r += step; phase -= step;
            } else {
                // Fade into silence after a late game frame, then refill.
                if (!buffering) { buffering = true; phase = 0; ++dry; }
                a = last_left * 0.94f; b = last_right * 0.94f;
                if (std::abs(a) < 1e-7f) a = 0;
                if (std::abs(b) < 1e-7f) b = 0;
            }
            left[i] = last_left = a; right[i] = last_right = b;
            nonzero += a != 0 || b != 0;
        }
        read.store(r, std::memory_order_release);
        rendered.fetch_add(count, std::memory_order_relaxed);
        nonzero_output.fetch_add(nonzero, std::memory_order_relaxed);
        underruns.fetch_add(dry, std::memory_order_relaxed);
    }
    std::uint64_t Filled() const { return written.load() - read.load(); }
private:
    std::array<float, capacity * 2> samples{};
    std::atomic<std::uint64_t> written{0}, read{0};
    bool buffering = true;
    unsigned fade = 0;
    double phase = 0;
    float last_left = 0, last_right = 0;
};
}
