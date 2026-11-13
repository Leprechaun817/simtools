# FLX / rstsflx: native Windows build

`rstsflx` is the repository directory and main source name; **`flx` is the
upstream executable name**. The Linux and DOS makefiles both build FLX from
`rstsflx.c`. These are one utility, not two independent implementations.

FLX v2.6 manipulates RSTS disk-container files from the Windows host. This build
does not require SIMH, DOSBox, MSVC, or a running RSTS guest. Its qualified scope
and remaining limitations are in [windows-gcc-validation.md](windows-gcc-validation.md).
The original [manual](flx.pdf), [license](LICENSE), [history](HISTORY), and
[upstream bug list](BUGS) remain available.

## Build, test, install

Use PowerShell 7 in `D:\GitHub\simtools\extracters\rstsflx`. Execute these units
one at a time and check each result before continuing:

```powershell
& 'C:\Program Files\CMake\bin\cmake.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --build --preset winlibs-x64 --verbose
& 'C:\Program Files\CMake\bin\ctest.exe' --preset winlibs-x64
& 'C:\Program Files\CMake\bin\cmake.exe' --install ..\..\bld\winlibs-x64\flx
```

The preset selects the installed WinLibs GCC and Ninja explicitly, GNU C11,
`-O2 -Wall -Wextra`, and one compilation/test job. Ninja compile/link pools are
also serial. No compiler-runtime binaries are copied into the repository.

| Purpose | Location |
| --- | --- |
| Build output | `bld\winlibs-x64\flx\bin\flx.exe` |
| Automatic post-build placement | `extracters\rstsflx\flx.exe` |
| Local installed executable | `bld\install\winlibs-x64\bin\flx.exe` |
| Installed documentation/license | `bld\install\winlibs-x64\share\doc\flx` |
| Build logs and case receipts | `bld\winlibs-x64\flx` |

Paths in this table are relative to the simtools repository root. FLX has no
generated runtime data files. The Windows executable imports `KERNEL32.dll`
and `msvcrt.dll`; no Readline, ncurses, or additional GCC runtime DLL is needed.

The new Windows backend uses regular container files. DOS absolute-disk
backends and Unix raw-device code are not linked. Windows device namespace
paths are explicitly refused. Physical disk/floppy access is not provided.
The original makefiles and non-Windows backends remain in the source tree;
they were not built or qualified in this work.

## Running FLX

```powershell
& 'D:\GitHub\simtools\extracters\rstsflx\flx.exe'
& 'D:\GitHub\simtools\extracters\rstsflx\flx.exe' identify -disk 'G:\path\disk.img'
& 'D:\GitHub\simtools\extracters\rstsflx\flx.exe' list -disk 'G:\path\disk.img' -full '[1,2]*.*'
```

With no arguments, FLX prompts for commands. A command on the process command
line normally executes once and exits; `disk PATH` instead selects a default
container and enters the prompt. `exit`, `quit`, and `bye` terminate it.
`-disk PATH` overrides a prior `disk` selection, then `RSTSDISK`, then the default
`rsts.dsk`. `RSTSDISKSIZE` supplies a default size when explicitly needed.

The native console path supports line input and redirected command scripts.
GNU Readline completion, Readline editing bindings, persistent history, and
`FLXHIST*` settings are not implemented in this build. The existing GNU Readline
path remains selected by the original non-Windows build. Interactive tokens
are space-delimited without shell quoting; use direct process arguments from
PowerShell for host paths containing spaces. Keyboard editing itself was not
manually qualified; scripted prompt execution was.

Commands and switches are case-sensitive and accept unambiguous prefixes.
RSTS filenames are case-insensitive, use six-character names and three-character
extensions, and accept account prefixes such as `[1,2]`. Quote those arguments
in PowerShell. Do not confuse lowercase `-size` (file allocation) with uppercase
`-Size` (device size), or lowercase switches with `-Write` and `-Debug`.
Host-side `put` inputs should be explicit filenames; this work does not promise
shell wildcard expansion.

| Command/switch | Purpose and notes |
| --- | --- |
| `initialize LABEL 1.2 -create rk05 -disk PATH` | Create a new raw container; refuses an existing filename. Revisions `0.0`, `1.1`, `1.2` are accepted. |
| `-create rl02`, `-create rm02`, `-create N` | Named geometry or size in 512-byte blocks. The tested named geometries are RK05, RL02, RM02. |
| `mkdir '[1,2]'`, `rmdir '[1,2]'` | Create/remove an account; `mkdir -user` marks an RDS1 account as a user account. |
| `put -binary INPUT '[1,2]NAME.BIN'` | Copy host bytes into a RSTS file. Last partial block is zero-padded. |
| `put -ascii INPUT '[1,2]NAME.TXT'` | Convert host line input to RSTS CRLF stream data. |
| `get -binary '[1,2]NAME.BIN' OUTPUT` | Extract allocated file blocks, including final block padding. |
| `get -ascii '[1,2]NAME.TXT' OUTPUT` | Extract records using Windows CRLF line endings. |
| `get -tree '[2,3]*.*' DIRECTORY` | Extract account files beneath a six-digit account directory such as `002003`. |
| `get -binary '[2,3]f00?.bin' OUTPUT` | Concatenate wildcard matches into one host output file. |
| `list -full`, `list -1column`, `list -summary` | List names and metadata with different output detail. |
| `rename OLD NEW`, `delete FILE` | Rename/delete files; `rename -replace` allows replacing an existing destination. |
| `protect FILE'<40>'` | Set the protection code; quote the complete specification. |
| `protect -protect FILE`, `protect -unprotect FILE` | Set/clear the no-delete flag. |
| `rts FILE RT11` | Change the runtime-system name recorded on a file. |
| `identify`, `allocation -brief` | Inspect pack geometry/flags and block allocation. |
| `clean -protect` | Inspect RDS1 without writing. **RDS0 clean/rebuild is unavailable.** |
| `clean`, `rebuild` | RDS1 checking/repair. Healthy images were tested; arbitrary corruption recovery was not. |
| `compress` | Zero unused clusters; this does not change the container file's length. |
| `-query`, `-verbose`, `-clustersize N` | Per-file confirmation, progress text, and applicable cluster-size selection. |
| `-Write` | Override pack read-only/protection checks where allowed; does not override the no-delete flag. |
| `-rs`, `-rv`/`-r`, `-rf N` | Attach RMS stream, variable, or fixed record attributes during import. For `-rv`/`-rf`, provide already encoded records and use `-binary`. These switches are not general record encoders. |

`-rf N` now rejects zero, negative, nonnumeric, and greater-than-65535 record
sizes. Its input must contain a whole number of records. The tested fixed
record sizes are 4 and 512 bytes. Variable records include little-endian
16-bit lengths and even-byte padding; the test includes odd/even record lengths.
Binary extraction still returns block padding even when RMS EOF metadata exists.

`dump`, `type`, `hook`, and initialization with `-merge` remain compiled in;
their complete behavior is not qualified by this test set. A new image contains
a dummy bootstrap. Preparing a bootable guest requires actual RSTS system files
and a separately tested `hook` operation.

## Known limitations and test-media policy

**RDS 0.0 `clean`/`rebuild` is explicitly refused in both write and read-only
modes.** The upstream `cleanoldmfd` path never traverses the mixed account/file
chain before constructing the new allocation bitmap. Completing and validating
that path remains separate work. The refusal returns failure and preserves the
container; it is not counted as successful RDS0 checking/repair.

Many inherited command-level errors print diagnostics but still return process
exit code zero. Parser errors and fatal aborts return failure. Automation must
check diagnostics and outputs, as the test harness does, rather than relying
on exit status alone.

This qualification covers selected native Windows container operations. It does
not establish acceptance by an RSTS guest, all media sizes, >2-GiB operation,
all RMS formats/organizations, arbitrary damaged-media recovery, complete
Unicode/long-path handling, DOS builds, or Linux builds. The inherited Windows
`long`/stdio size and offset paths still need a separate large-container review.
The upstream erase-on-delete and general I/O-error concerns remain open.

All test containers are created under unique `G:\SimtoolsFlxTests` directories.
The PowerShell harness runs children serially, limits each invocation to 30
seconds, terminates owned timed-out children, and deletes its exact G: case
directory in `finally`, including failed cases. It records commands, output,
exit status, hashes, and cleanup status outside the image directory. A host or
PowerShell crash can bypass `finally`; audit for leftovers after forced shutdown.
Persistent guest OS disks are not touched.
