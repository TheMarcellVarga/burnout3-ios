#include "ps2host/host.h"
#include "ps2host/run.h"
#include "apple_touch_input.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <thread>

extern const ps2host::FunctionEntry kGuestFunctions[];
extern const std::size_t kGuestFunctionCount;
extern const ps2host::OverlayEntry kGuestOverlays[];
extern const std::size_t kGuestOverlayCount;
void RegisterGameOverrides();

int main(int argc, char** argv) {
    // Developer input for reproducing scenes without scripting menu timings.
    // Each line is a PS2 button bit index followed by 1 (held) or 0 (released).
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--pad-stdin")) continue;
        applehost::EnableTouchController(true);
        std::thread([] {
            unsigned button;
            int held;
            while (std::cin >> button >> held)
                applehost::SetTouchButton(button, held != 0);
            applehost::ReleaseTouchButtons();
        }).detach();
        for (int j = i; j + 1 < argc; ++j) argv[j] = argv[j + 1];
        --argc;
        argv[argc] = nullptr;
        --i;
    }
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--window") || !std::strcmp(argv[i], "--audio") ||
#if !PS2HOST_VULKAN
            !std::strncmp(argv[i], "--gpu", 5)
#else
            false
#endif
        ) {
            std::fprintf(stderr, "This headless build supports software frame dumps and WAV output; window/device audio/GPU output is not integrated.\n");
            return 64;
        }
    }
    ps2host::RegisterFunctions(kGuestFunctions, kGuestFunctionCount);
    ps2host::RegisterOverlays(kGuestOverlays, kGuestOverlayCount);
    RegisterGameOverrides();
    int code = ps2host::Main(argc, argv);
    ps2host::CloseAudio();
    // The optional input thread can hold stdin's lock while waiting. Flush
    // output explicitly so a bounded run still exits with that thread idle.
    std::fflush(stdout);
    std::fflush(stderr);
    // The upstream host is currently a one-run process. Bypass its global
    // worker destructors, as its Windows launcher does; iOS integration will
    // need an explicit stop/join lifecycle before reusing the host in an app.
    std::_Exit(code);
}
