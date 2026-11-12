# ods2 with WinLibs GCC on Windows x64

This builds the native Windows Files-11 ODS-2 reader/writer, its included VHD
backend, and the `makehelp` and `genmsg` support programs. It follows the
[simtools workflow](../../WINDOWS-BUILD-WORKFLOW.md). No emulator is needed to
run this utility. The [validation record](windows-gcc-validation.md) defines
the operations actually checked; it is not an OpenVMS guest qualification.

## Build, test, and install

Use PowerShell 7. Run each command to completion before starting the next.
From `D:\GitHub\simtools\extracters\ods2`:

```powershell
& 'C:\Program Files\CMake\bin\cmake.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --build --preset winlibs-x64 --verbose
& 'C:\Program Files\CMake\bin\ctest.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --install ..\..\bld\winlibs-x64\ods2
```

The preset explicitly uses `C:\gcc-winlibs-x86_64\bin\gcc.exe`, its Ninja and
windres, GNU C11, `-O2 -DNDEBUG -Wall -Wextra`, and one build/test job. The
project also constrains Ninja compile/link/generation pools to one job.
The bundled VHD C sources link into ods2; no separate VHD DLL is required.
Windows native console input is used; libedit and legacy ASPI are not enabled.

Build products are in `../../bld/winlibs-x64/ods2/bin`. Successful links copy
all three executables back to this utility directory. The default build also
places the runtime data here:

| File | Purpose |
| --- | --- |
| `ods2.exe` | Files-11 command interpreter and disk-image operations |
| `ods2.hlb` | Default compiled help library, needed for `help` |
| `ods2_en_us.hlb` | Same help library with its language name |
| `ods2_en_us.mdf` | Loadable English messages; defaults are also compiled in |
| `makehelp.exe` | Compiles structured `.hlp` text to architecture-specific `.hlb` |
| `genmsg.exe` | Produces `.mdf` data from the message table compiled into it |

The local installation is `../../bld/install/winlibs-x64/bin`; documentation
and source license notices are under its `../share/doc/ods2` directory. Keep
the help files beside the executable. The English build uses the repository's
existing `default.md` and `ssdef.h`. Perl is not needed for this build. Updating
translations or regenerating the message source tables is a separate upstream
`message`/Perl workflow, not a step this preset silently performs.

The observed imports are Windows system DLLs only: ods2 uses KERNEL32, msvcrt,
RPCRT4 and SHLWAPI; makehelp uses KERNEL32, msvcrt and SHLWAPI; genmsg uses
KERNEL32 and msvcrt. No GCC runtime DLL needs to be copied beside them.

## Invocation and commands

Start the interactive prompt:

```powershell
& 'D:\GitHub\simtools\extracters\ods2\ods2.exe'
```

Multiple command-line commands are separated by a literal `$` argument. For
example, this prints the utility/compiler identity and exits:

```powershell
& 'D:\GitHub\simtools\extracters\ods2\ods2.exe' 'show' 'version' '$' 'exit'
```

`@filename` executes a command file; files may be nested. Put `set error_exit`
at the beginning of automated command sequences and `exit` at the end. Command
errors otherwise need not cause a failing process exit status. The test runner
checks both exit codes and the ODS2 message text. `!` and `;` introduce comments
at the beginning of a command line.

`help copy`, `help initialize`, `help mount`, and `help syntax` describe the
DCL-style qualifiers. Abbreviations are accepted when unambiguous. `/image`
explicitly chooses a host disk-image file; `/medium=RK05`, `/medium=RL02`, or
`/medium=RM02` supplies geometry. An image ending in `.vhd` selects the VHD
backend; other image names select raw media. Mounting is read-only unless
`/write` is supplied. Use `dismount` before exiting after writes to flush caches.

Use a virtual device alias such as `A:=disk.img` when mounting an image. This
is an ods2 name, not a Windows drive mapping. Automatic letters vary with host
drive assignments. `initialize/nomount` followed by a separate explicitly
aliased `mount` avoids relying on the automatically assigned letter.

Examples inside ods2, assuming the image already exists:

```text
set error_exit
mount/image/write/medium=RK05 A:=disk.img ODS2TEST
create/directory A:[TEST.SUB]
copy/to_files-11/binary/record_format=undefined input.bin A:[TEST.SUB]DATA.BIN
copy/to_files-11/ascii/record_format=streamlf input.txt A:[TEST.SUB]TEXT.TXT
directory/full A:[TEST.SUB]*.*;*
copy/from_files-11/binary A:[TEST.SUB]DATA.BIN output.bin
copy/from_files-11/ascii A:[TEST.SUB]TEXT.TXT output.txt
dismount A:
exit
```

The tests use temporary G: images and delete them. Follow the same media rule
for additional validation; a manual interactive example does not supply an
automatic cleanup controller. For an existing image at an absolute host path,
quote the whole argument, for example `"A:=G:\case\disk.img"`. Windows narrow
path APIs are used; exhaustive Unicode and extended-length paths are untested.

Useful commands also include `rename`, `delete/noconfirm FILE;VERSION`,
`extend/allocate=n`, `extend/truncate`, `show volumes`, and `set default`.
Versions use VMS `;1`, `;2`, etc. Snapshot creation is available with
`mount/image/medium=RM02/snapshots_of=parent.vhd A:=child.vhd`; tested child
writes preserve the parent image bytes.

## Data semantics to account for

- Binary import operates in 512-byte blocks and zero-pads the last partial
  block. Specify `/record_format=undefined` for unstructured data. Extraction
  then preserves those bytes, including the padding. This is not a general
  exact-length host-file backup mechanism.
- For Windows line-oriented text, `/ascii/record_format=streamlf` provides the
  tested CRLF-to-record-to-CRLF round trip. STREAM uses CRLF delimiters and
  STREAMCR uses CR delimiters. Variable records without carriage control have
  no separator bytes when extracted; the records test deliberately verifies
  that behavior.
- Default variable-record carriage-return control has printing semantics,
  including leading LF and trailing CR. Other RMS print/FORTRAN/VFC modes need
  their own expectations. Do not assume every `/ascii` extraction is identical
  to the original host text. Indexed RMS files are not implemented upstream.
- `ODS2INIT`, or the user's `.ods2.ini`, controls startup. `ODS2HELP` or
  `set help_file` selects help. `set message PATH` loads an `.mdf`; `show message`
  identifies it. Tests isolate initialization and history from the user's home.
- `makehelp -q input.hlp output.hlb` builds help. `-h` shows syntax, `-d` and
  `-D` dump structure (the latter with text). Help libraries are architecture
  specific. `genmsg -q output.mdf` builds messages; `-d` emits C table data.

## Verification and limits

CTest calls [Check-Ods2.ps1](tests/Check-Ods2.ps1) serially. Every case gets a
unique directory under `G:\SimtoolsOds2Tests`, with child process timeouts,
isolated startup files, controlled PATH, byte comparisons, and a cleanup
receipt. Children are closed before recursive cleanup, and the resolved path
is checked to remain below that G: root. On success or failure the case deletes
its images and verifies deletion. Logs and receipts remain under the build
directory. After a host crash or forced termination of the test runner, audit
and clean up its owned directory before resuming; a process-local `finally`
cannot execute after the process or host has died.

The VHD interoperability case additionally requires the already installed
`C:\Program Files\qemu\qemu-img.exe`; it records its version and SHA-256 and
uses it only for host file conversion. It starts no guest and accesses no
network. This tests VHD container interchange, not independent Files-11 parsing.

No Linux/VMS build, physical disk or optical I/O, ASPI, volume-set behavior,
all media geometries, large-media limits, or historical guest acceptance is
claimed. See the validation record for exact coverage and changes.
