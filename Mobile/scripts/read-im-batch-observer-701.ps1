param([ValidatePattern('^[a-z0-9-]+$')][string]$Name='batch-observations')
# Read only the explicit acceptance observer's numeric/boolean records.
$ErrorActionPreference='Stop'
$adb='C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$package='com.hexing.zhilian.hexing_terminal_mobile'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence\im-batch-catchup-20260903'))
$output=Join-Path $root "$Name.json"
if(Test-Path -LiteralPath $output) { throw 'Existing evidence must not be overwritten.' }
$listing=@(& $adb -s emulator-5556 exec-out run-as $package ls cache 2>$null)
if($LASTEXITCODE -ne 0) { throw 'Observer cache unavailable.' }
$files=@($listing | Where-Object {$_ -match '^ai-uat-im-batch-\d+\.jsonl$'})
if($files.Count -ne 1) { throw 'Expected exactly one observer log; inspect process/run history.' }
$raw=(& $adb -s emulator-5556 exec-out run-as $package cat "cache/$($files[0])" 2>$null) -join "`n"
if($LASTEXITCODE -ne 0) { throw 'Observer log unavailable.' }
$numbers=@('batch','elapsedMs','eventCount','firstEventSequence','lastEventSequence','appliedCursor',
  'ackedCursor','batchTestMessages','persistedCount','uniqueServerIds','uniqueClientIds',
  'markerCount','lastMarker','lastMessage','lastRead','unread')
$booleans=@('batchMessagesPersisted','markersOrderedFromOne')
$records=@(foreach($line in ($raw -split "`n" | Where-Object {$_})) {
  try {$value=$line | ConvertFrom-Json -DateKind String} catch {throw 'Incomplete observer record; retry observation with a new filename.'}
  if($value.stage -ne 'committed_before_ack' -or $value.at -notmatch '^\d{4}-\d\d-\d\dT[0-9:.]+Z$') {
    throw 'Unexpected observer record.'
  }
  $record=[ordered]@{stage='committed_before_ack';at=$value.at}
  foreach($key in $numbers) {
    if($value.$key -isnot [long] -and $value.$key -isnot [int]) {throw 'Missing numeric observer field.'}
    if($value.$key -lt 0) {throw 'Negative observer counter.'}
    $record[$key]=$value.$key
  }
  foreach($key in $booleans) {
    if($value.$key -isnot [bool]) {throw 'Missing boolean observer field.'}
    $record[$key]=$value.$key
  }
  [pscustomobject]$record
})
$raw=$null
if($records.Count -lt 1 -or $records.Count -gt 20) {throw 'Observer record count out of bounds.'}
ConvertTo-Json -InputObject $records -Depth 4 | Set-Content -LiteralPath $output
@{records=$records.Count;eventCounts=@($records.eventCount);persisted=$records[-1].persistedCount;
  lastMarker=$records[-1].lastMarker;path=$output} | ConvertTo-Json -Compress
