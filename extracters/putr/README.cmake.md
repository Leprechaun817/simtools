# PUTR DOS build and use

PUTR V2.01 is John Wilson's 16-bit DOS assembly utility. It runs in DOSBox
Staging, not directly as a Windows executable. The selected workflow assembles
the source using the upstream **JWasm 2.21 DOS binary**, running under the
qualified `D:\GitHub\dosbox-staging\dosbox.exe`. GCC is not applicable to this
assembly source. CMake and Ninja orchestrate the serial DOS build and checks.

## Configure, build, test, install

Use PowerShell 7, from `D:\GitHub\simtools\extracters\putr`:

```powershell
& .\scripts\Initialize-PutrToolchain.ps1
& 'C:\Program Files\CMake\bin\cmake.exe' --preset dosbox-dos
& 'C:\Program Files\CMake\bin\cmake.exe' --build --preset dosbox-dos --verbose
& 'C:\Program Files\CMake\bin\ctest.exe' --preset dosbox-dos
& 'C:\Program Files\CMake\bin\cmake.exe' --install ..\..\bld\dos\putr
```

Run each command to completion before the next. The initialization script
downloads only the pinned DOS assembler package, verifies its recorded upstream
SHA-256, and extracts it under the ignored build directory. It preserves the
assembler's license and documentation. The downloaded toolchain is prebuilt;
this workflow builds PUTR from source, not JWasm from source.

The DOS assembler command is:

```text
JWASMD -Zm -bin -Fl=PUTR.LST -Fo=PUTR.COM PUTR.ASM
```

`-Zm` selects MASM 5 compatibility, including dotted macro names and historical
address-expression precedence. `-bin` produces the COM image directly; there
is no separate linker. `-Fl` retains a listing, which the build audits before
copying the executable. JWASMD uses the packaged HDPMI32 extender; PUTR itself
does not require that extender, the assembler, or a compiler runtime DLL.

Locations:

- Build output: `D:\GitHub\simtools\bld\dos\putr\bin\PUTR.COM`.
- Automatically placed utility: `D:\GitHub\simtools\extracters\putr\putr.com`.
- Local installation: `D:\GitHub\simtools\bld\install\dos\putr\PUTR.COM`.
- Logs, listings, provenance, and receipts: `D:\GitHub\simtools\bld\dos\putr`.

Unlike the preceding Windows EXEs, upstream `putr.com` is already tracked in
Git. A successful deployment therefore appears as a local binary modification.
The original supplied COM used for comparison is retained in the ignored
`bld/dos/putr/upstream` evidence directory. No Git staging or delivery is implied.

## Behavior-preserving source annotations

Four instructions are made explicit for JWasm:

- Three ODS-1 header loads specify `word ptr`, matching their 16-bit destination
  registers and the instruction bytes in the supplied COM.
- The RT-11 jump following `jz $+5` specifies `near ptr`. Without it, JWasm
  shortens that jump from three bytes to two, breaking the original fixed skip.

The build verifies all **19 fixed-byte conditional skips** against the listing
and checks the three word-load encodings in both listing and output bytes.
These checks are not proof of equivalence for the complete program.

JWasm 2.21 has no supported release-build equivalent of a global `-O0` for
instruction sizing. `OPTION NOLJMP` governs extension of conditional jumps,
not this shortening. This port retains normal assembly behavior and specifies
sizes where the original program depends on them. If similar incompatibilities
recur across utilities, evaluate a shared assembler configuration, an alternate
assembler, or a controlled assembler change before accumulating local fixes.

## Start PUTR interactively

Create/select an empty working directory on **G:**. Start DOSBox Staging with
the included isolated configuration, bypassing personal configurations:

```powershell
& 'D:\GitHub\dosbox-staging\dosbox.exe' --noprimaryconf --nolocalconf --conf .\dosbox-putr.conf
```

At its DOS prompt, mount the utility directory and the chosen G: work directory:

```text
mount p "D:\GitHub\simtools\extracters\putr"
mount c "G:\PutrWork"
c:
p:\putr.com
```

`G:\PutrWork` must already exist. Keep image files in the mounted G: workspace;
do not switch to the utility drive to create them. Release mounts/exit the
emulator, delete temporary test images after the case even on failure, and
verify deletion. The automated tests implement this lifecycle themselves.

The provided configuration disables NE2000, IPX, serial devices, and the
webserver. The automated runner additionally uses dummy SDL video/audio,
software rendering, a normal 386 CPU core, and a Windows-system-only PATH.
Networking is not needed for this workflow. Personal configurations are untouched.

## Useful PUTR commands and format details

PUTR has an interactive command interpreter. A `PUTR.INI` in its current
directory is executed automatically. `@ filename` reads an indirect command
file, with `.CMD` as its default extension. Indirect files chain rather than
nest. `QUIT` or `EXIT` returns to DOS. `SET MORE OFF` disables page pauses.

| Operation | Example / notes |
| --- | --- |
| Create an RT-11 RK05 image | `FORMAT DISK.DSK /RK05 /RT11`; answer confirmation, volume ID, owner |
| Create an OS/8 RK05 image | `FORMAT DISK.DSK /RK05 /OS8`; answer confirmation, info words, system allocation |
| Mount an image | `MOUNT X: DISK.DSK /RK05 /RT11`; `/RONLY` selects read-only access, `/RW` read/write |
| Inspect | `SHOW X:`, `VOLUME X:`, `DIRECTORY X: /FULL` |
| Binary transfer | `COPY/B INPUT.BIN X:DATA.BIN`; reverse source/destination to extract |
| Text transfer | `COPY INPUT.TXT X:TEXT.TXT`; text conversion is the default |
| Transfer between foreign filesystems | Mount two devices, then `COPY/B X:DATA.BIN Y:DATA.BN` |
| Delete | `DELETE/NOQUERY X:DATA.BIN`; `/OVERRIDE` overrides file protection where supported |
| Dismount | `DISMOUNT X:`; closes the image handle |
| RSTS account | `X:[1,2]DATA.BIN`, with decimal project/programmer numbers |
| DOS/BATCH account | `X:DATA.BIN[1,1]`, with octal account numbers |

Binary RT-11 extraction returns allocated 512-byte blocks; non-aligned files
include trailing padding. OS/8 binary interchange uses little-endian 16-bit
containers for 12-bit words: high four bits are ignored on input and cleared
on output. OS/8 uses six-character names and two-character extensions.

PUTR.SAV-format DECtapes use encoded extensions from a fixed list: blank, ASC,
SAV, BIN, BAS, BAC, FCL, TMP, DAT, LST, and PAL (XXX is the fallback marker).
Do not use arbitrary OS/8 extensions such as BN/TX for that format. In the
qualified text round trip, the original and rebuilt programs both retain a
trailing Ctrl-Z byte when extracting PUTR.SAV tape text; the RT-11 and OS/8
cases do not. Linked DOS/BATCH blocks carry 510 payload bytes; binary reads
include final-block slack and do not promise the original host byte length.

Initialization is implemented for RT-11 and OS/8-related formats, including
PUTR.SAV DECtape. RSTS, DOS/BATCH, and XXDP+ write support does not imply that
PUTR can initialize those filesystems. Files-11 ODS-1 and TSS/8 system-disk
support are read-only. `RENAME` and `SQUEEZE` are not implemented commands.
See the bundled ASCII `putr.doc` and source for additional device switches.

## Qualification and known limitation

See [windows-dos-validation.md](windows-dos-validation.md) for the actual tested
scope, comparison against the supplied COM, and the open DOS/BATCH-to-fsio
interoperability issue. A passing source build is not a claim that every format,
physical device, historical DOS version, or DEC guest has been qualified.

Run a focused test with `tests/Check-Putr.ps1`, supplying `-Executable`, `-Case`,
and `-EvidenceRoot`. Temporary media live under `G:\SimtoolsPutrTests` and are
deleted in `finally`, after the owned emulator/tool has exited. Logs and small
byte-comparison receipts are retained. Abrupt termination of PowerShell or the
host can bypass `finally`; inspect the recorded case path before resuming.

`-Case dosbatch-fsio-interop` is a separate diagnostic reproducer and is expected
to fail with the currently recorded fsio build. It is not included as a passing,
skipped, or disabled CTest case. Its failure receipts remain evidence.
