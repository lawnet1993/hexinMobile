param(
  [Parameter(Mandatory=$true)][ValidateRange(2,81)][int]$First,
  [Parameter(Mandatory=$true)][ValidateRange(2,81)][int]$Last
)
# Bounded real Android UI fixture for this exact two-person AI-UAT test group.
# No HTTP sending, database editing, credentials, or other conversation targets.
$ErrorActionPreference = 'Stop'
if ($Last -lt $First -or $Last - $First -gt 11) { throw 'Use batches of at most 12 messages.' }
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$serial = 'emulator-5554'
function ReadTestUi {
  $activity = (& $adb -s $serial shell dumpsys activity activities) -join "`n"
  if ($activity -notmatch 'topResumedActivity=[^\r\n]*com.hexing.zhilian.hexing_terminal_mobile/') {
    throw 'Test application is not foreground.'
  }
  & $adb -s $serial shell uiautomator dump /sdcard/sa-cache-uat.xml >$null
  [xml]$ui = (& $adb -s $serial shell cat /sdcard/sa-cache-uat.xml) -join "`n"
  $group = @($ui.SelectNodes('//node') | Where-Object {$_.'content-desc' -match '^AI-UAT-20260902-162326-GROUP\r?\n2 位成员'})
  if ($group.Count -ne 1) { throw 'Expected AI-UAT two-person group is not open.' }
  return $ui
}
function TapNode($Node) {
  $coords = [regex]::Matches([string]$Node.bounds, '\d+') | ForEach-Object {[int]$_.Value}
  if ($coords.Count -ne 4) { throw 'Invalid control bounds.' }
  & $adb -s $serial shell input tap ([int](($coords[0]+$coords[2])/2)) ([int](($coords[1]+$coords[3])/2))
}
for ($index=$First; $index -le $Last; $index++) {
  $ui = ReadTestUi
  $editors = @($ui.SelectNodes('//node[@class="android.widget.EditText"]'))
  $send = @($ui.SelectNodes('//node[@content-desc="发送"]'))
  if ($editors.Count -ne 1 -or $editors[0].text -ne '' -or $send.Count -ne 1 -or $send[0].enabled -ne 'true') {
    throw 'Composer is not empty and ready; stopping without modifying it.'
  }
  TapNode $editors[0]
  $marker = 'AI-UAT-20260902-172000-CACHE-{0:D3}' -f $index
  & $adb -s $serial shell input text $marker
  TapNode $send[0]
  Start-Sleep -Milliseconds 300
  Write-Output ('UI sent marker ' + $index)
}
$ui = ReadTestUi
$lastMarker = 'AI-UAT-20260902-172000-CACHE-{0:D3}' -f $Last
if (-not ($ui.SelectNodes('//node') | Where-Object {$_.'content-desc'.Contains($lastMarker)})) {
  throw 'Final marker is not visible; do not repeat this batch automatically.'
}
