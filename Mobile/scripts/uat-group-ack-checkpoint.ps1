# One native send on the independent M4, then kill M3 only at the verified
# committed-before-ACK checkpoint. Never clears data or writes a database.
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-group-ack-crash-20260903'))
$run=Get-Content (Join-Path $evidence 'run-config.json') -Raw | ConvertFrom-Json
$journal=Join-Path $evidence 'send-and-kill.json'
if(Test-Path -LiteralPath $journal){throw 'Existing send journal: inspect evidence; do not resend.'}
if($run.marker -notmatch '^AI-UAT-\d{8}-\d{6}-GROUP-ACK-CRASH$' -or
   $run.conversationId -ne '95e704ae-0e34-4f56-87db-038526796d6c') {throw 'Unexpected test scope.'}
function Android([string]$Serial,[string[]]$Arguments){
  $result=@(& $adb -s $Serial @Arguments 2>&1)
  if($LASTEXITCODE -ne 0){throw 'Android operation failed.'}
  return $result
}
$mobilePid=((Android emulator-5556 @('shell','pidof','com.hexing.zhilian.hexing_terminal_mobile')) -join '').Trim()
if($mobilePid -notmatch '^\d+$'){throw 'No unique M3 app process.'}
& (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5558 -EvidenceDirectory $evidence -Name m4-send-guard | Out-Null
[xml]$ui=Get-Content (Join-Path $evidence 'm4-send-guard.xml') -Raw
if(-not $ui.SelectSingleNode('//node[contains(@content-desc,"AI-UAT-20260903-050600-M3-M4-GROUP") and contains(@content-desc,"位成员")]')){throw 'Wrong group.'}
$editor=$ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
if($editor.text -ne ('@Test Terminal 03 '+$run.marker)){throw 'Expected one native self-mention and exact marker.'}
$send=$ui.SelectSingleNode('//node[@content-desc="发送" and @enabled="true"]')
if($null -eq $send){throw 'Send unavailable.'}
$coords=@([regex]::Matches($send.bounds,'\d+') | ForEach-Object {[int]$_.Value})
if($coords.Count -ne 4){throw 'Send bounds unavailable.'}
$steps=[Collections.Generic.List[object]]::new()
function SaveJournal { [ordered]@{conversationId=$run.conversationId;marker=$run.marker;steps=$steps.ToArray()} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $journal }
$steps.Add(@{step='about-to-send-once';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
Android emulator-5558 @('shell','input','tap',"$([int](($coords[0]+$coords[2])/2))","$([int](($coords[1]+$coords[3])/2))") | Out-Null
$steps.Add(@{step='send-clicked-once';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
$checkpoint=$null
$deadline=[DateTimeOffset]::Now.AddSeconds(45)
while([DateTimeOffset]::Now -lt $deadline){
  $raw=Android emulator-5556 @('logcat','-d',"--pid=$mobilePid",'-v','raw','flutter:I','*:S')
  foreach($line in $raw){
    if([string]$line -notmatch '^AI_UAT_IM_CHECKPOINT (\{.*\})$'){continue}
    try{$value=$Matches[1] | ConvertFrom-Json}catch{continue}
    if($value.stage -ne 'committed_before_ack' -or $value.conversationType -ne 'group' -or $value.mentionsSelf -ne $true){continue}
    $checkpoint=[ordered]@{observedAt=[DateTimeOffset]::Now.ToString('o');processId=[int]$mobilePid}
    foreach($key in @('stage','eventSequence','messageSequence','appliedCursor','ackedCursor','copies','conversationType','mentionsSelf')){$checkpoint[$key]=$value.$key}
  }
  $raw=$null
  if($null -ne $checkpoint){break}
  Start-Sleep -Milliseconds 500
}
if($null -eq $checkpoint){throw 'Checkpoint not observed; do not resend. Restore normal APK after inspecting current state.'}
$checkpoint | ConvertTo-Json | Set-Content (Join-Path $evidence 'checkpoint.json')
if($checkpoint.appliedCursor -le $checkpoint.ackedCursor -or $checkpoint.messageSequence -ne 4 -or $checkpoint.copies -ne 1){throw 'Checkpoint invariants failed; do not kill blindly.'}
& py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5556 --conversation-id $run.conversationId --message-ledger > (Join-Path $evidence 'm3-committed-before-kill.json')
if($LASTEXITCODE -ne 0){throw 'Pre-kill snapshot failed.'}
$snapshot=Get-Content (Join-Path $evidence 'm3-committed-before-kill.json') -Raw | ConvertFrom-Json
$applied=($snapshot.eventCursors | Where-Object cursor_kind -eq applied).sequence
$acked=($snapshot.eventCursors | Where-Object cursor_kind -eq acked).sequence
$projection=@($snapshot.groupProjections)
if($applied -ne $checkpoint.appliedCursor -or $acked -ne $checkpoint.ackedCursor -or
   @($snapshot.messageLedger).Count -ne 4 -or $projection.Count -ne 1 -or
   $projection[0].last_read_sequence -ne 3 -or $projection[0].unread_count -ne 1 -or
   $projection[0].unread_mention_sequences_json -ne '[4]'){throw 'Durable message/read/mention checkpoint not confirmed; preserve state for inspection.'}
$steps.Add(@{step='durable-before-ack-confirmed';at=[DateTimeOffset]::Now.ToString('o');applied=$applied;acked=$acked}); SaveJournal
Android emulator-5556 @('shell','am','force-stop','com.hexing.zhilian.hexing_terminal_mobile') | Out-Null
$remaining=(& $adb -s emulator-5556 shell pidof com.hexing.zhilian.hexing_terminal_mobile) -join ''
if($remaining.Trim()){throw 'M3 process is still alive.'}
$steps.Add(@{step='force-stopped-pid-absent';at=[DateTimeOffset]::Now.ToString('o');previousPid=[int]$mobilePid}); SaveJournal
& py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5556 --conversation-id $run.conversationId --message-ledger > (Join-Path $evidence 'm3-after-process-death.json')
if($LASTEXITCODE -ne 0){throw 'Post-kill snapshot failed.'}
$steps.Add(@{step='post-death-snapshot-saved';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
$checkpoint | ConvertTo-Json
$steps.ToArray() | ConvertTo-Json
