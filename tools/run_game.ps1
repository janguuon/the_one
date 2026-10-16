[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [switch]$Editor,
    [switch]$Headless,
    [switch]$SkipImport,
    [Alias('Frames')]
    [int]$QuitAfter = 0,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArguments = @()
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

$engineArguments = @('--path', $projectRoot)
if ($Editor) { $engineArguments += '--editor' }
if ($Headless) { $engineArguments += '--headless' }
if ($QuitAfter -gt 0) { $engineArguments += @('--quit-after', "$QuitAfter") }
$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$runtimeRoot = Join-Path $projectRoot '.tools\runtime-data'
$runtimeRoaming = Join-Path $runtimeRoot 'roaming'
$runtimeLocal = Join-Path $runtimeRoot 'local'
New-Item -ItemType Directory -Path $runtimeRoaming, $runtimeLocal -Force | Out-Null
$engineLog = Join-Path $runtimeRoot 'game.log'
Set-Content -LiteralPath $engineLog -Value '' -Encoding utf8
$engineArguments += @('--log-file', $engineLog)
if ($GameArguments.Count -gt 0) { $engineArguments += @('--') + $GameArguments }
try {
    $env:APPDATA = $runtimeRoaming
    $env:LOCALAPPDATA = $runtimeLocal
    if (-not $Editor -and -not $SkipImport) {
        # Fresh source checkouts do not contain Godot's imported textures/audio.
        $importLog = Join-Path $runtimeRoot 'launcher-import.log'
        & $GodotPath --headless --path $projectRoot --editor --import --quit --log-file $importLog *> (Join-Path $runtimeRoot 'launcher-import.stdout.log')
        if (($LASTEXITCODE -ne 0) -or (Select-String -LiteralPath $importLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet)) {
            throw "Project import failed. See $importLog"
        }
    }
    & $GodotPath @engineArguments
    $taskExitCode = $LASTEXITCODE
    if (Select-String -LiteralPath $engineLog -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet) { $taskExitCode = 1 }
}
finally {
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
}
exit $taskExitCode
