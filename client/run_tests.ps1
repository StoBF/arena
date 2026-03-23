# Run GUT unit tests for Arena client (PowerShell, Windows)
# Requires: Godot 4.x, GUT addon at addons/gut/ (install via Asset Library)
# Usage: .\run_tests.ps1
#        .\run_tests.ps1 -TestFile "test_websocket_manager_auction_events.gd"
#        .\run_tests.ps1 -GodotPath "C:\Godot\godot.exe"

param(
    [string]$TestFile = "",
    [string]$GodotPath = "godot",
    [string]$ProjectPath = $PSScriptRoot
)

$gutScript = Join-Path $ProjectPath "addons\gut\gut_cmdln.gd"
if (-not (Test-Path $gutScript)) {
    Write-Error "GUT not found at $gutScript. Install via Asset Library: Project -> Asset Library -> search 'GUT' -> Install"
    exit 1
}

$godotArgs = @(
    "-s",
    "--path", $ProjectPath,
    $gutScript,
    "-gdir", "res://tests/",
    "-gexit"
)

if ($TestFile -ne "") {
    $godotArgs += "-gfile"
    $godotArgs += $TestFile
}

$process = Start-Process -FilePath $GodotPath -ArgumentList $godotArgs -WorkingDirectory $ProjectPath -NoNewWindow -Wait -PassThru
exit $process.ExitCode
