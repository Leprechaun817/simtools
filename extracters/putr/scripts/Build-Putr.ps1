param(
    [string]$BuildDirectory = "$PSScriptRoot\..\..\..\bld\dos\putr",
    [string]$AssemblerDirectory = "$PSScriptRoot\..\..\..\bld\dos\putr\toolchain\jwasm-2.21",
    [string]$DosBox = 'D:\GitHub\dosbox-staging\dosbox.exe',
    [switch]$NoDeploy
)
$ErrorActionPreference = 'Stop'
$sourceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
$run = Join-Path $BuildDirectory ('assembly-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $run 'work'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'putr.asm') -Destination (Join-Path $work 'PUTR.ASM')
foreach ($file in @('JWasmd.exe','hdpmi32.exe')) {
    Copy-Item -LiteralPath (Join-Path $AssemblerDirectory $file) -Destination $work
}
@'
@echo off
JWASMD -Zm -bin -Fl=PUTR.LST -Fo=PUTR.COM PUTR.ASM > BUILD.TXT
if errorlevel 1 goto failed
echo ASSEMBLY-PASS > BUILD.OK
goto done
:failed
echo ASSEMBLY-FAIL > BUILD.BAD
:done
'@ | Set-Content -LiteralPath (Join-Path $work 'RUN.BAT') -Encoding ascii
& (Join-Path $PSScriptRoot 'Invoke-PutrDosBox.ps1') -WorkingDirectory $work -EvidenceDirectory $run -DosBox $DosBox
$log = Get-Content -LiteralPath (Join-Path $work 'BUILD.TXT') -Raw
$log | Write-Output
if (-not (Test-Path -LiteralPath (Join-Path $work 'BUILD.OK')) -or $log -notmatch '0 warnings, 0 errors') {
    throw "PUTR assembly failed or emitted diagnostics; see $run"
}
$binary = Join-Path $work 'PUTR.COM'
if (-not (Test-Path -LiteralPath $binary) -or (Get-Item -LiteralPath $binary).Length -gt 65280) {
    throw 'Missing or oversized DOS COM output'
}
& (Join-Path $PSScriptRoot 'Check-PutrEncoding.ps1') -Listing (Join-Path $work 'PUTR.LST') -Executable $binary -Receipt (Join-Path $run 'encoding-checks.json')
$binDirectory = Join-Path $BuildDirectory 'bin'
New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
Copy-Item -LiteralPath $binary -Destination (Join-Path $binDirectory 'PUTR.COM')
if (-not $NoDeploy) {
    Copy-Item -LiteralPath $binary -Destination (Join-Path $sourceDirectory 'putr.com')
}
[ordered]@{
    completedUtc = [DateTime]::UtcNow.ToString('o')
    sourceSha256 = (Get-FileHash -LiteralPath (Join-Path $work 'PUTR.ASM')).Hash
    assemblerSha256 = (Get-FileHash -LiteralPath (Join-Path $work 'JWasmd.exe')).Hash
    extenderSha256 = (Get-FileHash -LiteralPath (Join-Path $work 'hdpmi32.exe')).Hash
    executableSha256 = (Get-FileHash -LiteralPath $binary).Hash
    executableBytes = (Get-Item -LiteralPath $binary).Length
    command = 'JWASMD -Zm -bin -Fl=PUTR.LST -Fo=PUTR.COM PUTR.ASM'
    deployed = -not $NoDeploy
    evidenceDirectory = $run
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BuildDirectory 'build-result.json')
