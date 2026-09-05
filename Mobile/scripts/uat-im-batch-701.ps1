param([ValidateRange(1,510)][int]$Count = 510)
# One-shot real native UI run, only the dedicated two-person acceptance group.
# Existing journal means STOP, never infer that an uncertain click failed.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-batch-catchup-20260903'))
$journal = Join-Path $evidence 'native-send-run.json'
$group = 'AI-UAT-20260903-IM-BATCH-701'
$conversation = '245e652d-14be-4c29-a7aa-57b7659fa4e6'
if (Test-Path -LiteralPath $journal) { throw 'Run already exists. Inspect actual state; do not replay.' }
function Android([string]$Serial, [string[]]$CommandArgs) {
  $result = @(& $adb -s $Serial @CommandArgs 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android operation failed; do not replay any send.' }
  return $result
}
function ReadChat {
  $raw = (Android emulator-5558 @('exec-out','uiautomator','dump','/dev/tty')) -join "`n"
  $start=$raw.IndexOf('<?xml'); $end=$raw.LastIndexOf('</hierarchy>')
  if ($start -lt 0 -or $end -lt $start) { throw 'Fresh native hierarchy unavailable.' }
  [xml]$ui=$raw.Substring($start,$end+'</hierarchy>'.Length-$start)
  if (-not $ui.SelectSingleNode('//node[@content-desc="群聊详情"]') -or
      -not $ui.SelectSingleNode("//node[starts-with(@content-desc,'$group') and contains(@content-desc,'2 位成员')]")) {
    throw 'Dedicated two-person group is not open.'
  }
  return $ui
}
function Tap($node) {
  if ($null -eq $node) { throw 'Required control unavailable.' }
  $xy=@([regex]::Matches([string]$node.bounds,'\d+') | ForEach-Object { [int]$_.Value })
  if ($xy.Count -ne 4) { throw 'Unexpected bounds.' }
  Android emulator-5558 @('shell','input','tap',"$([int](($xy[0]+$xy[2])/2))","$([int](($xy[1]+$xy[3])/2))") | Out-Null
}
$wifi=((Android emulator-5556 @('shell','settings','get','global','wifi_on')) -join '').Trim()
$data=((Android emulator-5556 @('shell','settings','get','global','mobile_data')) -join '').Trim()
if ($wifi -notin @('0','1') -or $data -notin @('0','1')) { throw 'Network baseline unavailable.' }
$ui=ReadChat
$editor=$ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
if ($null -eq $editor -or $editor.text) { throw 'Preserve nonempty composer.' }
Tap $editor
$events=[Collections.Generic.List[object]]::new()
function Record([string]$Stage,[int]$Index=0) {
  $events.Add(@{stage=$Stage;index=$Index;at=[DateTimeOffset]::Now.ToString('o')})
  @{sender='emulator-5558';receiver='emulator-5556';conversationId=$conversation;requested=$Count;
    initialWifi=$wifi;initialData=$data;events=$events.ToArray()} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal
}
Record 'starting'
try {
  Android emulator-5556 @('shell','svc','wifi','disable') | Out-Null
  Android emulator-5556 @('shell','svc','data','disable') | Out-Null
  Start-Sleep -Milliseconds 800
  $network=(Android emulator-5556 @('shell','dumpsys','connectivity')) -join "`n"
  if ($network -notmatch 'Active default network: none') { throw 'Offline state not established.' }
  $network=$null
  Record 'offline-confirmed'
  for($i=1;$i -le $Count;$i++) {
    $marker='AI-UAT-701-BATCH-{0:D4}' -f $i
    Android emulator-5558 @('shell','input','text',$marker) | Out-Null
    # A fresh hierarchy after EVERY entry verifies exact text, foreground target,
    # current keyboard-dependent button bounds, and button state before click.
    $ui=ReadChat
    $editor=$ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
    $send=$ui.SelectSingleNode('//node[@content-desc="发送"]')
    if ($null -eq $editor -or $editor.text -cne $marker -or $null -eq $send -or $send.enabled -ne 'true') {
      throw 'Composer not exactly the unique marker. Preserve it; no click/replay.'
    }
    Record 'about-to-click' $i
    Tap $send
    Record 'clicked' $i
    Start-Sleep -Milliseconds 300
    if ($i % 5 -eq 0) { Write-Output "Native UI send clicks: $i/$Count (not server-confirmation count)." }
  }
  $ui=ReadChat
  if ($ui.SelectSingleNode('//node[@class="android.widget.EditText"]').text) { throw 'Final composer did not clear.' }
  py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5556 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm3-offline-after-send.json')
  if ($LASTEXITCODE -ne 0) { throw 'Receiver snapshot unavailable.' }
  py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5558 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm4-after-send.json')
  if ($LASTEXITCODE -ne 0) { throw 'Sender snapshot unavailable.' }
  Record 'send-run-ended'
} finally {
  Android emulator-5556 @('shell','svc','wifi',$(if($wifi -eq '1'){'enable'}else{'disable'})) | Out-Null
  Android emulator-5556 @('shell','svc','data',$(if($data -eq '1'){'enable'}else{'disable'})) | Out-Null
  Record 'network-restored'
}
