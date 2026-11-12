cmake_minimum_required(VERSION 3.21)
project(config11 LANGUAGES C)

# This is a standalone build for config11 only. Other simtools utilities are
# added to the Windows qualification work individually.
add_executable(config11 config11.c)
set_target_properties(config11 PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")

# Publish the executable beside the utility's sources after a successful link.
# Retain CMake's build-tree executable for incremental builds, tests and install.
add_custom_command(TARGET config11 POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:config11>"
        "${CMAKE_CURRENT_SOURCE_DIR}/$<TARGET_FILE_NAME:config11>"
    BYPRODUCTS "${CMAKE_CURRENT_SOURCE_DIR}/config11${CMAKE_EXECUTABLE_SUFFIX}"
    COMMENT "Placing config11 executable in the utility directory"
    VERBATIM)

if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
    target_compile_options(config11 PRIVATE
        -Wall -Wextra -Wshadow -Wpedantic -Woverflow -Wstrict-overflow)
endif()

# Keep compile and link work in the same serial pool when using Ninja.
if(CMAKE_GENERATOR MATCHES "Ninja")
    set_property(GLOBAL PROPERTY JOB_POOLS config11_serial=1)
    set_target_properties(config11 PROPERTIES
        JOB_POOL_COMPILE config11_serial
        JOB_POOL_LINK config11_serial)
endif()

include(CTest)
if(BUILD_TESTING)
    foreach(case IN ITEMS eof empty example lowercase invalid limit zero repeat)
        add_test(NAME config11.${case}
            COMMAND "${CMAKE_COMMAND}"
                "-DCONFIG11=$<TARGET_FILE:config11>"
                "-DCASE=${case}"
                "-DCASE_DIR=${CMAKE_CURRENT_BINARY_DIR}/checks/${case}"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CheckConfig11.cmake")
        set_tests_properties(config11.${case} PROPERTIES
            RUN_SERIAL TRUE TIMEOUT 15)
    endforeach()
endif()

install(TARGETS config11 RUNTIME DESTINATION bin)
install(FILES config11.txt README.cmake.md windows-gcc-validation.md
    DESTINATION share/doc/config11)
