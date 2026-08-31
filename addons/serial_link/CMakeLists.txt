# Partie C++ PURE du module serie : parseur de lignes et file SPSC.
# Elle se compile et se teste sans Godot, sans godot-cpp et sans port serie.
# C'est ce qui permet a la CI de l'eprouver sur les trois OS en quelques
# secondes, et au parseur d'etre couvert avant la moindre ligne de GDExtension.

add_library(serial_link_core STATIC
  src/line_parser.cpp
)
target_include_directories(serial_link_core PUBLIC src)

add_executable(serial_link_tests
  tests/test_line_parser.cpp
  tests/test_ring_buffer.cpp
)
target_link_libraries(serial_link_tests PRIVATE serial_link_core)
target_include_directories(serial_link_tests PRIVATE ${CMAKE_SOURCE_DIR}/third_party)

find_package(Threads REQUIRED)
target_link_libraries(serial_link_tests PRIVATE Threads::Threads)

add_test(NAME serial_link_tests COMMAND serial_link_tests)
