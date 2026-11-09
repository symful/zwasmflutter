# Flutter tooling requires CMake 3.10+.
cmake_minimum_required(VERSION 3.10)

project(zwasm_library VERSION 0.0.1 LANGUAGES C)

# The zwasm runtime itself is Zig. We build it (plus the flat C-ABI shim in
# src/zwasm_plugin_shim.zig) into one static archive, then link the archive
# into the plugin's shared library.
find_program(ZIG_EXECUTABLE zig REQUIRED)

set(ZWASM_SRC "${CMAKE_CURRENT_SOURCE_DIR}/zwasm")
set(ZIG_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/zig")

# A pub `git:` dependency clones this repo but not its submodule. Bootstrap the
# runtime source if it is missing so the plugin builds from a git dependency.
if(NOT EXISTS "${ZWASM_SRC}/build.zig")
  find_program(GIT_EXECUTABLE git REQUIRED)
  message(STATUS "zwasm submodule missing; fetching flutter-wasm64")
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" clone --depth 1
            --branch flutter-wasm64
            https://github.com/symful/zwasm.git "${ZWASM_SRC}"
    RESULT_VARIABLE ZWASM_CLONE_RESULT
  )
  if(NOT ZWASM_CLONE_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to fetch the zwasm runtime source")
  endif()
endif()

if(ANDROID)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(ZIG_TARGET "aarch64-linux-android")
  elseif(ANDROID_ABI STREQUAL "x86_64")
    set(ZIG_TARGET "x86_64-linux-android")
  else()
    message(FATAL_ERROR "zwasm supports arm64-v8a and x86_64 on Android (got ${ANDROID_ABI})")
  endif()
  set(ZWASM_ARCHIVE "${ZIG_PREFIX}/lib/libzwasm_plugin.a")
elseif(WIN32)
  set(ZIG_TARGET "x86_64-windows-msvc")
  set(ZWASM_ARCHIVE "${ZIG_PREFIX}/lib/zwasm_plugin.lib")
else()
  message(FATAL_ERROR "zwasm supports Android, Windows and Web only")
endif()

# Run Zig every build. Zig's own cache makes this a no-op when the submodule
# is unchanged, and an always-run target avoids a stale source glob when the
# submodule moves to a different commit.
add_custom_target(zwasm_native ALL
  COMMAND "${ZIG_EXECUTABLE}" build plugin-lib
          -Doptimize=ReleaseSafe
          "-Dtarget=${ZIG_TARGET}"
          --prefix "${ZIG_PREFIX}"
  WORKING_DIRECTORY "${ZWASM_SRC}"
  BYPRODUCTS "${ZWASM_ARCHIVE}"
  COMMENT "Building zwasm static library (${ZIG_TARGET})"
  VERBATIM
)

add_library(zwasm SHARED "zwasm.c")
if(WIN32)
  # CMake's WINDOWS_EXPORT_ALL_SYMBOLS only sees object files built in this
  # target, not the symbols inside the linked Zig archive, so list them.
  target_sources(zwasm PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/zwasm_plugin.def")
endif()
add_dependencies(zwasm zwasm_native)
set_target_properties(zwasm PROPERTIES OUTPUT_NAME "zwasm")
target_compile_definitions(zwasm PUBLIC DART_SHARED_LIB)
target_include_directories(zwasm PRIVATE "${ZWASM_SRC}/include")

if(WIN32)
  # Every zw_* export lives in the archive; nothing in zwasm.c references it,
  # so pull the whole archive in and let zwasm_plugin.def export the symbols.
  target_link_options(zwasm PRIVATE "/WHOLEARCHIVE:${ZWASM_ARCHIVE}")
  target_link_libraries(zwasm PRIVATE "${ZWASM_ARCHIVE}" ntdll advapi32)
elseif(ANDROID)
  target_link_options(zwasm PRIVATE
    "-Wl,--whole-archive,${ZWASM_ARCHIVE},--no-whole-archive"
    "-Wl,-z,max-page-size=16384"
  )
  target_link_libraries(zwasm PRIVATE "${ZWASM_ARCHIVE}")
endif()
