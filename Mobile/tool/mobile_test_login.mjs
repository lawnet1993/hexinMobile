import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const toolDir = path.dirname(fileURLToPath(import.meta.url))
const mobileRoot = path.resolve(toolDir, '..')
const defaultConfigPath = path.resolve(
  mobileRoot,
  '..',
  'Desktop',
  'Windows',
  'scripts',
  'admin-test-env.local',
)
const configPath =
  process.env.MOBILE_TEST_CONFIG ||
  process.env.ADMIN_TEST_CONFIG ||
  defaultConfigPath
const serialIndex = process.argv.indexOf('--serial')
const serial = serialIndex >= 0 ? process.argv[serialIndex + 1] : ''
const usernameIndex = process.argv.indexOf('--username')
const usernameOverride =
  usernameIndex >= 0 ? String(process.argv[usernameIndex + 1] || '').trim() : ''
const packageName = 'com.hexing.zhilian.hexing_terminal_mobile'
const activityName = `${packageName}/.MainActivity`
const adb =
  process.env.ANDROID_ADB ||
  path.join(
    process.env.LOCALAPPDATA || os.homedir(),
    'Android',
    'Sdk',
    'platform-tools',
    process.platform === 'win32' ? 'adb.exe' : 'adb',
  )

if (!serial || !/^[A-Za-z0-9._:-]+$/.test(serial)) {
  throw new Error('请通过 --serial 指定目标 Android 设备')
}
if (!fs.existsSync(configPath)) {
  throw new Error('未找到本地测试配置，请设置 MOBILE_TEST_CONFIG')
}

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'))
const username = usernameOverride || String(config.terminal_username || '').trim()
const password = String(config.terminal_password || '')
if (!username || !password) {
  throw new Error('本地测试配置缺少 terminal_username 或 terminal_password')
}
function runAdb(args, { capture = false } = {}) {
  const result = spawnSync(adb, ['-s', serial, ...args], {
    encoding: 'utf8',
    windowsHide: true,
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'ignore', 'pipe'],
  })
  if (result.status !== 0) {
    throw new Error('ADB 操作失败，请确认目标设备仍在线')
  }
  return capture ? String(result.stdout || '') : ''
}

function sleep(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds)
}

function attributes(tag) {
  const result = {}
  for (const match of tag.matchAll(/([\w-]+)="([^"]*)"/g)) {
    result[match[1]] = match[2]
  }
  return result
}

function nodes(xml) {
  return [...xml.matchAll(/<node\b[^>]*>/g)].map((match) => attributes(match[0]))
}

function center(bounds) {
  const match = bounds?.match(/^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/)
  if (!match) throw new Error('登录页控件位置不可用')
  return {
    x: Math.round((Number(match[1]) + Number(match[3])) / 2),
    y: Math.round((Number(match[2]) + Number(match[4])) / 2),
  }
}

function tap(node) {
  const point = center(node.bounds)
  runAdb(['shell', 'input', 'tap', String(point.x), String(point.y)])
}

function clearFocusedField() {
  runAdb(['shell', 'input', 'keyevent', '123'])
  runAdb(['shell', 'input', 'keyevent', ...Array(96).fill('67')])
}

const directKeyCodes = {
  '0': 7,
  '1': 8,
  '2': 9,
  '3': 10,
  '4': 11,
  '5': 12,
  '6': 13,
  '7': 14,
  '8': 15,
  '9': 16,
  ',': 55,
  '.': 56,
  ' ': 62,
  '`': 68,
  '-': 69,
  '=': 70,
  '[': 71,
  ']': 72,
  '\\': 73,
  ';': 74,
  "'": 75,
  '/': 76,
  '@': 77,
  '+': 81,
}
const shiftedCharacters = {
  '!': '1',
  '"': "'",
  '#': '3',
  '$': '4',
  '%': '5',
  '^': '6',
  '&': '7',
  '*': '8',
  '(': '9',
  ')': '0',
  '_': '-',
  '{': '[',
  '}': ']',
  '|': '\\',
  ':': ';',
  '<': ',',
  '>': '.',
  '?': '/',
  '~': '`',
}

function keyCode(character) {
  if (/^[a-z]$/.test(character)) {
    return { code: 29 + character.charCodeAt(0) - 'a'.charCodeAt(0) }
  }
  if (/^[A-Z]$/.test(character)) {
    return {
      code: 29 + character.charCodeAt(0) - 'A'.charCodeAt(0),
      shift: true,
    }
  }
  if (Object.hasOwn(directKeyCodes, character)) {
    return { code: directKeyCodes[character] }
  }
  const unshifted = shiftedCharacters[character]
  if (unshifted && Object.hasOwn(directKeyCodes, unshifted)) {
    return { code: directKeyCodes[unshifted], shift: true }
  }
  return null
}

function typeFocusedField(value) {
  const strokes = [...value].map(keyCode)
  if (strokes.some((stroke) => stroke == null)) {
    throw new Error('测试凭据包含当前安全键码输入不支持的字符')
  }
  for (const stroke of strokes) {
    runAdb(
      stroke.shift
        ? ['shell', 'input', 'keycombination', '59', String(stroke.code)]
        : ['shell', 'input', 'keyevent', String(stroke.code)],
    )
  }
}

function dumpUi() {
  runAdb(['shell', 'uiautomator', 'dump', '/sdcard/codex-mobile-login.xml'])
  return runAdb(
    ['exec-out', 'cat', '/sdcard/codex-mobile-login.xml'],
    { capture: true },
  )
}

runAdb(['shell', 'am', 'start', '-n', activityName])
sleep(1200)
let xml = dumpUi()
if (xml.includes('第 1 个标签，共 5 个')) {
  console.log(`设备登录态已就绪：${serial}`)
  process.exit(0)
}

let visibleNodes = nodes(xml)
const fields = visibleNodes.filter((node) => node.class === 'android.widget.EditText')
if (fields.length < 2) throw new Error('未识别到移动端账号和密码输入框')

tap(fields[0])
clearFocusedField()
typeFocusedField(username)
runAdb(['shell', 'input', 'keyevent', '61'])
clearFocusedField()
typeFocusedField(password)
runAdb(['shell', 'input', 'keyevent', '4'])
sleep(500)

xml = dumpUi()
visibleNodes = nodes(xml)
const remember = visibleNodes.find(
  (node) => node.class === 'android.widget.CheckBox',
)
if (remember && remember.checked !== 'true') tap(remember)
const loginButton = visibleNodes.find(
  (node) =>
    node.class === 'android.widget.Button' && node['content-desc'] === '登录',
)
if (!loginButton) throw new Error('未识别到移动端登录按钮')
tap(loginButton)
sleep(6500)

xml = dumpUi()
if (!xml.includes('第 1 个标签，共 5 个')) {
  throw new Error('移动端登录未成功，请在目标设备检查页面提示')
}
console.log(`设备已连接测试环境：${serial}`)
