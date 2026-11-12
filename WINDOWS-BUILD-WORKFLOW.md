# Standard Windows utility build and validation workflow

The user established this workflow on 2026-11-12 for every utility in simtools.
Finish one utility's configuration, build, functional verification, installation,
placement, and documentation before moving to the next. The initial example is
[config11](config11/README.cmake.md), with its
[validation record](config11/windows-gcc-validation.md).

`fsio` completed the same workflow on 2026-11-12: WinLibs GCC build with no
warnings, 26 passing serial cases, installation, automatic utility-directory
placement, and six additional functional checks of each deployed copy. See its
[build guide](converters/fsio/README.cmake.md) and
[qualification record](converters/fsio/windows-gcc-validation.md). The usable
host executable is `converters\fsio\fsio.exe`; this does not require DOSBox.

## Selected environment

| Component | Selected location | Version observed during config11 work |
| --- | --- | --- |
| PowerShell 7 | `C:\Program Files\PowerShell\7\pwsh.exe` | 7.6.3 |
| GCC | `C:\gcc-winlibs-x86_64\bin\gcc.exe` | 16.2.0 |
| G++, when needed | `C:\gcc-winlibs-x86_64\bin\g++.exe` | Verify when first used |
| CMake and CTest | `C:\Program Files\CMake\bin` | CMake 4.4.5 |
| Ninja | `C:\gcc-winlibs-x86_64\bin\ninja.exe` | 1.13.2 |

These versions describe the observed installation, not permission to recover
older tool binaries. Verify the selected tools when beginning each utility and
record path, version, and SHA-256. Use explicit paths and presets to prevent an
unintended compiler or the separate CMake bundled with WinLibs from being used.

## Per-utility process

1. **Inspect and define the checks.** Read the utility's source, existing build
   files, documentation, arguments, and supported formats. Identify required
   libraries and runtime files. Select meaningful examples, expected results,
   relevant boundary/error cases, and any required test media. Check the actual
   implementation when documentation and command parsing disagree.

2. **Configure.** Add or adapt the utility's CMake project and configure/build/
   test presets. Select only the current utility and its required dependencies.
   Keep intermediate files and logs in a separate directory such as
   `bld/winlibs-x64/<utility>`. Select GCC explicitly, choose the appropriate C or
   C++ standard, and preserve useful warnings. The C99 setting and exact tests
   used by config11 are not universal requirements for other utilities.

3. **Compile and link serially.** Use one build job, including a serial Ninja
   compile/link pool where applicable. Inspect the complete build result and
   investigate failures and warnings. Make necessary scoped build/source fixes;
   do not hide problems with blanket warning suppression or silently replace
   the chosen compiler. Retain build logs and compiler flags.

4. **Place the executable in its utility directory.** After a successful link,
   automatically copy the executable beside that utility's sources. Retain the
   CMake-managed build output for incremental builds, tests, and installation.
   Include required generated runtime data or documented dependencies when
   applicable. The copy is a build output; readiness still depends on passing
   the following checks. Do not mistake a stale copy from an older build for
   the current successful result.

5. **Check actual behavior.** Run appropriate functional checks serially and
   verify results, not merely process startup or a help screen. For example,
   converters need known input/output checks and assemblers need an assembled
   sample with checked output. Use relevant invalid-input and boundary cases.
   Keep input/output transcripts and identify what the checks establish.

6. **Verify the local installation.** Exercise the utility's CMake installation
   into the local staging prefix, initially `bld/install/winlibs-x64`. Include
   documentation and required runtime files. Run a meaningful installed
   executable check and compare its SHA-256 with the tested build output.

7. **Verify the copy in the utility directory.** Compare its SHA-256 with the
   tested build output and run a meaningful functional check from that copy.
   Inspect imported libraries and test with a controlled PATH that does not
   accidentally supply undeclared compiler/runtime dependencies. If dependencies
   are required, make the supported launch environment explicit; config11's
   lack of an additional GCC runtime DLL is not assumed for other programs.

8. **Record and report.** Save source revision and relevant file hashes,
   toolchain/runtime provenance, configuration and build commands, compiler
   flags, logs, test results, installation and utility-directory paths, binary
   hashes, runtime dependencies, and any limitations. Update build/use
   instructions and a per-utility validation record. Preserve earlier receipts
   when later work changes the binary. Summarize changes and results in chat.

Only declare the utility ready for the explicitly tested scope after the
applicable steps pass. A successful build alone is not functional validation.
Report an unresolved failure or environment limitation instead of silently
counting the utility as complete and moving on.

## Files, media, and execution scope

- Use existing Git ignore rules for generated binaries and build directories;
  extend them narrowly if a utility produces additional generated artifacts.
  Do not stage, commit, or push without express user permission.
- All temporary virtual hard disks used for testing, qualification, or
  validation belong on G:. After each case, including failure, release open
  consumers, delete the image, and verify deletion. Existing retained guest OS
  disks remain subject to their previously authorized exception. Logs and
  small non-disk test fixtures may stay under the build directory.
- No subagents or concurrent foreground execution units. An already authorized
  detached BSD build may continue under its own resource limits while these
  foreground operations run serially.
- This workflow does not expand a tool test into filesystem-family completion,
  guest compatibility, or hardware qualification. Report those separately when
  they are actually exercised.

## Utilities with different execution requirements

Apply the same inspection, functional verification, usable placement, provenance,
and reporting discipline to scripts, libraries, and platform-specific programs.
Document any step that is not applicable and why.

- Python and Perl scripts use a verified applicable interpreter; do not invent
  a C compilation step. Follow the host Python policy in [AGENTS.md](AGENTS.md).
  Do not bundle a Python interpreter when placing a utility script.
- DOS programs, including PUTR where its required operations permit, use
  DOSBox Staging from `D:\GitHub\dosbox-staging` by default. User clarification
  on 2026-11-12 makes MartyPC the alternative for cases requiring strict
  machine/hardware compatibility, rather than a requirement for every DOS
  utility. Identify the required behavior for each case and document that
  environment choice.
- DOSBox Staging must match the selected checkout and configuration. Its
  initial VS2026 rebuild was qualified on 2026-11-12; the record is at
  `D:\GitHub\dosbox-staging\docs\windows-vs2026-validation.md`. The usable
  project copy is `D:\GitHub\dosbox-staging\dosbox.exe`, with a local installed
  copy and resources under `build\install-vs2026`. That qualification includes
  921 passing unit tests, one upstream skip, four upstream disabled tests, and
  DOS file-operation checks of both copies. Verify the recorded identity before
  reuse; rebuild after relevant source/configuration changes. Preserve the
  simulator network-isolation constraint during testing.
- For this DOSBox rebuild, the user explicitly selected Visual Studio 2026 on
  2026-11-12. Use its ClangCL toolchain as specified by DOSBox's Windows preset,
  with one compilation job. This exception applies to the emulator only;
  simtools native utilities continue to use the selected WinLibs GCC toolchain.
- DOS utility builds and functional checks are recorded as DOS execution;
  native Windows GCC checks alone do not establish that a DOS program works.
- Support libraries and build generators are checked through their actual
  outputs and dependent programs, with generated runtime files included where
  needed. Identify Unix/VMS-specific helpers and validate them in their
  applicable environment rather than claiming native Windows execution.
