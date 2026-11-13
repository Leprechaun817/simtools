#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][string]$EvidenceRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$root = 'G:\SimtoolsFlxTests'
$id = $Case + '-' + [guid]::NewGuid().ToString('N')
$work = [IO.Path]::GetFullPath((Join-Path $root $id))
$evidence = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $id
if (-not $work.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test root' }
New-Item -ItemType Directory -Force -Path $work,$evidence | Out-Null
$script:sequence = 0
$receipt = [ordered]@{case=$Case; executable=$Executable;
    executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    startedUtc=[DateTime]::UtcNow.ToString('o'); mediaDirectory=$work;
    passed=$false; cleanupVerified=$false; error=$null}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Flx([string[]]$Arguments, [string]$InputText='', [int]$ExitCode=0, [string]$ExpectedError='') {
    $script:sequence++
    $stem = '{0:D3}' -f $script:sequence
    @{arguments=$Arguments; stdin=$InputText} | ConvertTo-Json | Set-Content (Join-Path $evidence "$stem.input.json")
    $psi = [Diagnostics.ProcessStartInfo]::new($Executable)
    $psi.WorkingDirectory=$work; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.Environment['PATH']="$env:SystemRoot\System32;$env:SystemRoot"
    foreach ($name in @('HOME','FLXHISTFILE','FLXHISTFILESIZE','FLXHISTSIZE','RSTSDISK','RSTSDISKSIZE')) {
        $psi.Environment.Remove($name) | Out-Null
    }
    foreach ($argument in $Arguments) { $psi.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$psi; $started=$false
    try {
        $started=$process.Start()
        $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText); $process.StandardInput.Close()
        $timedOut=-not $process.WaitForExit(30000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $out=$outTask.GetAwaiter().GetResult(); $err=$errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stdout.txt"),$out)
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stderr.txt"),$err)
        @{exitCode=$process.ExitCode; timedOut=$timedOut} | ConvertTo-Json | Set-Content (Join-Path $evidence "$stem.result.json")
        Assert-True (-not $timedOut) "Process timed out ($stem)"
        Assert-True ($process.ExitCode -eq $ExitCode) "Exit $($process.ExitCode), expected $ExitCode ($stem): $out $err"
        if ($ExpectedError) { Assert-True (($out+$err) -match $ExpectedError) "Missing '$ExpectedError' ($stem): $out $err" }
        else {
            Assert-True (-not $err) "Unexpected stderr ($stem): $err"
            Assert-True ($out -notmatch '(?im)(Invalid |Internal error|Corrupt |Failure copying|Error opening|No room |No files matching|not properly dismounted|does not appear|Unexpected |Can.t |could not)') "Unexpected diagnostic ($stem): $out"
        }
        return $out+$err
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Disk([string[]]$Arguments, [string]$ExpectedError='', [int]$ExitCode=0, [string]$InputText='') {
    Run-Flx (@('-disk','disk.img')+$Arguments) $InputText $ExitCode $ExpectedError
}
function Check-Bytes([string]$Name, [byte[]]$Expected) {
    $path=Join-Path $work $Name
    $actual=[IO.File]::ReadAllBytes($path)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Expected))
    $actualHash=(Get-FileHash -LiteralPath $path).Hash
    @{name=$Name;expectedLength=$Expected.Length;actualLength=$actual.Length;
        expectedSha256=$expectedHash;actualSha256=$actualHash} | ConvertTo-Json |
        Set-Content (Join-Path $evidence (($Name -replace '[/\\]','_')+'.bytes.json'))
    Assert-True ($actual.Length -eq $Expected.Length -and $actualHash -eq $expectedHash) "Byte mismatch for $Name ($($actual.Length) vs $($Expected.Length))"
}
function New-Volume([string]$Revision='1.2', [string]$Medium='rk05') {
    Disk @('initialize','FLXTST',$Revision,'-create',$Medium) | Out-Null
    $out=Disk @('identify')
    Assert-True ($out -match ('Revision level:\s+'+[regex]::Escape($Revision))) 'Wrong RDS revision'
    Assert-True ($out -match 'FLXTST') 'Wrong volume label'
    Disk @('mkdir','[1,2]') | Out-Null
}
function Put-Payload { Disk @('put','-binary','input.bin','[1,2]DATA.BIN') | Out-Null }
try {
    $payload=[byte[]]::new(8192)
    for ($i=0;$i -lt $payload.Length;$i++) { $payload[$i]=$i%256 }
    $ascii=[Text.Encoding]::ASCII.GetBytes("alpha`r`nbeta`r`nlast`r`n")
    [IO.File]::WriteAllBytes((Join-Path $work 'input.bin'),$payload)
    [IO.File]::WriteAllBytes((Join-Path $work 'input.txt'),$ascii)
    [IO.File]::WriteAllBytes((Join-Path $work 'empty.bin'),[byte[]]@())
    if ($Case -eq 'commands') {
        $out=Run-Flx @() "`r`nexit`r`n"
        Assert-True ($out -match 'FLX v2.6') 'Version banner missing'
        Run-Flx @('nonsense') '' 1 'Unrecognized command' | Out-Null
        Run-Flx @('d') '' 1 'Ambiguous command' | Out-Null
        Run-Flx @('list','-bogus') '' 1 'Unrecognized switch' | Out-Null
        Run-Flx @('list','-disk') '' 1 'Missing argument' | Out-Null
        Run-Flx @('list','-c') '' 1 'Ambiguous switch' | Out-Null
        Run-Flx @() (' '*4096+"exit`n") | Out-Null
        Run-Flx @() '' | Out-Null
    } elseif ($Case -eq 'interactive') {
        $out=Run-Flx @('disk','disk.img') ("initialize FLXTST -create rk05`nmkdir [1,2]`nput -binary input.bin [1,2]DATA.BIN`nget -binary [1,2]DATA.BIN output.bin`nidentify`nexit`n")
        Assert-True ($out -match 'FLXTST') 'Interactive commands did not finish'
        Check-Bytes 'output.bin' $payload
        $out=Run-Flx @('disk','disk.img') "identify -disk absent.img`nidentify`nexit`n" 0 'Error opening'
        Assert-True ($out -match 'FLXTST') 'Interactive abort did not recover'
        Disk @('delete','-query','[1,2]DATA.BIN') '' 0 '' | Out-Null
        Disk @('get','-binary','[1,2]DATA.BIN','query.bin') | Out-Null
        Check-Bytes 'query.bin' $payload
        $spaced=Join-Path $work 'space dir'
        New-Item -ItemType Directory -Path $spaced | Out-Null
        Move-Item -LiteralPath (Join-Path $work 'disk.img') -Destination (Join-Path $spaced 'disk image.img')
        Run-Flx @('-disk',(Join-Path $spaced 'disk image.img'),'get','-binary','[1,2]DATA.BIN',(Join-Path $spaced 'output data.bin')) | Out-Null
        Check-Bytes 'space dir/output data.bin' $payload
    } elseif ($Case -match '^rds(0|11|12)-(rk05|rl02|rm02)$') {
        $revision=@{'0'='0.0';'11'='1.1';'12'='1.2'}[$Matches[1]]
        $medium=$Matches[2]
        New-Volume $revision $medium
        $blocks=@{rk05=4800;rl02=20480;rm02=131680}[$medium]
        Assert-True ((Get-Item -LiteralPath (Join-Path $work 'disk.img')).Length -eq $blocks*512) 'Wrong container size'
        Put-Payload
        Disk @('put','-ascii','input.txt','[1,2]TEXT.TXT') | Out-Null
        Disk @('put','-binary','empty.bin','[1,2]EMPTY.BIN') | Out-Null
        Disk @('get','-binary','[1,2]DATA.BIN','output.bin') | Out-Null
        Disk @('get','-ascii','[1,2]TEXT.TXT','output.txt') | Out-Null
        Disk @('get','-binary','[1,2]EMPTY.BIN','empty.out') | Out-Null
        Check-Bytes 'output.bin' $payload; Check-Bytes 'output.txt' $ascii; Check-Bytes 'empty.out' ([byte[]]@())
        $out=Disk @('list','-full','[1,2]*.*')
        Assert-True ($out -match 'data\s*\.bin' -and $out -match 'text\s*\.txt') 'Files absent in full listing'
        Disk @('rename','[1,2]DATA.BIN','RENAM.BIN') | Out-Null
        Disk @('get','-binary','[1,2]RENAM.BIN','renamed.bin') | Out-Null
        Check-Bytes 'renamed.bin' $payload
        Disk @('delete','[1,2]RENAM.BIN') | Out-Null
        Disk @('list','[1,2]RENAM.BIN') 'No files matching' | Out-Null
        if ($revision -eq '0.0') {
            $hash=(Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash
            Disk @('clean','-protect') 'RDS 0.0 clean/rebuild is not implemented' 1 | Out-Null
            Disk @('clean') 'RDS 0.0 clean/rebuild is not implemented' 1 | Out-Null
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash -eq $hash) 'Unsupported RDS0 clean changed image'
        } else { Disk @('clean','-protect','-verbose') | Out-Null }
    } elseif ($Case -eq 'boundaries') {
        New-Volume
        foreach ($length in @(1,511,512,513,32769,65536)) {
            $bytes=[byte[]]::new($length)
            for ($i=0;$i -lt $length;$i++) { $bytes[$i]=($i*17+3)%256 }
            [IO.File]::WriteAllBytes((Join-Path $work 'bound.bin'),$bytes)
            Disk @('put','-binary','bound.bin','[1,2]BOUND.BIN') | Out-Null
            Disk @('get','-binary','[1,2]BOUND.BIN',"b$length.out") | Out-Null
            $expected=[byte[]]::new([int]([Math]::Ceiling($length/512.0)*512))
            [Array]::Copy($bytes,$expected,$length)
            Check-Bytes "b$length.out" $expected
        }
    } elseif ($Case -eq 'records') {
        New-Volume
        Disk @('put','-ascii','input.txt','[1,2]TEXT.TXT') | Out-Null
        Disk @('get','[1,2]TEXT.TXT','auto.txt') | Out-Null
        Check-Bytes 'auto.txt' $ascii
        Disk @('put','-binary','-rs','input.txt','[1,2]STREAM.TXT') | Out-Null
        Disk @('get','-ascii','[1,2]STREAM.TXT','stream.txt') | Out-Null
        Check-Bytes 'stream.txt' $ascii
        Disk @('put','-binary','-rf','512','input.bin','[1,2]FIXED.BIN') | Out-Null
        Disk @('get','[1,2]FIXED.BIN','fixed.bin') | Out-Null
        Check-Bytes 'fixed.bin' $payload
        $variable=[byte[]]@(5,0,97,108,112,104,97,0,4,0,98,101,116,97)
        [IO.File]::WriteAllBytes((Join-Path $work 'var.bin'),$variable)
        Disk @('put','-binary','-rv','var.bin','[1,2]VAR.TXT') | Out-Null
        Disk @('get','-ascii','[1,2]VAR.TXT','var.txt') | Out-Null
        Check-Bytes 'var.txt' ([Text.Encoding]::ASCII.GetBytes("alpha`r`nbeta`r`n"))
        [IO.File]::WriteAllBytes((Join-Path $work 'four.bin'),[Text.Encoding]::ASCII.GetBytes('abcdefgh'))
        Disk @('put','-binary','-rf','4','four.bin','[1,2]FOUR.TXT') | Out-Null
        Disk @('get','-ascii','[1,2]FOUR.TXT','four.txt') | Out-Null
        Check-Bytes 'four.txt' ([Text.Encoding]::ASCII.GetBytes("abcd`r`nefgh`r`n"))
    } elseif ($Case -eq 'directories') {
        New-Volume
        Disk @('mkdir','-user','[2,3]') | Out-Null
        $argsList=@('put','-binary')
        for ($i=0;$i -lt 40;$i++) {
            $name='f{0:D3}.bin' -f $i
            [IO.File]::WriteAllBytes((Join-Path $work $name),$payload)
            $argsList+=$name
        }
        Disk ($argsList+@('[2,3]*.*')) | Out-Null
        $out=Disk @('list','-1column','[2,3]*.*')
        Assert-True ($out -match 'f000' -and $out -match 'f039') 'Directory extension lost files'
        New-Item -ItemType Directory -Path (Join-Path $work 'tree') | Out-Null
        Disk @('get','-binary','-tree','[2,3]*.*','tree') | Out-Null
        Check-Bytes 'tree/002003/f000.bin' $payload; Check-Bytes 'tree/002003/f039.bin' $payload
        Disk @('get','-binary','[2,3]f00?.bin','concat.bin') | Out-Null
        $expected=[byte[]]::new(10*$payload.Length)
        for ($i=0;$i -lt 10;$i++) { [Array]::Copy($payload,0,$expected,$i*$payload.Length,$payload.Length) }
        Check-Bytes 'concat.bin' $expected
        Disk @('delete','[2,3]*.*') | Out-Null
        Disk @('rmdir','[2,3]') | Out-Null
    } elseif ($Case -eq 'metadata') {
        New-Volume; Put-Payload
        Disk @('rts','[1,2]DATA.BIN','RT11') | Out-Null
        Disk @('protect','[1,2]DATA.BIN<40>') | Out-Null
        $out=Disk @('list','-full','[1,2]DATA.BIN')
        Assert-True ($out -match 'rt11' -and $out -match '<\s*40>') 'RTS/protection not persisted'
        Disk @('protect','-protect','[1,2]DATA.BIN') | Out-Null
        Disk @('delete','[1,2]DATA.BIN') 'protected|no.delete' | Out-Null
        Disk @('get','-binary','[1,2]DATA.BIN','protected.bin') | Out-Null
        Check-Bytes 'protected.bin' $payload
        Disk @('protect','-unprotect','[1,2]DATA.BIN') | Out-Null
        Disk @('delete','[1,2]DATA.BIN') | Out-Null
    } elseif ($Case -eq 'readonly') {
        New-Volume; Put-Payload
        $path=Join-Path $work 'disk.img'
        $bytes=[IO.File]::ReadAllBytes($path); $bytes[523]=$bytes[523] -bor 0x10
        [IO.File]::WriteAllBytes($path,$bytes)
        $hash=(Get-FileHash -LiteralPath $path).Hash
        Disk @('put','-binary','input.bin','[1,2]FAIL.BIN') 'Disk is read-only' 1 | Out-Null
        Disk @('get','-binary','[1,2]DATA.BIN','readonly.bin') | Out-Null
        Check-Bytes 'readonly.bin' $payload
        Assert-True ((Get-FileHash -LiteralPath $path).Hash -eq $hash) 'Readonly operations modified image'
        Disk @('put','-Write','-binary','input.bin','[1,2]ALLOW.BIN') | Out-Null
        Disk @('get','-binary','[1,2]ALLOW.BIN','allowed.bin') | Out-Null
        Check-Bytes 'allowed.bin' $payload
    } elseif ($Case -eq 'clean-compress') {
        New-Volume; Put-Payload
        $hash=(Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash
        Disk @('clean','-protect','-verbose') | Out-Null
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash -eq $hash) 'Read-only clean modified image'
        Disk @('clean','-verbose') | Out-Null
        Disk @('compress') | Out-Null
        Disk @('allocation','-brief') | Out-Null
        Disk @('get','-binary','[1,2]DATA.BIN','clean.bin') | Out-Null
        Check-Bytes 'clean.bin' $payload
    } elseif ($Case -eq 'errors') {
        Disk @('identify') 'Error opening' 1 | Out-Null
        Disk @('initialize','FLXTST','-create','799') 'Invalid container size' | Out-Null
        Disk @('initialize','FLXTST','-create','rk05','-clustersize','3') 'Invalid clustersize' | Out-Null
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $work 'disk.img'))) 'Invalid initialization created media'
        Disk @('hook','zz') 'Unknown disk name' | Out-Null
        New-Volume
        foreach ($badSize in @('0','-1','65536','abc')) {
            Disk @('put','-binary','-rf',$badSize,'input.bin','[1,2]BAD.BIN') 'Invalid fixed record size' | Out-Null
        }
        $hash=(Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash
        Disk @('initialize','FLXTST','-create','rk05') 'already exists' | Out-Null
        Disk @('initialize','FLXTST') '' 0 "n`n" | Out-Null
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash -eq $hash) 'Refused initialization changed image'
        [IO.File]::WriteAllBytes((Join-Path $work 'short.img'),[byte[]]::new(10))
        Run-Flx @('-disk','short.img','identify') '' 1 'Block number out of range|I/O error' | Out-Null
    } else { throw "Unknown case $Case" }
    $receipt.passed=$true
} catch { $receipt.error=$_.ToString(); throw }
finally {
    try {
        $resolved=[IO.Path]::GetFullPath($work)
        if (-not $resolved.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing unsafe cleanup' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
        $receipt.cleanupVerified=-not (Test-Path -LiteralPath $resolved)
        if (-not $receipt.cleanupVerified) { throw 'Test media remains' }
    } finally {
        $receipt.processInvocations=$script:sequence
        $receipt.finishedUtc=[DateTime]::UtcNow.ToString('o')
        $receipt | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'receipt.json')
    }
}
Write-Output "PASS $Case; $script:sequence serial invocations; G: media removed"
