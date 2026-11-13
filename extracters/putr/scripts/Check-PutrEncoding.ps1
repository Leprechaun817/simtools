param(
    [Parameter(Mandatory)][string]$Listing,
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Receipt
)
$ErrorActionPreference='Stop'
$lines=Get-Content -LiteralPath $Listing
$bytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Executable).Path)
$checks=[Collections.Generic.List[object]]::new()
for($i=0;$i -lt $lines.Count;$i++) {
    if($lines[$i] -match '^([0-9A-F]{4,8})\s+[0-9A-F]+\s+.*\bj\w+\s+\$\+([345])\b') {
        $address=[Convert]::ToInt32($Matches[1],16)
        $skip=[int]$Matches[2]
        $next=[Collections.Generic.List[int]]::new()
        for($j=$i+1;$j -lt $lines.Count -and $next.Count -lt 2;$j++) {
            if($lines[$j] -match '^([0-9A-F]{4,8})\s+[0-9A-F]{2}') { $next.Add([Convert]::ToInt32($Matches[1],16)) }
        }
        if($next.Count -ne 2 -or $address+$skip -ne $next[1]) { throw "Fixed-byte skip crosses an instruction boundary: $($lines[$i])" }
        $checks.Add(@{kind='fixed-byte-skip';address=$address;target=$next[1];instruction=$lines[$i].Trim()})
    }
}
if($checks.Count -ne 19) { throw "Expected 19 fixed-byte conditional skips; found $($checks.Count)" }
foreach($pattern in @('odsize:.*word ptr ds:h_ufat\+f_efbk\[si\]','word ptr ds:h_ufat\+f_efbk\+2\[si\]','word ptr ds:h_ufat\+f_ffby\[si\]')) {
    $line=$lines | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if($line -notmatch '^([0-9A-F]{4,8})\s+(8B(?:5416|4418|5C1A))\s') { throw "Unexpected word-load encoding: $line" }
    $address=[Convert]::ToInt32($Matches[1],16); $hex=$Matches[2]
    if([Convert]::ToHexString($bytes[($address-256)..($address-254)]) -ne $hex) { throw 'Binary and listing disagree' }
    $checks.Add(@{kind='word-load';address=$address;bytes=$hex;instruction=$line.Trim()})
}
$checks | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Receipt
Write-Output "$($checks.Count) instruction-encoding checks passed"
