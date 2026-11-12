# fsio: Windows GCC validation

Qualified on 2026-11-12 for the native Windows x64 operations below. The final
build has **zero compiler warnings**, and **26/26 CTest cases passed** in
57.83 seconds (135 serial fsio process invocations). The installed and
utility-directory copies each passed six further functional cases.

Source baseline: `60875a408d87fa409b9f534ad249cae91bc21fc7`, branch `main`, with
local fsio build, portability and correctness changes. No staging, commit or
push was performed. The original Unix Makefile remains available. See
[build and use instructions](README.cmake.md).

## Environment and executable

| Component | Verified selection |
| --- | --- |
| PowerShell | 7.6.3, `C:\Program Files\PowerShell\7\pwsh.exe`, .NET 10.0.9 |
| GCC | 16.2.0, `C:\gcc-winlibs-x86_64\bin\gcc.exe`, `x86_64-w64-mingw32`, MSVCRT/POSIX/SEH |
| CMake / CTest | 4.4.5, `C:\Program Files\CMake\bin` |
| Ninja | 1.13.2, `C:\gcc-winlibs-x86_64\bin\ninja.exe` |
| Inspection | WinLibs GNU objdump 2.47.20260726 |

The build explicitly selected GNU C11, `-O2 -DNDEBUG`, `_FILE_OFFSET_BITS=64`,
MinGW's BSD getopt-reset and thread-safe time interfaces, `DEBUG`, and
`FSIO_NO_READLINE`. Warning options: `-Wall -Wextra -Wshadow -Wpedantic
-Woverflow -Wstrict-overflow`. Ninja and CTest both used one job; the build also
has a shared serial compile/link pool. No Python or guest/emulator was used.

All three executables are 284178 bytes and have SHA-256:

`5FCD5B696D4FC17452D791311AA677A792413A145D3B2F50520FE776868CE0C7`

- Utility directory: `D:\GitHub\simtools\converters\fsio\fsio.exe`
- Build: `D:\GitHub\simtools\bld\winlibs-x64\fsio\bin\fsio.exe`
- Install: `D:\GitHub\simtools\bld\install\winlibs-x64\bin\fsio.exe`

PE imports are **KERNEL32.dll and msvcrt.dll only**. Every functional subprocess
used PATH restricted to Windows and System32, so WinLibs DLLs could not be
silently supplied through PATH. The install includes user documentation, six
manual pages and the relevant source license notices. Binary reproducibility
across future rebuilds is not claimed; this hash identifies this build.

## Functional coverage

| Cases | Checks |
| --- | --- |
| `commands`, `local`, `errors` | stdin and command-file modes; quiet/verbose flags; nested `do -q`; repeated option parsing; binary and text copies; empty files; quoted Windows drive paths using `local:`; native local listings; deletion; invalid process arguments and command errors; refusal to overwrite; missing/invalid images; bad inode requests; cleanup after rejection |
| `dos11` | RK05 logical size, UFD creation, linked binary/text files, remount/extract, read-only protection, delete/reallocate |
| `rt11-default`, `rt11-rk05`, `rt11-rl01`, `rt11-rl02`, `rt11-rx01`, `rt11-rx02`, `rt11-extra` | All listed format geometries; binary/text copies; independent header/length checks; floppy interleaving; remount; read-only protection; deletion/reallocation; `*` and `%` matches and nonmatches; odd extra-directory-byte rounding |
| `os8-rk05`, `os8-rx01`, `os8-rx02`, `os8-extra` | Exact physical image size, RK05 unit 0 and both floppy types, binary 12-bit packing with all byte values, ASCII conversion, extra directory words, remount, read-only protection and reuse |
| `dosmt`, `dosmt-extended` | Empty creation, six-/nine-character names, binary/text transfer, append/end positioning, rewind, forward/reverse file skip, `copy -n`, `info`, directory listing and independent SIMH record-length/trailer/tape-mark checks |
| `unixv7-default`, `unixv7-small`, `unixv7-rl01`, `unixv7-rl02`, `unixv7-rk06`, `unixv7-rk07` | Physical geometry and PDP-11 word ordering, 64-inode override, nested directories, UID/GID setting commands, 80017-byte transfer across direct/single/double indirect allocation, remount, read-only protection, bracket wildcards and delete/reallocate |
| `large-offset` | Unix V7 partition starting at **3 GiB**, block offset 6291456; create/copy/extract/remount/delete/reallocate through 64-bit Windows file I/O |
| `rt11-fixture` | Read a directly constructed 128-block V05 image, without calling fsio `newfs`; verify exact payload and unchanged read-only image; reject a corrupted directory extent |
| `unixv7-directory` | Directory with 40 numbered files plus hidden and empty files; cross a directory-block boundary, extract the boundary file and final file, enumerate without implicit dot-file matching, delete/reuse entries |

Byte comparisons check contents and expected padding, including NUL, CR, LF,
Ctrl-Z, and high-bit values. Output length/hash/comparison receipts are saved.
The installed and utility-directory executables each repeat `local`, `dos11`,
`rt11-fixture`, `os8-rx02`, `dosmt-extended`, and `unixv7-small` (6/6 each).

## Code changes and failures resolved

- Added standalone CMake/presets, automatic executable placement, local install
  rules, and a bounded PowerShell functional driver with G: media cleanup.
- Added Windows little-endian definitions, explicit binary stream modes,
  64-bit file offsets and native local directory enumeration. GNU Readline is
  optional; the qualified preset uses fsio's existing simple input interface.
- Replaced RT-11's regex translation with name/extension glob matching using
  the same matching interface as Unix V7. Windows links a BSD-licensed NetBSD
  implementation directly; Unix continues using its system matcher. See
  [dependency provenance](compat/README.md).
- DOS-11 now formats 4800 **512-byte** blocks, infers geometry from logical
  image length rather than allocated host blocks, and clears each new linked
  tail's successor. The old self-link caused deletion of a multiblock file to
  loop. Its information timestamp now prints a portable full year.
- RT-11 validation no longer counts an extent twice during overflow checking,
  which rejected the default 65535-block volume. Formatting with extra directory
  bytes now places the end marker after those extra bytes. Fixed-width system
  identification copying is explicit and bounded.
- OS/8 now creates a full physical image, including RX01's partial logical
  block at the physical end. Directory initialization zeroes unused words.
  Packing input bytes as unsigned prevents sign extension from corrupting the
  third byte of each packed group. Free-space coordinates are initialized while
  retaining the existing `found` guard.
- Unix V7 applies valid inode-count overrides and rejects malformed, truncated
  or excessive requests; small free-inode caches exclude reserved inodes, and
  validation uses correct cache and inode bounds. Cached directory buffers now
  have the same lifetime as their block identifiers. Directory growth updates
  the directory inode rather than the newly created file inode. Fixed-width
  filename copying explicitly preserves the zero-padded on-disk representation.
- DOS-11 tape creation closes its initial empty stream. `info` now treats a
  successful position restore as success.

Initial compiler errors/warnings and 14 failing test-case receipts are retained,
including failures due to corrected test assumptions (DOS-11 exact file length
and OS/8's two-character extension). They are historical evidence, not passing
qualification results. Two early DOS-11 delete attempts reached their 15-second
timeout; the child was terminated and media cleanup succeeded.

One earlier full-suite attempt ended with **PowerShell's internal CLR error
0x80131506**, before that case created its directory or launched fsio. An
independent audit found no fsio process or remaining media. Physical RAM in use
was 13.886 GiB and commit headroom 10.864 GiB when checked afterward. No root
cause for that host-runtime crash is claimed. The subsequent final suite and
copy checks passed. Logs and the separate interruption receipt are retained.

## Cleanup, evidence and limits

All temporary disk/tape images were created beneath `G:\SimtoolsFsioTests`.
All **91 recorded attempts**, successful and failed, report verified cleanup.
The independent final audit found **zero remaining media and zero fsio
processes**. Retained BSD guest disks and unrelated work were not touched.

Evidence under `D:\GitHub\simtools\bld\winlibs-x64\fsio` includes:

- `configure-final.log`, `build-final.log`, `compile_commands.json`, CMake cache
- `test-final.log`, `test-final.xml`, `final-suite-start.txt`
- `checks/<unique-case>/` commands, stdout/stderr, comparisons and result JSON
- `installed-checks/`, `utility-directory-checks/`, install and copy-check logs
- `qualification-summary.json`, `executable-hashes.json`, `pe-imports.txt`
- `provenance.json` with tool paths, versions/digests and host details
- `source-file-hashes.json`, `source-changes.patch`, downloaded matcher originals
- historical configure/build/test logs and `clr-interruption-cleanup.json`.

This qualifies the described **Windows host utility scope**. It does not qualify
Linux builds, historical guest acceptance, every native-format variant, DOS-11
contiguous allocation, RT-11 multipart/old forced mounts, OS/8 RK05 unit-1 data
transfer, exhaustive malformed-image handling, or BSD FFS/UFS implementations.
Readline history is disabled. Windows local paths and filename matching have the
limitations documented in the build guide. Command-level errors generally leave
process exit status zero, so automation must inspect stderr and verify outputs.
