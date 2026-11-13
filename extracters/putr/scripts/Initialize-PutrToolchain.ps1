#requires -Version 7.0
param([string]$ToolchainDirectory = "$PSScriptRoot\..\..\..\bld\dos\putr\toolchain")
$ErrorActionPreference='Stop'
$url='https://github.com/Baron-von-Riedesel/JWasm/releases/download/v2.21/JWasm_v221_dos.zip'
$expected='A6B318CC3B3C98369F794C8F42EB2AD969E46485AD9B9FE81B7AC35F9321AE1B'
$ToolchainDirectory=[IO.Path]::GetFullPath($ToolchainDirectory)
New-Item -ItemType Directory -Path $ToolchainDirectory -Force | Out-Null
$zip=Join-Path $ToolchainDirectory 'JWasm_v221_dos.zip'
if(-not(Test-Path -LiteralPath $zip)) { Invoke-WebRequest -Uri $url -OutFile $zip }
if((Get-FileHash -LiteralPath $zip).Hash -ne $expected) { throw 'JWasm archive digest mismatch' }
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach($entry in $archive.Entries) {
        if($entry.FullName -match '(?i)python|\.img$|\.vhd$|\.iso$|(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($entry.FullName)) {
            throw "Unexpected archive entry: $($entry.FullName)"
        }
    }
} finally { $archive.Dispose() }
$destination=Join-Path $ToolchainDirectory 'jwasm-2.21'
Expand-Archive -LiteralPath $zip -DestinationPath $destination -Force
[ordered]@{downloadUrl=$url;archiveSha256=$expected;preparedUtc=[DateTime]::UtcNow.ToString('o');
    files=@(Get-ChildItem -LiteralPath $destination -File | ForEach-Object {
        @{name=$_.Name;length=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ToolchainDirectory 'provenance.json')
Write-Output "Verified JWasm 2.21 DOS toolchain: $destination"
