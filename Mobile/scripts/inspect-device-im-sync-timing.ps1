param(
  [Parameter(Mandatory)]
  [ValidatePattern('^(?:emulator-\d+|[A-Za-z0-9._:-]+)$')]
  [string]$Serial
)

# Read only, PID-scoped and field-allowlisted. Raw application logs are never
# persisted or emitted because they can contain business or transport data.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package = 'com.hexing.zhilian.hexing_terminal_mobile'
$deviceProcessId = ((& $adb -s $Serial shell pidof $package 2>$null) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $deviceProcessId -notmatch '^\d+$') {
  throw 'Mobile app is not running; no unscoped logs read.'
}

$lines = @(& $adb -s $Serial logcat -d -v epoch --pid=$deviceProcessId -t 8000 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Scoped diagnostics unavailable.' }
$events = @(
  foreach ($line in $lines) {
    $match = [regex]::Match($line, '^\s*(?<epoch>\d+(?:\.\d+)?)\s+.*MOBILE_IM_SYNC_STAGE (?<json>\{[^\r\n]*\})\s*$')
    if (-not $match.Success) { continue }
    try { $entry = $match.Groups['json'].Value | ConvertFrom-Json } catch { continue }
    $result = [ordered]@{
      recordedAt = [DateTimeOffset]::FromUnixTimeMilliseconds(
        [long]([double]$match.Groups['epoch'].Value * 1000)
      ).ToUniversalTime().ToString('o')
    }
    $valid = $true
    foreach ($field in @(
      'waitSeconds','eventCount','firstEventSequence','lastEventSequence',
      'requestMs','bootstrapMs','commitMs','ackMs','totalMs'
    )) {
      $value = $entry.$field
      if ($null -eq $value) {
        $result[$field] = $null
        continue
      }
      if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) {
        $valid = $false
        break
      }
      $result[$field] = [long]$value
    }
    foreach ($field in @('oldestEventAgeMs','newestEventAgeMs')) {
      $value = $entry.$field
      if ($null -eq $value) {
        $result[$field] = $null
      } elseif ($value -is [int] -or $value -is [long]) {
        # A small negative age is valid evidence of emulator clock skew; keep
        # it visible rather than silently dropping the complete sync batch.
        $result[$field] = [long]$value
      } else {
        $valid = $false
      }
    }
    if ($valid) { $result }
  }
)
$lines = $null

[ordered]@{
  checkedAt = [DateTimeOffset]::Now.ToString('o')
  serial = $Serial
  processId = [int]$deviceProcessId
  source = 'normal-app-scoped-logcat-whitelisted-im-timing'
  events = $events
} | ConvertTo-Json -Depth 6
