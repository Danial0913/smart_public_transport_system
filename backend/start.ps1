$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'connect_android.ps1')
$serviceIsRunning = $false
try {
    $recoveryHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/health' -TimeoutSec 3
    $serviceIsRunning = $recoveryHealth.status -eq 'ok'
} catch {
    # Start a new server below if the health endpoint is unavailable.
}
if ($serviceIsRunning) {
    Write-Output 'Recovery server is already running. Android USB connections have been refreshed.'
    return
}
$runtimePython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $runtimePython)) {
    throw 'Python runtime not found. Install Python 3.10+ and run: python backend/app.py'
}
Push-Location $PSScriptRoot
try {
    & $runtimePython app.py
} finally {
    Pop-Location
}
