# fatal - when a start-up failure may show a message box (src/game/fatal.c):
# never in a headless or unattended run, which has nobody to click it. The
# box itself is not shown by the test.
#   cmake --build <build> --target bo3_fatal_test && ctest -R bo3_fatal
add_executable(bo3_fatal_test test_main.c ${CMAKE_CURRENT_LIST_DIR}/../../src/game/fatal.c)
if(WIN32)
    target_link_libraries(bo3_fatal_test PRIVATE user32)
else()
    find_package(SDL2 REQUIRED)
    target_link_libraries(bo3_fatal_test PRIVATE SDL2::SDL2)
endif()
target_include_directories(bo3_fatal_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../src/game)
enable_testing()
add_test(NAME bo3_fatal COMMAND bo3_fatal_test)
