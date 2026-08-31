cmake_minimum_required(VERSION 3.16)
project(ss_emu LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

if(MSVC)
  add_compile_options(/W4 /permissive- /utf-8)
else()
  add_compile_options(-Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

# Coeur : reproduction du firmware, sans aucune dependance systeme.
add_library(ss_emu_core STATIC
  src/avr_types.cpp
  src/firmware_sim.cpp
  src/rider_model.cpp
  src/faults.cpp
  src/port_pty.cpp
)
target_include_directories(ss_emu_core PUBLIC src)

# L'outil lui-meme.
add_executable(ss_emu src/main.cpp)
target_link_libraries(ss_emu PRIVATE ss_emu_core)

# Tests natifs : ne lancent ni Godot ni port serie.
enable_testing()
add_executable(ss_emu_tests tests/test_firmware_sim.cpp tests/test_model_and_faults.cpp)
target_link_libraries(ss_emu_tests PRIVATE ss_emu_core)
target_include_directories(ss_emu_tests PRIVATE third_party tests)
add_test(NAME ss_emu_tests COMMAND ss_emu_tests)
