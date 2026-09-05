param(
  [Parameter(Mandatory)][string]$EvidenceDirectory,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name
)

# Read-only current M3 process; retain only explicit startup timing fields.
# Do not save raw logcat, debugger URLs, session state, or network payloads.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
$target = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Expected a project evidence directory.'
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
$output = Join-Path $target ($Name + '.json')
if (Test-Path -LiteralPath $output) { throw 'Choose a new evidence name.' }
$mobilePid = ((& $adb -s emulator-5556 shell pidof com.hexing.zhilian.hexing_terminal_mobile) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $mobilePid -notmatch '^\d+$') { throw 'Expected one active M3 app process.' }
$lines = @(& $adb -s emulator-5556 logcat -d -v threadtime --pid=$mobilePid)
if ($LASTEXITCODE -ne 0) { throw 'Current process log unavailable.' }

function Numeric-Tree($Value) {
  if ($null -eq $Value) { return $true }
  if ([Type]::GetTypeCode($Value.GetType()) -in @('Byte','SByte','Int16','UInt16',
      'Int32','UInt32','Int64','UInt64','Single','Double','Decimal')) { return $true }
  if ($Value -is [pscustomobject]) {
    foreach ($p in $Value.PSObject.Properties) {
      if ($p.Name -notin @('p50Micros','p95Micros','maxMicros','overBudgetCount',
          'buildMicros','rasterMicros','totalSpanMicros','vsyncOverheadMicros')) { return $false }
      if (-not (Numeric-Tree $p.Value)) { return $false }
    }
    return $true
  }
  return $false
}

$events = @()
$rejected = 0
foreach ($line in $lines) {
  $match = [regex]::Match($line, '\b(MOBILE_STARTUP_NATIVE|MOBILE_STARTUP_FRAMES|MOBILE_STARTUP)\s*:?\s*(\{.*\})\s*$')
  if (-not $match.Success) { continue }
  try { $data = $match.Groups[2].Value | ConvertFrom-Json } catch { $rejected++; continue }
  $kind = $match.Groups[1].Value
  $valid = $true
  if ($kind -eq 'MOBILE_STARTUP_FRAMES') {
    if ($data.reason -notin @('window_elapsed','sample_limit')) { $valid = $false }
    foreach ($p in $data.PSObject.Properties) {
      if ($p.Name -eq 'reason') { continue }
      if ($p.Name -notin @('elapsedMicros','sampleCount','maxSamples','invalidSamples',
          'refreshRateHz','frameBudgetMicros','build','raster','totalSpan','vsyncOverhead','firstFrame') -or
          -not (Numeric-Tree $p.Value)) { $valid = $false }
    }
  } else {
    if ($data.stage -notin @('onCreateEnter','onCreateReturn','configureEngineEnter',
        'pluginsRegistered','configureEngineReturn','firstFlutterUiDisplayed',
        'dartMain','tunnelRegistered','runAppReturned','firstFrameworkFrame')) { $valid = $false }
    foreach ($p in $data.PSObject.Properties) {
      if ($p.Name -eq 'stage') { continue }
      if ($p.Name -notin @('elapsedMs','elapsedMicros') -or -not (Numeric-Tree $p.Value)) { $valid = $false }
    }
  }
  if (-not $valid) { $rejected++; continue }
  $events += [ordered]@{
    deviceLogTime=[regex]::Match($line,'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+').Value
    kind=$kind
    data=$data
  }
}
$lines = $null
[ordered]@{
  checkedAt=[DateTimeOffset]::Now.ToString('o');serial='emulator-5556';pid=$mobilePid;
  rejectedTimingRecords=$rejected;events=$events;
  hasNativeFirstUi=@($events | Where-Object {$_.data.stage -eq 'firstFlutterUiDisplayed'}).Count -gt 0;
  hasFrameSummary=@($events | Where-Object {$_.kind -eq 'MOBILE_STARTUP_FRAMES'}).Count -gt 0
} | ConvertTo-Json -Depth 10 | Tee-Object -FilePath $output
