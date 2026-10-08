[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$ExportTemplateArchive,
    [ValidateRange(25, 512)]
    [int]$MaxStaticAssetMiB = 25
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ExpectedVersion = (Get-Content -LiteralPath (Join-Path $ProjectRoot '.godot-version') -Raw).Trim()
if (-not $GodotPath) { $GodotPath = Join-Path $ProjectRoot ".tools/godot/Godot_v$ExpectedVersion-stable_win64_console.exe" }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
if (-not $ExportTemplateArchive) { $ExportTemplateArchive = Join-Path $ProjectRoot ".tools/godot/Godot_v$ExpectedVersion-stable_export_templates.tpz" }
$ProfileRoot = Join-Path $ProjectRoot '.tools/web-export-profile'
$TemplateRoot = Join-Path $ProfileRoot "Godot/export_templates/$ExpectedVersion.stable"
$ArtifactsRoot = Join-Path $ProjectRoot '.artifacts'
$WorkspaceRoot = Join-Path $ArtifactsRoot ('web-build-' + [Guid]::NewGuid().ToString('N'))
$OutputRoot = Join-Path $ProjectRoot 'build/web-site/dist'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Invoke-WebGodot {
    param([string]$Name, [string[]]$EngineArguments, [switch]$AllowInitialImportErrors)
    $LogPath = Join-Path $ArtifactsRoot "$Name.log"
    & $GodotPath @EngineArguments *> $LogPath
    if ($LASTEXITCODE -ne 0 -and -not $AllowInitialImportErrors) { throw "Godot failed. See $LogPath" }
    if (-not $AllowInitialImportErrors -and (Select-String -LiteralPath $LogPath -Pattern '(^ERROR:|SCRIPT ERROR:)' -Quiet)) {
        throw "Godot reported errors. See $LogPath"
    }
}

$PreviousAppData = $env:APPDATA
try {
    $ActualVersion = (& $GodotPath --headless --version | Out-String).Trim()
    if ($ActualVersion -notmatch ('^' + [regex]::Escape($ExpectedVersion) + '\.')) { throw "Use Godot $ExpectedVersion, found $ActualVersion" }
    New-Item -ItemType Directory -Force $TemplateRoot, $WorkspaceRoot, $OutputRoot | Out-Null
    if (Test-Path -LiteralPath $ExportTemplateArchive -PathType Leaf) {
        $Archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ExportTemplateArchive).Path)
        try {
            foreach ($TemplateName in @('version.txt', 'web_nothreads_debug.zip', 'web_nothreads_release.zip')) {
                $Entry = $Archive.GetEntry("templates/$TemplateName")
                if ($null -eq $Entry) { throw "Missing $TemplateName in export templates" }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, (Join-Path $TemplateRoot $TemplateName), $true)
            }
        } finally { $Archive.Dispose() }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $TemplateRoot 'web_nothreads_release.zip'))) { throw 'Pass -ExportTemplateArchive with matching Godot export templates.' }
    foreach ($SourceName in @('assets', 'characters', 'houses', 'levels', 'materials', 'scenes', 'scripts', 'translations', 'web', 'default_bus_layout.tres', 'project.godot', 'export_presets.cfg', '.godot-version')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot $SourceName) -Destination $WorkspaceRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force (Join-Path $WorkspaceRoot 'build/web') | Out-Null
    $env:APPDATA = $ProfileRoot
    # Первый импорт создаёт шрифты, на которые уже ссылается тема проекта.
    Invoke-WebGodot -Name 'web-first-import' -EngineArguments @('--headless', '--path', $WorkspaceRoot, '--editor', '--import', '--quit') -AllowInitialImportErrors
    Invoke-WebGodot -Name 'web-import' -EngineArguments @('--headless', '--path', $WorkspaceRoot, '--editor', '--import', '--quit')
    Invoke-WebGodot -Name 'web-export' -EngineArguments @('--headless', '--path', $WorkspaceRoot, '--export-release', 'Web', 'build/web/index.html')
    Copy-Item -Path (Join-Path $WorkspaceRoot 'build/web/*') -Destination $OutputRoot -Force
    # Значок домашнего экрана iOS отдельный; favicon и графика самой игры прежние.
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets/icons/apple_touch.png') -Destination (Join-Path $OutputRoot 'index.apple-touch-icon.png') -Force
    # Отдельные файлы совместимы с хостингом, запрещающим inline-скрипты.
    $HtmlPath = Join-Path $OutputRoot 'index.html'
    $HtmlText = [System.IO.File]::ReadAllText($HtmlPath)
    $StyleMatch = [regex]::Match($HtmlText, '(?s)<style>(.*?)</style>')
    $ScriptMatch = [regex]::Match($HtmlText, '(?s)<script>(.*?)</script>')
    if (-not $StyleMatch.Success -or -not $ScriptMatch.Success) { throw 'Web shell style or loader is missing.' }
    [System.IO.File]::WriteAllText((Join-Path $OutputRoot 'game.css'), $StyleMatch.Groups[1].Value, $Utf8)
    [System.IO.File]::WriteAllText((Join-Path $OutputRoot 'game-loader.js'), $ScriptMatch.Groups[1].Value, $Utf8)
    $HtmlText = $HtmlText.Replace($StyleMatch.Value, '<link rel="stylesheet" href="game.css">').Replace($ScriptMatch.Value, '<script src="game-loader.js"></script>')
    [System.IO.File]::WriteAllText($HtmlPath, $HtmlText, $Utf8)
    foreach ($CompressedName in @('index.wasm', 'index.pck')) {
        $TargetPath = Join-Path $OutputRoot $CompressedName
        $Bytes = [System.IO.File]::ReadAllBytes($TargetPath)
        $Memory = [System.IO.MemoryStream]::new()
        try {
            $Compressor = [System.IO.Compression.GZipStream]::new($Memory, [System.IO.Compression.CompressionLevel]::Optimal, $true)
            try { $Compressor.Write($Bytes, 0, $Bytes.Length) } finally { $Compressor.Dispose() }
            [System.IO.File]::WriteAllBytes($TargetPath, $Memory.ToArray())
        } finally { $Memory.Dispose() }
        if ((Get-Item -LiteralPath $TargetPath).Length -gt ($MaxStaticAssetMiB * 1MB)) { throw "Static asset exceeds $MaxStaticAssetMiB MiB: $CompressedName" }
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'web/headers.txt') -Destination (Join-Path $OutputRoot '_headers') -Force
    $ManifestRoot = Join-Path $ProjectRoot 'build/web-site/.openai'
    New-Item -ItemType Directory -Force $ManifestRoot | Out-Null
    $ManifestPath = Join-Path $ManifestRoot 'hosting.json'
    if (-not (Test-Path -LiteralPath $ManifestPath)) { [System.IO.File]::WriteAllText($ManifestPath, '{"static":{"directory":"dist"}}', $Utf8) }
    $ZipPath = Join-Path $ProjectRoot 'build/cats-vs-dogs-web.zip'
    if (Test-Path -LiteralPath $ZipPath) { [System.IO.File]::Delete($ZipPath) }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($OutputRoot, $ZipPath)
    Write-Host "Web build ready: $OutputRoot"
    Write-Host "Archive: $ZipPath"
} finally {
    $env:APPDATA = $PreviousAppData
}
