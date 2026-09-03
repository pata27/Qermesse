# Emulateur de firmware — docs/07.
#
# Se construit aussi bien seul (`cmake -S tools/ss_emu -B <build>`) que depuis
# la racine. Le README documente les deux ; le mode SEUL etait pourtant casse :
# sans `cmake_minimum_required` ni `project()`, CMake refusait de configurer un
# dossier pris comme racine. Le drapeau ci-dessous existait, mais rien ne
# declarait le projet — l'intention etait ecrite, pas implementee.
#
# `cmake_minimum_required` est repete ici sans dommage quand ce fichier est
# inclus depuis la racine : il ne fait que reposer les memes politiques.
cmake_minimum_required(VERSION 3.16)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(ss_emu LANGUAGES CXX)
  set(SS_EMU_STANDALONE TRUE)
  # `add_test` reste sans effet si personne n'a appele `enable_testing()` au
  # niveau racine : construit seul, `ctest` repondait « No tests were found ».
  # Depuis la racine du projet, c'est le CMakeLists parent qui l'appelle.
  enable_testing()
else()
  set(SS_EMU_STANDALONE FALSE)
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
