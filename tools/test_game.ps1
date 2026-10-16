[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$TestScript = 'res://tests/combat_tests.gd',
    [switch]$ImportOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = Join-Path $projectRoot '.tools\godot\Godot_v4.5.2-stable_win64_console.exe'
    if (-not (Test-Path -LiteralPath $GodotPath)) {
        $engineCommand = Get-Command godot -ErrorAction SilentlyContinue
        if (-not $engineCommand) { $engineCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
        if ($engineCommand) { $GodotPath = $engineCommand.Source }
    }
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot 4.5.2 was not found. Extract the official Windows x86_64 Standard archive to .tools/godot, or pass -GodotPath.'
}

$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$runtimeRoot = Join-Path $projectRoot '.tools\runtime-data'
$runtimeRoaming = Join-Path $runtimeRoot 'roaming'
$runtimeLocal = Join-Path $runtimeRoot 'local'
New-Item -ItemType Directory -Path $runtimeRoaming, $runtimeLocal -Force | Out-Null
try {
    $env:APPDATA = $runtimeRoaming
    $env:LOCALAPPDATA = $runtimeLocal
    Write-Host 'Importing project and validating scripts...'
    $importLog = Join-Path $runtimeRoot 'import.log'
    Set-Content -LiteralPath $importLog -Value '' -Encoding utf8
    & $GodotPath --headless --path $projectRoot --editor --import --quit --log-file $importLog
    $taskExitCode = $LASTEXITCODE
    if (Select-String -LiteralPath $importLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet) { $taskExitCode = 1 }
    if (($taskExitCode -eq 0) -and -not $ImportOnly) {
        $testFile = Join-Path $projectRoot ($TestScript -replace '^res://', '')
        if (-not (Test-Path -LiteralPath $testFile)) { throw "Test script does not exist: $TestScript" }
        Write-Host "Running $TestScript..."
        $testLog = Join-Path $runtimeRoot 'tests.log'
        Set-Content -LiteralPath $testLog -Value '' -Encoding utf8
        & $GodotPath --headless --path $projectRoot --script $TestScript --log-file $testLog
        $taskExitCode = $LASTEXITCODE
        if (Select-String -LiteralPath $testLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet) { $taskExitCode = 1 }
    }
}
finally {
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
}
exit $taskExitCode
