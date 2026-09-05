param(
  [Parameter(Mandatory)][ValidateSet('emulator-5556','emulator-5558')][string]$Serial,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name
)
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$directory=Join-Path $PSScriptRoot '..\test\evidence\im-row-decode-20260903'
$output=Join-Path $directory ($Name+'.json')
if(Test-Path -LiteralPath $output){throw 'Evidence exists; use a new name'}
$processId=((& $adb -s $Serial shell pidof com.hexing.zhilian.hexing_terminal_mobile)-join '').Trim()
if($processId -notmatch '^\d+$'){throw 'App process not running'}
# Raw device logging never leaves memory. Only these three numeric fields may be saved.
$raw=@(& $adb -s $Serial logcat -d -v threadtime --pid=$processId)
if($LASTEXITCODE -ne 0){throw 'Log read failed'}
$events=@();$rejected=0
foreach($line in $raw){
  $match=[regex]::Match($line,'\bMOBILE_IM_ROW_DECODE\s+(\{.*\})\s*$')
  if(-not $match.Success){continue}
  try{
    $entry=$match.Groups[1].Value | ConvertFrom-Json
    if(@($entry.PSObject.Properties).Count -ne 3 -or
       $entry.rows -isnot [long] -or $entry.cacheHits -isnot [long] -or
       $entry.durationMicros -isnot [long] -or $entry.rows -lt 0 -or
       $entry.cacheHits -lt 0 -or $entry.cacheHits -gt $entry.rows -or
       $entry.durationMicros -lt 0){throw 'Unknown fields'}
    $events += [ordered]@{rows=$entry.rows;cacheHits=$entry.cacheHits;durationMicros=$entry.durationMicros}
  }catch{$rejected++}
}
$raw=$null
[ordered]@{checkedAt=[DateTimeOffset]::Now.ToString('o');serial=$Serial;pid=$processId;rejected=$rejected;events=$events} |
  ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $output
[ordered]@{serial=$Serial;pid=$processId;rejected=$rejected;sampleCount=$events.Count;last=($events | Select-Object -Last 1)} | ConvertTo-Json -Depth 3
