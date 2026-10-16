[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [switch]$SkipPlaythrough
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.5.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Pass -GodotPath with a Godot 4.5.2 Standard executable.'
}
$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$runtimeRoot = Join-Path $projectRoot '.tools/runtime-data'
$validationRoot = Join-Path $runtimeRoot 'validation'
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
$failed = @()
try {
    $env:APPDATA = Join-Path $runtimeRoot 'roaming'
    $env:LOCALAPPDATA = Join-Path $runtimeRoot 'local'
    New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
    $importLog = Join-Path $validationRoot 'import.log'
    & $GodotPath --headless --path $projectRoot --editor --import --quit --log-file $importLog *> (Join-Path $validationRoot 'import.stdout.log')
    if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $importLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet)) {
        throw "Project import failed. See $importLog"
    }
    $scripts = @('combat_tests', 'm3_tests', 'scene_integration', 'pattern_safety', 'm4_combat_tests', 'profile_tests', 'm4_review_tests', 'm4_integration', 'm4_ui_boundary', 'art_tests', 'geometry_render_tests', 'audio_tests', 'm5_ui_tests', 'm5_combat_tests', 'close_lifecycle', 'difficulty_metrics')
    if (-not $SkipPlaythrough) {
        $scripts += @('playthrough', 'm3_playthrough', 'm4_playthrough', 'device_playthrough', 'balance_benchmark')
    }
    foreach ($script in $scripts) {
        $engineLog = Join-Path $validationRoot "$script.log"
        $outputLog = Join-Path $validationRoot "$script.stdout.log"
        & $GodotPath --headless --path $projectRoot --script "res://tests/$script.gd" --log-file $engineLog *> $outputLog
        $engineExit = $LASTEXITCODE
        $hasError = Select-String -LiteralPath $engineLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet
        Get-Content -LiteralPath $outputLog -Tail 6 | Write-Host
        if (($engineExit -ne 0) -or $hasError) {
            $failed += $script
            Write-Host "FAILED: $script (exit $engineExit)"
        } else {
            Write-Host "OK: $script"
        }
    }
}
finally {
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
}
if ($failed.Count -gt 0) {
    throw "Validation failed: $($failed -join ', '). Logs: $validationRoot"
}
Write-Host "All validation scripts passed. Logs: $validationRoot"
