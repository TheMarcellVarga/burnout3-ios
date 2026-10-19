#include "ps2host/run.h"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <time.h>

static double ThreadSeconds() {
    timespec t{};
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)) throw std::runtime_error("thread CPU clock unavailable");
    return double(t.tv_sec) + double(t.tv_nsec) / 1e9;
}

int main() {
    using namespace ps2host;
    using Clock = std::chrono::steady_clock;
    constexpr unsigned first_full = (1u << 22) / 3;
    constexpr unsigned frames = first_full + 8192;
    std::mutex gate_mutex;
    std::condition_variable gate;
    bool entered = false, release = false;
    std::atomic<bool> about_to_block{false};
    std::atomic<unsigned> processed{0};
    std::atomic<bool> ordered{true};
    SetGsFrameHandler([&](u64 frame) {
        if (frame == 0) {
            std::unique_lock<std::mutex> lock(gate_mutex);
            entered = true;
            gate.notify_one();
            gate.wait(lock, [&] { return release; });
        }
        if (frame == frames + 1) throw std::runtime_error("expected GS failure");
        if (frame != processed.fetch_add(1)) ordered = false;
    });
    StartGsThread();
    GsFrame(0);
    {
        std::unique_lock<std::mutex> lock(gate_mutex);
        gate.wait(lock, [&] { return entered; });
    }
    std::thread unblock([&] {
        while (!about_to_block.load()) std::this_thread::yield();
        std::this_thread::sleep_for(std::chrono::milliseconds(60));
        {
            std::lock_guard<std::mutex> lock(gate_mutex);
            release = true;
        }
        gate.notify_one();
    });
    double cpu = 0, wall = 0;
    for (unsigned frame = 1; frame <= frames; ++frame) {
        if (frame == first_full) {
            const double began_cpu = ThreadSeconds();
            const auto began = Clock::now();
            about_to_block = true;
            GsFrame(frame);
            wall = std::chrono::duration<double>(Clock::now() - began).count();
            cpu = ThreadSeconds() - began_cpu;
        } else GsFrame(frame);
    }
    unblock.join();
    SyncGs();
    const bool delivered = ordered && processed == frames + 1;
    bool threw = false;
    try {
        GsFrame(frames + 1);
        SyncGs();
    } catch (const std::runtime_error& e) {
        threw = std::string(e.what()) == "expected GS failure";
    }
    StopGsThread();
    SetGsFrameHandler({});
    std::printf("GS ring: ordered %d, failure %d, full-ring wait %.2f ms wall / %.2f ms CPU\n",
                delivered, threw, wall * 1000, cpu * 1000);
    // A full queue must block, not burn a core while the consumer cannot run.
    const bool slept = wall > 0.04 && cpu < wall * 0.35 + 0.002;
    return delivered && threw && slept ? 0 : 1;
}
