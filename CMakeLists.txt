# Racine des cibles natives du projet.
#
# Deux ensembles, tous deux testables sans lancer Godot :
#   tools/ss_emu       — emulateur du firmware (docs/07)
#   addons/serial_link — parseur de trames et file SPSC (docs/03 §4)
#
# La partie GDExtension proprement dite se construit avec SCons, impose par la
# chaine godot-cpp. Elle ne passe pas par ici.

cmake_minimum_required(VERSION 3.16)
project(qermesse_native LANGUAGES CXX)

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

enable_testing()

add_subdirectory(tools/ss_emu)
add_subdirectory(addons/serial_link)
