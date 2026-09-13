param([string]$Fixture = "$PSScriptRoot/../.build/compatibility")
$ErrorActionPreference = 'Stop'
$fixturePath = (Resolve-Path $Fixture).Path
$destination = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
try {
    Expand-Archive -LiteralPath (Join-Path $fixturePath 'compatibility.zip') -DestinationPath $destination
    $expected = Get-Content -LiteralPath (Join-Path $fixturePath 'expected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $count = 0
    foreach ($entry in $expected.PSObject.Properties) {
        $path = Join-Path $destination $entry.Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Unicode filename: $($entry.Name)" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $entry.Value) { throw "Content mismatch: $($entry.Name)" }
        $count++
    }
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -Force -File)
    if ($files.Count -ne $count) { throw 'Unexpected metadata files in archive' }
    $empty = Join-Path $destination '跨平台资料/空目录'
    if (-not (Test-Path -LiteralPath $empty -PathType Container)) { throw 'Empty directory missing' }
    Write-Output "PASS: Windows Expand-Archive; $count Unicode filenames and SHA-256 contents; empty directory; no metadata."
} finally {
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
}
