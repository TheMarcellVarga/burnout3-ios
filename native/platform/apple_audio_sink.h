#pragma once
namespace applehost {
struct AudioSink {
    bool (*open)() = nullptr;
    void (*close)() = nullptr;
    void (*write)(const short*, unsigned) = nullptr;
};
// Install before running the game; callbacks stay valid until audio is closed.
void SetAudioSink(AudioSink sink);
}
