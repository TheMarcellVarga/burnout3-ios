// Additional Metal regression: preserve mask bits after blending, and refresh
// destination feedback when another masked primitive overlaps the first.
int RunGpuMaskChecks(ps2gpu::GsRenderer& renderer) {
    auto state = Target(0xA0);
    Rect(renderer, state, 0, 0, 32, 32, 0x2547698Bu);
    state.fbmsk = 0x0F0F0F0Fu;
    state.blend = true;
    state.c = ps2gpu::BlendAlpha::Fix;
    state.fix = 0x40;
    Rect(renderer, state, 0, 0, 24, 24, 0x80C0A040u);
    Rect(renderer, state, 0, 0, 8, 8, 0x4080C0FFu);
    int failures = 0;
    if (Pixel(renderer, 0xA0, 16, 16) != 0x8587896Bu) {
        std::printf("FAIL: partial mask preserves destination bits after blending\n");
        ++failures;
    }
    if (Pixel(renderer, 0xA0, 2, 2) != 0x4587A9BBu) {
        std::printf("FAIL: overlapping partial masks refresh destination feedback\n");
        ++failures;
    }
    // A narrow transfer must preserve every byte outside its GS block. Compare
    // with the existing full-width transfer for 32-bit and both 16-bit layouts.
    for (unsigned format : {0u, 2u, 10u}) {
        std::vector<unsigned char> sentinel(4u << 20, 0xA5), full(sentinel.size()), partial(sentinel.size());
        renderer.MemoryWrite(0, 16384, sentinel.data());
        auto strip = Target(0xA4);
        strip.psm = format; strip.fbw = 3; strip.width = 192; strip.height = 128;
        strip.scissor_x1 = 191; strip.scissor_y1 = 127;
        Rect(renderer, strip, 0, 0, 192, 128, 0x7F4D2B19u);
        renderer.Kick();
        renderer.TargetToMemory(strip.fbp, strip.fbw, format, 192, 128);
        renderer.MemoryRead(0, 16384, full.data());
        renderer.MemoryWrite(0, 16384, sentinel.data());
        const unsigned y = format == 0 ? 32 : 64, width = format == 0 ? 8 : 16;
        renderer.TargetToMemory(strip.fbp, strip.fbw, format, 64 + width, y + 8, y, 64);
        renderer.MemoryRead(0, 16384, partial.data());
        const unsigned block = (strip.fbp * 32 + 128) * 256;
        bool ok = true;
        for (unsigned i = 0; i < partial.size(); ++i)
            if (partial[i] != (i >= block && i < block + 256 ? full[i] : sentinel[i])) { std::printf("narrow mismatch at %X got %02X expected %02X full %02X, block %X\n", i, partial[i], i >= block && i < block + 256 ? full[i] : sentinel[i], full[i], block); ok = false; break; }
        if (!ok) { std::printf("FAIL: narrow write-back preserves surrounding memory (PSM %02X)\n", format); ++failures; }
    }
    return failures;
}
