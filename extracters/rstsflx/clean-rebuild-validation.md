# FLX clean/rebuild implementation and qualification

Work date: 2026-11-12 (America/New_York; receipt timestamps are UTC).
Source baseline: `070f0dcc1259276661b8c650378515510a20c974`, initially clean.
Changes in this follow-up are local and unstaged. No staging, commit, or push
was performed by this task.

This record supersedes the RDS0 repair refusal in the
[initial build record](windows-gcc-validation.md). `clean` and `rebuild` are
aliases for the same command handler. The native Windows executable remains
`extracters/rstsflx/flx.exe`.

## Implementation

- Completed the RDS0 mixed MFD traversal: reserve name entries, detect cycles,
  process account accounting entries and UFDs, retain empty accounts, process
  ordinary `[1,1]` files, and handle the `[1,1]` self-reference without counting
  its directory storage twice. Required system accounts are protected.
- Corrected full directory reads, directory-block counting, secondary map
  validation, stale extension-map copies, and the RDS1 pointer-table exclusions.
  Directory allocations consume at least one pack cluster. Cluster extents
  must fit entirely inside the usable device, not merely start inside it.
- Reconstructed allocation bits from reachable storage and known bad blocks;
  reclaimed unreachable blockettes in the same pass. Corrected deletion links,
  empty-directory headers, shared-directory references, and RDS1.2 usage quotas.
  Truncation also bounds RMS size/EOF metadata to the remaining allocation.
- Corrected read-only confirmation behavior and EOF handling. Destructive
  truncation prompts now require an affirmative answer; read-only simulations
  continue without writing. Protected/system files are not silently deleted.
- Bounded system-file lookup and bad-block/attribute scans. Unreadable critical
  metadata fails closed. Bad-block DCNs use one-based alignment; a malformed
  bad-block chain is not discarded to make the pack appear healthy.
- Added deferred metadata writes, read-after-write visibility, cache
  invalidation, abort cleanup, and checked seek/close/flush results. Scanning
  and confirmation finish before container mutation. Commit writes a dirty
  label first and the final clean label last. This does not provide a durable
  transaction journal, rollback after a write failure, or power-loss atomicity.

The on-disk layout follows the local `fldef.h`, `fip.c`, and `doinit.c`; the
[upstream layout definitions](https://raw.githubusercontent.com/open-simh/simtools/master/extracters/rstsflx/fldef.h)
also describe the old mixed account/file MFD. The original FLX manual, section
5.3, defines read-only preview and repair confirmation behavior.

## Validation method and limits

`tests/Check-Flx.ps1` owns serial process execution and G: cleanup.
`tests/Clean-Cases.ps1` reads little-endian image structures directly to locate
faults and check allocation tables. It saves fault offsets/values, expected and
actual hashes, process transcripts, and cleanup receipts. Tests compare complete
bitmaps, exported payload bytes, unchanged-image hashes after preview/refusal,
and repeated rebuilds. The RDS1.2 mount timestamp is excluded only from the
second-rebuild byte comparison; it is an intentional dismount update.

The repair cases exercise RDS0 RK05, RM02, and RL02 with pack cluster size 16;
RDS1.1 RL02; and RDS1.2 RM02 with pack cluster size 32. The growth case extends
the old MFD beyond 16 blocks and a four-block-cluster UFD beyond 16 blocks,
with 254 additional accounts and 301 files in the grown UFD.

Fault coverage includes both allocation-bit error directions and padding,
dirty/read-only flags, MFD/UFD/retrieval cycles, invalid accounting links,
self-reference repair, deleted files and orphan blockettes, shared file data,
shared directories, stale map copies, end-of-device extents, valid bad-block
records including PCS 16, and fatal bad-block/root/SATT/system-lookup damage.
Interactive cancellation/recovery is checked in one FLX process.

These are host container tests with direct structural oracles. They do not
establish RSTS guest acceptance, native INIT/ONLCLN equivalence, recovery from
arbitrary damage, every geometry/RMS organization, physical devices, DOS/Linux
builds, >2-GiB containers, injected host write failures, or power-loss recovery.
If essential system files or their lookup path cannot be trusted, repair can
still refuse the image. The native console's Readline/history limitation and
other unrelated limitations in the build guide remain open.

## Final results

Selected tools: PowerShell 7.6.3; WinLibs GCC 16.2.0 from
`C:\gcc-winlibs-x86_64\bin`; CMake/CTest 4.4.5 from
`C:\Program Files\CMake\bin`; Ninja 1.13.2. The existing preset selects
GNU C11, Release `-O2 -DNDEBUG -Wall -Wextra`, and one build/test job.
The final clean build completed all 26 compile/link steps with **zero warnings
and zero errors**.

| Verification | Result | Serial FLX process invocations |
| --- | --- | ---: |
| Complete functional inventory | 41 distinct cases passed across the main run and one infrastructure retry | 562 |
| Installed executable | 8/8 passed | 136 |
| Utility-directory executable | 8/8 passed | 136 |
| Combined final evidence | 57 passing case receipts | 834 |

The initial final-suite CTest invocation reported **40 passed and one failed**
in 102.45 seconds. That failure was a PowerShell startup crash before test
initialization, not a FLX process failure. `ctest --rerun-failed` passed its one
case in 2.40 seconds with unchanged source, executable, and test-script hashes.
This is a consolidated 41-case result, not a claim that the original full
invocation passed without an infrastructure failure. Windows recorded
`pwsh.exe` 7.6.3.500 / `coreclr.dll` 10.0.926.27113, exception `0xc0000005`,
offset `0x108b47`. The error and retry are retained.

Each deployed copy passed `repair-rds0-rk05`, `repair-growth`, `repair-crosslink`,
`repair-rds11`, `repair-rds12-pcs32`, `repair-interactive`, `repair-fatal-badb`,
and `repair-mfd-cycle`. Child FLX processes use a PATH limited to Windows and
System32; no compiler directory supplies a runtime dependency during the tests.

The build, installed, and utility-directory copies are **217499 bytes** and
share this SHA-256:

```text
24F4AC755E5580FAAB0FC010DF5DDE73AEF915CFD54A8C6829E6F2737F321CED
```

PE imports remain `KERNEL32.dll` and `msvcrt.dll` only. Installation places the
executable in `bld/install/winlibs-x64/bin` and eight original/new documents in
`bld/install/winlibs-x64/share/doc/flx`. The automatic build copy remains beside
the utility sources. All selected receipts authenticate the final executable
and both harness scripts, and verify their own media deletion. Final audit:
zero remaining test directories/images and zero active FLX processes.

## Evidence and media

Follow-up evidence: `bld/winlibs-x64/flx/clean-rebuild`, including
`configure-final.log`, `build-final.log`, `test-final.log/xml`,
`test-retry.log/xml`, `runtime-events.json`, `final-receipts.json`, deployment
receipts, `tool-hashes.json`, `source-file-hashes.json`, `source-changes.patch`,
`executable-hashes.json`, `qualification-summary.json`, and `completion.json`.
Case transcripts: `bld/winlibs-x64/flx/checks/<case-id>`.
The previous executable, final logs, manifests, and guides are preserved under
`bld/winlibs-x64/flx/prior-qualification-070f0dc`; prior case receipts remain in
their original directories. Historical hashes are not presented as the current
binary identity.

Development failures are retained, including the label-cache overwrite,
empty-header and quota second-pass corrections, and corrected test expectations
for multi-entry retrieval chains. Two PowerShell CLR startup crashes occurred
before their case directories were created: a development growth test and the
final UFD-cycle test. Audits found no FLX process or leftover G: image; both
cases passed on retry. The underlying runtime cause is not claimed to have
been established, and no host runtime changes were made.

All temporary images belong to unique `G:\SimtoolsFlxTests` case directories.
Each case deletes its image after success or failure and verifies deletion.
No persistent guest disk is used or changed. No subagents, scheduled tasks,
parallel foreground units, or extra BSD guests are used.
