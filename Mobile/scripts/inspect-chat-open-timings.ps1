param(
  [Parameter(Mandatory)][string]$EvidenceDirectory,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name,
  [ValidatePattern('^[a-zA-Z0-9._:-]+$')][string]$Serial = 'emulator-5556'
)
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
$target=[IO.Path]::GetFullPath($EvidenceDirectory)
if (-not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Expected project evidence child directory' }
$output=Join-Path $target ($Name+'.json')
if (Test-Path -LiteralPath $output) { throw 'Choose a new evidence name' }
$mobilePid=((& $adb -s $Serial shell pidof com.hexing.zhilian.hexing_terminal_mobile) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $mobilePid -notmatch '^\d+$') { throw 'Expected current mobile app process' }
# Raw logcat is never persisted. Reject unknown fields, arbitrary strings and IDs.
$raw=@(& $adb -s $Serial logcat -d -v threadtime --pid=$mobilePid)
if ($LASTEXITCODE -ne 0) { throw 'Current process log unavailable' }
function NumericTree($value) {
  if ($null -eq $value) { return $true }
  if ([Type]::GetTypeCode($value.GetType()) -in @('Byte','SByte','Int16','UInt16','Int32','UInt32','Int64','UInt64','Single','Double','Decimal')) { return $true }
  if ($value -isnot [pscustomobject]) { return $false }
  foreach ($p in $value.PSObject.Properties) {
    if ($p.Name -notin @('tap','keyboardHidden','navigationRequested','routeMounted','routeFrame','messagesAvailable','latestMessageLaidOut',
      'sampleCount','maxSamples','invalidSamples','refreshRateHz','frameBudgetMicros','build','raster','totalSpan','vsyncOverhead','firstFrame',
      'p50Micros','p95Micros','maxMicros','overBudgetCount','buildMicros','rasterMicros','totalSpanMicros','vsyncOverheadMicros') -or -not (NumericTree $p.Value)) { return $false }
  }
  return $true
}
$events=@();$rejected=0
foreach ($line in $raw) {
  $match=[regex]::Match($line,'\bMOBILE_CHAT_OPEN\s+(\{.*\})\s*$')
  if (-not $match.Success) { continue }
  try { $data=$match.Groups[1].Value | ConvertFrom-Json } catch { $rejected++;continue }
  $valid=$data.reason -in @('windowElapsed','routeClosed','superseded')
  foreach ($p in $data.PSObject.Properties) {
    if ($p.Name -eq 'reason') { continue }
    if ($p.Name -eq 'cacheHit') { if ($null -ne $p.Value -and $p.Value -isnot [bool]) { $valid=$false };continue }
    if ($p.Name -notin @('sampleId','elapsedMicros','messageCount','stagesMicros','frames') -or -not (NumericTree $p.Value)) { $valid=$false }
  }
  if (-not $valid) { $rejected++;continue }
  $events += [ordered]@{deviceLogTime=[regex]::Match($line,'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+').Value;data=$data}
}
$raw=$null
New-Item -ItemType Directory -Path $target -Force | Out-Null
[ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');serial=$Serial;pid=$mobilePid;rejected=$rejected;events=$events} |
  ConvertTo-Json -Depth 10 | Tee-Object -FilePath $output
