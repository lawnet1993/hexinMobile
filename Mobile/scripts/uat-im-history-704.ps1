$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$serial = 'emulator-5556'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-batch-catchup-20260903'))
$journalPath = Join-Path $evidence 'history-native-704.json'
if (Test-Path -LiteralPath $journalPath) { throw 'History evidence already exists; do not replay automatically.' }
$wifi = (& $adb -s $serial shell settings get global wifi_on).Trim()
$data = (& $adb -s $serial shell settings get global mobile_data).Trim()
if ($wifi -notin @('0','1') -or $data -notin @('0','1')) { throw 'Unknown network state' }
$journal = [ordered]@{ startedAt=[DateTimeOffset]::Now.ToString('o'); serial=$serial; originalWifi=$wifi; originalData=$data; reachedFirst=$false; networkRestored=$false; observations=@() }
function Observe-History([string]$name, [int]$gestures) {
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial $serial -EvidenceDirectory $evidence -Name $name | Out-Null
  [xml]$ui = Get-Content -LiteralPath (Join-Path $evidence ($name + '.xml')) -Raw
  $labels = @($ui.SelectNodes('//node') | ForEach-Object { $_.'content-desc' })
  if (-not ($labels | Where-Object { $_ -match '^AI-UAT-20260903-IM-BATCH-701\s' })) { throw 'Not the expected test conversation' }
  # Flutter merges a cluster's sender/date and first message into one label.
  $numbers = @($labels | ForEach-Object { if ($_ -match '(?m)^AI-UAT-701-BATCH-(\d{4})\b') { [int]$Matches[1] } } | Sort-Object -Unique)
  if ($numbers.Count -eq 0) { throw 'No test messages in viewport' }
  $journal.observations += [ordered]@{at=[DateTimeOffset]::Now.ToString('o'); screenshot=$name+'.png'; gestures=$gestures; first=$numbers[0]; last=$numbers[-1]; visibleDistinct=$numbers.Count}
  $journal.reachedFirst = $numbers[0] -eq 1
  $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalPath
}
try {
  Observe-History 'm3-history-704-start' 0
  & $adb -s $serial shell svc wifi disable
  & $adb -s $serial shell svc data disable
  Start-Sleep -Milliseconds 700
  $network = (& $adb -s $serial shell dumpsys connectivity) -join "`n"
  $journal.offlineVerified = $network -match 'Active default network: none'
  if (-not $journal.offlineVerified) { throw 'Receiver still has an active default network' }
  for ($section=1; $section -le 12; $section++) {
    1..4 | ForEach-Object {
      & $adb -s $serial shell input swipe 540 500 540 2050 450
      Start-Sleep -Milliseconds 450
    }
    Observe-History ('m3-history-704-' + $section.ToString('00')) 4
    if ($journal.reachedFirst) { break }
  }
  if (-not $journal.reachedFirst) { throw 'First message not reached within bounded gestures' }
  1..3 | ForEach-Object { & $adb -s $serial shell input swipe 540 500 540 2050 450 }
  Observe-History 'm3-history-704-first-stable' 3
} finally {
  if ($wifi -eq '1') { & $adb -s $serial shell svc wifi enable }
  if ($data -eq '1') { & $adb -s $serial shell svc data enable }
  $journal.networkRestored = ((& $adb -s $serial shell settings get global wifi_on).Trim() -eq $wifi -and (& $adb -s $serial shell settings get global mobile_data).Trim() -eq $data)
  $journal.finishedAt = [DateTimeOffset]::Now.ToString('o')
  $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journalPath
}
$journal | ConvertTo-Json -Depth 5
