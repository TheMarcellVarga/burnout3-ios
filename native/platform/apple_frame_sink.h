#pragma once
#include <cstdint>
#include <functional>
#include <vector>
namespace applehost {
using FrameSink = std::function<void(const std::vector<std::uint32_t>&, std::uint32_t, std::uint32_t)>;
// Set only before starting the host or after its GS worker has joined.
void SetFrameSink(FrameSink sink);
}
