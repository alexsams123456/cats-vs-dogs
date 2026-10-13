[CmdletBinding()]
param(
    [string]$GodotPath = '.tools/Godot_v4.7.1-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutputPath = Join-Path $ProjectRoot 'build/web'
$ProfilePath = Join-Path $ProjectRoot '.artifacts/web-export-profile'
$PreviousAppData = $env:APPDATA
$Utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Force $OutputPath, $ProfilePath | Out-Null
try {
    $env:APPDATA = $ProfilePath
    & $GodotPath --headless --path $ProjectRoot --export-release "Web local legacy" (Join-Path $OutputPath 'index.html')
    if ($LASTEXITCODE -ne 0) { throw 'Web export failed.' }
} finally {
    $env:APPDATA = $PreviousAppData
}

$GeneratedHtml = Get-Content -LiteralPath (Join-Path $OutputPath 'index.html') -Encoding UTF8 -Raw
$EngineJavaScript = Get-Content -LiteralPath (Join-Path $OutputPath 'index.js') -Encoding UTF8 -Raw
# Custom templates ignore the preset's thread toggle: inspect the exported runtime too.
if ($EngineJavaScript.Contains('loadWasmModuleToAllWorkers') -or
    $EngineJavaScript -match 'shared\s*:\s*true') {
    throw 'Web runtime uses shared memory. Use the matching web_nothreads_release.zip template.'
}
$ConfigMatch = [regex]::Match($GeneratedHtml, 'const GODOT_CONFIG = (\{[^\r\n]+\});')
if (-not $ConfigMatch.Success) { throw 'Godot web configuration was not found.' }
$Config = $ConfigMatch.Groups[1].Value | ConvertFrom-Json
if ($Config.gdextensionLibs.Count -ne 0) { throw 'Unexpected web extension.' }
foreach ($Asset in @('index.pck', 'index.wasm')) {
    if ((Get-Item -LiteralPath (Join-Path $OutputPath $Asset)).Length -ne $Config.fileSizes.$Asset) {
        throw "Exported file size does not match configuration: $Asset"
    }
}
$Loader = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'web/game-loader.js') -Encoding UTF8 -Raw
$Loader = $Loader.Replace('__GODOT_CONFIG__', $ConfigMatch.Groups[1].Value)
[IO.File]::WriteAllText((Join-Path $OutputPath 'game-loader.js'), $Loader, $Utf8)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'web/index.html') -Destination (Join-Path $OutputPath 'index.html')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'web/game.css') -Destination (Join-Path $OutputPath 'game.css')
Write-Output "Web export ready: $OutputPath"
