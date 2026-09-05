param([ValidateSet('online','offline')][string]$Phase='online')
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-composer-20260903'))
$journal=Join-Path $evidence "native-$Phase.json"
$group='AI-UAT-20260903-IM-BATCH-701'
$conversation='245e652d-14be-4c29-a7aa-57b7659fa4e6'
if(Test-Path -LiteralPath $journal){throw 'Phase already attempted. Inspect the journal and live ledger; never replay clicks.'}
function Android([string]$Serial,[string[]]$Arguments){
  $result=@(& $adb -s $Serial @Arguments 2>&1)
  if($LASTEXITCODE -ne 0){throw 'Android operation failed; stop without replay.'}
  return $result
}
function Ui([string]$Serial){
  $raw=(Android $Serial @('exec-out','uiautomator','dump','/dev/tty')) -join "`n"
  $start=$raw.IndexOf('<?xml');$end=$raw.LastIndexOf('</hierarchy>')
  if($start -lt 0 -or $end -lt $start){throw 'Fresh hierarchy unavailable.'}
  [xml]$xml=$raw.Substring($start,$end+'</hierarchy>'.Length-$start)
  if(-not $xml.SelectSingleNode('//node[@package="com.hexing.zhilian.hexing_terminal_mobile"]')){throw 'App is not foreground.'}
  return $xml
}
function Point($Node){
  if($null -eq $Node){throw 'Control unavailable.'}
  $bounds=@([regex]::Matches([string]$Node.bounds,'\d+')|ForEach-Object{[int]$_.Value})
  if($bounds.Count -ne 4){throw 'Invalid bounds.'}
  return @([int](($bounds[0]+$bounds[2])/2),[int](($bounds[1]+$bounds[3])/2))
}
function Tap([string]$Serial,$Node){
  $p=Point $Node
  Android $Serial @('shell','input','tap',"$($p[0])","$($p[1])")|Out-Null
}
function IsGroup($Xml){
  return ($null -ne $Xml.SelectSingleNode('//node[@content-desc="群聊详情"]') -and
    $null -ne $Xml.SelectSingleNode("//node[starts-with(@content-desc,'$group') and contains(@content-desc,'2 位成员')]"))
}
function OpenGroup([string]$Serial){
  $xml=Ui $Serial
  if(IsGroup $xml){return}
  if($xml.SelectSingleNode('//node[@class="android.widget.EditText" and string-length(@text)>0]') -or
     $xml.SelectSingleNode('//node[@content-desc="群聊详情"]')){throw 'Unexpected conversation/input; preserve it.'}
  Tap $Serial ($xml.SelectSingleNode('//node[contains(@content-desc,"消息") and contains(@content-desc,"第 2 个标签")]'))
  $xml=Ui $Serial
  Tap $Serial ($xml.SelectSingleNode("//node[contains(@content-desc,'$group') and @clickable='true']"))
  $xml=Ui $Serial
  if(-not(IsGroup $xml)){throw 'Dedicated test group not confirmed.'}
}
function Sender{
  $xml=Ui emulator-5558
  if(-not(IsGroup $xml)){throw 'Wrong sender conversation.'}
  return $xml
}
function Capture([string]$Serial,[string]$Name){
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial $Serial -EvidenceDirectory $evidence -Name $Name | Out-Null
}
function Snapshot([string]$Serial,[string]$Name){
  $file=Join-Path $evidence "$Name.json"
  if(Test-Path -LiteralPath $file){throw 'Snapshot exists.'}
  py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial $Serial --conversation-id $conversation --message-ledger --recipient-read > $file
  if($LASTEXITCODE -ne 0){throw 'Read-only ledger unavailable.'}
  return Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
}
OpenGroup emulator-5556
OpenGroup emulator-5558
$xml=Sender
$editor=$xml.SelectSingleNode('//node[@class="android.widget.EditText"]')
if($null -eq $editor -or $editor.text){throw 'Preserve nonempty composer.'}
$prefix='AI-UAT-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-COMPOSER-'
$first=1
if($Phase -eq 'offline'){
  $previous=Get-Content (Join-Path $evidence 'native-online.json') -Raw|ConvertFrom-Json
  if($previous.events[-1].stage -ne 'phase-complete'){throw 'Online phase must be verified first.'}
  $prefix=$previous.prefix;$first=3
}
$events=[Collections.Generic.List[object]]::new()
function Record([string]$Stage,$Detail=$null){
  $events.Add(@{stage=$Stage;detail=$Detail;at=[DateTimeOffset]::Now.ToString('o')})
  @{phase=$Phase;prefix=$prefix;conversationId=$conversation;events=$events.ToArray()}|
    ConvertTo-Json -Depth 8|Set-Content -LiteralPath $journal
}
$wifi=((Android emulator-5558 @('shell','settings','get','global','wifi_on')) -join '').Trim()
$data=((Android emulator-5558 @('shell','settings','get','global','mobile_data')) -join '').Trim()
if($wifi -ne '1' -or $data -ne '1'){throw 'Expected both radios enabled before test.'}
Record 'start' @{wifi=$wifi;data=$data}
try {
  if($Phase -eq 'offline'){
    $baseline=Snapshot emulator-5558 'm4-offline-baseline'
    if($baseline.outbox.Count -ne 0 -or $baseline.messageLedger.Count -ne 612){throw 'Unsettled online queue; do not continue.'}
    Android emulator-5558 @('shell','svc','wifi','disable')|Out-Null
    Android emulator-5558 @('shell','svc','data','disable')|Out-Null
    Record 'radios-disabled'
  }
  Tap emulator-5558 $editor
  $a=$prefix+('{0:D2}' -f $first)
  $b=$prefix+('{0:D2}' -f ($first+1))
  Android emulator-5558 @('shell','input','text',$a)|Out-Null
  $xml=Sender
  if($xml.SelectSingleNode('//node[@class="android.widget.EditText"]').text -cne $a){throw 'First input mismatch.'}
  $send=$xml.SelectSingleNode('//node[@content-desc="发送" and @enabled="true"]')
  $point=Point $send
  Record 'about-to-send-and-type' @{first=$first;next=$first+1}
  # Same device shell, no hierarchy dump or arbitrary delay between send A and
  # typing B. Markers contain only ASCII letters/digits/hyphens, never secrets.
  Android emulator-5558 @('shell',"input tap $($point[0]) $($point[1]); input text $b")|Out-Null
  Record 'sent-and-typed'
  Capture emulator-5558 "m4-$Phase-next-draft"
  $xml=Sender
  if($xml.SelectSingleNode('//node[@class="android.widget.EditText"]').text -cne $b){throw 'Next draft was altered. Preserve it; do not send or replay.'}
  Record 'next-draft-preserved' @{exact=$true}
  Record 'about-to-send-second'
  Tap emulator-5558 ($xml.SelectSingleNode('//node[@content-desc="发送" and @enabled="true"]'))
  Record 'second-clicked'
  $xml=Sender
  if($xml.SelectSingleNode('//node[@class="android.widget.EditText"]').text){throw 'Composer did not clear.'}
  Android emulator-5558 @('shell','input','keyevent','KEYCODE_BACK')|Out-Null
  Capture emulator-5558 "m4-$Phase-sent"
  if($Phase -eq 'offline'){
    $queued=Snapshot emulator-5558 'm4-offline-queued'
    if($queued.outbox.Count -ne 2 -or $queued.messageLedger.Count -ne 614){throw 'Offline local ledger mismatch.'}
    Record 'two-messages-durable' @{outbox=$queued.outbox.Count;ledger=$queued.messageLedger.Count}
  }
  Record 'phase-complete'
} finally {
  if($Phase -eq 'offline'){
    Android emulator-5558 @('shell','svc','wifi','enable')|Out-Null
    Android emulator-5558 @('shell','svc','data','enable')|Out-Null
    Record 'network-restored'
  }
}
Write-Output "$Phase pair executed; verify both device ledgers before acceptance."
