[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$TemplateArchive,
    [string]$EditorProfile,
    [string]$BuildToolsVersion = '36.0.0'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (!$GodotPath) { $GodotPath = Join-Path $ProjectRoot '.tools/Godot_v4.7.1-stable_win64_console.exe' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
# The Windows console wrapper can wait for a key after a failed export.
$GuiExecutable = $GodotPath -replace '_console\.exe$', '.exe'
if ($GuiExecutable -ne $GodotPath -and (Test-Path -LiteralPath $GuiExecutable)) { $GodotPath = $GuiExecutable }
$Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot '.godot-version') -Raw).Trim()
if (!$EditorProfile -and (Test-Path (Join-Path $ProjectRoot '.tools/android-export-profile'))) {
    $EditorProfile = Join-Path $ProjectRoot '.tools/android-export-profile'
}
$PreviousAppData = $env:APPDATA
try {
    if ($EditorProfile) { $env:APPDATA = (Resolve-Path -LiteralPath $EditorProfile).Path }
    if (!$TemplateArchive) {
        $TemplateArchive = Join-Path $env:APPDATA "Godot/export_templates/$Version.stable/android_source.zip"
    }
    $TemplateArchive = (Resolve-Path -LiteralPath $TemplateArchive).Path
    $TvTemplateDir = Join-Path $ProjectRoot 'build/android-tv'
    $TvBuildDir = Join-Path $TvTemplateDir 'build'
    $BuildVersionPath = Join-Path $TvTemplateDir '.build_version'
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    if (!(Test-Path -LiteralPath $BuildVersionPath)) {
        if (Test-Path -LiteralPath $TvBuildDir) {
            throw 'TV template directory already exists without .build_version. Preserve or move it before retrying.'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($TemplateArchive, $TvBuildDir)
        [System.IO.File]::WriteAllText($BuildVersionPath, "$Version.stable", $Utf8)
    }
    if ((Get-Content -LiteralPath $BuildVersionPath -Raw).Trim() -ne "$Version.stable") {
        throw 'TV template version does not match .godot-version.'
    }
    [System.IO.File]::WriteAllText((Join-Path $TvBuildDir '.gdignore'), '', $Utf8)
    if ($BuildToolsVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Build Tools version.' }
    $ConfigPath = Join-Path $TvBuildDir 'config.gradle'
    $Config = [System.IO.File]::ReadAllText($ConfigPath)
    $Config = [regex]::Replace($Config, "buildTools\s*:\s*'[^']+'", "buildTools         : '$BuildToolsVersion'")
    [System.IO.File]::WriteAllText($ConfigPath, $Config, $Utf8)
    $MainDir = Join-Path $TvBuildDir 'src/main'
    $DrawableDir = Join-Path $MainDir 'res/drawable-xhdpi'
    [void][System.IO.Directory]::CreateDirectory($DrawableDir)
    # Godot regenerates debug/release manifests; the main template keeps TV declarations.
    $ManifestPath = Join-Path $MainDir 'AndroidManifest.xml'
    [xml]$Manifest = [System.IO.File]::ReadAllText($ManifestPath)
    $AndroidNamespace = 'http://schemas.android.com/apk/res/android'
    foreach ($Name in @('android.hardware.touchscreen', 'android.software.leanback')) {
        $Feature = @($Manifest.manifest.'uses-feature') | Where-Object { $_.GetAttribute('name', $AndroidNamespace) -eq $Name } | Select-Object -First 1
        if (!$Feature) {
            $Feature = $Manifest.CreateElement('uses-feature')
            [void]$Feature.SetAttribute('name', $AndroidNamespace, $Name)
            [void]$Manifest.manifest.AppendChild($Feature)
        }
        [void]$Feature.SetAttribute('required', $AndroidNamespace, 'false')
    }
    [void]$Manifest.manifest.application.SetAttribute('banner', $AndroidNamespace, '@drawable/tv_banner')
    $Manifest.Save($ManifestPath)
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets/icons/android_tv_banner.png') -Destination (Join-Path $DrawableDir 'tv_banner.png') -Force
    [void][System.IO.Directory]::CreateDirectory((Join-Path $ProjectRoot '.artifacts'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $ProjectRoot 'build/android'))
    $Log = Join-Path $ProjectRoot '.artifacts/android-tv-build.log'
    $Process = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--path', ('"' + $ProjectRoot + '"'), '--export-debug', '"Android TV APK"', 'build/android/cats-vs-dogs-android-tv.apk') -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $Log -RedirectStandardError (Join-Path $ProjectRoot '.artifacts/android-tv-build-errors.log')
    $Process.WaitForExit()
    if ($Process.ExitCode -ne 0) { throw "Android TV export failed. See $Log" }
    Write-Host (Join-Path $ProjectRoot 'build/android/cats-vs-dogs-android-tv.apk')
} finally {
    $env:APPDATA = $PreviousAppData
}
