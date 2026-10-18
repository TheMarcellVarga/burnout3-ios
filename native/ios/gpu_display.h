#pragma once
#import <UIKit/UIKit.h>
#include <functional>
namespace applehost {
// Main thread, before starting the game. Failure keeps the CPU image fallback.
UIView *InstallGpuDisplay(UIView *parent, std::function<void()> first_frame);
}
