param([ValidateSet('host','swiftshader_indirect')][string]$GpuMode = 'host')

# Dedicated empty-install UAT device. Never clones userdata or restarts another AVD.
$ErrorActionPreference = 'Stop'
$sdk = 'C:\Users\86137\AppData\Local\Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$avdRoot = 'E:\CodexToolchains\secureaccess-uat-avds'
$definition = Join-Path $avdRoot 'SecureAccess_UAT_M4.ini'
if (-not (Test-Path -LiteralPath $definition -PathType Leaf)) {
  throw 'Create the independent M4 AVD before starting it.'
}
$dataPath = (Get-Content -LiteralPath $definition | Where-Object { $_ -like 'path=*' }) -replace '^path=', ''
if ($dataPath -ne (Join-Path $avdRoot 'M4.avd') -or
    -not (Test-Path -LiteralPath (Join-Path $dataPath 'config.ini'))) {
  throw 'Unexpected M4 data directory.'
}
$active = @(Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^(emulator|qemu-system-x86_64.*)\.exe$' -and
  $_.CommandLine -match '(?:-avd\s+|@)SecureAccess_UAT_M4(?:\s|$)'
})
if ($active.Count) { throw 'M4 already running; no duplicate started.' }
if (((& $adb devices) -join "`n") -match '(?m)^emulator-5558\s') {
  throw 'Port 5558 already has a device.'
}
if (Get-NetTCPConnection -LocalPort 5558,5559 -ErrorAction SilentlyContinue) {
  throw 'M4 emulator ports are occupied.'
}
$process = Start-Process -FilePath (Join-Path $sdk 'emulator\emulator.exe') -ArgumentList @(
  '-avd','SecureAccess_UAT_M4','-port','5558','-gpu',$GpuMode,
  '-memory','2048','-cores','2','-no-window','-no-audio','-no-snapshot'
) -Environment @{ANDROID_AVD_HOME=$avdRoot} -WindowStyle Hidden -PassThru
[ordered]@{startedAt=[DateTimeOffset]::Now.ToString('o');avd='SecureAccess_UAT_M4';
  serial='emulator-5558';gpu=$GpuMode;launcherPid=$process.Id;dataWiped=$false;
  memoryMb=2048;cores=2;avdRoot=$avdRoot;bootVerified=$false
} | ConvertTo-Json
