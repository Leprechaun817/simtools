# Dot-sourced by Check-Flx.ps1 inside its media-cleanup try/finally.
# This parser reads documented little-endian blockettes directly. It never
# calls FLX to obtain fault offsets or expected allocation bits.
$script:mutations=[Collections.Generic.List[object]]::new()
function Read-Image {
    $script:media=[IO.File]::ReadAllBytes((Join-Path $work 'disk.img'))
    $script:dcs=1
    while (($media.Length/512-1)/$script:dcs -ge 65536) { $script:dcs*=2 }
    $script:label=$script:dcs*512
    $script:pcs=U16 ($label+8)
    $script:old=((U16 ($label+10)) -band 0x2000) -eq 0
    $script:mfd=if($old){1}else{U16 ($label+4)}
}
function U16([int]$Offset) { [int]$media[$Offset] + 256*[int]$media[$Offset+1] }
function W16([int]$Offset,[int]$Value) {
    $script:mutations.Add(@{offset=$Offset;before=(U16 $Offset);after=$Value})
    $media[$Offset]=[byte]($Value -band 255); $media[$Offset+1]=[byte](($Value -shr 8) -band 255)
}
function Save-Image {
    [IO.File]::WriteAllBytes((Join-Path $work 'disk.img'),$media)
    $script:mutations | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $evidence 'injections.json')
}
function Image-Hash { (Get-FileHash -LiteralPath (Join-Path $work 'disk.img')).Hash }
function Bytes-Hash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function Link-Offset([int]$Dcn,[int]$Link) {
    if (($Link -band 0xfff0) -eq 0) { return -1 }
    $clu=($Link -shr 9) -band 7; $blk=$Link -shr 12; $off=$Link -band 0x1f0
    $map=$Dcn*$dcs*512+496; $size=$media[$map]
    Assert-True ($clu -lt 7 -and $blk -lt $size -and $off -ne 496) 'Oracle: invalid directory link'
    $target=U16 ($map+2+2*$clu)
    Assert-True ($target -ne 0) 'Oracle: link into absent cluster'
    return ($target*$dcs+$blk)*512+$off
}
function Entries([int]$Dcn) {
    $link=U16 ($Dcn*$dcs*512); $seen=[Collections.Generic.HashSet[int]]::new()
    while (($link -band 0xfff0) -ne 0) {
        Assert-True ($seen.Add($link -band 0xfff0)) 'Oracle: directory cycle'
        $off=Link-Offset $Dcn $link
        [pscustomobject]@{Offset=$off;Link=$link;Status=$media[$off+8];Next=(U16 $off)}
        $link=U16 $off
    }
}
function Account([int]$Project,[int]$User) {
    if ($old) {
        $matches=@(Entries $mfd | Where-Object { ($_.Status -band 0x40) -ne 0 -and (U16 ($_.Offset+2)) -eq $Project*256+$User })
        Assert-True ($matches.Count -eq 1) "Oracle: missing/duplicate account [$Project,$User]"
        $off=$matches[0].Offset; $dir=$mfd
    } else {
        $dir=U16 ($mfd*$dcs*512+512+2*$Project)
        $link=U16 ($dir*$dcs*512+1024+2*$User)
        $off=Link-Offset $dir $link
        Assert-True ($off -ge 0) "Oracle: missing account [$Project,$User]"
    }
    return [pscustomobject]@{Ne=$off;Ae=(Link-Offset $dir (U16 ($off+12)));Dcn=(U16 ($off+14))}
}
function Rad50([int]$Value) {
    $chars=' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.%0123456789'
    return [string]$chars[[int][Math]::Floor($Value/1600)] + $chars[[int][Math]::Floor(($Value%1600)/40)] + $chars[$Value%40]
}
function File-Record([int]$Project,[int]$User,[string]$Name) {
    $acc=Account $Project $User
    foreach($ent in @(Entries $acc.Dcn)) {
        if($ent.Status -band 0x40){continue}
        $off=$ent.Offset
        $fn=((Rad50 (U16 ($off+2)))+(Rad50 (U16 ($off+4)))).Trim()+'.'+(Rad50 (U16 ($off+6))).Trim()
        if($fn -eq $Name) {
            $ae=Link-Offset $acc.Dcn (U16 ($off+12)); $re=Link-Offset $acc.Dcn (U16 ($off+14))
            return [pscustomobject]@{Ne=$off;Link=$ent.Link;Ae=$ae;Re=$re;Dcn=$acc.Dcn;
                FirstDcn=$(if($re -ge 0){U16 ($re+2)}else{0})}
        }
    }
    throw "Oracle: file [$Project,$User]$Name missing"
}
function Bitmap {
    $s=File-Record 0 1 'SATT.SYS'
    $script:satOffset=$s.FirstDcn*$dcs*512
    $script:satLength=(U16 ($s.Ae+4))*512
    return ,([byte[]]$media[$satOffset..($satOffset+$satLength-1)])
}
function Retrievals($File) {
    $re=$File.Re; $seen=[Collections.Generic.HashSet[int]]::new()
    while($re -ge 0){
        Assert-True ($seen.Add($re)) 'Oracle: retrieval cycle'
        $dcns=@(for($j=0;$j -lt 7;$j++){ $dc=U16 ($re+2+2*$j); if(!$dc){break}; $dc })
        [pscustomobject]@{Offset=$re;Dcns=$dcns}
        $re=Link-Offset $File.Dcn (U16 $re)
    }
}
function Free-FileBits($File,[byte[]]$Map) {
    $clu=U16 ($File.Ae+14)
    foreach($re in @(Retrievals $File)){
        foreach($dc in $re.Dcns){
            $pcn=($dc-1)*$dcs/$pcs
            for($bit=$pcn;$bit -lt $pcn+$clu/$pcs;$bit++){
                $byte=[int][Math]::Floor($bit/8)
                $Map[$byte]=$Map[$byte] -band (255 -bxor (1 -shl ($bit%8)))
            }
        }
    }
}
function Free-DirectoryBits([int]$Dcn,[byte[]]$Map) {
    $start=$Dcn*$dcs*512+496; $clu=[Math]::Max($pcs,$media[$start])
    for($j=0;$j -lt 7;$j++){
        $dc=U16 ($start+2+2*$j); if(!$dc){break}
        $pcn=($dc-1)*$dcs/$pcs
        for($bit=$pcn;$bit -lt $pcn+$clu/$pcs;$bit++){
            $byte=[int][Math]::Floor($bit/8); $Map[$byte]=$Map[$byte] -band (255 -bxor (1 -shl ($bit%8)))
        }
    }
}
function Assert-Bitmap([byte[]]$Expected) {
    Read-Image
    $actual=Bitmap
    $expectedHash=Bytes-Hash $Expected; $actualHash=Bytes-Hash $actual
    @{expectedSha256=$expectedHash;actualSha256=$actualHash;length=$actual.Length} | ConvertTo-Json |
        Set-Content (Join-Path $evidence ('bitmap-'+$script:sequence+'.json'))
    Assert-True ($actualHash -eq $expectedHash) 'Reconstructed bitmap differs from expected allocation'
    Assert-True (((U16 ($label+10)) -band 0x8000) -eq 0) 'Rebuilt pack still marked dirty'
}
function New-RepairVolume([string]$Revision='0.0',[string]$Medium='rk05',[int]$Pcs=0) {
    $initArgs=@('initialize','REPAIR',$Revision,'-create',$Medium)
    if($Pcs){$initArgs+=@('-clustersize',"$Pcs")}
    Disk $initArgs | Out-Null
    if($Revision -ne '0.0'){Disk @('mkdir','[1,1]') | Out-Null}
    Disk @('put','-binary','input.bin','[1,1]ROOT.BIN') | Out-Null
    Disk @('mkdir','[1,2]') | Out-Null
    Put-Payload
    Disk @('mkdir','[2,3]') | Out-Null
    Disk @('put','-binary','-rs','input.bin','[2,3]OTHER.BIN') | Out-Null
    Disk @('mkdir','[2,4]') | Out-Null # intentionally unallocated UFD
    Read-Image
}
function Check-Payloads {
    foreach($item in @(@('[1,1]ROOT.BIN','root.out'),@('[1,2]DATA.BIN','data.out'),@('[2,3]OTHER.BIN','other.out'))) {
        Disk @('get','-binary',$item[0],$item[1]) | Out-Null
        Check-Bytes $item[1] $payload
    }
}
function Assert-Idempotent {
    Read-Image
    # Mount timestamp is an intentional RDS1.2 dismount side effect.
    $before=[byte[]]$media.Clone()
    if(-not $old){[Array]::Clear($before,$label+24,4)}
    $out=Disk @('rebuild','-verbose')
    Assert-True ($out -notmatch 'was free, now allocated|was allocated, now free|will be|fixed|incorrect') 'Second rebuild still proposes repairs'
    Read-Image
    $after=[byte[]]$media.Clone()
    if(-not $old){[Array]::Clear($after,$label+24,4)}
    if((Bytes-Hash $before) -ne (Bytes-Hash $after)) {
        @(for($pos=0;$pos -lt $before.Length;$pos++){if($before[$pos] -ne $after[$pos]){
            @{offset=$pos;before=$before[$pos];after=$after[$pos]}
        }}) | ConvertTo-Json | Set-Content (Join-Path $evidence 'second-pass-differences.json')
        throw 'Second rebuild changed metadata or data'
    }
}
function Check-Refusals([string]$Pattern) {
    $hash=Image-Hash
    Disk @('clean','-verbose') $Pattern 1 '' | Out-Null
    Assert-True ((Image-Hash) -eq $hash) 'EOF/abort changed image'
    Disk @('rebuild','-verbose') $Pattern 1 "n`n" | Out-Null
    Assert-True ((Image-Hash) -eq $hash) 'Declined repair changed image'
    Disk @('clean','-protect','-verbose') $Pattern 0 | Out-Null
    Assert-True ((Image-Hash) -eq $hash) 'Read-only repair changed image'
}
function Free-Entry([int]$Dcn) {
    # Fixtures only need a free blockette in the first directory block.
    $base=$Dcn*$dcs*512
    for($off=16;$off -lt 496;$off+=16){
        $zero=$true
        for($j=0;$j -lt 16;$j++){if($media[$base+$off+$j]){$zero=$false;break}}
        if($zero){return [pscustomobject]@{Offset=$base+$off;Link=$off}}
    }
    throw 'No free fixture blockette'
}
function Invoke-CleanCase([string]$Name) {
    switch($Name) {
        'repair-rds0-rm02' {New-RepairVolume '0.0' 'rm02'}
        'repair-rds0-pcs16' {New-RepairVolume '0.0' 'rl02' 16}
        'repair-badb-pcs16' {New-RepairVolume '0.0' 'rl02' 16}
        'repair-rds11' {New-RepairVolume '1.1' 'rl02'}
        'repair-rds12-pcs32' {New-RepairVolume '1.2' 'rm02' 32}
        'repair-rds12-cycle' {New-RepairVolume '1.2'}
        'repair-rds12-crosslink' {New-RepairVolume '1.2'}
        'repair-rds12-shared-dir' {New-RepairVolume '1.2'}
        'repair-rds11-delete' {New-RepairVolume '1.1'}
        default {New-RepairVolume}
    }
    if($Name -eq 'repair-extent-end'){
        Disk @('put','-binary','-rs','-clustersize','16','input.bin','[2,3]OTHER.BIN') | Out-Null
        Read-Image
    }
    $expected=Bitmap
    if($Name -match '^repair-(rds0-(rk05|rm02|pcs16)|rds11|rds12-pcs32)$') {
        $hash=Image-Hash
        Disk @('clean','-protect','-verbose') | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Healthy read-only clean changed image'
        Disk @('clean','-verbose') | Out-Null
        Assert-Bitmap $expected
        Check-Payloads
        # Flip every SATT bit: both lost allocations and leaked allocations,
        # including padding beyond the last usable pack cluster.
        Read-Image; $null=Bitmap
        for($j=0;$j -lt $satLength;$j++){$media[$satOffset+$j]=$media[$satOffset+$j] -bxor 255}
        W16 ($label+10) ((U16 ($label+10)) -bor 0x8000)
        Save-Image; $hash=Image-Hash
        $out=Disk @('clean','-protect','-verbose')
        Assert-True ($out -match 'was free, now allocated' -and $out -match 'was allocated, now free') 'Both bitmap error directions were not detected'
        Assert-True ((Image-Hash) -eq $hash) 'Damaged read-only clean changed image'
        Disk @('rebuild','-verbose') | Out-Null
        Assert-Bitmap $expected
        Check-Payloads
        Assert-Idempotent
        Disk @('put','-binary','input.bin','[1,2]NEW.BIN') | Out-Null
        Check-Payloads # subsequent allocations must not overwrite live data
    } elseif($Name -eq 'repair-growth') {
        $commands=[Collections.Generic.List[string]]::new()
        for($j=1;$j -le 254;$j++){$commands.Add("mkdir [5,$j]")}
        $commands.Add('mkdir -clustersize 4 [4,1]')
        for($j=0;$j -lt 300;$j++){$commands.Add(('put -binary empty.bin [4,1]F{0:D5}.BIN' -f $j))}
        $commands.Add('put -binary input.bin [4,1]LAST.BIN'); $commands.Add('exit')
        Run-Flx @('disk','disk.img') (($commands -join "`n")+"`n") | Out-Null
        Read-Image; $expected=Bitmap
        $a=Account 4 1
        Assert-True ((U16 ($mfd*$dcs*512+500)) -ne 0) 'MFD did not extend beyond first 16 blocks'
        Assert-True ((U16 ($a.Dcn*$dcs*512+506)) -ne 0) 'UFD did not extend beyond sixteen blocks'
        $hash=Image-Hash
        Disk @('clean','-protect','-verbose') | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Growth check wrote image'
        Disk @('rebuild','-verbose') | Out-Null
        Assert-Bitmap $expected
        Read-Image
        Assert-True (@(Entries $a.Dcn).Count -eq 301) 'Lost extended UFD entries'
        $null=Account 5 254
        Disk @('get','-binary','[4,1]LAST.BIN','last.out') | Out-Null
        Check-Bytes 'last.out' $payload
        Check-Payloads; Assert-Idempotent
    } elseif($Name -in @('repair-mfd-cycle','repair-ufd-cycle','repair-rds12-cycle','repair-interactive')) {
        if($Name -eq 'repair-mfd-cycle'){
            $entries=@(Entries $mfd); W16 $entries[-1].Offset $entries[0].Link
            $pattern='bad or cyclic link in RDS0 MFD'
        }else{
            $f=File-Record 1 2 'DATA.BIN'; W16 $f.Ne $f.Link
            $pattern='bad next file link'
        }
        Save-Image
        Check-Refusals $pattern
        if($Name -eq 'repair-interactive'){
            $out=Run-Flx @('disk','disk.img') "clean`nn`nidentify`nrebuild`ny`nidentify`nexit`n" 0 'Clean aborted'
            Assert-True ($out -match 'REPAIR') 'Interactive session did not recover after aborted clean'
        }else{Disk @('rebuild','-verbose') $pattern 0 "y`n" | Out-Null}
        Assert-Bitmap $expected; Check-Payloads; Assert-Idempotent
    } elseif($Name -eq 'repair-self') {
        $a=Account 1 1; W16 ($a.Ne+14) 0; W16 ($a.Ae+14) 0
        Save-Image; $hash=Image-Hash
        Disk @('clean','-protect','-verbose') 'fixed RDS0' | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Self-reference preview changed image'
        Disk @('rebuild','-verbose') 'fixed RDS0' | Out-Null
        Assert-Bitmap $expected; Check-Payloads; Assert-Idempotent
    } elseif($Name -in @('repair-delete','repair-mfd-delete','repair-rds11-delete')) {
        $rootFile=$Name -eq 'repair-mfd-delete'
        $f=if($rootFile){File-Record 1 1 'ROOT.BIN'}else{File-Record 1 2 'DATA.BIN'}
        $media[$f.Ne+8]=$media[$f.Ne+8] -bor 0x80
        Free-FileBits $f $expected
        $orphan=Free-Entry $f.Dcn; W16 $orphan.Offset 1; W16 ($orphan.Offset+2) 1234
        Save-Image
        Disk @('clean','-verbose') | Out-Null
        Assert-Bitmap $expected
        if($rootFile){Disk @('list','[1,1]ROOT.BIN') 'No files matching' | Out-Null}
        else{Assert-True (@(Entries $f.Dcn).Count -eq 0) 'Deleted file still linked'}
        Assert-True ((U16 $orphan.Offset) -eq 0 -and (U16 $f.Ne) -eq 0 -and (U16 $f.Ae) -eq 0) 'Orphan/deleted blockettes not cleared'
        Assert-Idempotent
    } elseif($Name -eq 'repair-account') {
        $a=Account 2 4; W16 ($a.Ne+12) 0; Save-Image
        Check-Refusals 'invalid or shared accounting entry'
        Disk @('rebuild','-verbose') 'account will be deleted' 0 "y`n" | Out-Null
        Assert-Bitmap $expected; Check-Payloads; Assert-Idempotent
    } elseif($Name -eq 'repair-map-copy') {
        Disk @('mkdir','-clustersize','4','[3,1]') | Out-Null
        Disk @('put','-binary','input.bin','[3,1]MAP.BIN') | Out-Null
        Read-Image; $expected=Bitmap; $a=Account 3 1
        W16 ($a.Dcn*$dcs*512+512+500) 4001
        Save-Image; $hash=Image-Hash
        Disk @('clean','-protect','-verbose') | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Directory-map preview changed image'
        Disk @('rebuild','-verbose') | Out-Null
        Assert-Bitmap $expected
        Assert-True ((U16 ($a.Dcn*$dcs*512+512+500)) -eq 0) 'Stale directory extension was not cleared'
        Check-Payloads
        Disk @('get','-binary','[3,1]MAP.BIN','map.out') | Out-Null; Check-Bytes 'map.out' $payload
        Assert-Idempotent
    } elseif($Name -in @('repair-shared-dir','repair-rds12-shared-dir')) {
        $a=Account 2 3; $keep=Account 1 2; $lose=File-Record 2 3 'OTHER.BIN'
        Free-FileBits $lose $expected; Free-DirectoryBits $a.Dcn $expected
        W16 ($a.Ne+14) $keep.Dcn
        if(-not $old){
            $gfd=U16 ($mfd*$dcs*512+512+4)
            W16 ($gfd*$dcs*512+512+6) $keep.Dcn
        }
        Save-Image
        Check-Refusals 'doubly allocated block'
        Disk @('rebuild','-verbose') 'account \[2,3\] will be zeroed' 0 "y`n" | Out-Null
        Assert-Bitmap $expected
        Assert-True ((Account 2 3).Dcn -eq 0) 'Shared directory reference was not cleared'
        Disk @('get','-binary','[1,2]DATA.BIN','kept.out') | Out-Null; Check-Bytes 'kept.out' $payload
        Assert-Idempotent
    } elseif($Name -in @('repair-crosslink','repair-rds12-crosslink','repair-extent-end')) {
        $keep=File-Record 1 2 'DATA.BIN'; $lose=File-Record 2 3 'OTHER.BIN'
        Free-FileBits $lose $expected
        W16 ($lose.Re+2) $(if($Name -eq 'repair-extent-end'){4785}else{$keep.FirstDcn}); Save-Image
        Check-Refusals $(if($Name -eq 'repair-extent-end'){'cluster number out of range'}else{'doubly allocated block'})
        Disk @('rebuild','-verbose') 'file will be truncated' 0 "y`n" | Out-Null
        Assert-Bitmap $expected
        $repaired=File-Record 2 3 'OTHER.BIN'
        $rms=Link-Offset $repaired.Dcn (U16 $repaired.Ae)
        Assert-True ((U16 ($rms+6)) -eq 0 -and (U16 ($rms+8)) -eq 0) 'RMS allocated size was not truncated'
        Disk @('get','-binary','[1,2]DATA.BIN','kept.out') | Out-Null; Check-Bytes 'kept.out' $payload
        Disk @('get','-binary','[2,3]OTHER.BIN','truncated.out') | Out-Null; Check-Bytes 'truncated.out' ([byte[]]@())
        Disk @('get','-ascii','[2,3]OTHER.BIN','rms.out') | Out-Null; Check-Bytes 'rms.out' ([byte[]]@())
        Assert-Idempotent
    } elseif($Name -eq 'repair-retrieval-cycle') {
        $f=File-Record 1 2 'DATA.BIN'; $res=@(Retrievals $f)
        W16 $res[-1].Offset (U16 ($f.Ne+14)); Save-Image
        Check-Refusals 'retrieval entry chain'
        Disk @('rebuild','-verbose') 'file will be truncated' 0 "y`n" | Out-Null
        Assert-Bitmap $expected; Check-Payloads; Assert-Idempotent
    } elseif($Name -in @('repair-badb','repair-badb-pcs16','repair-fatal-badb')) {
        $f=File-Record 0 1 'BADB.SYS'; $entry=Free-Entry $f.Dcn
        $dc=if($pcs -eq 16){20001}else{4701}; $pcn=($dc-1)*$dcs/$pcs
        W16 ($f.Ne+14) $entry.Link; W16 $entry.Offset $(if($Name -eq 'repair-fatal-badb'){$entry.Link}else{0})
        W16 ($entry.Offset+2) $dc; Save-Image
        if($Name -ne 'repair-fatal-badb'){
            $expected[[int][Math]::Floor($pcn/8)]=$expected[[int][Math]::Floor($pcn/8)] -bor (1 -shl ($pcn%8))
            $hash=Image-Hash
            Disk @('clean','-protect','-verbose') | Out-Null
            Assert-True ((Image-Hash) -eq $hash) 'Bad-block preview changed image'
            Disk @('rebuild','-verbose') | Out-Null
            Assert-Bitmap $expected; Check-Payloads; Assert-Idempotent
        } else {
            $hash=Image-Hash
            Disk @('rebuild','-verbose') 'cyclic retrieval chain' 1 | Out-Null
            Assert-True ((Image-Hash) -eq $hash) 'Invalid bad-block map changed image'
        }
    } elseif($Name -eq 'repair-fatal-lookup') {
        $a=Account 1 1
        $entry=@(Entries $mfd | Where-Object Offset -eq $a.Ne)[0]
        W16 $label $entry.Link; W16 $entry.Offset $entry.Link
        Save-Image; $hash=Image-Hash
        Disk @('rebuild','-verbose') 'Corrupt disk structure' 1 | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Failed system lookup changed image'
    } elseif($Name -in @('repair-fatal-map','repair-fatal-satt')) {
        if($Name -eq 'repair-fatal-map'){
            W16 ($mfd*$dcs*512+510) 4001
        }else{
            $f=File-Record 0 1 'SATT.SYS'; W16 ($f.Re+2) 1
        }
        Save-Image; $hash=Image-Hash
        Disk @('rebuild','-verbose') 'Disk cannot be rebuilt' 1 | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Fatal root/system corruption changed image'
    } elseif($Name -eq 'repair-readonly') {
        W16 ($label+10) ((U16 ($label+10)) -bor 0x1000 -bor 0x8000); Save-Image; $hash=Image-Hash
        Disk @('clean') 'Disk is read-only' 1 | Out-Null
        Disk @('clean','-protect') | Out-Null
        Assert-True ((Image-Hash) -eq $hash) 'Readonly pack was changed'
        Disk @('rebuild','-Write') | Out-Null
        Assert-Bitmap $expected
        Assert-True (((U16 ($label+10)) -band 0x1000) -ne 0) 'Read-only flag lost'
        Check-Payloads
    } else {throw "Unknown repair case $Name"}
}
