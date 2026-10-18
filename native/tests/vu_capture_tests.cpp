#include "ps2host/vu.h"
#include <array>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <vector>

// Same on-disk format as Vu::Snapshots. Captures stay in ignored local storage.
struct Snapshot {
    std::uint32_t pc, flags[6], vf[32][4], vc[32], vacc[4];
};
struct Capture {
    Snapshot state;
    std::array<std::uint8_t, 16384> micro, data;
};
static void Load(ps2host::Vu& vu, const Capture& capture) {
    const auto& s = capture.state;
    std::memcpy(vu.micro.data(), capture.micro.data(), capture.micro.size());
    std::memcpy(vu.data.data(), capture.data.data(), capture.data.size());
    vu.MicroWritten();
    std::memcpy(vu.regs.vf, s.vf, sizeof s.vf);
    std::memcpy(vu.regs.vc, s.vc, sizeof s.vc);
    std::memcpy(vu.regs.vacc, s.vacc, sizeof s.vacc);
    vu.mac = s.flags[0]; vu.status = s.flags[1]; vu.clip = s.flags[2];
    vu.p = s.flags[3]; vu.top = s.flags[4]; vu.itop = s.flags[5];
}
int main(int argc, char** argv) {
    if (argc != 2) return 64;
    auto* file = std::fopen(argv[1], "rb");
    if (!file) return 1;
    std::vector<Capture> captures;
    Capture c;
    while (std::fread(&c.state, sizeof c.state, 1, file) == 1) {
        if (std::fread(c.micro.data(), c.micro.size(), 1, file) != 1 ||
            std::fread(c.data.data(), c.data.size(), 1, file) != 1) {
            std::fclose(file);
            return 1;
        }
        captures.push_back(c);
    }
    std::fclose(file);
    if (captures.empty()) return 1;
    ps2host::Vu interpreted(1), compiled(1);
    interpreted.use_compiled = false;
    std::vector<std::array<std::uint64_t, 2>> expected_kicks, actual_kicks;
    interpreted.on_kick = [&](auto lo, auto hi) { expected_kicks.push_back({lo, hi}); };
    compiled.on_kick = [&](auto lo, auto hi) { actual_kicks.push_back({lo, hi}); };
    double before_ms = 0, after_ms = 0;
    for (const auto& capture : captures) {
        Load(interpreted, capture); Load(compiled, capture);
        expected_kicks.clear(); actual_kicks.clear();
        auto start = std::chrono::steady_clock::now();
        auto pairs = interpreted.Run(capture.state.pc);
        auto middle = std::chrono::steady_clock::now();
        auto compiled_pairs = compiled.Run(capture.state.pc);
        auto end = std::chrono::steady_clock::now();
        before_ms += std::chrono::duration<double, std::milli>(middle - start).count();
        after_ms += std::chrono::duration<double, std::milli>(end - middle).count();
        if (pairs != compiled_pairs || !interpreted.SameState(compiled) || expected_kicks != actual_kicks) {
            std::fprintf(stderr, "VU mismatch at PC %04X\n", capture.state.pc);
            return 1;
        }
    }
    std::printf("%zu captures match: registers, flags, memory, cycles and GIF packets; "
                "%llu/%llu pairs compiled; interpreter %.2f ms, compiled %.2f ms\n",
                captures.size(), (unsigned long long)compiled.compiled_pairs(),
                (unsigned long long)compiled.pairs(), before_ms, after_ms);
    return compiled.compiled_pairs() ? 0 : 1;
}
