import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const configPath = process.env.ADMIN_TEST_CONFIG
if (!configPath) throw new Error('ADMIN_TEST_CONFIG is required')
const config = JSON.parse(readFileSync(configPath, 'utf8'))
const baseUrl = String(config.base_url || '').replace(/\/$/, '')
const deviceId = '8f98ea30-17ab-4fab-b3e0-8b9ba48013a7'
const fingerprint = createHash('sha256')
  .update(`mobile-contract|${deviceId}`)
  .digest('hex')

const login = await request('/api/client/login', {
  method: 'POST',
  body: {
    username: config.terminal_username,
    password: config.terminal_password,
    deviceId,
    deviceName: 'Codex 移动端契约测试',
    fingerprint,
    operatingSystem: 'Android test',
    clientVersion: '1.0.1',
    region: '',
  },
})
const token = login.body.accessToken
const collaboration = login.body.collaboration || {}
if (!token || !collaboration.imApiUrl || !collaboration.oaApiUrl) {
  throw new Error('login response does not include collaboration endpoints')
}

const headers = {
  Authorization: `Bearer ${token}`,
  'X-Device-Id': login.body.device?.id || deviceId,
  'X-Terminal-Device-Id': login.body.device?.id || deviceId,
  'X-Terminal-Account-Id': login.body.device?.userId || '',
}
const probes = [
  ['im-bootstrap', collaboration.imApiUrl, '/api/im/bootstrap'],
  ['oa-bootstrap', collaboration.oaApiUrl, '/api/oa/bootstrap'],
  ['oa-app-catalog', collaboration.oaApiUrl, '/api/oa/app-catalog'],
  ['oa-notifications', collaboration.oaApiUrl, '/api/oa/notifications?take=20&unreadOnly=false'],
  ['oa-approval-page', collaboration.oaApiUrl, '/api/oa/approval-requests/page?take=20&view=all'],
]

const results = []
for (const [name, origin, pathname] of probes) {
  const started = performance.now()
  const response = await fetch(`${collaborationOrigin(origin, pathname)}${pathname}`, { headers })
  const body = await response.json().catch(() => null)
  results.push({
    name,
    status: response.status,
    ok: response.ok,
    durationMs: Math.round((performance.now() - started) * 10) / 10,
    shape: shapeOf(body),
  })
}

function collaborationOrigin(rawUrl, pathname) {
  const url = new URL(String(rawUrl))
  const servicePrefix = pathname.startsWith('/api/im') ? '/api/im' : '/api/oa'
  const normalizedPath = url.pathname.replace(/\/$/, '')
  if (normalizedPath.endsWith(servicePrefix)) {
    url.pathname = normalizedPath.slice(0, -servicePrefix.length) || '/'
  }
  url.search = ''
  url.hash = ''
  return url.toString().replace(/\/$/, '')
}

const report = {
  checkedAt: new Date().toISOString(),
  loginStatus: login.status,
  collaborationConfigured: true,
  results,
}
const output = path.resolve(process.argv[2] || '.cache/mobile-contract-check.json')
mkdirSync(path.dirname(output), { recursive: true })
writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`)
console.log(JSON.stringify(report, null, 2))
if (results.some((item) => !item.ok)) process.exit(2)

async function request(pathname, { method, body }) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${pathname} returned ${response.status}`)
  return { status: response.status, body: data }
}

function shapeOf(value) {
  if (Array.isArray(value)) return { type: 'array', length: value.length }
  if (value && typeof value === 'object') {
    return { type: 'object', keys: Object.keys(value).sort() }
  }
  return { type: typeof value }
}
