cmake_minimum_required(VERSION 3.25)

# ut2004-stats-bridge: the LCServer package's stats lines -> LANCommander match statistics.
# Built by the image's Dockerfile; see src/main.cpp.
#
#   LANCOMMANDER_INTERPOSER_DIR  a LANCommander.Interposer source tree

project(ut2004-stats-bridge VERSION 1.0.0 LANGUAGES C CXX)

set(LANCOMMANDER_INTERPOSER_DIR "" CACHE PATH "A LANCommander.Interposer source tree")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# The Interposer's embeddable library, with match statistics only
set(INTERPOSER_EMBEDDED_ONLY ON CACHE BOOL "" FORCE)
set(INTERPOSER_FEATURE_MATCHES ON CACHE BOOL "" FORCE)
add_subdirectory("${LANCOMMANDER_INTERPOSER_DIR}" interposer EXCLUDE_FROM_ALL)

find_package(nlohmann_json 3 REQUIRED)
find_package(Threads REQUIRED)

add_executable(ut2004-stats-bridge
    src/main.cpp
    src/reporter.cpp
    src/translator.cpp)

target_link_libraries(ut2004-stats-bridge PRIVATE
    LANCommander::Interposer::Embedded
    nlohmann_json::nlohmann_json
    Threads::Threads)
target_compile_options(ut2004-stats-bridge PRIVATE -Wall -Wextra)
target_link_options(ut2004-stats-bridge PRIVATE -static-libstdc++ -static-libgcc)

install(TARGETS ut2004-stats-bridge RUNTIME DESTINATION bin)
