#include "ps2host/host.h"
#include <cstring>
#include <chrono>
#include <cstdio>
#include "ps2host/run.h"

void F_001E2358(lifted::Context&);
void F_00276300(lifted::Context&);

namespace {
unsigned long long scene_draws = 0;
unsigned aux_interval = 1;
void MeasureWorldDraw(lifted::Context& c) {
    const bool primary = c.r[5] == 0;
    const bool normal = !ps2host::VirtualClock() && ps2host::FastForward() == 1;
    constexpr u32 view_count_at = 0x00667054u;
    const u32 views = generated::ReadU32(view_count_at);
    static unsigned phase = 0;
    using Clock = std::chrono::steady_clock;
    static auto previous_draw = Clock::time_point{};
    const auto began = Clock::now();
    if (primary && normal) {
        if (previous_draw.time_since_epoch().count() == 0 || began - previous_draw > std::chrono::milliseconds(500))
            phase = 0; // Warm the auxiliary maps after loading or a pause.
        previous_draw = began;
    }
    // GS descriptors identify view 0 as the display and views 1–3 as
    // 128x128 reflection maps. The POC performance preset skips those views
    // and their sampling overlay; --live-reflections restores all four views
    // each frame. These pages double as scratch, so sampling stale reflection
    // pixels would corrupt car paint.
    const bool reuse_aux = primary && normal && aux_interval != 1 && views == 4 &&
                           (aux_interval == 0 ? phase++ != 0 : (phase++ % aux_interval) != 0);
    struct RestoreViews {
        u32 count;
        bool changed;
        ~RestoreViews() { if (changed) generated::Write32(view_count_at, count); }
    } restore{views, reuse_aux};
    if (reuse_aux) generated::Write32(view_count_at, 1);
    F_00276300(c);
    if (reuse_aux) { generated::Write32(view_count_at, views); restore.changed = false; }
    static bool described_views = false;
    if (primary && normal && !described_views && views == 4) {
        described_views = true;
        for (u32 view = 0; view < views; ++view) {
            const u32 descriptor = 0x00665EC0u + view * 0x230u + 0x470u + 0x1C0u;
            for (u32 pair = 0; pair < 4; ++pair)
                std::fprintf(stderr, "[scene-view] %u register %02X value %016llX\n", view,
                    unsigned(generated::ReadU64(descriptor + pair * 16 + 8) & 0xFFu),
                    (unsigned long long)generated::ReadU64(descriptor + pair * 16));
        }
    }
    if (!primary || ps2host::VirtualClock() || ps2host::FastForward() > 1) return;
    ++scene_draws;
    static auto last = Clock::now();
    static unsigned count = 0;
    ++count;
    const auto now = Clock::now();
    const double seconds = std::chrono::duration<double>(now - last).count();
    if (seconds >= 2.0) {
        std::fprintf(stderr, "[scene] full world render submissions: %.1f/s (%u in %.3f s), views %u, auxiliary interval %u\n",
                     count / seconds, count, seconds, views, aux_interval);
        count = 0; last = now;
    }
}
// Depth haze builds full-screen depth/alpha alias passes, independently of
// world geometry, physics and HUD. Omit the entire packet builder.
void OmitHaze(lifted::Context&) {}

void ObserveWorldFarClip(lifted::Context& c) {
    const u32 caller = u32(c.r[31]);
    if (caller == 0x00211E88u || caller == 0x002273FCu || caller == 0x00227458u) {
        float distance;
        std::memcpy(&distance, &c.f[12], sizeof distance);
        static unsigned described = 0;
        if (described++ < 4)
            std::fprintf(stderr, "[mobile] original world far clip: %.1f (unchanged)\n", double(distance));
    }
    F_001E2358(c);
}
}

void RegisterMobileQuality() {
    ps2host::Override(0x002659C0u, OmitHaze, "mobile: omit depth haze");
    ps2host::Override(0x001E2358u, ObserveWorldFarClip, "iOS: observe original world draw distance");
}

void RegisterNativeRaceMetrics() {
    ps2host::Override(0x00276300u, MeasureWorldDraw, "iOS: measure full world render submissions");
}
void RegisterMobileAuxRefresh(unsigned interval) { aux_interval = interval; }
unsigned long long NativeRaceDrawCalls() { return scene_draws; }

