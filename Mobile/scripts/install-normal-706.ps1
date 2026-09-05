param(
  [ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceFolder='im-row-decode-20260903',
  [ValidatePattern('^[a-z0-9-]+\.apk$')][string]$ArtifactName='normal-706.apk',
  [ValidatePattern('^[a-z0-9-]+\.json$')][string]$RecordName='install.json'
)
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$evidence=Join-Path (Join-Path $root 'test\evidence') $EvidenceFolder
$output=Join-Path $evidence $RecordName
if(Test-Path -LiteralPath $output){throw 'Install already observed; do not replay automatically'}
$apk=Join-Path $evidence $ArtifactName
if(Test-Path -LiteralPath $apk){throw 'APK artifact exists'}
Copy-Item -LiteralPath (Join-Path $root 'build\app\outputs\flutter-apk\app-profile.apk') -Destination $apk
$expected=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
$records=@()
foreach($serial in @('emulator-5556','emulator-5558')){
  & $adb -s $serial install -r $apk | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Install failed'}
  & $adb -s $serial shell am start -W -n com.hexing.zhilian.hexing_terminal_mobile/.MainActivity | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Launch failed'}
  $packagePath=((& $adb -s $serial shell pm path com.hexing.zhilian.hexing_terminal_mobile)-join '').Trim()
  if($packagePath -notmatch '^package:(/data/app/[^\r\n]+/base\.apk)$'){throw 'Unexpected installed path'}
  $actualHash=((& $adb -s $serial shell sha256sum $Matches[1])-join '').Split(' ')[0].ToUpperInvariant()
  if($actualHash -ne $expected){throw 'Installed APK does not match'}
  $processId=((& $adb -s $serial shell pidof com.hexing.zhilian.hexing_terminal_mobile)-join '').Trim()
  if($processId -notmatch '^\d+$'){throw 'No app PID'}
  $records += [ordered]@{at=[DateTimeOffset]::Now.ToString('o');serial=$serial;pid=$processId;sha256=$actualHash;normalApkMatches=$true}
  $records | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $output
}
$records | ConvertTo-Json -Depth 3
