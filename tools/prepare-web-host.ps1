[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SourceRoot = Join-Path $ProjectRoot 'build/web-site/dist'
$TargetRoot = Join-Path $ProjectRoot 'build/samsonapps/cats-vs-dogs'
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'index.html'))) { throw 'Run tools/build-web.ps1 first.' }
New-Item -ItemType Directory -Force $TargetRoot | Out-Null
Get-ChildItem -LiteralPath $SourceRoot -File | Where-Object { $_.Name -ne '_headers' } | Copy-Item -Destination $TargetRoot -Force
foreach ($CompressedName in @('index.wasm', 'index.pck')) {
    $TargetPath = Join-Path $TargetRoot $CompressedName
    $InputStream = [System.IO.MemoryStream]::new([System.IO.File]::ReadAllBytes($TargetPath))
    $OutputStream = [System.IO.MemoryStream]::new()
    try {
        $Decoder = [System.IO.Compression.GZipStream]::new($InputStream, [System.IO.Compression.CompressionMode]::Decompress)
        try { $Decoder.CopyTo($OutputStream) } finally { $Decoder.Dispose() }
        [System.IO.File]::WriteAllBytes($TargetPath, $OutputStream.ToArray())
    } finally {
        $InputStream.Dispose()
        $OutputStream.Dispose()
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ZipPath = Join-Path $ProjectRoot 'build/cats-vs-dogs-samsonapps.zip'
if (Test-Path -LiteralPath $ZipPath) { [System.IO.File]::Delete($ZipPath) }
[System.IO.Compression.ZipFile]::CreateFromDirectory($TargetRoot, $ZipPath)
Write-Host "Hosting files ready: $TargetRoot"
Write-Host "Archive: $ZipPath"
