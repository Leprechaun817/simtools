param(
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string]$DosBox = 'D:\GitHub\dosbox-staging\dosbox.exe',
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 is required' }
$WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
$DosBox = (Resolve-Path -LiteralPath $DosBox).Path
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$config = Join-Path $EvidenceDirectory 'dosbox.conf'
$marker = Join-Path $WorkingDirectory 'DOSDONE.TXT'
if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
@"
[sdl]
output=texture
texture_renderer=software
fullscreen=false
[cpu]
core=normal
cputype=386
cpu_cycles=30000
[mixer]
nosound=true
[midi]
mididevice=none
[ethernet]
ne2000=false
[ipx]
ipx=false
[serial]
serial1=disabled
serial2=disabled
serial3=disabled
serial4=disabled
[webserver]
webserver_enabled=false
[autoexec]
mount c "$WorkingDirectory"
c:
call RUN.BAT
echo DOSBOX-BATCH-COMPLETE > DOSDONE.TXT
exit
"@ | Set-Content -LiteralPath $config -Encoding ascii
$record = [ordered]@{
    startedUtc = [DateTime]::UtcNow.ToString('o')
    executable = $DosBox
    executableSha256 = (Get-FileHash -LiteralPath $DosBox).Hash
    workingDirectory = $WorkingDirectory
    configSha256 = (Get-FileHash -LiteralPath $config).Hash
    passed = $false
}
$process = [Diagnostics.Process]::new()
$started = $false
$stdout = $null
$stderr = $null
try {
    $start = [Diagnostics.ProcessStartInfo]::new($DosBox)
    foreach ($argument in @('--noprimaryconf','--nolocalconf','--conf',$config,'--exit')) {
        $start.ArgumentList.Add($argument)
    }
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $start.Environment['SDL_VIDEO_DRIVER'] = 'dummy'
    $start.Environment['SDL_AUDIO_DRIVER'] = 'dummy'
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'DOSBox Staging did not start' }
    $started = $true
    $record.processId = $process.Id
    $record.processStartedUtc = $process.StartTime.ToUniversalTime().ToString('o')
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'DOSBox Staging timed out' }
    $record.exitCode = $process.ExitCode
    if ($process.ExitCode -ne 0) { throw "DOSBox exit code $($process.ExitCode)" }
    if (-not (Test-Path -LiteralPath $marker) -or
        (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'DOSBOX-BATCH-COMPLETE') {
        throw 'DOS batch did not reach its completion marker'
    }
    $record.passed = $true
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    if ($stdout) { $stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'dosbox.stdout.log') }
    if ($stderr) { $stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'dosbox.stderr.log') }
    $record.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'dosbox-result.json')
    $process.Dispose()
}
