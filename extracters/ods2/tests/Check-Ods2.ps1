#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][string]$EvidenceRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$bin = Split-Path -Parent $Executable
$root = 'G:\SimtoolsOds2Tests'
$id = $Case + '-' + [guid]::NewGuid().ToString('N')
$work = [IO.Path]::GetFullPath((Join-Path $root $id))
$evidence = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $id
if (-not $work.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Test directory escaped the required G: root'
}
New-Item -ItemType Directory -Force -Path $work,$evidence | Out-Null
[IO.File]::WriteAllText((Join-Path $work 'empty.ini'), "; Isolated test initialization`n")
$script:sequence = 0
$receipt = [ordered]@{ case=$Case; executable=$Executable;
    executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    startedUtc=[DateTime]::UtcNow.ToString('o'); mediaDirectory=$work;
    passed=$false; cleanupVerified=$false; error=$null }
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Run-Program([string]$Program, [string[]]$Arguments, [string]$InputText = '',
                     [int]$ExitCode = 0, [string]$ExpectedError = '') {
    $script:sequence++
    $stem = '{0:D3}' -f $script:sequence
    @{program=$Program;arguments=$Arguments;stdin=$InputText} | ConvertTo-Json |
        Set-Content (Join-Path $evidence "$stem.input.json")
    $psi = [Diagnostics.ProcessStartInfo]::new($Program)
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.Environment['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $psi.Environment['HOMEDRIVE'] = 'G:'
    $psi.Environment['HOMEPATH'] = $work.Substring(2)
    $psi.Environment['ODS2INIT'] = Join-Path $work 'empty.ini'
    $psi.Environment.Remove('ODS2HELP') | Out-Null
    foreach ($arg in $Arguments) { $psi.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $started = $false
    try {
        $started = $process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        $timedOut = -not $process.WaitForExit(30000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stdout.txt"), $out)
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stderr.txt"), $err)
        @{exitCode=$process.ExitCode;timedOut=$timedOut} | ConvertTo-Json |
            Set-Content (Join-Path $evidence "$stem.result.json")
        Assert-True (-not $timedOut) "Process exceeded 30 seconds ($stem)"
        Assert-True ($process.ExitCode -eq $ExitCode) "Exit $($process.ExitCode), expected $ExitCode ($stem): $out $err"
        if ($ExpectedError) {
            Assert-True (($out + $err) -match $ExpectedError) "Missing diagnostic '$ExpectedError' ($stem): $out $err"
        } else {
            Assert-True (-not $err) "Unexpected stderr ($stem): $err"
            Assert-True ($out -notmatch '%[A-Z0-9_]+-[WEF]-') "Unexpected ODS2 diagnostic ($stem): $out"
        }
        return $out + $err
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Run-Ods2([string[]]$Commands, [int]$ExitCode = 0, [string]$ExpectedError = '') {
    $text = (@('set error_exit') + $Commands + @('exit') -join "`n") + "`n"
    Run-Program $Executable @() $text $ExitCode $ExpectedError
}
function Check-Bytes([string]$Name, [byte[]]$Expected) {
    $actual = [IO.File]::ReadAllBytes((Join-Path $work $Name))
    @{name=$Name;expectedLength=$Expected.Length;actualLength=$actual.Length;
        expectedPrefix=if ($Expected.Length) { [Convert]::ToHexString([byte[]]$Expected[0..([Math]::Min(63,$Expected.Length-1))]) } else { '' };
        actualPrefix=if ($actual.Length) { [Convert]::ToHexString([byte[]]$actual[0..([Math]::Min(63,$actual.Length-1))]) } else { '' }} |
        ConvertTo-Json | Set-Content (Join-Path $evidence "$Name.bytes.json")
    Assert-True ($actual.Length -eq $Expected.Length) "$Name length $($actual.Length), expected $($Expected.Length)"
    for ($i=0; $i -lt $actual.Length; $i++) {
        if ($actual[$i] -ne $Expected[$i]) { throw "$Name byte $i is $($actual[$i]), expected $($Expected[$i])" }
    }
    @{name=$Name;length=$actual.Length;sha256=(Get-FileHash -LiteralPath (Join-Path $work $Name)).Hash;
        byteComparisonPassed=$true} | ConvertTo-Json | Set-Content (Join-Path $evidence "$Name.comparison.json")
}
function New-Volume([string]$Image = 'disk.img', [string]$Medium = 'RK05') {
    Run-Ods2 @("initialize/image/noconfirm/nomount/medium=$Medium $Image ODS2TEST",
        "mount/image/write/medium=$Medium A:=$Image ODS2TEST",
        'copy/to_files-11/binary/record_format=undefined input.bin A:[000000]PAYLOAD.BIN', 'dismount A:') | Out-Null
}
try {
    $payload = [byte[]]::new(8192)
    for ($i=0; $i -lt $payload.Length; $i++) { $payload[$i] = $i % 256 }
    $ascii = [Text.Encoding]::ASCII.GetBytes("alpha`r`nbeta`r`nlast`r`n")
    [IO.File]::WriteAllBytes((Join-Path $work 'input.bin'), $payload)
    [IO.File]::WriteAllBytes((Join-Path $work 'input.txt'), $ascii)
    [IO.File]::WriteAllBytes((Join-Path $work 'empty.bin'), [byte[]]@())

    if ($Case -eq 'commands') {
        $out = Run-Ods2 @('show version','help copy','show message',
            ('set message "' + (Join-Path $bin 'ods2_en_us.mdf') + '"'),
            'show message 1','help initialize')
        Assert-True ($out -match 'V3\.0\.2') 'Version absent'
        Assert-True ($out -match 'GCC \(MinGW-w64\)') 'Compiler identity absent'
        Assert-True ($out -match 'record_format' -and $out -match 'medium') 'Compiled help absent'
        Assert-True ($out -match 'NORMAL|normal successful completion') 'External message library absent'
        [IO.File]::WriteAllText((Join-Path $work 'nested.cmd'), "echo NESTED_OK`n")
        $out = Run-Program $Executable @('set','error_exit','$','@nested.cmd','$','echo','CLI_OK','$','exit')
        Assert-True ($out.Contains('NESTED_OK') -and $out.Contains('CLI_OK')) 'CLI/nested command dispatch failed'
    } elseif ($Case -match '^(raw|vhd)-(rk05|rl02|rm02)$') {
        $medium = $Matches[2].ToUpperInvariant()
        $image = if ($Matches[1] -eq 'vhd') { 'disk.vhd' } else { 'disk.img' }
        New-Volume $image $medium
        $out = Run-Ods2 @("mount/image/write/medium=$medium A:=$image ODS2TEST",
            'create/directory A:[TEST.SUB]',
            'copy/to_files-11/ascii/record_format=streamlf input.txt A:[TEST.SUB]TEXT.TXT',
            'copy/to_files-11/binary/record_format=undefined empty.bin A:[TEST.SUB]EMPTY.BIN',
            'directory/full A:[TEST.SUB]*.*;*',
            'copy/from_files-11/ascii A:[TEST.SUB]TEXT.TXT output.txt',
            'copy/from_files-11/binary A:[TEST.SUB]EMPTY.BIN empty.out',
            'rename A:[000000]PAYLOAD.BIN A:[TEST.SUB]RENAMED.BIN',
            'extend/allocate=24 A:[TEST.SUB]RENAMED.BIN',
            'extend/truncate A:[TEST.SUB]RENAMED.BIN','dismount A:')
        Check-Bytes 'output.txt' $ascii
        Check-Bytes 'empty.out' ([byte[]]@())
        Run-Ods2 @("mount/image/medium=$medium A:=$image ODS2TEST",
            'copy/from_files-11/binary A:[TEST.SUB]RENAMED.BIN output.bin',
            'show volumes','dismount A:') | Out-Null
        Check-Bytes 'output.bin' $payload
        Run-Ods2 @("mount/image/write/medium=$medium A:=$image ODS2TEST",
            'delete/noconfirm A:[TEST.SUB]RENAMED.BIN;*','dismount A:') | Out-Null
        Run-Ods2 @("mount/image/medium=$medium A:=$image ODS2TEST",
            'copy/from_files-11/binary A:[TEST.SUB]RENAMED.BIN absent.bin') 1 'file not found|no such file' | Out-Null
    } elseif ($Case -eq 'readonly') {
        New-Volume
        $hash = (Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash
        Run-Ods2 @('mount/image/medium=RK05 A:=disk.img ODS2TEST',
            'copy/to_files-11/binary/record_format=undefined input.bin A:[000000]REFUSED.BIN') 1 'write.lock|write.protect' | Out-Null
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash -eq $hash) 'Read-only mount changed image'
        Run-Ods2 @('mount/image/medium=RK05 A:=disk.img ODS2TEST',
            'copy/from_files-11/binary A:[000000]PAYLOAD.BIN output.bin','dismount A:') | Out-Null
        Check-Bytes 'output.bin' $payload
    } elseif ($Case -eq 'versions') {
        New-Volume
        Run-Ods2 @('mount/image/write/medium=RK05 A:=disk.img ODS2TEST',
            'copy/to_files-11/ascii/record_format=streamlf input.txt A:[000000]VERSION.TXT',
            'copy/to_files-11/ascii/record_format=streamlf input.txt A:[000000]VERSION.TXT',
            'copy/to_files-11/ascii/record_format=streamlf/append input.txt A:[000000]VERSION.TXT;2',
            'directory A:[000000]VERSION.TXT;*',
            'copy/from_files-11/ascii A:[000000]VERSION.TXT;1 one.txt',
            'copy/from_files-11/ascii A:[000000]VERSION.TXT;2 two.txt',
            'delete/noconfirm A:[000000]VERSION.TXT;1','dismount A:') | Out-Null
        Check-Bytes 'one.txt' $ascii
        Check-Bytes 'two.txt' ([byte[]]($ascii + $ascii))
    } elseif ($Case -eq 'directories') {
        New-Volume 'disk.img' 'RL02'
        $cmd = @('mount/image/write/medium=RL02 A:=disk.img ODS2TEST','create/directory A:[MANY.DEEP]')
        for ($i=0; $i -lt 80; $i++) { $cmd += ('copy/to_files-11/binary/record_format=undefined input.bin A:[MANY.DEEP]F{0:D3}.BIN' -f $i) }
        $cmd += @('directory A:[MANY.DEEP]F*.BIN;1','dismount A:')
        $out = Run-Ods2 $cmd
        Assert-True ($out -match 'F000\.BIN;1' -and $out -match 'F079\.BIN;1') 'Directory boundary listing failed'
        Run-Ods2 @('mount/image/medium=RL02 A:=disk.img ODS2TEST',
            'copy/from_files-11/binary A:[MANY.DEEP]F079.BIN output.bin','dismount A:') | Out-Null
        Check-Bytes 'output.bin' $payload
    } elseif ($Case -eq 'records') {
        New-Volume
        foreach ($format in @('variable','stream','streamlf','streamcr')) {
            Run-Ods2 @('mount/image/write/medium=RK05 A:=disk.img ODS2TEST',
                "copy/to_files-11/ascii/record_format=$format input.txt A:[000000]TEXT.TXT",
                "copy/from_files-11/ascii A:[000000]TEXT.TXT $format.txt",'dismount A:') | Out-Null
            $expected = switch ($format) {
                'variable' { [Text.Encoding]::ASCII.GetBytes('alphabetalast') }
                'streamcr' { [Text.Encoding]::ASCII.GetBytes("alpha`rbeta`rlast`r") }
                default { $ascii }
            }
            Check-Bytes "$format.txt" $expected
        }
    } elseif ($Case -eq 'snapshot') {
        New-Volume 'parent.vhd' 'RM02'
        $hash = (Get-FileHash -LiteralPath (Join-Path $work 'parent.vhd')).Hash
        Run-Ods2 @('mount/image/medium=RM02/snapshots_of=parent.vhd A:=child.vhd',
            'copy/from_files-11/binary A:[000000]PAYLOAD.BIN inherited.bin',
            'copy/to_files-11/ascii/record_format=streamlf input.txt A:[000000]CHILD.TXT','dismount A:') | Out-Null
        Check-Bytes 'inherited.bin' $payload
        Run-Ods2 @('mount/image/medium=RM02 A:=child.vhd ODS2TEST',
            'copy/from_files-11/ascii A:[000000]CHILD.TXT child.txt','dismount A:') | Out-Null
        Check-Bytes 'child.txt' $ascii
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'parent.vhd')).Hash -eq $hash) 'Snapshot modified parent'
        $childHash = (Get-FileHash -LiteralPath (Join-Path $work 'child.vhd')).Hash
        Run-Ods2 @('mount/image/medium=RM02/snapshots_of=parent.vhd A:=child.vhd') 1 'already exists' | Out-Null
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'child.vhd')).Hash -eq $childHash) 'Refused snapshot overwrite changed child'
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'parent.vhd')).Hash -eq $hash) 'Refused snapshot overwrite changed parent'
    } elseif ($Case -eq 'errors') {
        Run-Ods2 @('invalid_command') 1 'unknown|unrecognized|unrecognised' | Out-Null
        Run-Ods2 @('mount/image/medium=RK05 absent.img') 1 'not found|cannot find|No such' | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $work 'bad.img'), [byte[]]::new(16384))
        Run-Ods2 @('mount/image/medium=RK05 bad.img') 1 'home block|not.*volume|format|non-existent LBN' | Out-Null
        New-Volume
        $hash = (Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash
        Run-Ods2 @('initialize/image/noconfirm/medium=RK05 disk.img OTHER') 1 'exists|duplicate' | Out-Null
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash -eq $hash) 'Refused overwrite changed image'
        Run-Ods2 @('mount/image/medium=RK05 A:=disk.img WRONG') 1 "contains volume 'ODS2TEST\s*', 'WRONG\s*' expected" | Out-Null
        Run-Ods2 @('mount/image/medium=RK05 A:=disk.img LABELTOOLONG123') 1 'label' | Out-Null
    } elseif ($Case -eq 'binary-boundaries') {
        New-Volume
        foreach ($length in @(1,511,512,513,32769)) {
            $input = [byte[]]::new($length)
            for ($i=0; $i -lt $length; $i++) { $input[$i] = ($i*73+19) % 256 }
            [IO.File]::WriteAllBytes((Join-Path $work 'boundary.bin'), $input)
            $expected = [byte[]]::new([int]([Math]::Ceiling($length / 512.0)*512))
            $input.CopyTo($expected,0)
            Run-Ods2 @('mount/image/write/medium=RK05 A:=disk.img ODS2TEST',
                "copy/to_files-11/binary/record_format=undefined boundary.bin A:[000000]B$length.BIN",
                'dismount A:') | Out-Null
            Run-Ods2 @('mount/image/medium=RK05 A:=disk.img ODS2TEST',
                "copy/from_files-11/binary A:[000000]B$length.BIN output$length.bin",'dismount A:') | Out-Null
            Check-Bytes "output$length.bin" $expected
        }
    } elseif ($Case -eq 'vhd-interoperability') {
        $qemu = 'C:\Program Files\qemu\qemu-img.exe'
        Assert-True (Test-Path -LiteralPath $qemu) 'Installed qemu-img required for this case'
        $receipt.referenceExecutable = $qemu
        $receipt.referenceSha256 = (Get-FileHash -LiteralPath $qemu).Hash
        $receipt.referenceVersion = (Run-Program $qemu @('--version')).Trim()
        New-Volume 'disk.vhd' 'RM02'
        $info = Run-Program $qemu @('info','--output=json','-f','vpc','disk.vhd')
        $parsed = $info | ConvertFrom-Json
        Assert-True ($parsed.format -eq 'vpc' -and $parsed.'virtual-size' -ge 67420160) 'VHD size/format rejected by qemu-img'
        Run-Program $qemu @('convert','-f','vpc','-O','raw','disk.vhd','converted.img') | Out-Null
        Run-Ods2 @('mount/image/medium=RM02 A:=converted.img ODS2TEST',
            'copy/from_files-11/binary A:[000000]PAYLOAD.BIN decoded.bin','dismount A:') | Out-Null
        Check-Bytes 'decoded.bin' $payload
        Run-Program $qemu @('convert','-f','raw','-O','vpc','-o','subformat=dynamic','converted.img','qemu.vhd') | Out-Null
        Run-Ods2 @('mount/image/medium=RM02 A:=qemu.vhd ODS2TEST',
            'copy/from_files-11/binary A:[000000]PAYLOAD.BIN encoded.bin','dismount A:') | Out-Null
        Check-Bytes 'encoded.bin' $payload
    } elseif ($Case -eq 'generators') {
        Run-Program (Join-Path $bin 'genmsg.exe') @('-q','messages.mdf') | Out-Null
        Check-Bytes 'messages.mdf' ([IO.File]::ReadAllBytes((Join-Path $bin 'ods2_en_us.mdf')))
        $source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\en_us.hlp'))
        Run-Program (Join-Path $bin 'makehelp.exe') @('-q',$source,'help.hlb') | Out-Null
        Check-Bytes 'help.hlb' ([IO.File]::ReadAllBytes((Join-Path $bin 'ods2_en_us.hlb')))
        Run-Ods2 @('set help_file help.hlb','help copy','set message messages.mdf','show message 1') | Out-Null
        Run-Program (Join-Path $bin 'genmsg.exe') @('-z') '' 1 'Unknown option' | Out-Null
        Run-Program (Join-Path $bin 'makehelp.exe') @('-z') '' 1 'Unknown option' | Out-Null
    } else { throw "Unknown case: $Case" }
    $receipt.passed = $true
} catch {
    $receipt.error = $_.ToString()
    Write-Host $receipt.error
} finally {
    # Every child has exited before entering this cleanup. Resolve the exact
    # owned directory and check the boundary before any recursive removal.
    if (Test-Path -LiteralPath $work) {
        $resolved = (Resolve-Path -LiteralPath $work).Path
        if (-not $resolved.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the required G: test root'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    $receipt.cleanupVerified = -not (Test-Path -LiteralPath $work)
    $receipt.completedUtc = [DateTime]::UtcNow.ToString('o')
    $receipt.processInvocations = $script:sequence
    $receipt | ConvertTo-Json | Set-Content (Join-Path $evidence 'receipt.json')
}
if (-not $receipt.passed -or -not $receipt.cleanupVerified) { exit 1 }
Write-Host "PASS $Case ($script:sequence serial processes); cleanup verified"
