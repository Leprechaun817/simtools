# config11: Windows GCC validation

Observed on 2026-11-12. Scope: **config11 only**, native Windows x64.

The source checkout was simtools commit
`60875a408d87fa409b9f534ad249cae91bc21fc7`. `config11.c` was not modified.
New files provide a standalone CMake build, a local toolchain preset, functional
checks, and documentation. This is not a build result for the rest of simtools.

## Selected tools

| Component | Observed version | Executable |
| --- | --- | --- |
| PowerShell | 7.6.3, Core | `C:\Program Files\PowerShell\7\pwsh.exe` |
| GCC | 16.2.0, `x86_64-w64-mingw32`, MSVCRT/POSIX/SEH | `C:\gcc-winlibs-x86_64\bin\gcc.exe` |
| CMake | 4.4.5 | `C:\Program Files\CMake\bin\cmake.exe` |
| Ninja | 1.13.2 | `C:\gcc-winlibs-x86_64\bin\ninja.exe` |

All commands were run serially. The build explicitly used one Ninja job and a
serial compile/link pool. Tests ran one at a time. No compiler or runtime was
downloaded or copied. The separate BSD GCC 16.1.0 work was not changed.

## Results

- CMake configuration: passed, selected GNU C 16.2.0 at the requested path.
- Compilation and linking: passed with no warnings or errors. Flags included
  `-O2 -DNDEBUG -std=c99 -Wall -Wextra -Wshadow -Wpedantic -Woverflow
  -Wstrict-overflow`.
- CTest: **8/8 passed**: EOF, empty configuration, documented UDA50/DZ11 example,
  lowercase names, invalid-name/count recovery, controller-count limits, zero
  controllers, and reset between successive configurations.
- Local CMake install: passed. Build and installed executable SHA-256 digests
  matched.
- Installed executable check: the documented example passed with PATH limited
  to the Windows and System32 directories, without WinLibs on PATH.
- PE inspection: `pei-x86-64`; imported DLLs were `KERNEL32.dll` and `msvcrt.dll`.
  This executable does not require a separate GCC runtime DLL.

For the documented example, observed octal CSRs included:

| Controller | Instance | CSR |
| --- | --- | --- |
| DZ11 | 1 | `760100` |
| DZ11 | 2 | `760110` |
| UDA50 | 1 | `772150*` (fixed) |
| UDA50 | 2 | `760354` |

The checks establish build, installation, and selected command behavior on this
host. They do not establish the correctness of every historical hardware
configuration. No guest was launched, and no virtual hard disk was created.

## Retained evidence and executable

Under `D:\GitHub\simtools\bld\winlibs-x64\config11`:

- `configure.log`, `build.log`, `test.log`, `install.log`, `installed-check.log`
- `compile_commands.json` and `CMakeCache.txt`
- `checks/<case>/input.txt`, `stdout.txt`, `stderr.txt`
- `provenance.json`

Initial installed executable:
`D:\GitHub\simtools\bld\install\winlibs-x64\bin\config11.exe`.

SHA-256 digests observed for this run:

| File | SHA-256 |
| --- | --- |
| `config11.c` | `46794CF6A5C669197A191589348EA69DD0CD2BCBFCF5E29E6C2F30EAC4CCFCEB` |
| `gcc.exe` | `B7EC2C871C88A7AC6E5B91C2BCC48408D98A6B0BEFD37F4920A71258E10BD716` |
| `cmake.exe` | `84935C0B7CB09C140DE0D3B042D4E93E5FAC4E6371E75BF28EAE3D841F79DFB3` |
| `ninja.exe` | `2BD16B291E96867EE619A749BF637CE5983925BB4FEA9C283E3411807F08F2E6` |
| Installed `config11.exe` | `DA378CBB395F4A2F6107AA87AAE254BE4C0A100B077634872A8E1BC6E8999EEC` |

The executable digest identifies this particular build; reproducible binary
identity across rebuilds has not been established.

## Utility-directory executable placement

On 2026-11-12, the user requested that the compiled executable be placed back
in the utility's own directory after compilation. CMake now copies the linked
executable to `D:\GitHub\simtools\config11\config11.exe` automatically after a
successful build. Its build-tree copy remains available for CMake's incremental
build, test, and install operations.

The updated build completed successfully and placed the executable at that
path. The utility-directory and build-tree copies have identical SHA-256:
`196D58C59CA2B4AF5F3C58EF79479D6FEF2816822D5A1DABB1ED7FB8DE23C2C8`.
The documented UDA50/DZ11 example passed when run from the utility-directory
copy with WinLibs absent from PATH. The executable is covered by the existing
`*.exe` Git ignore rule.

Additional evidence under the build directory: `build-placement.log`,
`utility-directory-check.log`, `checks/utility-directory/`, and
`placement-provenance.json`. The initial run's receipts and digest above are
retained as historical evidence.
