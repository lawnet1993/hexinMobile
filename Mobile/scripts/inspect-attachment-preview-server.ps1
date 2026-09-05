param(
  [Guid]$OaAttachmentId = 'f9ebf8e3-b657-4009-a9e5-dd58ac65dad4',
  [Guid]$ImMessageId = '090bcabc-244d-4bcb-a5d7-66584f36b2de',
  [Guid]$ImMediaAttachmentId = 'fb1ae10c-d90a-442f-9a9c-f0e7da0ca5ea'
)

# Destructive scope: none. This probe only creates short-lived preview sessions
# for existing AI-UAT attachments and revokes every session it creates.
# It never emits credentials, device/account identifiers, tickets, preview URLs,
# original download URLs, response bodies, attachment names, or attachment bytes.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http

$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$configPath = Join-Path $appDir 'managed_access.yaml'
$sessionPath = Join-Path $appDir 'managed_access_session.bin'
$config = Get-Content -LiteralPath $configPath -Raw

function ConfigValue([string]$Name) {
  $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
  if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

function Get-RequestId([Net.Http.HttpResponseMessage]$Response) {
  foreach ($header in @('X-Request-ID', 'X-Correlation-ID', 'Request-Id')) {
    if ($Response.Headers.Contains($header)) {
      return ($Response.Headers.GetValues($header) -join ',')
    }
  }
  return $null
}

function Get-Header([Net.Http.HttpResponseMessage]$Response, [string]$Name) {
  if ($Response.Headers.Contains($Name)) { return ($Response.Headers.GetValues($Name) -join ',') }
  if ($Response.Content.Headers.Contains($Name)) { return ($Response.Content.Headers.GetValues($Name) -join ',') }
  return $null
}

function New-ProbeClient([string]$Token, [string]$DeviceId, [string]$AccountId) {
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(20)
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

function Send-ProbeRequest(
  [Net.Http.HttpClient]$Client,
  [string]$Origin,
  [string]$Method,
  [string]$Path,
  [string]$Range = '',
  [switch]$ReadJson
) {
  $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Origin + $Path)
  try {
    if ($Range) { $request.Headers.TryAddWithoutValidation('Range', $Range) | Out-Null }
    $response = $Client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    try {
      $data = $null
      $bodyLength = $null
      $jsonParsed = $false
      # Some deployed preview-session endpoints currently omit the JSON
      # Content-Type header even though the body is a JSON object.  Keep the
      # probe bounded and parse the small response body whenever JSON was
      # requested so the sanitized field summary remains useful.
      if ($ReadJson) {
        $length = $response.Content.Headers.ContentLength
        if ($null -eq $length -or $length -le 65536) {
          $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
          $bodyLength = $body.Length
          try {
            # Keep compatibility with Windows PowerShell 5.1, where
            # ConvertFrom-Json does not expose -NoEnumerate.
            $data = ConvertFrom-Json -InputObject $body
            $jsonParsed = $null -ne $data
          } catch { }
          $body = $null
        }
      }
      return [pscustomobject]@{
        Status = [int]$response.StatusCode
        RequestId = Get-RequestId $response
        Data = $data
        BodyLength = $bodyLength
        JsonParsed = $jsonParsed
        ContentType = [string]$response.Content.Headers.ContentType.MediaType
        ContentLength = $response.Content.Headers.ContentLength
        ContentRange = [string]$response.Content.Headers.ContentRange
        AcceptRanges = [string]($response.Headers.AcceptRanges -join ',')
        ContentDisposition = [string]$response.Content.Headers.ContentDisposition.DispositionType
        CacheControl = [string]$response.Headers.CacheControl
        ReferrerPolicy = Get-Header $response 'Referrer-Policy'
        ContentTypeOptions = Get-Header $response 'X-Content-Type-Options'
        ContentSecurityPolicy = Get-Header $response 'Content-Security-Policy'
      }
    } finally {
      $response.Dispose()
    }
  } finally {
    $request.Dispose()
  }
}

function Test-PreviewUrl([string]$Service, [string]$SessionId, [string]$PreviewUrl) {
  if (-not $PreviewUrl -or -not $SessionId) { return $false }
  if ($PreviewUrl -match '[\\#\r\n]' -or $PreviewUrl.StartsWith('//')) { return $false }
  $escaped = [regex]::Escape($SessionId)
  return $PreviewUrl -match ('^/api/' + $Service + '/attachment-preview-sessions/' + $escaped + '/content\?ticket=[A-Za-z0-9._~-]+$')
}

function Content-Summary($Result) {
  return [ordered]@{
    status = $Result.Status
    requestId = $Result.RequestId
    contentType = $Result.ContentType
    contentLength = $Result.ContentLength
    contentRangePresent = -not [string]::IsNullOrWhiteSpace($Result.ContentRange)
    acceptRangesBytes = $Result.AcceptRanges -match 'bytes'
    disposition = $Result.ContentDisposition
    cacheControlNoStore = $Result.CacheControl -match 'no-store'
    referrerPolicyNoReferrer = $Result.ReferrerPolicy -eq 'no-referrer'
    contentTypeOptionsNoSniff = $Result.ContentTypeOptions -eq 'nosniff'
    cspPresent = -not [string]::IsNullOrWhiteSpace($Result.ContentSecurityPolicy)
  }
}

function Session-Summary([string]$Service, $Result) {
  $data = $Result.Data
  $sessionId = [string]$data.sessionId
  $previewUrl = [string]$data.previewUrl
  return [ordered]@{
    statusCode = $Result.Status
    requestId = $Result.RequestId
    bodyLength = $Result.BodyLength
    jsonParsed = $Result.JsonParsed
    responseFields = @($data.PSObject.Properties.Name)
    status = [string]$data.status
    previewKind = [string]$data.previewKind
    contentType = [string]$data.contentType
    hasSessionId = -not [string]::IsNullOrWhiteSpace($sessionId)
    hasPreviewUrl = -not [string]::IsNullOrWhiteSpace($previewUrl)
    previewUrlShapeValid = Test-PreviewUrl $Service $sessionId $previewUrl
    expiresAt = [string]$data.expiresAt
    renewAfterSeconds = $data.renewAfterSeconds
    originalDownloadAllowed = $data.originalDownloadAllowed
    hasOriginalDownloadUrl = -not [string]::IsNullOrWhiteSpace([string]$data.originalDownloadUrl)
  }
}

function Probe-Target(
  [string]$Name,
  [string]$Service,
  [string]$Origin,
  [string]$CreatePath,
  [Net.Http.HttpClient]$Client,
  [Net.Http.HttpClient]$UnauthenticatedClient,
  [Net.Http.HttpClient]$WrongDeviceClient
) {
  $created = [Collections.Generic.List[object]]::new()
  $result = [ordered]@{ name = $Name; service = $Service; createPathShape = $CreatePath -replace '[a-fA-F0-9-]{36}', '{id}' }
  try {
    $unauth = Send-ProbeRequest $UnauthenticatedClient $Origin 'POST' $CreatePath -ReadJson
    $result.unauthenticatedCreate = [ordered]@{ status = $unauth.Status; requestId = $unauth.RequestId }

    $first = Send-ProbeRequest $Client $Origin 'POST' $CreatePath -ReadJson
    $result.create = Session-Summary $Service $first
    $firstData = $first.Data
    $firstSessionId = [string]$firstData.sessionId
    $firstPreviewUrl = [string]$firstData.previewUrl
    if ($firstSessionId) { $created.Add([pscustomobject]@{ Service=$Service; Origin=$Origin; SessionId=$firstSessionId }) }

    if ($first.Status -ne 200 -or [string]$firstData.status -ne 'ready' -or -not (Test-PreviewUrl $Service $firstSessionId $firstPreviewUrl)) {
      return $result
    }

    $range = Send-ProbeRequest $Client $Origin 'GET' $firstPreviewUrl 'bytes=0-31'
    $result.contentRange = Content-Summary $range
    $head = Send-ProbeRequest $Client $Origin 'HEAD' $firstPreviewUrl
    $result.contentHead = Content-Summary $head

    $wrongTicketPath = $firstPreviewUrl -replace 'ticket=[^&]+', 'ticket=invalid-preview-ticket'
    $wrongTicket = Send-ProbeRequest $Client $Origin 'HEAD' $wrongTicketPath
    $result.wrongTicket = [ordered]@{ status=$wrongTicket.Status; requestId=$wrongTicket.RequestId }

    $renewPath = '/api/' + $Service + '/attachment-preview-sessions/' + $firstSessionId + '/renew'
    $renew = Send-ProbeRequest $Client $Origin 'POST' $renewPath -ReadJson
    $result.renewSameDevice = [ordered]@{
      status=$renew.Status; requestId=$renew.RequestId
      responseFields=@($renew.Data.PSObject.Properties.Name)
      renewAfterSeconds=$renew.Data.renewAfterSeconds
      expiresAt=[string]$renew.Data.expiresAt
    }
    $wrongRenew = Send-ProbeRequest $WrongDeviceClient $Origin 'POST' $renewPath -ReadJson
    $result.renewWrongDevice = [ordered]@{ status=$wrongRenew.Status; requestId=$wrongRenew.RequestId }

    $downloadUrl = [string]$firstData.originalDownloadUrl
    if ($firstData.originalDownloadAllowed -eq $true -and $downloadUrl -match ('^/api/' + $Service + '/')) {
      $download = Send-ProbeRequest $Client $Origin 'GET' $downloadUrl 'bytes=0-0'
      $result.originalDownload = Content-Summary $download
    }

    $second = Send-ProbeRequest $Client $Origin 'POST' $CreatePath -ReadJson
    $result.duplicateCreate = Session-Summary $Service $second
    $secondData = $second.Data
    $secondSessionId = [string]$secondData.sessionId
    $secondPreviewUrl = [string]$secondData.previewUrl
    if ($secondSessionId) { $created.Add([pscustomobject]@{ Service=$Service; Origin=$Origin; SessionId=$secondSessionId }) }
    if ($second.Status -eq 200 -and [string]$secondData.status -eq 'ready' -and (Test-PreviewUrl $Service $secondSessionId $secondPreviewUrl)) {
      $oldAfterDuplicate = Send-ProbeRequest $Client $Origin 'HEAD' $firstPreviewUrl
      $result.oldSessionAfterDuplicate = [ordered]@{ status=$oldAfterDuplicate.Status; requestId=$oldAfterDuplicate.RequestId }

      $closePath = '/api/' + $Service + '/attachment-preview-sessions/' + $secondSessionId
      $close = Send-ProbeRequest $Client $Origin 'DELETE' $closePath
      $result.close = [ordered]@{ status=$close.Status; requestId=$close.RequestId }
      $closeAgain = Send-ProbeRequest $Client $Origin 'DELETE' $closePath
      $result.closeAgain = [ordered]@{ status=$closeAgain.Status; requestId=$closeAgain.RequestId }
      $afterClose = Send-ProbeRequest $Client $Origin 'HEAD' $secondPreviewUrl
      $result.contentAfterClose = [ordered]@{ status=$afterClose.Status; requestId=$afterClose.RequestId }
    }
    return $result
  } catch {
    $result.probeErrorType = $_.Exception.GetType().Name
    return $result
  } finally {
    foreach ($session in $created) {
      try {
        $cleanupPath = '/api/' + $session.Service + '/attachment-preview-sessions/' + $session.SessionId
        $null = Send-ProbeRequest $Client $session.Origin 'DELETE' $cleanupPath
      } catch { }
    }
  }
}

$plain = $null
$secret = $null
$oaClient = $null
$imClient = $null
$oaUnauth = $null
$imUnauth = $null
$oaWrongDevice = $null
$imWrongDevice = $null
try {
  $oaUri = [uri](ConfigValue 'collaboration-oa-api-url')
  $imUri = [uri](ConfigValue 'collaboration-im-api-url')
  foreach ($uri in @($oaUri, $imUri)) {
    if ($uri.Scheme -notin @('http','https') -or $uri.Host -ne 'api.sfhkh.com' -or $uri.UserInfo) {
      throw 'Desktop origin is not the authorized test environment.'
    }
  }
  $oaOrigin = $oaUri.GetLeftPart([UriPartial]::Authority)
  $imOrigin = $imUri.GetLeftPart([UriPartial]::Authority)
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes($sessionPath), $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') {
    throw 'Desktop account is not an authorized numbered test account.'
  }
  $deviceId = ConfigValue 'device-id'
  $accountId = ConfigValue 'terminal-account-id'
  $wrongDeviceId = 'preview-probe-' + [Guid]::NewGuid().ToString('N')

  $oaClient = New-ProbeClient ([string]$secret.access_token) $deviceId $accountId
  $imClient = New-ProbeClient ([string]$secret.access_token) $deviceId $accountId
  $oaUnauth = New-ProbeClient '' $deviceId $accountId
  $imUnauth = New-ProbeClient '' $deviceId $accountId
  $oaWrongDevice = New-ProbeClient ([string]$secret.access_token) $wrongDeviceId $accountId
  $imWrongDevice = New-ProbeClient ([string]$secret.access_token) $wrongDeviceId $accountId

  # Prove that authentication, the services, and the selected AI-UAT objects are
  # still valid. This distinguishes a missing preview-session route from a stale
  # login or an inaccessible attachment.
  $oaBootstrap = Send-ProbeRequest $oaClient $oaOrigin 'GET' '/api/oa/bootstrap' -ReadJson
  $imBootstrap = Send-ProbeRequest $imClient $imOrigin 'GET' '/api/im/bootstrap' -ReadJson
  $oaOriginal = Send-ProbeRequest $oaClient $oaOrigin 'GET' ('/api/oa/attachments/' + $OaAttachmentId) 'bytes=0-0'
  $imMessageOriginal = Send-ProbeRequest $imClient $imOrigin 'GET' ('/api/im/messages/' + $ImMessageId + '/attachment') 'bytes=0-0'
  $imMediaOriginal = Send-ProbeRequest $imClient $imOrigin 'GET' ('/api/im/media-attachments/' + $ImMediaAttachmentId) 'bytes=0-0'
  $imMediaCover = Send-ProbeRequest $imClient $imOrigin 'GET' ('/api/im/media-attachments/' + $ImMediaAttachmentId + '?cover=true') 'bytes=0-0'

  $targets = @(
    Probe-Target 'oa-attachment' 'oa' $oaOrigin ('/api/oa/attachments/' + $OaAttachmentId + '/preview-sessions') $oaClient $oaUnauth $oaWrongDevice
    Probe-Target 'im-message-attachment' 'im' $imOrigin ('/api/im/messages/' + $ImMessageId + '/attachment/preview-sessions') $imClient $imUnauth $imWrongDevice
    Probe-Target 'im-media-attachment' 'im' $imOrigin ('/api/im/media-attachments/' + $ImMediaAttachmentId + '/preview-sessions') $imClient $imUnauth $imWrongDevice
    Probe-Target 'im-media-cover' 'im' $imOrigin ('/api/im/media-attachments/' + $ImMediaAttachmentId + '/preview-sessions?cover=true') $imClient $imUnauth $imWrongDevice
  )
  [ordered]@{
    checkedAt = [DateTimeOffset]::Now.ToString('o')
    environment = 'authorized-test'
    accountClass = 'numbered-test-account'
    baseline = [ordered]@{
      oaBootstrap = [ordered]@{ status=$oaBootstrap.Status; requestId=$oaBootstrap.RequestId }
      imBootstrap = [ordered]@{ status=$imBootstrap.Status; requestId=$imBootstrap.RequestId }
      oaOriginal = Content-Summary $oaOriginal
      imMessageOriginal = Content-Summary $imMessageOriginal
      imMediaOriginal = Content-Summary $imMediaOriginal
      imMediaCover = Content-Summary $imMediaCover
    }
    targets = $targets
  } | ConvertTo-Json -Depth 12
} catch {
  [ordered]@{
    checkedAt = [DateTimeOffset]::Now.ToString('o')
    environment = 'authorized-test'
    fatalErrorType = $_.Exception.GetType().Name
  } | ConvertTo-Json -Depth 4
  exit 1
} finally {
  foreach ($client in @($oaClient,$imClient,$oaUnauth,$imUnauth,$oaWrongDevice,$imWrongDevice)) {
    if ($client) { $client.Dispose() }
  }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
  $deviceId = $null
  $accountId = $null
  $wrongDeviceId = $null
}
