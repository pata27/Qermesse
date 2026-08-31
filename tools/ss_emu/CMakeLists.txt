# Emulateur de firmware — docs/07.
# Se construit aussi bien seul (cmake -S tools/ss_emu) que depuis la racine.

if(NOT DEFINED PROJECT_NAME OR NOT CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  set(SS_EMU_STANDALONE FALSE)
else()
  set(SS_EMU_STANDALONE TRUE)
endif()

# Coeur : reproduction du firmware, sans dependance systeme pour FirmwareSim.
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
find_package(Threads REQUIRED)
target_link_libraries(ss_emu PRIVATE Threads::Threads)

# Tests natifs : ne lancent ni Godot ni port serie.
add_executable(ss_emu_tests tests/test_firmware_sim.cpp tests/test_model_and_faults.cpp)
target_link_libraries(ss_emu_tests PRIVATE ss_emu_core)
target_include_directories(ss_emu_tests PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party
  ${CMAKE_CURRENT_SOURCE_DIR}/tests
)
add_test(NAME ss_emu_tests COMMAND ss_emu_tests)
