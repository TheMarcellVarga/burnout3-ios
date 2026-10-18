#pragma once
namespace applehost {
// DualShock 2 bit order: select, L3, R3, start, up, right, down,
// left, L2, R2, L1, R1, triangle, circle, cross, square.
void EnableTouchController(bool enabled);
void SetTouchButton(unsigned input, bool held);
// stick 0 is left, 1 is right. Axes range -1 to 1; negative Y is up.
void SetTouchStick(unsigned stick, float x, float y);
void ReleaseTouchButtons();
}
