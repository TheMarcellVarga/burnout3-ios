#include "apple_fibers.h"
#include <algorithm>
#include <cfenv>
#include <condition_variable>
#include <exception>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <sys/mman.h>
#include <unistd.h>

// ABI of Boost.Context's assembly entry points (two pointers returned in x0/x1).
struct Transfer { void* context; void* data; };
extern "C" void* make_fcontext(void* stack_top, std::size_t size, void (*entry)(Transfer));
extern "C" Transfer jump_fcontext(void* context, void* data);

#pragma STDC FENV_ACCESS ON

namespace applehost {
struct Fiber {
    void* context = nullptr;
    void* mapping = nullptr;
    std::size_t mapping_size = 0;
    FiberEntry entry = nullptr;
    void* data = nullptr;
    std::thread::id owner = std::this_thread::get_id();
    std::fenv_t environment{};
    std::exception_ptr exception;
    bool finished = false;
    ~Fiber() { if (mapping) munmap(mapping, mapping_size); }
};

namespace {
thread_local Fiber root;
thread_local Fiber* current = nullptr;
std::mutex sequence_mutex;
std::condition_variable sequence_changed;

Fiber* Receive(Transfer transfer) {
    auto* source = static_cast<Fiber*>(transfer.data);
    source->context = transfer.context;
    return source;
}

void Enter(Transfer transfer) {
    Receive(transfer);
    Fiber* self = current;
    try { self->entry(self->data); }
    catch (...) { self->exception = std::current_exception(); }
    self->finished = true;
    SwitchToFiber(&root);
    std::terminate(); // A completed fiber must never be resumed.
}
}

Fiber* ConvertThread(void* data) {
    if (!current) {
        root.data = data;
        std::fegetenv(&root.environment);
        current = &root;
    }
    return current;
}

Fiber* CreateFiber(std::size_t size, FiberEntry entry, void* data) {
    if (!entry) throw std::invalid_argument("fiber entry is null");
    ConvertThread(nullptr);
    const std::size_t page = std::size_t(sysconf(_SC_PAGESIZE));
    if (size > std::numeric_limits<std::size_t>::max() - 3 * page)
        throw std::bad_alloc();
    size = (std::max(size, std::size_t(65536)) + page - 1) / page * page;
    auto fiber = std::make_unique<Fiber>();
    fiber->mapping_size = size + 2 * page;
    void* mapping = mmap(nullptr, fiber->mapping_size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mapping == MAP_FAILED) throw std::bad_alloc();
    fiber->mapping = mapping;
    char* bottom = static_cast<char*>(mapping) + page;
    if (mprotect(bottom, size, PROT_READ | PROT_WRITE)) throw std::bad_alloc();
    fiber->entry = entry;
    fiber->data = data;
    std::fegetenv(&fiber->environment);
    fiber->context = make_fcontext(bottom + size, size, Enter);
    return fiber.release();
}

void SwitchToFiber(Fiber* target) {
    if (!current || !target || target->owner != std::this_thread::get_id())
        throw std::logic_error("fiber switch on the wrong thread");
    if (target == current) return;
    if (target->finished) throw std::logic_error("cannot resume a completed fiber");
    Fiber* from = current;
    std::fegetenv(&from->environment);
    std::fesetenv(&target->environment);
    current = target;
    Fiber* source = Receive(jump_fcontext(target->context, from));
    // Exceptions never unwind across an assembly stack switch.
    if (source->exception) {
        auto exception = source->exception;
        source->exception = nullptr;
        std::rethrow_exception(exception);
    }
}

void DeleteFiber(Fiber* fiber) {
    if (!fiber) return;
    if (fiber == current || !fiber->mapping || fiber->owner != std::this_thread::get_id())
        throw std::logic_error("invalid fiber deletion");
    delete fiber;
}
bool Finished(Fiber* fiber) { return fiber && fiber->finished; }

void WaitForSequence(std::atomic<std::uint32_t>* address, std::uint32_t expected, unsigned ms) {
    std::unique_lock<std::mutex> lock(sequence_mutex);
    sequence_changed.wait_for(lock, std::chrono::milliseconds(ms), [&] {
        return address->load(std::memory_order_acquire) != expected;
    });
}
void WakeSequence() {
    // Serialize with the wait's check and unlock, avoiding a lost notification.
    std::lock_guard<std::mutex> lock(sequence_mutex);
    sequence_changed.notify_all();
}
}
