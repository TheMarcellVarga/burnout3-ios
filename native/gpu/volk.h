#pragma once
// Apple builds link MoltenVK directly. Use Vulkan's normal entry points rather
// than a desktop Vulkan loader, which is not present on iOS.
#include <vulkan/vulkan.h>
inline VkResult volkInitialize() { return VK_SUCCESS; }
inline void volkLoadInstance(VkInstance) {}
