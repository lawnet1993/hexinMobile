# Observes the real M3 list without opening a conversation or refreshing it.
# Only independent M4 networking is changed, and its initial state is restored.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\message-list-presence-refresh-20260903'))
$journal = Join-Path $evidence 'presence-run.json'
if (Test-Path -LiteralPath $journal) { throw 'Existing run found. Inspect its live process/evidence instead of restarting.' }
function Android([string]$Serial, [string[]]$Arguments) {
  $result = @(& $adb -s $Serial @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android observation operation failed.' }
  return $result
}
$initialWifi = ((Android emulator-5558 @('shell','settings','get','global','wifi_on')) -join '').Trim()
$initialData = ((Android emulator-5558 @('shell','settings','get','global','mobile_data')) -join '').Trim()
if ($initialWifi -notin @('0','1') -or $initialData -notin @('0','1')) { throw 'Network state unavailable.' }
$samples = [Collections.Generic.List[object]]::new()
$clock = [Diagnostics.Stopwatch]::StartNew()
function SaveJournal {
  [ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');observer='emulator-5556/test03';
    peer='emulator-5558/test04';samples=$samples.ToArray()
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $journal
}
function Sample([string]$Name) {
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name $Name | Out-Null
  [xml]$ui = Get-Content (Join-Path $evidence "$Name.xml") -Raw
  if (-not $ui.SelectSingleNode('//node[@content-desc="消息"]')) { throw 'M3 is no longer on the verified message list.' }
  $rows = $ui.SelectNodes('//node[contains(@content-desc,"Test Terminal 04") and contains(@content-desc,"单聊，")]')
  if ($rows.Count -ne 1) { throw 'Expected unique Test Terminal 04 direct row.' }
  $label = [string]$rows[0].'content-desc'
  $status = if ($label.StartsWith('单聊，对方在线')) {'online'} elseif ($label.StartsWith('单聊，对方离线')) {'offline'} else {'unknown'}
  $record = [ordered]@{step=$Name;at=[DateTimeOffset]::Now.ToString('o');elapsedSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,1);status=$status}
  $samples.Add($record); SaveJournal
  Write-Output ($record | ConvertTo-Json -Compress)
}
try {
  Sample 'baseline-00'
  for ($i=1; $i -le 3; $i++) {
    Start-Sleep -Seconds 30
    Sample "baseline-$($i*30)"
  }
  Android emulator-5558 @('shell','svc','wifi','disable') | Out-Null
  Android emulator-5558 @('shell','svc','data','disable') | Out-Null
  Start-Sleep -Milliseconds 800
  $connectivity = (Android emulator-5558 @('shell','dumpsys','connectivity')) -join "`n"
  if ($connectivity -notmatch 'Active default network: none') { throw 'M4 is not offline.' }
  $connectivity = $null
  $samples.Add(@{step='peer-network-off';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
  for ($i=1; $i -le 5; $i++) {
    Start-Sleep -Seconds 30
    Sample "peer-offline-$($i*30)"
    if ($samples[$samples.Count-1].status -eq 'offline') { break }
  }
} finally {
  $wifi = if ($initialWifi -eq '1') {'enable'} else {'disable'}
  $data = if ($initialData -eq '1') {'enable'} else {'disable'}
  Android emulator-5558 @('shell','svc','wifi',$wifi) | Out-Null
  Android emulator-5558 @('shell','svc','data',$data) | Out-Null
  $samples.Add(@{step='peer-network-restored';at=[DateTimeOffset]::Now.ToString('o');
    wifi=((Android emulator-5558 @('shell','settings','get','global','wifi_on')) -join '').Trim();
    mobileData=((Android emulator-5558 @('shell','settings','get','global','mobile_data')) -join '').Trim()}); SaveJournal
}
for ($i=1; $i -le 4; $i++) {
  Start-Sleep -Seconds 30
  Sample "peer-reconnected-$($i*30)"
  if ($samples[$samples.Count-1].status -eq 'online') { break }
}
$samples.Add(@{step='finished';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
