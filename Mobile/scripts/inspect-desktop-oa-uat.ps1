param(
  [string]$Marker = 'AI-UAT-20260902-165500-LEAVE',
  [ValidateSet('all', 'pending', 'initiated', 'cc', 'completed', 'draft')]
  [string]$View = 'initiated',
  [switch]$IncludeEvents,
  [switch]$VerifyCancellationText,
  [switch]$InspectFormSchemas,
  [guid[]]$ApprovalId = @(),
  [ValidateRange(0, 2147483647)][long]$AfterSequence = 0
)

# Read-only corroboration of UI-created test requests. Never emit raw payloads,
# credentials, device identity, attachment URLs, or unrelated business data.
$ErrorActionPreference = 'Stop'
if ($Marker -notmatch '^AI-UAT-[A-Za-z0-9-]+$') { throw 'An AI-UAT marker is required.' }
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
$origin = $uri.GetLeftPart([UriPartial]::Authority)
$plain = $null
$secret = $null
$client = $null
try {
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') { throw 'Not a numbered test account.' }
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(15)
  $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', [string]$secret.access_token)
  $client.DefaultRequestHeaders.Add('X-Device-Id', (ConfigValue 'device-id'))
  $client.DefaultRequestHeaders.Add('X-Terminal-Device-Id', (ConfigValue 'device-id'))
  $client.DefaultRequestHeaders.Add('X-Terminal-Account-Id', (ConfigValue 'terminal-account-id'))
  function ReadEndpoint([string]$Path) {
    $response = $client.GetAsync($origin + $Path).GetAwaiter().GetResult()
    try {
      $payload = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      $data = $null
      try { $data = ConvertFrom-Json -InputObject $payload -NoEnumerate } catch { }
      $requestId = $null
      foreach ($header in @('X-Request-ID', 'X-Correlation-ID', 'Request-Id')) {
        if ($response.Headers.Contains($header)) { $requestId = $response.Headers.GetValues($header) -join ','; break }
      }
      return [pscustomobject]@{ status=[int]$response.StatusCode; requestId=$requestId; data=$data }
    } finally { $response.Dispose() }
  }
  $bootstrap = ReadEndpoint '/api/oa/bootstrap'
  $summary = [ordered]@{ checkedAt=[DateTimeOffset]::Now.ToString('o'); origin=$origin; account=[string]$secret.saved_username; marker=$Marker; bootstrapStatus=$bootstrap.status; requestId=$bootstrap.requestId }
  if ($InspectFormSchemas) {
    $summary.templates = @($bootstrap.data.approvalTemplates | Where-Object { $null -ne $_ } | ForEach-Object {
      $template = $_
      $schema = $null
      try { $schema = [string]$template.formSchemaJson | ConvertFrom-Json } catch { }
      [ordered]@{
        id=$template.id; name=$template.name; version=$template.version
        schemaParsed=($null -ne $schema)
        fields=@($schema.fields | Where-Object { $null -ne $_ } | ForEach-Object {
          [ordered]@{id=$_.id;label=$_.label;type=$_.type;readOnly=($_.readOnly -eq $true);required=($_.required -eq $true)}
        })
      }
    })
    $summary | ConvertTo-Json -Depth 6
    return
  }
  $page = ReadEndpoint ('/api/oa/approval-requests/page?view=' + [Uri]::EscapeDataString($View) + '&take=100')
  $summary.pageStatus = $page.status
  $summary.pageRequestId = $page.requestId
  $summary.hasMore = $page.data.hasMore
  $matches = @(@($bootstrap.data.approvalRequests) + @($page.data.items) | Where-Object {
    $_ -and ([string]$_.formDataJson).Contains($Marker)
  } | Sort-Object id -Unique)
  $candidateIds = @(@($matches | ForEach-Object { [string]$_.id }) + @($ApprovalId | ForEach-Object { $_.ToString() }) | Sort-Object -Unique)
  $summary.requests = @($candidateIds | ForEach-Object {
    $candidateId = $_
    $detail = ReadEndpoint ('/api/oa/approval-requests/' + $candidateId)
    $r = $detail.data
    # Explicit IDs allow inspecting transferred/finished requests absent from
    # bootstrap, but never expose a different business request's contents.
    $markerMatched = $detail.status -eq 200 -and ([string]$r.formDataJson).Contains($Marker)
    if (-not $markerMatched) {
      [ordered]@{ id=$candidateId; detailStatus=$detail.status; requestId=$detail.requestId; markerMatched=$false }
      return
    }
    [ordered]@{
      id=$r.id; detailStatus=$detail.status; requestId=$detail.requestId; markerMatched=$true; status=$r.status
      title=$r.title; requesterName=$r.requesterName; requesterDepartmentName=$r.requesterDepartmentName
      createdAt=$r.createdAt; updatedAt=$r.updatedAt; allowedActions=$r.allowedActions
      templateVersion=$r.templateVersion; requestVersion=$r.version; workflowKey=$r.workflowKey; clientRequestId=$r.clientRequestId; completedAt=$r.completedAt; fields=@($r.PSObject.Properties.Name)
      tasks=@($r.tasks | Select-Object id,nodeName,assigneeId,assigneeName,assigneeDepartmentName,status,version,canOperate,completedAt)
      actions=@($r.actions | Select-Object id,action,actorName,comment,occurredAt)
      attachments=@($r.attachments | Select-Object id,fileName,size,contentType,formFieldId)
      notifications=@($bootstrap.data.notifications | Where-Object {$_.requestId -eq $r.id} | Select-Object id,type,isRead,readAt,createdAt)
    }
  })
  $summary.matchCount = @($summary.requests | Where-Object markerMatched -eq $true).Count
  if ($VerifyCancellationText) {
    $verifiedIds = @($summary.requests | Where-Object markerMatched -eq $true | ForEach-Object { $_.id })
    # Fixed predicates only: never export untrusted notification body text.
    $summary.cancellationText = @($bootstrap.data.notifications | Where-Object {
      $_.requestId -in $verifiedIds -and $_.type -eq 'approval.task.canceled'
    } | ForEach-Object {
      [ordered]@{
        notificationId=$_.id; approvalId=$_.requestId
        saysOtherHandlerCompleted=([string]$_.body -eq '该节点已由其他处理人完成')
        mentionsWithdrawal=([string]$_.body -match '撤回')
      }
    })
  }
  if ($IncludeEvents) {
    $targetIds = @($summary.requests | Where-Object markerMatched -eq $true | ForEach-Object { $_.id })
    $eventPage = ReadEndpoint ('/api/oa/sync/events?afterSequence=' + $AfterSequence + '&waitSeconds=0&take=200')
    $summary.sync = [ordered]@{
      status=$eventPage.status; requestId=$eventPage.requestId
      latestSequence=$eventPage.data.latestSequence
      afterSequence=$AfterSequence
      totalReturned=@($eventPage.data.events).Count
      events=@($eventPage.data.events | ForEach-Object {
        $event = $_
        $payload = $null
        try { $payload = [string]$event.payloadJson | ConvertFrom-Json } catch { }
        $targetId = [string]$payload.requestId
        if (-not $targetId) { $targetId = [string]$payload.approvalRequestId }
        if ($targetId -in $targetIds) {
          [ordered]@{
            id=$event.id; sequence=$event.sequence; type=$event.type
            requestId=$targetId; createdAt=$event.createdAt
            payloadFields=@($payload.PSObject.Properties.Name)
          }
        }
      })
    }
  }
  $summary | ConvertTo-Json -Depth 10
} catch {
  Write-Output ('Read-only OA inspection failed: ' + $_.Exception.GetType().Name)
  exit 1
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret=$null; $config=$null
}
