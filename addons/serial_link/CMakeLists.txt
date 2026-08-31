# Partie C++ PURE du module serie : parseur de lignes et file SPSC.
# Elle se compile et se teste sans Godot, sans godot-cpp et sans port serie.
# C'est ce qui permet a la CI de l'eprouver sur les trois OS en quelques
# secondes, et au parseur d'etre couvert avant la moindre ligne de GDExtension.

add_library(serial_link_core STATIC
  src/line_parser.cpp
  src/port_selection.cpp
  src/link_driver.cpp
  src/serial_port_posix.cpp
  src/serial_port_win.cpp
)
target_include_directories(serial_link_core PUBLIC src)

# Enumeration des ports avec VID/PID : la seule partie qui touche a l'OS.
if(APPLE)
  target_link_libraries(serial_link_core PUBLIC "-framework IOKit" "-framework CoreFoundation")
elseif(WIN32)
  target_link_libraries(serial_link_core PUBLIC setupapi)
endif()

add_executable(serial_link_tests
  tests/test_line_parser.cpp
  tests/test_ring_buffer.cpp
  tests/test_link_driver.cpp
  tests/test_integration_pty.cpp
)
target_link_libraries(serial_link_tests PRIVATE serial_link_core)

# Le test d'integration relie le driver a l'emulateur de firmware par un vrai
# pseudo-terminal. POSIX seulement — sous Windows le fichier se compile a vide.
target_link_libraries(serial_link_tests PRIVATE ss_emu_core)
target_include_directories(serial_link_tests PRIVATE ${CMAKE_SOURCE_DIR}/tools/ss_emu/src)
target_include_directories(serial_link_tests PRIVATE ${CMAKE_SOURCE_DIR}/third_party)

find_package(Threads REQUIRED)
target_link_libraries(serial_link_tests PRIVATE Threads::Threads)

add_test(NAME serial_link_tests COMMAND serial_link_tests)
