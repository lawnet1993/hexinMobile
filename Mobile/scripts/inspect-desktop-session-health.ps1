param(
  [guid[]]$ApprovalId = @()
)

# Read-only inspection of the installed desktop test session. Never exports
# credentials, account/device claims, response bodies, or attachment addresses.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http
$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$binary = 'C:\Users\86137\AppData\Local\HexingZhilian\hexing-zhilian.exe'
$plain = $null
$secret = $null
$client = $null
function TimeHints([string]$Value) {
  try {
    if ($Value.Length -gt 16384) { return @{ available=$false } }
    $parts = $Value.Split('.')
    if ($parts.Count -ne 3) { return @{ available=$false } }
    $part = $parts[1].Replace('-', '+').Replace('_', '/')
    $part += '=' * ((4 - $part.Length % 4) % 4)
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
    $result = [ordered]@{ verified=$false; available=$false }
    foreach ($name in @('iat','nbf','exp')) {
      $claimValue = $claims.$name
      if (($claimValue -is [int] -or $claimValue -is [long]) -and $claimValue -ge 0 -and $claimValue -lt 100000000000) {
        $result[$name] = [DateTimeOffset]::FromUnixTimeSeconds($claimValue).ToString('o')
        $result.available = $true
      }
    }
    return $result
  } catch { return @{ available=$false } }
}
try {
  $config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
  function ConfigValue([string]$Name) {
    $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
    if (-not $match.Success) { throw 'Required configuration absent.' }
    return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
  }
  $uri = [uri](ConfigValue 'collaboration-oa-api-url')
  if ($uri.Host -ne 'api.sfhkh.com' -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo) { throw 'Not the authorized test origin.' }
  $origin = $uri.GetLeftPart([UriPartial]::Authority)
  $sessionPath = Join-Path $appDir 'managed_access_session.bin'
  $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($sessionPath), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') { throw 'Not a numbered test account.' }
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(10)
  function ReadStatus([string]$Path) {
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $origin + $Path)
    $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', [string]$secret.access_token)
    $request.Headers.Add('X-Device-Id', (ConfigValue 'device-id'))
    $request.Headers.Add('X-Terminal-Device-Id', (ConfigValue 'device-id'))
    $request.Headers.Add('X-Terminal-Account-Id', (ConfigValue 'terminal-account-id'))
    try {
      $response = $client.SendAsync($request).GetAwaiter().GetResult()
      try { return [int]$response.StatusCode } finally { $response.Dispose() }
    } finally { $request.Dispose() }
  }
  [ordered]@{
    checkedAt=[DateTimeOffset]::Now.ToString('o')
    source='installed-desktop-dpapi-and-read-only-get-not-ui'
    version=(Get-Item -LiteralPath $binary).VersionInfo.FileVersion
    running=@(Get-Process -Name 'hexing-zhilian' -ErrorAction SilentlyContinue).Count -gt 0
    account=[string]$secret.saved_username
    sessionFileUpdatedAt=(Get-Item -LiteralPath $sessionPath).LastWriteTimeUtc.ToString('o')
    accessTokenTimes=(TimeHints ([string]$secret.access_token))
    hasRefreshToken=(-not [string]::IsNullOrEmpty([string]$secret.refresh_token))
    refreshTokenTimes=(TimeHints ([string]$secret.refresh_token))
    imStatus=(ReadStatus '/api/im/bootstrap')
    oaStatus=(ReadStatus '/api/oa/bootstrap')
    approvalStatuses=@($ApprovalId | ForEach-Object {
      [ordered]@{
        requestId=$_.ToString()
        status=(ReadStatus ('/api/oa/approval-requests/' + $_.ToString()))
      }
    })
  } | ConvertTo-Json -Depth 5
} catch {
  Write-Output ('Read-only session inspection failed: ' + $_.Exception.GetType().Name)
  exit 1
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain,0,$plain.Length) }
  $secret=$null
  $config=$null
}
