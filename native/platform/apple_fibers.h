#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace applehost {
struct Fiber;
using FiberEntry = void (*)(void*);
Fiber* ConvertThread(void* data);
Fiber* CreateFiber(std::size_t stack_size, FiberEntry entry, void* data);
void SwitchToFiber(Fiber* target);
void DeleteFiber(Fiber* fiber);
bool Finished(Fiber* fiber);
void WaitForSequence(std::atomic<std::uint32_t>* address, std::uint32_t expected,
                     unsigned milliseconds);
void WakeSequence();
}

// Narrow adapter for the existing Windows scheduler's fiber and sequence calls.
// No Windows headers, executable memory or runtime code generation are needed.
using LPVOID = applehost::Fiber*;
#define CALLBACK
inline LPVOID ConvertThreadToFiber(void* data) { return applehost::ConvertThread(data); }
inline LPVOID CreateFiber(std::size_t size, applehost::FiberEntry entry, void* data) {
    return applehost::CreateFiber(size, entry, data);
}
using applehost::SwitchToFiber;
using applehost::DeleteFiber;
inline void WaitOnAddress(std::atomic<std::uint32_t>* address, const std::uint32_t* expected,
                          std::size_t, unsigned milliseconds) {
    applehost::WaitForSequence(address, *expected, milliseconds);
}
inline void WakeByAddressAll(std::atomic<std::uint32_t>*) { applehost::WakeSequence(); }
