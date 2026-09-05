# Bounded real UI test for the already verified M3/test03 <-> M4/test04 chat.
# M3 network is always restored. Never re-run an uncertain send automatically.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-independent-m4-20260903'))
$journal = Join-Path $evidence 'offline-run.json'
if (Test-Path -LiteralPath $journal) { throw 'Existing run found; inspect it before any further sends.' }
$conversation = 'e51db063-4ed2-4a43-b7ff-bfbf32b1806d'
function Android([string]$Serial, [string[]]$CommandArgs) {
  $result = @(& $adb -s $Serial @CommandArgs 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android test operation failed.' }
  return $result
}
function ReadChat {
  $raw = (Android emulator-5558 @('exec-out','uiautomator','dump','/dev/tty')) -join "`n"
  $start = $raw.IndexOf('<?xml')
  $end = $raw.LastIndexOf('</hierarchy>')
  if ($start -lt 0 -or $end -lt $start) { throw 'Fresh chat hierarchy unavailable.' }
  [xml]$ui = $raw.Substring($start, $end + '</hierarchy>'.Length - $start)
  if (-not $ui.SelectSingleNode('//node[@content-desc="聊天"]') -or
      -not $ui.SelectSingleNode('//node[contains(@content-desc,"Test Terminal 03")]') -or
      -not $ui.SelectSingleNode('//node[contains(@content-desc,"AI-UAT-20260903-045700-M3-M4-DIRECT")]')) {
    throw 'Verified M4 direct conversation is not open.'
  }
  return $ui
}
function Tap($Node) {
  if ($null -eq $Node) { throw 'Required chat control absent.' }
  $coords = [regex]::Matches([string]$Node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
  if ($coords.Count -ne 4) { throw 'Unexpected bounds.' }
  Android emulator-5558 @('shell','input','tap',"$([int](($coords[0]+$coords[2])/2))","$([int](($coords[1]+$coords[3])/2))") | Out-Null
}
$initialWifi = (Android emulator-5556 @('shell','settings','get','global','wifi_on')) -join ''
$initialData = (Android emulator-5556 @('shell','settings','get','global','mobile_data')) -join ''
if ($initialWifi.Trim() -notin @('0','1') -or $initialData.Trim() -notin @('0','1')) { throw 'Network state unavailable.' }
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
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name '20-m3-offline-cold-home' | Out-Null
  for ($i = 1; $i -le 2; $i++) {
    $ui = ReadChat
    $editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
    if ($null -eq $editor -or $editor.text) { throw 'Composer is not empty; do not overwrite a draft.' }
    Tap $editor
    $marker = 'AI-UAT-20260903-045700-M4-M3-OFFLINE-{0:D2}' -f $i
    Android emulator-5558 @('shell','input','text',$marker) | Out-Null
    $ui = ReadChat
    $send = $ui.SelectSingleNode('//node[@content-desc="发送"]')
    if ($null -eq $send -or $send.enabled -ne 'true') { throw 'Send unavailable.' }
    Tap $send
    $events += @{step='send-clicked';marker=$marker;at=[DateTimeOffset]::Now.ToString('o')}; SaveJournal
    Start-Sleep -Milliseconds 600
  }
  & py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5556 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm3-offline-before-reconnect.json')
  if ($LASTEXITCODE -ne 0) { throw 'Offline snapshot unavailable.' }
  & py (Join-Path $PSScriptRoot 'inspect-device-im-outbox.py') --serial emulator-5558 --conversation-id $conversation --message-ledger > (Join-Path $evidence 'm4-offline-messages-sent.json')
  if ($LASTEXITCODE -ne 0) { throw 'Sender snapshot unavailable.' }
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5558 -EvidenceDirectory $evidence -Name '21-m4-offline-messages' | Out-Null
} finally {
  $wifiAction = if ($initialWifi.Trim() -eq '1') { 'enable' } else { 'disable' }
  $dataAction = if ($initialData.Trim() -eq '1') { 'enable' } else { 'disable' }
  Android emulator-5556 @('shell','svc','wifi',$wifiAction) | Out-Null
  Android emulator-5556 @('shell','svc','data',$dataAction) | Out-Null
  $events += @{step='network-restored';wifi=(Android emulator-5556 @('shell','settings','get','global','wifi_on')) -join '';mobileData=(Android emulator-5556 @('shell','settings','get','global','mobile_data')) -join '';at=[DateTimeOffset]::Now.ToString('o')}
  SaveJournal
}
Get-Content -LiteralPath $journal
