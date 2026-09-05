param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._:-]+$')][string]$Serial,
  [ValidateRange(0, 60)][int]$WaitSeconds = 0
)

# Read only. Parse the normal app's allowlisted diagnostics; never print raw
# log lines, response payloads, token strings, identities or device fingerprints.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package = 'com.hexing.zhilian.hexing_terminal_mobile'
$started = [DateTimeOffset]::Now
$deadline = $started.AddSeconds($WaitSeconds)
$initialPid = ''
do {
  $devicePid = ((& $adb -s $Serial shell pidof $package 2>$null) -join '').Trim()
  if ($LASTEXITCODE -ne 0 -or $devicePid -notmatch '^\d+$') {
    throw 'The requested mobile app is not running; no unscoped logs read.'
  }
  if ($initialPid -and $initialPid -ne $devicePid) {
    throw 'Mobile process changed during observation; start a fresh observation.'
  }
  $initialPid = $devicePid
  $lines = @(& $adb -s $Serial logcat -d -v epoch --pid=$devicePid -t 5000 2>$null)
  if ($LASTEXITCODE -ne 0) { throw 'Scoped mobile diagnostics unavailable.' }
  $events = @(
    foreach ($line in $lines) {
      $match = [regex]::Match($line, 'MOBILE_SESSION_(REFRESH|AUTH) (\{[^\r\n]*\})\s*$')
      if (-not $match.Success) { continue }
      try { $entry = $match.Groups[2].Value | ConvertFrom-Json } catch { continue }
      $epoch = [regex]::Match($line, '^\s*(\d+\.\d+)\s').Groups[1].Value
      $status = if (($entry.status -is [int] -or $entry.status -is [long]) -and $entry.status -ge 100 -and $entry.status -le 599) { [int]$entry.status } else { $null }
      $action = if ($entry.action -in @('accepted','rejected','retry','stale_result','invalid_response','ignored_stale_response','session_preserved','refresh_retry','terminated')) { $entry.action } else { 'unrecognized' }
      $source = if ($entry.source -in @('heartbeat','managed_commands','managed_sites','im_events','authenticated_request')) { $entry.source } else { $null }
      $errorCode = if ($entry.errorCode -in @('invalid_grant','invalid_client','invalid_request','unauthorized_client','unsupported_grant_type','server_error','temporarily_unavailable','unrecognized')) { $entry.errorCode } else { $null }
      [ordered]@{ epochSeconds=$epoch; kind=$match.Groups[1].Value; status=$status; action=$action; source=$source; errorCode=$errorCode }
    }
  )
  $lines = $null
  if (@($events | Where-Object { $_.kind -eq 'REFRESH' -and $_.action -eq 'accepted' }).Count -gt 0) { break }
  if ([DateTimeOffset]::Now -ge $deadline) { break }
  Start-Sleep -Seconds 2
} while ($true)
[ordered]@{
  startedAt=$started.ToString('o')
  checkedAt=[DateTimeOffset]::Now.ToString('o')
  serial=$Serial
  processId=[int]$initialPid
  source='normal-app-scoped-logcat-whitelisted-metadata'
  events=$events
} | ConvertTo-Json -Depth 5
