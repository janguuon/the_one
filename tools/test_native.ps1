[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [ValidateRange(3, 60)]
    [int]$BenchmarkSeconds = 5
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.5.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Pass -GodotPath with a Godot 4.5.2 Standard executable.' }
$runtimeRoot = Join-Path $projectRoot '.tools/runtime-data'
$outputRoot = Join-Path $runtimeRoot 'performance'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$failed = @()
try {
    $env:APPDATA = Join-Path $runtimeRoot 'roaming'
    $env:LOCALAPPDATA = Join-Path $runtimeRoot 'local'
    New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
    $importLog = Join-Path $outputRoot 'native-import.log'
    & $GodotPath --headless --path $projectRoot --editor --import --quit --log-file $importLog *> (Join-Path $outputRoot 'native-import.stdout.log')
    if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $importLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet)) { throw "Import failed: $importLog" }
    $renderLog = Join-Path $outputRoot 'art-render.log'
    & $GodotPath --path $projectRoot --script res://tests/art_render_tests.gd --log-file $renderLog
    if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $renderLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet)) { $failed += 'art_render_tests' }
    $closeLog = Join-Path $outputRoot 'native-close.log'
    & $GodotPath --path $projectRoot --script res://tests/close_lifecycle.gd --log-file $closeLog
    if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $closeLog -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING: ObjectDB instances leaked)' -Quiet)) { $failed += 'close_lifecycle' }
    foreach ($config in @(@(30,'1280x720'),@(60,'1280x720'),@(120,'1280x720'),@(60,'1024x768'),@(60,'1920x720'))) {
        $tag = "$($config[0])-$($config[1])"
        $engineLog = Join-Path $outputRoot "native-$tag.log"
        $report = (Join-Path $outputRoot "native-$tag.json").Replace('\','/')
        $snapshot = (Join-Path $outputRoot "native-$tag.png").Replace('\','/')
        & $GodotPath --path $projectRoot --script res://tests/presentation_benchmark.gd --log-file $engineLog -- "--fps=$($config[0])" "--size=$($config[1])" "--seconds=$BenchmarkSeconds" "--output=$report" "--snapshot=$snapshot"
        if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $engineLog -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING: ObjectDB instances leaked)' -Quiet)) { $failed += $tag }
    }
    # Include the P5 ground-pool/wave pattern as a separate effect-heavy sample.
    $stressLog = Join-Path $outputRoot 'native-last-horizon.log'
    $stressReport = (Join-Path $outputRoot 'native-last-horizon.json').Replace('\','/')
    & $GodotPath --path $projectRoot --script res://tests/presentation_benchmark.gd --log-file $stressLog -- '--fps=60' '--size=1280x720' '--seconds=8' '--pattern=last_horizon' "--output=$stressReport"
    if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $stressLog -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING: ObjectDB instances leaked)' -Quiet)) { $failed += 'last_horizon' }
}
finally {
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
}
if ($failed.Count) { throw "Native validation failed: $($failed -join ', ')" }
Write-Host "Native validation passed. Logs and captures: $outputRoot"
