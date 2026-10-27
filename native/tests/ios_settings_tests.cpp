// Exercise the actual in-game menu against bounded guest-memory/drawing fixtures.
#define BURNOUT_IOS 1
#include "overrides.cpp"
#include "mobile_settings.h"
#include "apple_touch_input.h"
#include <filesystem>
#include <unistd.h>

// Simulate only the original game's string lookup/drawing; all menu code is real.
void F_00271A00(lifted::Context& c) {
    for (unsigned i = 0; i < sizeof(kDonors) / sizeof(kDonors[0]); ++i)
        if (c.r[5] == kDonors[i].id) { c.r[2] = 0x10000 + i * 0x1000; return; }
    c.r[2] = 0;
}
void F_00321470(lifted::Context&) {}
void F_0031C350(lifted::Context&) {}
void F_003181E0(lifted::Context&) {}
void F_00318100(lifted::Context&) {}
static u32 messageResult = kNo;
static unsigned closedBoxes = 0;
static void DrawFixture(lifted::Context&) {}
static void ConfirmFixture(lifted::Context& c) { c.r[2] = 1; }
static void MessageFixture(lifted::Context& c) { c.r[2] = messageResult; }
static void CloseFixture(lifted::Context&) { ++closedBoxes; }

static int CheckGameMenu() {
    ps2host::Override(0x0022CFE0u, ConfirmFixture, "test confirm");
    ps2host::Override(0x0031FE40u, DrawFixture, "test redraw");
    ps2host::Override(0x0031ECD0u, DrawFixture, "test legend");
    ps2host::Override(0x0032D080u, DrawFixture, "test message");
    ps2host::Override(0x0032B2C0u, MessageFixture, "test message input");
    ps2host::Override(0x003ABC00u, CloseFixture, "test close message");
    generated::Write32(kMessageBox, 0x00200000u);
    generated::Write32(0x0020000Cu, 0x003ABC00u);
    constexpr u32 menu = 0x00070000u, entries = 0x00050000u, helps = 0x00060000u;
    for (u32 i = 0; i < 5; ++i) {
        generated::Write32(entries + i * 8, 0x80000 + i * 32);
        generated::Write32(entries + i * 8 + 4, 0);
        generated::Write32(helps + i * 4, 0x90000 + i * 32);
    }
    lifted::Context c{};
    c.r[4] = 0x001E89544u; c.r[5] = menu + 0x14; c.r[6] = entries; c.r[31] = 0x00318464u;
    MenuList(c);
    if (!g_main.made || generated::ReadU16(menu + 0x16) != 5) return 20;
    c.r[6] = helps; c.r[31] = 0x003184A8u;
    MenuHelps(c);
    c.r[4] = menu;
    generated::Write16(menu + 0x14, kPcSettingsEntry);
    MainMenuInput(c);
    if (g_main.page != Page::kPcSettings || g_main.row_count != 3) return 21;
    generated::Write16(menu + 0x14, 0);
    MainMenuInput(c);
    if (g_main.page != Page::kVideo || g_main.row_count != 3) return 22;
    for (u32 option = 0; option < kOptionCount; ++option) {
        ShowPage(c, kOptions[option].page);
        if (g_main.row_count > kEntries) return 23;
        int row = -1;
        for (u32 i = 0; i < g_main.row_count; ++i) if (g_main.rows[i] == int(option)) row = int(i);
        if (row < 0) return 24;
        generated::Write16(menu + 0x14, row);
        const int before = kOptions[option].now();
        MainMenuInput(c); // Actual Cross handling, guest-label update, persistence and redraw.
        const std::string file = ps2host::SettingsPath();
        ps2host::LoadSettings(file);
        if (kOptions[option].now() != (before + 1) % kOptions[option].count) return 25;
    }
    applehost::SetMobileChoice(applehost::RenderResolution, 1);
    for (u32 answer : {kNo, kYes}) {
        ShowPage(c, Page::kPcSettings, 2);
        MainMenuInput(c);
        if (!g_main.quitting || generated::ReadU16(kMessageBox + 0x0C) != 1) return 26;
        messageResult = answer;
        MainMenu(c); // NO preserves choices; YES resets without exiting the game.
        if (g_main.quitting) return 27;
        if (applehost::MobileRenderScale() != (answer == kNo ? 2u : 1u)) return 28;
    }
    if (closedBoxes != 2) return 29;
    ShowPage(c, Page::kMainMenu);
    if (generated::ReadU16(menu + 0x16) != 5 || generated::ReadU16(menu + 0x14) != kPcSettingsEntry) return 30;
    for (u32 i = 0; i < 5; ++i)
        if (generated::ReadU32(g_main.entries + i * 8) != 0x80000 + i * 32 ||
            generated::ReadU32(g_main.helps + i * 4) != 0x90000 + i * 32) return 31;
    return 0;
}

int main() {
    const auto path = std::filesystem::temp_directory_path() /
        ("burnout-ios-settings-" + std::to_string(getpid()) + ".ini");
    ps2host::LoadSettings(path.string());
    if (kEntries != 5 || kOptionCount != 7 || applehost::MobileSettingCount != 7) return 1;
    // Migrate unsupported PC values before the renderer can use them.
    ps2host::SetSetting("resolution", "display");
    ps2host::SetSetting("aspect", "auto");
    ps2host::SetSetting("frame_pacing", "off");
    ps2host::SetSetting("antialiasing", "ssaa4");
    ps2host::SetSetting("unrelated_game_option", "keep");
    applehost::NormalizeMobileSettings();
    if (applehost::MobileRenderScale() != 1 || applehost::MobilePictureAspect() != 4.0f/3.0f ||
        !ps2host::SettingOn("frame_pacing") || ps2host::Setting("antialiasing") != "off") return 2;
    for (int setting = 0; setting < applehost::MobileSettingCount; ++setting) {
        const auto& item = applehost::MobileSettings()[setting];
        for (int value = 0; value < item.count; ++value) {
            applehost::SetMobileChoice(setting, value);
            ps2host::LoadSettings(path.string()); // Verify the next launch's exact values.
            if (applehost::MobileChoiceIndex(setting) != value ||
                ps2host::Setting(item.key) != item.choices[value].value) return 3;
        }
    }
    if (applehost::MobileRenderScale() != 2 || applehost::MobilePictureAspect() != 16.0f/9.0f ||
        applehost::MobileStickSize() != 136 || applehost::TouchIdleOpacity() != 0.8f) return 4;
    applehost::SetMobileChoice(applehost::SteeringResponse, 0);
    if (!(applehost::MobileSteering(0.5f) < 0.5f)) return 5;
    applehost::SetMobileChoice(applehost::SteeringResponse, 2);
    if (!(applehost::MobileSteering(0.5f) > 0.5f) || applehost::MobileSteering(-1) != -1 ||
        applehost::MobileSteering(1) != 1 || applehost::MobileSteering(0) != 0 ||
        applehost::MobileSteering(NAN) != 0 || applehost::MobileSteering(10) != 1) return 6;
    applehost::ResetMobileSettings();
    ps2host::LoadSettings(path.string());
    for (int i = 0; i < applehost::MobileSettingCount; ++i)
        if (applehost::MobileChoiceIndex(i) != applehost::MobileSettings()[i].initial) return 9;
    if (ps2host::Setting("unrelated_game_option") != "keep" ||
        applehost::MobileSteering(0.5f) != 0.5f || applehost::TouchIdleOpacity() != 0.24f) return 10;
    const int menuResult = CheckGameMenu();
    if (menuResult) return menuResult;
    if (ps2host::Setting("unrelated_game_option") != "keep") return 32;
    std::filesystem::remove(path);
    return 0;
}
