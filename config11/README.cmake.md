# config11 with CMake and WinLibs GCC

This standalone CMake project builds **config11 only**. The remaining simtools
utilities are being handled individually; this project does not qualify them.
The existing Makefile remains available.

The complete process is the reference for the repository's standard
per-utility workflow, documented in `WINDOWS-BUILD-WORKFLOW.md` at the root of
the simtools source checkout.

The `winlibs-x64` preset selects the local installation at
`C:\gcc-winlibs-x86_64`, including GCC and Ninja. Use the separately installed
CMake at `C:\Program Files\CMake\bin`. No MSVC compiler is selected by this
preset. GCC produces a native Windows x64 console executable.

## Build, check, and install

Run these commands in **PowerShell 7**, one execution at a time. Each must
succeed before continuing. Use a separate build directory if changing compilers.

```powershell
Set-Location 'D:\GitHub\simtools\config11'
& 'C:\Program Files\CMake\bin\cmake.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --build --preset winlibs-x64 --parallel 1
& 'C:\Program Files\CMake\bin\ctest.exe' --preset winlibs-x64 --parallel 1
& 'C:\Program Files\CMake\bin\cmake.exe' --install '..\bld\winlibs-x64\config11'
```

After a successful build, `config11.exe` is automatically copied into the
utility's own directory, `D:\GitHub\simtools\config11`. Run that copy directly.
CMake keeps its build-tree executable and intermediate files under
`bld/winlibs-x64/config11` for incremental builds, tests, and installation.
The verified local install contains `bld/install/winlibs-x64/bin/config11.exe`
and documentation under `share/doc/config11`. The existing `*.exe` and `bld/`
ignore rules cover these generated files. No system-wide PATH changes are
required. The preset uses one build job, and Ninja's compile/link pool is also
limited to one job. Tests run serially.

The CMake project selects C99 explicitly and retains the original Makefile's
GCC warning categories. It does not suppress errors or warnings. This tool
needs neither C++ nor any third-party library.

## Use

```powershell
& 'D:\GitHub\simtools\config11\config11.exe'
```

Enter a controller name, then its count. A blank name prints the address table
and starts another configuration. Controller names are case-insensitive. Counts
from zero through eight are accepted. The table's addresses are octal; an
asterisk marks a fixed CSR address. End console input with Ctrl+Z followed by
Enter, or use Ctrl+C to interrupt.

The example from `config11.txt` is `UDA50`, `2`, `DZ11`, `2`, then a blank name.
The program has no implemented command-line switches.

## Validation scope

CTest exercises immediate EOF, an empty configuration, the documented example,
lowercase names, invalid-name/count recovery, the eight-controller boundary,
zero controllers, and state reset between configurations. It checks successful
termination, table size, selected CSR results, and diagnostics. Input/output
transcripts are retained under the build directory's `checks/` directory.

These are Windows executable and command-behavior checks. They do not certify
every historical device assignment or guest configuration. They create no
virtual disks and do not require a simulator or a running guest. See
`windows-gcc-validation.md` for the observed toolchain and results.
