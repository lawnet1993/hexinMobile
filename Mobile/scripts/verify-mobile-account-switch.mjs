import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Read-only verification of the 2026-09-03 native M3/M4 session-switch run.
// Inputs are sanitized SQLite metadata, finite auth diagnostics and UI evidence.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/mobile-account-switch-20260903')
const read = name => JSON.parse(fs.readFileSync(path.join(root, `${name}.json`), 'utf8').replace(/^\uFEFF/, ''))
const ui = name => fs.readFileSync(path.join(root, `${name}.xml`), 'utf8')
const a3 = 'c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc'
const a4 = 'b6a2d272-aaca-4845-bbf8-294288c940a9'
const message = '63992535-b438-4e0a-81f4-928c27a22a32'
const clientMessage = '50d6d450-615b-4192-a833-2cde32e7eeef'
const checks = []
const check = (name, passed) => checks.push({ name, passed: Boolean(passed) })
const equal = (left, right) => JSON.stringify(left) === JSON.stringify(right)
const projection = (snapshot, account) => {
  const rows = snapshot.groupProjections.filter(row => row.account_id === account)
  if (rows.length !== 1) throw new Error('Expected exactly one account-scoped conversation projection')
  return rows[0]
}
const at = (snapshot, account, last, readSequence, unread) => {
  const row = projection(snapshot, account)
  return row.last_message_sequence === last && row.last_read_sequence === readSequence && row.unread_count === unread
}
const b3 = read('m3-im-before')
const b4 = read('m4-im-before')
const c3 = read('m3-cold-im')
const c4 = read('m4-cold-im')
const terminated = read('m3-terminated-events').events
const exits = terminated.filter(event => event.kind === 'AUTH' && event.status === 409 && event.action === 'terminated' && event.source === 'heartbeat')
check('one_observed_heartbeat_409_termination', exits.length === 1)
check('late_refresh_200_rejected_after_termination', exits.length === 1 && terminated.some(event => event.kind === 'REFRESH' && event.status === 200 && event.action === 'stale_result' && Number(event.epochSeconds) > Number(exits[0].epochSeconds)))
check('replaced_login_notice_persisted', read('m3-still-terminated-ui').sessionReplacedNotice)
// The initial inspect-only schema had no passwordFieldEmpty property. Use the
// actual captured password node instead of treating an absent field as false.
const passwordNodes = [...ui('m3-after-replacement-attempt').matchAll(/<node\b[^>]*>/g)].map(([tag]) =>
  Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(match => [match[1], match[2]])))
  .filter(node => node.class === 'android.widget.EditText' && node.password === 'true')
check('replaced_login_password_empty', passwordNodes.length === 1 && passwordNodes[0].text === '')
for (const name of ['m3-stopped-before-new-message', 'm3-stopped-after-new-message', 'm3-stopped-later']) {
  const stopped = read(name)
  check(`${name}_cursor_and_messages_unchanged`, equal(stopped.eventCursors, b3.eventCursors) && at(stopped, a3, 5, 5, 0) && stopped.messageLedger.every(row => row.id !== message))
}
const restored = read('m4-restored-before-read')
check('m4_account03_read_did_not_clear_account04_unread', at(restored, a3, 6, 6, 0) && at(restored, a4, 6, 5, 1))
check('m3_restored_own_message_no_unread', at(read('m3-restored-im'), a3, 6, 6, 0))
check('m4_visible_read_persisted', at(read('m4-after-visible-read'), a4, 6, 6, 0))
for (const [label, snapshot, account] of [['m3', c3, a3], ['m4_account04', c4, a4], ['m4_account03', c4, a3]]) {
  const rows = snapshot.messageLedger.filter(row => row.account_id === account)
  check(`${label}_six_unique_messages`, rows.length === 6 && new Set(rows.map(row => row.id)).size === 6 && new Set(rows.map(row => row.client_message_id)).size === 6 && equal(rows.map(row => row.sequence).sort((a, b) => a - b), [1, 2, 3, 4, 5, 6]))
  const own = rows.filter(row => row.id === message || row.client_message_id === clientMessage)
  check(`${label}_same_server_and_client_identity`, own.length === 1 && own[0].id === message && own[0].client_message_id === clientMessage && own[0].sender_id === a3 && own[0].local_status === 'sent')
  check(`${label}_read_survives_cold_start`, at(snapshot, account, 6, 6, 0))
}
const queueIdentity = snapshot => snapshot.outbox.map(({ client_message_id, conversation_id, kind, created_at }) => ({ client_message_id, conversation_id, kind, created_at })).sort((a, b) => a.client_message_id.localeCompare(b.client_message_id))
check('m3_two_pending_media_preserved_not_copied_to_m4', b3.outbox.length === 2 && equal(queueIdentity(b3), queueIdentity(c3)) && c4.outbox.length === 0)
for (const [label, before, after, account] of [['m3', b3, c3, a3], ['m4', b4, c4, a4]]) {
  check(`${label}_all_original_conversations_retained`, before.conversationMetadata.filter(row => row.account_id === account).every(old => after.conversationMetadata.some(row => row.account_id === account && row.id === old.id && row.type === old.type)))
  const oaBefore = read(`${label}-oa-before`)
  const oaAfter = read(`${label}-cold-oa`)
  check(`${label}_oa_drafts_unchanged`, equal(oaBefore.drafts, oaAfter.drafts))
  check(`${label}_oa_read_receipts_unchanged`, equal(oaBefore.readReceipts, oaAfter.readReceipts))
  check(`${label}_oa_outbox_unchanged`, equal(oaBefore.outbox, oaAfter.outbox))
}
const m4As03 = ui('m4-test03-list')
const m4As04 = ui('m4-restored-list')
check('native_lists_show_account_specific_conversations', m4As03.includes('财顺') && !m4As03.includes('Test Terminal 05') && !m4As03.includes('合盈') && m4As04.includes('合盈') && m4As04.includes('Test Terminal 05') && !m4As04.includes('财顺') && !m4As04.includes('Test Terminal 01'))
check('cold_start_original_accounts_visible', ui('m3-cold-home').includes('Test Terminal 03') && ui('m4-cold-home').includes('Test Terminal 04'))
const desktop = read('desktop-final')
check('desktop_test01_readonly_session_healthy', desktop.running && desktop.account === 'test01' && desktop.imStatus === 200 && desktop.oaStatus === 200)
console.log(JSON.stringify({ checkedAt: new Date().toISOString(), scope: 'native-session-switch-evidence-not-full-product-acceptance', passed: checks.filter(check => check.passed).length, total: checks.length, checks }, null, 2))
if (checks.some(check => !check.passed)) process.exitCode = 1
