cmake_minimum_required(VERSION 3.21)
project(putr VERSION 2.1 LANGUAGES NONE)

if(NOT WIN32)
    message(FATAL_ERROR "This configuration qualifies the Windows PowerShell / DOSBox Staging workflow")
endif()
find_program(PUTR_PWSH pwsh PATHS "C:/Program Files/PowerShell/7" NO_DEFAULT_PATH REQUIRED)
set(PUTR_DOSBOX "D:/GitHub/dosbox-staging/dosbox.exe" CACHE FILEPATH "Qualified DOSBox Staging executable")
set(PUTR_ASSEMBLER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../bld/dos/putr/toolchain/jwasm-2.21"
    CACHE PATH "Verified JWasm 2.21 DOS package")
foreach(required IN ITEMS "${PUTR_DOSBOX}" "${PUTR_ASSEMBLER_DIR}/JWasmd.exe" "${PUTR_ASSEMBLER_DIR}/hdpmi32.exe")
    if(NOT EXISTS "${required}")
        message(FATAL_ERROR "Missing ${required}; see README.cmake.md and scripts/Initialize-PutrToolchain.ps1")
    endif()
endforeach()
set_property(GLOBAL PROPERTY JOB_POOLS putr_serial=1)
set(putr_binary "${CMAKE_CURRENT_BINARY_DIR}/bin/PUTR.COM")
add_custom_command(OUTPUT "${putr_binary}"
    COMMAND "${PUTR_PWSH}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/Build-Putr.ps1"
        -BuildDirectory "${CMAKE_CURRENT_BINARY_DIR}"
        -AssemblerDirectory "${PUTR_ASSEMBLER_DIR}" -DosBox "${PUTR_DOSBOX}"
    DEPENDS putr.asm scripts/Build-Putr.ps1 scripts/Invoke-PutrDosBox.ps1
        scripts/Check-PutrEncoding.ps1 "${PUTR_ASSEMBLER_DIR}/JWasmd.exe" "${PUTR_ASSEMBLER_DIR}/hdpmi32.exe"
    BYPRODUCTS "${CMAKE_CURRENT_SOURCE_DIR}/putr.com" "${CMAKE_CURRENT_BINARY_DIR}/build-result.json"
    JOB_POOL putr_serial VERBATIM
    COMMENT "Assembling PUTR under DOSBox Staging and checking instruction encodings")
add_custom_target(putr ALL DEPENDS "${putr_binary}")

include(CTest)
if(BUILD_TESTING)
    foreach(case IN ITEMS commands rt11 os8 putr-tape cross-filesystem boundaries
            readonly-errors rt11-independent dosbatch rsts0 rsts11 rsts12)
        add_test(NAME putr.${case} COMMAND "${PUTR_PWSH}" -NoProfile -File
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/Check-Putr.ps1"
            -Executable "${putr_binary}" -Case "${case}"
            -EvidenceRoot "${CMAKE_CURRENT_BINARY_DIR}/checks" -DosBox "${PUTR_DOSBOX}")
        set_tests_properties(putr.${case} PROPERTIES RUN_SERIAL TRUE TIMEOUT 180)
    endforeach()
endif()
install(FILES "${putr_binary}" DESTINATION putr)
install(FILES README LICENSE putr.doc README.cmake.md windows-dos-validation.md dosbox-putr.conf DESTINATION putr)
