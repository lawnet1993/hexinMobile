# A bounded self-offline check; no message is sent and M3 network is restored.
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\message-list-presence-refresh-20260903'))
$journal=Join-Path $evidence 'observer-offline-run.json'
if(Test-Path -LiteralPath $journal){throw 'Existing run must be inspected before retry.'}
function Android([string[]]$Arguments){
  $result=@(& $adb -s emulator-5556 @Arguments 2>&1)
  if($LASTEXITCODE -ne 0){throw 'Android operation failed.'}
  return $result
}
$wifi=((Android @('shell','settings','get','global','wifi_on')) -join '').Trim()
$data=((Android @('shell','settings','get','global','mobile_data')) -join '').Trim()
if($wifi -notin @('0','1') -or $data -notin @('0','1')){throw 'Unknown network state.'}
$events=[Collections.Generic.List[object]]::new()
function SaveJournal { $events.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal }
function Sample([string]$name){
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name $name | Out-Null
  [xml]$ui=Get-Content (Join-Path $evidence "$name.xml") -Raw
  $rows=$ui.SelectNodes('//node[contains(@content-desc,"Test Terminal 04") and contains(@content-desc,"单聊，")]')
  if($rows.Count -ne 1 -or -not $ui.SelectSingleNode('//node[@content-desc="消息"]')){throw 'Verified M3 list no longer visible.'}
  $label=[string]$rows[0].'content-desc'
  $status=if($label.StartsWith('单聊，对方在线')){'online'}elseif($label.StartsWith('单聊，对方离线')){'offline'}else{'unknown'}
  $record=@{step=$name;at=[DateTimeOffset]::Now.ToString('o');status=$status}
  $events.Add($record); SaveJournal; $record | ConvertTo-Json -Compress
}
try{
  Sample 'observer-before'
  Android @('shell','svc','wifi','disable') | Out-Null
  Android @('shell','svc','data','disable') | Out-Null
  Start-Sleep -Milliseconds 800
  $connectivity=(Android @('shell','dumpsys','connectivity')) -join "`n"
  if($connectivity -notmatch 'Active default network: none'){throw 'M3 offline state not confirmed.'}
  $connectivity=$null
  $events.Add(@{step='observer-network-off';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
  Start-Sleep -Seconds 40
  Sample 'observer-offline-40'
}finally{
  $wifiAction=if($wifi -eq '1'){'enable'}else{'disable'}
  $dataAction=if($data -eq '1'){'enable'}else{'disable'}
  Android @('shell','svc','wifi',$wifiAction) | Out-Null
  Android @('shell','svc','data',$dataAction) | Out-Null
  $events.Add(@{step='observer-network-restored';at=[DateTimeOffset]::Now.ToString('o');
    wifi=((Android @('shell','settings','get','global','wifi_on')) -join '').Trim();
    mobileData=((Android @('shell','settings','get','global','mobile_data')) -join '').Trim()}); SaveJournal
}
Start-Sleep -Seconds 35
Sample 'observer-reconnected-35'
$events.Add(@{step='finished';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
