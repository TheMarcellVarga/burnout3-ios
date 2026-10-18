#pragma once
#ifndef _WIN32
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <ctime>
inline int gmtime_s(std::tm* result, const std::time_t* value) {
    return gmtime_r(value, result) ? 0 : errno;
}
inline int localtime_s(std::tm* result, const std::time_t* value) {
    return localtime_r(value, result) ? 0 : errno;
}
inline int _fseeki64(std::FILE* file, std::int64_t offset, int origin) {
    static_assert(sizeof(off_t) == 8, "Disc offsets must be 64-bit");
    return fseeko(file, off_t(offset), origin);
}
inline std::int64_t _ftelli64(std::FILE* file) { return ftello(file); }
inline std::uint64_t _byteswap_uint64(std::uint64_t value) { return __builtin_bswap64(value); }
#endif
