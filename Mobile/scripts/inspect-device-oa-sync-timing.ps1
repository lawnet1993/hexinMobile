param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._:-]+$')][string]$Serial
)

# Read only, PID-scoped and field-allowlisted. Never persist raw mobile logs.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package = 'com.hexing.zhilian.hexing_terminal_mobile'
$devicePid = ((& $adb -s $Serial shell pidof $package 2>$null) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $devicePid -notmatch '^\d+$') {
  throw 'Mobile app is not running; no unscoped logs read.'
}
$lines = @(& $adb -s $Serial logcat -d -v epoch --pid=$devicePid -t 5000 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Scoped diagnostics unavailable.' }
$events = @(
  foreach ($line in $lines) {
    $match = [regex]::Match($line, 'MOBILE_OA_SYNC (\{[^\r\n]*\})\s*$')
    if (-not $match.Success) { continue }
    try { $entry = $match.Groups[1].Value | ConvertFrom-Json } catch { continue }
    if ($entry.outcome -ne 'committed') { continue }
    $recordedAt = [DateTimeOffset]::MinValue
    if ($entry.recordedAt -is [DateTime]) {
      # PowerShell may deserialize ISO timestamps as DateTime. Casting that to
      # string first loses the UTC kind and would reinterpret it as local time.
      $recordedAt = [DateTimeOffset]$entry.recordedAt
    } elseif (-not [DateTimeOffset]::TryParse([string]$entry.recordedAt, [ref]$recordedAt)) { continue }
    $result = [ordered]@{ recordedAt=$recordedAt.ToUniversalTime().ToString('o') }
    $valid = $true
    foreach ($field in @('eventCount','waitSeconds','requestMs','projectionMs','commitMs','totalMs')) {
      $value = $entry.$field
      if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) { $valid=$false; break }
      $result[$field] = [long]$value
    }
    if (-not $valid) { continue }
    $result['outcome'] = 'committed'
    $result
  }
)
$lines = $null
[ordered]@{
  checkedAt=[DateTimeOffset]::Now.ToString('o')
  serial=$Serial
  processId=[int]$devicePid
  source='normal-app-scoped-logcat-whitelisted-timing'
  events=$events
} | ConvertTo-Json -Depth 5
