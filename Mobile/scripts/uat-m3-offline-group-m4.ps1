# One bounded, journaled real-UI test of the newly created AI-UAT M3/M4 group.
# Never replay an uncertain send. Restore M3's original network state in finally.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-m3-m4-group-20260903'))
$journal = Join-Path $evidence 'offline-group-run.json'
$conversation = '95e704ae-0e34-4f56-87db-038526796d6c'
$groupTitle = 'AI-UAT-20260903-050600-M3-M4-GROUP'
if (Test-Path -LiteralPath $journal) { throw 'Existing run found; inspect evidence before any further sends.' }
function Android([string]$Serial, [string[]]$CommandArgs) {
  $result = @(& $adb -s $Serial @CommandArgs 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android operation failed.' }
  return $result
}
function ReadUi {
  $raw = (Android emulator-5558 @('exec-out','uiautomator','dump','/dev/tty')) -join "`n"
  $start = $raw.IndexOf('<?xml'); $end = $raw.LastIndexOf('</hierarchy>')
  if ($start -lt 0 -or $end -lt $start) { throw 'Fresh hierarchy unavailable.' }
  [xml]$ui = $raw.Substring($start, $end + '</hierarchy>'.Length - $start)
  return $ui
}
function ReadChat {
  $ui = ReadUi
  if (-not $ui.SelectSingleNode('//node[@content-desc="群聊详情"]') -or
      -not $ui.SelectSingleNode("//node[contains(@content-desc,'$groupTitle')]")) {
    throw 'Verified AI-UAT group chat is not open.'
  }
  return $ui
}
function Tap($Node) {
  if ($null -eq $Node) { throw 'Required control absent.' }
  $coords = [regex]::Matches([string]$Node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
  if ($coords.Count -ne 4) { throw 'Unexpected bounds.' }
  Android emulator-5558 @('shell','input','tap',"$([int](($coords[0]+$coords[2])/2))","$([int](($coords[1]+$coords[3])/2))") | Out-Null
}
$initialWifi = ((Android emulator-5556 @('shell','settings','get','global','wifi_on')) -join '').Trim()
$initialData = ((Android emulator-5556 @('shell','settings','get','global','mobile_data')) -join '').Trim()
if ($initialWifi -notin @('0','1') -or $initialData -notin @('0','1')) { throw 'Network state unavailable.' }
$events = @()
function SaveJournal {
  [ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');conversationId=$conversation;
    offlineDevice='emulator-5556';senderDevice='emulator-5558';events=$events
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $journal
}
ReadChat | Out-Null
try {
  $events += @{step='starting';at=[DateTimeOffset]::Now.ToString('o')}; SaveJournal
  Android emulator-5556 @('shell','svc','wifi','disable') | Out-Null
  Android emulator-5556 @('shell','svc','data','disable') | Out-Null
  Start-Sleep -Milliseconds 800
  $connectivity = (Android emulator-5556 @('shell','dumpsys','connectivity')) -join "`n"
  if ($connectivity -notmatch 'Active default network: none') { throw 'M3 offline state not established.' }
  $connectivity = $null
  $events += @{step='offline-confirmed';at=[DateTimeOffset]::Now.ToString('o')}; SaveJournal
  Android emulator-5556 @('shell','am','force-stop','com.hexing.zhilian.hexing_terminal_mobile') | Out-Null
  Android emulator-5556 @('shell','am','start','-W','-n','com.hexing.zhilian.hexing_terminal_mobile/.MainActivity') | Out-Null
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name '21-m3-group-offline-home' | Out-Null
  for ($i = 1; $i -le 2; $i++) {
    $ui = ReadChat
    $editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
    if ($null -eq $editor -or $editor.text) { throw 'Composer is not empty; preserve draft.' }
    if ($i -eq 2) {
      Tap ($ui.SelectSingleNode('//node[@content-desc="提及成员"]'))
      $ui = ReadUi
      Tap ($ui.SelectSingleNode('//node[contains(@content-desc,"Test Terminal 03") and contains(@content-desc,"test03")]'))
      $ui = ReadChat
      $editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
      if ($editor.text -notmatch '^@Test Terminal 03\s') { throw 'Native mention selection failed.' }
    }
    Tap $editor
    Android emulator-5558 @('shell','input','keyevent','KEYCODE_MOVE_END') | Out-Null
    $marker = 'AI-UAT-20260903-051400-M4-M3-GROUP-OFFLINE-{0:D2}' -f $i
    Android emulator-5558 @('shell','input','text',$marker) | Out-Null
    $ui = ReadChat
    $send = $ui.SelectSingleNode('//node[@content-desc="发送"]')
    if ($null -eq $send -or $send.enabled -ne 'true') { throw 'Send unavailable.' }
    $events += @{step='send-about-to-click';marker=$marker;at=[DateTimeOffset]::Now.ToString('o')}; SaveJournal
    Tap $send
    $events += @{step='send-clicked';marker=$marker;at=[DateTimeOffset]::Now.ToString('o')}; SaveJournal
    Start-Sleep -Milliseconds 600
    $inputState = (Android emulator-5558 @('shell','dumpsys','input_method')) -join "`n"
    if ($inputState -match 'mInputShown=true') { Android emulator-5558 @('shell','input','keyevent','KEYCODE_BACK') | Out-Null }
    $inputState = $null
  }
  & py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5556 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm3-group-offline-before-reconnect.json')
  if ($LASTEXITCODE -ne 0) { throw 'Offline snapshot unavailable.' }
  & py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5558 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm4-group-offline-sent.json')
  if ($LASTEXITCODE -ne 0) { throw 'Sender snapshot unavailable.' }
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5558 -EvidenceDirectory $evidence -Name '22-m4-group-offline-sent' | Out-Null
} finally {
  $wifiAction = if ($initialWifi -eq '1') { 'enable' } else { 'disable' }
  $dataAction = if ($initialData -eq '1') { 'enable' } else { 'disable' }
  Android emulator-5556 @('shell','svc','wifi',$wifiAction) | Out-Null
  Android emulator-5556 @('shell','svc','data',$dataAction) | Out-Null
  $events += @{step='network-restored';wifi=(Android emulator-5556 @('shell','settings','get','global','wifi_on')) -join '';mobileData=(Android emulator-5556 @('shell','settings','get','global','mobile_data')) -join '';at=[DateTimeOffset]::Now.ToString('o')}
  SaveJournal
}
Get-Content -LiteralPath $journal
