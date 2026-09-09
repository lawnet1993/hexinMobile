param(
  [ValidateSet('dd00d66d','emulator-5556','emulator-5558','emulator-5560')][string]$Serial = 'emulator-5558',
  [ValidateSet('test01','test03','test04','test05')][string]$Username = 'test04',
  [switch]$ReplaceSavedFields
)

# Authorized test01-test10 share the supplied test password. Read the installed
# desktop's DPAPI-protected saved credential in memory, never write a plaintext
# config. Only an explicitly allowlisted UAT device login screen can be
# operated; never logs out an account.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$appDir = 'C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian'
$config = Get-Content -LiteralPath (Join-Path $appDir 'managed_access.yaml') -Raw
if ($config -notmatch '(?m)^collaboration-oa-api-url:\s*["'']?https?://api\.sfhkh\.com(?:/|["'']?\s*$)') {
  throw 'The current desktop is not using the authorized test origin.'
}
$plain = $null
$secret = $null
$previousUsername = $env:MOBILE_UAT_USERNAME
$previousPassword = $env:MOBILE_UAT_PASSWORD
try {
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $appDir 'managed_access_session.bin')),
    $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
  if ([string]$secret.saved_username -notmatch '^test(0[1-9]|10)$' -or
      [string]::IsNullOrEmpty([string]$secret.saved_password)) {
    throw 'No saved authorized numbered test credential is available.'
  }
  $env:MOBILE_UAT_USERNAME = $Username
  $env:MOBILE_UAT_PASSWORD = [string]$secret.saved_password
  $arguments = @((Join-Path $PSScriptRoot '..\tool\mobile_ui_login_env.mjs'), '--serial', $Serial)
  if ($ReplaceSavedFields) { $arguments += '--replace-saved-fields' }
  & node @arguments
  if ($LASTEXITCODE -ne 0) { throw 'Independent test-device UI login not confirmed.' }
} finally {
  $env:MOBILE_UAT_USERNAME = $previousUsername
  $env:MOBILE_UAT_PASSWORD = $previousPassword
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $secret = $null
  $config = $null
}
