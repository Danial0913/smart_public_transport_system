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
$runtimePython = $null
$pythonArguments = @()
$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
$installedPython = Get-Command python -ErrorAction SilentlyContinue
$bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if ($pythonLauncher) {
    $runtimePython = $pythonLauncher.Source
    $pythonArguments = @('-3')
} elseif ($installedPython -and $installedPython.Source -notlike '*WindowsApps*') {
    $runtimePython = $installedPython.Source
} elseif (Test-Path -LiteralPath $bundledPython) {
    $runtimePython = $bundledPython
} else {
    throw 'Install Python 3.10+ on this computer, then run backend/start.ps1 again.'
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.env')) -and -not $env:SMTP_USERNAME) {
    throw 'This computer has no recovery server configuration. Follow backend/README.md to use the shared HTTPS server or configure a private local .env.'
}
Push-Location $PSScriptRoot
try {
    & $runtimePython @pythonArguments app.py
} finally {
    Pop-Location
}
