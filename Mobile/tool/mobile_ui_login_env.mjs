import process from 'node:process'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

// Test-device UI login only. No API login, credential file, screenshot, or XML file.
const serial = process.argv[process.argv.indexOf('--serial') + 1]
const username = process.env.MOBILE_UAT_USERNAME || ''
const password = process.env.MOBILE_UAT_PASSWORD || ''
const inspectOnly = process.argv.includes('--inspect-only')
const replaceSavedFields = process.argv.includes('--replace-saved-fields')
delete process.env.MOBILE_UAT_PASSWORD
delete process.env.MOBILE_UAT_USERNAME
if (!['dd00d66d', 'emulator-5556', 'emulator-5558', 'emulator-5560'].includes(serial)) {
  throw new Error('Only allowlisted UAT devices are supported.')
}
if (!inspectOnly && (!/^test(01|03|04|05)$/.test(username) || !password)) {
  throw new Error('Supply the authorized independent test account via environment.')
}
const adb = path.join(process.env.LOCALAPPDATA, 'Android', 'Sdk', 'platform-tools', 'adb.exe')
function run(args) {
  const result = spawnSync(adb, ['-s', serial, ...args], {
    encoding: 'utf8', windowsHide: true, timeout: 15000,
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  if (result.status !== 0) throw new Error('Android UI operation failed.')
  return result.stdout || ''
}
function pause(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms) }
function readUi() { return run(['exec-out', 'uiautomator', 'dump', '/dev/tty']) }
function nodes(xml) {
  return [...xml.matchAll(/<node\b[^>]*>/g)].map(([tag]) =>
    Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]])))
}
function tap(node) {
  const bounds = node?.bounds?.match(/^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/)
  if (!bounds) throw new Error('Required login control unavailable.')
  run(['shell', 'input', 'tap',
    String(Math.round((+bounds[1] + +bounds[3]) / 2)),
    String(Math.round((+bounds[2] + +bounds[4]) / 2))])
}
function strokes(value) {
  const punctuation = { '@': 77, '\\': 73, '.': 56, '-': 69, '/': 76, '=': 70, '+': 81 }
  const shifted = { '!': 8, '#': 10, '$': 11, '%': 12, '^': 13, '&': 14, '*': 15, '(': 16, ')': 7, '_': 69 }
  return [...value].map(ch => {
    if (/^[a-z]$/i.test(ch)) return { key: ch.toLowerCase().charCodeAt(0) - 97 + 29, shift: ch !== ch.toLowerCase() }
    if (/^\d$/.test(ch)) return { key: +ch + 7 }
    if (Object.hasOwn(punctuation, ch)) return { key: punctuation[ch] }
    if (Object.hasOwn(shifted, ch)) return { key: shifted[ch], shift: true }
    throw new Error('Credential character not supported by this UI helper.')
  })
}
function type(value) {
  for (const stroke of value) run(stroke.shift
    ? ['shell', 'input', 'keycombination', '59', String(stroke.key)]
    : ['shell', 'input', 'keyevent', String(stroke.key)])
}

const initial = nodes(readUi())
if (inspectOnly) {
  const inputFields = initial.filter(node => node.class === 'android.widget.EditText')
  const descriptions = initial.filter(node => node.class !== 'android.widget.EditText')
    .map(node => `${node.text || ''} ${node['content-desc'] || ''}`).join('\n')
  console.log(JSON.stringify({
    checkedAt: new Date().toISOString(),
    serial,
    loggedIn: descriptions.includes('第 1 个标签，共 5 个'),
    loginScreen: initial.some(node => node.class === 'android.widget.Button' && node['content-desc'] === '登录'),
    inputFieldCount: inputFields.length,
    fieldsEmpty: inputFields.every(node => !node.text?.trim()),
    passwordFieldEmpty: inputFields.length === 2 && !inputFields[1].text?.trim(),
    usernameIsTest03: inputFields[0]?.text === 'test03',
    usernameIsTest01: inputFields[0]?.text === 'test01',
    usernameIsTest04: inputFields[0]?.text === 'test04',
    usernameIsTest05: inputFields[0]?.text === 'test05',
    sessionReplacedNotice: descriptions.includes('当前移动端已在另一台设备登录，请重新登录'),
    sessionExpiredNotice: descriptions.includes('登录已失效或已到期，请重新登录'),
  }))
  process.exit(0)
}
const usernameStrokes = strokes(username)
const passwordStrokes = strokes(password)
if (initial.some(node => node['content-desc']?.includes('第 1 个标签，共 5 个'))) {
  throw new Error('Already logged in; inspect account instead of replacing it.')
}
const fields = initial.filter(node => node.class === 'android.widget.EditText')
const login = initial.find(node => node.class === 'android.widget.Button' && node['content-desc'] === '登录')
if (fields.length !== 2 || !login || (!replaceSavedFields && fields.some(node => node.text?.trim()))) {
  throw new Error('Expected an empty fresh-install login screen.')
}
// Keep credential UI only in memory; never save or print a filled login form.
function clearFocusedField(node) {
  if (!replaceSavedFields) return
  const length = node.text?.length || 0
  if (length > 256) throw new Error('Unexpected login field length.')
  // Injected Ctrl+A is not consistently handled by Android/Flutter.
  run(['shell', 'input', 'keyevent', '123'])
  run(['shell', 'input', 'keyevent', ...Array(length + 2).fill('67')])
}
tap(fields[0]); clearFocusedField(fields[0]); type(usernameStrokes)
run(['shell', 'input', 'keyevent', '4']); pause(350)
const usernameReady = nodes(readUi()).filter(node => node.class === 'android.widget.EditText')
if (usernameReady[0]?.text !== username) {
  throw new Error('Username input verification failed; no login submitted.')
}
tap(usernameReady[1]); clearFocusedField(usernameReady[1]); type(passwordStrokes)
run(['shell', 'input', 'keyevent', '4']); pause(350)
const ready = nodes(readUi())
if (ready.filter(node => node.class === 'android.widget.EditText')[0]?.text !== username) {
  throw new Error('Username changed before submit; no login submitted.')
}
const submittedAt = new Date().toISOString()
tap(ready.find(node => node.class === 'android.widget.Button' && node['content-desc'] === '登录'))
pause(6500)
const result = readUi()
if (!result.includes('第 1 个标签，共 5 个')) {
  // Emit only a finite classification, never an arbitrary server/UI message.
  const failureKind = /绑定|换绑/.test(result) ? 'device_binding'
    : /账号或密码错误/.test(result) ? 'credentials_rejected'
    : /当前账号已停用或无终端权限/.test(result) ? 'account_permission'
    : /网络|超时/.test(result) ? 'network_or_timeout' : 'unclassified'
  console.log(JSON.stringify({ serial, account: username, submittedAt, checkedAt: new Date().toISOString(), uiLoginConfirmed: false, failureKind, credentialsLogged: false }))
  process.exitCode = 2
} else {
  console.log(JSON.stringify({ serial, account: username, submittedAt, checkedAt: new Date().toISOString(), uiLoginConfirmed: true, credentialsLogged: false }))
}
