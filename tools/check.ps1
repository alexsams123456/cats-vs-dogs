[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ArtifactsPath = Join-Path $ProjectRoot '.artifacts'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $Candidates = @()
    if ($RequestedPath) {
        $Candidates = @($RequestedPath)
    } elseif ($env:GODOT_BIN) {
        $Candidates = @($env:GODOT_BIN)
    } else {
        $Candidates = @('godot', 'godot4', 'C:\GameDev\Godot\Godot.exe')
    }

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
        $Command = Get-Command -Name $Candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($Command) {
            return $Command.Source
        }
    }
    throw 'Godot was not found. Pass -GodotPath <path-to-exe>, set GODOT_BIN, or add godot/godot4 to PATH.'
}

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    $EngineLog = Join-Path $ArtifactsPath "$Name.log"
    $ConsoleLog = Join-Path $ArtifactsPath "$Name.console.log"
    # Truncate previous results so a stale error cannot fail a new run.
    [System.IO.File]::WriteAllText($EngineLog, '', $Utf8)
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $EnginePath
    # All arguments are controlled here; normalize paths to avoid trailing-backslash quoting.
    $StartInfo.Arguments = ($Arguments | ForEach-Object { '"' + $_.Replace('\', '/') + '"' }) -join ' '
    $StartInfo.WorkingDirectory = $ProjectRoot
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.StandardOutputEncoding = $Utf8
    $StartInfo.StandardErrorEncoding = $Utf8
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $StartInfo

    try {
        [void]$Process.Start()
        # Drain both pipes concurrently so verbose import output cannot deadlock.
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $TimedOut = -not $Process.WaitForExit($TimeoutSeconds * 1000)
        if ($TimedOut) {
            $Process.Kill()
        }
        $Process.WaitForExit()
        $ConsoleOutput = $OutputTask.GetAwaiter().GetResult() + "`n" + $ErrorTask.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($ConsoleLog, $ConsoleOutput, $Utf8)
        $CombinedOutput = $ConsoleOutput + "`n" + [System.IO.File]::ReadAllText($EngineLog, $Utf8)
        $CombinedOutput = $CombinedOutput -replace '\x1B\[[0-9;]*m', ''

        if ($TimedOut) {
            throw "$Name timed out after $TimeoutSeconds seconds. See $ConsoleLog and $EngineLog."
        }
        if ($Process.ExitCode -ne 0 -or $CombinedOutput -match '(?im)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):') {
            Write-Host $CombinedOutput.Trim()
            throw "$Name failed (exit code $($Process.ExitCode)). See $ConsoleLog and $EngineLog."
        }
        return $ConsoleOutput.Trim()
    } finally {
        $Process.Dispose()
    }
}

try {
    $EnginePath = Resolve-GodotExecutable -RequestedPath $GodotPath
    [void][System.IO.Directory]::CreateDirectory($ArtifactsPath)
    $ExpectedVersion = (Get-Content -LiteralPath (Join-Path $ProjectRoot '.godot-version') -Raw).Trim()
    $ActualVersion = Invoke-GodotCheck -Name 'version' -Arguments @('--headless', '--version')
    $VersionPattern = '^' + [regex]::Escape($ExpectedVersion) + '(?:\.|$)'
    if ($ActualVersion -notmatch $VersionPattern) {
        throw "Expected Godot $ExpectedVersion from .godot-version, found '$ActualVersion'. Use the pinned version."
    }
    Write-Host "Godot $ActualVersion"

    Write-Host 'Importing project and checking scripts...'
    $ImportArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'import.log'), '--editor', '--import', '--quit')
    [void](Invoke-GodotCheck -Name 'import' -Arguments $ImportArguments)

    Write-Host 'Running smoke tests...'
    $SmokeArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'smoke.log'), '--script', 'res://tests/smoke_test.gd')
    $SmokeOutput = Invoke-GodotCheck -Name 'smoke' -Arguments $SmokeArguments
    Write-Host $SmokeOutput
    Write-Host 'Running camera gesture tests...'
    $CameraGesturesArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'camera-gestures.log'), '--script', 'res://tests/camera_gestures_test.gd')
    $CameraGesturesOutput = Invoke-GodotCheck -Name 'camera-gestures' -Arguments $CameraGesturesArguments
    Write-Host $CameraGesturesOutput
    Write-Host 'Running roster and ability tests...'
    $RosterArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'roster.log'), '--script', 'res://tests/roster_test.gd')
    $RosterOutput = Invoke-GodotCheck -Name 'roster' -Arguments $RosterArguments
    Write-Host $RosterOutput
    Write-Host 'Running ten cat ability checks...'
    $CatAbilitiesArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'cat-abilities.log'), '--script', 'res://tests/cat_abilities_test.gd')
    $CatAbilitiesOutput = Invoke-GodotCheck -Name 'cat-abilities' -Arguments $CatAbilitiesArguments
    Write-Host $CatAbilitiesOutput
    Write-Host 'Running animation and audio checks...'
    $AnimationArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'animation.log'), '--script', 'res://tests/animation_test.gd')
    $AnimationOutput = Invoke-GodotCheck -Name 'animation' -Arguments $AnimationArguments
    Write-Host $AnimationOutput
    Write-Host 'Running dog defeat effect checks...'
    $DogDefeatArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'dog-defeat.log'), '--script', 'res://tests/dog_defeat_test.gd')
    $DogDefeatOutput = Invoke-GodotCheck -Name 'dog-defeat' -Arguments $DogDefeatArguments
    Write-Host $DogDefeatOutput
    Write-Host 'Running dog audio checks...'
    $DogAudioArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'dog-audio.log'), '--script', 'res://tests/dog_audio_test.gd')
    $DogAudioOutput = Invoke-GodotCheck -Name 'dog-audio' -Arguments $DogAudioArguments
    Write-Host $DogAudioOutput
    Write-Host 'Running level storage checks...'
    $LevelLibraryArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'level-library.log'), '--script', 'res://tests/level_library_test.gd')
    $LevelLibraryOutput = Invoke-GodotCheck -Name 'level-library' -Arguments $LevelLibraryArguments
    Write-Host $LevelLibraryOutput
    Write-Host 'Running level editor checks...'
    $EditorArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'editor.log'), '--script', 'res://tests/editor_test.gd')
    $EditorOutput = Invoke-GodotCheck -Name 'editor' -Arguments $EditorArguments
    Write-Host $EditorOutput
    Write-Host 'Running material and building checks...'
    $MaterialsArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'materials.log'), '--script', 'res://tests/materials_test.gd')
    $MaterialsOutput = Invoke-GodotCheck -Name 'materials' -Arguments $MaterialsArguments
    Write-Host $MaterialsOutput
    Write-Host 'Running kennel type checks...'
    $KennelTypesArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'kennel-types.log'), '--script', 'res://tests/kennel_types_test.gd')
    $KennelTypesOutput = Invoke-GodotCheck -Name 'kennel-types' -Arguments $KennelTypesArguments
    Write-Host $KennelTypesOutput
    foreach ($Suite in @('round_campaign', 'hud_help', 'result_feedback', 'aim_gesture', 'menu_reactions', 'touch_option_button', 'campaign', 'editor_recovery', 'biome', 'ambient_life', 'sun_observer', 'structural_load', 'world_audio', 'background_music', 'localization')) {
        Write-Host "Running $Suite checks..."
        $SuiteArguments = @('--headless', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath "$Suite.log"), '--script', "res://tests/${Suite}_test.gd")
        Write-Host (Invoke-GodotCheck -Name $Suite -Arguments $SuiteArguments)
    }
    Write-Host 'Replaying campaign physics routes...'
    $RoutesArguments = @('--headless', '--fixed-fps', '60', '--path', $ProjectRoot, '--log-file', (Join-Path $ArtifactsPath 'campaign-routes.log'), '--script', 'res://tools/solve_campaign.gd')
    Write-Host (Invoke-GodotCheck -Name 'campaign-routes' -Arguments $RoutesArguments)
    Write-Host "Checks passed. Logs: $ArtifactsPath"
    exit 0
} catch {
    Write-Host "CHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
