param([ValidateSet('host','swiftshader_indirect')][string]$GpuMode = 'host')

# Start only the independent UAT AVD, never another device, a duplicate process,
# or a wiped installation. GPU mode is a launch argument, not a global setting.
$ErrorActionPreference = 'Stop'
$sdk = 'C:\Users\86137\AppData\Local\Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$avdRoot = 'E:\CodexToolchains\secureaccess-uat-avds'
$avdIni = Join-Path $avdRoot 'SecureAccess_UAT_M3.ini'
if (-not (Test-Path -LiteralPath $avdIni -PathType Leaf)) {
  throw 'Existing M3 AVD definition is missing; never create a replacement.'
}
$dataPath = (Get-Content -LiteralPath $avdIni | Where-Object { $_ -like 'path=*' }) -replace '^path=', ''
if ($dataPath -ne (Join-Path $avdRoot 'M3.avd') -or
    -not (Test-Path -LiteralPath (Join-Path $dataPath 'config.ini'))) {
  throw 'Unexpected or missing existing M3 data directory.'
}
if (-not (Get-Command Start-Process).Parameters.ContainsKey('Environment')) {
  throw 'PowerShell 7.4 or newer is required for child-only AVD environment.'
}
$active = @(Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^(emulator|qemu-system-x86_64.*)\.exe$' -and
  $_.CommandLine -match '(?:-avd\s+|@)SecureAccess_UAT_M3(?:\s|$)'
})
if ($active.Count) { throw 'M3 is already running; no duplicate instance started.' }
$devices = (& $adb devices) -join "`n"
if ($devices -match '(?m)^emulator-5556\s') { throw 'Port 5556 already has a device.' }
$process = Start-Process -FilePath $emulator -ArgumentList @(
  '-avd','SecureAccess_UAT_M3','-port','5556','-gpu',$GpuMode,
  '-no-window','-no-audio','-no-snapshot'
) -Environment @{ANDROID_AVD_HOME=$avdRoot} -WindowStyle Hidden -PassThru
[ordered]@{startedAt=[DateTimeOffset]::Now.ToString('o');avd='SecureAccess_UAT_M3';
  serial='emulator-5556';gpu=$GpuMode;launcherPid=$process.Id;dataWiped=$false;
  avdRoot=$avdRoot;bootVerified=$false
} | ConvertTo-Json
