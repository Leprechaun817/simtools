# PUTR Windows-host / DOS qualification

Date: 2026-11-12 (America/New_York). Source baseline:
`8218455bae631c3189ce88600c2472458299bd2a`, plus the local build, test, and four
assembly annotations documented in [README.cmake.md](README.cmake.md).

## Build and runtime

- PUTR V2.01 assembled from source under DOSBox Staging using JWasm 2.21's DOS
  protected-mode assembler and its supplied HDPMI32 extender.
- CMake 4.4.5, Ninja 1.13.2, PowerShell 7.6.3; serial foreground execution.
- Final assembly: 23,322 source lines, four passes, **zero warnings/errors**.
- Encoding audit: **22 checks passed** (19 fixed-byte skips, three word loads).
- Runtime host: Windows x64, DOSBox Staging `0.84.0-alpha`, normal 386 core.
- DOSBox source `27b1b7ca719c21ef3444f7ad1cf2d9cd439527cc` and recorded local
  build/configuration hashes were reverified against its VS2026 qualification.
  Its executable SHA-256 remains
  `C5E97C7DF5A30F1088513D740D127AC1C4E588AB22EB3F9D1D3A8CFC7D67EBBE`.
- JWasm package came from the author's
  [v2.21 release](https://github.com/Baron-von-Riedesel/JWasm/releases/tag/v2.21).
  Archive SHA-256:
  `A6B318CC3B3C98369F794C8F42EB2AD969E46485AD9B9FE81B7AC35F9321AE1B`.
- JWASMD SHA-256:
  `7033A577FBBC59D1641260ABCCB6BE41B56205CACA2D9C7A1C9F81A6CD3A7DD6`.
  HDPMI32 SHA-256:
  `FCC8F6CF6CE0A931CBE8C37F84F497CEA121D4D9A9A36D4BC80CF14961F954AB`.
- Final PUTR.COM: **48,631 bytes**, SHA-256
  `C7421BE5A29952AD40B3986153F92D1547A1ADB21CB6E6A235B1DEDA32A0186D`.
- Supplied reference PUTR.COM: 44,264 bytes, SHA-256
  `24FC5FA98A409327E3DE9DC1F6A0EB10A90BAB432F602D9D24C105A41D845D6B`.

The rebuilt COM is not byte-identical to the supplied binary. JWasm selects
different instruction layouts and emits trailing uninitialized storage in the
flat output. No whole-program binary-equivalence claim is made. Behavioral
comparison is bounded to the cases below. PUTR does not require the assembler,
HDPMI32, a separate installed DOS OS, or extra runtime DLLs when run in this
qualified DOSBox environment.

## Functional checks

The final rebuilt suite passed **12/12**, with no failed, skipped, or disabled
CTest cases, in 29.45 seconds. The supplied reference COM separately passed
the **same 12 cases**. Each suite records 34 DOSBox/native comparison processes;
NASM's construction of the small DOS capture helper is recorded separately.

| Case | Qualified behavior |
| --- | --- |
| commands | Startup, settings, DOS-directory listing, indirect command chaining, unknown-command diagnostic |
| rt11 | RK05 creation, mount, show, directory, binary/text transfer, delete, dismount |
| os8 | RK05 creation, 12-bit-word masking, binary/text transfer, delete, dismount |
| putr-tape | 380,292-byte TU56 image, interleaved PUTR.SAV filesystem, binary/text transfer, supported extensions, retained Ctrl-Z, delete |
| cross-filesystem | Direct RT-11 to OS/8 to RT-11 transfer of 12-bit word data |
| boundaries | RT-11 binary sizes 0, 1, 511, 512, 513, 32,769, and 65,536 bytes, with checked 512-byte padding |
| readonly-errors | Write/delete refusals and unchanged image SHA-256; missing-image and unsupported-initializer diagnostics |
| rt11-independent | fsio reads PUTR-created files and PUTR reads fsio-written files in the same image |
| dosbatch | Reads fsio-created linked files; PUTR write/read round trip; independent raw directory/block-chain/payload checks, using 1,530-byte full-block data |
| rsts0 | PUTR and flx transfer files in both directions on an RDS 0.0 RK05 image |
| rsts11 | Same on RDS 1.1 |
| rsts12 | Same on RDS 1.2 |

All three executable copies match the final digest. The installed copy passed
**6/6** deployment cases and the utility-directory copy passed **6/6**; these
are recorded in `qualification-summary.json`. Deployment cases are commands,
RT-11, OS/8, PUTR tape, read-only/errors, and RDS0. The standalone
COM is copied into each fresh G: test directory; its digest identifies the
deployed source being exercised. All outputs are checked by exact length/hash
or explicit state/diagnostic assertions, not by emulator exit status alone.

## DOS/BATCH-to-fsio interoperability remains open

The reverse independent DOS/BATCH lane fails with **both** the supplied and
rebuilt PUTR. After PUTR writes BACK.BIN, fsio exits with Windows access
violation `0xC0000005` while extracting it. This failure is separate from the
12 passing cases and is preserved under `known-interop-failure` for both COMs.
It is not an accepted success, skip, or disabled test.

The recorded directory inspection shows next-free-byte 512 for the original
fsio-created file and zero for the PUTR-created file. PUTR's `dbcl5` explicitly
writes zero into directory word 4, described in its source as unknown.
`converters/fsio/dos11.c` interprets that field as the final-block byte limit.
For linked blocks its read cursor begins at 2 and stops on equality with that
limit; a zero limit allows it to read beyond its allocated block buffer. This
source path explains the observed crash; a debugger trace was not collected.

PUTR reads its own written file correctly, and a separate host-side directory
and block-chain inspection confirms all 1,530 payload bytes and the terminating
link. That does not settle which historical format convention should govern
the byte-limit field. Resolve the format contract and harden fsio in a separate
follow-up before claiming this cross-reader direction works. Neither fsio nor
PUTR's DOS/BATCH algorithms were changed in this task.

## Compatibility issue found during development

The first syntactically successful JWasm build shortened the jump after an
RT-11 `jz $+5`, making that fixed skip land inside the next instruction. It
incorrectly listed free space and filenames and failed extraction. The supplied
COM passed the same test. Explicit `near ptr` restores the original three-byte
jump; the final build passes that test and the complete bounded suite.

The other source edits are three explicit `word ptr` declarations in ODS-1
header loads. Their bytes match the original program's corresponding loads:
`8B 54 16`, `8B 44 18`, `8B 5C 1A`. These annotations preserve intended widths;
ODS-1 image compatibility itself has not been tested here.

The build now rejects drift in the checked fixed-byte skips. A global
no-optimization release option was not found in JWasm 2.21's
[option parser](https://github.com/Baron-von-Riedesel/JWasm/blob/v2.21/src/cmdline.c)
or [branch implementation](https://github.com/Baron-von-Riedesel/JWasm/blob/v2.21/src/branch.c).
Its short-jump selection excludes explicitly near branches. The user's agreed
approach is narrow encoding requirements now, with broader toolchain changes
worth considering if similar issues recur in other utilities.

Initial failed assemblies, the faulty rebuilt COM, early test-fixture failures,
and corrected results remain in ignored build evidence. Early fixtures assumed
`SHOW C:` printed PC-DOS instead of DOS, did not capture DOS stderr, used
unsupported PUTR tape extensions, expected no tape-text Ctrl-Z, and assumed
DOS/BATCH binary extraction preserved a non-block-aligned host length. Those
assumptions were corrected against source and/or the supplied binary; program
behavior was not changed to make those fixtures pass.

## Media, evidence, and limits

All temporary disk/tape images were created in unique directories under
`G:\SimtoolsPutrTests`. The owning process was reaped before cleanup, and each
case's directory was removed and deletion checked, including failed cases.
All 62 retained case receipts verify cleanup, including 13 failed development
or diagnostic cases. The 36 final/reference/deployment cases passed. Images
are not retained. Logs, listings, byte-comparison receipts, directory
metadata, executable hashes, and source hashes remain in
`D:\GitHub\simtools\bld\dos\putr`:

- `configure.log`, `build-final.log`, `build-result.json`, `assembly-*`.
- `test-final.log`, `test-final.xml`, `final-suite-start.txt`, `final-receipts.json`.
- `checks`, `upstream-checks`, `upstream-final-checks`, `known-interop-failure`.
- `installed-checks`, `utility-directory-checks`, `install.log`.
- `toolchain/release.json`, `toolchain/provenance.json`, `provenance.json`.
- `executable-hashes.json`, `source-file-hashes.json`, `qualification-summary.json`.

The emulator uses only a mounted host directory, no separately booted DOS disk.
NE2000, IPX, serial and webserver facilities are disabled. A system-only PATH
prevents accidental compiler DLL dependencies. The SDL dummy backend's window
opacity warning and normal-core cycle-setting advisories are retained emulator
messages; the assembler itself reports zero warnings.

Unqualified: ODS-1, TSS/8 system disks, XXDP+, hardware floppy/SCSI/TU58/CD-ROM
access, boot installation, extensive corruption recovery, large-image limits,
every device/interleave/partition combination, historical DOS/CPU variants,
and acceptance by an actual DEC guest OS. Ghidra was not required or rebuilt.
No staging, commit, or push was performed.
