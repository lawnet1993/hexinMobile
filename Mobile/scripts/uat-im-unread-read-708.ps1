# Native navigation only; metadata snapshots never mutate the device database.
param([switch]$Recheck,[switch]$ContinueScroll)
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-unread-navigation-20260903'))
$output=Join-Path $evidence $(if($Recheck){'native-recheck-scroll.json'}else{'native-scroll.json'})
if($ContinueScroll -and -not $Recheck){throw 'Only the inspected recheck may continue.'}
if((Test-Path -LiteralPath $output) -and -not $ContinueScroll){throw 'Read run exists; inspect current state instead of replaying.'}
$send=Get-Content (Join-Path $evidence 'native-send.json') -Raw|ConvertFrom-Json
if($send.events[-1].stage -ne 'clicks-complete'){throw 'Sender has not completed.'}
$unread=Get-Content (Join-Path $evidence $(if($Recheck){'m3-recheck-baseline.json'}else{'m3-unread.json'})) -Raw|ConvertFrom-Json
$projection=@($unread.groupProjections|Where-Object account_id -eq 'c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc')
$baseline=if($Recheck){550}else{510}
$expectedFirst=$baseline-510+1
if($projection.Count -ne 1 -or $projection[0].unread_count -ne (610-$baseline) -or $projection[0].last_read_sequence -ne $baseline){throw 'Expected unread baseline missing.'}
$observations=[Collections.Generic.List[object]]::new()
if($ContinueScroll){
  foreach($observation in (Get-Content -LiteralPath $output -Raw|ConvertFrom-Json)){$observations.Add($observation)}
}
function Android([string[]]$ArgsList){
  & $adb -s emulator-5556 @ArgsList|Out-Null
  if($LASTEXITCODE -ne 0){throw 'Android operation failed.'}
}
function Capture([string]$Name){
  if($Recheck){$Name=$Name -replace '^m3-','m3-recheck-'}
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name $Name|Out-Null
  return [xml](Get-Content (Join-Path $evidence ($Name+'.xml')) -Raw)
}
function Tap($Node){
  if($null -eq $Node){throw 'Required navigation target missing.'}
  $xy=@([regex]::Matches([string]$Node.bounds,'\d+')|ForEach-Object{[int]$_.Value})
  if($xy.Count -ne 4){throw 'Invalid control bounds.'}
  Android @('shell','input','tap',"$([int](($xy[0]+$xy[2])/2))","$([int](($xy[1]+$xy[3])/2))")
}
function Observe([string]$Name,[int]$Gestures){
  $ui=Capture $Name
  if(-not $ui.SelectSingleNode('//node[starts-with(@content-desc,"AI-UAT-20260903-IM-BATCH-701")]')){throw 'Wrong conversation.'}
  $pattern=[regex]::Escape($send.prefix)+'(\d{4})\b'
  $numbers=@($ui.SelectNodes('//node')|ForEach-Object{
    $label=[string]$_.'content-desc'
    if($label -match $pattern){[int]$Matches[1]}
  }|Sort-Object -Unique)
  if($numbers.Count -eq 0){throw 'No new test messages visible.'}
  $savedName=if($Recheck){$Name -replace '^m3-','m3-recheck-'}else{$Name}
  $observations.Add(@{screenshot=$savedName+'.png';gestures=$Gestures;first=$numbers[0];last=$numbers[-1];at=[DateTimeOffset]::Now.ToString('o')})
  $observations.ToArray()|ConvertTo-Json -Depth 4 -AsArray|Set-Content -LiteralPath $output
  return $numbers
}
function Snapshot([string]$Serial,[string]$Name){
  if($Recheck){$Name=$Name -replace '^(m[34])-','$1-recheck-'}
  py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial $Serial --conversation-id 245e652d-14be-4c29-a7aa-57b7659fa4e6 --message-ledger --recipient-read > (Join-Path $evidence ($Name+'.json'))
  if($LASTEXITCODE -ne 0){throw 'Read-only snapshot failed.'}
}
if(-not $ContinueScroll){
$workbenchUi=Capture 'm3-before-open'
if(-not $workbenchUi.SelectSingleNode('//node[contains(@content-desc,"Test Terminal 03")]')){throw 'Receiver identity not confirmed.'}
Tap ($workbenchUi.SelectSingleNode('//node[contains(@content-desc,"消息") and contains(@content-desc,"第 2 个标签")]'))
$list=Capture 'm3-unread-list'
Tap ($list.SelectSingleNode('//node[@clickable="true" and contains(@content-desc,"AI-UAT-20260903-IM-BATCH-701")]'))
Start-Sleep -Milliseconds 900
$first=Observe 'm3-first-unread' 0
if($first -notcontains $expectedFirst -or $first[0] -lt ($expectedFirst-1) -or $first[-1] -ge ($expectedFirst+39)){throw 'Initial unread position incorrect; stop before scrolling.'}
Start-Sleep -Milliseconds 1200
Snapshot emulator-5556 'm3-partial'
Snapshot emulator-5558 'm4-partial'
}else{
  $visible=Observe 'm3-before-scroll' 0
  if($visible -notcontains $expectedFirst){throw 'Receiver no longer at inspected unread start.'}
}
$partial=Get-Content (Join-Path $evidence $(if($Recheck){'m3-recheck-partial.json'}else{'m3-partial.json'})) -Raw|ConvertFrom-Json
$read=$partial.groupProjections[0].last_read_sequence
if($read -le $baseline -or $read -ge ($baseline+40)){throw 'Initial visible read boundary incorrect.'}
Write-Output "First unread visible; persisted read sequence $read, before latest 610."
for($section=1;$section -le 15;$section++){
  for($step=0;$step -lt 2;$step++){
    Android @('shell','input','swipe','540','1940','540','580','450')
    Start-Sleep -Milliseconds 500
  }
  $visible=Observe ('m3-forward-'+$section.ToString('00')) ($section*2)
  if($visible[-1] -eq 100){break}
}
if($visible[-1] -ne 100){throw 'Forward gestures did not reach latest.'}
# Move the last partially exposed bubble fully into view before the final read.
Android @('shell','input','swipe','540','1940','540','1580','350')
Start-Sleep -Milliseconds 500
$null=Observe 'm3-latest' ($section*2+1)
Start-Sleep -Milliseconds 1200
Snapshot emulator-5556 'm3-after'
Snapshot emulator-5558 'm4-after'
Write-Output "Reached final message after $($section*2+1) forward gestures."
