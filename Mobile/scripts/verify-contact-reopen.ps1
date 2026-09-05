param(
  [ValidateRange(1, 30)][int]$Iterations = 20,
  [Parameter(Mandatory)][string]$EvidenceDirectory,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$RunName
)

# UI-only M3 check. Begin on the expanded directory containing the existing
# test01 contact. Never log credentials, inspect other devices, or send messages.
# Durations include adb/uiautomator and MUST NOT be reported as Flutter latency.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package = 'com.hexing.zhilian.hexing_terminal_mobile'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
$target = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Evidence directory must be under Mobile/test/evidence.'
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
$summaryPath = Join-Path $target ($RunName + '.json')
if (Test-Path -LiteralPath $summaryPath) { throw 'Choose a new run name.' }

function Invoke-TestAdb([string[]]$CommandArgs) {
  $result = @(& $adb -s emulator-5556 @CommandArgs 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'Android diagnostic command failed.' }
  return $result
}

function Read-TestUi([string]$Label) {
  $path = Join-Path $target ($RunName + '-' + $Label + '.xml')
  if (Test-Path -LiteralPath $path) { throw 'UI evidence must not be overwritten.' }
  $remote = '/sdcard/hexing-uat-' + [Guid]::NewGuid().ToString('N') + '.xml'
  $dump = Invoke-TestAdb @('shell', 'uiautomator', 'dump', $remote)
  if (($dump -join '') -notmatch 'UI hierchary dumped to:') { throw 'Fresh UI unavailable.' }
  Invoke-TestAdb @('pull', $remote, $path) | Out-Null
  [xml]$ui = Get-Content -LiteralPath $path -Raw
  if ($null -eq $ui.hierarchy) { throw 'Invalid UI hierarchy.' }
  return $ui
}

function Read-Memory {
  $lines = (Invoke-TestAdb @('shell', 'dumpsys', 'meminfo', $package)) -join "`n"
  $pss = [regex]::Match($lines, 'TOTAL PSS:\s+(\d+)')
  $swap = [regex]::Match($lines, 'TOTAL SWAP PSS:\s+(\d+)')
  if (-not $pss.Success) { throw 'Memory sample unavailable.' }
  return [ordered]@{pssKb=[int]$pss.Groups[1].Value;swapPssKb=if($swap.Success){[int]$swap.Groups[1].Value}else{$null}}
}

$initialPid = (Invoke-TestAdb @('shell', 'pidof', $package)) -join ''
$memory = @([ordered]@{afterCycles=0;sample=(Read-Memory)})
$cycles = @()
$ui = Read-TestUi 'start'
try {
  for ($i = 1; $i -le $Iterations; $i++) {
    $avatar = $ui.SelectSingleNode('//node[contains(@content-desc,"联系Test Terminal 01")]')
    $directory = $ui.SelectSingleNode('//node[@content-desc="通讯录"]')
    if ($null -eq $avatar -or $null -eq $directory) { throw 'Expected directory/contact is not visible; no input sent.' }
    $bounds = [regex]::Match($avatar.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $bounds.Success) { throw 'Contact bounds unavailable.' }
    $x = [int](([int]$bounds.Groups[1].Value + [int]$bounds.Groups[3].Value)/2)
    $y = [int](([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value)/2)
    Invoke-TestAdb @('shell', 'input', 'tap', "$x", "$y") | Out-Null
    $chat = Read-TestUi ("{0:D2}-chat" -f $i)
    if ($null -eq $chat.SelectSingleNode('//node[@content-desc="聊天"]') -or
        $null -eq $chat.SelectSingleNode('//node[contains(@content-desc,"Test Terminal 01")]')) {
      throw 'Expected direct chat did not open.'
    }
    Invoke-TestAdb @('shell', 'input', 'keyevent', '4') | Out-Null
    $ui = Read-TestUi ("{0:D2}-back" -f $i)
    $returned = $null -ne $ui.SelectSingleNode('//node[@content-desc="通讯录"]')
    if (-not $returned) { throw 'One back did not return to contacts.' }
    $cycles += [ordered]@{iteration=$i;chatVerified=$true;singleBackReturned=$true}
    if ($i % 5 -eq 0) {
      $memory += [ordered]@{afterCycles=$i;sample=(Read-Memory)}
      Write-Output "Verified $i contact/chat/back cycles."
    }
  }
} finally {
  $endPid = (Invoke-TestAdb @('shell', 'pidof', $package)) -join ''
  [ordered]@{
    checkedAt=[DateTimeOffset]::Now.ToString('o');serial='emulator-5556';
    requested=$Iterations;completed=$cycles.Count;cycles=$cycles;memory=$memory;
    sameProcess=($initialPid -eq $endPid);pid=$endPid;
    timingScope='No frame or input-latency claim; each cycle verified by fresh UI hierarchy.'
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath
}
