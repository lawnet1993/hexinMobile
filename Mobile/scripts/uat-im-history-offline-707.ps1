# Only scrolls existing test history. No sends, account changes or database writes.
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$serial='emulator-5556'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-history-session-20260903'))
$output=Join-Path $evidence 'offline-history.json'
if(Test-Path -LiteralPath $output){throw 'Evidence already exists; do not replay automatically'}
$wifi=((& $adb -s $serial shell settings get global wifi_on)-join '').Trim()
$data=((& $adb -s $serial shell settings get global mobile_data)-join '').Trim()
if($wifi -notin @('0','1') -or $data -notin @('0','1')){throw 'Unknown network state'}
$journal=[ordered]@{startedAt=[DateTimeOffset]::Now.ToString('o');serial=$serial;originalWifi=$wifi;originalData=$data;offlineVerified=$false;reachedFirst=$false;offlineReopenLatest=$false;networkRestored=$false;observations=@()}
function Capture([string]$name){
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial $serial -EvidenceDirectory $evidence -Name $name | Out-Null
  return [xml](Get-Content -LiteralPath (Join-Path $evidence ($name+'.xml')) -Raw)
}
function Observe([string]$name,[int]$gestures){
  $ui=Capture $name
  $labels=@($ui.SelectNodes('//node') | ForEach-Object {$_.'content-desc'})
  if(-not($labels | Where-Object {$_ -match '^AI-UAT-20260903-IM-BATCH-701\s'})){throw 'Wrong conversation'}
  $numbers=@($labels | ForEach-Object {if($_ -match '(?m)^AI-UAT-701-BATCH-(\d{4})\b'){[int]$Matches[1]}} | Sort-Object -Unique)
  if($numbers.Count -eq 0){throw 'No test messages visible'}
  $journal.observations += [ordered]@{at=[DateTimeOffset]::Now.ToString('o');screenshot=$name+'.png';gestures=$gestures;first=$numbers[0];last=$numbers[-1]}
  $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output
  return $numbers
}
try{
  $initial=Observe 'm3-offline-start' 0
  if($initial[-1] -ne 510){throw 'Must start at latest message'}
  & $adb -s $serial shell svc wifi disable
  & $adb -s $serial shell svc data disable
  Start-Sleep -Milliseconds 900
  $connectivity=(& $adb -s $serial shell dumpsys connectivity)-join "`n"
  $journal.offlineVerified=$connectivity -match 'Active default network: none'
  $connectivity=$null
  if(-not $journal.offlineVerified){throw 'Device still has an active default network'}
  for($section=1;$section -le 12;$section++){
    1..4 | ForEach-Object {& $adb -s $serial shell input swipe 540 500 540 2050 450; Start-Sleep -Milliseconds 450}
    $visible=Observe ('m3-offline-history-'+$section.ToString('00')) ($section*4)
    if($visible[0] -eq 1){$journal.reachedFirst=$true;break}
  }
  if(-not $journal.reachedFirst){throw 'Did not reach first message'}
  & $adb -s $serial shell input keyevent KEYCODE_BACK
  $ui=Capture 'm3-offline-list'
  $target=@($ui.SelectNodes('//node') | Where-Object {$_.'content-desc' -match 'AI-UAT-20260903-IM-BATCH-701' -and $_.clickable -eq 'true'})
  if($target.Count -ne 1 -or $target[0].bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'){throw 'Cannot find conversation'}
  $x=[int](([int]$Matches[1]+[int]$Matches[3])/2);$y=[int](([int]$Matches[2]+[int]$Matches[4])/2)
  & $adb -s $serial shell input tap $x $y
  $visible=Observe 'm3-offline-reopened' 0
  $journal.offlineReopenLatest=$visible[-1] -eq 510
  if(-not $journal.offlineReopenLatest){throw 'Offline reopen did not show latest message'}
}finally{
  if($wifi -eq '1'){& $adb -s $serial shell svc wifi enable}
  if($data -eq '1'){& $adb -s $serial shell svc data enable}
  $journal.networkRestored=((& $adb -s $serial shell settings get global wifi_on).Trim() -eq $wifi -and (& $adb -s $serial shell settings get global mobile_data).Trim() -eq $data)
  $journal.finishedAt=[DateTimeOffset]::Now.ToString('o')
  $journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output
}
$journal | ConvertTo-Json -Depth 5
