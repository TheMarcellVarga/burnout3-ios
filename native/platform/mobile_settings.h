#pragma once

#include "ps2host/settings.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <string>

namespace applehost {
struct MobileChoice { const char *value, *title; };
struct MobileSetting {
    const char *key, *title, *help;
    std::array<MobileChoice, 3> choices;
    int count, initial;
};
enum MobileSettingID { RenderResolution, PictureShape, BlurGlow, RacingButtons,
    SteeringResponse, StickSize, ControlVisibility, MobileSettingCount };
// Saved iOS choices and defaults, shared by the game menu and Apple host.
inline const std::array<MobileSetting, MobileSettingCount>& MobileSettings() {
    static const std::array<MobileSetting, MobileSettingCount> settings = {{
        {"resolution", "Render resolution", "Original uses less GPU power. Sharper increases detail and GPU load; it can reduce frame rate and increase heat.",
         {{{"original", "Original · 640 × 448"}, {"2x", "Sharper · 1280 × 896"}}}, 2, 0},
        {"aspect", "Picture shape", "Original uses the game's 4:3 picture. Widescreen adjusts the camera and HUD for 16:9. Both fit inside the safe area without cropping.",
         {{{"4:3", "Original · 4:3"}, {"16:9", "Widescreen · 16:9"}}}, 2, 0},
        {"blur", "Blur and glow", "Restore the game's speed blur and glow. Leave off for a clearer picture and less GPU work. Reflections and depth haze stay optimized for iPhone.",
         {{{"off", "Off"}, {"original", "On"}}}, 2, 0},
        {"modern_controls", "Racing buttons", "Classic: Cross accelerates, Square brakes, R1 boosts. Triggers: R2 accelerates, L2 brakes, Cross boosts. Menu buttons stay the same.",
         {{{"off", "Classic"}, {"on", "Triggers"}}}, 2, 0},
        {"steering_response", "Steering response", "Adjust the left stick's horizontal response. Gentle gives more precision near the center; Quick turns sooner. Full movement always reaches full steering. The D-pad stays digital.",
         {{{"gentle", "Gentle"}, {"standard", "Standard"}, {"quick", "Quick"}}}, 3, 1},
        {"stick_size", "Analog stick size", "Enlarge both stick touch areas. Size adapts to the available space so sticks do not overlap the D-pad or face buttons.",
         {{{"standard", "Standard"}, {"large", "Large"}}}, 2, 0},
        {"touch_visibility", "Control visibility", "Set the resting visibility of buttons and sticks. Controls remain visible at every level and brighten while pressed.",
         {{{"subtle", "Subtle"}, {"medium", "Medium"}, {"high", "High"}}}, 3, 0},
    }};
    return settings;
}
inline int MobileChoiceIndex(int setting) {
    const auto& item = MobileSettings().at(setting);
    const auto value = ps2host::Setting(item.key, item.choices[item.initial].value);
    for (int i = 0; i < item.count; ++i) if (value == item.choices[i].value) return i;
    return item.initial;
}
inline void SetMobileChoice(int setting, int choice) {
    if (setting < 0 || setting >= MobileSettingCount) return;
    const auto& item = MobileSettings()[setting];
    if (choice >= 0 && choice < item.count) ps2host::SetSetting(item.key, item.choices[choice].value);
}
inline void NormalizeMobileSettings() {
    for (int i = 0; i < MobileSettingCount; ++i) SetMobileChoice(i, MobileChoiceIndex(i));
    // Display synchronization is managed by Metal. Desktop AA modes have no iOS UI.
    ps2host::SetSettingOn("frame_pacing", true);
    ps2host::SetSetting("antialiasing", "off");
}
inline void ResetMobileSettings() {
    for (int i = 0; i < MobileSettingCount; ++i) SetMobileChoice(i, MobileSettings()[i].initial);
    NormalizeMobileSettings();
}
inline float TouchIdleOpacity() {
    const int choice = MobileChoiceIndex(ControlVisibility);
    return choice == 2 ? 0.8f : choice == 1 ? 0.45f : 0.24f;
}
inline float MobilePictureAspect() { return MobileChoiceIndex(PictureShape) ? 16.0f / 9.0f : 4.0f / 3.0f; }
inline unsigned MobileRenderScale() { return MobileChoiceIndex(RenderResolution) ? 2 : 1; }
inline float MobileStickSize() { return MobileChoiceIndex(StickSize) ? 136.0f : 112.0f; }
inline float MobileSteering(float value) {
    if (!std::isfinite(value)) return 0;
    value = std::clamp(value, -1.0f, 1.0f);
    const int choice = MobileChoiceIndex(SteeringResponse);
    const float exponent = choice == 0 ? 1.5f : choice == 2 ? 0.65f : 1.0f;
    return std::copysign(std::pow(std::abs(value), exponent), value);
}
}
