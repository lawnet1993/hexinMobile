param(
  [Parameter(Mandatory)]
  [ValidateSet('emulator-5554', 'emulator-5556', 'emulator-5558', 'emulator-5560')]
  [string]$Serial,

  [Parameter(Mandatory)]
  [ValidateSet(
    'Test Terminal 01',
    'Test Terminal 04',
    'Test Terminal 05',
    'AI-UAT-20260903-IM-BATCH-701',
    'AI-UAT-MULTIVM-20260906-1100'
  )]
  [string]$ExpectedHeader,

  [Parameter(Mandatory)]
  [ValidatePattern('^AI-UAT-[A-Z0-9-]+-$')]
  [string]$Prefix,

  [ValidateRange(1, 30)]
  [int]$Count = 20,

  [ValidateRange(50, 2000)]
  [int]$DelayMilliseconds = 100,

  [ValidateRange(0, 2000)]
  [int]$InputSettleMilliseconds = 0,

  [Parameter(Mandatory)]
  [string]$JournalPath
)

# Bounded Android UI load worker. It can only operate four named test
# emulators, known AI-UAT conversations and AI-UAT-prefixed text. It never
# reads credentials, calls the IM API directly or writes application storage.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package = 'com.hexing.zhilian.hexing_terminal_mobile'

function Invoke-Android([string[]]$Arguments) {
  $output = @(& $adb -s $Serial @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "Android operation failed for $Serial."
  }
  return $output
}

function Read-Ui {
  # Capturing exec-out as PowerShell text corrupts UTF-8 under parallel
  # Windows jobs. Pull the raw XML bytes first so Chinese semantics and XML
  # quoting remain intact.
  $remote = "/sdcard/sa-load-$($Serial.Replace(':', '-')).xml"
  $localRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $local = [IO.Path]::GetFullPath((Join-Path $localRoot "sa-load-$($Serial.Replace(':', '-'))-$PID.xml"))
  if (-not $local.StartsWith($localRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary UI path escaped the system temporary directory.'
  }
  Invoke-Android @('shell', 'uiautomator', 'dump', $remote) | Out-Null
  Invoke-Android @('pull', $remote, $local) | Out-Null
  try {
    $raw = [IO.File]::ReadAllText($local, [Text.Encoding]::UTF8)
    return [xml]$raw
  } finally {
    if (Test-Path -LiteralPath $local) { [IO.File]::Delete($local) }
  }
}

function Get-Point($Node) {
  if ($null -eq $Node) { throw "Required control unavailable for $Serial." }
  $bounds = @([regex]::Matches([string]$Node.bounds, '\d+') | ForEach-Object { [int]$_.Value })
  if ($bounds.Count -ne 4) { throw "Invalid control bounds for $Serial." }
  return @(
    [int](($bounds[0] + $bounds[2]) / 2),
    [int](($bounds[1] + $bounds[3]) / 2)
  )
}

function Tap($Node) {
  $point = Get-Point $Node
  Invoke-Android @('shell', 'input', 'tap', "$($point[0])", "$($point[1])") | Out-Null
}

$journal = [IO.Path]::GetFullPath($JournalPath)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
if (-not $journal.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Journal must stay inside Mobile/test/evidence.'
}
if (Test-Path -LiteralPath $journal) {
  throw 'Journal already exists; inspect it instead of replaying a burst.'
}
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $journal)

$ui = Read-Ui
if (-not $ui.SelectSingleNode("//node[@package='$package']")) {
  throw "The mobile app is not foreground on $Serial."
}
$header = @($ui.SelectNodes('//node[@content-desc!=""]') | Where-Object {
  ([string]$_.'content-desc').Contains($ExpectedHeader)
})
if ($header.Count -eq 0) {
  throw "The expected test conversation is not open on $Serial."
}
$editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
if ($null -eq $editor -or [string]$editor.text) {
  throw "The composer is unavailable or non-empty on $Serial."
}

Tap $editor
Start-Sleep -Milliseconds 300
$ui = Read-Ui
$editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
if ($null -eq $editor -or [string]$editor.text) {
  throw "The focused composer is unavailable or non-empty on $Serial."
}
$sendPoint = Get-Point ($ui.SelectSingleNode('//node[@content-desc="发送"]'))

$events = [Collections.Generic.List[object]]::new()
$startedAt = [DateTimeOffset]::UtcNow
for ($index = 1; $index -le $Count; $index++) {
  $marker = $Prefix + ('{0:D3}' -f $index)
  Invoke-Android @('shell', 'input', 'text', $marker) | Out-Null
  if ($InputSettleMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $InputSettleMilliseconds
  }
  Invoke-Android @('shell', 'input', 'tap', "$($sendPoint[0])", "$($sendPoint[1])") | Out-Null
  $events.Add([ordered]@{
    index = $index
    tappedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  })
  Start-Sleep -Milliseconds $DelayMilliseconds
}

Start-Sleep -Milliseconds 800
$ui = Read-Ui
$lastMarker = $Prefix + ('{0:D3}' -f $Count)
$lastVisible = @($ui.SelectNodes('//node[@content-desc!=""]') | Where-Object {
  ([string]$_.'content-desc').Contains($lastMarker)
}).Count -gt 0
$editor = $ui.SelectSingleNode('//node[@class="android.widget.EditText"]')
$composerEmpty = $null -ne $editor -and -not [string]$editor.text

$result = [ordered]@{
  serial = $Serial
  expectedHeader = $ExpectedHeader
  prefix = $Prefix
  requested = $Count
  inputSettleMilliseconds = $InputSettleMilliseconds
  startedAtUtc = $startedAt.ToString('o')
  completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  lastMarkerVisible = $lastVisible
  composerEmpty = $composerEmpty
  events = $events.ToArray()
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal -Encoding UTF8
if (-not $lastVisible -or -not $composerEmpty) {
  throw "Burst completion could not be confirmed on $Serial; do not replay it automatically."
}
$result | ConvertTo-Json -Depth 5
