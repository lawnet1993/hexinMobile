param(
  [string]$GroupTitle = 'AI-UAT-20260902-162326-GROUP',
  [string]$ConversationId = '',
  [switch]$InspectGateway,
  [switch]$InspectConversationIndex,
  [switch]$ListTestDirects,
  [ValidateSet('test03','test04')][string]$InspectTestMember
)

# Read-only verification using the desktop app's existing authorized test session.
# Never emit credentials, device IDs, raw response bodies, or attachment URLs.
$ErrorActionPreference = 'Stop'
if (-not $GroupTitle.StartsWith('AI-UAT-')) { throw 'Only AI-UAT test groups are allowed.' }
if ($ConversationId -and $ConversationId -notmatch '^[a-fA-F0-9-]{36}$') { throw 'Invalid test conversation identifier.' }
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http
$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
function ConfigValue([string]$Name) {
  $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($Name) + ':\s*(.+)$')
  if (-not $match.Success) { throw 'Required desktop configuration is absent.' }
  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}
$imUri = [uri](ConfigValue $(if ($InspectGateway) { 'collaboration-im-grpc-url' } else { 'collaboration-im-api-url' }))
if ($imUri.Scheme -notin @('http', 'https') -or $imUri.Host -notin @('api.sfhkh.com', 'gw02.sfjxd.com') -or $imUri.UserInfo) {
  throw 'Desktop origin is not the authorized test environment.'
}
$origin = $imUri.GetLeftPart([System.UriPartial]::Authority)
$plain = $null
$client = $null
$secret = $null
try {
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$') {
    throw 'Desktop account is not an authorized numbered test account.'
  }
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
        if ($response.Headers.Contains($header)) { $requestId = ($response.Headers.GetValues($header) -join ','); break }
      }
      return [pscustomobject]@{ Status = [int]$response.StatusCode; RequestId = $requestId; Data = $data; Allow = @($response.Content.Headers.Allow); ContentType = [string]$response.Content.Headers.ContentType }
    } finally { $response.Dispose() }
  }
  if ($InspectTestMember) {
    $memberId = if ($InspectTestMember -eq 'test03') { 'c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc' } else { 'b6a2d272-aaca-4845-bbf8-294288c940a9' }
    $result = ReadEndpoint ('/api/im/members/' + $memberId + '/profile')
    [ordered]@{
      checkedAt=[DateTimeOffset]::Now.ToString('o');account=[string]$secret.saved_username
      target=$InspectTestMember;status=$result.Status;requestId=$result.RequestId
      memberId=$result.Data.id;username=$result.Data.userName
      presenceFieldPresent=($null -ne $result.Data.PSObject.Properties['isOnline'])
      isOnline=$result.Data.isOnline;lastSeenAt=$result.Data.lastSeenAt
    } | ConvertTo-Json -Depth 4
    return
  }
  if ($InspectConversationIndex) {
    $probes = foreach ($path in @('/api/im/conversations?take=50', '/api/im/conversations/page?page=1&pageSize=50')) {
      $result = ReadEndpoint $path
      $items = @()
      if ($result.Data -is [Array]) { $items = @($result.Data) }
      elseif ($null -ne $result.Data.items) { $items = @($result.Data.items) }
      [ordered]@{
        path = $path; status = $result.Status; contentType = $result.ContentType
        requestId = $result.RequestId; allow = $result.Allow
        responseType = if ($null -eq $result.Data) { 'null' } else { $result.Data.GetType().Name }
        fields = @($result.Data.PSObject.Properties.Name)
        itemCount = $items.Count
        itemFields = @($items | Select-Object -First 1 | ForEach-Object { $_.PSObject.Properties.Name })
        items = @($items | ForEach-Object { [ordered]@{id=$_.id;type=$_.type;lastMessageSequence=$_.lastMessageSequence;lastReadSequence=$_.lastReadSequence;unreadCount=$_.unreadCount} })
      }
    }
    [ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');account=[string]$secret.saved_username;probes=@($probes)} | ConvertTo-Json -Depth 8
    return
  }
  $bootstrap = ReadEndpoint '/api/im/bootstrap'
  $summary = [ordered]@{ checkedAt = [DateTimeOffset]::Now.ToString('o'); origin = $origin; account = [string]$secret.saved_username; bootstrapStatus = $bootstrap.Status; bootstrapRequestId = $bootstrap.RequestId }
  if ($ListTestDirects) {
    $summary.conversations = @($bootstrap.Data.conversations | Where-Object {
      $_.type -eq 'direct' -and
      $_.title -match '^Test Terminal (?:0[1-9]|10)、Test Terminal (?:0[1-9]|10)$'
    } | Select-Object id,title,type,lastMessageSequence,lastReadSequence,unreadCount)
    $summary | ConvertTo-Json -Depth 4
    return
  }
  $events = ReadEndpoint '/api/im/sync/events?afterSequence=0&waitSeconds=0&take=500'
  $summary.sync = [ordered]@{ status = $events.Status; allow = $events.Allow; requestId = $events.RequestId; fields = @($events.Data.PSObject.Properties.Name); latestSequence = $events.Data.latestSequence; eventCount = @($events.Data.events).Count; events = @($events.Data.events | ForEach-Object {
    $event = $_
    $payload = $null
    try { $payload = [string]$event.payloadJson | ConvertFrom-Json } catch { }
    [ordered]@{ id=$event.id; sequence=$event.sequence; type=$event.type; createdAt=$event.createdAt; conversationId=$payload.conversationId; fields=@($event.PSObject.Properties.Name); payloadFields=@($payload.PSObject.Properties.Name); messageId=$(if ($event.type -eq 'message.created') { $payload.id }); messageSequence=$(if ($event.type -eq 'message.created') { $payload.sequence }); readerId=$(if ($event.type -eq 'conversation.read') { $payload.ReaderId }); readSequence=$(if ($event.type -eq 'conversation.read') { $payload.Sequence }) }
  }) }
  if ($bootstrap.Status -eq 200) {
    $summary.currentUser = $bootstrap.Data.currentMember.userName
    $conversations = @($bootstrap.Data.conversations | Where-Object { $_.title -eq $GroupTitle -or $_.id -eq 'a164a0c0-4cad-44b0-9ece-e095371b2f91' -or ($ConversationId -and $_.id -eq $ConversationId) })
    $summary.conversations = @($conversations | ForEach-Object {
      $conversation = $_
      $messages = ReadEndpoint ('/api/im/conversations/' + $conversation.id + '/messages?take=50')
      $items = @($messages.Data | Where-Object { $null -ne $_ })
      [ordered]@{
        id = $conversation.id; title = $conversation.title; type = $conversation.type
        unreadCount = $conversation.unreadCount; lastMessageSequence = $conversation.lastMessageSequence
        lastReadSequence = $conversation.lastReadSequence; unreadMentionSequences = $conversation.unreadMentionSequences
        messagesStatus = $messages.Status; requestId = $messages.RequestId; allow = $messages.Allow; contentType = $messages.ContentType
        responseType = if ($null -eq $messages.Data) { 'null' } else { $messages.Data.GetType().Name }
        messageCount = $items.Count
        messages = @($items | ForEach-Object {
          $item = $_
          $textValue = [string]$item.content
          if (-not $textValue) { $textValue = [string]$item.text }
          [ordered]@{
            id = $item.id; clientMessageId = $item.clientMessageId; sequence = $item.sequence
            type = $item.type; senderId = $item.senderId; createdAt = $item.createdAt
            testText = if ($textValue -match 'AI-UAT-' -and $textValue -notmatch 'https?://') { $textValue } else { '[omitted]' }
            mentionCount = @($item.mentions).Count
            mentionFields = @($item.mentions | ForEach-Object { @($_.PSObject.Properties.Name) -join ',' })
            fields = @($item.PSObject.Properties.Name)
          }
        })
      }
    })
  }
  $summary | ConvertTo-Json -Depth 9
} catch {
  # Exception messages can include URLs or request headers. Emit type only.
  Write-Output ('Read-only test inspection failed: ' + $_.Exception.GetType().Name)
  exit 1
} finally {
  if ($client) { $client.Dispose() }
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
