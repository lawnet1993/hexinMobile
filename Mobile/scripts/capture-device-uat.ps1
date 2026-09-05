param(
  [Parameter(Mandatory)][string]$Serial,
  [Parameter(Mandatory)][string]$EvidenceDirectory,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Name
)

# UI-only evidence. Each dump uses a fresh device path: a failed dump must not
# accidentally recycle the previous screen. Do not run on credential forms.
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidenceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\test\evidence'))
$target = [IO.Path]::GetFullPath($EvidenceDirectory)
if (-not $target.StartsWith($evidenceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Evidence directory must be a child of Mobile/test/evidence.'
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
$xmlPath = Join-Path $target ($Name + '.xml')
$pngPath = Join-Path $target ($Name + '.png')
$metadataPath = Join-Path $target ($Name + '.json')
if ((Test-Path -LiteralPath $xmlPath) -or (Test-Path -LiteralPath $pngPath) -or
    (Test-Path -LiteralPath $metadataPath)) {
  throw 'Evidence already exists; choose a new capture name.'
}
$remote = '/sdcard/hexing-uat-' + [Guid]::NewGuid().ToString('N')
$dump = @(& $adb -s $Serial shell uiautomator dump ($remote + '.xml') 2>&1)
if ($LASTEXITCODE -ne 0 -or ($dump -join "`n") -notmatch 'UI hierchary dumped to:') {
  throw 'UI hierarchy unavailable; no existing device dump was reused.'
}
& $adb -s $Serial pull ($remote + '.xml') $xmlPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'UI hierarchy download failed.' }
[xml]$ui = Get-Content -LiteralPath $xmlPath -Raw
if ($null -eq $ui.hierarchy) { throw 'Invalid UI hierarchy.' }
& $adb -s $Serial shell screencap -p ($remote + '.png') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Screenshot capture failed.' }
& $adb -s $Serial pull ($remote + '.png') $pngPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Screenshot download failed.' }
[ordered]@{
  capturedAt = [DateTimeOffset]::Now.ToString('o')
  serial = $Serial
  xml = $Name + '.xml'
  screenshot = $Name + '.png'
} | ConvertTo-Json | Set-Content -LiteralPath $metadataPath
$ui.SelectNodes('//node') | Where-Object { $_.text -or $_.'content-desc' } |
  ForEach-Object { '{0} {1} {2}' -f $_.text, $_.'content-desc', $_.bounds }
