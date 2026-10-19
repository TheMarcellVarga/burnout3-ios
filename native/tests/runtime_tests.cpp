#include "ps2rt/lifted.h"
#include "ps2rt/vu_rounding.h"
#include <cfenv>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <initializer_list>

#pragma STDC FENV_ACCESS ON

namespace {
int failures = 0;
void Check(bool condition, const char* message) {
    if (!condition) { std::fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
constexpr u32 Add(u32 fd, u32 fs, u32 ft, u32 mask = 15) {
    return (0x12u << 26) | (1u << 25) | (mask << 21) |
           (ft << 16) | (fs << 11) | (fd << 6) | 0x28u;
}
bool VuChopActive() {
#if PS2RT_VU_SSE
    // The desktop implementation controls SSE, while fegetround on x86 also
    // observes the separate x87 environment. Test the unit the VU actually uses.
    return (_mm_getcsr() & 0x6000u) == 0x6000u;
#else
    return std::fegetround() == FE_TOWARDZERO;
#endif
}

void CheckMacroBatches(bool nearest) {
    const u32 values[] = {0, 0x80000000u, 1, 0x007fffffu, 0x00800000u,
        0x3f800000u, 0x33c00000u, 0x7f7fffffu, 0xff7fffffu, 0x7f800000u,
        0xff800000u, 0x7fc12345u};
    u32 rng = 0x13579bdu;
    auto next = [&] { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; };
    for (int mode : {FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO}) {
        for (int sample = 0; sample < 128; ++sample) {
            lifted::Context expected{};
            for (auto& reg : expected.vf) for (auto& lane : reg) lane = values[next() % 12];
            for (auto& lane : expected.vf[0]) lane = 0;
            expected.vf[0][3] = 0x3f800000u;
            for (auto& lane : expected.vacc) lane = values[next() % 12];
            for (auto& reg : expected.vc) reg = values[next() % 12];
            lifted::Context actual = expected;
            u32 words[64];
            for (u32& word : words) {
                word = (0x12u << 26) | (1u << 25) | ((next() & 15) << 21) |
                    ((next() & 31) << 16) | ((next() & 31) << 11) | ((next() & 31) << 6);
                // Synthetic ISA encodings, including masked/aliased writes,
                // broadcast and accumulator inputs. No game code is embedded.
                lifted::FmacOp op;
                u32 function = next() % 0x30;
                while (!lifted::DecodeFmac(word | function, &op)) function = (function + 1) % 0x30;
                word |= function;
            }
            std::fesetround(mode);
            std::feclearexcept(FE_ALL_EXCEPT);
            std::feraiseexcept(FE_DIVBYZERO);
            for (u32 word : words) lifted::Cop2(expected, word);
            const int flags = std::fetestexcept(FE_ALL_EXCEPT);
            std::feclearexcept(FE_ALL_EXCEPT);
            std::feraiseexcept(FE_DIVBYZERO);
            lifted::Cop2Batch(actual, words, 64);
            Check(std::memcmp(expected.vf, actual.vf, sizeof expected.vf) == 0 &&
                  std::memcmp(expected.vacc, actual.vacc, sizeof expected.vacc) == 0 &&
                  std::memcmp(expected.vc, actual.vc, sizeof expected.vc) == 0, "batch matches individual VU macros");
            Check(std::fegetround() == mode, "batch restores caller rounding");
            Check(std::fetestexcept(FE_ALL_EXCEPT) == flags, "batch matches caller exception flags");
        }
        const u32 invalid[] = {Add(3, 1, 2), 0xffffffffu};
        lifted::Context c{};
        std::feclearexcept(FE_ALL_EXCEPT);
        std::feraiseexcept(FE_DIVBYZERO);
        bool caught = false;
        try { lifted::Cop2Batch(c, invalid, 2); }
        catch (const lifted::Abort& e) { caught = e.reason == 5; }
        Check(caught && std::fegetround() == mode, "batch exception restores rounding");
        if (!nearest) Check(std::fetestexcept(FE_ALL_EXCEPT) == FE_DIVBYZERO, "batch exception restores status");
    }
    std::fesetround(FE_TONEAREST);
    std::feclearexcept(FE_ALL_EXCEPT);
}

}

int RunRuntimeTests() {
    failures = 0;
    const bool nearest = std::getenv("PS2RT_EE_ROUND_NEAREST") != nullptr;
    lifted::Context c{};
    c.vf[0][3] = 0x3f800000u;
    // 1 + 3 * 2^-25 lies above the midpoint between adjacent float values.
    // Nearest rounds up; console chop rounds down.
    for (int i = 0; i < 4; ++i) {
        c.vf[1][i] = 0x3f800000u;
        c.vf[2][i] = 0x33c00000u;
    }
    for (int mode : {FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO}) {
        std::fesetround(mode);
        std::feclearexcept(FE_ALL_EXCEPT);
        std::feraiseexcept(FE_DIVBYZERO);
        const int flags = std::fetestexcept(FE_ALL_EXCEPT);
        lifted::Cop2(c, Add(3, 1, 2));
        if (!nearest || mode == FE_TONEAREST)
            Check(c.vf[3][0] == (nearest ? 0x3f800001u : 0x3f800000u), "VU add rounding");
        Check(std::fegetround() == mode, "caller rounding restored");
        if (!nearest) Check(std::fetestexcept(FE_ALL_EXCEPT) == flags, "caller exception flags restored");
    }
    std::fesetround(FE_TONEAREST);
    std::feclearexcept(FE_ALL_EXCEPT);
    {
        lifted::ScopedVuRounding outer;
        Check(VuChopActive(), "VU microprogram rounding scope");
        { lifted::ScopedVuRounding inner; }
        Check(VuChopActive(), "nested rounding scope");
    }
    Check(std::fegetround() == FE_TONEAREST, "outer rounding scope restored");
    {
        lifted::ScopedVuRounding disabled(false);
        Check(std::fegetround() == FE_TONEAREST, "disabled rounding scope");
    }
    // Masked writes with an aliased destination must retain untouched lanes.
    lifted::Cop2(c, Add(1, 1, 2, 10));
    Check(c.vf[1][1] == 0x3f800000u && c.vf[1][3] == 0x3f800000u, "destination mask");
    Check(c.vf[1][0] == (nearest ? 0x3f800001u : 0x3f800000u), "aliased destination");
    c.vf[1][0] = 0x00000001u; c.vf[2][0] = 0;
    lifted::Cop2(c, Add(3, 1, 2, 8));
    Check(c.vf[3][0] == 0, "VU denormal operand flushed");
    c.vf[1][0] = 0x7f7fffffu; c.vf[2][0] = 0x7f7fffffu;
    lifted::Cop2(c, Add(3, 1, 2, 8));
    Check(c.vf[3][0] == 0x7f7fffffu, "VU positive overflow saturates");
    c.vf[1][0] = 0xff7fffffu; c.vf[2][0] = 0xff7fffffu;
    lifted::Cop2(c, Add(3, 1, 2, 8));
    Check(c.vf[3][0] == 0xff7fffffu, "VU negative overflow saturates");
    lifted::Cop2(c, Add(0, 1, 2));
    Check(c.vf[0][0] == 0 && c.vf[0][3] == 0x3f800000u, "vf0 stays constant");
    Check(generated::FloatAdd(0x7f7fffffu, 0x7f7fffffu) == 0x7f7fffffu, "EE overflow");
    Check(generated::FloatDiv(0x3f800000u, 0) == 0, "EE zero divisor");
    Check(generated::FloatAdd(0x3f800000u, 0x33c00000u) ==
          (nearest ? 0x3f800001u : 0x3f800000u), "EE rounding");
    CheckMacroBatches(nearest);
    std::printf("Runtime: %s (%s mode)\n", failures ? "FAIL" : "PASS", nearest ? "verification" : "console");
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}

#ifndef BURNOUT_RUNTIME_PROBE
int main() { return RunRuntimeTests(); }
#endif
