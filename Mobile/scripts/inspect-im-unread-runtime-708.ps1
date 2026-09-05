param([ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceFolder='im-unread-navigation-20260903')
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\test\evidence') $EvidenceFolder))
$output=Join-Path $evidence 'runtime.json'
if(Test-Path -LiteralPath $output){throw 'Runtime snapshot exists.'}
$records=@()
foreach($serial in @('emulator-5556','emulator-5558')){
  $processId=((& $adb -s $serial shell pidof com.hexing.zhilian.hexing_terminal_mobile)-join '').Trim()
  if($processId -notmatch '^\d+$'){throw 'App process missing.'}
  $packagePath=((& $adb -s $serial shell pm path com.hexing.zhilian.hexing_terminal_mobile)-join '').Trim()
  if($packagePath -notmatch '^package:(/data/app/[^\r\n]+/base\.apk)$'){throw 'Unexpected package path.'}
  $hash=((& $adb -s $serial shell sha256sum $Matches[1])-join '').Split(' ')[0].ToUpperInvariant()
  # Never persist raw device logs; collect explicit numeric diagnostics only.
  $raw=@(& $adb -s $serial logcat -d -v threadtime --pid=$processId)
  if($LASTEXITCODE -ne 0){throw 'Device log unavailable.'}
  $decode=@()
  foreach($line in $raw){
    if($line -match '\bMOBILE_IM_ROW_DECODE\s+(\{.*\})\s*$'){
      try{
        $entry=$Matches[1]|ConvertFrom-Json
        if(@($entry.PSObject.Properties).Count -eq 3 -and $entry.rows -is [long] -and
           $entry.cacheHits -is [long] -and $entry.durationMicros -is [long] -and
           $entry.rows -ge 0 -and $entry.cacheHits -ge 0 -and $entry.cacheHits -le $entry.rows -and $entry.durationMicros -ge 0){
          $decode+=@{rows=$entry.rows;cacheHits=$entry.cacheHits;durationMicros=$entry.durationMicros}
        }
      }catch{}
    }
  }
  $records += [ordered]@{at=[DateTimeOffset]::Now.ToString('o');serial=$serial;pid=$processId;sha256=$hash;
    fatalCount=@($raw|Where-Object{$_ -match 'FATAL EXCEPTION'}).Count;
    unhandledCount=@($raw|Where-Object{$_ -match 'Unhandled Exception'}).Count;
    overflowCount=@($raw|Where-Object{$_ -match 'RenderFlex overflowed'}).Count;decodedWindows=$decode;
    wifiOn=((& $adb -s $serial shell settings get global wifi_on)-join '').Trim();
    mobileDataOn=((& $adb -s $serial shell settings get global mobile_data)-join '').Trim()}
  $raw=$null
}
$records|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $output
$records|ForEach-Object{[pscustomobject]$_}|Select-Object serial,pid,sha256,fatalCount,unhandledCount,overflowCount|ConvertTo-Json
