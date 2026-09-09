param(
  [Parameter(Mandatory = $true)][guid]$RequestId,
  [Parameter(Mandatory = $true)][guid]$TaskId,
  [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$ExpectedTaskVersion,
  [Parameter(Mandatory = $true)][ValidateSet('approved', 'rejected')][string]$Decision,
  [Parameter(Mandatory = $true)][string]$Comment,
  [Parameter(Mandatory = $true)][DateTimeOffset]$NotBeforeUtc,
  [Parameter(Mandatory = $true)][string]$OutputPath
)

# Executes one AI-UAT review through the installed desktop session at a fixed
# time. The output contains only status/timing/correlation metadata; credentials,
# tokens, device identifiers and raw response payloads are never emitted.
$ErrorActionPreference = 'Stop'
if ($Comment -notmatch '^AI-UAT-[A-Za-z0-9-]+$') {
  throw 'An AI-UAT comment is required.'
}

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http
$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$plain = $null
$secret = $null
$client = $null
$request = $null
$response = $null

try {
  $config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
  function ConfigValue([string]$Name) {
    $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
    if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
    return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
  }

  $uri = [uri](ConfigValue 'collaboration-oa-api-url')
  if ($uri.Scheme -notin @('http', 'https') -or $uri.Host -ne 'api.sfhkh.com' -or $uri.UserInfo) {
    throw 'Not the authorized test origin.'
  }
  $origin = $uri.GetLeftPart([UriPartial]::Authority)

  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') {
    throw 'Not a numbered test account.'
  }

  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(15)

  $remaining = $NotBeforeUtc.ToUniversalTime() - [DateTimeOffset]::UtcNow
  if ($remaining.TotalMilliseconds -gt 0) {
    Start-Sleep -Milliseconds ([Math]::Floor($remaining.TotalMilliseconds))
  }

  $startedAt = [DateTimeOffset]::UtcNow
  $body = [ordered]@{
    taskId = $TaskId.ToString()
    expectedTaskVersion = $ExpectedTaskVersion
    idempotencyKey = [guid]::NewGuid().ToString()
    decision = $Decision
    comment = $Comment
  } | ConvertTo-Json -Compress

  $request = [Net.Http.HttpRequestMessage]::new(
    [Net.Http.HttpMethod]::Patch,
    $origin + '/api/oa/approval-requests/' + $RequestId.ToString() + '/review'
  )
  $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new(
    'Bearer', [string]$secret.access_token
  )
  $request.Headers.Add('X-Device-Id', (ConfigValue 'device-id'))
  $request.Headers.Add('X-Terminal-Device-Id', (ConfigValue 'device-id'))
  $request.Headers.Add('X-Terminal-Account-Id', (ConfigValue 'terminal-account-id'))
  $request.Content = [Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'application/json')

  $response = $client.SendAsync($request).GetAwaiter().GetResult()
  $completedAt = [DateTimeOffset]::UtcNow
  $payloadText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $payload = $null
  try { $payload = ConvertFrom-Json -InputObject $payloadText -NoEnumerate } catch { }
  $correlationId = $null
  foreach ($header in @('X-Request-ID', 'X-Correlation-ID', 'Request-Id')) {
    if ($response.Headers.Contains($header)) {
      $correlationId = $response.Headers.GetValues($header) -join ','
      break
    }
  }

  $summary = [ordered]@{
    source = 'installed-desktop-session'
    account = [string]$secret.saved_username
    requestId = $RequestId.ToString()
    taskId = $TaskId.ToString()
    expectedTaskVersion = $ExpectedTaskVersion
    startedAt = $startedAt.ToString('o')
    completedAt = $completedAt.ToString('o')
    durationMs = [Math]::Round(($completedAt - $startedAt).TotalMilliseconds, 3)
    httpStatus = [int]$response.StatusCode
    correlationId = $correlationId
    responseCode = if ($payload) { [string]$payload.code } else { $null }
    responseMessage = if ($payload) { [string]$payload.message } else { $null }
    responseStatus = if ($payload) { [string]$payload.status } else { $null }
    responseVersion = if ($payload -and $null -ne $payload.version) { [int]$payload.version } else { $null }
  }
  $parent = Split-Path -Parent $OutputPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
} catch {
  $failure = [ordered]@{
    source = 'installed-desktop-session'
    requestId = $RequestId.ToString()
    taskId = $TaskId.ToString()
    failedAt = [DateTimeOffset]::UtcNow.ToString('o')
    errorType = $_.Exception.GetType().Name
  }
  $parent = Split-Path -Parent $OutputPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $failure | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
  exit 1
} finally {
  if ($response) { $response.Dispose() }
  if ($request) { $request.Dispose() }
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
