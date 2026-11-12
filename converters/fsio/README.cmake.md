# fsio: Windows GCC build and use

This standalone CMake project builds only fsio with the installed WinLibs GCC.
The native Windows executable belongs on the host; DOSBox/SIMH is not required
to run it. It manipulates DOS-11, RT-11, DOS-11 SIMH tape, OS/8 and Unix V7
container files. See [the validation record](windows-gcc-validation.md) for the
tested scope and [the shared workflow](../../WINDOWS-BUILD-WORKFLOW.md).

## Build, test, install

Run each command in order from PowerShell 7:

```powershell
Set-Location D:\GitHub\simtools\converters\fsio
& 'C:\Program Files\CMake\bin\cmake.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --build --preset winlibs-x64 --verbose
& 'C:\Program Files\CMake\bin\ctest.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --install ..\..\bld\winlibs-x64\fsio
```

Stop and investigate any failed command before continuing. The preset selects
`C:\gcc-winlibs-x86_64\bin\gcc.exe`, that installation's Ninja, Release `-O2`,
GNU C11, one build job and one test at a time. A single Ninja compile/link pool
also serializes work. No build-time dependency downloads occur.

The successful build automatically copies `fsio.exe` into this utility's
directory. Copies are retained at:

- `D:\GitHub\simtools\converters\fsio\fsio.exe`
- `D:\GitHub\simtools\bld\winlibs-x64\fsio\bin\fsio.exe`
- `D:\GitHub\simtools\bld\install\winlibs-x64\bin\fsio.exe` after installation.

The Windows preset uses the existing simple stdin/command-file interface.
GNU Readline editing and history are disabled. `FSIO_USE_READLINE=ON` is an
explicit alternative requiring an installed matching library and separate
qualification. Debug commands remain compiled in, as in the original Makefile.
The Windows build includes a small BSD-licensed filename matcher; see
[its source provenance and limitations](compat/README.md). It requires no
additional GCC or filename-matching runtime DLL.

## Commands and Windows paths

Launch `fsio.exe` for a prompt, or `fsio.exe [-qv] commands.txt` for a script.
`-q` suppresses some unsolicited output; `-v` echoes script commands. Use `help`
for the command inventory and the six installed man pages for format details.

| Operation | Example / meaning |
| --- | --- |
| Create | `newfs -t rk05 image.img rt11` (refuses an existing file) |
| Attach | `mount dd image.img rt11`; add `-r` for read-only access |
| List / inspect | `dir dd:*.*`, `dir -f dd:`, `info dd:`, `status` |
| Import / export | `copy input.bin dd:SAMPLE.BIN`, `copy dd:SAMPLE.BIN output.bin` |
| Text conversion | `copy -a input.txt dd:TEXT.TXT` (explicit LF/CRLF conversion) |
| Delete / detach | `delete dd:SAMPLE.BIN`, `umount dd` |
| Command scripts | `do commands.txt`, `do -q commands.txt`, `exit` / `quit` |
| Tape positioning | `rewind mt:`, `eom mt:`, `skipf mt: 1`, `skipr mt: 1` |

For local **file specifications** containing a Windows drive colon, use the
reserved prefix: `'local:G:/some folder/input.bin'`. Quote paths containing
spaces. The `newfs`/`mount` container argument is already a host path and does
not need `local:`. Relative local filenames are also accepted. Setting the
`FSioForceLocal` environment variable requires the prefix for local access.
On Windows, `dir local:` uses native enumeration, and `dir -f local:` displays
type, byte length and name. File paths use the Windows narrow-character API;
full Unicode/extended-length path support is not claimed.

Relevant format details:

- **DOS-11:** create a UFD before writing: `set dd: ufd [1,1]`. The supported
  `newfs` image is 4800 blocks of 512 bytes. `copy -c N` requests contiguous
  allocation; it is outside this initial qualification's linked-file coverage.
- **RT-11:** default `newfs` creates 65535 blocks. `-t` also accepts `rk05`,
  `rl01`, `rl02`, `rx01`, `rx02`. Mount floppies with `-t rx01`/`-t rx02`.
  Use `-e N` for extra directory bytes; odd values round up. `%` and `*` match
  one and any number of characters, with name and extension matched separately.
- **OS/8:** mount with `-t rk05`, `-t rx01`, or `-t rx02`. RK05 has two units
  (`dd0:` and `dd1:`). Names use at most six characters and a two-character
  extension. `-e N` selects extra directory words. Binary bytes are packed into
  pairs of 12-bit words; exported data is padded to 384-byte block boundaries.
- **DOS-11 tape:** `newfs tape.tap dosmt` creates an empty file. `mount -x`
  enables extended nine-character names. Position with `eom` before appending.
  `copy -n` avoids the usual input rewind; the tape backend does not delete files.
- **Unix V7:** `newfs -t rk05|rl01|rl02|rk06|rk07` or `newfs -b N -i N`.
  Use `mkdir -p dd:/sub/path`, `set dd: uid N`, and `set dd: gid N`.
  `mount -o N` specifies a partition offset in 512-byte blocks. The actual
  RK05 size is 4872 blocks, and the superblock is logical block 1; some older
  included prose gives conflicting values. Unix V7 is distinct from BSD FFS/UFS.

Command-level errors are written to stderr and generally **do not set a failing
process exit code** in the upstream command interpreter. Automation must check
stderr and verify its outputs. A missing command file returns 2; invalid process
arguments return 1. `-f` forced mounts bypass checks and are not qualified here.

## Test media and evidence

The PowerShell test driver runs bounded fsio processes with PATH restricted to
Windows/System32. All generated disk/tape images, including the large-offset
case, live in unique directories beneath `G:\SimtoolsFsioTests`. Each case
releases its child process, deletes its directory on success or failure, and
writes a cleanup receipt. Transcripts, byte-comparison receipts and result JSON
are retained under `bld\winlibs-x64\fsio\checks`. If PowerShell or the computer
is forcibly terminated, inspect process ownership and clean the recorded G:
directory before continuing; a process-local `finally` cannot survive a crash.

Tests cover selected host-side operations; they do not establish historical OS
guest acceptance, all media variants, malicious-image robustness or Linux build
qualification. Preserve the original Makefile for Unix/Readline builds.
