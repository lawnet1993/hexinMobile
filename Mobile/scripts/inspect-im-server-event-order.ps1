param(
  [Parameter(Mandatory = $true)]
  [ValidateRange(0, [long]::MaxValue)]
  [long]$AfterSequence,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^AI-UAT-[A-Z0-9-]+-$')]
  [string[]]$Prefixes,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

# Reads authorized test-account events and emits only aggregate delivery order.
# Credentials, device identifiers, message bodies and server identifiers are
# deliberately excluded from the evidence file and console output.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http

$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
$plain = $null
$secret = $null
$client = $null

function Get-ConfigValue([string]$Name) {
  $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
  if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
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

  $client = [Net.Http.HttpClient]::new()
  $client.Timeout = [TimeSpan]::FromSeconds(15)
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

  $response = $client.GetAsync(
    $origin + '/api/im/sync/events?afterSequence=' + $AfterSequence +
      '&waitSeconds=0&take=500'
  ).GetAwaiter().GetResult()
  try {
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ([int]$response.StatusCode -ne 200) {
      throw 'The event page could not be read.'
    }
    $payload = $body | ConvertFrom-Json
    $matches = foreach ($event in @($payload.events)) {
      if ([string]$event.type -ne 'message.created') { continue }
      try { $message = [string]$event.payloadJson | ConvertFrom-Json } catch { continue }
      $content = [string]$message.Content
      $prefixIndex = -1
      for ($i = 0; $i -lt $Prefixes.Count; $i++) {
        if ($content.StartsWith($Prefixes[$i], [StringComparison]::Ordinal)) {
          $prefixIndex = $i
          break
        }
      }
      if ($prefixIndex -lt 0) { continue }
      [pscustomobject]@{
        prefix = $Prefixes[$prefixIndex]
        eventSequence = [long]$event.sequence
        createdAtUtc = ([DateTimeOffset]$event.createdAt).ToUniversalTime().ToString('o')
      }
    }

    $groups = foreach ($prefix in $Prefixes) {
      $items = @($matches | Where-Object prefix -eq $prefix | Sort-Object eventSequence)
      [ordered]@{
        prefix = $prefix
        count = $items.Count
        firstEventSequence = if ($items.Count) { $items[0].eventSequence } else { $null }
        lastEventSequence = if ($items.Count) { $items[-1].eventSequence } else { $null }
        firstCreatedAtUtc = if ($items.Count) { $items[0].createdAtUtc } else { $null }
        lastCreatedAtUtc = if ($items.Count) { $items[-1].createdAtUtc } else { $null }
      }
    }
    $summary = [ordered]@{
      checkedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
      afterSequence = $AfterSequence
      latestSequence = [long]$payload.latestSequence
      returnedEvents = @($payload.events).Count
      matchedEvents = @($matches).Count
      byPrefix = $groups
    }

    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
    $target = [IO.Path]::GetFullPath($OutputPath)
    if (-not $target.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Evidence path must stay inside Mobile/test/evidence.'
    }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $target -Encoding UTF8
    $summary | ConvertTo-Json -Depth 5
  } finally {
    $response.Dispose()
  }
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
