# FLX / rstsflx Windows GCC qualification

Date: 2026-11-12. Source baseline: simtools
`681df6ea8bc110be5d2f997bd4fa723b6c325fba` on `main`, clean at the start of
this task. The changes described here are local and unstaged. No commit or push
was performed.

The repository's `rstsflx` directory builds the single **FLX v2.6** utility,
named `flx.exe`. There is no separate second `rstsflx` implementation to build.
This is a Windows host build for the scope below, not a claim that every
historical FLX feature is complete.

## Tools and products

| Component | Selected version/path |
| --- | --- |
| PowerShell | 7.6.3, `C:\Program Files\PowerShell\7\pwsh.exe` |
| GCC | WinLibs 16.2.0, `C:\gcc-winlibs-x86_64\bin\gcc.exe`, x86_64 MSVCRT POSIX SEH |
| CMake / CTest | 4.4.5, `C:\Program Files\CMake\bin` |
| Ninja | 1.13.2, `C:\gcc-winlibs-x86_64\bin\ninja.exe` |
| Configuration | Release, GNU C11, `-O2 -DNDEBUG -Wall -Wextra`, `FLX_NATIVE_CONSOLE`, one job |

The final clean build completed all 26 compilation/link steps with **zero
warnings and zero errors**. Final `flx.exe` size: **212450 bytes**. SHA-256:

```text
DA3053E31068E327A7E17899C32BFA5FC173E6E7833C2AD962C49DD40AB828E8
```

Imports are `KERNEL32.dll` and `msvcrt.dll` only. Functional processes run with
PATH limited to the Windows and System32 directories, with FLX/default-disk
environment overrides removed. No Readline, ncurses, SIMH, DOSBox, guest, or
additional GCC runtime DLL is used.

## Results

Final CTest: **12/12 passed**, zero failed/skipped/disabled, **140 serial FLX
process invocations**, 22.84 seconds. Final case receipts identify the exact
executable and test-script hashes. All temporary media were deleted after each
case, including failed development cases.

| Case | Verified behavior |
| --- | --- |
| commands | Version/prompt, EOF/blank/long input, unknown/ambiguous commands and switches, missing arguments, no HOME requirement |
| interactive | Scripted multi-command disk lifecycle, recovery after an open failure, EOF at a confirmation prompt, direct CLI host paths with spaces |
| rds0-rk05 | RDS0 creation, basic transfers, metadata listing, rename/delete; **explicit refusal of both clean modes with unchanged image hash** |
| rds11-rl02 | RDS1.1 on an RL02-sized container, same file lifecycle and read-only clean |
| rds12-rm02 | RDS1.2 on an RM02-sized container, same lifecycle and read-only clean, device cluster size greater than one |
| records | Ordinary text and RMS stream round trips; RMS variable odd/even records; fixed records of 4 and 512 bytes |
| boundaries | Binary lengths 1, 511, 512, 513, 32769, 65536; exact expected content and zero padding to 512-byte blocks |
| directories | Forty files forcing directory growth, user account, tree extraction, wildcard concatenation, account removal |
| metadata | Runtime-system and protection changes, no-delete enforcement, clearing no-delete |
| readonly | Pack read-only write refusal, unchanged-image proof for reads/refusal, explicit `-Write` override |
| clean-compress | RDS1 read-only clean without mutation, writable clean of a healthy image, zeroing unused clusters, allocation report, data preservation |
| errors | Missing/truncated media, invalid geometry/cluster size, invalid fixed record size, unknown hook device, existing-image and declined-initialization preservation |

Installed copy: **6/6 passed**, 77 serial invocations. Utility-folder copy:
**6/6 passed**, another 77 serial invocations. Each deployed copy passed
`commands`, `rds0-rk05`, `rds11-rl02`, `rds12-rm02`, `records`, and `directories`.
That gives **24 final/deployment cases and 294 serial process invocations**.
All three executable copies have the SHA-256 above. Installation includes the
original license/manual and both new guides; installed document hashes match
the source documents.

## Changes and remaining work

- Added CMake/presets, single-job pools, automatic source-folder executable
  placement, local installation, and the PowerShell case harness with G: cleanup.
- Added a native console input implementation and container-only Windows I/O
  backend. The original Readline and non-Windows source paths remain present.
  Native Readline completion/history are not implemented.
- Resolved duplicate module globals, a date-string overread, invalid-date bounds,
  command state across `longjmp`, uninitialized locals, signedness diagnostics,
  unused declarations, and missing braces in command wildcard handling.
- Repaired wildcard concatenation and per-file tree output path construction,
  bounded generated output paths, handled EOF at confirmation prompts, and
  stopped invalid cluster sizes before creating media.
- Fixed the unknown `hook` device terminator check. Boot preparation itself was
  not qualified.
- Allowed the special RDS0 `[0,1]` system account and prevented writes to the
  RDS1-only GFD pointer table on RDS0. DEC's historical
  [RSTS/E V6 programming manual](https://bitsavers.trailing-edge.com/pdf/dec/pdp11/rsts_e/V06/DEC-11-ORPMA-B-D_RSTS_E_Programming_Manual_V06B-02_Nov76.pdf)
  describes the `[0,1]` system account (section 1.1.4).
- Fixed fixed-record-size validation and RMS EOF metadata/reader calculations.
  The [RMS-11 User's Guide](https://www.bitsavers.org/pdf/dec/vax/vms/2.0/AA-D538A-TC_RMS-11_Users_Guide_197903.pdf)
  describes logical EOF as a virtual block plus byte offset. The
  [VSI I/O reference](https://docs.vmssoftware.com/vsi-openvms-io-user-s-reference-manual/)
  documents the corresponding first-free-byte/block-boundary convention.
- **RDS0 clean/rebuild remains unimplemented and is now blocked before any
  write.** The upstream old-MFD routine does not traverse account/file entries;
  enabling bitmap reconstruction would risk treating live data as free. The
  passing refusal tests do not mean the repair feature is implemented.

RDS guest acceptance, Linux/DOS builds, physical device access, boot hooking,
merge initialization, >2-GiB containers, broad geometry transitions, all RMS
organizations and boundary patterns, fault injection, and exhaustive malformed
input handling remain outside this qualification. The repository's inherited
BUGS document is retained; its erase-on-delete/general I/O concerns are not
closed by these tests. Readline editing/completion/history and a complete RDS0
clean implementation would be needed before claiming full feature parity.

## Evidence

Evidence root: `D:\GitHub\simtools\bld\winlibs-x64\flx` (ignored build output).

- `configure-*.log`, `build-*.log`, `build-final.log`, `CMakeCache.txt`,
  `compile_commands.json`: configuration, flags, diagnostics, final clean build.
- `test-first.*`, focused test logs, `test-final.log`, `test-final.xml`,
  `final-suite-start.txt`, `final-receipts.json`: historical and final results.
- `checks/<case-id>`: complete inputs, stdout/stderr, exit/timeout results,
  expected/actual byte hashes, executable/script hashes, and cleanup receipts.
- `installed-checks`, `utility-directory-checks`, and their top-level logs:
  deployed binary functional checks.
- `provenance.json`, `source-file-hashes.json`, `source-changes.patch`,
  `executable-hashes.json`, `flx.pe-imports.txt`, `qualification-summary.json`,
  `completion.json`: tool/source/output identity and final completion audit.

Development failures are retained: initial RDS0 initialization rejection,
variable-record truncation, and the invalid fixed-record divide-by-zero crash.
They are not final passing results. Receipt timestamps must be compared as
`DateTimeOffset` values (or JSON strings), not mixed local/UTC `DateTime` values.

No test image is retained in the repository or on G:. The harness verifies
cleanup after both success and failure. No staging, commits, pushes, subagents,
scheduled tasks, or additional BSD guests were used for this work.
