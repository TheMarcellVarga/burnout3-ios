# Cross-compiling the installer's window for Windows with llvm-mingw (set LLVM_MINGW
# to its folder). Used by make-windows-cross.sh.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(_llvm "$ENV{LLVM_MINGW}")
set(CMAKE_C_COMPILER "${_llvm}/bin/x86_64-w64-mingw32-clang")
set(CMAKE_CXX_COMPILER "${_llvm}/bin/x86_64-w64-mingw32-clang++")
set(CMAKE_RC_COMPILER "${_llvm}/bin/x86_64-w64-mingw32-windres")
set(CMAKE_FIND_ROOT_PATH "${_llvm}/x86_64-w64-mingw32")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
