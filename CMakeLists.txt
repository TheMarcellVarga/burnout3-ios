cmake_minimum_required(VERSION 3.24)
project(BurnoutNative LANGUAGES CXX)
enable_language(ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(ENGINE "${CMAKE_CURRENT_SOURCE_DIR}/local/upstream/burnout3-pc/engine")
if(NOT EXISTS "${ENGINE}/runtime/src/vu0.cpp")
    message(FATAL_ERROR "Run python3 scripts/prepare_native.py first")
endif()

add_library(apple_fibers STATIC native/platform/apple_fibers.cpp
    native/vendor/boost-context/make_arm64_aapcs_macho_gas.S
    native/vendor/boost-context/jump_arm64_aapcs_macho_gas.S)
target_include_directories(apple_fibers PUBLIC native/platform)
target_compile_options(apple_fibers PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:-frounding-math>")
if(NOT APPLE)
    message(FATAL_ERROR "This port experiment currently targets Apple platforms")
endif()

add_library(ps2rt STATIC
    "${ENGINE}/runtime/src/eefpu.cpp"
    "${ENGINE}/runtime/src/eeint.cpp"
    "${ENGINE}/runtime/src/vu0.cpp"
    "${ENGINE}/runtime/src/lifted_support.cpp")
target_include_directories(ps2rt PUBLIC "${ENGINE}/runtime/include")
# Runtime rounding changes are observable; contraction or fast math can change
# game behavior even when the translated instruction sequence is unchanged.
target_compile_options(ps2rt PUBLIC -frounding-math -ffp-contract=off)

# The VU microprogram host shares the portable runtime rounding scope;
# the Apple game host supplies its remaining services.
add_library(ps2vu_micro STATIC "${ENGINE}/host/src/vu.cpp")
target_include_directories(ps2vu_micro PUBLIC "${ENGINE}/host/include")
target_link_libraries(ps2vu_micro PUBLIC ps2rt)

option(BURNOUT_BUILD_TRANSLATED "Compile the generated executable translation" OFF)
if(BURNOUT_BUILD_TRANSLATED)
    set(GAME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/native/game")
    if(NOT EXISTS "${GAME_DIR}/manifest.json")
        message(FATAL_ERROR "Run python3 scripts/emit_native_game.py first")
    endif()
    file(READ "${GAME_DIR}/manifest.json" GAME_MANIFEST)
    string(JSON CHUNK_COUNT LENGTH "${GAME_MANIFEST}" chunks)
    if(CHUNK_COUNT LESS 1)
        message(FATAL_ERROR "No translated chunks in the game manifest")
    endif()
    math(EXPR LAST_CHUNK "${CHUNK_COUNT} - 1")
    set(GAME_SOURCES)
    foreach(INDEX RANGE ${LAST_CHUNK})
        string(JSON CHUNK GET "${GAME_MANIFEST}" chunks ${INDEX})
        list(APPEND GAME_SOURCES "${GAME_DIR}/${CHUNK}")
    endforeach()
    add_library(burnout_translated STATIC ${GAME_SOURCES})
    target_link_libraries(burnout_translated PUBLIC ps2rt)
    # Optimize the large generated translation without O3 code-size expansion.
    target_compile_options(burnout_translated PRIVATE "$<$<CONFIG:Release>:-O2>")
endif()

find_package(Python3 3.10 REQUIRED COMPONENTS Interpreter)
set(HARNESS "${CMAKE_CURRENT_BINARY_DIR}/generated/host.cpp")
execute_process(COMMAND "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/export_native_harness.py" "${HARNESS}"
    COMMAND_ERROR_IS_FATAL ANY)

option(BURNOUT_BUILD_GPU "Build off-screen Vulkan/Metal rendering with MoltenVK" OFF)
if(BURNOUT_BUILD_GPU)
    include(cmake/AppleGpu.cmake)
endif()

option(BURNOUT_BUILD_HEADLESS "Build the Apple headless game host" OFF)
if(BURNOUT_BUILD_HEADLESS)
    include(cmake/HeadlessHost.cmake)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/native/ios/Info.plist")
    enable_language(OBJCXX)
    if(BURNOUT_BUILD_HEADLESS)
        add_executable(BurnoutNativeProbe MACOSX_BUNDLE
            native/ios/main.mm native/ios/native_boot.mm native/ios/mobile_quality.cpp native/ios/sixty_fps.cpp native/ios/game_launch.mm native/ios/analog_stick.mm native/tests/analog_tracking_tests.mm native/ios/audio.mm native/tests/runtime_tests.cpp)
        target_compile_definitions(BurnoutNativeProbe PRIVATE BURNOUT_NATIVE_HOST=1)
        target_include_directories(BurnoutNativeProbe PRIVATE native/ios)
        target_link_libraries(BurnoutNativeProbe PRIVATE burnout_game_host)
        if(BURNOUT_BUILD_GPU)
            target_sources(BurnoutNativeProbe PRIVATE "${PS2GPU_TEST_HARNESS}" native/ios/gpu_display.mm)
            target_include_directories(BurnoutNativeProbe PRIVATE "${ENGINE}/gpu/src" "${MVK_ROOT}/include" native/gpu)
            configure_file("${MVK_ROOT}/../LICENSE" "${CMAKE_CURRENT_BINARY_DIR}/licenses/MoltenVK.txt" COPYONLY)
            configure_file("${ENGINE}/LICENSE" "${CMAKE_CURRENT_BINARY_DIR}/licenses/PS2Recomp.txt" COPYONLY)
            configure_file("${CMAKE_CURRENT_SOURCE_DIR}/local/upstream/burnout3-pc/LICENSE"
                "${CMAKE_CURRENT_BINARY_DIR}/licenses/Burnout3-PC.txt" COPYONLY)
            file(GLOB GPU_LICENSES "${CMAKE_CURRENT_BINARY_DIR}/licenses/*.txt")
            set_source_files_properties(${GPU_LICENSES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses)
            target_sources(BurnoutNativeProbe PRIVATE ${GPU_LICENSES})
        endif()
    else()
        add_executable(BurnoutNativeProbe MACOSX_BUNDLE
            native/ios/main.mm native/tests/runtime_tests.cpp "${HARNESS}")
    endif()
    set_property(TARGET BurnoutNativeProbe PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
    set_source_files_properties(native/ios/Assets.xcassets PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_sources(BurnoutNativeProbe PRIVATE native/ios/Assets.xcassets)
    target_compile_definitions(BurnoutNativeProbe PRIVATE BURNOUT_RUNTIME_PROBE=1)
    target_compile_options(BurnoutNativeProbe PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
    target_link_libraries(BurnoutNativeProbe PRIVATE ps2rt "-framework UIKit" "-framework CoreGraphics" "-framework AVFAudio" "-framework UniformTypeIdentifiers")
    set_target_properties(BurnoutNativeProbe PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/native/ios/Info.plist"
        MACOSX_BUNDLE_GUI_IDENTIFIER "dev.burnout3.nativeprobe"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "dev.burnout3.nativeprobe"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
        XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
        XCODE_GENERATE_SCHEME TRUE)
    if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.25)
        set_property(TARGET BurnoutNativeProbe PROPERTY XCODE_SCHEME_LAUNCH_CONFIGURATION Release)
    endif()
else()
    add_executable(fiber_tests native/tests/fiber_tests.cpp)
    target_link_libraries(fiber_tests PRIVATE apple_fibers)
    add_executable(runtime_tests native/tests/runtime_tests.cpp "${HARNESS}")
    target_link_libraries(runtime_tests PRIVATE ps2rt)
    enable_testing()
    add_test(NAME apple_fiber_scheduling COMMAND fiber_tests)
    add_test(NAME console_rounding COMMAND runtime_tests)
    set_tests_properties(console_rounding PROPERTIES
        ENVIRONMENT_MODIFICATION "PS2RT_EE_ROUND_NEAREST=unset:")
    add_test(NAME verification_rounding COMMAND runtime_tests)
    set_tests_properties(verification_rounding PROPERTIES
        ENVIRONMENT "PS2RT_EE_ROUND_NEAREST=1")
endif()
