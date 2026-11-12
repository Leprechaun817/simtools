#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Case,
    [Parameter(Mandatory)][string]$EvidenceRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$root = 'G:\SimtoolsFsioTests'
$id = $Case + '-' + [guid]::NewGuid().ToString('N')
$work = [IO.Path]::GetFullPath((Join-Path $root $id))
$evidence = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $id
if (-not $work.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Test directory escaped the required G: root'
}
New-Item -ItemType Directory -Force -Path $work,$evidence | Out-Null
$script:sequence = 0
$receipt = [ordered]@{ case=$Case; executable=$Executable;
    executableSha256=(Get-FileHash -LiteralPath $Executable).Hash;
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
    startedUtc=[DateTime]::UtcNow.ToString('o'); mediaDirectory=$work;
    passed=$false; cleanupVerified=$false; error=$null }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Run-Fsio([string[]]$Commands, [string]$ExpectedError = '',
                  [string[]]$Arguments = @('-q'), [int]$ExitCode = 0,
                  [switch]$Stdin, [switch]$NoCommandFile) {
    $script:sequence++
    $stem = '{0:D3}' -f $script:sequence
    $inputFile = Join-Path $evidence ($stem + '.commands.txt')
    $text = ($Commands -join "`n") + "`n"
    [IO.File]::WriteAllText($inputFile, $text)
    $psi = [Diagnostics.ProcessStartInfo]::new($Executable)
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.Environment['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $psi.Environment.Remove('FSioForceLocal') | Out-Null
    $psi.Environment.Remove('FSioDebugLog') | Out-Null
    foreach ($arg in $Arguments) { $psi.ArgumentList.Add($arg) }
    if (-not $Stdin -and -not $NoCommandFile) { $psi.ArgumentList.Add($inputFile) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $started = $false
    try {
        $started = $process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if ($Stdin) { $process.StandardInput.Write($text) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill($true)
            $process.WaitForExit()
            [IO.File]::WriteAllText((Join-Path $evidence "$stem.stdout.txt"), $outTask.GetAwaiter().GetResult())
            [IO.File]::WriteAllText((Join-Path $evidence "$stem.stderr.txt"), $errTask.GetAwaiter().GetResult())
            throw "fsio exceeded 15 seconds ($stem)"
        }
        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stdout.txt"), $out)
        [IO.File]::WriteAllText((Join-Path $evidence "$stem.stderr.txt"), $err)
        Assert-True ($process.ExitCode -eq $ExitCode) "Exit $($process.ExitCode), expected $ExitCode ($stem): $err"
        if ($ExpectedError) {
            Assert-True ($err -match $ExpectedError) "Missing error '$ExpectedError' ($stem): $err"
        } else { Assert-True (-not $err) "Unexpected stderr ($stem): $err" }
        return $out
    } finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}
function Check-Bytes([string]$Name, [byte[]]$Expected, [int]$Block = 1) {
    $actual = [IO.File]::ReadAllBytes((Join-Path $work $Name))
    $length = [int]([Math]::Ceiling($Expected.Length / [double]$Block) * $Block)
    Assert-True ($actual.Length -eq $length) "$Name length $($actual.Length), expected $length"
    for ($i=0; $i -lt $length; $i++) {
        $value = if ($i -lt $Expected.Length) { $Expected[$i] } else { 0 }
        if ($actual[$i] -ne $value) { throw "$Name byte $i is $($actual[$i]), expected $value" }
    }
    @{name=$Name;inputLength=$Expected.Length;outputLength=$actual.Length;
        paddingBlockSize=$Block;sha256=(Get-FileHash -LiteralPath (Join-Path $work $Name)).Hash;
        byteComparisonPassed=$true} | ConvertTo-Json | Set-Content (Join-Path $evidence "$Name.comparison.json")
}
function U16([byte[]]$Data, [int]$Offset) { [BitConverter]::ToUInt16($Data, $Offset) }
function Check-Size([long]$Expected) {
    Assert-True ((Get-Item -LiteralPath (Join-Path $work 'disk.img')).Length -eq $Expected) "Wrong image length, expected $Expected"
}
try {
    $payload = [byte[]]::new(1536)
    for ($i=0; $i -lt $payload.Length; $i++) { $payload[$i] = $i % 256 }
    $ascii = [Text.Encoding]::ASCII.GetBytes("alpha`nbeta`nlast`n")
    [IO.File]::WriteAllBytes((Join-Path $work 'input.bin'), $payload)
    [IO.File]::WriteAllBytes((Join-Path $work 'input.txt'), $ascii)
    [IO.File]::WriteAllBytes((Join-Path $work 'empty.bin'), [byte[]]@())

    if ($Case -eq 'commands') {
        $out = Run-Fsio @('help','status') -Stdin
        foreach ($type in @('dos11','rt11','dosmt','os8','unixv7','local')) {
            Assert-True ($out.Contains($type)) "Missing supported format $type"
        }
        $nested = Join-Path $work 'nested.cmd'
        [IO.File]::WriteAllText($nested, "status`n")
        $out = Run-Fsio @('do -q nested.cmd','status','dir -f local:','status') -Arguments @('-qv')
        Assert-True ($out.Contains('fsio>')) 'Verbose command echo absent'
        Run-Fsio @() -Arguments @('-z') -ExitCode 1 -ExpectedError 'Usage:' -NoCommandFile | Out-Null
        Run-Fsio @() -Arguments @('missing.commands') -ExitCode 2 -ExpectedError 'Failed to open' -NoCommandFile | Out-Null
        Run-Fsio @('bad-command','status') -ExpectedError 'Unknown command' | Out-Null
    } elseif ($Case -eq 'local') {
        $absolute = (Join-Path $work 'space name.bin').Replace('\','/')
        $out = Run-Fsio @('copy input.bin output.bin', "copy input.bin 'local:$absolute'",
            'copy -a input.txt text.txt', 'copy empty.bin empty.out', 'dir local:',
            'dir -f local:*.bin', 'type input.txt', 'delete empty.out')
        Check-Bytes 'output.bin' $payload
        Check-Bytes 'space name.bin' $payload
        Check-Bytes 'text.txt' $ascii
        Assert-True ($out.Contains('space name.bin') -and $out.Contains('alpha')) 'Local listing/type failed'
        Assert-True (-not (Test-Path (Join-Path $work 'empty.out'))) 'Local deletion failed'
    } elseif ($Case -eq 'errors') {
        Run-Fsio @('newfs disk.img rt11','newfs disk.img rt11') -ExpectedError 'already exists' | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $work 'invalid.img'), [byte[]]::new(512))
        Run-Fsio @('mount dd invalid.img rt11','mount dd missing.img rt11',
            'newfs unused.img unsupported','mount dd disk.img rt11','mount dd disk.img rt11',
            'copy -c nope input.bin dd:BAD.BIN','umount dd') -ExpectedError '(?s)(?=.*valid file system)(?=.*failed to open)(?=.*not a supported)(?=.*already mounted)(?=.*Invalid character)' | Out-Null
        Assert-True (-not (Test-Path (Join-Path $work 'unused.img'))) 'Invalid format created media'
        foreach ($inodes in @('7','65536','abc','5000')) {
            Run-Fsio @("newfs -b 1024 -i $inodes rejected.img unixv7") -ExpectedError 'range|50%' | Out-Null
            Assert-True (-not (Test-Path (Join-Path $work 'rejected.img'))) 'Rejected V7 image was retained'
        }
    } elseif ($Case -eq 'rt11-fixture') {
        # Build a small V05 volume directly from its byte layout, without newfs.
        function Put-Word([byte[]]$Buffer,[int]$Offset,[uint16]$Value) {
            [BitConverter]::GetBytes($Value).CopyTo($Buffer,$Offset)
        }
        function Rad50([string]$Text) {
            $alphabet=' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.%0123456789'; $value=0
            foreach ($ch in $Text.PadRight(3).ToCharArray()) { $value=$value*40+$alphabet.IndexOf($ch) }
            return [uint16]$value
        }
        $fixture=[byte[]]::new(128*512)
        Put-Word $fixture (512+466) 1
        Put-Word $fixture (512+468) 6
        Put-Word $fixture (512+470) 36435
        [Text.Encoding]::ASCII.GetBytes('DECRT11A    ').CopyTo($fixture,512+496)
        $sum=0
        for ($i=512; $i -lt 1022; $i+=2) { $sum+=U16 $fixture $i }
        Put-Word $fixture 1022 ($sum -band 65535)
        $dir=6*512
        Put-Word $fixture $dir 1
        Put-Word $fixture ($dir+4) 1
        Put-Word $fixture ($dir+8) 8
        Put-Word $fixture ($dir+10) 1024
        Put-Word $fixture ($dir+12) (Rad50 'SAM')
        Put-Word $fixture ($dir+14) (Rad50 'PLE')
        Put-Word $fixture ($dir+16) (Rad50 'BIN')
        Put-Word $fixture ($dir+18) 3
        Put-Word $fixture ($dir+24) 512
        Put-Word $fixture ($dir+32) 117
        Put-Word $fixture ($dir+38) 2048
        $payload.CopyTo($fixture,8*512)
        $path=Join-Path $work 'fixture.img'
        [IO.File]::WriteAllBytes($path,$fixture)
        $before=(Get-FileHash $path).Hash
        $out=Run-Fsio @('mount -r dd fixture.img rt11','dir dd:S%M*.B%N',
            'copy dd:SAMPLE.BIN output.bin','umount dd')
        Check-Bytes 'output.bin' $payload
        Assert-True ($out -match 'SAMPLE.*BIN') 'Fixture wildcard missing'
        Assert-True ((Get-FileHash $path).Hash -eq $before) 'Read-only fixture changed'
        Put-Word $fixture ($dir+32) 65535
        [IO.File]::WriteAllBytes($path,$fixture)
        Run-Fsio @('mount dd fixture.img rt11') -ExpectedError 'valid file system' | Out-Null
    } elseif ($Case -eq 'unixv7-directory') {
        $commands=@('newfs -b 1024 -i 512 disk.img unixv7','mount dd disk.img unixv7','mkdir dd:/many')
        for ($i=0; $i -lt 40; $i++) { $commands += 'copy input.txt dd:/many/f{0:D2}' -f $i }
        $commands+=@('copy input.txt dd:/many/.hidden','copy empty.bin dd:/many/empty','umount dd')
        Run-Fsio $commands | Out-Null
        $out=Run-Fsio @('mount dd disk.img unixv7','dir dd:/many/*','copy dd:/many/f39 output.txt',
            'copy dd:/many/f30 boundary.txt','copy dd:/many/empty empty.out','delete dd:/many/f00','delete dd:/many/f39',
            'copy input.txt dd:/many/reused','copy dd:/many/reused reused.txt','umount dd')
        Assert-True ([regex]::Matches($out,'(?m)^f\d\d\s*$').Count -eq 40) 'Directory crossing did not list 40 files'
        Assert-True (-not $out.Contains('.hidden')) 'Wildcard improperly matched leading dot'
        Check-Bytes 'output.txt' $ascii
        Check-Bytes 'boundary.txt' $ascii
        Check-Bytes 'reused.txt' $ascii
        Check-Bytes 'empty.out' ([byte[]]@())
    } elseif ($Case -like 'dosmt*') {
        $extra = if ($Case -eq 'dosmt-extended') { '-x' } else { '' }
        $name = if ($extra) { 'ABCDEF123.BIN' } else { 'SAMPLE.BIN' }
        Run-Fsio @('newfs tape.tap dosmt') | Out-Null
        Assert-True ((Get-Item (Join-Path $work 'tape.tap')).Length -eq 0) 'New tape is not empty'
        Run-Fsio @("mount $extra mt tape.tap dosmt", "copy input.bin mt:$name",
            'eom mt:', 'copy -a input.txt mt:TEXT.TXT', 'rewind mt:',
            "copy mt:$name output.bin", 'rewind mt:', 'skipf mt: 1',
            'copy -an mt:TEXT.TXT text.txt', 'skipr mt: 1', 'info mt:',
            'dir mt:*.*', 'umount mt') | Out-Null
        Check-Bytes 'output.bin' $payload 512
        Check-Bytes 'text.txt' $ascii
        $tape = [IO.File]::ReadAllBytes((Join-Path $work 'tape.tap'))
        $pos=0; $records=0; $marks=0
        while ($pos -lt $tape.Length) {
            $len = [BitConverter]::ToUInt32($tape,$pos); $pos+=4
            if ($len -eq 0) { $marks++; continue }
            if ($len -eq [uint32]::MaxValue) { break }
            Assert-True ($len -lt 65536 -and ($pos+$len+4) -le $tape.Length) 'Invalid SIMH tape record'
            $pos += [int]($len + ($len % 2))
            Assert-True ([BitConverter]::ToUInt32($tape,$pos) -eq $len) 'Tape length trailer differs'
            $pos+=4; $records++
        }
        Assert-True ($records -ge 4 -and $marks -ge 2) 'Missing tape data or marks'
    } else {
        $format = ($Case -split '-')[0]
        if ($Case -eq 'large-offset') { $format='unixv7' }
        $device = if ($Case.Contains('-')) { ($Case -split '-',2)[1] } else { '' }
        $newFlags=''; $mountFlags=''; $setup=@(); $target='SAMPLE.BIN'; $textTarget='TEXT.TXT'; $block=512
        switch ($format) {
            'dos11' { $setup=@('set dd: ufd [1,1]'); $block=1 }
            'rt11' {
                if ($device -eq 'extra') { $newFlags='-t rk05 -e 3' }
                elseif ($device -ne 'default') { $newFlags="-t $device" }
                if ($device -like 'rx*') { $mountFlags="-t $device" }
            }
            'os8' {
                if ($device -eq 'extra') { $device='rk05'; $newFlags='-e 2' }
                $newFlags="$newFlags -t $device"; $mountFlags="-t $device"
                $target='SAMPLE.BN'; $textTarget='TEXT.TX'; $block=384
                $setup=@('set dd: year none')
            }
            'unixv7' {
                $block=1; $target='/sub/nested/data.bin'; $textTarget='/sub/nested/text.txt'
                if ($device -eq 'small' -or $Case -eq 'large-offset') { $newFlags='-b 1024 -i 64' }
                elseif ($device -ne 'default') { $newFlags="-t $device" }
                $setup=@('mkdir -p dd:/sub/nested','set dd: uid 12','set dd: gid 34')
                $payload = [byte[]]::new(80017)
                for ($i=0; $i -lt $payload.Length; $i++) { $payload[$i] = ($i*37+19) % 256 }
                [IO.File]::WriteAllBytes((Join-Path $work 'input.bin'), $payload)
            }
            default { throw "Unknown case $Case" }
        }
        Run-Fsio @("newfs $newFlags disk.img $format") | Out-Null
        $size = (Get-Item (Join-Path $work 'disk.img')).Length
        switch ($format) {
            'dos11' { Check-Size (4800*512) }
            'rt11' {
                $sizes=@{default=65535*512;rk05=4800*512;rl01=10240*512;rl02=20480*512;rx01=2002*128;rx02=2002*256;extra=4800*512}
                Check-Size $sizes[$device]
                if ($device -notlike 'rx*') {
                    $bytes = [IO.File]::ReadAllBytes((Join-Path $work 'disk.img'))
                    Assert-True ((U16 $bytes (512+468)) -eq 6) 'RT-11 home directory pointer differs'
                    Assert-True ((U16 $bytes (6*512+6)) -eq $(if ($device -eq 'extra') {4} else {0})) 'RT-11 extra bytes differ'
                }
            }
            'os8' { $sizes=@{rk05=6496*512;rx01=2002*128;rx02=2002*256}; Check-Size $sizes[$device] }
            'unixv7' {
                $sizes=@{default=4872;small=1024;rl01=10240;rl02=20480;rk06=27126;rk07=53790;offset=1024}
                Check-Size ($sizes[$device]*512)
                $bytes = [IO.File]::ReadAllBytes((Join-Path $work 'disk.img'))
                $diskBlocks = ((U16 $bytes 514) -shl 16) -bor (U16 $bytes 516)
                Assert-True ($diskBlocks -eq $sizes[$device]) 'V7 PDP-11 longword block count differs'
                if ($device -eq 'small' -or $Case -eq 'large-offset') {
                    Assert-True ((U16 $bytes 512) -eq 10) 'V7 -i 64 did not allocate 8 inode blocks'
                }
            }
        }
        if ($Case -eq 'large-offset') {
            $image = Join-Path $work 'disk.img'
            $partition = [IO.File]::ReadAllBytes($image)
            $stream = [IO.File]::Open($image,[IO.FileMode]::Create)
            try {
                $stream.SetLength(3GB + $partition.Length)
                $stream.Position=3GB
                $stream.Write($partition)
            } finally { $stream.Dispose() }
            $mountFlags='-o 6291456'
        }
        Run-Fsio (@("mount $mountFlags dd disk.img $format") + $setup + @(
            "copy input.bin dd:$target", "copy -a input.txt dd:$textTarget", 'umount dd')) | Out-Null
        $out = Run-Fsio @("mount $mountFlags dd disk.img $format", "copy dd:$target output.bin",
            "copy -a dd:$textTarget text.txt", 'dir -f dd:', 'status', 'umount dd')
        Check-Bytes 'output.bin' $payload $block
        Check-Bytes 'text.txt' $ascii
        if ($Case -ne 'large-offset') {
            $before = (Get-FileHash (Join-Path $work 'disk.img')).Hash
            Run-Fsio @("mount -r $mountFlags dd disk.img $format", 'copy input.bin dd:BAD.BIN',
                "delete dd:$target",'umount dd') -ExpectedError 'read-only' | Out-Null
            Assert-True ((Get-FileHash (Join-Path $work 'disk.img')).Hash -eq $before) 'Read-only image changed'
        }
        if ($format -eq 'rt11') {
            $out=Run-Fsio @("mount $mountFlags dd disk.img $format",'dir dd:S%M*.B%N','umount dd')
            Assert-True ($out -match 'SAMPLE.*BIN') 'RT-11 %/* matching failed'
            $out=Run-Fsio @("mount $mountFlags dd disk.img $format",'dir dd:S%.B%N','umount dd')
            Assert-True ($out -notmatch 'SAMPLE') 'RT-11 nonmatch returned SAMPLE'
        }
        if ($format -eq 'unixv7') {
            $out=Run-Fsio @("mount $mountFlags dd disk.img $format",'dir dd:/sub/nested/[d-f]?ta.*','umount dd')
            Assert-True ($out -match 'data.bin' -and $out -notmatch 'text.txt') 'V7 bracket wildcard failed'
        }
        Run-Fsio @("mount $mountFlags dd disk.img $format", "delete dd:$target",
            "copy input.bin dd:$target", "copy dd:$target reused.bin",'umount dd') | Out-Null
        Check-Bytes 'reused.bin' $payload $block
    }
    $receipt.passed=$true
} catch {
    $receipt.error=$_.ToString()
} finally {
    $receipt.processInvocations=$script:sequence
    $receipt.finishedUtc=[DateTime]::UtcNow.ToString('o')
    try {
        # $work was resolved and checked against the fixed G: root above.
        Remove-Item -LiteralPath $work -Recurse -Force
        $receipt.cleanupVerified = -not (Test-Path -LiteralPath $work)
        if (-not $receipt.cleanupVerified) { throw 'Temporary media remains' }
    } catch { $receipt.passed=$false; $receipt.error="$($receipt.error); cleanup: $_" }
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'result.json')
}
if (-not $receipt.passed) { throw $receipt.error }
Write-Output "$Case passed; $($receipt.processInvocations) fsio processes; G: cleanup verified"
