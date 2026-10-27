if(NOT BURNOUT_BUILD_TRANSLATED)
    message(FATAL_ERROR "Headless host requires BURNOUT_BUILD_TRANSLATED=ON")
endif()
set(HEADLESS_DIR "${CMAKE_CURRENT_BINARY_DIR}/headless")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/generate_headless_dispatch.py" "${HEADLESS_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/local/native/vu_programs.txt"
    "${ENGINE}/tools/vurecomp.py")
file(GLOB VU_BLOCK_SOURCES CONFIGURE_DEPENDS "${HEADLESS_DIR}/vu_blocks_*.cpp")
# Registration uses a static initializer. Object files must reach the final
# executable directly; an otherwise unreferenced archive member is discarded.
add_library(burnout_vu_programs OBJECT "${HEADLESS_DIR}/vu_programs.cpp" ${VU_BLOCK_SOURCES})
target_link_libraries(burnout_vu_programs PRIVATE ps2vu_micro)
target_compile_options(burnout_vu_programs PRIVATE -O2)

# Same pinned third-party headers and checksums as upstream host/CMakeLists.txt.
set(THIRD_PARTY "${HEADLESS_DIR}/third_party")
file(MAKE_DIRECTORY "${THIRD_PARTY}")
foreach(ENTRY
    "xxhash.h|https://raw.githubusercontent.com/Cyan4973/xxHash/v0.8.3/xxhash.h|17973c0dc49d9854ca26caa191f0e12f7a424b68858d9a78de3860d959d85e4b"
    "bcdec.h|https://raw.githubusercontent.com/iOrange/bcdec/80859ed3b7afb1c527a2a99d70c61457bea72d0c/bcdec.h|134520764d96f70a27db814173616c89ad85db95fbd3328417c7a8c77e7ca189"
    "stb_image.h|https://raw.githubusercontent.com/nothings/stb/2c980bb59875b0d32144a71867fbdebb2f77cd20/stb_image.h|594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3")
    string(REPLACE "|" ";" PARTS "${ENTRY}")
    list(GET PARTS 0 NAME)
    list(GET PARTS 1 URL)
    list(GET PARTS 2 SHA)
    if(NOT EXISTS "${THIRD_PARTY}/${NAME}")
        file(DOWNLOAD "${URL}" "${THIRD_PARTY}/${NAME}" EXPECTED_HASH "SHA256=${SHA}" TLS_VERIFY ON)
    endif()
endforeach()

file(GLOB HOST_SOURCES CONFIGURE_DEPENDS "${ENGINE}/host/src/*.cpp")
list(REMOVE_ITEM HOST_SOURCES "${ENGINE}/host/src/main.cpp" "${ENGINE}/host/src/window.cpp"
    "${ENGINE}/host/src/audio.cpp" "${ENGINE}/host/src/vu.cpp")
add_library(ps2host_apple STATIC ${HOST_SOURCES} native/headless/platform.cpp)
target_include_directories(ps2host_apple PUBLIC "${ENGINE}/host/include" PRIVATE "${HEADLESS_DIR}" "${THIRD_PARTY}")
target_link_libraries(ps2host_apple PUBLIC ps2rt ps2vu_micro apple_fibers)
if(BURNOUT_BUILD_GPU)
    target_compile_definitions(ps2host_apple PUBLIC PS2HOST_VULKAN=1)
    target_link_libraries(ps2host_apple PUBLIC ps2gpu_apple)
endif()
# Pixel reads/writes live in separate translation units from rasterization.
# ThinLTO allows the optimizer to inline those hot calls across the host archive.
set_property(TARGET ps2host_apple PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
target_compile_options(ps2host_apple PRIVATE -include "${CMAKE_CURRENT_SOURCE_DIR}/native/platform/msvc_crt.h")
# The software GS rasterizer is otherwise unusably slow in an unoptimized
# diagnostic build. Keep IEEE behavior and rounding controls; optimize the host.
target_compile_options(ps2host_apple PRIVATE "$<$<CONFIG:Debug>:-O2>")

set(GAME_PORT "${CMAKE_CURRENT_SOURCE_DIR}/local/upstream/burnout3-pc/games/burnout3/port")
add_library(burnout_game_host STATIC "${HEADLESS_DIR}/dispatch.cpp" "${HEADLESS_DIR}/discovered.cpp"
    "${GAME_PORT}/overrides.cpp" "${GAME_PORT}/iop_servers.cpp" "${GAME_PORT}/widescreen.cpp"
    "${GAME_PORT}/mouse.cpp" "${GAME_PORT}/prompts.cpp" "${GAME_PORT}/controls.cpp")
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    target_compile_definitions(burnout_game_host PRIVATE BURNOUT_IOS=1)
    target_compile_definitions(ps2host_apple PRIVATE BURNOUT_IOS=1)
endif()
target_link_libraries(burnout_game_host PUBLIC burnout_translated ps2host_apple)
target_sources(burnout_game_host INTERFACE $<TARGET_OBJECTS:burnout_vu_programs>)
add_executable(burnout_headless native/headless/main.cpp)
target_link_libraries(burnout_headless PRIVATE burnout_game_host)
set_property(TARGET burnout_headless PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

add_custom_command(OUTPUT "${HEADLESS_DIR}/vu_corpus.cpp"
    COMMAND "${Python3_EXECUTABLE}" "${ENGINE}/tools/vurecomp.py" --corpus --count 120 --seed 1
        --out "${HEADLESS_DIR}/vu_corpus.cpp"
    DEPENDS "${ENGINE}/tools/vurecomp.py")
add_executable(apple_host_tests "${ENGINE}/host/tests/host_tests.cpp" "${HEADLESS_DIR}/vu_corpus.cpp")
target_include_directories(apple_host_tests PRIVATE "${ENGINE}/host/src")
target_link_libraries(apple_host_tests PRIVATE ps2host_apple)
set_property(TARGET apple_host_tests PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
add_test(NAME apple_host_semantics COMMAND apple_host_tests)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # Compile the real iOS menu choices without linking the translated game.
    # Dead stripping drops unused guest hooks from the included port source.
    add_executable(ios_settings_tests native/tests/ios_settings_tests.cpp)
    target_include_directories(ios_settings_tests PRIVATE "${GAME_PORT}" native/ios)
    target_compile_options(ios_settings_tests PRIVATE -ffunction-sections -fdata-sections)
    target_link_options(ios_settings_tests PRIVATE -Wl,-dead_strip)
    target_link_libraries(ios_settings_tests PRIVATE ps2host_apple)
    add_test(NAME ios_settings COMMAND ios_settings_tests)
    add_executable(vu_capture_tests native/tests/vu_capture_tests.cpp $<TARGET_OBJECTS:burnout_vu_programs>)
    target_link_libraries(vu_capture_tests PRIVATE ps2host_apple)
    add_executable(gs_thread_tests native/tests/gs_thread_tests.cpp)
    target_link_libraries(gs_thread_tests PRIVATE ps2host_apple)
    add_test(NAME gs_thread_backpressure COMMAND gs_thread_tests)
    set_tests_properties(gs_thread_backpressure PROPERTIES TIMEOUT 20)
    add_executable(headless_io_tests native/tests/headless_io_tests.cpp)
    target_link_libraries(headless_io_tests PRIVATE ps2host_apple)
    set_property(TARGET headless_io_tests PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
    add_test(NAME headless_io COMMAND headless_io_tests)
endif()
