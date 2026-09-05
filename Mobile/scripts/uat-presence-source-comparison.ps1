# Bounded, native-UI experiment on the independent M3/M4 test pair.
# Logs only the diagnostic field allowlist, never raw logcat or HTTP payloads.
param(
  [ValidateSet('source','precise')][string]$RunTag = 'source',
  [ValidateRange(5,30)][int]$SampleSeconds = 25,
  [ValidateRange(1,35)][int]$MaximumSamples = 7
)
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\presence-source-comparison-20260903'))
$journal = Join-Path $evidence "$RunTag-comparison.json"
if (Test-Path -LiteralPath $journal) { throw 'Run already exists; inspect its live process before any retry.' }
$conversationId = 'e51db063-4ed2-4a43-b7ff-bfbf32b1806d'
function Android([string]$Serial, [string[]]$Arguments) {
  $result = @(& $adb -s $Serial @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android observation failed.' }
  return $result
}
$mobilePid = ((Android emulator-5556 @('shell','pidof','com.hexing.zhilian.hexing_terminal_mobile')) -join '').Trim()
if ($mobilePid -notmatch '^\d+$') { throw 'Expected one live M3 app process.' }
$initialWifi = ((Android emulator-5558 @('shell','settings','get','global','wifi_on')) -join '').Trim()
$initialData = ((Android emulator-5558 @('shell','settings','get','global','mobile_data')) -join '').Trim()
if ($initialWifi -ne '1' -or $initialData -ne '1') { throw 'M4 must start with both network transports enabled.' }
$samples = [Collections.Generic.List[object]]::new()
$records = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new()
$clock = [Diagnostics.Stopwatch]::StartNew()
function SaveJournal {
  [ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');observer='emulator-5556/test03';
    peer='emulator-5558/test04';processId=[int]$mobilePid;conversationId=$conversationId;
    samples=$samples.ToArray();diagnostics=$records.ToArray()
  } | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $journal
}
function CollectDiagnostics {
  $currentPid = ((Android emulator-5556 @('shell','pidof','com.hexing.zhilian.hexing_terminal_mobile')) -join '').Trim()
  if ($currentPid -ne $mobilePid) { throw 'M3 process changed during observation.' }
  $raw = Android emulator-5556 @('logcat','-d',"--pid=$mobilePid",'-v','raw','flutter:I','*:S')
  foreach ($line in $raw) {
    if ([string]$line -notmatch '^MOBILE_IM_PRESENCE (\{.*\})$') { continue }
    try { $value = $Matches[1] | ConvertFrom-Json } catch { continue }
    if ($value.conversationId -ne $conversationId -or $value.kind -notin @('response','render')) { continue }
    $keys = if ($value.kind -eq 'response') {
      @('sampledAt','kind','conversationId','conversationType','httpStatus','host','startedAt',
        'peerOnline','peerPresenceKnown','peerLastSeenAt','onlineMemberCount','serverTime')
    } else {
      @('sampledAt','kind','conversationId','displayedOnline','transportAvailable','memberOnline',
        'memberFresh','memberOrder','memberLastSeenAt','conversationOnline','conversationFresh','conversationServerTime')
    }
    $safe = [ordered]@{}
    foreach ($key in $keys) { $safe[$key] = $value.$key }
    $identity = $safe | ConvertTo-Json -Compress
    if ($seen.Add($identity)) { $records.Add([pscustomobject]$safe) }
  }
  $raw = $null
}
function Sample([string]$Name) {
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name $Name | Out-Null
  [xml]$ui = Get-Content -LiteralPath (Join-Path $evidence "$Name.xml") -Raw
  if (-not $ui.SelectSingleNode('//node[@content-desc="消息"]')) { throw 'M3 left the message list.' }
  $rows = $ui.SelectNodes('//node[contains(@content-desc,"Test Terminal 04") and contains(@content-desc,"单聊，")]')
  if ($rows.Count -ne 1) { throw 'Expected exactly one Test04 direct row.' }
  $label = [string]$rows[0].'content-desc'
  $status = if ($label.StartsWith('单聊，对方在线')) {'online'} elseif ($label.StartsWith('单聊，对方离线')) {'offline'} else {'unknown'}
  $uiAt = [DateTimeOffset]::Now.ToString('o')
  CollectDiagnostics
  $profile = & (Join-Path $PSScriptRoot 'inspect-desktop-im-uat.ps1') -InspectTestMember test04 | ConvertFrom-Json
  $latestResponse = $records | Where-Object kind -eq response | Select-Object -Last 1
  $latestRender = $records | Where-Object kind -eq render | Select-Object -Last 1
  $record = [ordered]@{step=$Name;at=$uiAt;elapsedSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,1);
    status=$status;latestResponse=$latestResponse;latestRender=$latestRender;desktopProfile=$profile}
  $samples.Add($record); SaveJournal
  [ordered]@{step=$Name;at=$uiAt;status=$status;responseOnline=$latestResponse.peerOnline;
    renderOnline=$latestRender.displayedOnline;profileOnline=$profile.isOnline;
    responseAt=$latestResponse.sampledAt;profileStatus=$profile.status} | ConvertTo-Json -Compress | Write-Output
}
try {
  Sample "$RunTag-baseline"
  if ($records.Count -eq 0 -or -not ($records | Where-Object kind -eq response)) { throw 'Diagnostic build has not produced a presence response.' }
  Android emulator-5558 @('shell','svc','wifi','disable') | Out-Null
  Android emulator-5558 @('shell','svc','data','disable') | Out-Null
  Start-Sleep -Milliseconds 800
  $connectivity = (Android emulator-5558 @('shell','dumpsys','connectivity')) -join "`n"
  if ($connectivity -notmatch 'Active default network: none') { throw 'M4 disconnect not confirmed.' }
  $connectivity = $null
  $samples.Add(@{step='peer-network-off';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
  for ($i=1; $i -le $MaximumSamples; $i++) {
    Start-Sleep -Seconds $SampleSeconds
    Sample "$RunTag-offline-$($i*$SampleSeconds)"
    if ($samples[$samples.Count-1].status -eq 'offline') { break }
  }
} finally {
  Android emulator-5558 @('shell','svc','wifi','enable') | Out-Null
  Android emulator-5558 @('shell','svc','data','enable') | Out-Null
  $samples.Add(@{step='peer-network-restored';at=[DateTimeOffset]::Now.ToString('o');
    wifi=((Android emulator-5558 @('shell','settings','get','global','wifi_on')) -join '').Trim();
    mobileData=((Android emulator-5558 @('shell','settings','get','global','mobile_data')) -join '').Trim()}); SaveJournal
}
for ($i=1; $i -le 4; $i++) {
  Start-Sleep -Seconds $SampleSeconds
  Sample "$RunTag-restored-$($i*$SampleSeconds)"
  if ($samples[$samples.Count-1].status -eq 'online') { break }
}
$samples.Add(@{step='finished';at=[DateTimeOffset]::Now.ToString('o')}); SaveJournal
