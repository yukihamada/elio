cmake_minimum_required(VERSION 3.16)
project(CAgentLib C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Compiler flags
if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Wpedantic")
    set(CMAKE_C_FLAGS_DEBUG "-g -O0 -DDEBUG")
    set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
endif()

# iOS specific settings
if(CMAKE_SYSTEM_NAME MATCHES "iOS")
    set(CMAKE_OSX_ARCHITECTURES "arm64")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fembed-bitcode")
endif()

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# Source files
set(AGENT_LIB_SOURCES
    src/agent_lib.c
    src/agent_context.c
    src/agent_string.c
    src/agent_json.c
    src/agent_parser.c
    src/agent_orchestrator.c
    src/agent_mcp.c
)

# Static library
add_library(agent_lib STATIC ${AGENT_LIB_SOURCES})

target_include_directories(agent_lib PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Apple frameworks (for UUID generation)
if(APPLE)
    find_library(SECURITY_FRAMEWORK Security)
    if(SECURITY_FRAMEWORK)
        target_link_libraries(agent_lib PRIVATE ${SECURITY_FRAMEWORK})
    endif()
endif()

# Tests
option(BUILD_TESTS "Build test executables" ON)

if(BUILD_TESTS)
    enable_testing()

    # Test executables
    add_executable(test_string tests/test_string.c)
    target_link_libraries(test_string agent_lib)
    add_test(NAME test_string COMMAND test_string)

    add_executable(test_json tests/test_json.c)
    target_link_libraries(test_json agent_lib)
    add_test(NAME test_json COMMAND test_json)

    add_executable(test_parser tests/test_parser.c)
    target_link_libraries(test_parser agent_lib)
    add_test(NAME test_parser COMMAND test_parser)

    add_executable(test_orchestrator tests/test_orchestrator.c)
    target_link_libraries(test_orchestrator agent_lib)
    add_test(NAME test_orchestrator COMMAND test_orchestrator)
endif()

# Install
install(TARGETS agent_lib
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
