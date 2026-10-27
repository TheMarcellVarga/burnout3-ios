#pragma once
#import <UIKit/UIKit.h>
#include <functional>
namespace applehost {
// Main thread, before starting the game. Failure keeps the CPU image fallback.
void SetGpuDisplayScale(UIView *view, unsigned scale);
UIView *InstallGpuDisplay(UIView *parent, std::function<void()> first_frame);
}
