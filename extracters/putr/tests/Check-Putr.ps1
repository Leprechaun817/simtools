#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [string]$DosBox = 'D:\GitHub\dosbox-staging\dosbox.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root = 'G:\SimtoolsPutrTests'
$id = $Case + '-' + [guid]::NewGuid().ToString('N')
$work = [IO.Path]::GetFullPath((Join-Path $root $id))
$evidence = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $id
if (-not $work.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid G: case directory' }
New-Item -ItemType Directory -Path $work,$evidence -Force | Out-Null
$script:sequence = 0
$record = [ordered]@{case=$Case; executable=$Executable;
    executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    runnerSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Invoke-PutrDosBox.ps1')).Hash;
    startedUtc=[DateTime]::UtcNow.ToString('o'); mediaDirectory=$work;
    passed=$false; cleanupVerified=$false}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Write-Ascii([string]$Name, [string[]]$Lines) {
    [IO.File]::WriteAllText((Join-Path $work $Name), ($Lines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
}
function Run-Putr([string[]]$Commands, [string]$ExpectedError = '') {
    $script:sequence++
    $run = Join-Path $evidence ('{0:D3}-dos' -f $script:sequence)
    New-Item -ItemType Directory -Path $run | Out-Null
    Write-Ascii 'PUTR.INI' (@('set more off') + $Commands + @('quit'))
    Write-Ascii 'RUN.BAT' @('@echo off','CAPTURE.COM','if errorlevel 1 goto failed','echo CHILD-PASS > CHILD.OK','goto done',':failed','echo CHILD-FAIL > CHILD.BAD',':done')
    foreach($name in @('CHILD.OK','CHILD.BAD','PUTR.OUT')) {
        $path=Join-Path $work $name
        if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Copy-Item -LiteralPath (Join-Path $work 'PUTR.INI'),(Join-Path $work 'RUN.BAT') -Destination $run
    & (Join-Path $PSScriptRoot '..\scripts\Invoke-PutrDosBox.ps1') -WorkingDirectory $work -EvidenceDirectory $run -DosBox $DosBox
    $text = Get-Content -LiteralPath (Join-Path $work 'PUTR.OUT') -Raw
    [IO.File]::WriteAllText((Join-Path $run 'putr-output.txt'), $text)
    Assert-True (Test-Path -LiteralPath (Join-Path $work 'CHILD.OK')) 'DOS child failed'
    Assert-True ($text -match 'PUTR V2.01') 'PUTR version banner missing'
    if ($ExpectedError) { Assert-True ($text -match $ExpectedError) "Missing expected diagnostic: $text" }
    else { Assert-True ($text -notmatch '(?m)^\?|^[A-Z]+\?\s*$') "Unexpected PUTR diagnostic: $text" }
    return $text
}
function Run-Native([string]$Tool, [string[]]$Arguments, [string]$InputText = '') {
    $script:sequence++
    $stem = Join-Path $evidence ('{0:D3}-native' -f $script:sequence)
    $psi = [Diagnostics.ProcessStartInfo]::new($Tool)
    $psi.WorkingDirectory=$work; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.Environment['PATH']="$env:SystemRoot\System32;$env:SystemRoot"
    foreach ($name in @('HOME','RSTSDISK','RSTSDISKSIZE','FSioForceLocal','FSioDebugLog')) { $psi.Environment.Remove($name) | Out-Null }
    foreach ($arg in $Arguments) { $psi.ArgumentList.Add($arg) }
    @{executable=$Tool;sha256=(Get-FileHash -LiteralPath $Tool).Hash;arguments=$Arguments;stdin=$InputText} |
        ConvertTo-Json | Set-Content -LiteralPath ($stem+'.input.json')
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$psi; $started=$false
    try {
        $started=$process.Start()
        $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText); $process.StandardInput.Close()
        $timedOut=-not $process.WaitForExit(30000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $out=$outTask.GetAwaiter().GetResult(); $err=$errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($stem+'.stdout.txt',$out); [IO.File]::WriteAllText($stem+'.stderr.txt',$err)
        @{exitCode=$process.ExitCode;timedOut=$timedOut} | ConvertTo-Json | Set-Content -LiteralPath ($stem+'.result.json')
        Assert-True (-not $timedOut -and $process.ExitCode -eq 0 -and -not $err) "Native tool failed: $out $err"
        Assert-True ($out -notmatch '(?im)(Error opening|Failure copying|No files matching|not properly dismounted|does not appear|Invalid |Internal error|Corrupt )') "Native diagnostic: $out"
        return $out
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Check-Bytes([string]$Name, [byte[]]$Expected, [int]$Block = 1) {
    $padded = [byte[]]::new([int]([Math]::Ceiling($Expected.Length / [double]$Block) * $Block))
    $Expected.CopyTo($padded,0)
    $path=Join-Path $work $Name
    $actual=[IO.File]::ReadAllBytes($path)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($padded))
    $actualHash=(Get-FileHash -LiteralPath $path).Hash
    @{name=$Name;expectedLength=$padded.Length;actualLength=$actual.Length;expectedSha256=$expectedHash;actualSha256=$actualHash;
      actualPrefixHex=[Convert]::ToHexString($actual,0,[Math]::Min(64,$actual.Length));
      actualSuffixHex=[Convert]::ToHexString($actual,[Math]::Max(0,$actual.Length-64),[Math]::Min(64,$actual.Length))} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence ($Name+'.comparison.json'))
    Assert-True ($padded.Length -eq $actual.Length -and $expectedHash -eq $actualHash) "$Name bytes differ (expected $($padded.Length), actual $($actual.Length))"
}
function Format-Rt11([string]$Name='DISK.DSK') { @("format $Name /rk05 /rt11",'y','PUTRTEST','SIMTOOLS') }
function Format-Os8([string]$Name='DISK.DSK', [string]$Medium='rk05', [string]$Format='os8') {
    @("format $Name /$Medium /$Format",'y','1','n')
}
function Inspect-DosBatch {
    $data=[IO.File]::ReadAllBytes((Join-Path $work 'DISK.DSK'))
    $mfd=[BitConverter]::ToUInt16($data,512)
    $ufd=0; $entryWords=0
    for($offset=$mfd*512+2;$offset -lt ($mfd+1)*512-7;$offset+=8) {
        if([BitConverter]::ToUInt16($data,$offset) -eq 0x0101) {
            $ufd=[BitConverter]::ToUInt16($data,$offset+2)
            $entryWords=[BitConverter]::ToUInt16($data,$offset+4)
            break
        }
    }
    Assert-True ($ufd -gt 0 -and $entryWords -eq 9) 'DOS/BATCH fixture directory missing'
    $entries=[Collections.Generic.List[object]]::new()
    $found=$false
    for($offset=$ufd*512+2;$offset -le ($ufd+1)*512-18;$offset+=18) {
        $fields=@(for($j=0;$j -lt 9;$j++){[BitConverter]::ToUInt16($data,$offset+$j*2)})
        if($fields[0] -eq 0 -and $fields[1] -eq 0) { continue }
        $entries.Add(@{offset=$offset;words=$fields;nextFreeByte=$fields[4];startBlock=$fields[5];blocks=$fields[6];lastBlock=$fields[7]})
        # RAD50 encodings of BACK.BIN, independent of PUTR's reader.
        if($fields[0] -eq 3243 -and $fields[1] -eq 17600 -and $fields[2] -eq 3574) {
            $found=$true; $block=[int]$fields[5]
            $actual=[Collections.Generic.List[byte]]::new()
            $visited=[Collections.Generic.HashSet[int]]::new()
            for($j=0;$j -lt $fields[6];$j++) {
                Assert-True ($block -gt 0 -and ($block+1)*512 -le $data.Length -and $visited.Add($block)) 'Invalid DOS/BATCH block chain'
                $actual.AddRange([byte[]]$data[($block*512+2)..($block*512+511)])
                if($j -eq $fields[6]-1) { Assert-True ($block -eq $fields[7]) 'Last-block metadata disagrees' }
                $block=[BitConverter]::ToUInt16($data,$block*512)
            }
            Assert-True ($block -eq 0) 'Unterminated DOS/BATCH block chain'
            [IO.File]::WriteAllBytes((Join-Path $work 'RAW.BIN'),$actual.ToArray())
        }
    }
    $entries | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'dosbatch-directory.json')
    Assert-True $found 'Independent DOS/BATCH directory scan did not find BACK.BIN'
}
try {
    Copy-Item -LiteralPath $Executable -Destination (Join-Path $work 'PUTR.COM')
    & 'C:\gcc-winlibs-x86_64\bin\nasm.exe' -f bin (Join-Path $PSScriptRoot 'capture.asm') -o (Join-Path $work 'CAPTURE.COM')
    if($LASTEXITCODE -ne 0) { throw 'DOS output-capture helper assembly failed' }
    $record.captureSourceSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'capture.asm')).Hash
    $record.captureExecutableSha256=(Get-FileHash -LiteralPath (Join-Path $work 'CAPTURE.COM')).Hash
    $record.captureAssemblerSha256=(Get-FileHash -LiteralPath 'C:\gcc-winlibs-x86_64\bin\nasm.exe').Hash
    $payload=[byte[]]::new(1024)
    for($i=0;$i -lt $payload.Length;$i++) { $payload[$i]=($i*37+11)%256 }
    $words=[byte[]]$payload.Clone()
    for($i=1;$i -lt $words.Length;$i+=2) { $words[$i]=$words[$i] -band 15 }
    $ascii=[Text.Encoding]::ASCII.GetBytes("alpha`r`nbeta`r`nlast`r`n")
    [IO.File]::WriteAllBytes((Join-Path $work 'INPUT.BIN'),$payload)
    [IO.File]::WriteAllBytes((Join-Path $work 'WORDS.BN'),$words)
    [IO.File]::WriteAllBytes((Join-Path $work 'INPUT.TXT'),$ascii)
    $fsio=Join-Path $repo 'converters\fsio\fsio.exe'
    $flx=Join-Path $repo 'extracters\rstsflx\flx.exe'
    switch -Regex ($Case) {
        '^commands$' {
            Write-Ascii 'NEXT.CMD' @('dir c:INPUT.*','quit')
            $out=Run-Putr @('set copy binary','show c:','@ NEXT')
            Assert-True ($out -match 'INPUT' -and $out -match 'C: DOS') 'Command or indirect-file output missing'
            Run-Putr @('nonsense') 'NONSENSE\?' | Out-Null
            break
        }
        '^(rt11|os8|putr-tape)$' {
            if($Case -eq 'rt11') {
                $create=Format-Rt11; $mount='mount x: DISK.DSK /rk05 /rt11'; $name='DATA.BIN'; $textName='TEXT.TXT'; $expected=$payload; $size=2457600
            } else {
                $medium=if($Case -eq 'os8'){'rk05'}else{'tu56'}
                $format=if($Case -eq 'os8'){'os8'}else{'putr'}
                $create=Format-Os8 'DISK.DSK' $medium $format
                $mount="mount x: DISK.DSK /$medium /$format"; $name='DATA.BN'; $textName='TEXT.TX'; $expected=$words
                $size=if($Case -eq 'os8'){3276800}else{380292}
                if($Case -eq 'putr-tape') { $name='DATA.BIN'; $textName='TEXT.ASC' }
            }
            $out=Run-Putr ($create+@($mount,'show x:',"copy/b INPUT.BIN x:$name","copy INPUT.TXT x:$textName",'dir x: /full',"copy/b x:$name OUTPUT.BIN","copy x:$textName OUTPUT.TXT",'dismount x:'))
            Check-Bytes 'OUTPUT.BIN' $expected
            # PUTR.SAV tape text retains a trailing DOS Ctrl-Z, also observed
            # with the supplied upstream COM; OS/8 and RT-11 do not here.
            $expectedText=if($Case -eq 'putr-tape'){[byte[]]($ascii + 26)}else{$ascii}
            Check-Bytes 'OUTPUT.TXT' $expectedText
            Assert-True ((Get-Item -LiteralPath (Join-Path $work 'DISK.DSK')).Length -eq $size) 'Wrong image size'
            $out=Run-Putr @($mount,"delete/noquery x:$name",'dir x:','dismount x:')
            $listing=($out -split 'Directory of')[-1]
            Assert-True ($listing -match 'TEXT' -and $listing -notmatch 'DATA\s*\.') 'Delete or retained text listing failed'
            break
        }
        '^cross-filesystem$' {
            Run-Putr ((Format-Rt11 'RT.DSK')+(Format-Os8 'OS.DSK')+@('mount x: RT.DSK /rk05 /rt11','mount y: OS.DSK /rk05 /os8','copy/b WORDS.BN x:DATA.BIN','copy/b x:DATA.BIN y:DATA.BN','copy/b y:DATA.BN x:BACK.BIN','copy/b x:BACK.BIN OUTPUT.BIN')) | Out-Null
            Check-Bytes 'OUTPUT.BIN' $words
            break
        }
        '^boundaries$' {
            $commands=@(Format-Rt11)+@('mount x: DISK.DSK /rk05 /rt11')
            foreach($length in @(0,1,511,512,513,32769,65536)) {
                $bytes=[byte[]]::new($length)
                for($i=0;$i -lt $length;$i++) { $bytes[$i]=($i*17+3)%256 }
                [IO.File]::WriteAllBytes((Join-Path $work "I$length.BIN"),$bytes)
                $commands+=@("copy/b I$length.BIN x:B$length.BIN","copy/b x:B$length.BIN O$length.BIN")
            }
            Run-Putr $commands | Out-Null
            foreach($length in @(0,1,511,512,513,32769,65536)) { Check-Bytes "O$length.BIN" ([IO.File]::ReadAllBytes((Join-Path $work "I$length.BIN"))) 512 }
            break
        }
        '^readonly-errors$' {
            Run-Putr ((Format-Rt11)+@('mount x: DISK.DSK /rk05 /rt11','copy/b INPUT.BIN x:DATA.BIN')) | Out-Null
            $before=(Get-FileHash -LiteralPath (Join-Path $work 'DISK.DSK')).Hash
            Run-Putr @('mount x: DISK.DSK /rk05 /rt11 /ronly','copy/b INPUT.BIN x:BAD.BIN','delete/noquery x:DATA.BIN','copy/b x:DATA.BIN OUTPUT.BIN') 'read.only|write.protect' | Out-Null
            Check-Bytes 'OUTPUT.BIN' $payload
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'DISK.DSK')).Hash -eq $before) 'Read-only operations modified image'
            Run-Putr @('mount x: ABSENT.DSK /rk05 /rt11','initialize DISK.DSK /rk05 /rsts') '(?s)\?File not found.*\?Don.t know how to init that filesystem' | Out-Null
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $work 'DISK.DSK')).Hash -eq $before) 'Unsupported initializer modified image'
            break
        }
        '^rt11-independent$' {
            Run-Putr ((Format-Rt11)+@('mount x: DISK.DSK /rk05 /rt11','copy/b INPUT.BIN x:DATA.BIN')) | Out-Null
            Run-Native $fsio @('-q') "mount dd DISK.DSK rt11`ncopy dd:DATA.BIN FSIO.BIN`ncopy INPUT.BIN dd:BACK.BIN`numount dd`n" | Out-Null
            Check-Bytes 'FSIO.BIN' $payload
            Run-Putr @('mount x: DISK.DSK /rk05 /rt11','copy/b x:BACK.BIN OUTPUT.BIN') | Out-Null
            Check-Bytes 'OUTPUT.BIN' $payload
            break
        }
        '^dosbatch(?:-fsio-interop)?$' {
            # Linked DOS/BATCH blocks expose 510 payload bytes per block.
            # Use full blocks: PUTR binary reads include the final block's slack.
            $payload=[byte[]]::new(1530)
            for($i=0;$i -lt $payload.Length;$i++) { $payload[$i]=($i*37+11)%256 }
            [IO.File]::WriteAllBytes((Join-Path $work 'INPUT.BIN'),$payload)
            Run-Native $fsio @('-q') "newfs DISK.DSK dos11`nmount dd DISK.DSK dos11`nset dd: ufd [1,1]`ncopy INPUT.BIN dd:DATA.BIN`numount dd`n" | Out-Null
            Run-Putr @('mount x: DISK.DSK /rk05 /dosbatch','copy/b x:DATA.BIN[1,1] OUTPUT.BIN','copy/b INPUT.BIN x:BACK.BIN[1,1]') | Out-Null
            Check-Bytes 'OUTPUT.BIN' $payload
            Inspect-DosBatch
            Check-Bytes 'RAW.BIN' $payload
            if($Case -eq 'dosbatch-fsio-interop') {
                # Separate diagnostic reproducer; this lane is not qualified.
                Run-Native $fsio @('-q') "mount dd DISK.DSK dos11`nset dd: ufd [1,1]`ncopy dd:BACK.BIN FSIO.BIN`numount dd`n" | Out-Null
                Check-Bytes 'FSIO.BIN' $payload
            } else {
                Run-Putr @('mount x: DISK.DSK /rk05 /dosbatch','copy/b x:BACK.BIN BACK.BIN') | Out-Null
                Check-Bytes 'BACK.BIN' $payload
                $record.dosbatchFsioWriteInteropQualified=$false
            }
            break
        }
        '^rsts(0|11|12)$' {
            $revision=@{'rsts0'='0.0';'rsts11'='1.1';'rsts12'='1.2'}[$Case]
            Run-Native $flx @('-disk','DISK.DSK','initialize','PUTRTEST',$revision,'-create','rk05') | Out-Null
            Run-Native $flx @('-disk','DISK.DSK','mkdir','[1,2]') | Out-Null
            Run-Native $flx @('-disk','DISK.DSK','put','-binary','INPUT.BIN','[1,2]DATA.BIN') | Out-Null
            Run-Putr @('mount x: DISK.DSK /rk05 /rsts','show x:','copy/b x:[1,2]DATA.BIN OUTPUT.BIN','copy/b INPUT.BIN x:[1,2]BACK.BIN') | Out-Null
            Check-Bytes 'OUTPUT.BIN' $payload
            Run-Native $flx @('-disk','DISK.DSK','get','-binary','[1,2]BACK.BIN','FLX.BIN') | Out-Null
            Check-Bytes 'FLX.BIN' $payload
            break
        }
        default { throw "Unknown test case: $Case" }
    }
    $record.passed=$true
} catch {
    $record.error=$_.Exception.Message
    throw
} finally {
    try {
        if(Test-Path -LiteralPath $work) {
            $resolved=(Resolve-Path -LiteralPath $work).Path
            if($resolved -ne $work -or -not $resolved.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
        $record.cleanupVerified=-not(Test-Path -LiteralPath $work)
    } catch { $record.passed=$false; $record.cleanupError=$_.Exception.Message }
    $record.processInvocations=$script:sequence
    $record.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'receipt.json')
    if(-not $record.cleanupVerified) { throw "Test-media cleanup failed; see $evidence" }
}
Write-Output "$Case passed; $script:sequence serial processes; G: cleanup verified"
