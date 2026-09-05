# One-shot native sends, only the existing two-person AI-UAT acceptance group.
# The receiver must stay outside chat. Never replay a journaled/uncertain click.
param([ValidateRange(0,99)][int]$ResumeAfter=0)
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-unread-navigation-20260903'))
$journal=Join-Path $evidence 'native-send.json'
$group='AI-UAT-20260903-IM-BATCH-701'
$conversation='245e652d-14be-4c29-a7aa-57b7659fa4e6'
if((Test-Path -LiteralPath $journal) -and $ResumeAfter -eq 0){throw 'Run exists. Inspect authoritative state; do not replay.'}
if($ResumeAfter -gt 0 -and -not(Test-Path -LiteralPath $journal)){throw 'No run to resume.'}
function Android([string]$Serial,[string[]]$ArgsList){
  $result=@(& $adb -s $Serial @ArgsList 2>&1)
  if($LASTEXITCODE -ne 0){throw 'Android command failed; stop without replay.'}
  return $result
}
function Ui([string]$Serial){
  $raw=(Android $Serial @('exec-out','uiautomator','dump','/dev/tty')) -join "`n"
  $start=$raw.IndexOf('<?xml');$end=$raw.LastIndexOf('</hierarchy>')
  if($start -lt 0 -or $end -lt $start){throw 'Fresh hierarchy unavailable.'}
  [xml]$xml=$raw.Substring($start,$end+'</hierarchy>'.Length-$start)
  if(-not $xml.SelectSingleNode('//node[@package="com.hexing.zhilian.hexing_terminal_mobile"]')){throw 'App not foreground.'}
  return $xml
}
function Sender{
  $xml=Ui emulator-5558
  if(-not $xml.SelectSingleNode('//node[@content-desc="群聊详情"]') -or
     -not $xml.SelectSingleNode("//node[starts-with(@content-desc,'$group') and contains(@content-desc,'2 位成员')]")){
    throw 'Sender is not in the dedicated two-person group.'
  }
  return $xml
}
function Receiver{
  $xml=Ui emulator-5556
  if($xml.SelectSingleNode('//node[@content-desc="群聊详情"]') -or
     $xml.SelectSingleNode('//node[@class="android.widget.EditText"]')){throw 'Receiver must remain outside chat/search.'}
  if(-not $xml.SelectSingleNode('//node[contains(@content-desc,"工作台")]')){throw 'Receiver shell not confirmed.'}
}
function Tap($Node){
  if($null -eq $Node){throw 'Control unavailable.'}
  $xy=@([regex]::Matches([string]$Node.bounds,'\d+')|ForEach-Object{[int]$_.Value})
  if($xy.Count -ne 4){throw 'Invalid bounds.'}
  Android emulator-5558 @('shell','input','tap',"$([int](($xy[0]+$xy[2])/2))","$([int](($xy[1]+$xy[3])/2))")|Out-Null
}
Receiver
$xml=Sender
$editor=$xml.SelectSingleNode('//node[@class="android.widget.EditText"]')
if($null -eq $editor -or $editor.text){throw 'Preserve nonempty composer.'}
$prefix='AI-UAT-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-UNREAD-'
$events=[Collections.Generic.List[object]]::new()
if($ResumeAfter -gt 0){
  $prior=Get-Content -LiteralPath $journal -Raw|ConvertFrom-Json
  $clicked=@($prior.events|Where-Object stage -eq 'clicked'|ForEach-Object{[int]$_.index})
  if($prior.events[-1].stage -ne 'clicked' -or $prior.events[-1].index -ne $ResumeAfter -or
     ($clicked -join ',') -ne ((1..$ResumeAfter) -join ',')){throw 'Ambiguous journal; no automatic recovery.'}
  foreach($serial in @('emulator-5556','emulator-5558')){
    $snapshot=Join-Path $evidence "$serial-resume-$ResumeAfter.json"
    if(Test-Path -LiteralPath $snapshot){throw 'Resume attempt already exists.'}
    py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial $serial --conversation-id $conversation --message-ledger --recipient-read > $snapshot
    if($LASTEXITCODE -ne 0){throw 'Live ledger unavailable.'}
    $doc=Get-Content -LiteralPath $snapshot -Raw|ConvertFrom-Json
    if($doc.messageLedger.Count -ne (510+$ResumeAfter) -or
       $doc.messageLedger[-1].sequence -ne (510+$ResumeAfter) -or
       @($doc.messageLedger|Where-Object local_status -ne 'sent').Count -ne 0){throw 'Ledger does not confirm all and only clicked messages.'}
    if($serial -eq 'emulator-5558' -and $doc.outbox.Count -ne 0){throw 'Pending sender queue; do not resume.'}
  }
  $prefix=$prior.prefix
  foreach($event in $prior.events){$events.Add($event)}
}
function Record([string]$Stage,[int]$Index=0){
  $events.Add(@{stage=$Stage;index=$Index;at=[DateTimeOffset]::Now.ToString('o')})
  @{conversationId=$conversation;prefix=$prefix;count=100;sender='emulator-5558';receiver='emulator-5556';events=$events.ToArray()}|
    ConvertTo-Json -Depth 5|Set-Content -LiteralPath $journal
}
Record $(if($ResumeAfter -gt 0){'resume-confirmed'}else{'start'}) $ResumeAfter
Tap $editor
for($i=$ResumeAfter+1;$i -le 100;$i++){
  $marker=$prefix+('{0:D4}' -f $i)
  Android emulator-5558 @('shell','input','text',$marker)|Out-Null
  $xml=Sender
  $editor=$xml.SelectSingleNode('//node[@class="android.widget.EditText"]')
  $send=$xml.SelectSingleNode('//node[@content-desc="发送"]')
  if($null -eq $editor -or $editor.text -cne $marker -or $null -eq $send -or $send.enabled -ne 'true'){
    throw 'Exact composer/target not confirmed. Preserve text; do not click/replay.'
  }
  Record 'about-to-click' $i
  Tap $send
  Record 'clicked' $i
  Start-Sleep -Milliseconds 300
  # A send can finish asynchronously after the tap. Wait for the composer to
  # clear before typing the next fixture; never infer delivery from this alone.
  $cleared=$false
  for($attempt=0;$attempt -lt 10;$attempt++){
    $ready=Sender
    $pending=$ready.SelectSingleNode('//node[@class="android.widget.EditText"]')
    if($null -ne $pending -and -not $pending.text){$cleared=$true;break}
    Start-Sleep -Milliseconds 300
  }
  if(-not $cleared){throw 'Previous composer did not clear; stop without next input.'}
  if($i % 10 -eq 0){Receiver;Write-Output "Native send clicks $i/100; awaiting ledger confirmation."}
}
$xml=Sender
if($xml.SelectSingleNode('//node[@class="android.widget.EditText"]').text){throw 'Final composer did not clear.'}
Receiver
Record 'clicks-complete'
