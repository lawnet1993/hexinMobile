param(
  [Parameter(Mandatory)][ValidateSet('emulator-5556','emulator-5558')][string]$Serial,
  [Parameter(Mandatory)][string]$OutputPath
)

# Read current-process logs only in memory. Persist only the validated diagnostic
# schema, never raw logcat, request/response bodies, credentials or media URLs.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
$target = [IO.Path]::GetFullPath($OutputPath)
if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($target) -ne '.json' -or (Test-Path -LiteralPath $target)) {
  throw 'Use a new JSON file under Mobile/test/evidence.'
}
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$mobilePid = ((& $adb -s $Serial shell pidof com.hexing.zhilian.hexing_terminal_mobile) -join '').Trim()
if ($mobilePid -notmatch '^\d+$') { throw 'Current application process unavailable.' }
$raw = @(& $adb -s $Serial logcat -d --pid=$mobilePid 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Log read failed.' }
$expected = @('sampledAt','operation','httpStatus','failureType','requestBody','formFields',
  'fileBytes','responseType','bodyShape','errorCode','errorSignals','requestId',
  'correlationId','traceparent','bodyTraceId')
$codes = @('internal_error','upload_failed','storage_unavailable','file_too_large',
  'validation_failed','unsupported_media_type','invalid_file','unauthorized',
  'forbidden','session_replaced','NoSuchBucket','AccessDenied','InvalidAccessKeyId','SignatureDoesNotMatch')
$correlationPattern = '^(?:[a-fA-F0-9]{32}|[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}|[a-fA-F0-9]{2}-[a-fA-F0-9]{32}-[a-fA-F0-9]{16}-[a-fA-F0-9]{2}|0[A-Z0-9]{12}:[A-F0-9]{8})$'
$records = @()
$rejected = 0
foreach ($line in $raw) {
  $match = [regex]::Match([string]$line, 'MOBILE_IM_UPLOAD (\{.*\})$')
  if (-not $match.Success) { continue }
  try {
    # Preserve the UTC suffix: automatic DateTime conversion followed by string
    # parsing would otherwise apply this Windows host's time zone a second time.
    $value = $match.Groups[1].Value | ConvertFrom-Json -DateKind String
    if (Compare-Object @($value.PSObject.Properties.Name | Sort-Object) @($expected | Sort-Object)) { throw 'Unexpected schema' }
    if ($value.operation -notin @('video_upload','audio_upload','cover_upload','image_send','file_send','media_message')) { throw 'Unexpected operation' }
    if ($value.failureType -notin @('connectionTimeout','sendTimeout','receiveTimeout','badCertificate','badResponse','cancel','connectionError','unknown')) { throw 'Unexpected failure' }
    if ($value.requestBody -notin @('multipart','other') -or $value.responseType -notin @('json','html','text','other') -or $value.bodyShape -notin @('empty','object','array','string','other')) { throw 'Unexpected shape' }
    if ($null -ne $value.httpStatus -and ($value.httpStatus -isnot [long] -and $value.httpStatus -isnot [int] -or $value.httpStatus -lt 100 -or $value.httpStatus -gt 599)) { throw 'Unexpected status' }
    if ($null -ne $value.errorCode -and $value.errorCode -notin $codes) { throw 'Unexpected code' }
    foreach ($field in $value.formFields) { if ($field -notin @('file','files','files[]','caption','clientMessageId')) { throw 'Unexpected field' } }
    foreach ($size in $value.fileBytes) { if (($size -isnot [long] -and $size -isnot [int]) -or $size -lt 0 -or $size -gt 10737418240) { throw 'Unexpected file length' } }
    foreach ($signal in $value.errorSignals) { if ($signal -notin @('missing_bucket','storage_credentials_rejected','access_denied','disk_full','payload_too_large','storage_not_configured')) { throw 'Unexpected signal' } }
    foreach ($key in @('requestId','correlationId','traceparent','bodyTraceId')) { if ($null -ne $value.$key -and ($value.$key -isnot [string] -or $value.$key -cnotmatch $correlationPattern)) { throw 'Unexpected correlation value' } }
    $parsedTime = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($value.sampledAt, [ref]$parsedTime)) { throw 'Unexpected timestamp' }
    $value.sampledAt = $parsedTime.ToUniversalTime().ToString('o')
    $records += $value
  } catch { $rejected++ }
}
$raw = $null
$result = [ordered]@{
  capturedAt = [DateTimeOffset]::Now.ToString('o')
  serial = $Serial
  processId = [int]$mobilePid
  rejectedRecords = $rejected
  records = $records
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $target
$result | ConvertTo-Json -Depth 6
