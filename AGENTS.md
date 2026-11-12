# Project instructions

## Working rules

- Make repository changes only within the user's authorized work and preserve
  unrelated changes. Staging, commits, and pushes require express permission.
- Use PowerShell 7 explicitly: `C:\Program Files\PowerShell\7\pwsh.exe`.
- Run foreground scripts, batches, commands, and command bundles strictly one
  at a time. Pipelines, semicolons, and multiline scripts are allowed within an
  execution unit; wait for that unit to finish before starting another.
- Never use subagents. Do not create scheduled tasks unless requested.
- Already authorized, verified detached long-running processes, including the
  BSD GCC controller, may overlap this work. This exception does not authorize
  parallel foreground commands, parallel utility builds, or additional guests.
  Preserve their existing resource limits and ownership rules.
- Summarize new or generated code and the verification results in chat.

## Standard utility workflow

User direction recorded on 2026-11-12: apply the complete process established
with `config11` to every remaining utility, one utility at a time.

- Follow [WINDOWS-BUILD-WORKFLOW.md](WINDOWS-BUILD-WORKFLOW.md) for inspection,
  configuration, compilation, functional checks, local installation, dependency
  checks, executable placement, provenance, and documentation.
- For native Windows C/C++ utilities, explicitly select GCC/G++ from
  `C:\gcc-winlibs-x86_64\bin`, CMake from `C:\Program Files\CMake\bin`, and
  Ninja from the WinLibs installation. Do not silently fall back to MSVC or
  another compiler installation.
- Use one build job and one test at a time. Complete and verify the current
  utility before advancing to the next; report unresolved blockers explicitly.
- Automatically copy each finished executable back to that utility's own
  directory after a successful build, retaining the CMake-managed build copy.
  Verify the copied executable as well as the local installed executable.
- Adapt flags, dependencies, test cases, and execution environment to the
  utility. Scripts, libraries, and DOS-specific programs follow the applicable
  steps; do not invent a native GCC executable or claim an unperformed check.
- For DOS programs, use `D:\GitHub\dosbox-staging` as the default test
  environment unless strict compatibility requires MartyPC or another already
  agreed environment. Verify its source/configuration/binary identity against
  `D:\GitHub\dosbox-staging\docs\windows-vs2026-validation.md` before reuse.
  Rebuild and qualify it when the selected checkout or required configuration
  changes. The initial VS2026 rebuild was qualified on 2026-11-12.
- DOSBox Staging compiler exception authorized on 2026-11-12: use the installed
  Visual Studio 2026 and its upstream-supported ClangCL toolchain for that
  emulator. This does not change the WinLibs GCC choice for simtools utilities.
- Create test/qualification/validation virtual hard disks only on G:. Release
  consumers, delete each temporary image after its case even on failure, and
  verify deletion. Preserve previously authorized retained guest OS disks.
- For host-side tooling, use only the latest Python already installed on the
  host or supplied by the current Codex installation. Never download, copy,
  move, extract, archive, or retain Python executables or archives for this
  project. Copying utility
  scripts does not authorize copying their interpreter. Record runtime
  provenance; preserve historical receipts without recreating old runtimes.
