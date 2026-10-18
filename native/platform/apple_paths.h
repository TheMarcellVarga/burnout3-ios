#pragma once
#include <filesystem>
#include <vector>
#include <mach-o/dyld.h>
namespace applehost {
inline std::filesystem::path ExecutableDirectory() {
    std::uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::vector<char> buffer(size);
    if (_NSGetExecutablePath(buffer.data(), &size))
        throw std::runtime_error("Cannot determine executable path");
    return std::filesystem::weakly_canonical(buffer.data()).parent_path();
}
}
