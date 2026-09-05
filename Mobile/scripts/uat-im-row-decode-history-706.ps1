$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-row-decode-20260903'))
$output=Join-Path $evidence 'native-history.json'
if(Test-Path -LiteralPath $output){throw 'History already observed; do not replay automatically'}
$observations=@()
for($section=0;$section -le 12;$section++){
  if($section -gt 0){
    1..4 | ForEach-Object { & $adb -s emulator-5556 shell input swipe 540 500 540 2050 450; Start-Sleep -Milliseconds 450 }
  }
  $name='m3-history-'+$section.ToString('00')
  & (Join-Path $PSScriptRoot 'capture-device-uat.ps1') -Serial emulator-5556 -EvidenceDirectory $evidence -Name $name | Out-Null
  [xml]$ui=Get-Content (Join-Path $evidence ($name+'.xml')) -Raw
  $labels=@($ui.SelectNodes('//node') | ForEach-Object {$_.'content-desc'})
  if(-not($labels | Where-Object {$_ -match '^AI-UAT-20260903-IM-BATCH-701\s'})){throw 'Unexpected conversation'}
  $numbers=@($labels | ForEach-Object {if($_ -match '(?m)^AI-UAT-701-BATCH-(\d{4})\b'){[int]$Matches[1]}} | Sort-Object -Unique)
  if($numbers.Count -eq 0){throw 'No test markers visible'}
  $observations += [ordered]@{at=[DateTimeOffset]::Now.ToString('o');section=$section;gestures=($section*4);first=$numbers[0];last=$numbers[-1];screenshot=$name+'.png'}
  $observations | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $output
  if($numbers[0] -eq 1){
    & (Join-Path $PSScriptRoot 'inspect-im-row-decode-706.ps1') -Serial emulator-5556 -Name m3-expanded-decode
    exit 0
  }
}
throw 'First message was not reached'
