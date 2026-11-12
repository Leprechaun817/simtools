cmake_minimum_required(VERSION 3.21)
project(fsio LANGUAGES C)

option(FSIO_USE_READLINE "Use GNU Readline for interactive command editing" OFF)
add_executable(fsio fsio.c declib.c tape.c dos11.c rt11.c dosmt.c local.c
    os8.c unixv7.c)
set_target_properties(fsio PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED YES
    C_EXTENSIONS YES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
target_compile_definitions(fsio PRIVATE DEBUG _FILE_OFFSET_BITS=64)
if(WIN32)
    if(NOT MINGW)
        message(FATAL_ERROR "The qualified Windows build requires MinGW-w64 GCC")
    endif()
    target_compile_definitions(fsio PRIVATE _BSD_SOURCE _POSIX_THREAD_SAFE_FUNCTIONS)
    target_sources(fsio PRIVATE compat/fnmatch.c)
    target_include_directories(fsio PRIVATE compat)
endif()
if(FSIO_USE_READLINE)
    find_path(READLINE_INCLUDE_DIR readline/readline.h REQUIRED)
    find_library(READLINE_LIBRARY readline REQUIRED)
    target_include_directories(fsio PRIVATE "${READLINE_INCLUDE_DIR}")
    target_link_libraries(fsio PRIVATE "${READLINE_LIBRARY}")
else()
    target_compile_definitions(fsio PRIVATE FSIO_NO_READLINE)
endif()
if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
    target_compile_options(fsio PRIVATE -Wall -Wextra -Wshadow -Wpedantic
        -Woverflow -Wstrict-overflow)
endif()
if(CMAKE_GENERATOR MATCHES "Ninja")
    set_property(GLOBAL PROPERTY JOB_POOLS fsio_serial=1)
    set_target_properties(fsio PROPERTIES JOB_POOL_COMPILE fsio_serial
        JOB_POOL_LINK fsio_serial)
endif()
add_custom_command(TARGET fsio POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:fsio>"
        "${CMAKE_CURRENT_SOURCE_DIR}/$<TARGET_FILE_NAME:fsio>"
    BYPRODUCTS "${CMAKE_CURRENT_SOURCE_DIR}/fsio${CMAKE_EXECUTABLE_SUFFIX}"
    COMMENT "Placing fsio executable in the utility directory" VERBATIM)

include(CTest)
if(BUILD_TESTING AND WIN32)
    find_program(FSIO_PWSH pwsh PATHS "C:/Program Files/PowerShell/7"
        NO_DEFAULT_PATH REQUIRED)
    foreach(case IN ITEMS commands local dos11 rt11-default rt11-rk05 rt11-rl01
            rt11-rl02 rt11-rx01 rt11-rx02 rt11-extra os8-rk05 os8-rx01
            os8-rx02 os8-extra dosmt dosmt-extended unixv7-default
            unixv7-small unixv7-rl01 unixv7-rl02 unixv7-rk06 unixv7-rk07
            errors large-offset rt11-fixture unixv7-directory)
        add_test(NAME fsio.${case} COMMAND "${FSIO_PWSH}" -NoProfile -File
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/Check-Fsio.ps1"
            -Executable "$<TARGET_FILE:fsio>" -Case "${case}"
            -EvidenceRoot "${CMAKE_CURRENT_BINARY_DIR}/checks")
        set_tests_properties(fsio.${case} PROPERTIES RUN_SERIAL TRUE TIMEOUT 90)
    endforeach()
endif()
install(TARGETS fsio RUNTIME DESTINATION bin)
install(FILES fsio.txt fsioSimh.txt README.cmake.md windows-gcc-validation.md
    fsio.h unixv7.h DESTINATION share/doc/fsio)
install(FILES fsio.1 fsio-dos11.1 fsio-rt11.1 fsio-dosmt.1 fsio-os8.1
    fsio-unixv7.1 DESTINATION share/man/man1)
if(WIN32)
    install(FILES compat/fnmatch.c compat/fnmatch.h compat/README.md
        DESTINATION share/doc/fsio/compat)
endif()
