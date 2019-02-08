cmake_minimum_required(VERSION 3.16)
project(keelson C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

include_directories(src/c/include /opt/homebrew/include /usr/local/include)
link_directories(/opt/homebrew/lib /usr/local/lib)

file(GLOB SOURCES "src/c/*.c")

if(SOURCES)
    add_executable(keelson ${SOURCES})
    find_library(WREN_LIB wren HINTS /opt/homebrew/lib /usr/local/lib)
    if(WREN_LIB)
        target_link_libraries(keelson PRIVATE ${WREN_LIB})
    endif()
endif()

enable_testing()
add_test(NAME LintEmDashes COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/lint_em_dashes.sh)
