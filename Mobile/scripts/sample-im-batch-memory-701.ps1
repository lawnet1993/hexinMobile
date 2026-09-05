# Read-only Android process summary. Raw dumps and application payloads are never saved.
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-batch-catchup-20260903'))
$journal=Get-Content -Raw (Join-Path $root 'native-send-run.json') | ConvertFrom-Json
$mobilePid=((& $adb -s emulator-5558 shell pidof com.hexing.zhilian.hexing_terminal_mobile) -join '').Trim()
if($LASTEXITCODE -ne 0 -or $mobilePid -notmatch '^\d+$') { throw 'Expected one sender process.' }
$raw=(& $adb -s emulator-5558 shell dumpsys meminfo $mobilePid) -join "`n"
if($LASTEXITCODE -ne 0) { throw 'Process memory summary unavailable.' }
function Number([string]$Pattern) {
  $match=[regex]::Match($raw,$Pattern)
  if(-not $match.Success) { throw 'Expected Android memory counter unavailable.' }
  return [long]$match.Groups[1].Value
}
$sample=[ordered]@{
  at=[DateTimeOffset]::Now.ToString('o');serial='emulator-5558';pid=[int]$mobilePid
  nativeSendClicks=@($journal.events | Where-Object stage -eq clicked).Count
  runStage=$journal.events[-1].stage
  totalPssKiB=(Number 'TOTAL PSS:\s*(\d+)');totalRssKiB=(Number 'TOTAL RSS:\s*(\d+)')
  totalSwapPssKiB=(Number 'TOTAL SWAP PSS:\s*(\d+)')
  nativeHeapPssKiB=(Number 'Native Heap:\s*(\d+)');javaHeapPssKiB=(Number 'Java Heap:\s*(\d+)')
  privateOtherPssKiB=(Number 'Private Other:\s*(\d+)');systemPssKiB=(Number 'System:\s*(\d+)')
}
$raw=$null
$sample | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $root 'm4-batch-memory.jsonl')
$sample | ConvertTo-Json -Compress
