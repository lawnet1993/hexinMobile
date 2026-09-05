param()

# Read-only/negative-path probe for the IM push-device contract. The only PUT
# request contains deliberately malformed JSON so model binding rejects it
# before application state can be changed. Never emit tokens or device IDs.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http

$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw

function ConfigValue([string]$Name) {
  $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
  if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

function New-ProbeClient([string]$Token, [string]$DeviceId, [string]$AccountId) {
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(15)
  if ($Token) {
    $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
  }
  if ($DeviceId) {
    $client.DefaultRequestHeaders.Add('X-Device-Id', $DeviceId)
    $client.DefaultRequestHeaders.Add('X-Terminal-Device-Id', $DeviceId)
  }
  if ($AccountId) { $client.DefaultRequestHeaders.Add('X-Terminal-Account-Id', $AccountId) }
  return $client
}

function Get-RequestId([Net.Http.HttpResponseMessage]$Response) {
  foreach ($header in @('X-Request-ID', 'X-Correlation-ID', 'Request-Id')) {
    if ($Response.Headers.Contains($header)) {
      return ($Response.Headers.GetValues($header) -join ',')
    }
  }
  return $null
}

function Send-Probe(
  [Net.Http.HttpClient]$Client,
  [string]$Origin,
  [string]$Method,
  [switch]$MalformedJson
) {
  $request = [Net.Http.HttpRequestMessage]::new(
    [Net.Http.HttpMethod]::new($Method),
    $Origin + '/api/im/push/devices/current'
  )
  try {
    if ($MalformedJson) {
      $request.Content = [Net.Http.StringContent]::new('{', [Text.Encoding]::UTF8, 'application/json')
    }
    $response = $Client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    try {
      $data = $null
      $contentType = [string]$response.Content.Headers.ContentType.MediaType
      if ($contentType -match 'json') {
        $length = $response.Content.Headers.ContentLength
        if ($null -eq $length -or $length -le 65536) {
          $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
          try { $data = ConvertFrom-Json -InputObject $body -NoEnumerate } catch { }
          $body = $null
        }
      }
      return [pscustomobject]@{
        Status = [int]$response.StatusCode
        RequestId = Get-RequestId $response
        ContentType = $contentType
        Data = $data
      }
    } finally { $response.Dispose() }
  } finally { $request.Dispose() }
}

function Basic-Summary($Result) {
  return [ordered]@{
    status = $Result.Status
    requestId = $Result.RequestId
    contentType = $Result.ContentType
  }
}

$plain = $null
$secret = $null
$authenticated = $null
$unauthenticated = $null
$missingDevice = $null
try {
  $imUri = [uri](ConfigValue 'collaboration-im-api-url')
  if ($imUri.Scheme -notin @('http','https') -or $imUri.Host -ne 'api.sfhkh.com' -or $imUri.UserInfo) {
    throw 'Desktop origin is not the authorized test environment.'
  }
  $origin = $imUri.GetLeftPart([UriPartial]::Authority)
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') {
    throw 'Desktop account is not an authorized numbered test account.'
  }
  $deviceId = ConfigValue 'device-id'
  $accountId = ConfigValue 'terminal-account-id'
  $authenticated = New-ProbeClient ([string]$secret.access_token) $deviceId $accountId
  $unauthenticated = New-ProbeClient '' $deviceId $accountId
  $missingDevice = New-ProbeClient ([string]$secret.access_token) '' $accountId

  $authGet = Send-Probe $authenticated $origin 'GET'
  $unauthGet = Send-Probe $unauthenticated $origin 'GET'
  $missingDeviceGet = Send-Probe $missingDevice $origin 'GET'
  $authMalformedPut = Send-Probe $authenticated $origin 'PUT' -MalformedJson
  $unauthMalformedPut = Send-Probe $unauthenticated $origin 'PUT' -MalformedJson

  $registration = $null
  if ($authGet.Status -eq 200 -and $null -ne $authGet.Data) {
    $fields = @($authGet.Data.PSObject.Properties.Name)
    $tokenProperty = $authGet.Data.PSObject.Properties['token']
    $registration = [ordered]@{
      responseFields = $fields
      hasDeviceId = -not [string]::IsNullOrWhiteSpace([string]$authGet.Data.deviceId)
      platform = [string]$authGet.Data.platform
      provider = [string]$authGet.Data.provider
      privacyMode = [string]$authGet.Data.privacyMode
      isEnabled = $authGet.Data.isEnabled
      lastPushEventSequence = $authGet.Data.lastPushEventSequence
      updatedAt = [string]$authGet.Data.updatedAt
      tokenFieldReturned = $null -ne $tokenProperty
      tokenValueReturned = $null -ne $tokenProperty -and -not [string]::IsNullOrWhiteSpace([string]$tokenProperty.Value)
    }
  }

  [ordered]@{
    checkedAt = [DateTimeOffset]::Now.ToString('o')
    environment = 'authorized-test'
    accountClass = 'numbered-test-account'
    contractPath = '/api/im/push/devices/current'
    authenticatedGet = Basic-Summary $authGet
    unauthenticatedGet = Basic-Summary $unauthGet
    missingDeviceGet = Basic-Summary $missingDeviceGet
    authenticatedMalformedPut = Basic-Summary $authMalformedPut
    unauthenticatedMalformedPut = Basic-Summary $unauthMalformedPut
    currentRegistration = $registration
  } | ConvertTo-Json -Depth 8
} catch {
  [ordered]@{
    checkedAt = [DateTimeOffset]::Now.ToString('o')
    environment = 'authorized-test'
    fatalErrorType = $_.Exception.GetType().Name
  } | ConvertTo-Json -Depth 4
  exit 1
} finally {
  foreach ($client in @($authenticated,$unauthenticated,$missingDevice)) {
    if ($client) { $client.Dispose() }
  }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
  $deviceId = $null
  $accountId = $null
}
