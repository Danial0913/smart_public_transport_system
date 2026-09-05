$ErrorActionPreference = 'Stop'
$adbExecutable = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adbExecutable)) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adbCommand) {
        Write-Warning 'ADB not found. Set up Android SDK platform-tools to connect your phone.'
        return
    }
    $adbExecutable = $adbCommand.Source
}
$deviceLines = & $adbExecutable devices
if ($LASTEXITCODE -ne 0) { throw 'Could not list Android devices.' }
$connectedCount = 0
foreach ($line in $deviceLines) {
    if ($line -match '^(\S+)\s+device\s*$') {
        $deviceSerial = $Matches[1]
        & $adbExecutable -s $deviceSerial reverse tcp:8787 tcp:8787
        if ($LASTEXITCODE -ne 0) { throw "Could not connect recovery server to $deviceSerial." }
        Write-Output "Recovery server connected to Android device $deviceSerial on port 8787."
        $connectedCount++
    }
}
if ($connectedCount -eq 0) {
    Write-Warning 'No authorized Android devices found. Connect your phone, enable USB debugging, and accept its authorization prompt.'
}
