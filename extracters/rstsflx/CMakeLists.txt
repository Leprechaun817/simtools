cmake_minimum_required(VERSION 3.24)
project(flx VERSION 2.6 LANGUAGES C)

if(NOT WIN32 OR NOT MINGW OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "This preset qualifies native Windows x64 with MinGW GCC.")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)
set_property(GLOBAL PROPERTY JOB_POOLS serial=1)
set(CMAKE_JOB_POOL_COMPILE serial)
set(CMAKE_JOB_POOL_LINK serial)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
add_executable(flx rstsflx.c fip.c rtime.c filename.c doget.c dolist.c
  doalloc.c docomp.c dotype.c doput.c dodump.c dodelete.c dorename.c dorts.c
  doprot.c dodir.c doident.c doinit.c dohook.c scancmd.c doclean.c fileio.c
  diskio.c winabsio.c winconsole.c)
target_compile_definitions(flx PRIVATE FLX_NATIVE_CONSOLE)
target_compile_options(flx PRIVATE -Wall -Wextra)
add_custom_command(TARGET flx POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:flx>"
    "${CMAKE_CURRENT_SOURCE_DIR}/flx.exe" VERBATIM)
include(CTest)
if(BUILD_TESTING)
  set(POWERSHELL "C:/Program Files/PowerShell/7/pwsh.exe" CACHE FILEPATH "PowerShell 7")
  foreach(case commands interactive rds0-rk05 rds11-rl02 rds12-rm02 records boundaries
      directories metadata readonly clean-compress errors
      repair-rds0-rk05 repair-rds0-rm02 repair-rds0-pcs16 repair-rds11 repair-rds12-pcs32
      repair-growth repair-mfd-cycle repair-ufd-cycle repair-rds12-cycle repair-interactive
      repair-self repair-delete repair-account repair-crosslink repair-retrieval-cycle
      repair-badb repair-fatal-badb repair-fatal-map repair-fatal-satt repair-readonly
      repair-mfd-delete repair-rds11-delete repair-rds12-crosslink repair-fatal-lookup
      repair-badb-pcs16 repair-map-copy repair-shared-dir repair-rds12-shared-dir repair-extent-end)
    add_test(NAME "flx.${case}" COMMAND "${POWERSHELL}" -NoProfile -File
      "${CMAKE_CURRENT_SOURCE_DIR}/tests/Check-Flx.ps1"
      -Executable "$<TARGET_FILE:flx>" -Case "${case}"
      -EvidenceRoot "${CMAKE_BINARY_DIR}/checks")
    set_tests_properties("flx.${case}" PROPERTIES RUN_SERIAL TRUE TIMEOUT 120)
  endforeach()
endif()
install(TARGETS flx RUNTIME DESTINATION bin)
install(FILES README LICENSE HISTORY BUGS flx.pdf README.cmake.md windows-gcc-validation.md clean-rebuild-validation.md
  DESTINATION share/doc/flx)
