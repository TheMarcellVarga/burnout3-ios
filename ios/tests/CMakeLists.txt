cmake_minimum_required(VERSION 3.24)
project(TakedawnIosHostChecks C)
set(CMAKE_C_STANDARD 11)
set(XBOXRECOMP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../local/upstream/xboxrecomp" CACHE PATH "Patched Xbox runtime")
add_subdirectory(${XBOXRECOMP_DIR}/src/platform platform)
add_compile_options("SHELL:-include \"${XBOXRECOMP_DIR}/src/platform/xr_log.h\"")
add_subdirectory(${XBOXRECOMP_DIR}/tests/input_touch input_touch)
enable_testing()
add_executable(ios_session_guard session_guard_test.c ../session_guard.c)
target_include_directories(ios_session_guard PRIVATE ..)
add_test(NAME ios_session_guard COMMAND ios_session_guard)
add_executable(ios_menu_entry menu_entry_test.c ../../src/game/menuentry.c)
target_compile_definitions(ios_menu_entry PRIVATE XBOXRECOMP_IOS=1)
target_include_directories(ios_menu_entry PRIVATE ${XBOXRECOMP_DIR}/src ${XBOXRECOMP_DIR}/templates/runtime)
target_link_libraries(ios_menu_entry PRIVATE recomp_env)
add_test(NAME ios_menu_entry COMMAND ios_menu_entry)
add_executable(ios_hybrid_touch hybrid_touch_test.c ${XBOXRECOMP_DIR}/src/input/touch_pad.c)
target_include_directories(ios_hybrid_touch PRIVATE ${XBOXRECOMP_DIR}/src)
target_link_libraries(ios_hybrid_touch PRIVATE platform m)
add_test(NAME ios_hybrid_touch COMMAND ios_hybrid_touch)

# Exercise the ARM64 load/store fault decoder used by the Xbox MMIO runtime.
add_subdirectory(${XBOXRECOMP_DIR}/tests/mmio_decode_a64 mmio_decode_a64)

# Validate the shader emitters with the development Mac's Metal compiler.
# This does not establish iPhone GPU compatibility or rendering correctness.
enable_language(OBJC)
add_executable(ios_mobile_preferences mobile_preferences_test.m ../mobile_preferences.m)
target_include_directories(ios_mobile_preferences PRIVATE ..)
target_link_libraries(ios_mobile_preferences PRIVATE "-framework Foundation")
add_test(NAME ios_mobile_preferences COMMAND ios_mobile_preferences)
add_library(xbox_d3d8 STATIC
    ${XBOXRECOMP_DIR}/src/d3d/d3d8_vsh_parse.c
    ${XBOXRECOMP_DIR}/src/d3d/d3d8_combiners_parse.c
    ${XBOXRECOMP_DIR}/src/d3d/d3d8_vsh_msl.c
    ${XBOXRECOMP_DIR}/src/d3d/d3d8_combiners_msl.c)
target_include_directories(xbox_d3d8 PUBLIC ${XBOXRECOMP_DIR}/src/d3d)
add_subdirectory(${XBOXRECOMP_DIR}/tests/d3d8_msl_split d3d8_msl_split)

# Compile the mobile backing-file path on Darwin and verify true shared aliases.
add_library(ios_platform_probe STATIC ${XBOXRECOMP_DIR}/src/platform/win32_compat.c)
target_compile_definitions(ios_platform_probe PRIVATE XBOXRECOMP_IOS=1)
target_link_libraries(ios_platform_probe PUBLIC recomp_env)
target_include_directories(ios_platform_probe PUBLIC ${XBOXRECOMP_DIR}/src)
add_executable(ios_memory_alias memory_alias_test.c)
target_link_libraries(ios_memory_alias PRIVATE ios_platform_probe)
add_test(NAME ios_memory_alias COMMAND ios_memory_alias)
