cmake_minimum_required(VERSION 3.21)
project(ods2 LANGUAGES C RC)

if(NOT WIN32 OR NOT MINGW OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "This preset targets native Windows x64 with MinGW-w64 GCC")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED YES)
set(CMAKE_C_EXTENSIONS YES)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
set_property(GLOBAL PROPERTY JOB_POOLS ods2_serial=1)
set(CMAKE_JOB_POOL_COMPILE ods2_serial)
set(CMAKE_JOB_POOL_LINK ods2_serial)

add_library(ods2_options INTERFACE)
target_compile_definitions(ods2_options INTERFACE _FILE_OFFSET_BITS=64
    _CRT_SECURE_NO_WARNINGS LIBVHD_HAS_SYSLOG=0 USE_VHD)
target_compile_options(ods2_options INTERFACE
    "$<$<COMPILE_LANGUAGE:C>:-Wall;-Wextra>")
target_include_directories(ods2_options INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/vhd")

add_executable(makehelp makehelp.c compat.c)
target_link_libraries(makehelp PRIVATE ods2_options shlwapi)
add_executable(genmsg genmsg.c)
target_link_libraries(genmsg PRIVATE ods2_options)

set(runtime_data "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2.hlb"
    "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2_en_us.hlb"
    "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2_en_us.mdf")
add_custom_command(OUTPUT ${runtime_data}
    COMMAND "$<TARGET_FILE:makehelp>" -q "${CMAKE_CURRENT_SOURCE_DIR}/en_us.hlp"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2_en_us.hlb"
    COMMAND "$<TARGET_FILE:genmsg>" -q "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2_en_us.mdf"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2_en_us.hlb"
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ods2.hlb"
    DEPENDS makehelp genmsg en_us.hlp default.md
    JOB_POOL ods2_serial VERBATIM)
add_custom_target(ods2_data DEPENDS ${runtime_data})

add_executable(ods2 ods2.c access.c cache.c compat.c copycmd.c createcmd.c
    debug.c deletecmd.c device.c diffcmd.c dircmd.c direct.c dismountcmd.c
    extendcmd.c helpcmd.c initialcmd.c initvol.c mountcmd.c phynt.c phyvirt.c
    renamecmd.c rms.c searchcmd.c setcmd.c showcmd.c spawncmd.c sysmsg.c
    termio.c update.c vmstime.c winfile.c phyvhd.c vhd/libvhd.c
    vhd/relative-path.c ods2.rc)
target_link_libraries(ods2 PRIVATE ods2_options shlwapi rpcrt4)
add_dependencies(ods2 ods2_data)

foreach(tool IN ITEMS ods2 makehelp genmsg)
    add_custom_command(TARGET ${tool} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:${tool}>"
            "${CMAKE_CURRENT_SOURCE_DIR}/$<TARGET_FILE_NAME:${tool}>"
        COMMENT "Placing ${tool} executable in its utility directory" VERBATIM)
endforeach()
add_custom_target(ods2_place ALL
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different ${runtime_data}
        "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS ods2 ods2_data JOB_POOL ods2_serial VERBATIM)

include(CTest)
if(BUILD_TESTING)
    find_program(ODS2_PWSH pwsh PATHS "C:/Program Files/PowerShell/7"
        NO_DEFAULT_PATH REQUIRED)
    foreach(case IN ITEMS commands raw-rk05 raw-rl02 raw-rm02 vhd-rm02
            readonly versions directories records snapshot errors generators
            binary-boundaries vhd-interoperability)
        add_test(NAME ods2.${case} COMMAND "${ODS2_PWSH}" -NoProfile -File
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/Check-Ods2.ps1"
            -Executable "$<TARGET_FILE:ods2>" -Case "${case}"
            -EvidenceRoot "${CMAKE_CURRENT_BINARY_DIR}/checks")
        set_tests_properties(ods2.${case} PROPERTIES RUN_SERIAL TRUE TIMEOUT 120)
    endforeach()
endif()

install(TARGETS ods2 makehelp genmsg RUNTIME DESTINATION bin)
install(FILES ${runtime_data} DESTINATION bin)
install(FILES 00README.txt 00INSTALL.TXT README.cmake.md windows-gcc-validation.md
    en_us.hlp en_us.msg ods2.h compat.h DESTINATION share/doc/ods2)
install(FILES vhd/libvhd.c vhd/libvhd.h vhd/relative-path.c vhd/relative-path.h
    vhd/blk_uuid.h vhd/vhd.h DESTINATION share/doc/ods2/vhd)
