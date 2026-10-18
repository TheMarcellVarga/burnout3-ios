#include "apple_fibers.h"
#include <array>
#include <cfenv>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>

namespace {
LPVOID root, first, second;
std::vector<int> events;
void Second(void*) {
    std::fesetround(FE_DOWNWARD);
    events.push_back(2);
    SwitchToFiber(root);
    if (std::fegetround() != FE_DOWNWARD) throw std::runtime_error("second rounding lost");
    events.push_back(4);
    SwitchToFiber(first);
}
void First(void*) {
    volatile int local[256];
    for (int i = 0; i < 256; ++i) local[i] = 73;
    std::fesetround(FE_UPWARD);
    events.push_back(1);
    SwitchToFiber(second);
    if (std::fegetround() != FE_UPWARD || local[200] != 73) throw std::runtime_error("fiber state lost");
    events.push_back(5);
}
void Throws(void*) { throw std::runtime_error("fiber exception"); }
LPVOID exception_target;
void IndirectThrow(void*) { SwitchToFiber(exception_target); }
}

int main() {
    root = ConvertThreadToFiber(nullptr);
    std::fesetround(FE_TONEAREST);
    first = CreateFiber(1 << 20, First, nullptr);
    second = CreateFiber(1 << 20, Second, nullptr);
    SwitchToFiber(first);
    if (events != std::vector<int>({1, 2}) || std::fegetround() != FE_TONEAREST) return 1;
    events.push_back(3);
    SwitchToFiber(second);
    if (events != std::vector<int>({1, 2, 3, 4, 5}) || !applehost::Finished(first)) return 2;
    bool rejected = false;
    try { SwitchToFiber(first); } catch (const std::logic_error&) { rejected = true; }
    if (!rejected) return 3;
    bool wrong_thread = false;
    std::thread other([&] {
        ConvertThreadToFiber(nullptr);
        try { SwitchToFiber(second); } catch (const std::logic_error&) { wrong_thread = true; }
    });
    other.join();
    if (!wrong_thread) return 4;
    DeleteFiber(first); DeleteFiber(second);
    auto throwing = CreateFiber(1 << 20, Throws, nullptr);
    bool caught = false;
    try { SwitchToFiber(throwing); } catch (const std::runtime_error&) { caught = true; }
    DeleteFiber(throwing);
    if (!caught) return 5;
    exception_target = CreateFiber(1 << 20, Throws, nullptr);
    auto indirect = CreateFiber(1 << 20, IndirectThrow, nullptr);
    caught = false;
    try { SwitchToFiber(indirect); } catch (const std::runtime_error&) { caught = true; }
    DeleteFiber(exception_target); DeleteFiber(indirect);
    if (!caught) return 8;
    std::atomic<std::uint32_t> sequence{1};
    auto before = std::chrono::steady_clock::now();
    applehost::WaitForSequence(&sequence, 0, 500);
    if (std::chrono::steady_clock::now() - before > std::chrono::milliseconds(100)) return 6;
    std::thread wake([&] {
        sequence.store(2, std::memory_order_release); applehost::WakeSequence();
    });
    applehost::WaitForSequence(&sequence, 1, 500);
    wake.join();
    if (sequence.load() != 2) return 7;
    std::puts("Apple fiber scheduling: PASS");
}
