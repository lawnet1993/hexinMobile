param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-fA-F0-9-]{36}$')]
  [string]$ExpectedConversationId,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [Parameter(Mandatory = $true)]
  [string]$ReadyPath
)

# Measures whether the authorized test IM long poll wakes when a new event is
# appended. Credentials, tokens and device identifiers are never emitted.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http

$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
$plain = $null
$secret = $null
$client = $null

function Get-ConfigValue([string]$Name) {
  $match = [regex]::Match(
    $config,
    '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$'
  )
  if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

function Read-RequestId([Net.Http.HttpResponseMessage]$Response) {
  foreach ($header in @('X-Request-ID', 'X-Correlation-ID', 'Request-Id')) {
    if ($Response.Headers.Contains($header)) {
      return $Response.Headers.GetValues($header) -join ','
    }
  }
  return $null
}

try {
  $uri = [uri](Get-ConfigValue 'collaboration-im-api-url')
  if ($uri.Scheme -notin @('http', 'https') -or
      $uri.Host -ne 'api.sfhkh.com' -or $uri.UserInfo) {
    throw 'Not the authorized test origin.'
  }
  $origin = $uri.GetLeftPart([UriPartial]::Authority)
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -ne 'test01') {
    throw 'The installed desktop session is not the expected test account.'
  }

  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(35)
  $client.DefaultRequestHeaders.Authorization =
    [Net.Http.Headers.AuthenticationHeaderValue]::new(
      'Bearer', [string]$secret.access_token
    )
  $deviceId = Get-ConfigValue 'device-id'
  $client.DefaultRequestHeaders.Add('X-Device-Id', $deviceId)
  $client.DefaultRequestHeaders.Add('X-Terminal-Device-Id', $deviceId)
  $client.DefaultRequestHeaders.Add(
    'X-Terminal-Account-Id',
    (Get-ConfigValue 'terminal-account-id')
  )

  $latest = 0L
  for ($page = 0; $page -lt 20; $page++) {
    $baselineResponse = $client.GetAsync(
      $origin + '/api/im/sync/events?afterSequence=' + $latest +
        '&waitSeconds=0&take=500'
    ).GetAwaiter().GetResult()
    try {
      $baselineBody = $baselineResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      $baseline = $baselineBody | ConvertFrom-Json
      $baselineEvents = @($baseline.events)
      $next = [long]$baseline.latestSequence
      if ([int]$baselineResponse.StatusCode -ne 200 -or $next -lt $latest) {
        throw 'Unable to establish the long-poll baseline.'
      }
      if ($baselineEvents.Count -gt 0 -and $next -le $latest) {
        throw 'The event baseline did not advance.'
      }
      $latest = $next
      if ($baselineEvents.Count -lt 500) { break }
    } finally {
      $baselineResponse.Dispose()
    }
  }
  if ($baselineEvents.Count -ge 500) {
    throw 'The event baseline exceeded the bounded page limit.'
  }

  $allowedRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\test\evidence')
  )
  $target = [IO.Path]::GetFullPath($OutputPath)
  $ready = [IO.Path]::GetFullPath($ReadyPath)
  foreach ($path in @($target, $ready)) {
    if (-not $path.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Evidence paths must stay inside Mobile/test/evidence.'
    }
  }
  if (Test-Path -LiteralPath $ready) {
    throw 'The ready signal already exists; use a unique evidence path.'
  }
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
  [ordered]@{
    baselineLatestSequence = $latest
    readyAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  } | ConvertTo-Json | Set-Content -LiteralPath $ready -Encoding UTF8

  $startedAt = [DateTimeOffset]::UtcNow
  $response = $client.GetAsync(
    $origin + '/api/im/sync/events?afterSequence=' + $latest +
      '&waitSeconds=25&take=500'
  ).GetAwaiter().GetResult()
  try {
    $completedAt = [DateTimeOffset]::UtcNow
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $payload = $body | ConvertFrom-Json
    $events = @($payload.events)
    $matching = @($events | Where-Object {
      if ($_.type -ne 'message.created') { return $false }
      try {
        $eventPayload = [string]$_.payloadJson | ConvertFrom-Json
        return [string]$eventPayload.ConversationId -eq $ExpectedConversationId
      } catch {
        return $false
      }
    })
    $summary = [ordered]@{
      source = 'installed-desktop-test-session'
      account = 'test01'
      baselineLatestSequence = $latest
      startedAtUtc = $startedAt.ToString('o')
      completedAtUtc = $completedAt.ToString('o')
      durationMs = [Math]::Round(($completedAt - $startedAt).TotalMilliseconds, 3)
      httpStatus = [int]$response.StatusCode
      requestId = Read-RequestId $response
      returnedEvents = $events.Count
      matchingConversationEvents = $matching.Count
      latestSequence = [long]$payload.latestSequence
      resetRequired = [bool]$payload.resetRequired
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $target -Encoding UTF8
    $summary | ConvertTo-Json -Depth 4
  } finally {
    $response.Dispose()
  }
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
