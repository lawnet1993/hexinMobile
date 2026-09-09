param(
  [ValidateRange(1, 500)][int]$Take = 100
)

# Read-only OA capability survey for the authorized numbered UAT account.
# It intentionally emits only aggregate action counts and opaque request IDs
# that currently expose `return`; no credentials, form contents or people.
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

$uri = [uri](ConfigValue 'collaboration-oa-api-url')
if ($uri.Scheme -notin @('http', 'https') -or $uri.Host -ne 'api.sfhkh.com' -or $uri.UserInfo) {
  throw 'Not the authorized test origin.'
}

$plain = $null
$secret = $null
$client = $null
try {
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') {
    throw 'Not a numbered test account.'
  }

  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(15)
  $client.DefaultRequestHeaders.Authorization =
    [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', [string]$secret.access_token)
  $client.DefaultRequestHeaders.Add('X-Device-Id', (ConfigValue 'device-id'))
  $client.DefaultRequestHeaders.Add('X-Terminal-Device-Id', (ConfigValue 'device-id'))
  $client.DefaultRequestHeaders.Add('X-Terminal-Account-Id', (ConfigValue 'terminal-account-id'))

  function ReadEndpoint([string]$Path) {
    $response = $client.GetAsync($uri.GetLeftPart([UriPartial]::Authority) + $Path).GetAwaiter().GetResult()
    try {
      $payload = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      $data = $null
      try { $data = ConvertFrom-Json -InputObject $payload -NoEnumerate } catch { }
      return [pscustomobject]@{ status=[int]$response.StatusCode; data=$data }
    } finally {
      $response.Dispose()
    }
  }

  $actionCounts = @{}
  $completionModeCounts = @{}
  $taskCount = 0
  $tasksWithCompletionMode = 0
  $returnCandidates = [Collections.Generic.HashSet[string]]::new()
  $seen = [Collections.Generic.HashSet[string]]::new()
  $views = @('all', 'pending', 'initiated', 'cc', 'completed', 'draft')
  $viewSummaries = foreach ($view in $views) {
    $page = ReadEndpoint ('/api/oa/approval-requests/page?view=' + $view + '&take=' + $Take)
    $items = if ($page.status -eq 200) { @($page.data.items) } else { @() }
    foreach ($item in $items) {
      $id = [string]$item.id
      if (-not $id -or -not $seen.Add($id)) { continue }
      $detail = ReadEndpoint ('/api/oa/approval-requests/' + $id)
      if ($detail.status -ne 200) { continue }
      foreach ($action in @($detail.data.allowedActions)) {
        $key = [string]$action
        if (-not $key) { continue }
        if (-not $actionCounts.ContainsKey($key)) { $actionCounts[$key] = 0 }
        $actionCounts[$key]++
        if ($key -eq 'return') { [void]$returnCandidates.Add($id) }
      }
      foreach ($task in @($detail.data.tasks)) {
        $taskCount++
        $mode = [string]$task.completionMode
        if (-not $mode) { continue }
        $tasksWithCompletionMode++
        if (-not $completionModeCounts.ContainsKey($mode)) {
          $completionModeCounts[$mode] = 0
        }
        $completionModeCounts[$mode]++
      }
    }
    [ordered]@{ view=$view; status=$page.status; itemCount=$items.Count; hasMore=$page.data.hasMore }
  }

  [ordered]@{
    checkedAt=[DateTimeOffset]::Now.ToString('o')
    origin=$uri.GetLeftPart([UriPartial]::Authority)
    account=[string]$secret.saved_username
    views=$viewSummaries
    uniqueRequestsInspected=$seen.Count
    allowedActionCounts=[ordered]@{} + $actionCounts
    taskCount=$taskCount
    tasksWithCompletionMode=$tasksWithCompletionMode
    completionModeCounts=[ordered]@{} + $completionModeCounts
    returnCandidateCount=$returnCandidates.Count
    returnCandidateIds=@($returnCandidates | Sort-Object)
  } | ConvertTo-Json -Depth 6
} catch {
  Write-Output ('Read-only OA capability survey failed: ' + $_.Exception.GetType().Name)
  exit 1
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
